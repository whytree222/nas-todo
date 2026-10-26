import 'sync_core.dart';
import 'task_dates.dart';

const weeklyListName = '周待办';

DateTime weekStart(DateTime date) =>
    DateTime(date.year, date.month, date.day - date.weekday + 1);

List<DateTime> weekDates(DateTime date) {
  final start = weekStart(date);
  return List.generate(
    7,
    (i) => DateTime(start.year, start.month, start.day + i),
  );
}

/// Unscheduled weekly tasks carry forward without inventing a due date.
List<Task> weeklyPool(Iterable<Task> tasks) => _sorted(
  tasks.where(
    (t) =>
        !t.deleted &&
        !t.completed &&
        t.listName == weeklyListName &&
        t.dueDate == null,
  ),
);

List<Task> weeklyDayTasks(Iterable<Task> tasks, DateTime day) =>
    _sorted(tasks.where((t) => !t.deleted && t.dueDate == dateKey(day)));

List<Task> _sorted(Iterable<Task> tasks) => tasks.toList()
  ..sort((a, b) {
    if (a.completed != b.completed) return a.completed ? 1 : -1;
    final priority = b.priority.compareTo(a.priority);
    return priority != 0 ? priority : a.title.compareTo(b.title);
  });
