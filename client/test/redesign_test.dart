import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_todo/achievement_core.dart';
import 'package:nas_todo/habit_achievement.dart';
import 'package:nas_todo/personal_core.dart';
import 'package:nas_todo/app_controller.dart';
import 'package:nas_todo/appearance.dart';
import 'package:nas_todo/main.dart';
import 'package:nas_todo/sync_core.dart';
import 'package:nas_todo/ui/task_editor.dart';

class _Store implements DataStore {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> state) async =>
      value = Map<String, dynamic>.from(jsonDecode(jsonEncode(state)) as Map);
}

class _Offline implements SyncTransport {
  @override
  Future<Map<String, dynamic>> sync(Map<String, dynamic> payload) async =>
      throw StateError('offline');
}

Future<AppController> _controller({AppearanceStore? appearance}) async {
  final engine = SyncEngine(_Store(), _Offline());
  await engine.load();
  final controller = AppController.forTesting(
    engine,
    appearanceStore: appearance,
  );
  await controller.loadAppearanceForTesting();
  addTearDown(controller.dispose);
  return controller;
}

void _size(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

const _id = '00000000-0000-4000-8000-000000000001';

void main() {
  test('Both categories must reach eighty percent; count goals weigh one habit-day', () {
    final tasks = [
      for (var i = 0; i < 20; i++)
        Task(id: '$i', title: '完成', completed: true, dueDate: '2026-10-05'),
    ];
    const plan = HabitAchievementPlan(
      habitId: _id,
      effectiveFrom: '2026-10-05',
      goal: 8,
      weekdays: [1, 2, 3, 4, 5],
    );
    final checks = [
      for (var d = 5; d < 10; d++)
        HabitCheckIn(
          id: '$_id:2026-10-0$d',
          habitId: _id,
          date: '2026-10-0$d',
          value: d < 8 ? 8 : 7,
        ),
    ];
    var report = calculateAchievement(
      '2026-10',
      tasks,
      habitPlans: [plan],
      checkins: checks,
      through: DateTime(2026, 10, 9),
      includeHabits: true,
    );
    expect(report.weeks[1].habitTotal, 5);
    expect(report.weeks[1].habitCompleted, 3);
    expect(report.weeks[1].star, isFalse);
    checks[3] = const HabitCheckIn(
      id: 'water',
      habitId: _id,
      date: '2026-10-08',
      value: 100,
    );
    report = calculateAchievement(
      '2026-10',
      tasks,
      habitPlans: [plan],
      checkins: checks,
      through: DateTime(2026, 10, 9),
      includeHabits: true,
    );
    expect(report.weeks[1].star, isTrue);
    expect(
      MonthAchievement.fromJson(report.toJson()).weeks[1].habitCompleted,
      4,
    );
  });
  test(
    'Plan changes retain earlier targets and exclude future and rest days',
    () {
      const plans = [
        HabitAchievementPlan(
          habitId: _id,
          effectiveFrom: '2026-10-01',
          goal: 8,
          weekdays: [4, 5],
        ),
        HabitAchievementPlan(
          habitId: _id,
          effectiveFrom: '2026-10-02',
          goal: 10,
          weekdays: [4, 5],
        ),
      ];
      final report = calculateAchievement(
        '2026-10',
        [],
        habitPlans: plans,
        checkins: const [
          HabitCheckIn(id: 'a', habitId: _id, date: '2026-10-01', value: 8),
          HabitCheckIn(id: 'b', habitId: _id, date: '2026-10-02', value: 8),
        ],
        through: DateTime(2026, 10, 2),
        includeHabits: true,
      );
      expect(report.taskTotal, 0);
      expect(report.habitTotal, 2);
      expect(report.habitCompleted, 1);
      expect(report.stars, 0);
      expect(report.weeks[1].total, 0);
    },
  );
  test('Display choices survive restart and concurrent theme writes without touching tasks', () async {
    final store = MemoryAppearanceStore();
    final first = await _controller(appearance: store);
    await Future.wait([
      first.setWorkspace({
        'matrix_enabled': true,
        'presentation': 'matrix',
        'scroll_offset': 123.0,
      }),
      first.setAppearance(TodoThemeColor.blue, TodoThemeColor.white),
    ]);
    final next = await _controller(appearance: store);
    expect(next.workspace.matrixEnabled, isTrue);
    expect(next.workspace.presentation, 'matrix');
    expect(next.workspace.scrollOffset, 123);
    expect(next.appTheme, TodoThemeColor.blue);
    expect(next.tasks, isEmpty);
    await next.setWorkspace({'matrix_enabled': false});
    expect(next.workspace.presentation, 'list');
  });
  testWidgets(
    'Matrix is optional and phone modules directly expose habits and achievements',
    (tester) async {
      _size(tester, const Size(390, 844));
      final controller = await _controller();
      await tester.pumpWidget(PrivateTodoApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text('四象限'), findsNothing);
      expect(find.text('习惯'), findsOneWidget);
      expect(find.text('成就'), findsOneWidget);
      await controller.setWorkspace({'matrix_enabled': true});
      await tester.pumpAndSettle();
      expect(find.text('四象限'), findsOneWidget);
      await tester.tap(find.text('习惯'));
      await tester.pumpAndSettle();
      expect(find.text('让小事慢慢长大'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Phone editor expands, protects input on close and saves above the keyboard',
    (tester) async {
      _size(tester, const Size(390, 844));
      final controller = await _controller();
      await tester.pumpWidget(PrivateTodoApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('完整新建'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('task-title')),
        '保留我的输入',
      );
      await tester.tap(find.byTooltip('全屏编辑'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭编辑器'));
      await tester.pumpAndSettle();
      expect(find.text('保留正在编辑的内容？'), findsOneWidget);
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      expect(find.text('保留我的输入'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final save = find.text('保存到本机');
      expect(tester.getBottomRight(save).dy, lessThanOrEqualTo(604));
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(controller.tasks.single.title, '保留我的输入');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Desktop editing stays inline and navigation asks before discarding',
    (tester) async {
      _size(tester, const Size(1440, 900));
      final controller = await _controller();
      await controller.saveTask(const TaskDraft(title: '原任务'));
      await tester.pumpWidget(PrivateTodoApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部待办').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('原任务'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑待办'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskEditorDialog), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('task-title')), '尚未保存');
      await tester.tap(find.byTooltip('日历'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      expect(find.text('尚未保存'), findsOneWidget);
      expect(controller.tasks.single.title, '原任务');
      expect(tester.takeException(), isNull);
    },
  );
}
