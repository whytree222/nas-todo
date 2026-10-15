import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_todo/app_controller.dart';
import 'package:nas_todo/sync_core.dart';
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

class _UnusedTransport implements SyncTransport {
  @override
  Future<Map<String, dynamic>> sync(Map<String, dynamic> payload) async =>
      throw StateError('This editor test uses local storage only.');
}

Future<AppController> _controller() async {
  final engine = SyncEngine(_Store(), _UnusedTransport());
  await engine.load();
  return AppController.forTesting(engine);
}

void _size(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _openEditor(
  WidgetTester tester,
  AppController controller, {
  Task? task,
  String? listName,
  String? dueDate,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showTaskEditor(
              context,
              controller,
              task: task,
              listName: listName,
              initialDueDate: dueDate,
            ),
            child: const Text('打开编辑器'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开编辑器'));
  await tester.pumpAndSettle();
}

Future<void> _openLists(WidgetTester tester) async {
  final picker = find.byKey(const ValueKey('task-list-picker'));
  await tester.ensureVisible(picker);
  await tester.pumpAndSettle();
  await tester.tap(picker);
  await tester.pumpAndSettle();
}

TextEditingController _field(WidgetTester tester, String name) =>
    tester.widget<TextFormField>(find.byKey(ValueKey(name))).controller!;

void main() {
  testWidgets(
    'New task can select all existing groups without clearing inbox',
    (tester) async {
      _size(tester, const Size(390, 844));
      final controller = await _controller();
      addTearDown(controller.dispose);
      await controller.saveTask(
        const TaskDraft(title: '工作任务一', listName: '工作'),
      );
      await controller.saveTask(
        const TaskDraft(title: '工作任务二', listName: '工作'),
      );
      await controller.saveTask(
        const TaskDraft(title: '已完成学习', listName: '学习', completed: true),
      );
      await controller.saveTask(
        const TaskDraft(title: '删除的任务', listName: '已删除的清单'),
      );
      await controller.deleteTask(controller.tasks.last.id);

      await _openEditor(tester, controller, dueDate: '2028-02-29');
      await tester.enterText(find.byKey(const ValueKey('task-title')), '新待办');
      await tester.enterText(find.byKey(const ValueKey('task-note')), '保留这份备注');
      await tester.ensureVisible(find.text('紧急'));
      await tester.tap(find.text('紧急'));
      await tester.pumpAndSettle();
      expect(_field(tester, 'task-list').text, '收件箱');

      await _openLists(tester);
      expect(
        find.byKey(const ValueKey('task-list-option-收件箱')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('task-list-option-工作')), findsOneWidget);
      expect(find.byKey(const ValueKey('task-list-option-学习')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('task-list-option-已删除的清单')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('task-list-option-学习')));
      await tester.pumpAndSettle();

      final group = _field(tester, 'task-list');
      expect(group.text, '学习');
      expect(
        group.selection,
        const TextSelection(baseOffset: 0, extentOffset: 2),
      );
      expect(_field(tester, 'task-title').text, '新待办');
      expect(_field(tester, 'task-note').text, '保留这份备注');
      await tester.tap(find.text('保存到本机'));
      await tester.pumpAndSettle();
      final saved = controller.tasks.singleWhere((task) => task.title == '新待办');
      expect(saved.listName, '学习');
      expect(saved.note, '保留这份备注');
      expect(saved.dueDate, '2028-02-29');
      expect(saved.priority, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Editing changes only the chosen group and retains other draft fields',
    (tester) async {
      _size(tester, const Size(1280, 800));
      final controller = await _controller();
      addTearDown(controller.dispose);
      await controller.saveTask(
        const TaskDraft(
          title: '原始任务',
          note: '原备注',
          listName: '原清单',
          dueDate: '2028-05-06',
          priority: 1,
          completed: true,
        ),
      );
      final original = controller.tasks.single;
      await controller.saveTask(
        const TaskDraft(title: '目标清单任务', listName: '生活'),
      );
      await _openEditor(tester, controller, task: original);
      await tester.enterText(
        find.byKey(const ValueKey('task-title')),
        '编辑中的标题',
      );
      await tester.enterText(find.byKey(const ValueKey('task-note')), '编辑中的备注');

      await _openLists(tester);
      await tester.tap(find.byKey(const ValueKey('task-list-option-生活')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存到本机'));
      await tester.pumpAndSettle();
      final saved = controller.tasks.singleWhere(
        (task) => task.id == original.id,
      );
      expect(saved.title, '编辑中的标题');
      expect(saved.note, '编辑中的备注');
      expect(saved.listName, '生活');
      expect(saved.dueDate, original.dueDate);
      expect(saved.priority, original.priority);
      expect(saved.completed, isTrue);
      expect(controller.tasks.length, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Groups arriving while editing appear without replacing typed drafts',
    (tester) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      await _openEditor(tester, controller, listName: '打开时的清单');
      await tester.enterText(
        find.byKey(const ValueKey('task-title')),
        '输入中的标题',
      );
      await tester.enterText(find.byKey(const ValueKey('task-list')), '手输的新清单');
      await controller.saveTask(
        const TaskDraft(title: '新到的任务', listName: '新到的清单'),
      );
      await tester.pumpAndSettle();
      expect(_field(tester, 'task-list').text, '手输的新清单');
      expect(_field(tester, 'task-title').text, '输入中的标题');

      await _openLists(tester);
      expect(
        find.byKey(const ValueKey('task-list-option-打开时的清单')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('task-list-option-新到的清单')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('task-list-option-新到的清单')));
      await tester.pumpAndSettle();
      expect(_field(tester, 'task-list').text, '新到的清单');
      expect(_field(tester, 'task-title').text, '输入中的标题');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Manual new group and required-name validation remain available',
    (tester) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      await _openEditor(tester, controller);
      await tester.enterText(
        find.byKey(const ValueKey('task-title')),
        '手动新建分组',
      );
      await tester.enterText(find.byKey(const ValueKey('task-list')), '   ');
      await tester.tap(find.text('保存到本机'));
      await tester.pumpAndSettle();
      expect(find.text('填写清单名称'), findsOneWidget);
      expect(controller.tasks, isEmpty);

      await tester.enterText(
        find.byKey(const ValueKey('task-list')),
        '  我的新分组  ',
      );
      await tester.tap(find.text('保存到本机'));
      await tester.pumpAndSettle();
      expect(controller.tasks.single.listName, '我的新分组');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Many groups scroll and long names fit a narrow phone popup', (
    tester,
  ) async {
    _size(tester, const Size(320, 640));
    final controller = await _controller();
    addTearDown(controller.dispose);
    for (var index = 0; index < 30; index++) {
      await controller.saveTask(
        TaskDraft(
          title: '任务$index',
          listName: '分组${index.toString().padLeft(2, '0')}',
        ),
      );
    }
    final longName = '长' * 60;
    await controller.saveTask(TaskDraft(title: '长名称任务', listName: longName));
    await _openEditor(tester, controller);
    await _openLists(tester);
    final option = find.byKey(ValueKey('task-list-option-$longName'));
    await tester.scrollUntilVisible(
      option,
      200,
      scrollable: find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .last,
    );
    await tester.pumpAndSettle();
    await tester.tap(option);
    await tester.pumpAndSettle();
    expect(_field(tester, 'task-list').text, longName);
    expect(tester.takeException(), isNull);
  });
}
