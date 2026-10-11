import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_controller.dart';
import 'sync_core.dart';

// A display snapshot contains no notes, server address or synchronization key.
String widgetSnapshot(Iterable<Task> tasks, Iterable<SyncConflict> conflicts,
    {String theme = 'green'}) {
  final blocked = conflicts.map((conflict) => conflict.taskId).toSet();
  final color = const {'black', 'white', 'green', 'blue'}.contains(theme)
      ? theme : 'green';
  return jsonEncode({'theme': color, 'tasks': [
    for (final task in tasks.where((task) => !task.deleted)) {
      'id': task.id, 'title': task.title, 'due_date': task.dueDate,
      'completed': task.completed, 'priority': task.priority,
      'conflict': blocked.contains(task.id),
    },
  ]});
}

/// Acknowledge an action only after its desired state is saved durably.
/// Retried actions set a value instead of toggling it a second time.
Future<List<String>> applyWidgetActions(AppController controller, List<dynamic> actions) async {
  final acknowledged = <String>[];
  for (final raw in actions) {
    if (controller.editing) break;
    if (raw is! Map) continue;
    final actionId = raw['action_id'];
    if (actionId is! String) continue;
    final id = raw['task_id'];
    final desired = raw['completed'];
    final matching = controller.tasks.where((task) => task.id == id && !task.deleted);
    if (id is! String || desired is! bool || matching.isEmpty ||
        controller.conflicts.any((conflict) => conflict.taskId == id)) {
      acknowledged.add(actionId);
      continue;
    }
    if (matching.first.completed != desired && !await controller.setCompleted(id, desired)) break;
    acknowledged.add(actionId);
  }
  return acknowledged;
}

class AndroidWidgetBridge with WidgetsBindingObserver {
  AndroidWidgetBridge._(this.controller);
  static const _channel = MethodChannel('cn.privatetodo/widgets');
  final AppController controller;
  bool _working = false;
  bool _again = false;
  String? _published;

  static Future<void> attach(AppController controller) async {
    if (!Platform.isAndroid) return;
    final bridge = AndroidWidgetBridge._(controller);
    WidgetsBinding.instance.addObserver(bridge);
    controller.addListener(bridge._changed);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'widgetActionsChanged') await bridge._refresh();
    });
    await bridge._refresh();
  }

  void _changed() => unawaited(_refresh());

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_working) { _again = true; return; }
    _working = true;
    try {
      do {
        _again = false;
        if (!controller.editing) {
          final actions = await _channel.invokeListMethod<dynamic>('getWidgetActions') ?? [];
          final saved = await applyWidgetActions(controller, actions);
          if (saved.isNotEmpty) await _channel.invokeMethod<void>('ackWidgetActions', saved);
        }
        final snapshot = widgetSnapshot(controller.tasks, controller.conflicts,
            theme: controller.effectiveWidgetTheme.name);
        if (snapshot != _published) {
          await _channel.invokeMethod<void>('updateWidget', snapshot);
          _published = snapshot;
        }
      } while (_again);
    } on PlatformException {
      // The queue remains on disk for the next resume; don't disrupt the editor.
    } on MissingPluginException {
      // Platforms without a widget host still retain all regular app functions.
    } finally {
      _working = false;
    }
  }
}
