import 'sync_core.dart';

String dateKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

List<Task> tasksOnDate(Iterable<Task> tasks, String? date) {
  final result = tasks.where((task) => !task.deleted && task.dueDate == date).toList();
  result.sort((a, b) {
    if (a.completed != b.completed) return a.completed ? 1 : -1;
    final priority = b.priority.compareTo(a.priority);
    return priority != 0 ? priority : a.title.compareTo(b.title);
  });
  return result;
}
