import 'package:flutter/material.dart';

import 'appearance.dart';

Color themeSwatch(TodoThemeColor color) => switch (color) {
  TodoThemeColor.black => const Color(0xff171b19),
  TodoThemeColor.white => const Color(0xffffffff),
  TodoThemeColor.green => const Color(0xff326b58),
  TodoThemeColor.blue => const Color(0xff315fa9),
};

ThemeData buildTodoTheme(TodoThemeColor themeColor) {
  final dark = themeColor == TodoThemeColor.black;
  var colors = ColorScheme.fromSeed(
    seedColor: themeColor == TodoThemeColor.white
        ? const Color(0xff596367)
        : themeColor == TodoThemeColor.black
        ? const Color(0xffb9c3be)
        : themeSwatch(themeColor),
    brightness: dark ? Brightness.dark : Brightness.light,
  );
  if (dark) {
    colors = colors.copyWith(
      primary: const Color(0xffcad3ce),
      onPrimary: const Color(0xff17221c),
      primaryContainer: const Color(0xff35433b),
      onPrimaryContainer: const Color(0xffe4eee7),
      surface: const Color(0xff151a17),
      onSurface: const Color(0xffedf2ef),
      onSurfaceVariant: const Color(0xffbdc8c0),
      surfaceContainerLow: const Color(0xff1b211d),
      surfaceContainer: const Color(0xff242c26),
      surfaceContainerHigh: const Color(0xff2b342e),
      surfaceContainerHighest: const Color(0xff333e36),
      outline: const Color(0xff8b988e),
      outlineVariant: const Color(0xff404c43),
    );
  } else if (themeColor == TodoThemeColor.white) {
    colors = colors.copyWith(
      primary: const Color(0xff30393d),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xffe5eaed),
      onPrimaryContainer: const Color(0xff172126),
      secondary: const Color(0xff536067),
      secondaryContainer: const Color(0xffe9eef0),
      onSecondaryContainer: const Color(0xff223138),
      surface: Colors.white,
      onSurface: const Color(0xff20282c),
      onSurfaceVariant: const Color(0xff556168),
      surfaceContainerLow: const Color(0xfff6f8f9),
      surfaceContainer: const Color(0xffeff2f4),
      surfaceContainerHigh: const Color(0xffe9edf0),
      surfaceContainerHighest: const Color(0xffe3e8eb),
      outline: const Color(0xff6e7a81),
      outlineVariant: const Color(0xffd5dce0),
    );
  } else {
    colors = colors.copyWith(surface: Colors.white);
  }
  final background = switch (themeColor) {
    TodoThemeColor.black => const Color(0xff111613),
    TodoThemeColor.white => const Color(0xfff5f7f8),
    TodoThemeColor.green => const Color(0xfff5f8f6),
    TodoThemeColor.blue => const Color(0xfff4f7fc),
  };
  return ThemeData(
    useMaterial3: true,
    brightness: colors.brightness,
    colorScheme: colors,
    scaffoldBackgroundColor: background,
    fontFamilyFallback: const ['Microsoft YaHei', 'Noto Sans CJK SC'],
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: colors.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    dialogTheme: DialogThemeData(backgroundColor: colors.surface),
    dividerTheme: DividerThemeData(
      color: colors.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 450),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surface,
      indicatorColor: colors.primaryContainer,
    ),
  );
}
