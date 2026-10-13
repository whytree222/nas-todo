import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_todo/app_controller.dart';
import 'package:nas_todo/appearance.dart';
import 'package:nas_todo/daily_celebration.dart';
import 'package:nas_todo/main.dart';
import 'package:nas_todo/sync_core.dart';
import 'package:nas_todo/task_dates.dart';
import 'package:nas_todo/theme.dart';
import 'package:nas_todo/ui/daily_celebration_dialog.dart';

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
  Future<Map<String, dynamic>> sync(Map<String, dynamic> payload) async =>
    throw StateError('No network required');
}

Future<AppController> _controller() async {
  final engine = SyncEngine(_Store(), _Offline());
  await engine.load();
  final controller = AppController.forTesting(engine);
  await controller.loadCelebrationForTesting();
  addTearDown(controller.dispose);
  return controller;
}

void _size(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _todayTask(AppController controller) async {
  await controller.saveTask(TaskDraft(title: '今天的一小步', dueDate: dateKey(DateTime.now())));
}

Future<String?> _previewFont(WidgetTester tester) async {
  const linuxFont = '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc';
  final candidate = File(linuxFont);
  if (!candidate.existsSync()) return null;
  await tester.runAsync(() async {
    final bytes = await candidate.readAsBytes();
    final loader = FontLoader('CelebrationPreviewSans')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  });
  return 'CelebrationPreviewSans';
}

Future<void> _preview(WidgetTester tester, String fileName) async {
  final directory = Platform.environment['NAS_TODO_TEST_TMP'];
  // Preview artifacts are opt-in CI diagnostics containing only synthetic data.
  if (directory == null || !File('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc').existsSync()) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('daily-celebration-artifact')));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File('$directory/$fileName').writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
    } finally {
      image.dispose();
    }
  });
}

void main() {
  testWidgets('Final checkbox celebrates globally and dismisses without same-day replay', (tester) async {
    _size(tester, const Size(390, 844));
    final controller = await _controller();
    await _todayTask(controller);
    await tester.pumpWidget(PrivateTodoApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.byType(DailyCelebrationDialog), findsOneWidget);
    expect(find.text('今天的 1 件待办，全部完成！'), findsOneWidget);
    expect(controller.tasks.single.completed, isTrue);
    await tester.tap(find.byKey(const ValueKey('daily-celebration-close')));
    await tester.pumpAndSettle();
    expect(find.byType(DailyCelebrationDialog), findsNothing);
    await controller.setCompleted(controller.tasks.single.id, false);
    await controller.setCompleted(controller.tasks.single.id, true);
    await tester.pumpAndSettle();
    expect(find.byType(DailyCelebrationDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Explicit widget completion before runApp is delivered after main screen mounts', (tester) async {
    _size(tester, const Size(1280, 800));
    final controller = await _controller();
    await _todayTask(controller);
    await controller.setCompleted(controller.tasks.single.id, true);
    expect(controller.pendingDailyCelebration, isNotNull);
    await tester.pumpWidget(PrivateTodoApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.byType(DailyCelebrationDialog), findsOneWidget);
    expect(controller.pendingDailyCelebration, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Another route defers the card until it closes', (tester) async {
    _size(tester, const Size(390, 844));
    final controller = await _controller();
    await _todayTask(controller);
    await tester.pumpWidget(PrivateTodoApp(controller: controller));
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push<void>(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Temporary page'))));
    await tester.pumpAndSettle();
    await controller.setCompleted(controller.tasks.single.id, true);
    await tester.pumpAndSettle();
    expect(find.byType(DailyCelebrationDialog), findsNothing);
    expect(controller.pendingDailyCelebration, isNotNull);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.byType(DailyCelebrationDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Background completion waits for resumed main app', (tester) async {
    _size(tester, const Size(390, 844));
    final controller = await _controller();
    await _todayTask(controller);
    await tester.pumpWidget(PrivateTodoApp(controller: controller));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await controller.setCompleted(controller.tasks.single.id, true);
    await tester.pumpAndSettle();
    expect(find.byType(DailyCelebrationDialog), findsNothing);
    expect(controller.pendingDailyCelebration, isNotNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(DailyCelebrationDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Small phone renders a cheerful finite animation and exports readable preview', (tester) async {
    _size(tester, const Size(360, 640));
    final font = await _previewFont(tester);
    var theme = buildTodoTheme(TodoThemeColor.green);
    if (font != null) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: font),
        primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: font));
    }
    await tester.pumpWidget(MaterialApp(theme: theme, home: Builder(builder: (context) =>
      Scaffold(body: Center(child: FilledButton(onPressed: () => showDailyCelebration(context,
        const DailyCelebration(day: '2026-10-13', taskCount: 8)), child: const Text('Open preview')))))));
    await tester.tap(find.text('Open preview'));
    await tester.pumpAndSettle();
    expect(find.text('今天的 8 件待办，全部完成！'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
    await _preview(tester, 'celebration-mobile.png');
    await tester.tap(find.byKey(const ValueKey('daily-celebration-close')));
    await tester.pumpAndSettle();
    expect(find.byType(DailyCelebrationDialog), findsNothing);
  });

  testWidgets('Dark desktop, large text and reduced motion remain scrollable and dismissible', (tester) async {
    _size(tester, const Size(1280, 800));
    final font = await _previewFont(tester);
    var theme = buildTodoTheme(TodoThemeColor.black);
    if (font != null) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: font),
        primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: font));
    }
    await tester.pumpWidget(MaterialApp(theme: theme,
      builder: (_, child) => MediaQuery(
        data: MediaQueryData(size: const Size(1280, 800), textScaler: TextScaler.linear(1.6), disableAnimations: true),
        child: child!),
      home: Builder(builder: (context) => Scaffold(body: Center(child: FilledButton(
        onPressed: () => showDailyCelebration(context, const DailyCelebration(day: '2026-10-12', taskCount: 12)),
        child: const Text('Open preview')))))));
    await tester.tap(find.text('Open preview'));
    await tester.pumpAndSettle();
    expect(find.text('今天的 12 件待办，全部完成！'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
    await _preview(tester, 'celebration-desktop.png');
    await tester.ensureVisible(find.byKey(const ValueKey('daily-celebration-close')));
    await tester.tap(find.byKey(const ValueKey('daily-celebration-close')));
    await tester.pumpAndSettle();
    expect(find.byType(DailyCelebrationDialog), findsNothing);
  });
}
