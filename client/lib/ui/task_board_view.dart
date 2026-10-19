import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../sync_core.dart';

class TaskBoardView extends StatefulWidget {
  const TaskBoardView({
    super.key,
    required this.controller,
    required this.tasks,
    required this.onEdit,
  });
  final AppController controller;
  final List<Task> tasks;
  final ValueChanged<Task> onEdit;

  @override
  State<TaskBoardView> createState() => _TaskBoardViewState();
}

class _TaskBoardViewState extends State<TaskBoardView> {
  final _horizontal = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  Future<void> _move(BuildContext context, String id, int priority) async {
    if (!canMoveWorkbenchTask(widget.controller, id)) return;
    final saved = await widget.controller.setTaskPlacement(id, priority: priority, requireIncomplete: true);
    if (!context.mounted || saved) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(widget.controller.error ?? '暂时无法移动，请稍后重试')));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
          child: Text(
            '按优先级看板 · 拖动卡片或使用卡片菜单调整优先级',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = math.max(276.0, (constraints.maxWidth - 56) / 3);
              return Scrollbar(
                key: const ValueKey('priority-board-scrollbar'),
                controller: _horizontal,
                child: SingleChildScrollView(
                  key: const ValueKey('priority-board-scroll'),
                  controller: _horizontal,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(20, 0, 8, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var priority = 0; priority <= 2; priority++)
                        SizedBox(
                          width: width,
                          child: _column(context, priority),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _column(BuildContext context, int priority) {
    final entries = widget.tasks
        .where((task) => !task.deleted && task.priority == priority)
        .toList();
    final colors = Theme.of(context).colorScheme;
    final accent = workbenchPriorityColor(context, priority);
    return DragTarget<String>(
      key: ValueKey('board-drop-$priority'),
      onWillAcceptWithDetails: (details) =>
          canMoveWorkbenchTask(widget.controller, details.data),
      onAcceptWithDetails: (details) => _move(context, details.data, priority),
      builder: (context, candidates, rejected) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: candidates.isNotEmpty
              ? accent.withValues(alpha: .10)
              : colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: candidates.isNotEmpty
                ? accent
                : colors.outlineVariant.withValues(alpha: .55),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    workbenchPriorityLabel(priority),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Text(
                    '${entries.length}',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          '拖放待办到这里',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      key: ValueKey('board-list-$priority'),
                      primary: false,
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final task = entries[index];
                        final card = WorkbenchTaskCard(
                          task: task,
                          controller: widget.controller,
                          onEdit: widget.onEdit,
                          menuItems: [
                            for (var value = 0; value <= 2; value++)
                              PopupMenuItem(
                                value: value,
                                child: Text(
                                  '移到${workbenchPriorityLabel(value)}',
                                ),
                              ),
                          ],
                          onMenuSelected: (value) =>
                              _move(context, task.id, value),
                        );
                        return draggableWorkbenchTask(
                          context,
                          widget.controller,
                          task,
                          card,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

bool canMoveWorkbenchTask(AppController controller, String id) =>
    !controller.editing &&
    !controller.conflicts.any((conflict) => conflict.taskId == id) &&
    controller.tasks.any(
      (task) => task.id == id && !task.deleted && !task.completed,
    );

Color workbenchPriorityColor(BuildContext context, int priority) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (priority) {
    2 => dark ? const Color(0xffff9a9f) : const Color(0xffcc4352),
    1 => dark ? const Color(0xffffce7b) : const Color(0xffa86b16),
    _ => dark ? const Color(0xff94baff) : const Color(0xff4777bd),
  };
}

String workbenchPriorityLabel(int priority) => switch (priority) {
  2 => '紧急',
  1 => '较高',
  _ => '普通',
};

Widget draggableWorkbenchTask(
  BuildContext context,
  AppController controller,
  Task task,
  Widget child,
) {
  if (!canMoveWorkbenchTask(controller, task.id)) return child;
  final feedback = Material(
    color: Colors.transparent,
    child: SizedBox(
      width: 280,
      child: IgnorePointer(child: Opacity(opacity: .94, child: child)),
    ),
  );
  final placeholder = Opacity(opacity: .28, child: child);
  final platform = Theme.of(context).platform;
  if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) {
    return LongPressDraggable<String>(
      key: ValueKey('workbench-drag-${task.id}'),
      data: task.id,
      delay: const Duration(milliseconds: 300),
      feedback: feedback,
      childWhenDragging: placeholder,
      child: child,
    );
  }
  return Draggable<String>(
    key: ValueKey('workbench-drag-${task.id}'),
    data: task.id,
    feedback: feedback,
    childWhenDragging: placeholder,
    child: child,
  );
}

/// Shared native-feeling card; every drag operation has a keyboard-accessible menu.
class WorkbenchTaskCard extends StatelessWidget {
  const WorkbenchTaskCard({
    super.key,
    required this.task,
    required this.controller,
    required this.onEdit,
    this.menuItems,
    this.onMenuSelected,
  });
  final Task task;
  final AppController controller;
  final ValueChanged<Task> onEdit;
  final List<PopupMenuEntry<int>>? menuItems;
  final ValueChanged<int>? onMenuSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final conflict = controller.conflicts.any((item) => item.taskId == task.id);
    final accent = workbenchPriorityColor(context, task.priority);
    return Card(
      key: ValueKey('workbench-card-${task.id}'),
      margin: const EdgeInsets.only(bottom: 9),
      elevation: 0,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: controller.editing || conflict ? null : () => onEdit(task),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: accent, width: 3)),
          ),
          padding: const EdgeInsets.fromLTRB(3, 6, 9, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    key: ValueKey('workbench-complete-${task.id}'),
                    value: task.completed,
                    onChanged: controller.editing || conflict
                        ? null
                        : (value) {
                            if (value != null) {
                              controller.setCompleted(task.id, value);
                            }
                          },
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        task.title,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
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
                  if (menuItems != null)
                    PopupMenuButton<int>(
                      key: ValueKey('workbench-menu-${task.id}'),
                      tooltip: '移动待办',
                      icon: const Icon(Icons.more_horiz_rounded, size: 20),
                      enabled: canMoveWorkbenchTask(controller, task.id),
                      itemBuilder: (_) => menuItems!,
                      onSelected: onMenuSelected,
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 13),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Text(
                      task.listName,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (task.dueDate != null)
                      Text(
                        task.dueDate!,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        workbenchPriorityLabel(task.priority),
                        style: TextStyle(fontSize: 10, color: accent),
                      ),
                    ),
                  ],
                ),
              ),
              if (conflict)
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 6, 0, 0),
                  child: Text(
                    '同步冲突，请先选择版本',
                    style: TextStyle(fontSize: 11, color: colors.error),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
