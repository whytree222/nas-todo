import 'personal_core.dart';

/// A dated plan revision preserves yesterday's schedule when a habit is edited.
class HabitAchievementPlan {
  const HabitAchievementPlan({
    required this.habitId,
    required this.effectiveFrom,
    required this.goal,
    required this.weekdays,
    this.active = true,
  });
  final String habitId, effectiveFrom;
  final int goal;
  final List<int> weekdays;
  final bool active;
  factory HabitAchievementPlan.fromJson(Map<String, dynamic> value) {
    final plan = HabitAchievementPlan(
      habitId: value['habit_id'] as String,
      effectiveFrom: value['effective_from'] as String,
      goal: value['goal'] as int,
      weekdays: (value['weekdays'] as List).cast<int>(),
      active: value['active'] as bool,
    );
    if (!validPersonalId(plan.habitId) ||
        !validPersonalDate(plan.effectiveFrom) ||
        plan.goal < 1 ||
        plan.goal > 100000 ||
        plan.weekdays.isEmpty ||
        plan.weekdays.any((d) => d < 1 || d > 7)) {
      throw const FormatException('习惯计划历史无效');
    }
    return plan;
  }
  Map<String, dynamic> toJson() => {
    'habit_id': habitId,
    'effective_from': effectiveFrom,
    'goal': goal,
    'weekdays': weekdays,
    'active': active,
  };
}
