import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_todo/app_controller.dart';
import 'package:nas_todo/sync_core.dart';
import 'package:nas_todo/ui/calendar_screen.dart';

class _Store implements DataStore {
  Map<String, dynamic>? state;
  bool fail = false;
  @override
  Future<Map<String, dynamic>?> read() async => state;
  @override
  Future<void> write(Map<String, dynamic> value) async {
    if (fail) throw StateError('磁盘已满');
    state = Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  }
}

class _Offline implements SyncTransport {
  @override
  Future<Map<String, dynamic>> sync(Map<String, dynamic> payload) async => throw StateError('Offline');
}

Future<AppController> _controller(_Store store) async {
  final engine = SyncEngine(store, _Offline());
  await engine.load();
  return AppController.forTesting(engine);
}

Future<void> _screen(WidgetTester tester, AppController controller, {bool phone = false}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = phone ? const Size(390, 844) : const Size(1200, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MaterialApp(theme: ThemeData(
    platform: phone ? TargetPlatform.android : TargetPlatform.windows,
  ), home: Scaffold(body: CalendarScreen(controller: controller, initialDate: DateTime(2024, 2, 1)))));
  await tester.pumpAndSettle();
}

Future<void> _drop(WidgetTester tester, String id, {bool phone = false, bool cancel = false}) async {
  final source = find.byKey(ValueKey('drag-$id'));
  final target = find.byKey(const ValueKey('drop-2024-02-01'));
  final gesture = await tester.startGesture(tester.getCenter(source),
    kind: phone ? PointerDeviceKind.touch : PointerDeviceKind.mouse);
  if (phone) await tester.pump(const Duration(milliseconds: 350));
  await gesture.moveBy(const Offset(0, -8));
  await tester.pump();
  await gesture.moveTo(cancel ? const Offset(-30, -30) : tester.getCenter(target));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  test('Scheduling preserves every other field, survives restart, and coalesces retries', () async {
    final store = _Store();
    final controller = await _controller(store);
    addTearDown(controller.dispose);
    await controller.saveTask(const TaskDraft(title: '保留所有内容', note: '私人备注', listName: '生活', priority: 2, completed: true));
    final id = controller.tasks.single.id;
    expect(await controller.scheduleTask(id, '2024-02-29'), isTrue);
    final task = controller.tasks.single;
    expect([task.id, task.title, task.note, task.listName, task.priority, task.completed, task.dueDate],
      [id, '保留所有内容', '私人备注', '生活', 2, true, '2024-02-29']);
    final pending = controller.pendingCount;
    expect(await controller.scheduleTask(id, '2024-02-29'), isTrue);
    expect(controller.pendingCount, pending);
    final reopened = await _controller(store);
    addTearDown(reopened.dispose);
    expect(reopened.tasks.single.dueDate, '2024-02-29');
    expect(reopened.tasks.single.id, id);
    expect(reopened.pendingCount, 1);
  });

  test('Failed scheduling keeps both the original date and durable outbox for retry', () async {
    final store = _Store();
    final controller = await _controller(store);
    addTearDown(controller.dispose);
    await controller.saveTask(const TaskDraft(title: '安排失败'));
    final id = controller.tasks.single.id;
    final before = jsonEncode(store.state);
    store.fail = true;
    expect(await controller.scheduleTask(id, '2024-02-29'), isFalse);
    expect(controller.tasks.single.dueDate, isNull);
    expect(jsonEncode(store.state), before);
    expect(controller.error, contains('磁盘已满'));
    store.fail = false;
    expect(await controller.scheduleTask(id, '2024-02-29'), isTrue);
  });

  test('A stale drag cannot overwrite a date assigned elsewhere or recreate a deleted task', () async {
    final controller = await _controller(_Store());
    addTearDown(controller.dispose);
    await controller.saveTask(const TaskDraft(title: '已被安排', dueDate: '2024-02-20'));
    final id = controller.tasks.single.id;
    expect(await controller.scheduleTask(id, '2024-02-29'), isFalse);
    expect(controller.tasks.single.dueDate, '2024-02-20');
    await controller.deleteTask(id);
    expect(await controller.scheduleTask(id, '2024-02-29'), isFalse);
    expect(controller.tasks, isEmpty);
  });

  test('Invalid dates and unresolved conflicts cannot schedule tasks', () async {
    final store = _Store();
    final controller = await _controller(store);
    addTearDown(controller.dispose);
    await controller.saveTask(const TaskDraft(title: '未安排'));
    final task = controller.tasks.single;
    expect(await controller.scheduleTask(task.id, '2024-02-30'), isFalse);
    expect(controller.tasks.single.dueDate, isNull);
    store.state!['conflicts'] = [SyncConflict(taskId: task.id, local: task, remote: task).toJson()];
    final conflicted = await _controller(store);
    addTearDown(conflicted.dispose);
    expect(await conflicted.scheduleTask(task.id, '2024-02-29'), isFalse);
    expect(conflicted.tasks.single.dueDate, isNull);
  });

  testWidgets('Month cells show task names and retain struck-through completed entries', (tester) async {
    final controller = await _controller(_Store());
    addTearDown(controller.dispose);
    await controller.saveTask(const TaskDraft(title: '直接显示日程', dueDate: '2024-02-01'));
    final id = controller.tasks.single.id;
    await _screen(tester, controller);
    expect(find.byKey(ValueKey('calendar-title-$id')), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('calendar-complete-$id')));
    await tester.pumpAndSettle();
    expect(controller.tasks.single.completed, isTrue);
    expect(tester.widget<Text>(find.byKey(ValueKey('calendar-title-$id'))).style!.decoration, TextDecoration.lineThrough);
    expect(tester.takeException(), isNull);
  });

  for (final phone in [false, true]) {
    testWidgets('${phone ? "Phone long press" : "Windows mouse"} drag schedules an undated task', (tester) async {
      final controller = await _controller(_Store());
      addTearDown(controller.dispose);
      await controller.saveTask(const TaskDraft(title: '拖到目标日期', note: '保留备注', priority: 1));
      final id = controller.tasks.single.id;
      await _screen(tester, controller, phone: phone);
      await _drop(tester, id, phone: phone);
      expect(controller.tasks.single.dueDate, '2024-02-01');
      expect(controller.tasks.single.note, '保留备注');
      expect(find.byKey(ValueKey('drag-$id')), findsNothing);
      expect(find.byKey(ValueKey('calendar-title-$id')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Cancelled dragging and failed saving leave the task in the unscheduled tray', (tester) async {
    final store = _Store();
    final controller = await _controller(store);
    addTearDown(controller.dispose);
    await controller.saveTask(const TaskDraft(title: '继续保留'));
    final id = controller.tasks.single.id;
    await _screen(tester, controller);
    await _drop(tester, id, cancel: true);
    expect(controller.tasks.single.dueDate, isNull);
    store.fail = true;
    await _drop(tester, id);
    expect(controller.tasks.single.dueDate, isNull);
    expect(find.byKey(ValueKey('drag-$id')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Overflow opens all daily tasks and long titles fit narrow phone screens', (tester) async {
    final controller = await _controller(_Store());
    addTearDown(controller.dispose);
    for (var i = 0; i < 5; i++) {
      await controller.saveTask(TaskDraft(title: '很长的日历待办名称需要正确省略而且仍然可以查看完整内容$i', dueDate: '2024-02-01'));
    }
    await _screen(tester, controller, phone: true);
    final firstId = controller.tasks.first.id;
    final previewCount = controller.tasks.where((task) =>
      find.byKey(ValueKey('calendar-title-${task.id}')).evaluate().isNotEmpty).length;
    expect(previewCount, inInclusiveRange(1, 3));
    await tester.tap(find.byKey(ValueKey('calendar-complete-$firstId')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(ValueKey('calendar-title-$firstId'))).style!.decoration, TextDecoration.lineThrough);
    await tester.tap(find.byKey(const ValueKey('more-2024-02-01')));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('+${5 - previewCount} 项'), findsOneWidget);
    final last = find.descendant(of: find.byType(BottomSheet),
      matching: find.text('很长的日历待办名称需要正确省略而且仍然可以查看完整内容4'));
    await tester.scrollUntilVisible(last, 180,
      scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first);
    expect(last, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Phone dragging scrolls calendar edges while its unscheduled tray stays visible', (tester) async {
    final controller = await _controller(_Store());
    addTearDown(controller.dispose);
    await controller.saveTask(const TaskDraft(title: '拖到其他周'));
    final id = controller.tasks.single.id;
    await _screen(tester, controller, phone: true);
    final viewport = find.descendant(of: find.byType(CalendarScreen), matching: find.byType(Scrollable)).first;
    final position = tester.state<ScrollableState>(viewport).position;
    final rect = tester.getRect(viewport);
    final tray = tester.getRect(find.byKey(const ValueKey('unscheduled-tray')));
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(ValueKey('drag-$id'))));
    await tester.pump(const Duration(milliseconds: 350));
    await gesture.moveTo(Offset(rect.center.dx, rect.bottom - 5));
    await tester.pump(const Duration(milliseconds: 550));
    expect(position.pixels, greaterThan(0));
    expect(tester.getRect(find.byKey(const ValueKey('unscheduled-tray'))), tray);
    await gesture.moveTo(const Offset(-30, -30));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.tasks.single.dueDate, isNull);
    expect(tester.takeException(), isNull);
  });
}
