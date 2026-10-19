import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_todo/app_controller.dart';
import 'package:nas_todo/main.dart';
import 'package:nas_todo/sync_core.dart';
import 'package:nas_todo/task_dates.dart';
import 'package:nas_todo/ui/calendar_screen.dart';

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
      throw StateError('Calendar layout tests use local data.');
}

Future<AppController> _controller() async {
  final engine = SyncEngine(_Store(), _Offline());
  await engine.load();
  return AppController.forTesting(engine);
}

void _size(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _openAppCalendar(
    WidgetTester tester, AppController controller) async {
  await tester.pumpWidget(PrivateTodoApp(controller: controller));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(NavigationBar).evaluate().isNotEmpty
      ? find.text('日历').last : find.byTooltip('日历'));
  await tester.pumpAndSettle();
}

Future<void> _standaloneCalendar(WidgetTester tester,
    AppController controller, DateTime date) async {
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: CalendarScreen(controller: controller, initialDate: date))));
  await tester.pumpAndSettle();
}

Finder _day(DateTime date) => find.byKey(ValueKey('day-${dateKey(date)}'));

Finder get _viewport => find.byKey(const ValueKey('calendar-viewport'));

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(find
        .descendant(of: _viewport, matching: find.byType(Scrollable))
        .first)
    .position;

void _inside(Rect child, Rect parent, {bool vertical = true}) {
  expect(child.left, greaterThanOrEqualTo(parent.left - 0.5));
  expect(child.right, lessThanOrEqualTo(parent.right + 0.5));
  if (vertical) {
    expect(child.top, greaterThanOrEqualTo(parent.top - 0.5));
    expect(child.bottom, lessThanOrEqualTo(parent.bottom + 0.5));
  }
}

Future<void> _mousePan(WidgetTester tester, Offset from, Offset delta) async {
  final gesture = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
  await gesture.moveBy(delta / 2);
  await tester.pump(const Duration(milliseconds: 30));
  await gesture.moveBy(delta / 2);
  await tester.pump(const Duration(milliseconds: 30));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('All twelve tasks for today are reachable and completion stays visible on $platform',
        (tester) async {
      _size(tester, platform == TargetPlatform.android ? const Size(320, 568) : const Size(1280, 800));
      final controller = await _controller();
      addTearDown(controller.dispose);
      final today = dateKey(DateTime.now());
      for (var index = 0; index < 12; index++) {
        await controller.saveTask(TaskDraft(title: '今天的待办 ${index.toString().padLeft(2, "0")}', dueDate: today));
      }
      await controller.saveTask(TaskDraft(title: '已删除的待办', dueDate: today));
      final deletedId = controller.tasks.last.id;
      await controller.deleteTask(deletedId);
      await _openAppCalendar(tester, controller);
      final tasks = controller.tasks.where((task) => !task.deleted).toList();
      for (final task in tasks) {
        expect(find.byKey(ValueKey('calendar-title-${task.id}')), findsOneWidget);
      }
      expect(find.byKey(ValueKey('calendar-title-$deletedId')), findsNothing);
      final last = tasks.last;
      final title = find.byKey(ValueKey('calendar-title-${last.id}'));
      await tester.ensureVisible(title);
      await tester.pumpAndSettle();
      _inside(tester.getRect(title), tester.getRect(_viewport));
      expect(_position(tester).pixels, greaterThan(0));
      await tester.tap(find.byKey(ValueKey('calendar-complete-${last.id}')));
      await tester.pumpAndSettle();
      expect(controller.tasks.firstWhere((task) => task.id == last.id).completed, isTrue);
      expect(tester.widget<Text>(title).style!.decoration, TextDecoration.lineThrough);
      for (final task in tasks) {
        expect(find.byKey(ValueKey('calendar-title-${task.id}')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant({platform}));
  }

  testWidgets('Expanded dates with enlarged text keep every task inside their cell', (tester) async {
    _size(tester, const Size(320, 568));
    final controller = await _controller();
    addTearDown(controller.dispose);
    for (var index = 0; index < 8; index++) {
      await controller.saveTask(TaskDraft(title: '放大字体任务 $index', dueDate: '2025-03-31'));
    }
    await tester.pumpWidget(MaterialApp(builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.5)), child: child!),
      home: Scaffold(body: CalendarScreen(controller: controller, initialDate: DateTime(2025, 3)))));
    await tester.pumpAndSettle();
    final cell = tester.getRect(_day(DateTime(2025, 3, 31)));
    for (final task in controller.tasks) {
      final title = find.byKey(ValueKey('calendar-title-${task.id}'));
      expect(title, findsOneWidget);
      _inside(tester.getRect(title), cell);
    }
    await tester.ensureVisible(find.byKey(const ValueKey('more-2025-03-31')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));

  for (final size in const [
    Size(390, 844),
    Size(390, 500),
    Size(320, 568),
    Size(1280, 800),
    Size(900, 650),
  ]) {
    testWidgets('Full app ${size.width}x${size.height} keeps all seven columns '
        'inside the calendar and its new-task button outside the tray',
        (tester) async {
      _size(tester, size);
      final controller = await _controller();
      addTearDown(controller.dispose);
      final now = DateTime.now();
      for (var i = 0; i < 4; i++) {
        await controller.saveTask(TaskDraft(
            title: '窄屏仍能显示的待办 $i', dueDate: dateKey(now)));
      }
      await controller.saveTask(const TaskDraft(title: '可拖动的未安排待办'));
      await _openAppCalendar(tester, controller);

      final first = DateTime(now.year, now.month);
      final start = DateTime(first.year, first.month, 2 - first.weekday);
      final viewport = tester.getRect(_viewport);
      for (var i = 0; i < 7; i++) {
        final date = DateTime(start.year, start.month, start.day + i);
        _inside(tester.getRect(_day(date)), viewport, vertical: false);
      }
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('新建待办'), findsOneWidget);
      final newTask = tester.getRect(find.text('新建待办'));
      final tray = tester
          .getRect(find.byKey(const ValueKey('unscheduled-tray')));
      expect(newTask.overlaps(tray), isFalse);
      if (size == const Size(1280, 800)) {
        _inside(tester.getRect(_day(first)), viewport);
        // Busy weeks grow to show all tasks; scrolling keeps month end reachable.
        await tester.ensureVisible(_day(DateTime(now.year, now.month + 1, 0)));
        await tester.pumpAndSettle();
        _inside(tester.getRect(_day(DateTime(now.year, now.month + 1, 0))),
            viewport);
      }
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant({
      size.width < 600 ? TargetPlatform.android : TargetPlatform.windows,
    }));
  }

  for (final month in [DateTime(2021, 2), DateTime(2025, 3)]) {
    testWidgets('Phone overview fits the entire ${month.year}-${month.month} '
        'month, including a six-week month, without horizontal panning',
        (tester) async {
      _size(tester, const Size(390, 844));
      final controller = await _controller();
      addTearDown(controller.dispose);
      await _standaloneCalendar(tester, controller, month);
      final viewport = tester.getRect(_viewport);
      final last = DateTime(month.year, month.month + 1, 0);
      for (var i = 1; i <= last.day; i++) {
        _inside(tester.getRect(_day(DateTime(month.year, month.month, i))),
            viewport);
      }
      // February 2021 starts on Monday and needs exactly four rows.
      // March 2025 starts on Saturday and needs its sixth row to show March 31.
      if (month.year == 2021) {
        expect(_day(DateTime(2021, 3, 1)), findsNothing);
      } else {
        expect(_day(DateTime(2025, 4, 6)), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }, variant: const TargetPlatformVariant({TargetPlatform.android}));
  }

  testWidgets('A real Windows mouse can drag a short calendar to the last week',
      (tester) async {
    _size(tester, const Size(900, 420));
    final controller = await _controller();
    addTearDown(controller.dispose);
    await _standaloneCalendar(tester, controller, DateTime(2025, 3));
    final viewport = tester.getRect(_viewport);
    final position = _position(tester);
    expect(position.maxScrollExtent, greaterThan(0));
    final scrollbar = tester.widget<Scrollbar>(
        find.byKey(const ValueKey('calendar-scrollbar')));
    expect(scrollbar.thumbVisibility, isTrue);
    expect(scrollbar.interactive, isTrue);

    await _mousePan(tester, Offset(viewport.center.dx, viewport.bottom - 40),
        const Offset(0, -160));
    expect(position.pixels, greaterThan(0));
    for (var i = 0;
        i < 8 && position.pixels < position.maxScrollExtent - 0.5;
        i++) {
      await _mousePan(tester, Offset(viewport.center.dx, viewport.bottom - 40),
          const Offset(0, -160));
    }
    _inside(tester.getRect(_day(DateTime(2025, 3, 31))), viewport);
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.windows}));

  testWidgets('Compact populated last-week cells expand without clipping '
      'and still reveal every task', (tester) async {
    _size(tester, const Size(320, 568));
    final controller = await _controller();
    addTearDown(controller.dispose);
    for (var i = 0; i < 5; i++) {
      await controller.saveTask(TaskDraft(
          title: '很长的最后一周待办名称 $i', dueDate: '2025-03-31'));
    }
    await _standaloneCalendar(tester, controller, DateTime(2025, 3));
    final more = find.byKey(const ValueKey('more-2025-03-31'));
    await tester.ensureVisible(more);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(more);
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    for (var i = 0; i < 5; i++) {
      final task = find.descendant(
          of: sheet, matching: find.text('很长的最后一周待办名称 $i'));
      await tester.scrollUntilVisible(task, 120,
          scrollable: find
              .descendant(of: sheet, matching: find.byType(Scrollable))
              .first);
      expect(task, findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('Phone calendar header creates a task on the selected date '
      'without a floating overlay', (tester) async {
    _size(tester, const Size(390, 844));
    final controller = await _controller();
    addTearDown(controller.dispose);
    await _openAppCalendar(tester, controller);
    final now = DateTime.now();
    final selected = DateTime(now.year, now.month, 15);
    await tester.ensureVisible(_day(selected));
    await tester.pumpAndSettle();
    await tester.tap(_day(selected));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.tap(find.text('新建待办'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('task-title')), '通过日历工具栏新建');
    await tester.tap(find.text('保存到本机'));
    await tester.pumpAndSettle();
    expect(controller.tasks.single.dueDate, dateKey(selected));
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));
}
