import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_todo/android_widget.dart';
import 'package:nas_todo/app_controller.dart';
import 'package:nas_todo/main.dart';
import 'package:nas_todo/sync_core.dart';
import 'package:nas_todo/task_dates.dart';
import 'package:nas_todo/ui/calendar_screen.dart';
import 'package:nas_todo/ui/agenda_task.dart';

class _Store implements DataStore {
  Map<String, dynamic>? state;
  bool fail = false;
  @override
  Future<Map<String, dynamic>?> read() async => state;
  @override
  Future<void> write(Map<String, dynamic> value) async {
    if (fail) throw StateError('Disk unavailable');
    state = Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  }
}

class _Transport implements SyncTransport {
  @override
  Future<Map<String, dynamic>> sync(Map<String, dynamic> payload) async => throw StateError('Offline');
}

Future<AppController> _controller([_Store? store]) async {
  final engine = SyncEngine(store ?? _Store(), _Transport());
  await engine.load();
  return AppController.forTesting(engine);
}

void _size(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  test('Date grouping keeps completed tasks, filters deleted and isolates undated tasks', () {
    final tasks = [
      const Task(id: 'a', title: '已完成', dueDate: '2024-02-29', completed: true),
      const Task(id: 'b', title: '进行中', dueDate: '2024-02-29', priority: 2),
      const Task(id: 'c', title: '已删除', dueDate: '2024-02-29', deleted: true),
      const Task(id: 'd', title: '没有日期'),
      const Task(id: 'e', title: '明天', dueDate: '2024-03-01'),
    ];
    expect(tasksOnDate(tasks, '2024-02-29').map((task) => task.id), ['b', 'a']);
    expect(tasksOnDate(tasks, null).map((task) => task.id), ['d']);
    expect(dateKey(DateTime(2024, 2, 29)), '2024-02-29');
  });

  test('Widget action retries are idempotent and completion survives restart', () async {
    final store = _Store();
    final controller = await _controller(store);
    addTearDown(controller.dispose);
    await controller.saveTask(const TaskDraft(title: '离线勾选'));
    final actions = [{'action_id': 'click1', 'task_id': controller.tasks.single.id, 'completed': true}];
    expect(await applyWidgetActions(controller, actions), ['click1']);
    final pending = controller.pendingCount;
    expect(await applyWidgetActions(controller, actions), ['click1']);
    expect(controller.pendingCount, pending);
    final reopened = await _controller(store);
    addTearDown(reopened.dispose);
    expect(reopened.tasks.single.completed, isTrue);
    expect(reopened.pendingCount, pending);
  });

  test('Failed widget write remains unacknowledged for retry', () async {
    final store = _Store();
    final controller = await _controller(store);
    addTearDown(controller.dispose);
    await controller.saveTask(const TaskDraft(title: '保存失败'));
    final actions = [{'action_id': 'click1', 'task_id': controller.tasks.single.id, 'completed': true}];
    store.fail = true;
    expect(await applyWidgetActions(controller, actions), isEmpty);
    store.fail = false;
    expect(await applyWidgetActions(controller, actions), ['click1']);
    expect(controller.tasks.single.completed, isTrue);
  });

  test('Widget snapshot excludes notes and deleted tasks', () {
    final snapshot = widgetSnapshot([
      const Task(id: 'a', title: '桌面标题', note: '私人备注'),
      const Task(id: 'b', title: '已删除', deleted: true),
    ], []);
    expect(snapshot, contains('桌面标题'));
    expect(snapshot, isNot(contains('私人备注')));
    expect(snapshot, isNot(contains('已删除')));
    expect(snapshot, isNot(contains('server_url')));
    expect(snapshot, isNot(contains('token')));
  });

  test('Widget theme changes update the snapshot while preserving its private-field exclusions', () {
    const tasks = [
      Task(id: 'theme-task', title: '主题预览', note: '不应发布的私人备注'),
      Task(id: 'deleted-task', title: '已删除内容', deleted: true),
    ];
    final original = jsonDecode(widgetSnapshot(tasks, [])) as Map;
    expect(original['theme'], 'green');
    final snapshots = <String>{};
    for (final theme in ['black', 'white', 'green', 'blue']) {
      final snapshot = widgetSnapshot(tasks, [], theme: theme);
      snapshots.add(snapshot);
      final state = jsonDecode(snapshot) as Map;
      expect(state['theme'], theme);
      expect(state['tasks'], original['tasks']);
      expect(state.keys, unorderedEquals(['theme', 'tasks']));
      expect(snapshot, isNot(contains('不应发布的私人备注')));
      expect(snapshot, isNot(contains('已删除内容')));
      expect(snapshot, isNot(contains('server_url')));
      expect(snapshot, isNot(contains('token')));
    }
    expect(snapshots.length, 4);
    final invalid = jsonDecode(widgetSnapshot(tasks, [], theme: 'unknown')) as Map;
    expect(invalid, original);
  });

  testWidgets('Calendar retains struck-through completed tasks and clamps leap month navigation', (tester) async {
    _size(tester, const Size(900, 650));
    final controller = await _controller();
    addTearDown(controller.dispose);
    await controller.saveTask(const TaskDraft(title: '闰日安排', dueDate: '2024-02-29'));
    final id = controller.tasks.single.id;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CalendarScreen(
      controller: controller, initialDate: DateTime(2024, 1, 31)))));
    await tester.tap(find.byTooltip('下个月'));
    await tester.pumpAndSettle();
    expect(find.text('2024年2月'), findsOneWidget);
    expect(find.text('2月29日的待办'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('complete-$id')));
    await tester.pumpAndSettle();
    expect(controller.tasks.single.completed, isTrue);
    final text = tester.widget<Text>(find.byKey(ValueKey('calendar-title-$id')));
    expect(text.style?.decoration, TextDecoration.lineThrough);
    expect(find.text('0/1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Small calendar viewport is scrollable and shows undated tasks separately', (tester) async {
    _size(tester, const Size(320, 568));
    final controller = await _controller();
    addTearDown(controller.dispose);
    await controller.saveTask(const TaskDraft(title: '未安排任务'));
    await tester.pumpWidget(PrivateTodoApp(controller: controller));
    await tester.tap(find.text('日历').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(FilterChip));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilterChip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日历').last);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(find.byType(FilterChip)).selected, isTrue);
    final agenda = find.descendant(of: find.byType(AgendaTask), matching: find.text('未安排任务'));
    await tester.scrollUntilVisible(agenda, 180,
      scrollable: find.descendant(of: find.byType(CalendarScreen),
        matching: find.byType(Scrollable)).first);
    expect(agenda, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Calendar new task uses the selected date', (tester) async {
    _size(tester, const Size(1280, 800));
    final controller = await _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(PrivateTodoApp(controller: controller));
    await tester.tap(find.byTooltip('日历'));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    final target = DateTime(now.year, now.month, 15);
    final day = find.byKey(ValueKey('day-${dateKey(target)}'));
    await tester.ensureVisible(day);
    await tester.pumpAndSettle();
    await tester.tap(day);
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建待办'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('task-title')), '选中日期的新任务');
    await tester.tap(find.text('保存到本机'));
    await tester.pumpAndSettle();
    expect(controller.tasks.single.dueDate, dateKey(target));
    expect(tester.takeException(), isNull);
  });

}
