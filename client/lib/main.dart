import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_controller.dart';
import 'android_widget.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final controller = await AppController.create();
    await AndroidWidgetBridge.attach(controller);
    runApp(PrivateTodoApp(controller: controller));
  } catch (error) {
    runApp(_StartupFailure(error: error));
  }
}

class _StartupFailure extends StatefulWidget {
  const _StartupFailure({required this.error});
  final Object error;

  @override
  State<_StartupFailure> createState() => _StartupFailureState();
}

class _StartupFailureState extends State<_StartupFailure> {
  bool _reading = false;
  String? _retryError;

  Future<void> _retry() async {
    setState(() => _reading = true);
    try {
      final controller = await AppController.create();
      await AndroidWidgetBridge.attach(controller);
      runApp(PrivateTodoApp(controller: controller));
    } catch (error) {
      if (mounted) {
        setState(() {
          _reading = false;
          _retryError = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storage_rounded, size: 44),
                  const SizedBox(height: 24),
                  const Text('本机数据未能读取', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  const Text('数据文件已保留。请检查存储权限，或按部署文档中的本机备份说明恢复数据。', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  SelectableText(_retryError ?? widget.error.toString(), style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: _reading ? null : _retry, child: Text(_reading ? '正在读取' : '重新读取')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PrivateTodoApp extends StatelessWidget {
  const PrivateTodoApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xff326b58),
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: '私有待办',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colors,
        scaffoldBackgroundColor: const Color(0xfff6f8f6),
        fontFamilyFallback: const ['Microsoft YaHei', 'Noto Sans CJK SC'],
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xfff6f8f6),
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colors.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colors.outlineVariant),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 46),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: colors.primaryContainer,
        ),
      ),
      home: HomeScreen(controller: controller),
    );
  }
}
