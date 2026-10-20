part of 'sync_core.dart';

String _canonicalPersonal(Object? value) {
  Object? ordered(Object? item) {
    if (item is Map) {
      return {
        for (final key in (item.keys.cast<String>().toList()..sort()))
          key: ordered(item[key]),
      };
    }
    if (item is List) {
      return item.map(ordered).toList();
    }
    return item;
  }

  return jsonEncode(ordered(value));
}

extension PersonalSyncOperations on SyncEngine {
  List<Habit> get habits =>
      _personalRecords.values
          .where((r) => r.kind == 'habit' && !r.deleted)
          .map(Habit.fromRecord)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
  List<HabitCheckIn> get habitCheckIns => _personalRecords.values
      .where((r) => r.kind == 'habit_checkin' && !r.deleted)
      .map(HabitCheckIn.fromRecord)
      .toList();
  List<PersonalConflict> get personalConflicts =>
      List.unmodifiable(_personalConflicts.values);
  bool get personalSupported => _personalSupported;
  bool get personalUpgradeRequired =>
      _personalOps.isNotEmpty && !_personalSupported && _lastSyncedAt != null;

  Task _decorateTask(Task task) {
    final meta = _personalRecords['task_meta/${task.id}'];
    return meta == null || meta.deleted ? task : task.withMetadata(meta.data);
  }

  Map<String, dynamic> _personalState() => {
    'personal_cursor': _personalCursor,
    'personal_supported': _personalSupported,
    'personal_records': _personalRecords.values.map((r) => r.toJson()).toList(),
    'personal_operations': _personalOps,
    'personal_attempted_ids': _personalAttempted.toList(),
    'personal_task_releases': _personalTaskReleases.toList(),
    'personal_conflicts': _personalConflicts.values
        .map((c) => c.toJson())
        .toList(),
  };

  void _restorePersonal(Map<String, dynamic> state) {
    _personalCursor = state['personal_cursor'] as int? ?? 0;
    if (_personalCursor < 0) {
      throw const FormatException('个人同步进度无效');
    }
    _personalSupported = state['personal_supported'] as bool? ?? false;
    _personalRecords.clear();
    for (final raw in state['personal_records'] as List? ?? []) {
      final record = PersonalRecord.fromJson(_map(raw));
      _personalRecords[record.key] = record;
    }
    _personalOps
      ..clear()
      ..addAll((state['personal_operations'] as List? ?? []).map(_map));
    _personalAttempted
      ..clear()
      ..addAll((state['personal_attempted_ids'] as List? ?? []).cast<String>());
    _personalTaskReleases
      ..clear()
      ..addAll((state['personal_task_releases'] as List? ?? []).cast<String>());
    _personalConflicts.clear();
    for (final raw in state['personal_conflicts'] as List? ?? []) {
      final conflict = PersonalConflict.fromJson(_map(raw));
      _personalConflicts[conflict.key] = conflict;
    }
  }

  void _removePersonalOps(String kind, String id) {
    _personalOps.removeWhere((op) {
      if (op['kind'] != kind || op['id'] != id) {
        return false;
      }
      _personalAttempted.remove(op['op_id']);
      return true;
    });
  }

  void _putPersonalLocal(
    String kind,
    String id,
    Map<String, dynamic> data, {
    bool deleted = false,
  }) {
    validatePersonalData(kind, id, data);
    final key = '$kind/$id';
    final old = _personalRecords[key];
    if (old != null &&
        old.deleted == deleted &&
        _canonicalPersonal(old.data) == _canonicalPersonal(data)) {
      return;
    }
    if (_personalConflicts.containsKey(key)) {
      throw StateError('请先处理这条个人记录的同步冲突');
    }
    if (old?.deleted == true) {
      throw StateError('这条记录已删除，请重新创建');
    }
    final first = _personalOps
        .where((op) => op['kind'] == kind && op['id'] == id)
        .firstOrNull;
    final base = first?['base_version'] as int? ?? old?.version ?? 0;
    _personalOps.removeWhere(
      (op) =>
          op['kind'] == kind &&
          op['id'] == id &&
          !_personalAttempted.contains(op['op_id']),
    );
    final record = PersonalRecord(
      kind: kind,
      id: id,
      data: data,
      deleted: deleted,
      version: old?.version ?? 0,
      changeSeq: old?.changeSeq ?? 0,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    _personalRecords[key] = record;
    _personalOps.add({
      'op_id': newId(),
      'kind': kind,
      'id': id,
      'base_version': base,
      'action': deleted ? 'delete' : 'upsert',
      'data': data,
    });
  }

  void _putTaskMetadata(String id, TaskDraft draft) {
    if (!draft.hasMetadata && !_personalRecords.containsKey('task_meta/$id')) {
      return;
    }
    _putPersonalLocal('task_meta', id, draft.toMetadata());
  }

  void _validateParent(String id, String? parentId) {
    final active = {for (final task in tasks) task.id: task};
    if (parentId != null && !active.containsKey(parentId)) {
      throw StateError('父待办已删除，请重新选择');
    }
    final parents = {
      for (final task in active.values) task.id: task.parentId,
      id: parentId,
    };
    for (final child in parents.keys) {
      String? current = child;
      final seen = <String>{};
      while (current != null) {
        if (!seen.add(current)) {
          throw ArgumentError('子任务不能形成循环');
        }
        if (seen.length > 5) {
          throw ArgumentError('子任务最多支持 5 层');
        }
        current = parents[current];
      }
    }
  }

  void _promoteLocalChildren(String parentId) {
    for (final task
        in tasks.where((task) => task.parentId == parentId).toList()) {
      _putTaskMetadata(
        task.id,
        TaskDraft.fromTask(task).copyWith(clearParentId: true),
      );
    }
  }

  Future<void> saveHabit(HabitDraft draft, {String? id}) => _serial(() async {
    _checkLoaded();
    draft.validate();
    final recordId = id ?? newId();
    if (id != null &&
        (_personalRecords['habit/$id'] == null ||
            _personalRecords['habit/$id']!.deleted)) {
      throw StateError('习惯已删除');
    }
    await _commit(() => _putPersonalLocal('habit', recordId, draft.toJson()));
  });

  Future<void> deleteHabit(String id) => _serial(() async {
    _checkLoaded();
    final habit = _personalRecords['habit/$id'];
    if (habit == null || habit.deleted) {
      return;
    }
    if (_personalConflicts.containsKey(habit.key)) {
      throw StateError('请先处理此习惯的同步冲突');
    }
    final pending = _personalOps
        .where((op) => op['kind'] == 'habit' && op['id'] == id)
        .toList();
    await _commit(() {
      if (habit.version == 0 &&
          !pending.any((op) => _personalAttempted.contains(op['op_id']))) {
        _personalRecords.remove(habit.key);
        _removePersonalOps('habit', id);
        for (final checkin
            in habitCheckIns.where((item) => item.habitId == id).toList()) {
          _personalRecords.remove('habit_checkin/${checkin.id}');
          _removePersonalOps('habit_checkin', checkin.id);
        }
      } else {
        _putPersonalLocal('habit', id, habit.data, deleted: true);
      }
    });
  });

  Future<void> setHabitValue(String habitId, String day, int value) =>
      _serial(() async {
        _checkLoaded();
        final record = _personalRecords['habit/$habitId'];
        if (record == null || record.deleted) {
          throw StateError('习惯已删除');
        }
        if (record.data['goal_type'] == 'bool' && value > 1) {
          throw ArgumentError('勾选习惯只能记录 0 或 1');
        }
        final id = '$habitId:$day';
        final data = {'habit_id': habitId, 'date': day, 'value': value};
        validatePersonalData('habit_checkin', id, data);
        await _commit(() => _putPersonalLocal('habit_checkin', id, data));
      });

  Future<void> resolvePersonalConflict(
    String kind,
    String id, {
    required bool keepLocal,
  }) => _serial(() async {
    _checkLoaded();
    final key = '$kind/$id';
    final conflict = _personalConflicts[key];
    if (conflict == null) {
      return;
    }
    if (keepLocal && conflict.remote?.deleted == true) {
      throw StateError('NAS 已删除此记录，请保留 NAS 版本后重新创建');
    }
    if (keepLocal && conflict.local != null) {
      final data = conflict.local!.data;
      if (kind == 'task_meta') {
        _validateParent(id, data['parent_id'] as String?);
      }
      if (kind == 'habit_checkin') {
        final habit = _personalRecords['habit/${data['habit_id']}'];
        if (habit == null || habit.deleted) {
          throw StateError('此习惯已删除，无法保留本机打卡');
        }
        if (habit.data['goal_type'] == 'bool' && (data['value'] as int) > 1) {
          throw StateError('此习惯已改为勾选，请保留 NAS 版本后重新打卡');
        }
      }
    }
    await _commit(() {
      _personalConflicts.remove(key);
      _removePersonalOps(kind, id);
      if (conflict.remote == null) {
        _personalRecords.remove(key);
      } else {
        _personalRecords[key] = conflict.remote!;
      }
      if (keepLocal && conflict.local != null) {
        _putPersonalLocal(
          kind,
          id,
          conflict.local!.data,
          deleted: conflict.local!.deleted,
        );
      }
    });
  });

  Future<void> _syncPersonal() async {
    if (!_personalSupported || transport is! PersonalSyncTransport) {
      return;
    }
    final personalTransport = transport as PersonalSyncTransport;
    do {
      final batch = <Map<String, dynamic>>[];
      final recordKeys = <String>{};
      for (final op in _personalOps) {
        if (recordKeys.add('${op['kind']}/${op['id']}')) {
          batch.add(_map(jsonDecode(jsonEncode(op))));
        }
        if (batch.length == 100) {
          break;
        }
      }
      if (batch.isNotEmpty) {
        await _commit(
          () => _personalAttempted.addAll(
            batch.map((op) => op['op_id'] as String),
          ),
        );
      }
      final releases = _personalTaskReleases
          .where((id) {
            if (_personalConflicts.containsKey('task_meta/$id')) {
              return false;
            }
            final pending = _personalOps
                .where((op) => op['kind'] == 'task_meta' && op['id'] == id)
                .toList();
            return pending.isEmpty ||
                (pending.length == 1 &&
                    batch.any((op) => op['op_id'] == pending.single['op_id']));
          })
          .take(100)
          .toList();
      var requested = _personalCursor;
      late Map<String, dynamic> response;
      try {
        response = await personalTransport.syncPersonal({
          'instance_id': _instanceId,
          'cursor': requested,
          'operations': batch,
          'release_tasks': releases,
        });
      } on SyncServerException catch (error) {
        if (error.code != 'future_cursor') {
          rethrow;
        }
        requested = 0;
        response = await personalTransport.syncPersonal({
          'instance_id': _instanceId,
          'cursor': 0,
          'operations': batch,
          'release_tasks': releases,
        });
      }
      final cursor = response['cursor'] as int;
      if (response['instance_id'] != _instanceId || cursor < requested) {
        throw StateError('NAS 个人数据身份或进度无效');
      }
      final changes = (response['changes'] as List)
          .map((raw) => PersonalRecord.fromJson(_map(raw)))
          .toList();
      final results = (response['results'] as List).map(_map).toList();
      final generated = (response['generated_tasks'] as List? ?? [])
          .map((raw) => Task.fromJson(_map(raw)))
          .toList();
      final released = (response['released_tasks'] as List? ?? [])
          .cast<String>();
      if (released.toSet().length != released.length ||
          released.any((id) => !releases.contains(id))) {
        throw StateError('NAS 重复待办确认无效');
      }
      final sentIds = batch.map((op) => op['op_id']).toSet();
      final seen = <String>{};
      for (final result in results) {
        final id = result['op_id'] as String;
        if (!sentIds.contains(id) ||
            !seen.add(id) ||
            !const ['applied', 'conflict'].contains(result['status'])) {
          throw StateError('NAS 个人数据确认无效');
        }
        final record = result['record'] == null
            ? null
            : PersonalRecord.fromJson(_map(result['record']));
        final op = batch.firstWhere((op) => op['op_id'] == id);
        if ((result['status'] == 'applied' && record == null) ||
            (record != null &&
                (record.kind != op['kind'] || record.id != op['id']))) {
          throw StateError('NAS 确认了错误的个人记录');
        }
      }
      if (seen.length != sentIds.length ||
          changes.any(
            (r) => r.changeSeq > cursor || r.changeSeq <= requested,
          )) {
        throw StateError('NAS 未完整确认个人数据');
      }
      for (final id in releases.where((id) => !released.contains(id))) {
        final blocked = results.any(
          (result) =>
              result['status'] == 'conflict' &&
              batch.any(
                (op) =>
                    op['op_id'] == result['op_id'] &&
                    op['kind'] == 'task_meta' &&
                    op['id'] == id,
              ),
        );
        if (!blocked) {
          throw StateError('NAS 未确认重复待办，请更新个人功能服务后重试');
        }
      }
      await _commit(() {
        for (final result in results) {
          final op = batch.firstWhere((op) => op['op_id'] == result['op_id']);
          final kind = op['kind'] as String, id = op['id'] as String;
          final key = '$kind/$id';
          final remote = result['record'] == null
              ? null
              : PersonalRecord.fromJson(_map(result['record']));
          _personalOps.removeWhere((op) => op['op_id'] == result['op_id']);
          _personalAttempted.remove(result['op_id']);
          if (result['status'] == 'conflict') {
            _personalConflicts[key] = PersonalConflict(
              kind: kind,
              id: id,
              local: _personalRecords[key],
              remote: remote,
            );
            _removePersonalOps(kind, id);
          } else {
            final next = _personalOps
                .where((op) => op['kind'] == kind && op['id'] == id)
                .firstOrNull;
            if (next == null) {
              _personalRecords[key] = remote!;
            } else {
              next['base_version'] = remote!.version;
              _personalRecords[key] = _personalRecords[key]!.withVersion(
                remote.version,
                remote.changeSeq,
              );
            }
          }
        }
        for (final record in changes) {
          final conflict = _personalConflicts[record.key];
          if (conflict != null) {
            if (requested == 0 ||
                conflict.remote == null ||
                record.version >= conflict.remote!.version) {
              _personalConflicts[record.key] = PersonalConflict(
                kind: record.kind,
                id: record.id,
                local: conflict.local,
                remote: record,
              );
            }
            continue;
          }
          if (_personalOps.any(
            (op) => op['kind'] == record.kind && op['id'] == record.id,
          )) {
            continue;
          }
          final cached = _personalRecords[record.key];
          if (requested == 0 ||
              cached == null ||
              record.version >= cached.version) {
            _personalRecords[record.key] = record;
          }
        }
        if (requested == 0) {
          final keys = changes.map((r) => r.key).toSet();
          final pending = _personalOps
              .map((op) => '${op['kind']}/${op['id']}')
              .toSet();
          _personalRecords.removeWhere(
            (key, _) =>
                !keys.contains(key) &&
                !pending.contains(key) &&
                !_personalConflicts.containsKey(key),
          );
          for (final key in _personalConflicts.keys.toList()) {
            if (!keys.contains(key)) {
              final c = _personalConflicts[key]!;
              _personalConflicts[key] = PersonalConflict(
                kind: c.kind,
                id: c.id,
                local: c.local,
              );
            }
          }
        }
        for (final task in generated) {
          // Only new deterministic recurrence instances are imported here. The
          // regular task cursor is deliberately unchanged and will replay them.
          if (!_tasks.containsKey(task.id)) {
            _tasks[task.id] = task;
          }
        }
        _personalCursor = cursor;
        _personalTaskReleases.removeAll(released);
      });
    } while (_personalOps.isNotEmpty ||
        _personalTaskReleases.any(
          (id) => !_personalConflicts.containsKey('task_meta/$id'),
        ));
  }
}
