import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_todo/app_controller.dart';
import 'package:nas_todo/main.dart';
import 'package:nas_todo/personal_core.dart';
import 'package:nas_todo/sync_core.dart';
import 'package:nas_todo/ui/habits_screen.dart';
import 'package:nas_todo/ui/task_editor.dart';

class _Store implements DataStore {
  Map<String, dynamic>? state;
  @override
  Future<Map<String, dynamic>?> read() async => state;
  @override
  Future<void> write(Map<String, dynamic> value) async {
    state = Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  }
}

class _Offline implements SyncTransport {
  @override
  Future<Map<String, dynamic>> sync(Map<String, dynamic> value) async =>
      throw StateError('offline widget test');
}

Future<AppController> _controller([_Store? store]) async {
  final engine = SyncEngine(
    store ?? _Store(),
    _Offline(),
    clock: () => DateTime(2026, 10, 19),
  );
  await engine.load();
  final controller = AppController.forTesting(engine);
  addTearDown(controller.dispose);
  return controller;
}

void _size(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _habits(
  WidgetTester tester,
  AppController controller, {
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: HabitsScreen(
          controller: controller,
          clock: () => DateTime(2026, 10, 20),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _drawer(WidgetTester tester, String text) async {
  await tester.tap(find.byTooltip('清单与智能视图'));
  await tester.pumpAndSettle();
  final target = find.descendant(
    of: find.byType(Drawer),
    matching: find.text(text),
  );
  await tester.scrollUntilVisible(
    target,
    140,
    scrollable: find
        .descendant(of: find.byType(Drawer), matching: find.byType(Scrollable))
        .first,
  );
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Habit can be created, checked and undone offline on a narrow phone',
    (tester) async {
      _size(tester, const Size(320, 568));
      final controller = await _controller();
      await _habits(tester, controller);
      await tester.tap(find.byKey(const ValueKey('habit-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('habit-name')), '每天阅读');
      await tester.ensureVisible(find.byKey(const ValueKey('habit-save')));
      await tester.tap(find.byKey(const ValueKey('habit-save')));
      await tester.pumpAndSettle();
      final id = controller.habits.single.id;
      final button = find.byKey(ValueKey('habit-check-$id'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(controller.habitCheckIns.single.value, 1);
      expect(find.text('今天已打卡'), findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(controller.habitCheckIns.single.value, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Counter goals retain their value after reopening and history supports backfill',
    (tester) async {
      _size(tester, const Size(390, 844));
      final store = _Store();
      final controller = await _controller(store);
      await controller.saveHabit(
        const HabitDraft(name: '喝水', goalType: 'count', goal: 3),
      );
      final id = controller.habits.single.id;
      await _habits(tester, controller);
      await tester.tap(find.byKey(ValueKey('habit-plus-$id')));
      await tester.pumpAndSettle();
      expect(controller.habitCheckIns.single.value, 1);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('habit-history-expand')),
        180,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('habits-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('habit-history-expand')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('打卡历史'));
      await tester.pumpAndSettle();
      final history = find.byKey(ValueKey('habit-history-$id-2026-10-19'));
      await tester.scrollUntilVisible(
        history,
        250,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('habits-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(history);
      await tester.pumpAndSettle();
      expect(history.hitTestable(), findsOneWidget);
      await tester.tap(history);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('habit-history-value')),
        '3',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(
        controller.habitCheckIns
            .firstWhere((item) => item.date == '2026-10-19')
            .value,
        3,
      );
      final reopened = await _controller(store);
      await _habits(tester, reopened);
      expect(
        reopened.habitCheckIns
            .firstWhere((item) => item.date == '2026-10-20')
            .value,
        1,
      );
      expect(
        reopened.habitCheckIns
            .firstWhere((item) => item.date == '2026-10-19')
            .value,
        3,
      );
      expect(find.text('喝水'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Habit cards and month history remain scrollable at 320 pixels and large text',
    (tester) async {
      _size(tester, const Size(320, 844));
      final controller = await _controller();
      await controller.saveHabit(
        const HabitDraft(name: '阅读和记录今天看到的新知识', goalType: 'count', goal: 8),
      );
      await _habits(tester, controller, scale: 1.8);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('habit-history-expand')),
        180,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('habits-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('habit-history-expand')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('打卡历史'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('habit-month-grid')),
        250,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('habits-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('2026年10月'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Task tree expands and popup creates a child with its actual parent',
    (tester) async {
      _size(tester, const Size(1440, 900));
      final controller = await _controller();
      await controller.saveTask(const TaskDraft(title: '写计划'));
      final parent = controller.tasks.single;
      await controller.saveTask(TaskDraft(title: '第一步', parentId: parent.id));
      await tester.pumpWidget(PrivateTodoApp(controller: controller));
      await tester.pumpAndSettle();
      await _drawer(tester, '全部待办');
      await tester.tap(find.byKey(ValueKey('task-expand-${parent.id}')));
      await tester.pumpAndSettle();
      expect(find.text('第一步'), findsNothing);
      await tester.tap(find.byKey(ValueKey('task-expand-${parent.id}')));
      await tester.pumpAndSettle();
      expect(find.text('第一步'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('task-menu-${parent.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加子任务'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('task-title')), '第二步');
      await tester.tap(find.text('保存到本机'));
      await tester.pumpAndSettle();
      expect(
        controller.tasks.firstWhere((task) => task.title == '第二步').parentId,
        parent.id,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Tag filter and quick add use existing tags without creating hidden tasks',
    (tester) async {
      _size(tester, const Size(390, 844));
      final controller = await _controller();
      await controller.saveTask(const TaskDraft(title: '学习任务', tags: ['学习']));
      await controller.saveTask(const TaskDraft(title: '其他任务'));
      await tester.pumpWidget(PrivateTodoApp(controller: controller));
      await tester.pumpAndSettle();
      await _drawer(tester, '#学习');
      expect(find.text('学习任务'), findsOneWidget);
      expect(find.text('其他任务'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('workbench-quick-add')),
        '新的学习',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(controller.tasks.firstWhere((task) => task.title == '新的学习').tags, [
        '学习',
      ]);
      expect(find.text('新的学习'), findsOneWidget);
      await _drawer(tester, '习惯');
      expect(find.byType(HabitsScreen), findsOneWidget);
      expect(find.text('番茄钟'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Task editor stores tags and an actual repeat rule with the arranged date',
    (tester) async {
      _size(tester, const Size(390, 844));
      final controller = await _controller();
      await controller.saveTask(
        const TaskDraft(title: '安排阅读', dueDate: '2099-10-20'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showTaskEditor(
                  context,
                  controller,
                  task: controller.tasks.single,
                ),
                child: const Text('打开编辑'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开编辑'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('task-personal-options')),
      );
      await tester.tap(find.byKey(const ValueKey('task-personal-options')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('task-tags')), '学习，阅读');
      await tester.ensureVisible(find.byKey(const ValueKey('task-repeat')));
      await tester.tap(find.byKey(const ValueKey('task-repeat')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('按天重复').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存到本机'));
      await tester.pumpAndSettle();
      expect(controller.tasks.single.tags, ['学习', '阅读']);
      expect(controller.tasks.single.repeatRule!.frequency, 'daily');
      expect(controller.tasks.single.dueDate, '2099-10-20');
      expect(tester.takeException(), isNull);
    },
  );
}
