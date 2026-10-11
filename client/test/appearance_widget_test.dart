import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_todo/app_controller.dart';
import 'package:nas_todo/appearance.dart';
import 'package:nas_todo/main.dart';
import 'package:nas_todo/sync_core.dart';
import 'package:nas_todo/task_dates.dart';
import 'package:nas_todo/theme.dart';
import 'package:nas_todo/ui/agenda_task.dart';
import 'package:nas_todo/ui/calendar_screen.dart';

class _TaskStore implements DataStore {
  Map<String, dynamic>? state;
  @override
  Future<Map<String, dynamic>?> read() async => state;
  @override
  Future<void> write(Map<String, dynamic> value) async => state = value;
}

class _UnusedTransport implements SyncTransport {
  @override
  Future<Map<String, dynamic>> sync(Map<String, dynamic> payload) async =>
      throw StateError('Theme widgets use local tasks only.');
}

Future<AppController> _controller() async {
  final engine = SyncEngine(_TaskStore(), _UnusedTransport());
  await engine.load();
  return AppController.forTesting(engine);
}

void _size(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _choose(WidgetTester tester, String key) async {
  final choice = find.byKey(ValueKey(key));
  await tester.ensureVisible(choice);
  await tester.tap(choice);
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('Phone $width can change app and widget colors independently', (tester) async {
      _size(tester, Size(width, 844));
      final controller = await _controller();
      addTearDown(controller.dispose);
      await tester.pumpWidget(PrivateTodoApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(find.text('外观与主题'), findsOneWidget);
      expect(find.text('应用主题'), findsOneWidget);
      expect(find.text('小组件主题'), findsOneWidget);
      await _choose(tester, 'app-theme-black');
      expect(controller.appTheme, TodoThemeColor.black);
      expect(controller.effectiveWidgetTheme, TodoThemeColor.black);
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.brightness, Brightness.dark);
      await _choose(tester, 'widget-theme-blue');
      expect(controller.appTheme, TodoThemeColor.black);
      expect(controller.widgetTheme, TodoThemeColor.blue);
      await _choose(tester, 'app-theme-white');
      expect(controller.effectiveWidgetTheme, TodoThemeColor.blue);
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.brightness, Brightness.light);
      await _choose(tester, 'widget-theme-follow');
      expect(controller.widgetTheme, isNull);
      expect(controller.effectiveWidgetTheme, TodoThemeColor.white);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Black palette reaches the editor, date picker, calendar, and agenda', (tester) async {
    _size(tester, const Size(390, 844));
    final controller = await _controller();
    addTearDown(controller.dispose);
    await controller.saveTask(TaskDraft(title: '黑色主题待办', dueDate: dateKey(DateTime.now())));
    await controller.setAppearance(TodoThemeColor.black, null);
    await tester.pumpWidget(PrivateTodoApp(controller: controller));
    await tester.pumpAndSettle();
    final dark = buildTodoTheme(TodoThemeColor.black);
    await tester.tap(find.text('新建待办'));
    await tester.pumpAndSettle();
    final editor = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(editor.backgroundColor, dark.colorScheme.surface);
    expect(Theme.of(tester.element(find.byKey(const ValueKey('task-title')))).brightness, Brightness.dark);
    await tester.tap(find.text('不设日期'));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(DatePickerDialog))).brightness, Brightness.dark);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日历'));
    await tester.pumpAndSettle();
    final tomorrow = dateKey(DateTime.now().add(const Duration(days: 1)));
    final day = find.byKey(ValueKey('day-$tomorrow'));
    final cell = tester.widget<Material>(find.ancestor(of: day, matching: find.byType(Material)).first);
    expect(cell.color, dark.colorScheme.surface);
    final agenda = find.byType(AgendaTask);
    await tester.ensureVisible(agenda);
    final card = tester.widget<Card>(find.descendant(of: agenda, matching: find.byType(Card)).first);
    expect(card.color, dark.colorScheme.surface);
    expect(Theme.of(tester.element(find.byType(CalendarScreen))).brightness, Brightness.dark);
    expect(tester.takeException(), isNull);
  });
}
