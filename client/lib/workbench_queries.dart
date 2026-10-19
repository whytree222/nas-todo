import 'sync_core.dart';
import 'task_dates.dart';

/// Personal smart views are projections of the existing synced task fields.
enum SmartTaskView {
  all,
  inbox,
  today,
  nextSevenDays,
  completed,
  important,
  overdue,
  unscheduled,
}

enum WorkbenchDueBucket {
  overdue,
  today,
  tomorrow,
  nextSevenDays,
  later,
  unscheduled,
}

extension WorkbenchDueBucketLabel on WorkbenchDueBucket {
  String get label => switch (this) {
    WorkbenchDueBucket.overdue => '已逾期',
    WorkbenchDueBucket.today => '今天',
    WorkbenchDueBucket.tomorrow => '明天',
    WorkbenchDueBucket.nextSevenDays => '未来七天',
    WorkbenchDueBucket.later => '以后',
    WorkbenchDueBucket.unscheduled => '未安排',
  };
}

List<Task> queryWorkbenchTasks(
  Iterable<Task> tasks, {
  required SmartTaskView view,
  DateTime? now,
  String query = '',
  String? listName,
  int? priority,
  String sort = 'due',
}) {
  final day = now ?? DateTime.now();
  final today = dateKey(day);
  // Calendar arithmetic keeps the inclusive seven-day window correct across DST.
  final weekEnd = dateKey(DateTime(day.year, day.month, day.day + 6));
  final text = query.trim().toLowerCase();
  final result = tasks.where((task) {
    if (task.deleted ||
        (view == SmartTaskView.completed ? !task.completed : task.completed))
      return false;
    if (listName != null && task.listName != listName) return false;
    if (priority != null && task.priority != priority) return false;
    if (text.isNotEmpty &&
        !'${task.title}\n${task.note}\n${task.listName}'.toLowerCase().contains(
          text,
        ))
      return false;
    return switch (view) {
      SmartTaskView.all || SmartTaskView.completed => true,
      SmartTaskView.inbox => const {
        '',
        '收件箱',
        '未分类',
      }.contains(task.listName.trim()),
      SmartTaskView.today => task.dueDate == today,
      SmartTaskView.nextSevenDays =>
        task.dueDate != null &&
            task.dueDate!.compareTo(today) >= 0 &&
            task.dueDate!.compareTo(weekEnd) <= 0,
      SmartTaskView.important => task.priority >= 1,
      SmartTaskView.overdue =>
        task.dueDate != null && task.dueDate!.compareTo(today) < 0,
      SmartTaskView.unscheduled => task.dueDate == null,
    };
  }).toList();
  result.sort((a, b) => compareWorkbenchTasks(a, b, sort: sort));
  return result;
}

int compareWorkbenchTasks(Task a, Task b, {String sort = 'due'}) {
  final due = (a.dueDate ?? '9999-12-31').compareTo(b.dueDate ?? '9999-12-31');
  final priority = b.priority.compareTo(a.priority);
  final title = a.title.toLowerCase().compareTo(b.title.toLowerCase());
  final first = switch (sort) {
    'priority' => priority != 0 ? priority : due,
    'title' => title,
    'updated' || 'recent' => b.updatedAt.compareTo(a.updatedAt),
    _ => due != 0 ? due : priority,
  };
  if (first != 0) return first;
  if (title != 0) return title;
  return a.id.compareTo(b.id);
}

WorkbenchDueBucket workbenchDueBucket(Task task, {DateTime? now}) {
  final due = task.dueDate;
  if (due == null) return WorkbenchDueBucket.unscheduled;
  final day = now ?? DateTime.now();
  final today = dateKey(day);
  if (due.compareTo(today) < 0) return WorkbenchDueBucket.overdue;
  if (due == today) return WorkbenchDueBucket.today;
  if (due == dateKey(DateTime(day.year, day.month, day.day + 1)))
    return WorkbenchDueBucket.tomorrow;
  if (due.compareTo(dateKey(DateTime(day.year, day.month, day.day + 6))) <= 0)
    return WorkbenchDueBucket.nextSevenDays;
  return WorkbenchDueBucket.later;
}

Map<WorkbenchDueBucket, List<Task>> groupWorkbenchTasksByDueDate(
  Iterable<Task> tasks, {
  DateTime? now,
}) {
  final result = {
    for (final bucket in WorkbenchDueBucket.values) bucket: <Task>[],
  };
  final day = now ?? DateTime.now();
  for (final task in tasks) {
    if (!task.deleted) result[workbenchDueBucket(task, now: day)]!.add(task);
  }
  for (final entries in result.values) {
    entries.sort(compareWorkbenchTasks);
  }
  return result;
}

enum MatrixQuadrant {
  importantUrgent,
  importantNotUrgent,
  notImportantUrgent,
  notImportantNotUrgent,
}

extension MatrixQuadrantDetails on MatrixQuadrant {
  bool get important =>
      this == MatrixQuadrant.importantUrgent ||
      this == MatrixQuadrant.importantNotUrgent;
  bool get urgent =>
      this == MatrixQuadrant.importantUrgent ||
      this == MatrixQuadrant.notImportantUrgent;
  String get label => switch (this) {
    MatrixQuadrant.importantUrgent => '重要且紧急',
    MatrixQuadrant.importantNotUrgent => '重要不紧急',
    MatrixQuadrant.notImportantUrgent => '紧急不重要',
    MatrixQuadrant.notImportantNotUrgent => '不紧急不重要',
  };
  String get hint => switch (this) {
    MatrixQuadrant.importantUrgent => '优先处理',
    MatrixQuadrant.importantNotUrgent => '留出时间，持续推进',
    MatrixQuadrant.notImportantUrgent => '及时处理，减少打扰',
    MatrixQuadrant.notImportantNotUrgent => '留待合适的时候',
  };
}

MatrixQuadrant taskMatrixQuadrant(Task task, {DateTime? now}) {
  final important = task.priority >= 1;
  final urgent =
      task.dueDate != null &&
      task.dueDate!.compareTo(dateKey(now ?? DateTime.now())) <= 0;
  return important
      ? urgent
            ? MatrixQuadrant.importantUrgent
            : MatrixQuadrant.importantNotUrgent
      : urgent
      ? MatrixQuadrant.notImportantUrgent
      : MatrixQuadrant.notImportantNotUrgent;
}

class MatrixTaskPlacement {
  const MatrixTaskPlacement({
    required this.priority,
    this.dueDate,
    this.clearDueDate = false,
  });
  final int priority;
  final String? dueDate;
  final bool clearDueDate;
}

/// A move changes only the priority and date required to express that quadrant.
MatrixTaskPlacement matrixPlacementFor(
  Task task,
  MatrixQuadrant target, {
  DateTime? now,
}) {
  final today = dateKey(now ?? DateTime.now());
  final isUrgent = task.dueDate != null && task.dueDate!.compareTo(today) <= 0;
  return MatrixTaskPlacement(
    priority: target.important ? (task.priority >= 1 ? task.priority : 1) : 0,
    dueDate: target.urgent ? (isUrgent ? task.dueDate : today) : task.dueDate,
    clearDueDate: !target.urgent && isUrgent,
  );
}
