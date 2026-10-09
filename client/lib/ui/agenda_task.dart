import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../sync_core.dart';
import 'conflict_dialog.dart';
import 'task_editor.dart';

class AgendaTask extends StatelessWidget {
  const AgendaTask({super.key, required this.task, required this.controller});
  final Task task;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final conflict = controller.conflicts.any((item) => item.taskId == task.id);
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: Colors.white,
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 4, right: 12),
        leading: Checkbox(
          key: ValueKey('complete-${task.id}'),
          value: task.completed,
          onChanged: controller.editing || conflict ? null : (value) {
            controller.setCompleted(task.id, value!);
          },
        ),
        title: Text(task.title, style: TextStyle(
          decoration: task.completed ? TextDecoration.lineThrough : null,
          color: task.completed ? colors.onSurfaceVariant : colors.onSurface,
        )),
        subtitle: Text(conflict ? '需要选择版本' : task.listName,
          style: TextStyle(color: conflict ? colors.error : colors.onSurfaceVariant)),
        trailing: conflict ? const Icon(Icons.compare_arrows_rounded) : null,
        onTap: controller.editing ? null : () => conflict
            ? showConflictDialog(context, controller)
            : showTaskEditor(context, controller, task: task),
      ),
    );
  }
}
