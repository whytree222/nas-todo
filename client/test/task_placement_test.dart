import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_todo/app_controller.dart';
import 'package:nas_todo/sync_core.dart';

const _id = '1192930e-56e3-4ea9-b3a5-15102c75e305';
const _today = '2026-10-19';

class _Store implements DataStore {
  Map<String, dynamic>? state;
  bool fail = false;
  int writes = 0;

  @override
  Future<Map<String, dynamic>?> read() async => state;

  @override
  Future<void> write(Map<String, dynamic> value) async {
    if (fail) throw StateError('Disk full');
    writes++;
    state = Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  }
}

class _Offline implements SyncTransport {
  @override
  Future<Map<String, dynamic>> sync(Map<String, dynamic> payload) async =>
      throw StateError('Placement tests use local data.');
}

class _GatedPull implements SyncTransport {
  final Task remote;
  final entered = Completer<void>();
  final release = Completer<void>();
  Map<String, dynamic>? request;
  _GatedPull(this.remote);

  @override
  Future<Map<String, dynamic>> sync(Map<String, dynamic> payload) async {
    request = payload;
    entered.complete();
    await release.future;
    return {
      'instance_id': 'placement-server',
      'cursor': 2,
      'changes': [remote.toJson()],
      'results': <Map<String, dynamic>>[],
    };
  }
}

Task _task({
  String? date = '2026-10-25',
  int priority = 1,
  bool completed = false,
  bool deleted = false,
  int version = 1,
  String title = '原始标题',
  String note = '保留备注',
}) => Task(
  id: _id,
  title: title,
  note: note,
  listName: '工作',
  dueDate: date,
  priority: priority,
  completed: completed,
  deleted: deleted,
  version: version,
  changeSeq: version,
  updatedAt: '2026-10-19T00:00:00Z',
);

_Store _seed(Task task, {bool conflict = false}) => _Store()
  ..state = {
    'schema': 1,
    'instance_id': 'placement-server',
    'cursor': 1,
    'tasks': [task.toJson()],
    'operations': <Map<String, dynamic>>[],
    'attempted_ids': <String>[],
    'conflicts': [
      if (conflict)
        SyncConflict(
          taskId: task.id,
          local: task,
          remote: task.copyWith(version: 2, changeSeq: 2),
        ).toJson(),
    ],
  };

Future<SyncEngine> _engine(_Store store, [SyncTransport? transport]) async {
  final engine = SyncEngine(store, transport ?? _Offline());
  await engine.load();
  return engine;
}

Map<String, dynamic> _operation(_Store store) => Map<String, dynamic>.from(
  (store.state!['operations'] as List).single as Map,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Partial placement preserves other fields, coalesces and survives restart',
    () async {
      final original = _task(completed: true);
      final store = _seed(original);
      final engine = await _engine(store);
      await engine.setTaskPlacement(_id, listName: ' 家庭 ');
      expect(TaskDraft.fromTask(engine.tasks.single).toJson(), {
        'title': original.title,
        'note': original.note,
        'list_name': '家庭',
        'due_date': original.dueDate,
        'priority': original.priority,
        'completed': true,
      });
      await engine.setTaskPlacement(_id, priority: 2);
      await engine.setTaskPlacement(_id, clearDueDate: true);
      expect(engine.pendingCount, 1);
      final op = _operation(store);
      expect(op['base_version'], 1);
      expect(op['task_id'], _id);
      expect(op['action'], 'upsert');
      expect((op['data'] as Map)['title'], original.title);
      expect((op['data'] as Map)['note'], original.note);
      expect((op['data'] as Map)['list_name'], '家庭');
      expect((op['data'] as Map)['due_date'], isNull);
      expect((op['data'] as Map)['priority'], 2);
      expect((op['data'] as Map)['completed'], isTrue);
      final restarted = await _engine(store);
      expect(
        TaskDraft.fromTask(restarted.tasks.single).toJson(),
        TaskDraft.fromTask(engine.tasks.single).toJson(),
      );
      expect(restarted.pendingCount, 1);
      expect(restarted.tasks.single.version, 1);
    },
  );

  test('No-op placement and quadrant do not write or enqueue', () async {
    final store = _seed(_task(priority: 0));
    final engine = await _engine(store);
    final before = jsonEncode(store.state);
    await engine.setTaskPlacement(_id);
    await engine.setTaskPlacement(
      _id,
      listName: ' 工作 ',
      priority: 0,
      dueDate: '2026-10-25',
    );
    await engine.setTaskQuadrant(
      _id,
      important: false,
      urgent: false,
      today: _today,
    );
    expect(store.writes, 0);
    expect(engine.pendingCount, 0);
    expect(jsonEncode(store.state), before);
  });

  test(
    'Invalid placement fields and mutually exclusive date requests are atomic',
    () async {
      final store = _seed(_task());
      final engine = await _engine(store);
      final before = jsonEncode(store.state);
      final invalid = <Future<void> Function()>[
        () => engine.setTaskPlacement(_id, listName: ' '),
        () =>
            engine.setTaskPlacement(_id, listName: List.filled(61, '字').join()),
        () => engine.setTaskPlacement(_id, priority: -1),
        () => engine.setTaskPlacement(_id, priority: 3),
        () => engine.setTaskPlacement(_id, dueDate: '2026-02-30'),
        () => engine.setTaskPlacement(_id, dueDate: '2026-2-03'),
        () => engine.setTaskPlacement(_id, dueDate: _today, clearDueDate: true),
        () => engine.setTaskQuadrant(
          _id,
          important: true,
          urgent: true,
          today: '2026-02-30',
        ),
      ];
      for (final request in invalid) {
        await expectLater(request(), throwsArgumentError);
        expect(jsonEncode(store.state), before);
        expect(engine.tasks.single.dueDate, '2026-10-25');
        expect(engine.tasks.single.listName, '工作');
        expect(engine.pendingCount, 0);
      }
      expect(store.writes, 0);
    },
  );

  test(
    'Failed placement storage rolls task and outbox back before retry',
    () async {
      final store = _seed(_task());
      final engine = await _engine(store);
      await engine.setTaskPlacement(_id, priority: 2);
      final before = jsonEncode(store.state);
      final oldOperation = _operation(store);
      store.fail = true;
      await expectLater(
        engine.setTaskPlacement(_id, listName: '生活', dueDate: '2026-10-20'),
        throwsStateError,
      );
      expect(jsonEncode(store.state), before);
      expect(engine.tasks.single.priority, 2);
      expect(engine.tasks.single.listName, '工作');
      expect(engine.tasks.single.dueDate, '2026-10-25');
      expect(engine.pendingCount, 1);
      expect(_operation(store)['op_id'], oldOperation['op_id']);
      store.fail = false;
      await engine.setTaskPlacement(_id, listName: '生活', dueDate: '2026-10-20');
      expect(engine.tasks.single.listName, '生活');
      expect(engine.tasks.single.priority, 2);
      expect(engine.pendingCount, 1);
    },
  );

  test('Missing deleted and conflicted records cannot be repositioned or resurrected', () async {
    for (final record in [_task(deleted: true), _task()]) {
      final conflict = !record.deleted;
      final store = _seed(record, conflict: conflict);
      final engine = await _engine(store);
      final before = jsonEncode(store.state);
      await expectLater(
        engine.setTaskPlacement(_id, listName: '移动目标'),
        throwsStateError,
      );
      await expectLater(
        engine.setTaskQuadrant(
          _id,
          important: true,
          urgent: true,
          today: _today,
        ),
        throwsStateError,
      );
      expect(jsonEncode(store.state), before);
      expect(engine.pendingCount, 0);
      expect(engine.conflicts.length, conflict ? 1 : 0);
      expect(engine.tasks.length, record.deleted ? 0 : 1);
    }
    final engine = await _engine(_Store());
    await expectLater(
      engine.setTaskPlacement('missing', priority: 2),
      throwsStateError,
    );
    await expectLater(
      engine.setTaskQuadrant(
        'missing',
        important: false,
        urgent: false,
        today: _today,
      ),
      throwsStateError,
    );
  });

  test(
    'Quadrant mapping preserves high priority and appropriate existing dates',
    () async {
      final cases = <Map<String, dynamic>>[
        {
          'priority': 2,
          'date': '2026-10-18',
          'important': true,
          'urgent': true,
          'expectedPriority': 2,
          'expectedDate': '2026-10-18',
        },
        {
          'priority': 0,
          'date': null,
          'important': true,
          'urgent': true,
          'expectedPriority': 1,
          'expectedDate': _today,
        },
        {
          'priority': 0,
          'date': '2026-10-25',
          'important': true,
          'urgent': true,
          'expectedPriority': 1,
          'expectedDate': _today,
        },
        {
          'priority': 2,
          'date': '2026-10-25',
          'important': true,
          'urgent': false,
          'expectedPriority': 2,
          'expectedDate': '2026-10-25',
        },
        {
          'priority': 2,
          'date': '2026-10-25',
          'important': false,
          'urgent': false,
          'expectedPriority': 0,
          'expectedDate': '2026-10-25',
        },
        {
          'priority': 2,
          'date': _today,
          'important': false,
          'urgent': false,
          'expectedPriority': 0,
          'expectedDate': null,
        },
        {
          'priority': 1,
          'date': '2026-10-18',
          'important': true,
          'urgent': false,
          'expectedPriority': 1,
          'expectedDate': null,
        },
        {
          'priority': 2,
          'date': null,
          'important': false,
          'urgent': true,
          'expectedPriority': 0,
          'expectedDate': _today,
        },
      ];
      for (final row in cases) {
        final original = _task(
          date: row['date'] as String?,
          priority: row['priority'] as int,
        );
        final engine = await _engine(_seed(original));
        await engine.setTaskQuadrant(
          _id,
          important: row['important'] as bool,
          urgent: row['urgent'] as bool,
          today: _today,
        );
        final task = engine.tasks.single;
        expect(task.priority, row['expectedPriority'], reason: '$row');
        expect(task.dueDate, row['expectedDate'], reason: '$row');
        expect(
          [task.title, task.note, task.listName, task.completed],
          [original.title, original.note, original.listName, false],
        );
      }
    },
  );

  test(
    'Completed quadrant changes are rejected and failure preserves history',
    () async {
      final completedStore = _seed(_task(completed: true));
      final completedEngine = await _engine(completedStore);
      await expectLater(
        completedEngine.setTaskQuadrant(
          _id,
          important: false,
          urgent: true,
          today: _today,
        ),
        throwsStateError,
      );
      expect(completedStore.writes, 0);
      expect(completedEngine.tasks.single.completed, isTrue);
      final store = _seed(_task(date: '2026-10-18', priority: 2));
      final engine = await _engine(store);
      final before = jsonEncode(store.state);
      store.fail = true;
      await expectLater(
        engine.setTaskQuadrant(
          _id,
          important: false,
          urgent: false,
          today: _today,
        ),
        throwsStateError,
      );
      expect(jsonEncode(store.state), before);
      expect(engine.tasks.single.priority, 2);
      expect(engine.tasks.single.dueDate, '2026-10-18');
      expect(engine.pendingCount, 0);
    },
  );

  for (final action in ['placement', 'quadrant']) {
    test(
      'Queued $action reads fresh pulled fields and version before saving',
      () async {
        final stale = _task(date: '2026-10-18', priority: 0);
        final fresh = _task(
          title: 'NAS 最新标题',
          note: 'NAS 最新备注',
          date: '2026-10-25',
          priority: 2,
          version: 2,
        );
        final store = _seed(stale);
        final gate = _GatedPull(fresh);
        final engine = await _engine(store, gate);
        final syncing = engine.sync();
        await gate.entered.future;
        final changing = action == 'placement'
            ? engine.setTaskPlacement(_id, listName: '移动目标')
            : engine.setTaskQuadrant(
                _id,
                important: false,
                urgent: false,
                today: _today,
              );
        gate.release.complete();
        await syncing;
        await changing;
        final task = engine.tasks.single;
        expect(task.title, fresh.title);
        expect(task.note, fresh.note);
        expect(task.dueDate, '2026-10-25');
        expect(task.version, 2);
        expect(task.listName, action == 'placement' ? '移动目标' : '工作');
        expect(task.priority, action == 'placement' ? 2 : 0);
        expect(engine.conflicts, isEmpty);
        expect(engine.pendingCount, 1);
        expect(gate.request!['operations'], isEmpty);
        final operation = _operation(store);
        expect(operation['base_version'], 2);
        expect((operation['data'] as Map)['title'], fresh.title);
        expect((operation['data'] as Map)['note'], fresh.note);
        expect((operation['data'] as Map)['due_date'], '2026-10-25');
      },
    );
  }

  test('Queued incomplete-only placement rejects a task completed by the NAS pull', () async {
    final stale = _task(date: '2026-10-18', priority: 0);
    final fresh = _task(title: 'NAS 已完成标题', note: 'NAS 已完成备注',
      date: '2026-10-25', priority: 1, completed: true, version: 2);
    final store = _seed(stale);
    final gate = _GatedPull(fresh);
    final engine = await _engine(store, gate);
    final syncing = engine.sync();
    await gate.entered.future;
    final changing = engine.setTaskPlacement(_id, priority: 2,
      requireIncomplete: true);
    final rejected = expectLater(changing, throwsStateError);
    gate.release.complete();
    await syncing;
    await rejected;
    final task = engine.tasks.single;
    expect(task.toJson(), fresh.toJson());
    expect(task.completed, isTrue);
    expect(task.priority, 1);
    expect(engine.pendingCount, 0);
    expect(engine.conflicts, isEmpty);
    expect(store.state!['operations'], isEmpty);
    expect((store.state!['tasks'] as List).single, fresh.toJson());
  });

  test('Controller uses its injected day and returns bool on validation or disk failure', () async {
    final store = _seed(_task(date: '2040-07-05', priority: 0));
    final engine = await _engine(store);
    final controller = AppController.forTesting(
      engine,
      clock: () => DateTime(2040, 7, 4, 23, 30),
    );
    addTearDown(controller.dispose);
    expect(
      await controller.setTaskQuadrant(_id, important: true, urgent: true),
      isTrue,
    );
    expect(controller.tasks.single.dueDate, '2040-07-04');
    expect(controller.tasks.single.priority, 1);
    expect(await controller.setTaskPlacement(_id, priority: 99), isFalse);
    expect(controller.tasks.single.priority, 1);
    final before = jsonEncode(store.state);
    store.fail = true;
    expect(await controller.setTaskPlacement(_id, listName: '失败目标'), isFalse);
    expect(jsonEncode(store.state), before);
    expect(controller.tasks.single.listName, '工作');
    expect(controller.error, contains('Disk full'));
    expect(controller.editing, isFalse);
  });
}
