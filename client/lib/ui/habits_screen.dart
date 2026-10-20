import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../personal_core.dart';
import '../task_dates.dart';

class HabitsScreen extends StatefulWidget {
  const HabitsScreen({super.key, required this.controller, this.clock});
  final AppController controller;
  final DateTime Function()? clock;

  @override
  State<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends State<HabitsScreen> {
  late DateTime _month;
  String? _historyHabit;
  DateTime get _today {
    final now = (widget.clock ?? DateTime.now)();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _month = DateTime(_today.year, _today.month);
  }

  int _value(Habit habit, DateTime day) =>
      widget.controller.habitCheckIns
          .where(
            (item) => item.habitId == habit.id && item.date == dateKey(day),
          )
          .firstOrNull
          ?.value ??
      0;

  bool _scheduled(Habit habit, DateTime day) =>
      habit.weekdays.contains(day.weekday);

  Future<void> _setValue(Habit habit, DateTime day, int value) async {
    final saved = await widget.controller.setHabitValue(
      habit.id,
      dateKey(day),
      value,
    );
    if (!mounted || saved) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(widget.controller.error ?? '未能保存打卡，请重试')),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final habits = widget.controller.habits;
      final todayHabits = habits
          .where((habit) => _scheduled(habit, _today))
          .toList();
      final completed = todayHabits
          .where((habit) => _value(habit, _today) >= habit.goal)
          .length;
      final historyHabit =
          habits.where((habit) => habit.id == _historyHabit).firstOrNull ??
          habits.firstOrNull;
      final colors = Theme.of(context).colorScheme;
      return ListView(
        key: const ValueKey('habits-scroll'),
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                '让小事慢慢长大',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              FilledButton.icon(
                key: const ValueKey('habit-add'),
                onPressed: widget.controller.editing
                    ? null
                    : () => _editHabit(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('新建习惯'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.spa_rounded,
                  color: colors.onPrimaryContainer,
                  size: 34,
                ),
                const SizedBox(height: 8),
                Text(
                  '今天 $completed / ${todayHabits.length} 个习惯达标',
                  key: const ValueKey('habit-today-summary'),
                  style: TextStyle(
                    color: colors.onPrimaryContainer,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '每一次打卡，都在为想成为的自己浇水。',
                  style: TextStyle(color: colors.onPrimaryContainer),
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: todayHabits.isEmpty
                      ? 0
                      : completed / todayHabits.length,
                  borderRadius: BorderRadius.circular(8),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (habits.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.eco_outlined, size: 44, color: colors.primary),
                    const SizedBox(height: 12),
                    const Text('从一个小习惯开始，例如阅读或喝水。'),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => _editHabit(),
                      child: const Text('创建第一个习惯'),
                    ),
                  ],
                ),
              ),
            ),
          for (final habit in habits) _habitCard(habit),
          if (historyHabit != null) ...[
            const SizedBox(height: 18),
            Text('打卡历史', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey('habit-history-select-${historyHabit.id}'),
              initialValue: historyHabit.id,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '查看习惯'),
              items: [
                for (final habit in habits)
                  DropdownMenuItem(
                    value: habit.id,
                    child: Text(habit.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(() => _historyHabit = value),
            ),
            const SizedBox(height: 12),
            _monthHistory(historyHabit),
          ],
          const SizedBox(height: 16),
          Text(
            '周达标率 = 本周截至今天已达标的计划日 ÷ 计划日。休息日不计入；点历史日期可补记或撤销。记录保存在本机离线队列，联网后同步至支持个人功能的 NAS。',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
        ],
      );
    },
  );

  Widget _habitCard(Habit habit) {
    final colors = Theme.of(context).colorScheme;
    final value = _value(habit, _today);
    final scheduled = _scheduled(habit, _today);
    final done = value >= habit.goal;
    final start = DateTime(
      _today.year,
      _today.month,
      _today.day - _today.weekday + 1,
    );
    var planned = 0;
    var achieved = 0;
    for (
      var day = start;
      !day.isAfter(_today);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      if (!_scheduled(habit, day)) {
        continue;
      }
      planned++;
      if (_value(habit, day) >= habit.goal) {
        achieved++;
      }
    }
    return Card(
      key: ValueKey('habit-${habit.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: done
                      ? colors.primaryContainer
                      : colors.surfaceContainerHighest,
                  child: Icon(
                    done ? Icons.check_rounded : Icons.local_florist_outlined,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        habit.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        habit.weekdays.length == 7
                            ? '每天'
                            : '每周 ${habit.weekdays.map((day) => const ['一', '二', '三', '四', '五', '六', '日'][day - 1]).join('、')}',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  key: ValueKey('habit-menu-${habit.id}'),
                  tooltip: '习惯操作',
                  onSelected: (action) {
                    if (action == 'edit') {
                      _editHabit(habit);
                    }
                    if (action == 'delete') {
                      _deleteHabit(habit);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('编辑')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  scheduled
                      ? habit.goalType == 'bool'
                            ? (done ? '今天已打卡' : '今天还未打卡')
                            : '今天 $value / ${habit.goal} 次'
                      : '今天是休息日',
                  key: ValueKey('habit-value-${habit.id}'),
                ),
                if (scheduled && habit.goalType == 'bool')
                  FilledButton.tonalIcon(
                    key: ValueKey('habit-check-${habit.id}'),
                    onPressed: widget.controller.editing
                        ? null
                        : () => _setValue(habit, _today, done ? 0 : 1),
                    icon: Icon(done ? Icons.undo_rounded : Icons.check_rounded),
                    label: Text(done ? '撤销' : '打卡'),
                  ),
                if (scheduled && habit.goalType != 'bool') ...[
                  IconButton.outlined(
                    key: ValueKey('habit-minus-${habit.id}'),
                    tooltip: '减少一次',
                    onPressed: widget.controller.editing || value <= 0
                        ? null
                        : () => _setValue(habit, _today, value - 1),
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  FilledButton.tonalIcon(
                    key: ValueKey('habit-plus-${habit.id}'),
                    onPressed: widget.controller.editing
                        ? null
                        : () => _setValue(habit, _today, value + 1),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('记一次'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: math.min(1.0, value / habit.goal),
              borderRadius: BorderRadius.circular(6),
            ),
            const SizedBox(height: 8),
            Text(
              '本周 $achieved / $planned 天达标${planned == 0 ? '' : ' · ${(achieved / planned * 100).round()}%'}',
              key: ValueKey('habit-week-${habit.id}'),
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var offset = 6; offset >= 0; offset--)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _historyDay(
                        habit,
                        DateTime(
                          _today.year,
                          _today.month,
                          _today.day - offset,
                        ),
                        small: true,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthHistory(Habit habit) {
    final first = DateTime(_month.year, _month.month);
    final count = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = first.weekday - 1;
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              key: const ValueKey('habit-month-previous'),
              tooltip: '上个月',
              onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month - 1),
              ),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                '${_month.year}年${_month.month}月',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              key: const ValueKey('habit-month-next'),
              tooltip: '下个月',
              onPressed:
                  _month.year == _today.year && _month.month == _today.month
                  ? null
                  : () => setState(
                      () => _month = DateTime(_month.year, _month.month + 1),
                    ),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        Row(
          children: [
            for (final label in ['一', '二', '三', '四', '五', '六', '日'])
              Expanded(
                child: Center(
                  child: Text(label, style: const TextStyle(fontSize: 12)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          key: const ValueKey('habit-month-grid'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: leading + count,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 48,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemBuilder: (_, index) => index < leading
              ? const SizedBox.shrink()
              : _historyDay(
                  habit,
                  DateTime(_month.year, _month.month, index - leading + 1),
                ),
        ),
        const SizedBox(height: 8),
        const Text('深色：达标　浅色：已记录　空白：未打卡或休息日', style: TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _historyDay(Habit habit, DateTime day, {bool small = false}) {
    final colors = Theme.of(context).colorScheme;
    final value = _value(habit, day);
    final enabled = !day.isAfter(_today) && _scheduled(habit, day);
    final done = value >= habit.goal;
    return Semantics(
      label: '${dateKey(day)} ${habit.name} $value/${habit.goal}',
      child: Tooltip(
        message: '${day.month}月${day.day}日 · $value/${habit.goal}',
        child: Material(
          color: done
              ? colors.primary
              : value > 0
              ? colors.primaryContainer
              : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            key: ValueKey(
              'habit-${small ? 'recent' : 'history'}-${habit.id}-${dateKey(day)}',
            ),
            borderRadius: BorderRadius.circular(10),
            onTap: !enabled || widget.controller.editing
                ? null
                : () => _editCheckIn(habit, day),
            child: SizedBox(
              height: 42,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    small
                        ? const [
                            '一',
                            '二',
                            '三',
                            '四',
                            '五',
                            '六',
                            '日',
                          ][day.weekday - 1]
                        : '${day.day}',
                    style: TextStyle(
                      fontSize: 12,
                      color: done ? colors.onPrimary : colors.onSurfaceVariant,
                      fontWeight: done ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editCheckIn(Habit habit, DateTime day) async {
    var input = '${_value(habit, day)}';
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${day.month}月${day.day}日 · ${habit.name}'),
        content: habit.goalType == 'bool'
            ? const Text('补记或撤销这一天的打卡。')
            : TextFormField(
                key: const ValueKey('habit-history-value'),
                initialValue: input,
                onChanged: (value) => input = value,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: '完成次数（目标${habit.goal}）'),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 0),
            child: const Text('撤销打卡'),
          ),
          FilledButton(
            onPressed: () {
              final value = habit.goalType == 'bool' ? 1 : int.tryParse(input);
              if (value != null && value >= 0 && value <= 100000) {
                Navigator.pop(context, value);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value != null) {
      await _setValue(habit, day, value);
    }
  }

  Future<void> _deleteHabit(Habit habit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除“${habit.name}”？'),
        content: const Text('此操作会同步到其他设备。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.controller.deleteHabit(habit.id);
    }
  }

  Future<void> _editHabit([Habit? habit]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _HabitEditor(controller: widget.controller, habit: habit),
    );
  }
}

class _HabitEditor extends StatefulWidget {
  const _HabitEditor({required this.controller, this.habit});
  final AppController controller;
  final Habit? habit;
  @override
  State<_HabitEditor> createState() => _HabitEditorState();
}

class _HabitEditorState extends State<_HabitEditor> {
  late final _name = TextEditingController(text: widget.habit?.name ?? '');
  late final _goal = TextEditingController(text: '${widget.habit?.goal ?? 1}');
  late String _type = widget.habit?.goalType ?? 'bool';
  late final _weekdays = <int>{
    ...(widget.habit?.weekdays ?? [1, 2, 3, 4, 5, 6, 7]),
  };
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _goal.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final goal = _type == 'bool' ? 1 : int.tryParse(_goal.text);
    if (_name.text.trim().isEmpty ||
        _weekdays.isEmpty ||
        goal == null ||
        goal < 1 ||
        goal > 100000) {
      setState(() => _error = '请填写名称、有效目标和至少一个计划日');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await widget.controller.saveHabit(
      HabitDraft(
        name: _name.text.trim(),
        goalType: _type,
        goal: goal,
        weekdays: _weekdays.toList()..sort(),
      ),
      id: widget.habit?.id,
    );
    if (!mounted) {
      return;
    }
    if (saved) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = false;
      _error = widget.controller.error ?? '保存失败，请重试';
    });
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.habit == null ? '新建习惯' : '编辑习惯',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('habit-name'),
              controller: _name,
              enabled: !_saving,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: '习惯名称',
                hintText: '例如：阅读十分钟',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final type in const {
                  'bool': '勾选打卡',
                  'count': '次数目标',
                }.entries)
                  ChoiceChip(
                    key: ValueKey('habit-type-${type.key}'),
                    label: Text(type.value),
                    selected: _type == type.key,
                    onSelected: _saving
                        ? null
                        : (_) => setState(() => _type = type.key),
                  ),
              ],
            ),
            if (_type == 'count') ...[
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('habit-goal'),
                controller: _goal,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '每日目标次数'),
              ),
            ],
            const SizedBox(height: 18),
            const Text('每周计划日（全选为每天）'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (var day = 1; day <= 7; day++)
                  FilterChip(
                    key: ValueKey('habit-weekday-$day'),
                    label: Text(
                      const ['一', '二', '三', '四', '五', '六', '日'][day - 1],
                    ),
                    selected: _weekdays.contains(day),
                    onSelected: _saving
                        ? null
                        : (selected) => setState(() {
                            if (selected) {
                              _weekdays.add(day);
                            } else {
                              _weekdays.remove(day);
                            }
                          }),
                  ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FilledButton(
                  key: const ValueKey('habit-save'),
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? '保存中…' : '保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
