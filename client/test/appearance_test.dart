import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_todo/app_controller.dart';
import 'package:nas_todo/appearance.dart';
import 'package:nas_todo/sync_core.dart';
import 'package:nas_todo/theme.dart';

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
      throw StateError('Network is not used by appearance tests.');
}

Future<AppController> _controller(AppearanceStore store) async {
  final engine = SyncEngine(_TaskStore(), _UnusedTransport());
  await engine.load();
  final controller = AppController.forTesting(engine, appearanceStore: store);
  await controller.loadAppearanceForTesting();
  return controller;
}

class _FailingStore extends MemoryAppearanceStore {
  bool fail = false;
  @override
  Future<void> write(Map<String, dynamic> value) async {
    if (fail) throw const FileSystemException('磁盘不可写');
    await super.write(value);
  }
}

class _DelayedStore extends MemoryAppearanceStore {
  final ready = Completer<void>();
  @override
  Future<void> write(Map<String, dynamic> value) async {
    await ready.future;
    await super.write(value);
  }
}

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  return ((a > b ? a : b) + 0.05) / ((a > b ? b : a) + 0.05);
}

void main() {
  test('Appearance names are stable, unknown values safely use green and follow app', () {
    expect(TodoThemeColor.values.map((color) => color.name), ['black', 'white', 'green', 'blue']);
    final defaults = AppearancePreferences.fromJson(null);
    expect(defaults.appTheme, TodoThemeColor.green);
    expect(defaults.widgetTheme, isNull);
    expect(defaults.effectiveWidgetTheme, TodoThemeColor.green);
    for (final invalid in ['unknown', '', 42, true]) {
      final appearance = AppearancePreferences.fromJson({'app_theme': invalid, 'widget_theme': invalid});
      expect(appearance.appTheme, TodoThemeColor.green);
      expect(appearance.widgetTheme, isNull);
    }
  });

  test('Application and widget colors survive a restart independently', () async {
    final directory = await Directory.systemTemp.createTemp('nas-todo-appearance-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/appearance.json');
    final first = await _controller(FileAppearanceStore(file));
    addTearDown(first.dispose);
    expect(await first.setAppearance(TodoThemeColor.black, TodoThemeColor.blue), isTrue);
    final state = jsonDecode(await file.readAsString()) as Map;
    expect(state, {'schema': 1, 'app_theme': 'black', 'widget_theme': 'blue'});
    final restarted = await _controller(FileAppearanceStore(file));
    addTearDown(restarted.dispose);
    expect(restarted.appTheme, TodoThemeColor.black);
    expect(restarted.widgetTheme, TodoThemeColor.blue);
    expect(restarted.effectiveWidgetTheme, TodoThemeColor.blue);
    expect(await restarted.setAppearance(TodoThemeColor.white, null), isTrue);
    expect(restarted.effectiveWidgetTheme, TodoThemeColor.white);
    final following = await _controller(FileAppearanceStore(file));
    addTearDown(following.dispose);
    expect(following.appTheme, TodoThemeColor.white);
    expect(following.widgetTheme, isNull);
    expect(following.effectiveWidgetTheme, TodoThemeColor.white);
  });

  test('A failed write retains the previous app and widget colors and saved state', () async {
    final store = _FailingStore();
    final controller = await _controller(store);
    addTearDown(controller.dispose);
    expect(await controller.setAppearance(TodoThemeColor.blue, TodoThemeColor.white), isTrue);
    store.fail = true;
    expect(await controller.setAppearance(TodoThemeColor.black, TodoThemeColor.green), isFalse);
    expect(controller.appTheme, TodoThemeColor.blue);
    expect(controller.widgetTheme, TodoThemeColor.white);
    expect(controller.savingAppearance, isFalse);
    expect(controller.appearanceError, contains('磁盘不可写'));
    expect(await store.read(), {'schema': 1, 'app_theme': 'blue', 'widget_theme': 'white'});
  });

  test('A damaged appearance file falls back safely and can be replaced by a new choice', () async {
    final directory = await Directory.systemTemp.createTemp('nas-todo-appearance-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/appearance.json');
    const damaged = '{"app_theme":';
    await file.writeAsString(damaged, flush: true);
    final controller = await _controller(FileAppearanceStore(file));
    addTearDown(controller.dispose);
    expect(controller.appTheme, TodoThemeColor.green);
    expect(controller.widgetTheme, isNull);
    expect(controller.appearanceError, contains('主题设置读取失败'));
    expect(await file.readAsString(), damaged);
    // The default choice must also repair the unreadable preference file.
    expect(await controller.setAppearance(TodoThemeColor.green, null), isTrue);
    expect(controller.appearanceError, isNull);
    final restarted = await _controller(FileAppearanceStore(file));
    addTearDown(restarted.dispose);
    expect(restarted.appTheme, TodoThemeColor.green);
    expect(restarted.widgetTheme, isNull);
    expect(restarted.appearanceError, isNull);
  });

  test('Palette changes are published after durable storage completes', () async {
    final store = _DelayedStore();
    final controller = await _controller(store);
    addTearDown(controller.dispose);
    final observed = <TodoThemeColor>[];
    controller.addListener(() => observed.add(controller.appTheme));
    final saving = controller.setAppearance(TodoThemeColor.black, null);
    expect(controller.savingAppearance, isTrue);
    expect(controller.appTheme, TodoThemeColor.green);
    expect(observed, everyElement(TodoThemeColor.green));
    store.ready.complete();
    expect(await saving, isTrue);
    expect(controller.appTheme, TodoThemeColor.black);
    expect(observed.last, TodoThemeColor.black);
  });

  test('Every palette has readable normal, secondary, action, and danger text', () {
    for (final color in TodoThemeColor.values) {
      final theme = buildTodoTheme(color);
      final scheme = theme.colorScheme;
      expect(theme.brightness, color == TodoThemeColor.black ? Brightness.dark : Brightness.light);
      expect(_contrast(scheme.onSurface, scheme.surface), greaterThanOrEqualTo(4.5), reason: color.name);
      expect(_contrast(scheme.onSurfaceVariant, scheme.surfaceContainerLow), greaterThanOrEqualTo(4.5), reason: color.name);
      expect(_contrast(scheme.onPrimary, scheme.primary), greaterThanOrEqualTo(4.5), reason: color.name);
      expect(_contrast(scheme.onPrimaryContainer, scheme.primaryContainer), greaterThanOrEqualTo(4.5), reason: color.name);
      expect(_contrast(scheme.onErrorContainer, scheme.errorContainer), greaterThanOrEqualTo(4.5), reason: color.name);
      expect(theme.inputDecorationTheme.fillColor, scheme.surface);
    }
  });
}
