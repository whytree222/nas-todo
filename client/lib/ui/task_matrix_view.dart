import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../sync_core.dart';
import '../workbench_queries.dart';
import 'task_board_view.dart';

class TaskMatrixView extends StatelessWidget {
  const TaskMatrixView({
    super.key,
    required this.controller,
    required this.tasks,
    required this.onEdit,
    this.now,
  });
  final AppController controller;
  final List<Task> tasks;
  final ValueChanged<Task> onEdit;
  final DateTime? now;

  Future<void> _move(
    BuildContext context,
    String id,
    MatrixQuadrant quadrant,
  ) async {
    if (!canMoveWorkbenchTask(controller, id)) {
      return;
    }
    // Send intent, rather than a date derived from an older drag snapshot. The
    // controller computes the needed fields after any in-flight NAS sync.
    final saved = await controller.setTaskQuadrant(
      id,
      important: quadrant.important,
      urgent: quadrant.urgent,
    );
    if (!context.mounted || saved) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(controller.error ?? '暂时无法移动，请稍后重试')));
  }

  @override
  Widget build(BuildContext context) {
    final day = now ?? DateTime.now();
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
          child: Text(
            '重要：较高或紧急优先级 · 紧急：今天到期或已逾期\n移到“不紧急”会清除已到期日期；重复待办改到明天，未来日期保留。',
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 760) {
                return ListView(
                  key: const ValueKey('matrix-scroll'),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  children: [
                    for (final quadrant in MatrixQuadrant.values)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SizedBox(
                          height: 350,
                          child: _quadrant(context, quadrant, day),
                        ),
                      ),
                  ],
                );
              }
              return GridView.count(
                key: const ValueKey('matrix-scroll'),
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: constraints.maxWidth > 1150 ? 1.6 : 1.2,
                children: [
                  for (final quadrant in MatrixQuadrant.values)
                    _quadrant(context, quadrant, day),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _quadrant(
    BuildContext context,
    MatrixQuadrant quadrant,
    DateTime day,
  ) {
    final colors = Theme.of(context).colorScheme;
    final accent = switch (quadrant) {
      MatrixQuadrant.importantUrgent => workbenchPriorityColor(context, 2),
      MatrixQuadrant.importantNotUrgent => colors.primary,
      MatrixQuadrant.notImportantUrgent => workbenchPriorityColor(context, 1),
      MatrixQuadrant.notImportantNotUrgent => workbenchPriorityColor(
        context,
        0,
      ),
    };
    final entries = tasks
        .where(
          (task) =>
              !task.deleted && taskMatrixQuadrant(task, now: day) == quadrant,
        )
        .toList();
    return DragTarget<String>(
      key: ValueKey('matrix-drop-${quadrant.name}'),
      onWillAcceptWithDetails: (details) =>
          canMoveWorkbenchTask(controller, details.data),
      onAcceptWithDetails: (details) => _move(context, details.data, quadrant),
      builder: (context, candidates, rejected) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: candidates.isEmpty ? .045 : .12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: accent.withValues(alpha: candidates.isEmpty ? .24 : .85),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        quadrant.urgent
                            ? Icons.bolt_rounded
                            : Icons.timelapse_rounded,
                        size: 20,
                        color: accent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          quadrant.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ),
                      Text(
                        '${entries.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      quadrant.hint,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
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
                      key: ValueKey('matrix-list-${quadrant.name}'),
                      primary: false,
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final task = entries[index];
                        final card = WorkbenchTaskCard(
                          task: task,
                          controller: controller,
                          onEdit: onEdit,
                          menuItems: [
                            for (final target in MatrixQuadrant.values)
                              PopupMenuItem(
                                value: target.index,
                                child: Text('移到${target.label}'),
                              ),
                          ],
                          onMenuSelected: (value) => _move(
                            context,
                            task.id,
                            MatrixQuadrant.values[value],
                          ),
                        );
                        return draggableWorkbenchTask(
                          context,
                          controller,
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
