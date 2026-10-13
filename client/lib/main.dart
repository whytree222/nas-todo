import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';

import 'app_controller.dart';
import 'appearance.dart';
import 'android_widget.dart';
import 'desktop_widget_bridge.dart';
import 'theme.dart';
import 'ui/home_screen.dart';
import 'ui/daily_celebration_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final controller = await AppController.create();
    await AndroidWidgetBridge.attach(controller);
    await DesktopWidgetBridge.attach(controller);
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
      await DesktopWidgetBridge.attach(controller);
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
      theme: buildTodoTheme(TodoThemeColor.green),
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
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => MaterialApp(
      title: '私有待办',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildTodoTheme(controller.appTheme),
      navigatorObservers: [dailyCelebrationRouteObserver],
      builder: (context, child) {
        final theme = Theme.of(context);
        final dark = theme.brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: theme.colorScheme.surface,
            systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          ),
          child: child!,
        );
      },
      home: HomeScreen(controller: controller),
    ),
    );
  }
}
