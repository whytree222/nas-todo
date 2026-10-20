import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_todo/personal_core.dart';
import 'package:nas_todo/sync_core.dart';
import 'package:nas_todo/task_tree.dart';

class _Store implements DataStore {
  Map<String, dynamic>? state;
  bool fail = false;
  @override
  Future<Map<String, dynamic>?> read() async => state;
  @override
  Future<void> write(Map<String, dynamic> value) async {
    if (fail) {
      throw StateError('disk full');
    }
    state = Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  }
}

class _Legacy implements SyncTransport {
  final rows = <String, Map<String, dynamic>>{};
  int cursor = 0;
  @override
  Future<Map<String, dynamic>> sync(Map<String, dynamic> payload) async {
    expect(payload.keys.toSet(), {'instance_id', 'cursor', 'operations'});
    final results = <Map<String, dynamic>>[];
    for (final op in payload['operations'] as List) {
      final data = Map<String, dynamic>.from(op['data'] as Map);
      expect(data.keys.toSet(), {
        'title',
        'note',
        'list_name',
        'due_date',
        'priority',
        'completed',
      });
      final previous = rows[op['task_id']];
      final record = {
        'id': op['task_id'],
        ...data,
        'deleted': op['action'] == 'delete',
        'version': (previous?['version'] as int? ?? 0) + 1,
        'updated_at': '2026-10-20T00:00:00Z',
        'change_seq': ++cursor,
      };
      rows[op['task_id'] as String] = record;
      results.add({'op_id': op['op_id'], 'status': 'applied', 'task': record});
    }
    return {
      'instance_id': 'legacy-test',
      'cursor': cursor,
      'changes': rows.values
          .where(
            (row) => (row['change_seq'] as int) > (payload['cursor'] as int),
          )
          .toList(),
      'results': results,
    };
  }
}

Future<SyncEngine> _engine(_Store store, [SyncTransport? transport]) async {
  final engine = SyncEngine(store, transport ?? _Legacy());
  await engine.load();
  return engine;
}

void main() {
  test('Legacy NAS receives exact six fields while new metadata stays durable and pending', () async {
    final store = _Store(), transport = _Legacy();
    final engine = await _engine(store, transport);
    await engine.saveTask(
      const TaskDraft(
        title: '阅读',
        tags: ['学习'],
        dueDate: '2099-10-20',
        repeatRule: TaskRepeatRule(frequency: 'daily'),
      ),
    );
    await engine.sync();
    expect(engine.tasks.single.tags, ['学习']);
    expect(engine.tasks.single.repeatRule!.frequency, 'daily');
    expect(engine.pendingCount, 1);
    expect(engine.personalUpgradeRequired, isTrue);
    final reopened = await _engine(store, transport);
    expect(reopened.tasks.single.tags, ['学习']);
    expect(reopened.pendingCount, 1);
    await reopened.setCompleted(reopened.tasks.single.id, true);
    await reopened.sync();
    expect(reopened.tasks.single.repeatRule!.frequency, 'daily');
    expect(reopened.pendingCount, 1);
  });

  test(
    'One failed write rolls back base fields, metadata and both outboxes',
    () async {
      final store = _Store();
      final failing = await _engine(store);
      await failing.saveTask(const TaskDraft(title: '原始', tags: ['旧标签']));
      final original = failing.tasks.single;
      final before = jsonEncode(store.state);
      store.fail = true;
      await expectLater(
        failing.saveTask(
          TaskDraft.fromTask(original).copyWith(title: '修改', tags: ['新标签']),
          id: original.id,
        ),
        throwsStateError,
      );
      expect(failing.tasks.single.toJson(), original.toJson());
      expect(jsonEncode(store.state), before);
      expect(failing.pendingCount, 2);
    },
  );

  test(
    'Hierarchy rejects cycles and sixth depth without dropping siblings',
    () async {
      final engine = await _engine(_Store());
      String? parent;
      final ids = <String>[];
      for (var depth = 0; depth < 5; depth++) {
        await engine.saveTask(TaskDraft(title: '第 $depth 层', parentId: parent));
        parent = engine.tasks.last.id;
        ids.add(parent);
      }
      await expectLater(
        engine.saveTask(TaskDraft(title: '第六层', parentId: parent)),
        throwsArgumentError,
      );
      await expectLater(
        engine.saveTask(
          TaskDraft.fromTask(engine.tasks.first).copyWith(parentId: ids.last),
          id: ids.first,
        ),
        throwsArgumentError,
      );
      expect(engine.tasks, hasLength(5));
      await engine.deleteTask(ids[1]);
      expect(
        engine.tasks.firstWhere((task) => task.id == ids[2]).parentId,
        isNull,
      );
      expect(
        engine.tasks.firstWhere((task) => task.id == ids[3]).parentId,
        ids[2],
      );
    },
  );

  test(
    'Checkbox, schedule and priority edits retain tags and parent metadata',
    () async {
      final engine = await _engine(_Store());
      await engine.saveTask(const TaskDraft(title: '父'));
      final parent = engine.tasks.single.id;
      await engine.saveTask(
        TaskDraft(title: '子', parentId: parent, tags: ['保留']),
      );
      final id = engine.tasks.last.id;
      await engine.scheduleTask(id, '2099-10-20');
      await engine.setTaskPlacement(id, priority: 2);
      await engine.setCompleted(id, true);
      final child = engine.tasks.last;
      expect(child.tags, ['保留']);
      expect(child.parentId, parent);
      expect(child.dueDate, '2099-10-20');
      expect(child.priority, 2);
      expect(child.completed, isTrue);
    },
  );

  test('Moving a repeated urgent task to a nonurgent quadrant keeps recurrence and schedules tomorrow', () async {
    final engine = await _engine(_Store());
    await engine.saveTask(
      const TaskDraft(
        title: '每周阅读',
        dueDate: '2099-10-20',
        tags: ['阅读'],
        priority: 2,
        repeatRule: TaskRepeatRule(frequency: 'weekly', weekdays: [1, 3]),
      ),
    );
    final id = engine.tasks.single.id;
    await engine.setTaskQuadrant(
      id,
      important: true,
      urgent: false,
      today: '2099-10-20',
    );
    expect(engine.tasks.single.dueDate, '2099-10-21');
    expect(engine.tasks.single.tags, ['阅读']);
    expect(engine.tasks.single.repeatRule!.weekdays, [1, 3]);
    expect(engine.tasks.single.priority, 2);
  });

  test('Habit check-in invalid dates, invalid values and deleted habits never enqueue changes', () async {
    final engine = await _engine(_Store());
    await engine.saveHabit(const HabitDraft(name: '阅读'));
    final id = engine.habits.single.id;
    await expectLater(
      engine.setHabitValue(id, '2026-02-30', 1),
      throwsArgumentError,
    );
    await expectLater(
      engine.setHabitValue(id, '2026-10-20', 2),
      throwsArgumentError,
    );
    await engine.setHabitValue(id, '2026-10-20', 1);
    expect(engine.habitCheckIns.single.value, 1);
    await engine.deleteHabit(id);
    expect(engine.habits, isEmpty);
    expect(engine.habitCheckIns, isEmpty);
    expect(engine.pendingCount, 0);
    await expectLater(
      engine.setHabitValue(id, '2026-10-20', 1),
      throwsStateError,
    );
  });

  test('Task tree collapse hides only descendants and filtered children remain reachable', () {
    const parent = Task(id: 'p', title: '父');
    const child = Task(id: 'c', title: '子', parentId: 'p');
    const sibling = Task(id: 's', title: '其他');
    expect(taskTreeRows([parent, child, sibling]).map((row) => row.depth), [
      0,
      1,
      0,
    ]);
    expect(
      taskTreeRows(
        [parent, child, sibling],
        collapsed: {'p'},
      ).map((row) => row.task.id),
      ['p', 's'],
    );
    expect(taskTreeRows([child]).single.depth, 0);
  });

  test('Repeat and metadata validation reject damaged records rather than replacing local history', () {
    expect(
      () => const TaskRepeatRule(frequency: 'weekly', weekdays: [8]).validate(),
      throwsArgumentError,
    );
    expect(
      () => const TaskDraft(
        title: '没有日期',
        repeatRule: TaskRepeatRule(frequency: 'daily'),
      ).validate(),
      throwsArgumentError,
    );
    expect(() => normalizedTags(['x' * 31]), throwsArgumentError);
    expect(validPersonalDate('2024-02-29'), isTrue);
    expect(validPersonalDate('2023-02-29'), isFalse);
  });
}
