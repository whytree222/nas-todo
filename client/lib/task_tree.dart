import 'sync_core.dart';

class TaskTreeRow {
  const TaskTreeRow(this.task, this.depth, this.childCount);
  final Task task;
  final int depth;
  final int childCount;
}

/// A filtered child stays visible when its parent is outside that same view.
List<TaskTreeRow> taskTreeRows(
  List<Task> tasks, {
  Set<String> collapsed = const {},
}) {
  final byId = {for (final task in tasks) task.id: task};
  final children = <String, List<Task>>{};
  final roots = <Task>[];
  for (final task in tasks) {
    if (task.parentId == null || !byId.containsKey(task.parentId)) {
      roots.add(task);
    } else {
      children.putIfAbsent(task.parentId!, () => []).add(task);
    }
  }
  final result = <TaskTreeRow>[];
  final visited = <String>{};
  void append(Task task, int depth, {bool visible = true}) {
    if (!visited.add(task.id)) {
      return;
    }
    final nested = children[task.id] ?? const <Task>[];
    if (visible) {
      result.add(TaskTreeRow(task, depth.clamp(0, 4).toInt(), nested.length));
    }
    for (final child in nested) {
      append(
        child,
        depth + 1,
        visible: visible && !collapsed.contains(task.id),
      );
    }
  }

  for (final task in roots) {
    append(task, 0);
  }
  // A cross-device hierarchy conflict must remain reachable for resolution.
  for (final task in tasks) {
    if (!visited.contains(task.id)) {
      append(task, 0);
    }
  }
  return result;
}
