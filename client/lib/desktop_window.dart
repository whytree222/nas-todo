import 'dart:io';

import 'package:flutter/services.dart';

class DesktopWindow {
  static const _channel = MethodChannel('cn.privatetodo/desktop');
  static bool get supported => Platform.isWindows;
  static Future<void> openWidget() => _channel.invokeMethod<void>('openWidget');
}
