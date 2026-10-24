import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_todo/app_controller.dart';
import 'package:nas_todo/main.dart';
import 'package:nas_todo/sync_core.dart';

class _MemoryStore implements DataStore {
  Map<String, dynamic>? state;

  @override
  Future<Map<String, dynamic>?> read() async => state;

  @override
  Future<void> write(Map<String, dynamic> value) async {
    state = Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  }
}

class _UnusedTransport implements SyncTransport {
  @override
  Future<Map<String, dynamic>> sync(Map<String, dynamic> payload) async {
    throw StateError('This widget test uses local storage only.');
  }
}

Future<AppController> _controller() async {
  final engine = SyncEngine(_MemoryStore(), _UnusedTransport());
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
  testWidgets(
    'Android: create offline, complete, search, and obscure NAS token',
    (tester) async {
      _size(tester, const Size(390, 844));
      final controller = await _controller();
      addTearDown(controller.dispose);
      await tester.pumpWidget(PrivateTodoApp(controller: controller));
      await tester.pumpAndSettle();

      expect(find.text('从一件小事开始'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.tap(find.byTooltip('完整新建'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('task-title')),
        '整理 NAS 备份',
      );
      await tester.tap(find.text('保存到本机'));
      await tester.pumpAndSettle();
      expect(controller.tasks.single.title, '整理 NAS 备份');
      expect(controller.pendingCount, 1);
      expect(find.text('整理 NAS 备份'), findsOneWidget);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(controller.tasks.single.completed, isTrue);
      expect(find.text('整理 NAS 备份'), findsNothing);
      await tester.tap(find.byTooltip('清单与智能视图'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(Drawer), matching: find.text('已完成')),
      );
      await tester.pumpAndSettle();
      expect(find.text('整理 NAS 备份'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '不存在的待办');
      await tester.pumpAndSettle();
      expect(find.text('没有找到匹配的待办'), findsOneWidget);
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      final token = tester.widget<TextField>(
        find.byKey(const ValueKey('nas-token')),
      );
      expect(token.obscureText, isTrue);
      expect(find.text('保存并同步'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Windows: desktop sidebar, lists, search, and settings remain usable',
    (tester) async {
      _size(tester, const Size(1280, 800));
      final controller = await _controller();
      addTearDown(controller.dispose);
      await controller.saveTask(
        const TaskDraft(title: '检查磁盘空间', listName: 'NAS 维护', priority: 1),
      );
      await controller.saveTask(const TaskDraft(title: '读一本书', listName: '生活'));
      await tester.pumpWidget(PrivateTodoApp(controller: controller));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('私有待办'), findsOneWidget);
      expect(find.text('检查磁盘空间'), findsOneWidget);
      await tester.tap(find.text('NAS 维护').first);
      await tester.pumpAndSettle();
      expect(find.text('检查磁盘空间'), findsOneWidget);
      expect(find.text('读一本书'), findsNothing);

      await tester.enterText(find.byType(TextField).first, '磁盘');
      await tester.pumpAndSettle();
      expect(find.text('检查磁盘空间'), findsOneWidget);
      await tester.tap(find.text('连接设置'));
      await tester.pumpAndSettle();
      final token = tester.widget<TextField>(
        find.byKey(const ValueKey('nas-token')),
      );
      expect(token.obscureText, isTrue);
      expect(find.text('NAS 连接与同步'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Small Android viewport keeps an empty list accessible', (
    tester,
  ) async {
    _size(tester, const Size(320, 568));
    final controller = await _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(PrivateTodoApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('新建待办'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'An update received during editing requires an explicit overwrite choice',
    (tester) async {
      _size(tester, const Size(390, 844));
      final controller = await _controller();
      addTearDown(controller.dispose);
      await controller.saveTask(const TaskDraft(title: '原始标题'));
      final id = controller.tasks.single.id;
      await tester.pumpWidget(PrivateTodoApp(controller: controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('原始标题'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('task-title')), '我的修改');
      await controller.saveTask(const TaskDraft(title: '编辑期间收到的新内容'), id: id);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存到本机'));
      await tester.pumpAndSettle();
      expect(controller.tasks.single.title, '编辑期间收到的新内容');
      expect(find.text('确认覆盖更新'), findsOneWidget);
      expect(find.text('收到的新版本'), findsOneWidget);
      await tester.tap(find.text('确认覆盖更新'));
      await tester.pumpAndSettle();
      expect(controller.tasks.single.title, '我的修改');
      expect(tester.takeException(), isNull);
    },
  );
}
