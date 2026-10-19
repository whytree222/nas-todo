import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_todo/app_controller.dart';
import 'package:nas_todo/appearance.dart';
import 'package:nas_todo/main.dart';
import 'package:nas_todo/sync_core.dart';
import 'package:nas_todo/task_dates.dart';
import 'package:nas_todo/theme.dart';
import 'package:nas_todo/ui/home_screen.dart';
import 'package:nas_todo/ui/task_board_view.dart';
import 'package:nas_todo/ui/task_detail_pane.dart';
import 'package:nas_todo/ui/task_matrix_view.dart';

class _Store implements DataStore {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> data) async {
    value = Map<String, dynamic>.from(jsonDecode(jsonEncode(data)) as Map);
  }
}

class _Offline implements SyncTransport {
  @override
  Future<Map<String, dynamic>> sync(Map<String, dynamic> payload) async =>
      throw StateError('Offline UI test');
}

Future<AppController> _controller() async {
  final engine = SyncEngine(_Store(), _Offline());
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

Future<void> _seed(AppController controller) async {
  final now = DateTime.now();
  await controller.saveTask(
    TaskDraft(
      title: '准备周末的旅行计划',
      note: '确认车票，整理相机和充电器。',
      listName: '生活',
      dueDate: dateKey(now),
      priority: 2,
    ),
  );
  await controller.saveTask(
    TaskDraft(
      title: '把产品方案画清楚',
      note: '把复杂的问题拆成可以开始的第一步。',
      listName: '工作',
      dueDate: dateKey(now.add(const Duration(days: 2))),
      priority: 1,
    ),
  );
  await controller.saveTask(
    const TaskDraft(title: '读完书桌上的那本书', listName: '生活'),
  );
  await controller.saveTask(
    const TaskDraft(title: '记录一个突然出现的灵感', listName: '收件箱'),
  );
  await controller.saveTask(
    TaskDraft(
      title: '给自己留一点运动时间',
      listName: '生活',
      dueDate: dateKey(now.add(const Duration(days: 4))),
    ),
  );
}

Future<void> _drawer(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('清单与智能视图'));
  await tester.pumpAndSettle();
  final item = find.text(label).last;
  await tester.ensureVisible(item);
  await tester.tap(item);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Desktop workbench keeps compact list, real details and editing',
    (tester) async {
      _size(tester, const Size(1360, 860));
      final controller = await _controller();
      await _seed(controller);
      await tester.pumpWidget(PrivateTodoApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailPane), findsOneWidget);
      expect(find.text('把下一步看清楚'), findsOneWidget);
      final task = controller.tasks.firstWhere(
        (task) => task.title == '把产品方案画清楚',
      );
      await tester.tap(find.byKey(ValueKey('task-detail-${task.id}')));
      await tester.pumpAndSettle();
      expect(find.text('待办详情'), findsOneWidget);
      await tester.tap(find.text('编辑待办'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('task-title')),
        '修改后的方案',
      );
      await tester.tap(find.text('保存到本机'));
      await tester.pumpAndSettle();
      expect(
        controller.tasks.firstWhere((item) => item.id == task.id).title,
        '修改后的方案',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Phone quick add saves into selected list and Today uses current date',
    (tester) async {
      _size(tester, const Size(390, 844));
      final controller = await _controller();
      await controller.saveTask(
        const TaskDraft(title: 'existing', listName: '研究'),
      );
      await tester.pumpWidget(PrivateTodoApp(controller: controller));
      await tester.pumpAndSettle();
      await _drawer(tester, '研究');
      await tester.enterText(
        find.byKey(const ValueKey('workbench-quick-add')),
        '分组中的下一步',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        controller.tasks.firstWhere((task) => task.title == '分组中的下一步').listName,
        '研究',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('workbench-quick-add')),
            )
            .controller!
            .text,
        isEmpty,
      );
      await tester.tap(find.text('今天').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('workbench-quick-add')),
        '今天的新任务',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        controller.tasks.firstWhere((task) => task.title == '今天的新任务').dueDate,
        dateKey(DateTime.now()),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Smart views filter real tasks, board and matrix share saved tasks',
    (tester) async {
      _size(tester, const Size(390, 844));
      final controller = await _controller();
      await _seed(controller);
      await tester.pumpWidget(PrivateTodoApp(controller: controller));
      await tester.pumpAndSettle();
      await _drawer(tester, '重要待办');
      expect(find.text('准备周末的旅行计划'), findsOneWidget);
      expect(find.text('读完书桌上的那本书'), findsNothing);
      await _drawer(tester, '最近 7 天');
      expect(find.text('给自己留一点运动时间'), findsOneWidget);
      expect(find.text('记录一个突然出现的灵感'), findsNothing);
      await tester.tap(find.text('看板'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskBoardView), findsOneWidget);
      await tester.tap(find.text('四象限'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskMatrixView), findsOneWidget);
      expect(controller.tasks.length, 5);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Connection status opens settings and narrow navigation stays accessible',
    (tester) async {
      _size(tester, const Size(320, 568));
      final controller = await _controller();
      await tester.pumpWidget(PrivateTodoApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text('新建待办'), findsOneWidget);
      expect(find.byType(NavigationDestination), findsNWidgets(5));
      await tester.tap(find.text('待办已保存在本机'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nas-token')), findsOneWidget);
      expect(find.text('保存并同步'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Desktop keyboard shortcuts focus creation and search and clear search',
    (tester) async {
      _size(tester, const Size(1280, 800));
      final controller = await _controller();
      await tester.pumpWidget(PrivateTodoApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('workbench-quick-add')),
            )
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('workbench-search')))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await tester.enterText(
        find.byKey(const ValueKey('workbench-search')),
        'temporary query',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('workbench-search')))
            .controller!
            .text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final desktop in [true, false]) {
    testWidgets(
      'Workbench ${desktop ? 'desktop' : 'phone'} preview uses synthetic data only',
      (tester) async {
        _size(tester, desktop ? const Size(1440, 900) : const Size(390, 844));
        final controller = await _controller();
        await _seed(controller);
        final font = await _loadPreviewFonts(tester);
        var theme = buildTodoTheme(TodoThemeColor.green);
        if (font != null)
          theme = theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: font),
          );
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workbench-preview'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              home: HomeScreen(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (desktop) {
          final task = controller.tasks.firstWhere(
            (task) => task.title == '把产品方案画清楚',
          );
          await tester.tap(find.byKey(ValueKey('task-detail-${task.id}')));
          await tester.pumpAndSettle();
        }
        await _preview(
          tester,
          'workbench-${desktop ? 'desktop' : 'phone'}.png',
          font != null,
        );
        if (desktop) {
          await tester.tap(find.text('看板'));
          await tester.pumpAndSettle();
          await _preview(tester, 'workbench-board.png', font != null);
          await tester.tap(find.text('四象限'));
          await tester.pumpAndSettle();
          await _preview(tester, 'workbench-matrix.png', font != null);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<String?> _loadPreviewFonts(WidgetTester tester) async {
  const cjk = '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc';
  if (!File(cjk).existsSync()) return null;
  await tester.runAsync(() async {
    final font = FontLoader('WorkbenchPreviewSans')
      ..addFont(
        Future.value(ByteData.sublistView(await File(cjk).readAsBytes())),
      );
    await font.load();
    final flutter = Platform.environment['FLUTTER_ROOT'];
    if (flutter != null) {
      final icons = File(
        '$flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      if (icons.existsSync()) {
        final loader = FontLoader('MaterialIcons')
          ..addFont(
            Future.value(ByteData.sublistView(await icons.readAsBytes())),
          );
        await loader.load();
      }
    }
  });
  return 'WorkbenchPreviewSans';
}

Future<void> _preview(
  WidgetTester tester,
  String name,
  bool fontsLoaded,
) async {
  final directory = Platform.environment['NAS_TODO_TEST_TMP'];
  if (directory == null || !fontsLoaded) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('workbench-preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File('$directory/$name')
          .writeAsBytes(data!.buffer.asUint8List(), flush: true);
    } finally {
      image.dispose();
    }
  });
}
