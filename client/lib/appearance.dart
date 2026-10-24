import 'dart:convert';
import 'dart:io';

import 'workspace_preferences.dart';

enum TodoThemeColor {
  black,
  white,
  green,
  blue;

  String get label => switch (this) {
    black => '黑',
    white => '白',
    green => '绿',
    blue => '蓝',
  };

  static TodoThemeColor? tryParse(Object? name) {
    for (final color in values) {
      if (color.name == name) {
        return color;
      }
    }
    return null;
  }
}

class AppearancePreferences {
  const AppearancePreferences({
    this.appTheme = TodoThemeColor.green,
    this.widgetTheme,
    this.workspace = const WorkspacePreferences(),
  });

  final TodoThemeColor appTheme;
  final TodoThemeColor? widgetTheme;
  final WorkspacePreferences workspace;
  TodoThemeColor get effectiveWidgetTheme => widgetTheme ?? appTheme;

  factory AppearancePreferences.fromJson(Map<String, dynamic>? json) =>
      AppearancePreferences(
        appTheme:
            TodoThemeColor.tryParse(json?['app_theme']) ?? TodoThemeColor.green,
        widgetTheme: TodoThemeColor.tryParse(json?['widget_theme']),
        workspace: WorkspacePreferences.fromJson(
          json?['workspace'] == null
              ? null
              : Map<String, dynamic>.from(json!['workspace'] as Map),
        ),
      );

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'app_theme': appTheme.name,
    'widget_theme': widgetTheme?.name,
    'workspace': workspace.toJson(),
  };
}

abstract interface class AppearanceStore {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> state);
}

class FileAppearanceStore implements AppearanceStore {
  FileAppearanceStore(this.file);
  final File file;

  @override
  Future<Map<String, dynamic>?> read() async {
    if (!await file.exists()) {
      return null;
    }
    return Map<String, dynamic>.from(
      jsonDecode(await file.readAsString()) as Map,
    );
  }

  @override
  Future<void> write(Map<String, dynamic> state) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(state), flush: true);
    await temporary.rename(file.path);
  }
}

class MemoryAppearanceStore implements AppearanceStore {
  Map<String, dynamic>? _state;

  Map<String, dynamic> _copy(Map<String, dynamic> value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

  @override
  Future<Map<String, dynamic>?> read() async =>
      _state == null ? null : _copy(_state!);

  @override
  Future<void> write(Map<String, dynamic> state) async {
    _state = _copy(state);
  }
}
