import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../app_controller.dart';
import '../sync_core.dart';
import '../task_dates.dart';
import 'agenda_task.dart';
import 'task_editor.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.controller,
    this.initialDate, this.initialUnscheduled = false, this.onDateSelected});
  final AppController controller;
  final DateTime? initialDate;
  final bool initialUnscheduled;
  final ValueChanged<DateTime?>? onDateSelected;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScrollBehavior extends MaterialScrollBehavior {
  const _CalendarScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices, PointerDeviceKind.mouse,
  };

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month;
  late DateTime _selected;
  bool _unscheduled = false;
  final _vertical = ScrollController();
  final _viewportKey = GlobalKey();
  String? _dragId;
  Offset? _dragPoint;
  Timer? _dragScroll;

  @override
  void initState() {
    super.initState();
    final now = widget.initialDate ?? DateTime.now();
    _selected = DateTime(now.year, now.month, now.day);
    _month = DateTime(now.year, now.month);
    _unscheduled = widget.initialUnscheduled;
  }

  @override
  void dispose() {
    _dragScroll?.cancel();
    _vertical.dispose();
    super.dispose();
  }

  void _select(DateTime day) {
    setState(() {
      _selected = DateTime(day.year, day.month, day.day);
      _month = DateTime(day.year, day.month);
      _unscheduled = false;
    });
    widget.onDateSelected?.call(day);
  }

  void _moveMonth(int offset) {
    final next = DateTime(_month.year, _month.month + offset);
    final lastDay = DateTime(next.year, next.month + 1, 0).day;
    _select(DateTime(next.year, next.month, math.min(_selected.day, lastDay)));
    if (_vertical.hasClients) _vertical.jumpTo(0);
  }

  bool _canSchedule(String id) => !widget.controller.editing &&
      widget.controller.tasks.any((task) => task.id == id && !task.deleted && task.dueDate == null) &&
      !widget.controller.conflicts.any((conflict) => conflict.taskId == id);

  Future<void> _schedule(String id, DateTime day) async {
    final saved = await widget.controller.scheduleTask(id, dateKey(day));
    if (!mounted) return;
    if (saved) _select(day);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(saved
      ? '已安排到 ${day.month}月${day.day}日'
      : widget.controller.error ?? '当前正在保存，请稍后重试')));
  }

  void _startDrag(String id) {
    setState(() => _dragId = id);
    _dragScroll?.cancel();
    _dragScroll = Timer.periodic(const Duration(milliseconds: 50), (_) => _scrollDuringDrag());
  }

  void _endDrag() {
    _dragScroll?.cancel();
    _dragScroll = null;
    _dragPoint = null;
    if (mounted && _dragId != null) setState(() => _dragId = null);
  }

  void _scrollDuringDrag() {
    final point = _dragPoint;
    final box = _viewportKey.currentContext?.findRenderObject();
    if (point == null || box is! RenderBox || !box.hasSize) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    // The fixed tray sits outside the viewport; scrolling starts only after the
    // pointer enters the calendar, and continues near its visible top/bottom.
    if (!rect.inflate(6).contains(point)) return;
    double speed(double position, double low, double high) {
      if (position < low + 36) return -10;
      if (position > high - 36) return 10;
      return 0;
    }
    void move(ScrollController controller, double delta) {
      if (delta == 0 || !controller.hasClients || controller.positions.length != 1) return;
      final position = controller.position;
      controller.jumpTo((position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent));
    }
    move(_vertical, speed(point.dy, rect.top, rect.bottom));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 760) {
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _viewport(SingleChildScrollView(controller: _vertical,
            child: _calendar(constraints.maxHeight)))),
          const SizedBox(width: 20),
          SizedBox(width: 280, child: Column(children: [
            SizedBox(height: math.min(240.0, constraints.maxHeight * 0.45), child: _unscheduledTray(false)),
            const SizedBox(height: 16),
            Expanded(child: ListView(children: _agenda())),
          ])),
        ]);
      }
      final trayHeight = math.min(math.min(136.0, constraints.maxHeight * 0.65),
        math.max(112.0, constraints.maxHeight * 0.36));
      return Column(children: [
        Expanded(child: _viewport(ListView(
          controller: _vertical, padding: const EdgeInsets.only(bottom: 16),
          children: [_calendar(constraints.maxHeight - trayHeight - 8), const SizedBox(height: 16), ..._agenda()],
        ))),
        const SizedBox(height: 8),
        SizedBox(height: trayHeight, child: _unscheduledTray(true)),
      ]);
    }),
  );

  Widget _viewport(Widget child) => SizedBox(key: _viewportKey,
    child: ScrollConfiguration(behavior: const _CalendarScrollBehavior(),
      child: Scrollbar(key: const ValueKey('calendar-scrollbar'), controller: _vertical,
        thumbVisibility: true, interactive: true,
        child: Padding(key: const ValueKey('calendar-viewport'),
          padding: const EdgeInsets.only(right: 10), child: child))));

  Widget _calendar(double availableHeight) {
    final colors = Theme.of(context).colorScheme;
    final first = DateTime(_month.year, _month.month);
    final start = DateTime(first.year, first.month, 1 - (first.weekday - 1));
    final last = DateTime(_month.year, _month.month + 1, 0);
    final weeks = ((first.weekday - 1 + last.day) / 7).ceil();
    final scaler = MediaQuery.textScalerOf(context);
    final taskHeight = math.max(25.0, scaler.scale(11) * 1.5 + 8);
    final headerHeight = math.max(18.0, scaler.scale(12) * 1.5);
    final detailsHeight = math.max(20.0, scaler.scale(10) * 1.5 + 4);
    final chromeHeight = 148 + scaler.scale(11) + scaler.scale(14);
    final cellHeight = ((availableHeight - chromeHeight - (weeks - 1) * 4) / weeks)
      .clamp(48.0, 132.0).toDouble();
    return Column(children: [
      Row(children: [
        IconButton(tooltip: '上个月', onPressed: () => _moveMonth(-1), icon: const Icon(Icons.chevron_left_rounded)),
        Expanded(child: Text('${_month.year}年${_month.month}月', textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700))),
        IconButton(tooltip: '下个月', onPressed: () => _moveMonth(1), icon: const Icon(Icons.chevron_right_rounded)),
        TextButton(onPressed: () => _select(DateTime.now()), child: const Text('今天')),
      ]),
      const SizedBox(height: 10),
      Column(children: [
          Row(children: [for (final label in ['一', '二', '三', '四', '五', '六', '日'])
            Expanded(child: Center(child: Text(label, style: TextStyle(color: colors.onSurfaceVariant))))]),
          const SizedBox(height: 8),
          for (var week = 0; week < weeks; week++) ...[
            _week(start, week, cellHeight, headerHeight, taskHeight, detailsHeight),
            if (week < weeks - 1) const SizedBox(height: 4),
          ],
      ]),
      const SizedBox(height: 10),
      Text('待办全部展开 · 按住空白拖动或滚动查看',
        textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
      const SizedBox(height: 6),
      Align(alignment: Alignment.centerLeft, child: FilterChip(
        label: Text('未安排 · ${tasksOnDate(widget.controller.tasks, null).length}'),
        selected: _unscheduled,
        onSelected: (selected) {
          setState(() => _unscheduled = selected);
          widget.onDateSelected?.call(selected ? null : _selected);
        },
      )),
    ]);
  }

  Widget _week(DateTime start, int week, double baseHeight, double headerHeight,
      double taskHeight, double detailsHeight) {
    final days = List.generate(7, (index) => DateTime(start.year, start.month, start.day + week * 7 + index));
    final mostTasks = days.map((day) => tasksOnDate(widget.controller.tasks, dateKey(day)).length)
      .reduce(math.max);
    // Grow the entire week to the busiest day. No task is hidden behind a
    // preview cap; the existing outer scroll view keeps every week reachable.
    final contentHeight = 8 + headerHeight + 4 + mostTasks * (taskHeight + 3)
      + (mostTasks > 0 ? detailsHeight + 4 : 0);
    return SizedBox(height: math.max(baseHeight, contentHeight), child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (var index = 0; index < days.length; index++) ...[
        Expanded(child: _day(days[index], taskHeight, detailsHeight)),
        if (index < days.length - 1) const SizedBox(width: 4),
      ]],
    ));
  }

  Widget _day(DateTime day, double taskHeight, double detailsHeight) {
    final colors = Theme.of(context).colorScheme;
    final key = dateKey(day);
    final tasks = tasksOnDate(widget.controller.tasks, key);
    // Completion leaves each task in the same place with its strike-through.
    tasks.sort((a, b) {
      final priority = b.priority.compareTo(a.priority);
      if (priority != 0) return priority;
      final title = a.title.compareTo(b.title);
      return title != 0 ? title : a.id.compareTo(b.id);
    });
    final remaining = tasks.where((task) => !task.completed).length;
    final selected = !_unscheduled && key == dateKey(_selected);
    final currentMonth = day.month == _month.month;
    final today = key == dateKey(DateTime.now());
    return DragTarget<String>(
      key: ValueKey('drop-$key'),
      onWillAcceptWithDetails: (details) => _canSchedule(details.data),
      onAcceptWithDetails: (details) => unawaited(_schedule(details.data, day)),
      builder: (context, candidates, rejected) {
        final hovered = candidates.isNotEmpty;
        return Semantics(
          label: '$key，${tasks.length}项待办，$remaining项未完成', selected: selected,
          child: Material(
            color: hovered ? colors.secondaryContainer : selected ? colors.primaryContainer : colors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(
              width: hovered ? 2 : 1,
              color: hovered ? colors.primary : today ? colors.primary : colors.outlineVariant.withValues(alpha: 0.5))),
            child: InkWell(key: ValueKey('day-$key'), borderRadius: BorderRadius.circular(12), onTap: () => _select(day),
              child: LayoutBuilder(builder: (context, constraints) => Padding(padding: const EdgeInsets.all(4), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Text('${day.day}', style: TextStyle(fontSize: 12,
                    fontWeight: selected || today ? FontWeight.w700 : FontWeight.w400,
                    color: currentMonth ? colors.onSurface : colors.onSurfaceVariant)),
                  const Spacer(),
                  if (tasks.isNotEmpty && constraints.maxWidth >= 64) Text('$remaining/${tasks.length}', style: TextStyle(fontSize: 9, color: colors.primary)),
                ]),
                const SizedBox(height: 4),
                for (final task in tasks) _calendarTask(task, taskHeight),
                if (tasks.isNotEmpty)
                  InkWell(key: ValueKey('more-$key'), onTap: () => _showDay(day),
                    child: SizedBox(height: detailsHeight, child: Align(alignment: Alignment.centerLeft,
                      child: Text('详情', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: colors.primary))))),
                if (hovered && tasks.isEmpty) Expanded(child: Center(child: Icon(Icons.add_task_rounded, color: colors.primary))),
              ]))),
            ),
          ),
        );
      },
    );
  }

  Widget _calendarTask(Task task, double height) {
    final colors = Theme.of(context).colorScheme;
    final conflict = widget.controller.conflicts.any((item) => item.taskId == task.id);
    return Tooltip(message: task.title, child: InkWell(
      key: ValueKey('calendar-complete-${task.id}'),
      borderRadius: BorderRadius.circular(5),
      onTap: widget.controller.editing || conflict ? null : () => widget.controller.setCompleted(task.id, !task.completed),
      child: Container(height: height, margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(color: colors.surfaceContainerHigh.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(5)),
        child: Row(children: [
          Icon(conflict ? Icons.compare_arrows_rounded : task.completed ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 10, color: conflict ? colors.error : colors.primary),
          const SizedBox(width: 2),
          Expanded(child: Text(task.title, key: ValueKey('calendar-title-${task.id}'), maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, decoration: task.completed ? TextDecoration.lineThrough : null,
              color: task.completed ? colors.onSurfaceVariant : colors.onSurface))),
        ])),
    ));
  }

  Future<void> _showDay(DateTime day) async {
    _select(day);
    await showModalBottomSheet<void>(context: context, showDragHandle: true, isScrollControlled: true,
      builder: (context) => FractionallySizedBox(heightFactor: 0.75, child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
          Text('${day.month}月${day.day}日的待办', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          for (final task in tasksOnDate(widget.controller.tasks, dateKey(day))) AgendaTask(task: task, controller: widget.controller),
        ]),
      )));
  }

  Widget _unscheduledTray(bool compact) {
    final colors = Theme.of(context).colorScheme;
    final tasks = tasksOnDate(widget.controller.tasks, null);
    return Container(key: const ValueKey('unscheduled-tray'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: colors.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('未安排 · ${tasks.length}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        Text([TargetPlatform.android, TargetPlatform.iOS].contains(Theme.of(context).platform)
          ? '长按卡片拖到日期，可在边缘停留滚动' : '拖动卡片到日期，可在边缘停留滚动',
          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant)),
        const SizedBox(height: 8),
        Expanded(child: tasks.isEmpty ? Center(child: Text('没有未安排待办', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)))
          : ListView.separated(scrollDirection: compact ? Axis.horizontal : Axis.vertical,
            itemCount: tasks.length, separatorBuilder: (_, index) => const SizedBox(width: 8, height: 6),
            itemBuilder: (context, index) => SizedBox(width: compact ? 186 : null, child: _dragTask(tasks[index])),
          )),
      ]),
    );
  }

  Widget _dragTask(Task task) {
    final colors = Theme.of(context).colorScheme;
    final allowed = _canSchedule(task.id);
    final tile = Material(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(10),
      child: InkWell(borderRadius: BorderRadius.circular(10),
        onTap: widget.controller.editing ? null : () => showTaskEditor(context, widget.controller, task: task),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10), child: Row(children: [
          Icon(allowed ? Icons.drag_indicator_rounded : Icons.lock_outline_rounded, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(child: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12,
            decoration: task.completed ? TextDecoration.lineThrough : null, color: colors.onSurface))),
        ])),
      ));
    final feedback = Transform.translate(offset: const Offset(14, 14), child: Material(
      elevation: 8, color: colors.primaryContainer, borderRadius: BorderRadius.circular(12),
      child: SizedBox(width: 190, child: Padding(padding: const EdgeInsets.all(12),
        child: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.onPrimaryContainer, fontSize: 13))))));
    final placeholder = Opacity(opacity: 0.35, child: tile);
    final mouse = [TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.macOS].contains(Theme.of(context).platform);
    if (mouse) {
      return Draggable<String>(key: ValueKey('drag-${task.id}'), data: task.id, maxSimultaneousDrags: allowed ? 1 : 0,
        dragAnchorStrategy: pointerDragAnchorStrategy, feedback: feedback, childWhenDragging: placeholder,
        onDragStarted: () => _startDrag(task.id), onDragUpdate: (details) => _dragPoint = details.globalPosition,
        onDragEnd: (_) => _endDrag(), child: tile);
    }
    return LongPressDraggable<String>(key: ValueKey('drag-${task.id}'), data: task.id, maxSimultaneousDrags: allowed ? 1 : 0,
      delay: const Duration(milliseconds: 300), dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: feedback, childWhenDragging: placeholder,
      onDragStarted: () => _startDrag(task.id), onDragUpdate: (details) => _dragPoint = details.globalPosition,
      onDragEnd: (_) => _endDrag(), child: tile);
  }

  List<Widget> _agenda() {
    final tasks = tasksOnDate(widget.controller.tasks, _unscheduled ? null : dateKey(_selected));
    return [
      Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(
        _unscheduled ? '未安排日期' : '${_selected.month}月${_selected.day}日的待办',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
      if (tasks.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('没有待办，可以为这一天新建一条。')),
      for (final task in tasks) AgendaTask(task: task, controller: widget.controller),
    ];
  }
}
