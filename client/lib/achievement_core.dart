import 'sync_core.dart';
import 'habit_achievement.dart';
import 'personal_core.dart';

DateTime achievementToday() {
  final now = DateTime.now().toUtc().add(const Duration(hours: 8));
  return DateTime(now.year, now.month, now.day);
}

String achievementMonth(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
String _date(DateTime date) =>
    '${achievementMonth(date)}-${date.day.toString().padLeft(2, '0')}';

class WeekAchievement {
  final String start;
  final String end;
  final int total;
  final int completed;
  final int? taskTotal, taskCompleted;
  final int habitTotal, habitCompleted, rulesVersion;
  const WeekAchievement({
    required this.start,
    required this.end,
    required this.total,
    required this.completed,
    this.taskTotal,
    this.taskCompleted,
    this.habitTotal = 0,
    this.habitCompleted = 0,
    this.rulesVersion = 1,
  });
  int get plannedTasks => taskTotal ?? total;
  int get completedTasks => taskCompleted ?? completed;
  double get taskRatio => plannedTasks == 0 ? 0 : completedTasks / plannedTasks;
  double get habitRatio => habitTotal == 0 ? 0 : habitCompleted / habitTotal;
  bool get star =>
      total > 0 &&
      (rulesVersion == 1
          ? completed * 5 >= total * 4
          : (plannedTasks == 0 || completedTasks * 5 >= plannedTasks * 4) &&
                (habitTotal == 0 || habitCompleted * 5 >= habitTotal * 4));
  double get ratio => total == 0 ? 0 : completed / total;
  Map<String, dynamic> toJson() => {
    'start': start,
    'end': end,
    'total': total,
    'completed': completed,
    'star': star,
    if (rulesVersion == 2) ...{
      'task_total': plannedTasks,
      'task_completed': completedTasks,
      'habit_total': habitTotal,
      'habit_completed': habitCompleted,
    },
  };
  factory WeekAchievement.fromJson(
    Map<String, dynamic> json, {
    int rulesVersion = 1,
  }) {
    final result = WeekAchievement(
      start: json['start'] as String,
      end: json['end'] as String,
      total: json['total'] as int,
      completed: json['completed'] as int,
      rulesVersion: rulesVersion,
      taskTotal: json['task_total'] as int?,
      taskCompleted: json['task_completed'] as int?,
      habitTotal: json['habit_total'] as int? ?? 0,
      habitCompleted: json['habit_completed'] as int? ?? 0,
    );
    if (DateTime.tryParse(result.start) == null ||
        DateTime.tryParse(result.end) == null ||
        result.start.compareTo(result.end) > 0 ||
        result.total < 0 ||
        result.completed < 0 ||
        result.completed > result.total ||
        result.plannedTasks < 0 ||
        result.completedTasks < 0 ||
        result.completedTasks > result.plannedTasks ||
        result.habitTotal < 0 ||
        result.habitCompleted < 0 ||
        result.habitCompleted > result.habitTotal ||
        (rulesVersion == 2 &&
            (result.total != result.plannedTasks + result.habitTotal ||
                result.completed !=
                    result.completedTasks + result.habitCompleted)) ||
        json['star'] != result.star) {
      throw const FormatException('周成就数据无效');
    }
    return result;
  }
}

class MonthAchievement {
  final String month;
  final List<WeekAchievement> weeks;
  final bool settled;
  final int cleaned;
  const MonthAchievement({
    required this.month,
    required this.weeks,
    this.settled = false,
    this.cleaned = 0,
  });
  int get rulesVersion => weeks.firstOrNull?.rulesVersion ?? 1;
  int get taskTotal => weeks.fold(0, (sum, w) => sum + w.plannedTasks);
  int get taskCompleted => weeks.fold(0, (sum, w) => sum + w.completedTasks);
  int get habitTotal => weeks.fold(0, (sum, w) => sum + w.habitTotal);
  int get habitCompleted => weeks.fold(0, (sum, w) => sum + w.habitCompleted);
  int get total => weeks.fold(0, (sum, week) => sum + week.total);
  int get completed => weeks.fold(0, (sum, week) => sum + week.completed);
  int get stars => weeks.where((week) => week.star).length;
  String get status => total == 0
      ? 'empty'
      : weeks.where((w) => w.total > 0).every((w) => w.star)
      ? 'green'
      : 'red';
  Map<String, dynamic> toJson() => {
    'month': month,
    'weeks': weeks.map((w) => w.toJson()).toList(),
    'total': total,
    'completed': completed,
    'stars': stars,
    'status': status,
    'settled': settled,
    'cleaned': cleaned,
    if (rulesVersion == 2) 'rules_version': 2,
  };
  factory MonthAchievement.fromJson(Map<String, dynamic> json) {
    final result = MonthAchievement(
      month: json['month'] as String,
      weeks: (json['weeks'] as List)
          .map(
            (w) => WeekAchievement.fromJson(
              Map<String, dynamic>.from(w as Map),
              rulesVersion: json['rules_version'] as int? ?? 1,
            ),
          )
          .toList(),
      settled: json['settled'] as bool,
      cleaned: json['cleaned'] as int,
    );
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(result.month) ||
        result.weeks.isEmpty ||
        result.weeks.length > 6 ||
        result.cleaned < 0 ||
        result.cleaned > result.taskTotal ||
        json['total'] != result.total ||
        json['completed'] != result.completed ||
        json['stars'] != result.stars ||
        json['status'] != result.status) {
      throw const FormatException('月成就数据无效');
    }
    return result;
  }
}

MonthAchievement calculateAchievement(
  String month,
  Iterable<Task> tasks, {
  Iterable<HabitAchievementPlan> habitPlans = const [],
  Iterable<HabitCheckIn> checkins = const [],
  DateTime? through,
  bool includeHabits = false,
}) {
  final first = DateTime.parse('$month-01');
  final last = DateTime(first.year, first.month + 1, 0);
  final entries = tasks
      .where(
        (task) => !task.deleted && task.dueDate?.startsWith('$month-') == true,
      )
      .toList();
  final weeks = <WeekAchievement>[];
  var start = first;
  while (!start.isAfter(last)) {
    var end = DateTime(start.year, start.month, start.day + 7 - start.weekday);
    if (end.isAfter(last)) {
      end = last;
    }
    final inWeek = entries
        .where(
          (task) =>
              task.dueDate!.compareTo(_date(start)) >= 0 &&
              task.dueDate!.compareTo(_date(end)) <= 0,
        )
        .toList();
    var planned = 0, achieved = 0;
    if (includeHabits) {
      final histories = <String, List<HabitAchievementPlan>>{};
      for (final plan in habitPlans) {
        histories.putIfAbsent(plan.habitId, () => []).add(plan);
      }
      for (final history in histories.values) {
        history.sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom));
      }
      final values = {
        for (final c in checkins) '${c.habitId}:${c.date}': c.value,
      };
      final cutoff = through == null || end.isBefore(through) ? end : through;
      for (
        var day = start;
        !day.isAfter(cutoff);
        day = DateTime(day.year, day.month, day.day + 1)
      ) {
        final key = _date(day);
        for (final entry in histories.entries) {
          final plan = entry.value
              .where((p) => p.effectiveFrom.compareTo(key) <= 0)
              .lastOrNull;
          if (plan == null ||
              !plan.active ||
              !plan.weekdays.contains(day.weekday)) {
            continue;
          }
          planned++;
          if ((values['${entry.key}:$key'] ?? 0) >= plan.goal) {
            achieved++;
          }
        }
      }
    }
    final completed = inWeek.where((task) => task.completed).length;
    weeks.add(
      WeekAchievement(
        start: _date(start),
        end: _date(end),
        total: inWeek.length + planned,
        completed: completed + achieved,
        taskTotal: includeHabits ? inWeek.length : null,
        taskCompleted: includeHabits ? completed : null,
        habitTotal: planned,
        habitCompleted: achieved,
        rulesVersion: includeHabits ? 2 : 1,
      ),
    );
    start = DateTime(end.year, end.month, end.day + 1);
  }
  return MonthAchievement(month: month, weeks: List.unmodifiable(weeks));
}

class AchievementState {
  final String today;
  final String startMonth;
  final int version;
  final String? habitStartedOn;
  final List<HabitAchievementPlan> habitPlans;
  final MonthAchievement live;
  final List<MonthAchievement> settled;
  const AchievementState({
    required this.today,
    required this.startMonth,
    required this.live,
    required this.settled,
    this.version = 1,
    this.habitStartedOn,
    this.habitPlans = const [],
  });
  Map<String, dynamic> toJson() => {
    'version': version,
    'habit_started_on': habitStartedOn,
    'habit_plans': habitPlans.map((p) => p.toJson()).toList(),
    'today': today,
    'start_month': startMonth,
    'live': live.toJson(),
    'settled': settled.map((m) => m.toJson()).toList(),
  };
  factory AchievementState.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 && json['version'] != 2) {
      throw const FormatException('成就数据版本不受支持');
    }
    final result = AchievementState(
      today: json['today'] as String,
      startMonth: json['start_month'] as String,
      version: json['version'] as int,
      habitStartedOn: json['habit_started_on'] as String?,
      habitPlans: (json['habit_plans'] as List? ?? [])
          .map(
            (p) => HabitAchievementPlan.fromJson(
              Map<String, dynamic>.from(p as Map),
            ),
          )
          .toList(),
      live: MonthAchievement.fromJson(
        Map<String, dynamic>.from(json['live'] as Map),
      ),
      settled: List.unmodifiable(
        (json['settled'] as List).map(
          (m) => MonthAchievement.fromJson(Map<String, dynamic>.from(m as Map)),
        ),
      ),
    );
    if (DateTime.tryParse(result.today) == null ||
        !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(result.startMonth) ||
        result.live.settled ||
        result.settled.any((m) => !m.settled) ||
        result.settled.map((m) => m.month).toSet().length !=
            result.settled.length) {
      throw const FormatException('成就同步记录无效');
    }
    return result;
  }
}
