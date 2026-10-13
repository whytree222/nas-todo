import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'app_controller.dart';
import 'task_dates.dart';

Map<String, dynamic> desktopWidgetState(AppController controller) => {
  'today': dateKey(DateTime.now()),
  'theme': controller.effectiveWidgetTheme.name,
  'app_theme': controller.appTheme.name,
  'editing': controller.editing,
  'status': controller.syncing ? '正在同步' : controller.pendingCount > 0
      ? '${controller.pendingCount} 项等待同步' : controller.isConfigured ? '已保存 · NAS 已配置' : '本机离线模式',
  'error': controller.error ?? '',
  'tasks': [for (final task in controller.tasks) {
    'id': task.id, 'title': task.title, 'completed': task.completed,
    'due_date': task.dueDate ?? '', 'priority': task.priority,
    'conflict': controller.conflicts.any((conflict) => conflict.taskId == task.id),
  }],
};

/// The independent native widget sends edits to the one owner of the offline queue.
class DesktopWidgetBridge {
  DesktopWidgetBridge(this.controller, {this.channel = const MethodChannel('cn.privatetodo/desktop')});
  final AppController controller;
  final MethodChannel channel;
  Timer? _clock;
  bool _publishing = false;
  bool _again = false;
  bool _disposed = false;

  static Future<void> attach(AppController controller) async {
    if (!Platform.isWindows) return;
    await DesktopWidgetBridge(controller).start();
  }

  Future<void> start() async {
    channel.setMethodCallHandler(handleCall);
    controller.addListener(_changed);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => _changed());
    await publish();
  }

  Future<dynamic> handleCall(MethodCall call) async {
    if (call.method == 'mainWindowShown') {
      controller.onResume();
      return null;
    }
    if (call.method == 'widgetComplete') {
      if (call.arguments is! Map) return false;
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final id = args['id'];
      final completed = args['completed'];
      if (id is! String || completed is! bool || controller.editing) return false;
      final matches = controller.tasks.where((task) => task.id == id);
      if (matches.isEmpty || controller.conflicts.any((conflict) => conflict.taskId == id)) return false;
      if (matches.first.completed == completed) return true;
      return controller.setCompleted(id, completed);
    }
    if (call.method == 'widgetSync') {
      await controller.sync();
      return controller.error == null;
    }
    throw MissingPluginException('Unknown desktop widget operation');
  }

  void _changed() => unawaited(publish());

  Future<void> publish() async {
    if (_disposed) return;
    if (_publishing) { _again = true; return; }
    _publishing = true;
    try {
      do {
        _again = false;
        await channel.invokeMethod<void>('publishWidget', desktopWidgetState(controller));
      } while (_again && !_disposed);
    } on MissingPluginException {
      // Flutter widget tests and non-native previews don't host desktop widgets.
    } on PlatformException {
      // Regular task editing remains available if the native view is unavailable.
    } finally {
      _publishing = false;
    }
  }

  void dispose() {
    _disposed = true;
    _clock?.cancel();
    controller.removeListener(_changed);
    channel.setMethodCallHandler(null);
  }
}
