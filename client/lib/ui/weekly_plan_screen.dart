import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../sync_core.dart';
import '../task_dates.dart';
import '../weekly_plan.dart';
import 'task_editor.dart';

class WeeklyPlanScreen extends StatefulWidget {
  const WeeklyPlanScreen({
    super.key,
    required this.controller,
    required this.onEdit,
    this.clock,
  });
  final AppController controller;
  final ValueChanged<Task> onEdit;
  final DateTime Function()? clock;
  @override
  State<WeeklyPlanScreen> createState() => _WeeklyPlanScreenState();
}

class _WeeklyPlanScreenState extends State<WeeklyPlanScreen> {
  final _title = TextEditingController();
  Timer? _timer;
  late String _lastDay;
  DateTime get _now => (widget.clock ?? DateTime.now)();
  List<DateTime> get _days => weekDates(_now);
  static const _labels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  @override
  void initState() {
    super.initState();
    _lastDay = dateKey(_now);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _lastDay != dateKey(_now)) {
        setState(() => _lastDay = dateKey(_now));
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _title.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final title = _title.text.trim();
    if (title.isEmpty || widget.controller.editing) return;
    final ok = await widget.controller.saveTask(
      TaskDraft(title: title, listName: weeklyListName),
    );
    if (mounted && ok && _title.text.trim() == title) _title.clear();
  }

  Future<void> _assign(Task task, String day) async {
    if (!_days.any((date) => dateKey(date) == day)) return;
    await widget.controller.setTaskPlacement(
      task.id,
      dueDate: day,
      requireIncomplete: true,
    );
  }

  Future<void> _pickDay(Task task) async {
    final days = _days;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('安排到本周'),
        children: [
          for (final day in days)
            SimpleDialogOption(
              key: ValueKey('weekly-pick-${dateKey(day)}'),
              onPressed: () => Navigator.pop(context, dateKey(day)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Text(
                  '${_labels[day.weekday - 1]}  ${day.month}/${day.day}${dateKey(day) == dateKey(_now) ? ' · 今天' : ''}',
                ),
              ),
            ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    await _assign(task, result);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final days = _days;
      final tasks = widget.controller.tasks;
      final pool = weeklyPool(tasks);
      final colors = Theme.of(context).colorScheme;
      return ListView(
        key: const ValueKey('weekly-scroll'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Row(
            children: [
              const Icon(Icons.view_week_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '本周 · ${days.first.month}/${days.first.day} – ${days.last.month}/${days.last.day}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '长按拖动，或点日期按钮安排到本周。未安排的待办会延续。',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '待分配 · ${pool.length}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: '完整新建周待办',
                        onPressed: widget.controller.editing
                            ? null
                            : () => showTaskEditor(
                                context,
                                widget.controller,
                                listName: weeklyListName,
                              ),
                        icon: const Icon(Icons.add_circle_outline_rounded),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('weekly-quick-add'),
                          controller: _title,
                          decoration: const InputDecoration(
                            hintText: '这周想完成什么？',
                            border: InputBorder.none,
                          ),
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _add(),
                        ),
                      ),
                      IconButton(
                        tooltip: '添加周待办',
                        onPressed: widget.controller.editing ? null : _add,
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                  if (pool.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '先记下来，再安排到一天。',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ),
                  for (final task in pool) _card(task),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1200
                  ? 7
                  : constraints.maxWidth >= 700
                  ? 3
                  : constraints.maxWidth >= 480
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 10) / columns;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final day in days)
                    SizedBox(
                      width: width,
                      child: _day(day, weeklyDayTasks(tasks, day)),
                    ),
                ],
              );
            },
          ),
        ],
      );
    },
  );

  Widget _day(DateTime day, List<Task> tasks) {
    final colors = Theme.of(context).colorScheme;
    final today = dateKey(day) == dateKey(_now);
    return DragTarget<Task>(
      key: ValueKey('weekly-day-${dateKey(day)}'),
      onWillAcceptWithDetails: (details) =>
          !details.data.completed && !widget.controller.editing,
      onAcceptWithDetails: (details) => _assign(details.data, dateKey(day)),
      builder: (context, candidates, rejected) => Material(
        color: candidates.isNotEmpty
            ? colors.primaryContainer
            : colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: today ? colors.primary : colors.outlineVariant,
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 138),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${_labels[day.weekday - 1]} · ${day.month}/${day.day}${today ? ' · 今天' : ''}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: today ? colors.primary : colors.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                if (tasks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      '拖到这里',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                for (final task in tasks) _card(task),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(Task task) {
    final colors = Theme.of(context).colorScheme;
    Widget content({bool feedback = false}) => Card(
      key: feedback ? null : ValueKey('weekly-task-${task.id}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: feedback ? null : () => widget.onEdit(task),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: Checkbox(
                      value: task.completed,
                      activeColor: task.priority == 2
                          ? colors.error
                          : task.priority == 1
                          ? const Color(0xffb08025)
                          : colors.primary,
                      onChanged: feedback || widget.controller.editing
                          ? null
                          : (value) =>
                                widget.controller.setCompleted(task.id, value!),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6, right: 6),
                      child: Text(
                        task.title,
                        style: TextStyle(
                          fontSize: 14,
                          decoration: task.completed
                              ? TextDecoration.lineThrough
                              : null,
                          color: task.completed
                              ? colors.onSurfaceVariant
                              : colors.onSurface,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (!feedback)
                Row(
                  children: [
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        task.listName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (!task.completed)
                      IconButton(
                        key: ValueKey('weekly-schedule-${task.id}'),
                        tooltip: '安排日期',
                        onPressed: widget.controller.editing
                            ? null
                            : () => _pickDay(task),
                        icon: const Icon(
                          Icons.event_available_outlined,
                          size: 19,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
    if (task.completed) return content();
    final feedback = Material(
      color: Colors.transparent,
      child: SizedBox(width: 240, child: content(feedback: true)),
    );
    final child = content();
    final dragging = Opacity(opacity: 0.35, child: child);
    return MediaQuery.sizeOf(context).width >= 900
        ? Draggable<Task>(
            data: task,
            feedback: feedback,
            childWhenDragging: dragging,
            child: child,
          )
        : LongPressDraggable<Task>(
            data: task,
            feedback: feedback,
            childWhenDragging: dragging,
            child: child,
          );
  }
}
