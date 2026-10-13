import 'dart:convert';
import 'dart:io';

import 'sync_core.dart';
import 'task_dates.dart';

const encouragements = [
  '你真棒！',
  '你离梦想又近了一步',
  '今天的努力，闪闪发光',
  '小小的坚持，也有大大的力量',
  '为认真生活的你，鼓掌！',
];

class DailyCelebration {
  const DailyCelebration({required this.day, required this.taskCount});
  final String day;
  final int taskCount;

  String get message {
    final date = DateTime.parse(day);
    return encouragements[date.difference(DateTime(2026)).inDays.abs() % encouragements.length];
  }

  Map<String, dynamic> toJson() => {'day': day, 'task_count': taskCount};

  static DailyCelebration? fromJson(Object? raw) {
    if (raw is! Map || raw['day'] is! String || raw['task_count'] is! int) return null;
    final day = raw['day'] as String;
    final parsed = DateTime.tryParse(day);
    final count = raw['task_count'] as int;
    if (parsed == null || dateKey(parsed) != day || count <= 0) return null;
    return DailyCelebration(day: day, taskCount: count);
  }
}

/// Evaluate the actual serialized, durable checkbox change, never a sync snapshot.
DailyCelebration? celebrationForCompletion(TaskCompletionChange change, DateTime now) {
  final day = dateKey(now);
  if (change.before.completed || change.before.dueDate != day) return null;
  final today = change.tasks.where((task) => !task.deleted && task.dueDate == day).toList();
  if (today.isEmpty || today.any((task) => !task.completed)) return null;
  final changed = today.where((task) => task.id == change.before.id).firstOrNull;
  if (changed == null || !changed.completed) return null;
  return DailyCelebration(day: day, taskCount: today.length);
}

abstract interface class CelebrationStore {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> value);
}

class FileCelebrationStore implements CelebrationStore {
  FileCelebrationStore(this.file);
  final File file;

  @override
  Future<Map<String, dynamic>?> read() async {
    if (!await file.exists()) return null;
    return Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map);
  }

  @override
  Future<void> write(Map<String, dynamic> value) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    await temporary.rename(file.path);
  }
}

class MemoryCelebrationStore implements CelebrationStore {
  Map<String, dynamic>? _state;

  @override
  Future<Map<String, dynamic>?> read() async => _state == null
      ? null : Map<String, dynamic>.from(jsonDecode(jsonEncode(_state)) as Map);

  @override
  Future<void> write(Map<String, dynamic> value) async {
    _state = Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  }
}
