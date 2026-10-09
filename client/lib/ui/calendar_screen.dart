import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../task_dates.dart';
import 'agenda_task.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.controller,
    this.initialDate, this.onDateSelected});
  final AppController controller;
  final DateTime? initialDate;
  final ValueChanged<DateTime?>? onDateSelected;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month;
  late DateTime _selected;
  bool _unscheduled = false;

  @override
  void initState() {
    super.initState();
    final now = widget.initialDate ?? DateTime.now();
    _selected = DateTime(now.year, now.month, now.day);
    _month = DateTime(now.year, now.month);
  }

  void _select(DateTime day) {
    setState(() {
      _selected = day;
      _month = DateTime(day.year, day.month);
      _unscheduled = false;
    });
    widget.onDateSelected?.call(day);
  }

  void _moveMonth(int offset) {
    final next = DateTime(_month.year, _month.month + offset);
    final lastDay = DateTime(next.year, next.month + 1, 0).day;
    _select(DateTime(next.year, next.month,
        _selected.day > lastDay ? lastDay : _selected.day));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 760) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 420, child: SingleChildScrollView(child: _calendar())),
          const SizedBox(width: 24),
          Expanded(child: ListView(children: _agenda())),
        ]);
      }
      return ListView(padding: const EdgeInsets.only(bottom: 90), children: [
        _calendar(), const SizedBox(height: 16), ..._agenda(),
      ]);
    }),
  );

  Widget _calendar() {
    final colors = Theme.of(context).colorScheme;
    final first = DateTime(_month.year, _month.month);
    final start = DateTime(first.year, first.month, 1 - (first.weekday - 1));
    final today = dateKey(DateTime.now());
    return Column(children: [
      Row(children: [
        IconButton(tooltip: '上个月', onPressed: () => _moveMonth(-1),
          icon: const Icon(Icons.chevron_left_rounded)),
        Expanded(child: Text('${_month.year}年${_month.month}月',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700))),
        IconButton(tooltip: '下个月', onPressed: () => _moveMonth(1),
          icon: const Icon(Icons.chevron_right_rounded)),
        TextButton(onPressed: () => _select(DateTime.now()), child: const Text('今天')),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        for (final label in ['一', '二', '三', '四', '五', '六', '日'])
          Expanded(child: Center(child: Text(label))),
      ]),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, constraints) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 42,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7, mainAxisExtent: (constraints.maxWidth / 7).clamp(50.0, 70.0),
          crossAxisSpacing: 3, mainAxisSpacing: 3),
        itemBuilder: (context, index) {
          final day = DateTime(start.year, start.month, start.day + index);
          final key = dateKey(day);
          final tasks = tasksOnDate(widget.controller.tasks, key);
          final remaining = tasks.where((task) => !task.completed).length;
          final selected = !_unscheduled && key == dateKey(_selected);
          final currentMonth = day.month == _month.month;
          return Semantics(
            label: '$key，${tasks.length}项待办，$remaining项未完成',
            selected: selected,
            child: Material(
              color: selected ? colors.primaryContainer : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: key == today ? colors.primary : Colors.transparent)),
              child: InkWell(
                key: ValueKey('day-$key'),
                borderRadius: BorderRadius.circular(10), onTap: () => _select(day),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('${day.day}', style: TextStyle(
                    fontWeight: selected || key == today ? FontWeight.w700 : FontWeight.w400,
                    color: currentMonth ? colors.onSurface : colors.onSurfaceVariant)),
                  const SizedBox(height: 3),
                  Text(tasks.isEmpty ? '' : '$remaining/${tasks.length}',
                    style: TextStyle(fontSize: 10, color: colors.primary)),
                ]),
              ),
            ),
          );
        },
      )),
      const SizedBox(height: 8),
      const Text('日期下方：未完成 / 全部待办', style: TextStyle(fontSize: 11)),
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

  List<Widget> _agenda() {
    final tasks = tasksOnDate(widget.controller.tasks,
        _unscheduled ? null : dateKey(_selected));
    return [
      Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(
        _unscheduled ? '未安排日期' : '${_selected.month}月${_selected.day}日的待办',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
      if (tasks.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('没有待办，可以为这一天新建一条。')),
      for (final task in tasks) AgendaTask(task: task, controller: widget.controller),
    ];
  }
}
