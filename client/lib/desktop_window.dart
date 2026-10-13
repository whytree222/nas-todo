import 'dart:io';

import 'package:flutter/services.dart';

class DesktopWindow {
  static const _channel = MethodChannel('cn.privatetodo/desktop');
  static bool get supported => Platform.isWindows;
  static Future<void> openWidget() => _channel.invokeMethod<void>('openWidget');
  static Future<bool> isMainVisible() async {
    if (!supported) return true;
    try {
      return await _channel.invokeMethod<bool>('isMainVisible') ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }
}
