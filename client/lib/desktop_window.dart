import 'dart:io';

import 'package:flutter/services.dart';

class DesktopWindow {
  static const _channel = MethodChannel('cn.privatetodo/desktop');
  static bool get supported => Platform.isWindows;
  static Future<void> setCompact(bool value) => _channel.invokeMethod<void>('setCompact', value);
  static Future<void> setPinned(bool value) => _channel.invokeMethod<void>('setPinned', value);
  static Future<void> startDrag() => _channel.invokeMethod<void>('startDrag');
}
