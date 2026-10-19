import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_todo/app_controller.dart';
import 'package:nas_todo/sync_core.dart';
import 'package:nas_todo/ui/agenda_task.dart';
import 'package:nas_todo/ui/calendar_screen.dart';
import 'package:nas_todo/ui/task_editor.dart';

class _Store implements DataStore {
  Map<String, dynamic>? state;
  @override
  Future<Map<String, dynamic>?> read() async => state;
  @override
  Future<void> write(Map<String, dynamic> value) async => state = value;
}

class _Offline implements SyncTransport {
  @override
  Future<Map<String, dynamic>> sync(Map<String, dynamic> payload) async =>
      throw StateError('Calendar mode tests use local data.');
}

Future<AppController> _controller() async {
  final engine = SyncEngine(_Store(), _Offline());
  await engine.load();
  return AppController.forTesting(engine);
}

Future<void> _open(
  WidgetTester tester,
  AppController controller, {
  DateTime? date,
  Size size = const Size(1200, 900),
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: CalendarScreen(
          controller: controller,
          initialDate: date ?? DateTime(2024, 12, 31),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _view(WidgetTester tester, String value) async {
  final chip = find.byKey(ValueKey('calendar-view-$value'));
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Week contains all seven dates across a year and day shows all tasks',
    (tester) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      for (var index = 0; index < 12; index++) {
        await controller.saveTask(
          TaskDraft(
            title: '当天待办 $index',
            dueDate: '2024-12-31',
            completed: index == 0,
          ),
        );
      }
      await controller.saveTask(
        const TaskDraft(title: '下周日', dueDate: '2025-01-05'),
      );
      await controller.saveTask(
        const TaskDraft(title: '范围之外', dueDate: '2025-01-06'),
      );
      await _open(tester, controller);
      await _view(tester, 'week');
      for (final date in [
        '2024-12-30',
        '2024-12-31',
        '2025-01-01',
        '2025-01-02',
        '2025-01-03',
        '2025-01-04',
        '2025-01-05',
      ]) {
        expect(find.byKey(ValueKey('calendar-group-$date')), findsOneWidget);
      }
      expect(find.text('下周日'), findsOneWidget);
      expect(find.text('范围之外'), findsNothing);
      await _view(tester, 'day');
      expect(find.byType(AgendaTask), findsNWidgets(12));
      expect(find.text('下周日'), findsNothing);
      expect(
        tester.widget<Text>(find.text('当天待办 0')).style!.decoration,
        TextDecoration.lineThrough,
      );
      final last = controller.tasks.firstWhere(
        (task) => task.title == '当天待办 11',
      );
      final checkbox = find.byKey(ValueKey('complete-${last.id}'));
      await tester.ensureVisible(checkbox);
      await tester.pumpAndSettle();
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(
        controller.tasks.firstWhere((task) => task.id == last.id).completed,
        isTrue,
      );
      expect(
        tester.widget<Text>(find.text(last.title)).style!.decoration,
        TextDecoration.lineThrough,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Agenda includes every day of leap month and empty day creates with selected date',
    (tester) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      await controller.saveTask(
        const TaskDraft(title: '月末待办', dueDate: '2024-02-29'),
      );
      await _open(tester, controller, date: DateTime(2024, 2, 28));
      await _view(tester, 'agenda');
      for (var day = 1; day <= 29; day++) {
        expect(
          find.byKey(
            ValueKey(
              'calendar-group-2024-02-${day.toString().padLeft(2, '0')}',
            ),
          ),
          findsOneWidget,
        );
      }
      expect(find.text('月末待办'), findsOneWidget);
      await _view(tester, 'day');
      await tester.tap(find.byKey(const ValueKey('calendar-next')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('calendar-group-2024-02-29')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('calendar-next')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('calendar-group-2024-03-01')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('calendar-add-2024-03-01')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TaskEditorDialog>(find.byType(TaskEditorDialog))
            .initialDueDate,
        '2024-03-01',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in ['week', 'day']) {
    testWidgets('Undated task can be dragged into $mode date group', (
      tester,
    ) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      await controller.saveTask(
        const TaskDraft(
          title: '待安排',
          note: '保留备注',
          listName: '工作',
          priority: 2,
        ),
      );
      final id = controller.tasks.single.id;
      await _open(tester, controller, date: DateTime(2024, 2, 1));
      await _view(tester, mode);
      final targetDate = mode == 'week' ? '2024-01-29' : '2024-02-01';
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(ValueKey('drag-$id'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(-8, 0));
      await tester.pump();
      await gesture.moveTo(
        tester.getCenter(find.byKey(ValueKey('drop-$targetDate'))),
      );
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      final saved = controller.tasks.single;
      expect(saved.dueDate, targetDate);
      expect(saved.note, '保留备注');
      expect(saved.listName, '工作');
      expect(saved.priority, 2);
      expect(find.byType(AgendaTask), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('All calendar modes fit a 320px screen with large text', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    await controller.saveTask(
      const TaskDraft(title: '测试日期安排', dueDate: '2024-12-31'),
    );
    await _open(tester, controller, size: const Size(320, 844), scale: 1.8);
    for (final mode in ['week', 'day', 'agenda', 'month']) {
      await _view(tester, mode);
      expect(tester.takeException(), isNull, reason: '$mode must not overflow');
      final viewport = tester.getRect(
        find.byKey(const ValueKey('calendar-viewport')),
      );
      expect(viewport.left, greaterThanOrEqualTo(0));
      expect(viewport.right, lessThanOrEqualTo(320));
    }
  });
}
