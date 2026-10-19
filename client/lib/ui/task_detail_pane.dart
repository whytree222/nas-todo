import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../sync_core.dart';

/// A selection preview; editing still uses the shared conflict-aware editor.
class TaskDetailPane extends StatelessWidget {
  const TaskDetailPane({
    super.key,
    required this.controller,
    required this.task,
    required this.onEdit,
    required this.onDelete,
    required this.onClose,
  });

  final AppController controller;
  final Task? task;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final current = task;
    return Container(
      key: const ValueKey('task-detail-pane'),
      width: 300,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(left: BorderSide(color: colors.outlineVariant)),
      ),
      child: current == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.article_outlined,
                      size: 38,
                      color: colors.outline,
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      '把下一步看清楚',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      '点击待办右侧的详情按钮，\n在这里查看完整内容。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        height: 1.7,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 13, 8, 8),
                  child: Row(
                    children: [
                      Text(
                        '待办详情',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '关闭详情',
                        onPressed: onClose,
                        icon: const Icon(Icons.close_rounded, size: 19),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          current.title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                height: 1.45,
                                fontWeight: FontWeight.w700,
                                decoration: current.completed
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                        ),
                        const SizedBox(height: 22),
                        _field(
                          context,
                          Icons.folder_outlined,
                          '清单',
                          current.listName,
                        ),
                        _field(
                          context,
                          Icons.event_outlined,
                          '截止日期',
                          current.dueDate ?? '不设日期',
                        ),
                        _field(
                          context,
                          Icons.flag_outlined,
                          '优先级',
                          ['普通', '较高', '紧急'][current.priority
                              .clamp(0, 2)
                              .toInt()],
                        ),
                        _field(
                          context,
                          Icons.task_alt_rounded,
                          '状态',
                          current.completed ? '已完成' : '进行中',
                        ),
                        const Divider(height: 32),
                        Text(
                          '备注',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SelectableText(
                          current.note.isEmpty ? '还没有备注' : current.note,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.8,
                            color: current.note.isEmpty
                                ? colors.outline
                                : colors.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: '删除待办',
                        onPressed: controller.editing ? null : onDelete,
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: controller.editing ? null : onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 17),
                        label: const Text('编辑待办'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _field(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: colors.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(
            width: 62,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}
