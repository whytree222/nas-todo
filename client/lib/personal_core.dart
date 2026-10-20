import 'dart:convert';

bool validPersonalId(String value) =>
    RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')
        .hasMatch(value);

bool validPersonalDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return false;
  }
  final day = DateTime.tryParse(value);
  return day != null &&
      day.year > 0 &&
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}' ==
          value;
}

List<String> normalizedTags(List<String> tags) {
  if (tags.length > 20 ||
      tags.any((tag) => tag.trim().isEmpty || tag.trim().runes.length > 30)) {
    throw ArgumentError('最多 20 个标签，每个标签需要 1–30 个字符');
  }
  return tags.map((tag) => tag.trim()).toSet().toList()..sort();
}

class TaskRepeatRule {
  const TaskRepeatRule({
    required this.frequency,
    this.interval = 1,
    this.weekdays = const [],
    this.monthDay,
  });
  final String frequency;
  final int interval;
  final List<int> weekdays;
  final int? monthDay;
  void validate() {
    if (!const ['daily', 'weekly', 'monthly'].contains(frequency) ||
        interval < 1 ||
        interval > 365 ||
        weekdays.length > 7 ||
        weekdays.any((day) => day < 1 || day > 7) ||
        (monthDay != null && (monthDay! < 1 || monthDay! > 31))) {
      throw ArgumentError('重复规则无效');
    }
  }

  Map<String, dynamic> toJson() => {
    'frequency': frequency,
    'interval': interval,
    'weekdays': (weekdays.toSet().toList()..sort()),
    'month_day': monthDay,
  };
  factory TaskRepeatRule.fromJson(Map<String, dynamic> json) {
    final rule = TaskRepeatRule(
      frequency: json['frequency'] as String,
      interval: json['interval'] as int,
      weekdays: (json['weekdays'] as List).cast<int>(),
      monthDay: json['month_day'] as int?,
    );
    rule.validate();
    return rule;
  }
}

class HabitDraft {
  const HabitDraft({
    required this.name,
    this.goalType = 'bool',
    this.goal = 1,
    this.weekdays = const [1, 2, 3, 4, 5, 6, 7],
  });
  final String name;
  final String goalType;
  final int goal;
  final List<int> weekdays;
  void validate() {
    if (name.trim().isEmpty || name.trim().runes.length > 80) {
      throw ArgumentError('习惯名称需要 1–80 个字符');
    }
    if (!const ['bool', 'count'].contains(goalType) ||
        goal < 1 ||
        goal > 100000 ||
        (goalType == 'bool' && goal != 1)) {
      throw ArgumentError('习惯目标无效');
    }
    if (weekdays.isEmpty ||
        weekdays.length > 7 ||
        weekdays.any((day) => day < 1 || day > 7)) {
      throw ArgumentError('至少选择一个有效的执行日');
    }
  }

  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'goal_type': goalType,
    'goal': goal,
    'weekdays': (weekdays.toSet().toList()..sort()),
  };
}

class Habit extends HabitDraft {
  const Habit({
    required this.id,
    required super.name,
    super.goalType,
    super.goal,
    super.weekdays,
  });
  final String id;
  factory Habit.fromRecord(PersonalRecord record) {
    final data = record.data;
    return Habit(
      id: record.id,
      name: data['name'] as String,
      goalType: data['goal_type'] as String,
      goal: data['goal'] as int,
      weekdays: (data['weekdays'] as List).cast<int>(),
    );
  }
}

class HabitCheckIn {
  const HabitCheckIn({
    required this.id,
    required this.habitId,
    required this.date,
    required this.value,
  });
  final String id;
  final String habitId;
  final String date;
  final int value;
  factory HabitCheckIn.fromRecord(PersonalRecord record) => HabitCheckIn(
    id: record.id,
    habitId: record.data['habit_id'] as String,
    date: record.data['date'] as String,
    value: record.data['value'] as int,
  );
}

/// Immutable, versioned records share the task database's identity and durability.
class PersonalRecord {
  PersonalRecord({
    required this.kind,
    required this.id,
    required Map<String, dynamic> data,
    this.deleted = false,
    this.version = 0,
    this.changeSeq = 0,
    this.updatedAt = '',
  }) : data = Map<String, dynamic>.unmodifiable(
         jsonDecode(jsonEncode(data)) as Map<String, dynamic>,
       );
  final String kind;
  final String id;
  final Map<String, dynamic> data;
  final bool deleted;
  final int version;
  final int changeSeq;
  final String updatedAt;
  String get key => '$kind/$id';
  Map<String, dynamic> toJson() => {
    'kind': kind,
    'id': id,
    'data': data,
    'deleted': deleted,
    'version': version,
    'change_seq': changeSeq,
    'updated_at': updatedAt,
  };
  factory PersonalRecord.fromJson(Map<String, dynamic> json) {
    final record = PersonalRecord(
      kind: json['kind'] as String,
      id: json['id'] as String,
      data: Map<String, dynamic>.from(json['data'] as Map),
      deleted: json['deleted'] as bool,
      version: json['version'] as int,
      changeSeq: json['change_seq'] as int,
      updatedAt: json['updated_at'] as String,
    );
    validatePersonalData(record.kind, record.id, record.data);
    if (record.version < 0 || record.changeSeq < 0) {
      throw const FormatException('个人记录版本无效');
    }
    return record;
  }
  PersonalRecord withVersion(int version, int sequence) => PersonalRecord(
    kind: kind,
    id: id,
    data: data,
    deleted: deleted,
    version: version,
    changeSeq: sequence,
    updatedAt: updatedAt,
  );
}

class PersonalConflict {
  const PersonalConflict({
    required this.kind,
    required this.id,
    this.local,
    this.remote,
  });
  final String kind;
  final String id;
  final PersonalRecord? local;
  final PersonalRecord? remote;
  String get key => '$kind/$id';
  Map<String, dynamic> toJson() => {
    'kind': kind,
    'id': id,
    'local': local?.toJson(),
    'remote': remote?.toJson(),
  };
  factory PersonalConflict.fromJson(Map<String, dynamic> json) =>
      PersonalConflict(
        kind: json['kind'] as String,
        id: json['id'] as String,
        local: json['local'] == null
            ? null
            : PersonalRecord.fromJson(
                Map<String, dynamic>.from(json['local'] as Map),
              ),
        remote: json['remote'] == null
            ? null
            : PersonalRecord.fromJson(
                Map<String, dynamic>.from(json['remote'] as Map),
              ),
      );
}

void validatePersonalData(String kind, String id, Map<String, dynamic> data) {
  if (kind == 'habit') {
    if (!validPersonalId(id)) {
      throw ArgumentError('习惯标识无效');
    }
    HabitDraft(
      name: data['name'] as String,
      goalType: data['goal_type'] as String,
      goal: data['goal'] as int,
      weekdays: (data['weekdays'] as List).cast<int>(),
    ).validate();
  } else if (kind == 'habit_checkin') {
    final habit = data['habit_id'] as String;
    final day = data['date'] as String;
    final value = data['value'] as int;
    if (!validPersonalId(habit) ||
        !validPersonalDate(day) ||
        id != '$habit:$day' ||
        value < 0 ||
        value > 100000) {
      throw ArgumentError('习惯打卡记录无效');
    }
  } else if (kind == 'task_meta') {
    if (!validPersonalId(id) ||
        (data['parent_id'] != null &&
            !validPersonalId(data['parent_id'] as String))) {
      throw ArgumentError('父待办标识无效');
    }
    normalizedTags((data['tags'] as List).cast<String>());
    if (data['repeat_rule'] != null) {
      TaskRepeatRule.fromJson(
        Map<String, dynamic>.from(data['repeat_rule'] as Map),
      );
    }
  } else {
    throw const FormatException('未知个人数据集合');
  }
}
