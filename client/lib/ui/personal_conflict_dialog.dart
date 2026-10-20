import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../personal_core.dart';
import 'task_repeat_options.dart';

Future<void> showPersonalConflictDialog(
  BuildContext context,
  AppController controller,
) => showDialog<void>(
  context: context,
  builder: (_) => _PersonalConflicts(controller: controller),
);

class _PersonalConflicts extends StatefulWidget {
  const _PersonalConflicts({required this.controller});
  final AppController controller;
  @override
  State<_PersonalConflicts> createState() => _PersonalConflictsState();
}

class _PersonalConflictsState extends State<_PersonalConflicts> {
  bool _saving = false;
  String? _error;
  Future<void> _resolve(PersonalConflict conflict, bool local) async {
    setState(() => _saving = true);
    final saved = await widget.controller.resolvePersonalConflict(
      conflict.kind,
      conflict.id,
      keepLocal: local,
    );
    if (!mounted) {
      return;
    }
    if (saved && widget.controller.personalConflicts.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = false;
      _error = saved ? null : widget.controller.error;
    });
  }

  String _summary(PersonalRecord? record) {
    if (record == null || record.deleted) {
      return '此记录已不存在或已删除';
    }
    final data = record.data;
    if (record.kind == 'habit') {
      return '${data['name']}\n目标：${data['goal']} ${data['goal_type'] == 'bool' ? '次勾选' : '次'}\n每周执行：${(data['weekdays'] as List).join('、')}';
    }
    if (record.kind == 'habit_checkin') {
      return '${data['date']}\n完成次数：${data['value']}';
    }
    final repeat = data['repeat_rule'] == null
        ? null
        : TaskRepeatRule.fromJson(
            Map<String, dynamic>.from(data['repeat_rule'] as Map),
          );
    final parent = widget.controller.tasks
        .where((task) => task.id == data['parent_id'])
        .firstOrNull;
    return '父待办：${parent?.title ?? '无'}\n标签：${(data['tags'] as List).join('、')}\n${taskRepeatLabel(repeat)}';
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final conflict = widget.controller.personalConflicts.firstOrNull;
      return AlertDialog(
        title: const Text('选择个人数据版本'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('这条记录在不同设备上被修改。选择后会同步到其他设备。'),
                if (conflict != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    '本机版本',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(_summary(conflict.local)),
                  const Divider(height: 28),
                  const Text(
                    'NAS 版本',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(_summary(conflict.remote)),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('稍后处理'),
          ),
          if (conflict != null) ...[
            OutlinedButton(
              onPressed: _saving ? null : () => _resolve(conflict, false),
              child: const Text('使用 NAS 版本'),
            ),
            FilledButton(
              onPressed: _saving || conflict.remote?.deleted == true
                  ? null
                  : () => _resolve(conflict, true),
              child: Text(_saving ? '正在保存' : '使用本机版本'),
            ),
          ],
        ],
      );
    },
  );
}
