import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_todo/android_widget.dart';
import 'package:nas_todo/app_controller.dart';
import 'package:nas_todo/daily_celebration.dart';
import 'package:nas_todo/sync_core.dart';

class _TaskStore implements DataStore {
  Map<String, dynamic>? state;
  bool fail = false;
  Completer<void>? gate;

  @override
  Future<Map<String, dynamic>?> read() async => state;

  @override
  Future<void> write(Map<String, dynamic> value) async {
    await gate?.future;
    if (fail) throw StateError('Task disk unavailable');
    state = Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  }
}

class _Preferences extends MemoryCelebrationStore {
  bool failRead = false;
  bool failWrite = false;
  int writes = 0;
  Completer<void>? gate;

  @override
  Future<Map<String, dynamic>?> read() async {
    if (failRead) throw const FormatException('Damaged preference');
    return super.read();
  }

  @override
  Future<void> write(Map<String, dynamic> value) async {
    writes++;
    await gate?.future;
    if (failWrite) throw StateError('Preference disk unavailable');
    await super.write(value);
  }
}

class _Transport implements SyncTransport {
  Completer<void>? gate;
  final entered = Completer<void>();
  List<Map<String, dynamic>> changes = [];

  @override
  Future<Map<String, dynamic>> sync(Map<String, dynamic> payload) async {
    if (!entered.isCompleted) entered.complete();
    await gate?.future;
    return {'instance_id': 'celebration-test', 'cursor': 2,
      'changes': changes, 'results': []};
  }
}

Future<AppController> _controller(_TaskStore tasks, {CelebrationStore? preferences,
    DateTime Function()? clock, _Transport? transport, bool disposeAutomatically = true}) async {
  final engine = SyncEngine(tasks, transport ?? _Transport());
  await engine.load();
  final controller = AppController.forTesting(engine,
    celebrationStore: preferences, clock: clock ?? () => DateTime(2026, 10, 13, 18));
  await controller.loadCelebrationForTesting();
  if (disposeAutomatically) addTearDown(controller.dispose);
  return controller;
}

Map<String, dynamic> _seed(List<Task> tasks) => {
  'schema': 1, 'instance_id': 'celebration-test', 'cursor': 1,
  'tasks': tasks.map((task) => task.toJson()).toList(),
  'operations': [], 'attempted_ids': [], 'conflicts': [], 'last_synced_at': null,
};

void main() {
  test('Final explicit today completion celebrates once; undated and future tasks do not block', () async {
    final preferences = _Preferences();
    var now = DateTime(2026, 10, 13, 18);
    final controller = await _controller(_TaskStore(), preferences: preferences, clock: () => now);
    await controller.saveTask(const TaskDraft(title: 'First', listName: '学习', dueDate: '2026-10-13'));
    await controller.saveTask(const TaskDraft(title: 'Last', listName: '生活', dueDate: '2026-10-13'));
    await controller.saveTask(const TaskDraft(title: 'Undated'));
    await controller.saveTask(const TaskDraft(title: 'Tomorrow', dueDate: '2026-10-14'));
    await controller.saveTask(const TaskDraft(title: 'Overdue', dueDate: '2026-10-12'));
    await controller.saveTask(const TaskDraft(title: 'Deleted today', dueDate: '2026-10-13'));
    await controller.deleteTask(controller.tasks.last.id);
    final first = controller.tasks.firstWhere((task) => task.title == 'First').id;
    final last = controller.tasks.firstWhere((task) => task.title == 'Last').id;
    expect(await controller.setCompleted(first, true), isTrue);
    expect(controller.pendingDailyCelebration, isNull);
    expect(await controller.setCompleted(last, true), isTrue);
    expect(controller.pendingDailyCelebration?.taskCount, 2);
    expect(controller.pendingDailyCelebration?.day, '2026-10-13');
    expect(encouragements, contains(controller.pendingDailyCelebration?.message));
    expect((await preferences.read())?['pending'], isNotNull);
    expect((await controller.takeDailyCelebration())?.taskCount, 2);
    expect((await preferences.read())?['pending'], isNull);
    await controller.setCompleted(last, false);
    await controller.setCompleted(last, true);
    expect(controller.pendingDailyCelebration, isNull);
    now = DateTime(2026, 10, 14, 18);
    final tomorrow = controller.tasks.firstWhere((task) => task.title == 'Tomorrow').id;
    await controller.setCompleted(tomorrow, true);
    expect(controller.pendingDailyCelebration?.day, '2026-10-14');
  });

  test('No celebration for empty days, completed creation/edit, deletion, scheduling or non-today tasks', () async {
    final controller = await _controller(_TaskStore());
    await controller.saveTask(const TaskDraft(title: 'Already done', dueDate: '2026-10-13', completed: true));
    final done = controller.tasks.single.id;
    await controller.setCompleted(done, true);
    await controller.saveTask(const TaskDraft(title: 'Edited done', dueDate: '2026-10-13', completed: true), id: done);
    expect(controller.pendingDailyCelebration, isNull);
    await controller.saveTask(const TaskDraft(title: 'Remaining', dueDate: '2026-10-13'));
    await controller.deleteTask(controller.tasks.last.id);
    expect(controller.pendingDailyCelebration, isNull);
    await controller.saveTask(const TaskDraft(title: 'Unscheduled done', completed: true));
    await controller.scheduleTask(controller.tasks.last.id, '2026-10-13');
    expect(controller.pendingDailyCelebration, isNull);
    for (final date in [null, '2026-10-12', '2026-10-14']) {
      await controller.saveTask(TaskDraft(title: 'Outside today', dueDate: date));
      await controller.setCompleted(controller.tasks.last.id, true);
    }
    expect(controller.pendingDailyCelebration, isNull);
  });

  test('Failed task write rolls completion back and never creates a card; retry can succeed', () async {
    final tasks = _TaskStore();
    final controller = await _controller(tasks);
    await controller.saveTask(const TaskDraft(title: 'Today', dueDate: '2026-10-13'));
    tasks.fail = true;
    expect(await controller.setCompleted(controller.tasks.single.id, true), isFalse);
    expect(controller.tasks.single.completed, isFalse);
    expect(controller.pendingDailyCelebration, isNull);
    tasks.fail = false;
    expect(await controller.setCompleted(controller.tasks.single.id, true), isTrue);
    expect(controller.pendingDailyCelebration, isNotNull);
  });

  test('Task and daily marker must flush before encouragement is published', () async {
    final tasks = _TaskStore();
    final preferences = _Preferences();
    final controller = await _controller(tasks, preferences: preferences);
    await controller.saveTask(const TaskDraft(title: 'Today', dueDate: '2026-10-13'));
    tasks.gate = Completer<void>();
    preferences.gate = Completer<void>();
    final completion = controller.setCompleted(controller.tasks.single.id, true);
    await Future<void>.delayed(Duration.zero);
    expect(controller.pendingDailyCelebration, isNull);
    expect(preferences.writes, 0);
    tasks.gate!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(preferences.writes, 1);
    expect(controller.pendingDailyCelebration, isNull);
    preferences.gate!.complete();
    expect(await completion, isTrue);
    expect(controller.pendingDailyCelebration, isNotNull);
  });

  test('Preference failure preserves successful completion and does not retry-spam', () async {
    final preferences = _Preferences()..failWrite = true;
    final controller = await _controller(_TaskStore(), preferences: preferences);
    await controller.saveTask(const TaskDraft(title: 'Today', dueDate: '2026-10-13'));
    final id = controller.tasks.single.id;
    expect(await controller.setCompleted(id, true), isTrue);
    expect(controller.tasks.single.completed, isTrue);
    expect(controller.error, isNull);
    expect(controller.pendingDailyCelebration, isNull);
    await controller.setCompleted(id, false);
    await controller.setCompleted(id, true);
    expect(preferences.writes, 1);
  });

  test('Unreadable encouragement preference suppresses popup without blocking tasks', () async {
    final preferences = _Preferences()..failRead = true;
    final controller = await _controller(_TaskStore(), preferences: preferences);
    await controller.saveTask(const TaskDraft(title: 'Today', dueDate: '2026-10-13'));
    expect(await controller.setCompleted(controller.tasks.single.id, true), isTrue);
    expect(controller.pendingDailyCelebration, isNull);
    expect(preferences.writes, 0);
  });

  test('Persisted widget completion remains pending through restart and never replays after presentation', () async {
    final root = Platform.environment['NAS_TODO_TEST_TMP'];
    final base = Directory(root ?? Directory.systemTemp.path);
    await base.create(recursive: true);
    final directory = await base.createTemp('celebration-');
    addTearDown(() => directory.delete(recursive: true));
    final preferenceFile = File('${directory.path}/celebration.json');
    final tasks = _TaskStore();
    final first = await _controller(tasks, preferences: FileCelebrationStore(preferenceFile));
    await first.saveTask(const TaskDraft(title: 'Widget today', dueDate: '2026-10-13'));
    final id = first.tasks.single.id;
    final actions = [{'action_id': 'queued', 'task_id': id, 'completed': true}];
    expect(await applyWidgetActions(first, actions), ['queued']);
    final reopened = await _controller(tasks, preferences: FileCelebrationStore(preferenceFile));
    expect(reopened.pendingDailyCelebration?.taskCount, 1);
    expect(await applyWidgetActions(reopened, actions), ['queued']);
    expect(await reopened.takeDailyCelebration(), isNotNull);
    final third = await _controller(tasks, preferences: FileCelebrationStore(preferenceFile));
    expect(third.pendingDailyCelebration, isNull);
    await third.setCompleted(id, false);
    await third.setCompleted(id, true);
    expect(third.pendingDailyCelebration, isNull);
  });

  test('Late undo or date rollover during preference flush discards the pending card', () async {
    final preferences = _Preferences();
    var now = DateTime(2026, 10, 13, 18);
    final controller = await _controller(_TaskStore(), preferences: preferences, clock: () => now);
    await controller.saveTask(const TaskDraft(title: 'Today', dueDate: '2026-10-13'));
    final id = controller.tasks.single.id;
    await controller.setCompleted(id, true);
    preferences.gate = Completer<void>();
    final taking = controller.takeDailyCelebration();
    await Future<void>.delayed(Duration.zero);
    await controller.setCompleted(id, false);
    preferences.gate!.complete();
    expect(await taking, isNull);
    now = DateTime(2026, 10, 14);
    await controller.saveTask(const TaskDraft(title: 'New day', dueDate: '2026-10-14'));
    await controller.setCompleted(controller.tasks.last.id, true);
    now = DateTime(2026, 10, 15);
    expect(await controller.takeDailyCelebration(), isNull);
  });

  test('A preceding remote completion cannot be credited to a queued checkbox', () async {
    const before = Task(id: 'remote', title: 'Today', dueDate: '2026-10-13', version: 1, changeSeq: 1);
    final tasks = _TaskStore()..state = _seed([before]);
    final transport = _Transport()..gate = Completer<void>()
      ..changes = [before.copyWith(completed: true, version: 2, changeSeq: 2).toJson()];
    final controller = await _controller(tasks, transport: transport);
    final sync = controller.engine.sync();
    await transport.entered.future;
    final completion = controller.setCompleted('remote', true);
    transport.gate!.complete();
    await sync;
    expect(await completion, isTrue);
    expect(controller.tasks.single.completed, isTrue);
    expect(controller.pendingDailyCelebration, isNull);
  });

  test('Disposal during a daily marker write does not publish an event or notify dead listeners', () async {
    final preferences = _Preferences();
    final controller = await _controller(_TaskStore(), preferences: preferences, disposeAutomatically: false);
    await controller.saveTask(const TaskDraft(title: 'Today', dueDate: '2026-10-13'));
    preferences.gate = Completer<void>();
    final completion = controller.setCompleted(controller.tasks.single.id, true);
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    preferences.gate!.complete();
    expect(await completion, isTrue);
    expect(controller.pendingDailyCelebration, isNull);
  });
}
