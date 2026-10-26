import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_todo/app_controller.dart';
import 'package:nas_todo/main.dart';
import 'package:nas_todo/sync_core.dart';
import 'package:nas_todo/weekly_plan.dart';
import 'package:nas_todo/ui/weekly_plan_screen.dart';

class _Store implements DataStore {
  Map<String, dynamic>? state;
  bool fail = false;
  @override
  Future<Map<String, dynamic>?> read() async => state;
  @override
  Future<void> write(Map<String, dynamic> value) async {
    if (fail) throw StateError('disk full');
    state = Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  }
}

class _Offline implements SyncTransport {
  @override
  Future<Map<String, dynamic>> sync(Map<String, dynamic> value) async =>
      throw StateError('offline');
}

Future<SyncEngine> _engine(_Store store) async {
  final engine = SyncEngine(store, _Offline());
  await engine.load();
  return engine;
}

Future<AppController> _controller() async {
  final controller = AppController.forTesting(await _engine(_Store()));
  addTearDown(controller.dispose);
  return controller;
}

void _size(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  test(
    'Deleting a category keeps all task fields and metadata through restart',
    () async {
      final store = _Store();
      final engine = await _engine(store);
      await engine.saveTask(
        const TaskDraft(
          title: '父待办',
          listName: '研究',
          dueDate: '2026-10-27',
          note: '保留备注',
          priority: 2,
          tags: ['论文'],
        ),
      );
      final parent = engine.tasks.single;
      await engine.saveTask(
        TaskDraft(
          title: '已完成子项',
          listName: '研究',
          completed: true,
          parentId: parent.id,
        ),
      );
      await engine.saveTask(const TaskDraft(title: '其他分类', listName: '生活'));
      final before = engine.tasks
          .where((t) => t.listName == '研究')
          .map((t) => TaskDraft.fromTask(t).toJson())
          .toList();
      await engine.deleteList('研究');
      expect(engine.tasks.where((t) => t.listName == '研究'), isEmpty);
      final moved = engine.tasks
          .where((t) => t.listName == '收件箱')
          .map((t) => TaskDraft.fromTask(t).toJson())
          .toList();
      expect(
        moved,
        before.map((value) => {...value, 'list_name': '收件箱'}).toList(),
      );
      expect(engine.tasks.every((t) => !t.deleted), isTrue);
      final restarted = await _engine(store);
      expect(
        restarted.tasks.map((t) => t.toJson()),
        engine.tasks.map((t) => t.toJson()),
      );
      expect(
        restarted.tasks.singleWhere((t) => t.title == '其他分类').listName,
        '生活',
      );
    },
  );

  test(
    'A failed category move rolls back the entire list and both outboxes',
    () async {
      final store = _Store();
      final engine = await _engine(store);
      for (var i = 0; i < 3; i++) {
        await engine.saveTask(
          TaskDraft(title: '任务$i', listName: '研究', tags: ['标签']),
        );
      }
      final disk = jsonEncode(store.state);
      final tasks = jsonEncode(engine.tasks.map((t) => t.toJson()).toList());
      store.fail = true;
      await expectLater(engine.deleteList('研究'), throwsStateError);
      expect(jsonEncode(store.state), disk);
      expect(jsonEncode(engine.tasks.map((t) => t.toJson()).toList()), tasks);
      await expectLater(engine.deleteList('收件箱'), throwsArgumentError);
    },
  );

  test(
    'Week dates span year boundaries; unscheduled weekly tasks carry forward',
    () {
      final days = weekDates(DateTime(2027, 1, 1));
      expect(days.first, DateTime(2026, 12, 28));
      expect(days.last, DateTime(2027, 1, 3));
      const tasks = [
        Task(id: 'pool', title: '周目标', listName: weeklyListName),
        Task(id: 'rest', title: '无日期普通待办'),
        Task(
          id: 'done',
          title: '已完成周目标',
          listName: weeklyListName,
          completed: true,
        ),
        Task(id: 'today', title: '工作安排', listName: '工作', dueDate: '2027-01-01'),
        Task(
          id: 'deleted',
          title: '已删除',
          listName: weeklyListName,
          deleted: true,
        ),
      ];
      expect(weeklyPool(tasks).map((t) => t.id), ['pool']);
      expect(weeklyDayTasks(tasks, DateTime(2027, 1, 1)).single.id, 'today');
      expect(weeklyDayTasks(tasks, DateTime(2027, 1, 4)), isEmpty);
      expect(weeklyPool(tasks).single.dueDate, isNull);
    },
  );

  for (final size in [const Size(320, 568), const Size(1440, 900)]) {
    testWidgets('Weekly pool adds and schedules to any weekday at $size', (
      tester,
    ) async {
      _size(tester, size);
      final controller = await _controller();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WeeklyPlanScreen(
              controller: controller,
              onEdit: (_) {},
              clock: () => DateTime(2026, 10, 27),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('weekly-quick-add')),
        '完成本周计划',
      );
      await tester.tap(find.byTooltip('添加周待办'));
      await tester.pumpAndSettle();
      final task = controller.tasks.single;
      expect(task.listName, weeklyListName);
      expect(task.dueDate, isNull);
      await tester.tap(find.byKey(ValueKey('weekly-schedule-${task.id}')));
      await tester.pumpAndSettle();
      final sunday = find.byKey(const ValueKey('weekly-pick-2026-11-01'));
      await tester.ensureVisible(sunday);
      await tester.tap(sunday);
      await tester.pumpAndSettle();
      expect(controller.tasks.single.dueDate, '2026-11-01');
      expect(weeklyPool(controller.tasks), isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Desktop drag changes only the chosen day and keeps existing classification',
    (tester) async {
      _size(tester, const Size(1440, 1000));
      final controller = await _controller();
      await controller.saveTask(
        const TaskDraft(
          title: '安排好的工作',
          listName: '工作',
          dueDate: '2026-10-26',
          tags: ['标签'],
          note: '备注',
        ),
      );
      final task = controller.tasks.single;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WeeklyPlanScreen(
              controller: controller,
              onEdit: (_) {},
              clock: () => DateTime(2026, 10, 27),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.dragFrom(
        tester.getCenter(find.text('安排好的工作')),
        tester.getCenter(find.byKey(const ValueKey('weekly-day-2026-10-28'))) -
            tester.getCenter(find.text('安排好的工作')),
      );
      await tester.pumpAndSettle();
      final moved = controller.tasks.single;
      expect(moved.dueDate, '2026-10-28');
      expect(moved.listName, '工作');
      expect(moved.note, '备注');
      expect(moved.tags, ['标签']);
      expect(moved.id, task.id);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Category deletion is reachable and keeps completed items', (
    tester,
  ) async {
    _size(tester, const Size(1440, 900));
    final controller = await _controller();
    await controller.saveTask(const TaskDraft(title: '保留待办', listName: '研究'));
    await controller.saveTask(
      const TaskDraft(title: '完成也保留', listName: '研究', completed: true),
    );
    await tester.pumpWidget(PrivateTodoApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('list-menu-研究')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除分类'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除分类'));
    await tester.pumpAndSettle();
    expect(controller.tasks.length, 2);
    expect(
      controller.tasks.every((t) => t.listName == '收件箱' && !t.deleted),
      isTrue,
    );
    expect(
      controller.tasks.singleWhere((t) => t.title == '完成也保留').completed,
      isTrue,
    );
    expect(find.byKey(const ValueKey('list-menu-研究')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
