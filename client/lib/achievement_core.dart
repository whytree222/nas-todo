import 'sync_core.dart';

DateTime achievementToday() {
  final now = DateTime.now().toUtc().add(const Duration(hours: 8));
  return DateTime(now.year, now.month, now.day);
}

String achievementMonth(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
String _date(DateTime date) => '${achievementMonth(date)}-${date.day.toString().padLeft(2, '0')}';

class WeekAchievement {
  final String start;
  final String end;
  final int total;
  final int completed;
  const WeekAchievement({required this.start, required this.end, required this.total, required this.completed});
  bool get star => total > 0 && completed * 5 >= total * 4;
  double get ratio => total == 0 ? 0 : completed / total;
  Map<String, dynamic> toJson() => {'start': start, 'end': end, 'total': total, 'completed': completed, 'star': star};
  factory WeekAchievement.fromJson(Map<String, dynamic> json) {
    final result = WeekAchievement(start: json['start'] as String, end: json['end'] as String,
      total: json['total'] as int, completed: json['completed'] as int);
    if (DateTime.tryParse(result.start) == null || DateTime.tryParse(result.end) == null ||
        result.start.compareTo(result.end) > 0 || result.total < 0 || result.completed < 0 ||
        result.completed > result.total || json['star'] != result.star) {
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
  const MonthAchievement({required this.month, required this.weeks, this.settled = false, this.cleaned = 0});
  int get total => weeks.fold(0, (sum, week) => sum + week.total);
  int get completed => weeks.fold(0, (sum, week) => sum + week.completed);
  int get stars => weeks.where((week) => week.star).length;
  String get status => total == 0 ? 'empty' : weeks.where((w) => w.total > 0).every((w) => w.star) ? 'green' : 'red';
  Map<String, dynamic> toJson() => {'month': month, 'weeks': weeks.map((w) => w.toJson()).toList(),
    'total': total, 'completed': completed, 'stars': stars, 'status': status, 'settled': settled, 'cleaned': cleaned};
  factory MonthAchievement.fromJson(Map<String, dynamic> json) {
    final result = MonthAchievement(month: json['month'] as String,
      weeks: (json['weeks'] as List).map((w) => WeekAchievement.fromJson(Map<String, dynamic>.from(w as Map))).toList(),
      settled: json['settled'] as bool, cleaned: json['cleaned'] as int);
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(result.month) || result.weeks.isEmpty ||
        result.weeks.length > 6 || result.cleaned < 0 || result.cleaned > result.total ||
        json['total'] != result.total || json['completed'] != result.completed ||
        json['stars'] != result.stars || json['status'] != result.status) {
      throw const FormatException('月成就数据无效');
    }
    return result;
  }
}

MonthAchievement calculateAchievement(String month, Iterable<Task> tasks) {
  final first = DateTime.parse('$month-01');
  final last = DateTime(first.year, first.month + 1, 0);
  final entries = tasks.where((task) => !task.deleted && task.dueDate?.startsWith('$month-') == true).toList();
  final weeks = <WeekAchievement>[];
  var start = first;
  while (!start.isAfter(last)) {
    var end = DateTime(start.year, start.month, start.day + 7 - start.weekday);
    if (end.isAfter(last)) end = last;
    final inWeek = entries.where((task) => task.dueDate!.compareTo(_date(start)) >= 0 && task.dueDate!.compareTo(_date(end)) <= 0).toList();
    weeks.add(WeekAchievement(start: _date(start), end: _date(end), total: inWeek.length,
      completed: inWeek.where((task) => task.completed).length));
    start = DateTime(end.year, end.month, end.day + 1);
  }
  return MonthAchievement(month: month, weeks: List.unmodifiable(weeks));
}

class AchievementState {
  final String today;
  final String startMonth;
  final MonthAchievement live;
  final List<MonthAchievement> settled;
  const AchievementState({required this.today, required this.startMonth, required this.live, required this.settled});
  Map<String, dynamic> toJson() => {'version': 1, 'today': today, 'start_month': startMonth,
    'live': live.toJson(), 'settled': settled.map((m) => m.toJson()).toList()};
  factory AchievementState.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) throw const FormatException('成就数据版本不受支持');
    final result = AchievementState(today: json['today'] as String, startMonth: json['start_month'] as String,
      live: MonthAchievement.fromJson(Map<String, dynamic>.from(json['live'] as Map)),
      settled: List.unmodifiable((json['settled'] as List).map((m) => MonthAchievement.fromJson(Map<String, dynamic>.from(m as Map)))));
    if (DateTime.tryParse(result.today) == null || !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(result.startMonth) ||
        result.live.settled || result.settled.any((m) => !m.settled) ||
        result.settled.map((m) => m.month).toSet().length != result.settled.length) {
      throw const FormatException('成就同步记录无效');
    }
    return result;
  }
}
