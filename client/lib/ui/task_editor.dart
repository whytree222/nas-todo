import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../sync_core.dart';
import 'task_repeat_options.dart';

Future<void> showTaskEditor(
  BuildContext context,
  AppController controller, {
  Task? task,
  String? listName,
  String? initialDueDate,
  String? initialParentId,
  List<String> initialTags = const [],
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => TaskEditorDialog(
      controller: controller,
      task: task,
      initialListName: listName,
      initialDueDate: initialDueDate,
      initialParentId: initialParentId,
      initialTags: initialTags,
    ),
  );
}

class TaskEditorDialog extends StatefulWidget {
  const TaskEditorDialog({
    super.key,
    required this.controller,
    this.task,
    this.initialListName,
    this.initialDueDate,
    this.initialParentId,
    this.initialTags = const [],
  });

  final AppController controller;
  final Task? task;
  final String? initialListName;
  final String? initialDueDate;
  final String? initialParentId;
  final List<String> initialTags;

  @override
  State<TaskEditorDialog> createState() => _TaskEditorDialogState();
}

class _TaskEditorDialogState extends State<TaskEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _note;
  late final TextEditingController _list;
  late final TextEditingController _tags;
  late final TextEditingController _repeatInterval;
  late final TextEditingController _repeatMonthDay;
  String? _parentId;
  String _repeatFrequency = 'none';
  final Set<int> _repeatWeekdays = {};
  String? _dueDate;
  late int _priority;
  bool _saving = false;
  String? _error;
  String? _acknowledgedContent;
  bool _confirmOverwrite = false;
  bool _saveAsNew = false;
  Task? _newerTask;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    _title = TextEditingController(text: widget.task?.title ?? '');
    _note = TextEditingController(text: widget.task?.note ?? '');
    _list = TextEditingController(
      text: widget.task?.listName ?? widget.initialListName ?? '收件箱',
    );
    _dueDate = widget.task != null
        ? widget.task!.dueDate
        : widget.initialDueDate;
    _priority = widget.task?.priority ?? 0;
    _parentId = widget.task?.parentId ?? widget.initialParentId;
    _tags = TextEditingController(
      text: (widget.task?.tags ?? widget.initialTags).join('，'),
    );
    final repeat = widget.task?.repeatRule;
    _repeatFrequency = repeat?.frequency ?? 'none';
    _repeatInterval = TextEditingController(text: '${repeat?.interval ?? 1}');
    _repeatMonthDay = TextEditingController(
      text:
          '${repeat?.monthDay ?? DateTime.tryParse(_dueDate ?? '')?.day ?? DateTime.now().day}',
    );
    _repeatWeekdays.addAll(repeat?.weekdays ?? const []);
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  List<String> get _availableLists {
    final names = <String>{
      for (final task in widget.controller.tasks)
        if (!task.deleted && task.listName.trim().isNotEmpty)
          task.listName.trim(),
      if (widget.task?.listName.trim().isNotEmpty ?? false)
        widget.task!.listName.trim(),
      if (widget.initialListName?.trim().isNotEmpty ?? false)
        widget.initialListName!.trim(),
    };
    names.remove('收件箱');
    return ['收件箱', ...(names.toList()..sort())];
  }

  void _selectList(String name) {
    if (_saving) {
      return;
    }
    setState(() {
      _list.value = TextEditingValue(
        text: name,
        selection: TextSelection(baseOffset: 0, extentOffset: name.length),
      );
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _title.dispose();
    _note.dispose();
    _list.dispose();
    _tags.dispose();
    _repeatInterval.dispose();
    _repeatMonthDay.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final first = DateTime(2000);
    final last = DateTime(2100, 12, 31);
    var initial = DateTime.tryParse(_dueDate ?? '') ?? DateTime.now();
    if (initial.isBefore(first)) {
      initial = first;
    }
    if (initial.isAfter(last)) {
      initial = last;
    }
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: '选择截止日期',
    );
    if (date != null && mounted) {
      setState(() {
        _dueDate =
            '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}';
      });
    }
  }

  List<String> _parseTags() => _tags.text
      .split(RegExp(r'[,，;；\n]'))
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toSet()
      .toList();

  List<Task> get _possibleParents {
    final excluded = <String>{if (widget.task != null) widget.task!.id};
    var changed = true;
    while (changed) {
      changed = false;
      for (final task in widget.controller.tasks) {
        if (task.parentId != null &&
            excluded.contains(task.parentId) &&
            excluded.add(task.id)) {
          changed = true;
        }
      }
    }
    return widget.controller.tasks
        .where((task) => !excluded.contains(task.id))
        .toList()
      ..sort((a, b) => a.title.compareTo(b.title));
  }

  Widget _personalFields() {
    final parents = _possibleParents;
    final knownTags =
        widget.controller.tasks.expand((task) => task.tags).toSet().toList()
          ..sort();
    return ExpansionTile(
      key: const ValueKey('task-personal-options'),
      tilePadding: EdgeInsets.zero,
      initiallyExpanded:
          widget.initialParentId != null ||
          widget.task?.parentId != null ||
          (widget.task?.tags.isNotEmpty ?? false) ||
          widget.task?.repeatRule != null,
      title: const Text('子任务、标签与重复'),
      subtitle: Text(
        _repeatFrequency == 'none'
            ? '按需添加更多安排'
            : taskRepeatLabel(
                TaskRepeatRule(
                  frequency: _repeatFrequency,
                  interval: int.tryParse(_repeatInterval.text) ?? 1,
                ),
              ),
      ),
      children: [
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: const ValueKey('task-parent'),
          initialValue: _parentId ?? 'none',
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '父待办',
            helperText: '不选择即为顶层待办，最多 5 层',
          ),
          items: [
            const DropdownMenuItem(value: 'none', child: Text('无 · 顶层待办')),
            if (_parentId != null &&
                !parents.any((task) => task.id == _parentId))
              DropdownMenuItem(
                value: _parentId,
                child: const Text('原父待办已删除，请重新选择'),
              ),
            for (final task in parents)
              DropdownMenuItem(
                value: task.id,
                child: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _saving
              ? null
              : (value) =>
                    setState(() => _parentId = value == 'none' ? null : value),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('task-tags'),
          controller: _tags,
          enabled: !_saving,
          maxLength: 700,
          decoration: InputDecoration(
            labelText: '标签',
            hintText: '用逗号分隔，例如：学习，阅读',
            counterText: '',
            suffixIcon: knownTags.isEmpty
                ? null
                : PopupMenuButton<String>(
                    tooltip: '选择已有标签',
                    onSelected: (tag) => setState(
                      () => _tags.text = ({
                        ..._parseTags(),
                        tag,
                      }.toList()..sort()).join('，'),
                    ),
                    itemBuilder: (_) => [
                      for (final tag in knownTags)
                        PopupMenuItem(value: tag, child: Text(tag)),
                    ],
                  ),
          ),
          validator: (_) {
            final tags = _parseTags();
            if (tags.length > 20 || tags.any((tag) => tag.runes.length > 30)) {
              return '最多 20 个标签，每个标签不超过 30 字';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: const ValueKey('task-repeat'),
          initialValue: _repeatFrequency,
          decoration: const InputDecoration(labelText: '重复规则'),
          items: const [
            DropdownMenuItem(value: 'none', child: Text('不重复')),
            DropdownMenuItem(value: 'daily', child: Text('按天重复')),
            DropdownMenuItem(value: 'weekly', child: Text('按周重复')),
            DropdownMenuItem(value: 'monthly', child: Text('按月重复')),
          ],
          onChanged: _saving
              ? null
              : (value) => setState(() {
                  _repeatFrequency = value ?? 'none';
                  if (_repeatFrequency == 'weekly' && _repeatWeekdays.isEmpty) {
                    _repeatWeekdays.add(
                      (DateTime.tryParse(_dueDate ?? '') ?? DateTime.now())
                          .weekday,
                    );
                  }
                }),
        ),
        if (_repeatFrequency != 'none') ...[
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('task-repeat-interval'),
            controller: _repeatInterval,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '重复间隔',
              helperText: '1–365，例如每 2 天、每 2 周或每 2 月',
            ),
            validator: (text) {
              final value = int.tryParse(text ?? '');
              return value == null || value < 1 || value > 365
                  ? '填写 1–365'
                  : null;
            },
          ),
          if (_repeatFrequency == 'weekly')
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Wrap(
                spacing: 5,
                children: [
                  for (var day = 1; day <= 7; day++)
                    FilterChip(
                      key: ValueKey('repeat-weekday-$day'),
                      label: Text(
                        const ['一', '二', '三', '四', '五', '六', '日'][day - 1],
                      ),
                      selected: _repeatWeekdays.contains(day),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _repeatWeekdays.add(day);
                        } else {
                          _repeatWeekdays.remove(day);
                        }
                      }),
                    ),
                ],
              ),
            ),
          if (_repeatFrequency == 'monthly')
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextFormField(
                key: const ValueKey('task-repeat-month-day'),
                controller: _repeatMonthDay,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '每月几日'),
                validator: (text) {
                  final value = int.tryParse(text ?? '');
                  return value == null || value < 1 || value > 31
                      ? '填写 1–31'
                      : null;
                },
              ),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '完成并同步后，由 NAS 生成下一次。月末不足指定日期时使用当月最后一天。',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) {
      return;
    }
    if (_repeatFrequency != 'none' && _dueDate == null) {
      setState(() => _error = '重复待办需要先选择截止日期。');
      return;
    }
    if (_repeatFrequency == 'weekly' && _repeatWeekdays.isEmpty) {
      setState(() => _error = '请选择每周重复的星期。');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    await widget.controller.waitForSync();
    if (!mounted) {
      return;
    }
    final original = widget.task;
    if (original != null && !_saveAsNew) {
      final matches = widget.controller.tasks.where(
        (task) => task.id == original.id,
      );
      final current = matches.isEmpty ? null : matches.first;
      if (current == null) {
        setState(() {
          _saving = false;
          _saveAsNew = true;
          _error = '这条待办在编辑期间已被删除。你的输入仍然保留，可以保存为一条新待办。';
        });
        return;
      }
      final currentContent = jsonEncode(TaskDraft.fromTask(current).toJson());
      final originalContent = jsonEncode(TaskDraft.fromTask(original).toJson());
      if (currentContent != originalContent &&
          currentContent != _acknowledgedContent) {
        setState(() {
          _saving = false;
          _confirmOverwrite = true;
          _newerTask = current;
          _acknowledgedContent = currentContent;
          _error = '这条待办在编辑期间收到新的修改。你的输入仍然保留；再次确认保存，会用当前输入覆盖新版本。';
        });
        return;
      }
    }
    final saved = await widget.controller.saveTask(
      TaskDraft(
        title: _title.text.trim(),
        note: _note.text.trim(),
        listName: _list.text.trim(),
        dueDate: _dueDate,
        priority: _priority,
        completed: widget.task?.completed ?? false,
        parentId: _parentId,
        tags: _parseTags(),
        repeatRule: _repeatFrequency == 'none'
            ? null
            : TaskRepeatRule(
                frequency: _repeatFrequency,
                interval: int.tryParse(_repeatInterval.text) ?? 1,
                weekdays: _repeatFrequency == 'weekly'
                    ? (_repeatWeekdays.toList()..sort())
                    : const [],
                monthDay: _repeatFrequency == 'monthly'
                    ? int.tryParse(_repeatMonthDay.text)
                    : null,
              ),
      ),
      id: _saveAsNew ? null : widget.task?.id,
    );
    if (!mounted) {
      return;
    }
    if (saved) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = widget.controller.error ?? '保存未完成，请重试。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        backgroundColor: colors.surface,
        title: Row(
          children: [
            Icon(
              widget.task == null
                  ? Icons.add_task_rounded
                  : Icons.edit_note_rounded,
              color: colors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(widget.task == null ? '新建待办' : '编辑待办')),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    key: const ValueKey('task-title'),
                    controller: _title,
                    autofocus: true,
                    enabled: !_saving,
                    maxLength: 200,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '待办标题',
                      hintText: '下一件想完成的事',
                      counterText: '',
                    ),
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? '写一个待办标题' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('task-note'),
                    controller: _note,
                    enabled: !_saving,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 10000,
                    decoration: const InputDecoration(
                      labelText: '备注',
                      hintText: '补充细节或下一步（选填）',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('task-list'),
                    controller: _list,
                    enabled: !_saving,
                    maxLength: 60,
                    decoration: InputDecoration(
                      labelText: '清单',
                      hintText: '选择已有清单，或输入新名称',
                      prefixIcon: const Icon(Icons.folder_outlined),
                      suffixIcon: PopupMenuButton<String>(
                        key: const ValueKey('task-list-picker'),
                        tooltip: '选择已有清单',
                        enabled: !_saving,
                        icon: const Icon(Icons.arrow_drop_down_rounded),
                        constraints: const BoxConstraints(maxWidth: 320),
                        onSelected: _selectList,
                        itemBuilder: (context) => [
                          for (final name in _availableLists)
                            CheckedPopupMenuItem<String>(
                              key: ValueKey('task-list-option-$name'),
                              value: name,
                              checked: name == _list.text.trim(),
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                      counterText: '',
                    ),
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? '填写清单名称' : null,
                  ),
                  const SizedBox(height: 16),
                  Text('截止日期', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : _pickDate,
                          icon: const Icon(
                            Icons.calendar_today_outlined,
                            size: 18,
                          ),
                          label: Text(_dueDate ?? '不设日期'),
                        ),
                      ),
                      if (_dueDate != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: '清除截止日期',
                          onPressed: _saving
                              ? null
                              : () => setState(() => _dueDate = null),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('优先级', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<int>(
                      showSelectedIcon: false,
                      style: ButtonStyle(
                        minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 6),
                        ),
                        textStyle: WidgetStatePropertyAll(
                          Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontSize: 12),
                        ),
                      ),
                      segments: const [
                        ButtonSegment(value: 0, label: Text('普通')),
                        ButtonSegment(value: 1, label: Text('较高')),
                        ButtonSegment(value: 2, label: Text('紧急')),
                      ],
                      selected: {_priority},
                      onSelectionChanged: _saving
                          ? null
                          : (selection) =>
                                setState(() => _priority = selection.first),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _personalFields(),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: colors.error)),
                  ],
                  if (_newerTask != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '收到的新版本',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(_newerTask!.title),
                          if (_newerTask!.note.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              _newerTask!.note,
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            '${_newerTask!.listName} · ${_newerTask!.completed ? '已完成' : '未完成'} · '
                            '${['普通', '较高', '紧急'][_newerTask!.priority.clamp(0, 2).toInt()]}优先级 · '
                            '${_newerTask!.dueDate ?? '无截止日期'}',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: _saving || widget.controller.syncing ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(
              _saving
                  ? '正在保存'
                  : widget.controller.syncing
                  ? '同步中，请稍候'
                  : _saveAsNew
                  ? '保存为新待办'
                  : _confirmOverwrite
                  ? '确认覆盖更新'
                  : '保存到本机',
            ),
          ),
        ],
      ),
    );
  }
}
