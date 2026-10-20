import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'achievement_core.dart';
import 'personal_core.dart';
export 'personal_core.dart' show TaskRepeatRule;
part 'personal_sync.dart';

/// Storage must finish durably before its returned future completes.
abstract interface class DataStore {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> state);
}

abstract interface class SyncTransport {
  Future<Map<String, dynamic>> sync(Map<String, dynamic> payload);
}

abstract interface class PersonalSyncTransport {
  Future<Map<String, dynamic>> syncPersonal(Map<String, dynamic> payload);
}

class SyncServerException implements Exception {
  final String code;
  final String message;
  SyncServerException(this.code, this.message);
  @override
  String toString() => message;
}

String newId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class TaskDraft {
  final String title;
  final String note;
  final String listName;
  final String? dueDate;
  final int priority;
  final bool completed;
  final String? parentId;
  final List<String> tags;
  final TaskRepeatRule? repeatRule;
  const TaskDraft({
    required this.title,
    this.note = '',
    this.listName = '收件箱',
    this.dueDate,
    this.priority = 0,
    this.completed = false,
    this.parentId,
    this.tags = const [],
    this.repeatRule,
  });

  factory TaskDraft.fromTask(Task task) => TaskDraft(
    title: task.title,
    note: task.note,
    listName: task.listName,
    dueDate: task.dueDate,
    priority: task.priority,
    completed: task.completed,
    parentId: task.parentId,
    tags: task.tags,
    repeatRule: task.repeatRule,
  );

  Map<String, dynamic> toBaseJson() => {
    'title': title.trim(),
    'note': note,
    'list_name': listName.trim(),
    'due_date': dueDate,
    'priority': priority,
    'completed': completed,
  };
  Map<String, dynamic> toMetadata() => {
    'parent_id': parentId,
    'tags': normalizedTags(tags),
    'repeat_rule': repeatRule?.toJson(),
  };
  bool get hasMetadata =>
      parentId != null || tags.isNotEmpty || repeatRule != null;
  Map<String, dynamic> toJson() => {
    ...toBaseJson(),
    if (hasMetadata) ...toMetadata(),
  };

  TaskDraft copyWith({
    String? title,
    String? note,
    String? listName,
    String? dueDate,
    int? priority,
    bool? completed,
    String? parentId,
    List<String>? tags,
    TaskRepeatRule? repeatRule,
    bool clearDueDate = false,
    bool clearParentId = false,
    bool clearRepeatRule = false,
  }) => TaskDraft(
    title: title ?? this.title,
    note: note ?? this.note,
    listName: listName ?? this.listName,
    dueDate: clearDueDate ? null : dueDate ?? this.dueDate,
    priority: priority ?? this.priority,
    completed: completed ?? this.completed,
    parentId: clearParentId ? null : parentId ?? this.parentId,
    tags: tags ?? this.tags,
    repeatRule: clearRepeatRule ? null : repeatRule ?? this.repeatRule,
  );

  void validate() {
    if (title.trim().isEmpty || title.trim().runes.length > 200) {
      throw ArgumentError('标题需要 1–200 个字符');
    }
    if (note.runes.length > 10000) {
      throw ArgumentError('备注最多 10000 个字符');
    }
    if (listName.trim().isEmpty || listName.trim().runes.length > 60) {
      throw ArgumentError('清单名称需要 1–60 个字符');
    }
    if (priority < 0 || priority > 2) {
      throw ArgumentError('优先级无效');
    }
    if (dueDate != null && !validPersonalDate(dueDate!)) {
      throw ArgumentError('截止日期无效');
    }
    if (parentId != null && !validPersonalId(parentId!)) {
      throw ArgumentError('父待办标识无效');
    }
    normalizedTags(tags);
    repeatRule?.validate();
    if (repeatRule != null && dueDate == null) {
      throw ArgumentError('重复待办需要安排日期');
    }
  }
}

class Task {
  final String id;
  final String title;
  final String note;
  final String listName;
  final String? dueDate;
  final int priority;
  final bool completed;
  final bool deleted;
  final int version;
  final String updatedAt;
  final int changeSeq;
  final String? parentId;
  final List<String> tags;
  final TaskRepeatRule? repeatRule;
  const Task({
    required this.id,
    required this.title,
    this.note = '',
    this.listName = '收件箱',
    this.dueDate,
    this.priority = 0,
    this.completed = false,
    this.deleted = false,
    this.version = 0,
    this.updatedAt = '',
    this.changeSeq = 0,
    this.parentId,
    this.tags = const [],
    this.repeatRule,
  });

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'] as String,
    title: json['title'] as String,
    note: json['note'] as String,
    listName: json['list_name'] as String,
    dueDate: json['due_date'] as String?,
    priority: json['priority'] as int,
    completed: json['completed'] as bool,
    deleted: json['deleted'] as bool,
    version: json['version'] as int,
    updatedAt: json['updated_at'] as String,
    changeSeq: json['change_seq'] as int,
    parentId: json['parent_id'] as String?,
    tags: List<String>.unmodifiable(
      (json['tags'] as List? ?? []).cast<String>(),
    ),
    repeatRule: json['repeat_rule'] == null
        ? null
        : TaskRepeatRule.fromJson(
            Map<String, dynamic>.from(json['repeat_rule'] as Map),
          ),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'note': note,
    'list_name': listName,
    'due_date': dueDate,
    'priority': priority,
    'completed': completed,
    if (parentId != null || tags.isNotEmpty || repeatRule != null)
      ...TaskDraft.fromTask(this).toMetadata(),
    'deleted': deleted,
    'version': version,
    'updated_at': updatedAt,
    'change_seq': changeSeq,
  };

  Task withMetadata(Map<String, dynamic> metadata) => Task(
    id: id,
    title: title,
    note: note,
    listName: listName,
    dueDate: dueDate,
    priority: priority,
    completed: completed,
    deleted: deleted,
    version: version,
    updatedAt: updatedAt,
    changeSeq: changeSeq,
    parentId: metadata['parent_id'] as String?,
    tags: List<String>.unmodifiable((metadata['tags'] as List).cast<String>()),
    repeatRule: metadata['repeat_rule'] == null
        ? null
        : TaskRepeatRule.fromJson(
            Map<String, dynamic>.from(metadata['repeat_rule'] as Map),
          ),
  );

  Task copyWith({
    bool? completed,
    bool? deleted,
    int? version,
    int? changeSeq,
  }) => Task(
    id: id,
    title: title,
    note: note,
    listName: listName,
    dueDate: dueDate,
    priority: priority,
    completed: completed ?? this.completed,
    deleted: deleted ?? this.deleted,
    version: version ?? this.version,
    updatedAt: updatedAt,
    changeSeq: changeSeq ?? this.changeSeq,
    parentId: parentId,
    tags: tags,
    repeatRule: repeatRule,
  );
}

class SyncConflict {
  final String taskId;
  final Task? local;
  final Task? remote;
  const SyncConflict({required this.taskId, this.local, this.remote});
  Map<String, dynamic> toJson() => {
    'task_id': taskId,
    'local': local?.toJson(),
    'remote': remote?.toJson(),
  };
  factory SyncConflict.fromJson(Map<String, dynamic> json) => SyncConflict(
    taskId: json['task_id'] as String,
    local: json['local'] == null ? null : Task.fromJson(_map(json['local'])),
    remote: json['remote'] == null ? null : Task.fromJson(_map(json['remote'])),
  );
}

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value as Map);

/// Personal offline-first sync. Writes and syncs are serialized so an in-flight
/// acknowledgement cannot erase a concurrent local edit. Conflicts are durable.
/// The before state is read inside the sync queue, and tasks follow durable save.
class TaskCompletionChange {
  TaskCompletionChange({required this.before, required List<Task> tasks})
    : tasks = List.unmodifiable(tasks);
  final Task before;
  final List<Task> tasks;
}

class SyncEngine {
  final DataStore store;
  final SyncTransport transport;
  final Map<String, Task> _tasks = {};
  final List<Map<String, dynamic>> _operations = [];
  final Set<String> _attemptedIds = {};
  final Map<String, SyncConflict> _conflicts = {};
  final Map<String, PersonalRecord> _personalRecords = {};
  final List<Map<String, dynamic>> _personalOps = [];
  final Set<String> _personalAttempted = {};
  final Set<String> _personalTaskReleases = {};
  final Map<String, PersonalConflict> _personalConflicts = {};
  int _personalCursor = 0;
  bool _personalSupported = false;
  Future<void> _tail = Future<void>.value();
  String? _instanceId;
  int _cursor = 0;
  DateTime? _lastSyncedAt;
  bool _loaded = false;
  AchievementState? _achievement;
  bool _achievementsSupported = false;

  SyncEngine(this.store, this.transport);
  List<Task> get tasks => List.unmodifiable(
    _tasks.values.where((t) => !t.deleted).map(_decorateTask),
  );
  List<SyncConflict> get conflicts => List.unmodifiable(_conflicts.values);
  int get pendingCount =>
      _operations.length + _personalOps.length + _personalTaskReleases.length;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  AchievementState? get achievement => _achievement;
  bool get achievementsSupported => _achievementsSupported;

  Future<T> _serial<T>(Future<T> Function() action) {
    final future = _tail.then((_) => action());
    _tail = future.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return future;
  }

  Future<void> load() => _serial(() async {
    if (_loaded) {
      return;
    }
    final state = await store.read();
    if (state != null) {
      _restore(state);
    }
    _loaded = true;
  });

  void _checkLoaded() {
    if (!_loaded) {
      throw StateError('请先加载本地数据');
    }
  }

  Map<String, dynamic> _state() => {
    'schema': 1,
    'instance_id': _instanceId,
    'cursor': _cursor,
    'tasks': _tasks.values.map((t) => t.toJson()).toList(),
    'operations': _operations,
    'attempted_ids': _attemptedIds.toList(),
    'conflicts': _conflicts.values.map((c) => c.toJson()).toList(),
    'last_synced_at': _lastSyncedAt?.toUtc().toIso8601String(),
    'achievement': _achievement?.toJson(),
    'achievements_supported': _achievementsSupported,
    ..._personalState(),
  };

  void _restore(Map<String, dynamic> state) {
    if (state['schema'] != 1) {
      throw StateError('本地数据版本不受支持');
    }
    _achievement = state['achievement'] == null
        ? null
        : AchievementState.fromJson(_map(state['achievement']));
    _achievementsSupported = state['achievements_supported'] as bool? ?? false;
    _instanceId = state['instance_id'] as String?;
    _cursor = state['cursor'] as int;
    if (_cursor < 0) {
      throw StateError('本地同步记录损坏');
    }
    _lastSyncedAt = state['last_synced_at'] == null
        ? null
        : DateTime.parse(state['last_synced_at'] as String);
    _tasks.clear();
    for (final raw in state['tasks'] as List) {
      final task = Task.fromJson(_map(raw));
      _tasks[task.id] = task;
    }
    _operations
      ..clear()
      ..addAll((state['operations'] as List).map(_map));
    _attemptedIds
      ..clear()
      ..addAll((state['attempted_ids'] as List? ?? []).cast<String>());
    _conflicts.clear();
    for (final raw in state['conflicts'] as List) {
      final conflict = SyncConflict.fromJson(_map(raw));
      _conflicts[conflict.taskId] = conflict;
    }
    _restorePersonal(state);
  }

  Future<void> _commit(void Function() change) async {
    // Deep copy: the outbox contains nested mutable JSON objects.
    final before = _map(jsonDecode(jsonEncode(_state())));
    try {
      change();
      await store.write(_state());
    } catch (_) {
      _restore(before);
      rethrow;
    }
  }

  Future<void> saveTask(TaskDraft draft, {String? id}) =>
      _serial(() => _saveDraft(draft, id: id));

  Future<TaskCompletionChange> setCompleted(String id, bool completed) =>
      _serial(() async {
        _checkLoaded();
        final task = _tasks[id] == null ? null : _decorateTask(_tasks[id]!);
        if (task == null || task.deleted) {
          throw StateError('这条待办已删除');
        }
        // Change only completion, keeping content freshly pulled by a preceding
        // in-flight sync. A checkbox must never write an old title or old note.
        await _saveDraft(
          TaskDraft.fromTask(task).copyWith(completed: completed),
          id: id,
        );
        return TaskCompletionChange(before: task, tasks: tasks);
      });

  Future<void> scheduleTask(String id, String date) => _serial(() async {
    _checkLoaded();
    final task = _tasks[id] == null ? null : _decorateTask(_tasks[id]!);
    if (task == null || task.deleted) {
      throw StateError('这条待办已删除');
    }
    if (_conflicts.containsKey(id)) {
      throw StateError('请先处理这条待办的同步冲突');
    }
    if (task.dueDate == date) {
      return;
    }
    if (task.dueDate != null) {
      throw StateError('这条待办已有日期，请刷新后重试');
    }
    // Read inside the sync queue: dragging changes only the date, never content
    // or completion freshly received from the NAS while the drag was underway.
    await _saveDraft(TaskDraft.fromTask(task).copyWith(dueDate: date), id: id);
  });

  Future<void> setTaskPlacement(
    String id, {
    String? listName,
    int? priority,
    String? dueDate,
    bool clearDueDate = false,
    bool requireIncomplete = false,
  }) => _serial(() async {
    final task = _placementTask(id);
    if (requireIncomplete && task.completed) {
      throw StateError('已完成的待办不能移动');
    }
    if (dueDate != null && clearDueDate) {
      throw ArgumentError('日期不能同时设置和清除');
    }
    await _placeTask(
      task,
      listName: listName,
      priority: priority,
      dueDate: dueDate,
      clearDueDate: clearDueDate,
    );
  });

  Future<void> setTaskQuadrant(
    String id, {
    required bool important,
    required bool urgent,
    required String today,
  }) => _serial(() async {
    // Resolve the quadrant intent after any pending NAS pull. Computing fields
    // from a drag snapshot could clear a future date just received from the NAS.
    final task = _placementTask(id);
    if (task.completed) {
      throw StateError('已完成的待办不能调整四象限');
    }
    TaskDraft(title: task.title, dueDate: today).validate();
    final isUrgent =
        task.dueDate != null && task.dueDate!.compareTo(today) <= 0;
    final moveRepeatedToTomorrow =
        !urgent && isUrgent && task.repeatRule != null;
    final day = DateTime.parse(today);
    final tomorrow = DateTime(
      day.year,
      day.month,
      day.day + 1,
    ).toIso8601String().substring(0, 10);
    await _placeTask(
      task,
      priority: important ? (task.priority == 2 ? 2 : 1) : 0,
      dueDate: moveRepeatedToTomorrow
          ? tomorrow
          : urgent && !isUrgent
          ? today
          : null,
      clearDueDate: !urgent && isUrgent && !moveRepeatedToTomorrow,
    );
  });

  Task _placementTask(String id) {
    _checkLoaded();
    final task = _tasks[id] == null ? null : _decorateTask(_tasks[id]!);
    if (task == null || task.deleted) {
      throw StateError('这条待办已删除');
    }
    if (_conflicts.containsKey(id)) {
      throw StateError('请先处理这条待办的同步冲突');
    }
    return task;
  }

  Future<void> _placeTask(
    Task task, {
    String? listName,
    int? priority,
    String? dueDate,
    bool clearDueDate = false,
  }) async {
    final draft = TaskDraft.fromTask(task).copyWith(
      listName: listName,
      priority: priority,
      dueDate: dueDate,
      clearDueDate: clearDueDate,
    );
    draft.validate();
    if (draft.listName.trim() == task.listName &&
        draft.priority == task.priority &&
        draft.dueDate == task.dueDate) {
      return;
    }
    await _saveDraft(draft, id: task.id);
  }

  Future<void> _saveDraft(TaskDraft draft, {String? id}) async {
    _checkLoaded();
    draft.validate();
    final taskId = id ?? newId();
    _validateParent(taskId, draft.parentId);
    if (_conflicts.containsKey(taskId)) {
      throw StateError('请先处理这条待办的同步冲突');
    }
    final old = _tasks[taskId];
    if (id != null && (old == null || old.deleted)) {
      throw StateError('这条待办已删除');
    }
    final queued = _operations
        .where((op) => op['task_id'] == taskId)
        .firstOrNull;
    final base = queued?['base_version'] as int? ?? old?.version ?? 0;
    final data = draft.toBaseJson();
    final task = Task(
      id: taskId,
      title: data['title'] as String,
      note: draft.note,
      listName: data['list_name'] as String,
      dueDate: draft.dueDate,
      priority: draft.priority,
      completed: draft.completed,
      version: old?.version ?? 0,
      changeSeq: old?.changeSeq ?? 0,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    await _commit(() {
      _tasks[taskId] = task;
      _removeUnsent(taskId);
      _operations.add(_operation(task, base, 'upsert'));
      _putTaskMetadata(taskId, draft);
    });
  }

  Map<String, dynamic> _operation(Task task, int base, String action) => {
    'op_id': newId(),
    'task_id': task.id,
    'base_version': base,
    'action': action,
    'data': TaskDraft.fromTask(task).toBaseJson(),
  };

  void _removeUnsent(String taskId) => _operations.removeWhere(
    (op) => op['task_id'] == taskId && !_attemptedIds.contains(op['op_id']),
  );

  void _removeTaskOperations(String taskId) {
    for (final op in _operations.where((op) => op['task_id'] == taskId)) {
      _attemptedIds.remove(op['op_id']);
    }
    _operations.removeWhere((op) => op['task_id'] == taskId);
  }

  Future<void> deleteTask(String id) => _serial(() async {
    _checkLoaded();
    if (_conflicts.containsKey(id)) {
      throw StateError('请先处理这条待办的同步冲突');
    }
    final old = _tasks[id];
    if (old == null || old.deleted) {
      return;
    }
    final queued = _operations.where((op) => op['task_id'] == id).firstOrNull;
    final base = queued?['base_version'] as int? ?? old.version;
    await _commit(() {
      _promoteLocalChildren(id);
      // A never-sent offline creation can be cancelled entirely. Once attempted,
      // preserve it unchanged, as the NAS may have committed a lost response.
      if (base == 0 &&
          queued != null &&
          !_attemptedIds.contains(queued['op_id'])) {
        _tasks.remove(id);
        _removeTaskOperations(id);
        _personalRecords.remove('task_meta/$id');
        _removePersonalOps('task_meta', id);
        return;
      }
      _tasks[id] = old.copyWith(deleted: true);
      _removeUnsent(id);
      _operations.add(_operation(old, base, 'delete'));
    });
  });

  Future<void> sync() => _serial(() async {
    _checkLoaded();
    var capabilityProbe =
        !_personalSupported &&
        _personalOps.isNotEmpty &&
        transport is PersonalSyncTransport;
    // Drain >100 local edits in bounded batches. Every acknowledged batch is
    // independently durable; an interrupted later batch is safe to retry.
    do {
      final batch = <Map<String, dynamic>>[];
      var batchBytes = 256;
      final batchTasks = <String>{};
      for (final operation in _operations) {
        if (capabilityProbe) {
          break;
        }
        if (batch.length == 100) {
          break;
        }
        final taskId = operation['task_id'] as String;
        if (batchTasks.contains(taskId)) {
          continue;
        }
        final size = utf8.encode(jsonEncode(operation)).length + 1;
        if (batchBytes + size > 900000) {
          break;
        }
        batch.add(_map(operation));
        batchTasks.add(taskId);
        batchBytes += size;
      }
      if (batch.isEmpty && _operations.isNotEmpty && !capabilityProbe) {
        throw StateError('本地修改超过单次同步限制，请保留数据文件并检查内容');
      }
      if (batch.any((op) => !_attemptedIds.contains(op['op_id']))) {
        await _commit(
          () => _attemptedIds.addAll(batch.map((op) => op['op_id'] as String)),
        );
      }
      var requestCursor = _cursor;
      final deferRepeats =
          _personalSupported && transport is PersonalSyncTransport;
      Map<String, dynamic> response;
      try {
        response = await transport.sync({
          'instance_id': _instanceId,
          'cursor': requestCursor,
          'operations': batch,
          if (deferRepeats) 'defer_repeats': true,
        });
      } on SyncServerException catch (error) {
        if (error.code != 'future_cursor' || _instanceId == null) {
          rethrow;
        }
        requestCursor = 0;
        response = await transport.sync({
          'instance_id': _instanceId,
          'cursor': 0,
          'operations': batch,
          if (deferRepeats) 'defer_repeats': true,
        });
      }
      final instance = response['instance_id'] as String;
      final cursor = response['cursor'] as int;
      if (instance.isEmpty ||
          (_instanceId != null && instance != _instanceId)) {
        throw SyncServerException(
          'instance_mismatch',
          'NAS 数据库与已绑定的数据库不同，请检查服务地址',
        );
      }
      if (cursor < requestCursor) {
        throw StateError('NAS 返回的同步进度无效');
      }
      final changes = (response['changes'] as List)
          .map((raw) => Task.fromJson(_map(raw)))
          .toList();
      final results = (response['results'] as List).map(_map).toList();
      final achievement = response['achievement'] == null
          ? null
          : AchievementState.fromJson(_map(response['achievement']));
      final sentIds = batch.map((op) => op['op_id'] as String).toSet();
      final seen = <String>{};
      for (final result in results) {
        final opId = result['op_id'] as String;
        if (!sentIds.contains(opId) ||
            !seen.add(opId) ||
            !['applied', 'conflict'].contains(result['status'])) {
          throw StateError('NAS 返回的修改确认无效');
        }
        if (result['task'] != null) {
          final task = Task.fromJson(_map(result['task']));
          final operation = batch.firstWhere((op) => op['op_id'] == opId);
          if (task.id != operation['task_id']) {
            throw StateError('NAS 返回了错误的待办记录');
          }
        }
      }
      if (seen.length != sentIds.length) {
        throw StateError('NAS 未确认全部修改，稍后重试');
      }
      await _commit(() {
        _instanceId = instance;
        if (achievement != null) {
          _achievement = achievement;
        }
        _achievementsSupported = achievement != null;
        _personalSupported = response['personal_sync'] == 1;
        for (final result in results) {
          final op = batch.firstWhere((op) => op['op_id'] == result['op_id']);
          final taskId = op['task_id'] as String;
          final remote = result['task'] == null
              ? null
              : Task.fromJson(_map(result['task']));
          _operations.removeWhere(
            (pending) => pending['op_id'] == result['op_id'],
          );
          _attemptedIds.remove(result['op_id']);
          if (result['status'] == 'conflict') {
            _conflicts[taskId] = SyncConflict(
              taskId: taskId,
              local: _tasks[taskId],
              remote: remote,
            );
            _removeTaskOperations(taskId);
          } else {
            if (deferRepeats && op['action'] == 'upsert') {
              _personalTaskReleases.add(taskId);
            }
            final next = _operations
                .where((pending) => pending['task_id'] == taskId)
                .firstOrNull;
            if (next != null) {
              // This operation has never been sent. Its base is now the actual
              // acknowledgement version of its predecessor, not a prediction.
              next['base_version'] = remote?.version ?? 0;
              final local = _tasks[taskId];
              if (local != null) {
                _tasks[taskId] = local.copyWith(
                  version: remote?.version ?? 0,
                  changeSeq: remote?.changeSeq ?? 0,
                );
              }
            } else if (remote != null) {
              _acceptRemote(remote, force: requestCursor == 0);
            } else {
              _tasks.remove(taskId);
            }
          }
        }
        for (final remote in changes) {
          final conflict = _conflicts[remote.id];
          if (conflict != null) {
            if (requestCursor == 0 ||
                conflict.remote == null ||
                remote.version >= conflict.remote!.version) {
              _conflicts[remote.id] = SyncConflict(
                taskId: remote.id,
                local: conflict.local,
                remote: remote,
              );
            }
            continue;
          }
          final queued = _operations
              .where((op) => op['task_id'] == remote.id)
              .firstOrNull;
          if (queued != null) {
            if (queued['base_version'] != remote.version) {
              _conflicts[remote.id] = SyncConflict(
                taskId: remote.id,
                local: _tasks[remote.id],
                remote: remote,
              );
              _removeTaskOperations(remote.id);
            }
            continue;
          }
          _acceptRemote(remote, force: requestCursor == 0);
        }
        if (requestCursor == 0) {
          final snapshotIds = changes.map((t) => t.id).toSet();
          for (final id in _conflicts.keys.toList()) {
            if (!snapshotIds.contains(id)) {
              final conflict = _conflicts[id]!;
              _conflicts[id] = SyncConflict(taskId: id, local: conflict.local);
            }
          }
          final pendingIds = _operations.map((op) => op['task_id']).toSet();
          _tasks.removeWhere(
            (id, _) =>
                !snapshotIds.contains(id) &&
                !pendingIds.contains(id) &&
                !_conflicts.containsKey(id),
          );
        }
        _cursor = cursor;
        _lastSyncedAt = DateTime.now().toUtc();
      });
      capabilityProbe = false;
    } while (_operations.isNotEmpty);
    await _syncPersonal();
  });

  void _acceptRemote(Task remote, {bool force = false}) {
    final cached = _tasks[remote.id];
    if (force || cached == null || remote.version >= cached.version) {
      _tasks[remote.id] = remote;
    }
  }

  Future<void> resolveConflict(
    String taskId, {
    required bool keepLocal,
  }) => _serial(() async {
    _checkLoaded();
    final conflict = _conflicts[taskId];
    if (conflict == null) {
      return;
    }
    await _commit(() {
      _conflicts.remove(taskId);
      _removeTaskOperations(taskId);
      final remote = conflict.remote;
      if (!keepLocal || conflict.local == null) {
        if (remote == null) {
          _tasks.remove(taskId);
        } else {
          _tasks[taskId] = remote;
        }
        return;
      }
      final local = conflict.local!;
      if (local.deleted && (remote == null || remote.deleted)) {
        if (remote == null) {
          _tasks.remove(taskId);
        } else {
          _tasks[taskId] = remote;
        }
        return;
      }
      // Server tombstones never resurrect: choosing a local edit creates a new
      // task ID and leaves the old deletion intact on every other device.
      final recreate = !local.deleted && remote?.deleted == true;
      final id = recreate ? newId() : taskId;
      if (recreate) {
        _tasks[taskId] = remote!;
      }
      final chosen = Task(
        id: id,
        title: local.title,
        note: local.note,
        listName: local.listName,
        dueDate: local.dueDate,
        priority: local.priority,
        completed: local.completed,
        deleted: local.deleted,
        version: recreate ? 0 : (remote?.version ?? 0),
        updatedAt: DateTime.now().toUtc().toIso8601String(),
        changeSeq: recreate ? 0 : (remote?.changeSeq ?? 0),
      );
      _tasks[id] = chosen;
      if (recreate) {
        _putTaskMetadata(id, TaskDraft.fromTask(_decorateTask(local)));
      }
      _operations.add(
        _operation(
          chosen,
          chosen.version,
          chosen.deleted ? 'delete' : 'upsert',
        ),
      );
    });
  });
}
