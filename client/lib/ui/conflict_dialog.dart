import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../sync_core.dart';

Future<void> showConflictDialog(BuildContext context, AppController controller) {
  return showDialog<void>(
    context: context,
    builder: (context) => _ConflictDialog(controller: controller),
  );
}

class _ConflictDialog extends StatefulWidget {
  const _ConflictDialog({required this.controller});
  final AppController controller;

  @override
  State<_ConflictDialog> createState() => _ConflictDialogState();
}

class _ConflictDialogState extends State<_ConflictDialog> {
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _resolve(String taskId, bool keepLocal) async {
    if (_saving || widget.controller.busy) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final resolved = await widget.controller.resolveConflict(taskId, keepLocal: keepLocal);
    if (!mounted) return;
    if (!resolved) {
      setState(() {
        _saving = false;
        _error = widget.controller.error ?? '处理未完成，请重试。';
      });
    } else if (widget.controller.conflicts.isEmpty) {
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final conflicts = widget.controller.conflicts;
    final busy = _saving || widget.controller.busy;
    final conflict = conflicts.isEmpty ? null : conflicts.first;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('选择要保留的版本'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '同一待办在不同设备上发生了修改。先比较内容，再选择这一条的保留版本。',
                  style: TextStyle(color: colors.onSurfaceVariant, height: 1.6),
                ),
                if (conflict != null) ...[
                  const SizedBox(height: 20),
                  Text('还有 ${conflicts.length} 项需要处理', style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  _VersionCard(label: '本机版本', task: conflict.local, icon: Icons.phone_android_rounded),
                  const SizedBox(height: 12),
                  _VersionCard(label: 'NAS 版本', task: conflict.remote, icon: Icons.dns_outlined),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: TextStyle(color: colors.error)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('稍后处理'),
          ),
          if (conflict != null) ...[
            OutlinedButton(
              onPressed: busy ? null : () => _resolve(conflict.taskId, false),
              child: const Text('使用 NAS 版本'),
            ),
            FilledButton(
              onPressed: busy ? null : () => _resolve(conflict.taskId, true),
              child: Text(_saving ? '正在保存' : '使用本机版本'),
            ),
          ],
        ],
      ),
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({required this.label, required this.task, required this.icon});
  final String label;
  final Task? task;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final value = task;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: colors.primary),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          if (value == null || value.deleted)
            Text('这条待办已删除', style: TextStyle(color: colors.error))
          else ...[
            Text(value.title, style: Theme.of(context).textTheme.titleMedium),
            if (value.note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(value.note, style: TextStyle(color: colors.onSurfaceVariant, height: 1.5)),
            ],
            const SizedBox(height: 12),
            Text(
              '${value.listName} · ${value.completed ? '已完成' : '未完成'} · '
              '${['普通', '较高', '紧急'][value.priority.clamp(0, 2).toInt()]}优先级',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
            if (value.dueDate != null) ...[
              const SizedBox(height: 5),
              Text('截止日期：${value.dueDate}', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
            ],
          ],
        ],
      ),
    );
  }
}
