import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../sync_core.dart';

Future<void> showTaskEditor(
  BuildContext context,
  AppController controller, {
  Task? task,
  String? listName,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => TaskEditorDialog(
      controller: controller,
      task: task,
      initialListName: listName,
    ),
  );
}

class TaskEditorDialog extends StatefulWidget {
  const TaskEditorDialog({
    super.key,
    required this.controller,
    this.task,
    this.initialListName,
  });

  final AppController controller;
  final Task? task;
  final String? initialListName;

  @override
  State<TaskEditorDialog> createState() => _TaskEditorDialogState();
}

class _TaskEditorDialogState extends State<TaskEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _note;
  late final TextEditingController _list;
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
    _dueDate = widget.task?.dueDate;
    _priority = widget.task?.priority ?? 0;
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _title.dispose();
    _note.dispose();
    _list.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final first = DateTime(2000);
    final last = DateTime(2100, 12, 31);
    var initial = DateTime.tryParse(_dueDate ?? '') ?? DateTime.now();
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: '选择截止日期',
    );
    if (date != null && mounted) {
      setState(() {
        _dueDate = '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    await widget.controller.waitForSync();
    if (!mounted) return;
    final original = widget.task;
    if (original != null && !_saveAsNew) {
      final matches = widget.controller.tasks.where((task) => task.id == original.id);
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
      if (currentContent != originalContent && currentContent != _acknowledgedContent) {
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
      ),
      id: _saveAsNew ? null : widget.task?.id,
    );
    if (!mounted) return;
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
        backgroundColor: const Color(0xfff8faf8),
        title: Row(
          children: [
            Icon(widget.task == null ? Icons.add_task_rounded : Icons.edit_note_rounded,
                color: colors.primary),
            const SizedBox(width: 12),
            Text(widget.task == null ? '新建待办' : '编辑待办'),
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
                    validator: (value) => (value ?? '').trim().isEmpty ? '写一个待办标题' : null,
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
                    decoration: const InputDecoration(
                      labelText: '清单',
                      hintText: '例如：工作、生活、收件箱',
                      prefixIcon: Icon(Icons.folder_outlined),
                      counterText: '',
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty ? '填写清单名称' : null,
                  ),
                  const SizedBox(height: 16),
                  Text('截止日期', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : _pickDate,
                          icon: const Icon(Icons.calendar_today_outlined, size: 18),
                          label: Text(_dueDate ?? '不设日期'),
                        ),
                      ),
                      if (_dueDate != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: '清除截止日期',
                          onPressed: _saving ? null : () => setState(() => _dueDate = null),
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
                      segments: const [
                        ButtonSegment(value: 0, label: Text('普通')),
                        ButtonSegment(value: 1, label: Text('较高')),
                        ButtonSegment(value: 2, label: Text('紧急')),
                      ],
                      selected: {_priority},
                      onSelectionChanged: _saving
                          ? null
                          : (selection) => setState(() => _priority = selection.first),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: colors.error)),
                  ],
                  if (_newerTask != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('收到的新版本', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Text(_newerTask!.title),
                          if (_newerTask!.note.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(_newerTask!.note, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            '${_newerTask!.listName} · ${_newerTask!.completed ? '已完成' : '未完成'} · '
                            '${['普通', '较高', '紧急'][_newerTask!.priority.clamp(0, 2).toInt()]}优先级 · '
                            '${_newerTask!.dueDate ?? '无截止日期'}',
                            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
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
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(_saving ? '正在保存' : widget.controller.syncing ? '同步中，请稍候' : _saveAsNew ? '保存为新待办' : _confirmOverwrite ? '确认覆盖更新' : '保存到本机'),
          ),
        ],
      ),
    );
  }
}
