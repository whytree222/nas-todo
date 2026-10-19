import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'appearance.dart';
import 'achievement_core.dart';
import 'daily_celebration.dart';
import 'storage_io.dart';
import 'sync_core.dart';
import 'task_dates.dart';

/// Keeps local edits available even when the NAS cannot be reached.
class AppController extends ChangeNotifier {
  AppController._(
    this.engine,
    this._transport,
    this._configFile,
    this._vault,
    this._appearanceStore,
    this._celebrationStore,
    this._clock,
  );

  @visibleForTesting
  factory AppController.forTesting(
    SyncEngine engine, {
    AppearanceStore? appearanceStore,
    CelebrationStore? celebrationStore,
    DateTime Function()? clock,
  }) => AppController._(
    engine,
    HttpSyncTransport('', ''),
    File('unused-test-config.json'),
    const FlutterSecureStorage(),
    appearanceStore ?? MemoryAppearanceStore(),
    celebrationStore ?? MemoryCelebrationStore(),
    clock ?? DateTime.now,
  );

  final SyncEngine engine;
  final HttpSyncTransport _transport;
  final File _configFile;
  final FlutterSecureStorage _vault;
  final AppearanceStore _appearanceStore;
  final CelebrationStore _celebrationStore;
  final DateTime Function() _clock;
  final Set<String> _celebratedDays = {};
  DailyCelebration? _pendingCelebration;
  Future<void>? _loadingCelebration;
  bool _celebrationReadable = true;
  bool _claimingCelebration = false;
  Future<void> _celebrationWriteTail = Future<void>.value();
  AppearancePreferences _appearance = const AppearancePreferences();
  bool _savingAppearance = false;
  String? _appearanceError;
  Timer? _periodicTimer;
  Timer? _editTimer;
  bool _disposed = false;
  bool _syncing = false;
  Completer<void>? _syncCompletion;
  bool _editing = false;
  String _serverUrl = '';
  String _token = '';
  String? _error;

  static const _tokenKey = 'private_todo_nas_token';

  static Future<AppController> create() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final transport = HttpSyncTransport('', '');
    final controller = AppController._(
      SyncEngine(
        FileDataStore(File('${directory.path}/tasks.json')),
        transport,
      ),
      transport,
      File('${directory.path}/config.json'),
      const FlutterSecureStorage(),
      FileAppearanceStore(File('${directory.path}/appearance.json')),
      FileCelebrationStore(File('${directory.path}/celebration.json')),
      DateTime.now,
    );
    try {
      await controller._initialize();
      return controller;
    } catch (_) {
      controller.dispose();
      rethrow;
    }
  }

  List<Task> get tasks => engine.tasks;
  AchievementState? get achievement => engine.achievement;
  bool get achievementsSupported => engine.achievementsSupported;
  List<SyncConflict> get conflicts => engine.conflicts;
  int get pendingCount => engine.pendingCount;
  DateTime? get lastSyncedAt => engine.lastSyncedAt;
  bool get busy => _syncing || _editing;
  bool get editing => _editing;
  bool get syncing => _syncing;
  String get serverUrl => _serverUrl;
  String get token => _token;
  String? get error => _error;
  bool get isConfigured => _serverUrl.isNotEmpty && _token.isNotEmpty;
  TodoThemeColor get appTheme => _appearance.appTheme;
  TodoThemeColor? get widgetTheme => _appearance.widgetTheme;
  TodoThemeColor get effectiveWidgetTheme => _appearance.effectiveWidgetTheme;
  bool get savingAppearance => _savingAppearance;
  String? get appearanceError => _appearanceError;
  DailyCelebration? get pendingDailyCelebration => _pendingCelebration;

  Future<void> _initialize() async {
    // Stop startup on corrupt storage, preserving the original data files.
    await engine.load();
    await _loadAppearance();
    await _loadCelebration();
    try {
      if (await _configFile.exists()) {
        final config = jsonDecode(
          await _configFile.readAsString(),
        ) as Map<String, dynamic>;
        _serverUrl = (config['server_url'] as String?) ?? '';
      }
      _token = await _vault.read(key: _tokenKey) ?? '';
      if (isConfigured) _transport.configure(_serverUrl, _token);
    } catch (error) {
      _setError(error);
      _serverUrl = '';
      _token = '';
    }
    _periodicTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (isConfigured && !busy) {
        unawaited(sync());
      }
    });
    if (isConfigured) unawaited(sync());
  }

  Future<void> _loadAppearance() async {
    try {
      _appearance = AppearancePreferences.fromJson(
        await _appearanceStore.read(),
      );
      _appearanceError = null;
    } catch (error) {
      _appearanceError = '主题设置读取失败，已使用默认颜色：${_messageFor(error)}';
    }
  }

  @visibleForTesting
  Future<void> loadAppearanceForTesting() async {
    await _loadAppearance();
    _notify();
  }

  Future<bool> setAppearance(
    TodoThemeColor appTheme,
    TodoThemeColor? widgetTheme,
  ) async {
    if (_disposed || _savingAppearance) return false;
    if (_appearance.appTheme == appTheme &&
        _appearance.widgetTheme == widgetTheme &&
        _appearanceError == null) {
      return true;
    }
    _savingAppearance = true;
    _notify();
    try {
      final next = AppearancePreferences(
        appTheme: appTheme,
        widgetTheme: widgetTheme,
      );
      await _appearanceStore.write(next.toJson());
      _appearance = next;
      _appearanceError = null;
      return true;
    } catch (error) {
      _appearanceError = '主题颜色未能保存：${_messageFor(error)}';
      return false;
    } finally {
      _savingAppearance = false;
      _notify();
    }
  }

  Future<bool> setConnection(String url, String token) async {
    if (busy) return false;
    final normalizedUrl = url.trim().replaceFirst(RegExp(r'/+$'), '');
    final normalizedToken = token.trim();
    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      _error = '请输入完整的 http:// 或 https:// 服务地址，不要包含账号、查询参数或锚点。';
      _notify();
      return false;
    }
    if (!RegExp(r'^[!-~]{32,}$').hasMatch(normalizedToken)) {
      _error = '访问令牌至少需要 32 个字符，只能包含不带空格的英文字符、数字或符号。';
      _notify();
      return false;
    }
    _editing = true;
    _notify();
    try {
      // Persist the credential through the operating system's secure store.
      await _vault.write(key: _tokenKey, value: normalizedToken);
      await _configFile.writeAsString(
        jsonEncode({'server_url': normalizedUrl}),
        flush: true,
      );
      _serverUrl = normalizedUrl;
      _token = normalizedToken;
      _transport.configure(_serverUrl, _token);
      _error = null;
      return true;
    } catch (error) {
      _setError(error);
      return false;
    } finally {
      _editing = false;
      _notify();
    }
  }

  Future<bool> saveTask(TaskDraft draft, {String? id}) async {
    return _edit(() => engine.saveTask(draft, id: id));
  }

  Future<bool> setCompleted(String id, bool completed) async {
    return _edit(() async {
      final change = await engine.setCompleted(id, completed);
      if (!completed || _disposed) return;
      final celebration = celebrationForCompletion(change, _clock());
      if (celebration != null) await _queueCelebration(celebration);
    });
  }

  Future<void> _loadCelebration() => _loadingCelebration ??= () async {
    try {
      final saved = await _celebrationStore.read();
      if (_disposed) return;
      final days = saved?['celebrated_days'];
      if (days is List) _celebratedDays.addAll(days.whereType<String>());
      _pendingCelebration = DailyCelebration.fromJson(saved?['pending']);
    } catch (_) {
      // An unreadable encouragement preference must never disrupt task storage.
      // Suppress this launch rather than risk replaying a previously seen card.
      _celebrationReadable = false;
    }
  }();

  Map<String, dynamic> _celebrationState(DailyCelebration? pending) => {
    'schema': 1,
    'celebrated_days': _celebratedDays.toList()..sort(),
    'pending': pending?.toJson(),
  };

  Future<void> _writeCelebration(DailyCelebration? pending) {
    final state = _celebrationState(pending);
    final write = _celebrationWriteTail.then(
      (_) => _celebrationStore.write(state),
    );
    // A failed preference flush must not poison later independent daily writes.
    _celebrationWriteTail = write.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return write;
  }

  Future<void> _queueCelebration(DailyCelebration celebration) async {
    await _loadCelebration();
    if (_disposed ||
        !_celebrationReadable ||
        _celebratedDays.contains(celebration.day)) {
      return;
    }
    // Keep the in-memory marker on failure as well: completing tasks still works,
    // and undo/recomplete cannot repeatedly retry a broken preference disk.
    _celebratedDays.add(celebration.day);
    try {
      await _writeCelebration(celebration);
      if (!_disposed) _pendingCelebration = celebration;
    } catch (_) {
      // Task completion was already durably saved; don't report it as failed.
    }
  }

  /// Clear the durable pending event before presentation, including startup
  /// actions queued by Android widgets before the main screen exists.
  Future<DailyCelebration?> takeDailyCelebration() async {
    await _loadCelebration();
    if (_disposed || _claimingCelebration || _pendingCelebration == null)
      return null;
    _claimingCelebration = true;
    final pending = _pendingCelebration!;
    try {
      await _writeCelebration(null);
      if (identical(_pendingCelebration, pending)) _pendingCelebration = null;
      // Another user action or midnight may occur while the preference flushes.
      final today = dateKey(_clock());
      final scheduled = tasks
          .where((task) => !task.deleted && task.dueDate == today)
          .toList();
      final valid =
          pending.day == today &&
          scheduled.isNotEmpty &&
          scheduled.every((task) => task.completed);
      return !_disposed && valid
          ? DailyCelebration(day: pending.day, taskCount: scheduled.length)
          : null;
    } catch (_) {
      // Retry only on a future launch, never spin on every controller rebuild.
      if (identical(_pendingCelebration, pending)) _pendingCelebration = null;
      return null;
    } finally {
      _claimingCelebration = false;
      _notify();
    }
  }

  @visibleForTesting
  Future<void> loadCelebrationForTesting() async {
    await _loadCelebration();
    _notify();
  }

  Future<bool> scheduleTask(String id, String date) async {
    return _edit(() => engine.scheduleTask(id, date));
  }

  Future<bool> setTaskPlacement(
    String id, {
    String? listName,
    int? priority,
    String? dueDate,
    bool clearDueDate = false,
    bool requireIncomplete = false,
  }) => _edit(
    () => engine.setTaskPlacement(
      id,
      listName: listName,
      priority: priority,
      dueDate: dueDate,
      clearDueDate: clearDueDate,
      requireIncomplete: requireIncomplete,
    ),
  );

  Future<bool> setTaskQuadrant(
    String id, {
    required bool important,
    required bool urgent,
  }) => _edit(
    () => engine.setTaskQuadrant(
      id,
      important: important,
      urgent: urgent,
      today: dateKey(_clock()),
    ),
  );

  Future<bool> deleteTask(String id) async {
    return _edit(() => engine.deleteTask(id));
  }

  Future<bool> resolveConflict(String id, {required bool keepLocal}) async {
    return _edit(() => engine.resolveConflict(id, keepLocal: keepLocal));
  }

  Future<bool> _edit(Future<void> Function() operation) async {
    if (_disposed || _editing) return false;
    _editing = true;
    _notify();
    try {
      await operation();
      _error = null;
      _scheduleSync();
      return true;
    } catch (error) {
      _setError(error);
      return false;
    } finally {
      _editing = false;
      _notify();
    }
  }

  void _scheduleSync() {
    _editTimer?.cancel();
    _editTimer = null;
    if (_disposed || !isConfigured) return;
    _editTimer = Timer(const Duration(milliseconds: 700), () {
      if (isConfigured && !busy) unawaited(sync());
    });
  }

  Future<void> sync() async {
    if (_disposed || busy) return;
    if (!isConfigured) {
      _error = '先在连接设置中填写 NAS 地址和访问令牌；本机待办仍然可以离线使用。';
      _notify();
      return;
    }
    _syncing = true;
    _syncCompletion = Completer<void>();
    _notify();
    try {
      await engine.sync();
      _error = null;
    } catch (error) {
      _setError(error);
    } finally {
      _syncing = false;
      _syncCompletion?.complete();
      _syncCompletion = null;
      _notify();
    }
  }

  Future<void> waitForSync() async {
    final pending = _syncCompletion?.future;
    if (pending != null) await pending;
  }

  void onResume() {
    _notify();
    if (isConfigured && !busy) unawaited(sync());
  }

  void clearError() {
    _error = null;
    _notify();
  }

  void _setError(Object error) {
    _error = _messageFor(error);
  }

  String _messageFor(Object error) {
    var message = error.toString();
    if (_token.isNotEmpty) message = message.replaceAll(_token, '••••••');
    return message.replaceFirst(RegExp(r'^\w*Exception:\s*'), '');
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _periodicTimer?.cancel();
    _editTimer?.cancel();
    _transport.dispose();
    super.dispose();
  }
}
