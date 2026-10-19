import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_todo/app_controller.dart';
import 'package:nas_todo/sync_core.dart';
import 'package:nas_todo/ui/task_board_view.dart';
import 'package:nas_todo/ui/task_matrix_view.dart';

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
      throw StateError('offline');
}

Future<AppController> _controller({_Store? store}) async {
  final engine = SyncEngine(store ?? _Store(), _Offline());
  await engine.load();
  return AppController.forTesting(engine, clock: () => DateTime(2026, 10, 19));
}

Future<void> _screen(
  WidgetTester tester,
  AppController controller, {
  bool matrix = false,
  bool phone = false,
  Size? size,
  ValueChanged<Task>? onEdit,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size ?? (phone
      ? const Size(390, 844)
      : const Size(1200, 860));
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        platform: phone ? TargetPlatform.android : TargetPlatform.windows,
      ),
      home: Scaffold(
        body: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => matrix
              ? TaskMatrixView(
                  controller: controller,
                  tasks: controller.tasks,
                  onEdit: onEdit ?? (_) {},
                  now: DateTime(2026, 10, 19),
                )
              : TaskBoardView(
                  controller: controller,
                  tasks: controller.tasks,
                  onEdit: onEdit ?? (_) {},
                ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Board menu changes real priority while preserving note, list and date',
    (tester) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      await controller.saveTask(
        const TaskDraft(
          title: '菜单调整',
          note: '私人备注',
          listName: '计划',
          dueDate: '2026-10-22',
        ),
      );
      final id = controller.tasks.single.id;
      await _screen(tester, controller);
      await tester.tap(find.byKey(ValueKey('workbench-menu-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移到紧急'));
      await tester.pumpAndSettle();
      final task = controller.tasks.single;
      expect(
        [task.priority, task.note, task.listName, task.dueDate, task.completed],
        [2, '私人备注', '计划', '2026-10-22', false],
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('board-drop-2')),
          matching: find.text('菜单调整'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Desktop board drag saves its destination priority', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    await controller.saveTask(const TaskDraft(title: '拖动调整'));
    final id = controller.tasks.single.id;
    await _screen(tester, controller);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(ValueKey('workbench-drag-$id'))),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('board-drop-2'))),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.tasks.single.priority, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Matrix menu changes urgency with a durable date and keeps the task identity',
    (tester) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      await controller.saveTask(
        const TaskDraft(title: '进入重要紧急', dueDate: '2026-10-18', priority: 2),
      );
      final id = controller.tasks.single.id;
      await _screen(tester, controller, matrix: true);
      await tester.tap(find.byKey(ValueKey('workbench-menu-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移到重要不紧急'));
      await tester.pumpAndSettle();
      expect(controller.tasks.single.id, id);
      expect(controller.tasks.single.priority, 2);
      expect(controller.tasks.single.dueDate, isNull);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('matrix-drop-importantNotUrgent')),
          matching: find.text('进入重要紧急'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Windows horizontal wheel and scrollbar thumb share the real board position',
    (tester) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      await controller.saveTask(const TaskDraft(title: '滚动到右侧', priority: 2));
      await _screen(tester, controller, size: const Size(700, 860));
      final scroll = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('priority-board-scroll')));
      final bar = tester.widget<Scrollbar>(
        find.byKey(const ValueKey('priority-board-scrollbar')));
      expect(identical(scroll.controller, bar.controller), isTrue);
      final position = scroll.controller!.position;
      expect(position.maxScrollExtent, greaterThan(0));
      final viewport = tester.getRect(find.byKey(const ValueKey('priority-board-scroll')));
      await tester.sendEventToBinding(PointerScrollEvent(
        position: viewport.center, scrollDelta: const Offset(20, 0),
        kind: PointerDeviceKind.mouse));
      await tester.pump(const Duration(milliseconds: 150));
      expect(position.pixels, greaterThan(0));
      expect(tester.takeException(), isNull);
      final before = position.pixels;
      final gesture = await tester.startGesture(
        Offset(viewport.left + viewport.width * .3, viewport.bottom - 3),
        kind: PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump(const Duration(milliseconds: 40));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(before));
      expect(controller.tasks.single.priority, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Phone board scrolls horizontally without modifying task priority',
    (tester) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      await controller.saveTask(const TaskDraft(title: '手机浏览', priority: 2));
      await _screen(tester, controller, phone: true);
      await tester.drag(
        find.byKey(const ValueKey('priority-board-scroll')),
        const Offset(-600, 0),
      );
      await tester.pumpAndSettle();
      expect(controller.tasks.single.priority, 2);
      expect(find.text('手机浏览').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Phone matrix allows scrolling to every quadrant', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    await _screen(tester, controller, matrix: true, phone: true);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('matrix-drop-notImportantNotUrgent')),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('matrix-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('不紧急不重要').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Completed cards cannot be dragged but their checkbox still permits undo',
    (tester) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      await controller.saveTask(
        const TaskDraft(title: '已完成卡片', completed: true),
      );
      final id = controller.tasks.single.id;
      await _screen(tester, controller);
      expect(find.byKey(ValueKey('workbench-drag-$id')), findsNothing);
      expect(
        tester
            .widget<PopupMenuButton<int>>(
              find.byKey(ValueKey('workbench-menu-$id')),
            )
            .enabled,
        isFalse,
      );
      await tester.tap(find.byKey(ValueKey('workbench-complete-$id')));
      await tester.pumpAndSettle();
      expect(controller.tasks.single.completed, isFalse);
      expect(find.byKey(ValueKey('workbench-drag-$id')), findsOneWidget);
    },
  );

  testWidgets('Conflict cards disable completion, drag and movement menus', (
    tester,
  ) async {
    final store = _Store();
    final first = await _controller(store: store);
    addTearDown(first.dispose);
    await first.saveTask(const TaskDraft(title: '保留冲突'));
    final task = first.tasks.single;
    store.state!['conflicts'] = [
      SyncConflict(taskId: task.id, local: task, remote: task).toJson(),
    ];
    final controller = await _controller(store: store);
    addTearDown(controller.dispose);
    await _screen(tester, controller);
    expect(find.byKey(ValueKey('workbench-drag-${task.id}')), findsNothing);
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(ValueKey('workbench-complete-${task.id}')),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<PopupMenuButton<int>>(
            find.byKey(ValueKey('workbench-menu-${task.id}')),
          )
          .enabled,
      isFalse,
    );
    expect(find.text('同步冲突，请先选择版本'), findsOneWidget);
  });
}
