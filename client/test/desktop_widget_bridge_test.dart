import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_todo/appearance.dart';
import 'package:nas_todo/app_controller.dart';
import 'package:nas_todo/desktop_widget_bridge.dart';
import 'package:nas_todo/sync_core.dart';

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

class _Offline implements SyncTransport {
  @override
  Future<Map<String, dynamic>> sync(Map<String, dynamic> payload) async => throw StateError('Offline');
}

Future<AppController> _controller(_Store store) async {
  final engine = SyncEngine(store, _Offline());
  await engine.load();
  return AppController.forTesting(engine);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Native completion persists offline, survives restart and duplicate clicks', () async {
    final store = _Store();
    final controller = await _controller(store);
    addTearDown(controller.dispose);
    await controller.saveTask(const TaskDraft(title: '组件离线任务'));
    final bridge = DesktopWidgetBridge(controller);
    final call = MethodCall('widgetComplete', {'id': controller.tasks.single.id, 'completed': true});
    expect(await bridge.handleCall(call), isTrue);
    final pending = controller.pendingCount;
    expect(await bridge.handleCall(call), isTrue);
    expect(controller.pendingCount, pending);
    final reopened = await _controller(store);
    addTearDown(reopened.dispose);
    expect(reopened.tasks.single.completed, isTrue);
    expect(reopened.pendingCount, pending);
  });
  test('Storage failure keeps old completion and permits retry', () async {
    final store = _Store();
    final controller = await _controller(store);
    addTearDown(controller.dispose);
    await controller.saveTask(const TaskDraft(title: '待重试'));
    final bridge = DesktopWidgetBridge(controller);
    final call = MethodCall('widgetComplete', {'id': controller.tasks.single.id, 'completed': true});
    store.fail = true;
    expect(await bridge.handleCall(call), isFalse);
    expect(controller.tasks.single.completed, isFalse);
    store.fail = false;
    expect(await bridge.handleCall(call), isTrue);
  });
  test('Component receives task updates without notes or connection credentials', () async {
    final controller = await _controller(_Store());
    addTearDown(controller.dispose);
    await controller.saveTask(const TaskDraft(title: '组件标题', note: '私人备注'));
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('cn.privatetodo/desktop');
    final snapshots = <Map>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'publishWidget');
      snapshots.add(call.arguments as Map);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final bridge = DesktopWidgetBridge(controller);
    await bridge.start();
    addTearDown(bridge.dispose);
    await bridge.handleCall(MethodCall('widgetComplete', {'id': controller.tasks.single.id, 'completed': true}));
    await Future<void>.delayed(Duration.zero);
    expect((snapshots.last['tasks'] as List).single['completed'], isTrue);
    final encoded = jsonEncode(snapshots);
    expect(encoded, contains('组件标题'));
    expect(encoded, isNot(contains('私人备注')));
    expect(encoded, isNot(contains('token')));
    expect(encoded, isNot(contains('server_url')));
    expect(await bridge.handleCall(const MethodCall('widgetComplete', {'id': 'missing', 'completed': true})), isFalse);
  });
  test('Native widget repaints when its override or followed app theme changes', () async {
    final controller = await _controller(_Store());
    addTearDown(controller.dispose);
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('cn.privatetodo/desktop');
    final themes = <String>[];
    final appThemes = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      themes.add((call.arguments as Map)['theme'] as String);
      appThemes.add((call.arguments as Map)['app_theme'] as String);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final bridge = DesktopWidgetBridge(controller);
    await bridge.start();
    addTearDown(bridge.dispose);
    expect(themes.last, 'green');
    await controller.setAppearance(TodoThemeColor.black, null);
    await Future<void>.delayed(Duration.zero);
    expect(themes.last, 'black');
    await controller.setAppearance(TodoThemeColor.blue, TodoThemeColor.white);
    await Future<void>.delayed(Duration.zero);
    expect(themes.last, 'white');
    expect(appThemes.last, 'blue');
    await controller.setAppearance(TodoThemeColor.green, TodoThemeColor.white);
    await Future<void>.delayed(Duration.zero);
    expect(themes.last, 'white');
    await controller.setAppearance(TodoThemeColor.blue, null);
    await Future<void>.delayed(Duration.zero);
    expect(themes.last, 'blue');
  });
}
