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
import 'personal_core.dart';
import 'workspace_preferences.dart';
import 'update_controller.dart';
import 'habit_achievement.dart';

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
  Future<void> _preferencesTail = Future<void>.value();
  String? workspaceError;
  WorkspacePreferences get workspace => _appearance.workspace;
  Future<void> _queuePreferences(Future<void> Function() action) {
    final result = _preferencesTail.then((_) => action());
    _preferencesTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<bool> setWorkspace(Map<String, dynamic> changes) async {
    if (_disposed) {
      return false;
    }
    try {
      await _queuePreferences(() async {
        final next = AppearancePreferences(
          appTheme: _appearance.appTheme,
          widgetTheme: _appearance.widgetTheme,
          workspace: workspace.withChanges(changes),
        );
        await _appearanceStore.write(next.toJson());
        _appearance = next;
        workspaceError = null;
      });
      _notify();
      return true;
    } catch (_) {
      workspaceError = '显示偏好未能保存，请重试。';
      _notify();
      return false;
    }
  }

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

  UpdateController? updates;
  bool _updatesForeground = true;
  int _updateEditorCount = 0;
  bool _quickUpdateBlock = false;
  VoidCallback pauseUpdatesForEditor() {
    _updateEditorCount++;
    _updatePolicy();
    var released = false;
    return () {
      if (!released) {
        released = true;
        _updateEditorCount--;
        _updatePolicy();
      }
    };
  }

  void setUpdatesForeground(bool value) {
    _updatesForeground = value;
    _updatePolicy();
  }

  void setQuickUpdateBlock(bool value) {
    _quickUpdateBlock = value;
    _updatePolicy();
  }

  void _updatePolicy() => updates?.setAllowed(
    !_disposed &&
        _updatesForeground &&
        !busy &&
        _updateEditorCount == 0 &&
        !_quickUpdateBlock,
  );

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
      controller.updates = await UpdateController.create();
      controller.updates?.addListener(controller._notify);
      controller._updatePolicy();
      return controller;
    } catch (_) {
      controller.dispose();
      rethrow;
    }
  }

  List<Task> get tasks => engine.tasks;
  List<Habit> get habits => engine.habits;
  List<HabitCheckIn> get habitCheckIns => engine.habitCheckIns;
  List<PersonalConflict> get personalConflicts => engine.personalConflicts;
  bool get personalSupported => engine.personalSupported;
  bool get personalUpgradeRequired => engine.personalUpgradeRequired;
  AchievementState? get achievement => engine.achievement;
  bool get achievementsSupported => engine.achievementsSupported;
  bool get habitAchievementsSupported => engine.habitAchievementsSupported;
  List<HabitAchievementPlan> get habitAchievementPlans =>
      engine.habitAchievementPlans;
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
      if (isConfigured) {
        _transport.configure(_serverUrl, _token);
      }
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
    if (isConfigured) {
      unawaited(sync());
    }
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
    if (_disposed || _savingAppearance) {
      return false;
    }
    if (_appearance.appTheme == appTheme &&
        _appearance.widgetTheme == widgetTheme &&
        _appearanceError == null) {
      return true;
    }
    _savingAppearance = true;
    _notify();
    try {
      await _queuePreferences(() async {
        final next = AppearancePreferences(
          appTheme: appTheme,
          widgetTheme: widgetTheme,
          workspace: workspace,
        );
        await _appearanceStore.write(next.toJson());
        _appearance = next;
        _appearanceError = null;
      });
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
    if (busy) {
      return false;
    }
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

  Future<bool> saveHabit(HabitDraft draft, {String? id}) =>
      _edit(() => engine.saveHabit(draft, id: id));
  Future<bool> deleteHabit(String id) => _edit(() => engine.deleteHabit(id));
  Future<bool> setHabitValue(String habitId, String date, int value) =>
      _edit(() => engine.setHabitValue(habitId, date, value));
  Future<bool> resolvePersonalConflict(
    String kind,
    String id, {
    required bool keepLocal,
  }) => _edit(
    () => engine.resolvePersonalConflict(kind, id, keepLocal: keepLocal),
  );

  Future<bool> setCompleted(String id, bool completed) async {
    return _edit(() async {
      final change = await engine.setCompleted(id, completed);
      if (!completed || _disposed) {
        return;
      }
      final celebration = celebrationForCompletion(change, _clock());
      if (celebration != null) {
        await _queueCelebration(celebration);
      }
    });
  }

  Future<void> _loadCelebration() => _loadingCelebration ??= () async {
    try {
      final saved = await _celebrationStore.read();
      if (_disposed) {
        return;
      }
      final days = saved?['celebrated_days'];
      if (days is List) {
        _celebratedDays.addAll(days.whereType<String>());
      }
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
      if (!_disposed) {
        _pendingCelebration = celebration;
      }
    } catch (_) {
      // Task completion was already durably saved; don't report it as failed.
    }
  }

  /// Clear the durable pending event before presentation, including startup
  /// actions queued by Android widgets before the main screen exists.
  Future<DailyCelebration?> takeDailyCelebration() async {
    await _loadCelebration();
    if (_disposed || _claimingCelebration || _pendingCelebration == null) {
      return null;
    }
    _claimingCelebration = true;
    final pending = _pendingCelebration!;
    try {
      await _writeCelebration(null);
      if (identical(_pendingCelebration, pending)) {
        _pendingCelebration = null;
      }
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
      if (identical(_pendingCelebration, pending)) {
        _pendingCelebration = null;
      }
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

  Future<bool> deleteList(String name) => _edit(() => engine.deleteList(name));

  Future<bool> resolveConflict(String id, {required bool keepLocal}) async {
    return _edit(() => engine.resolveConflict(id, keepLocal: keepLocal));
  }

  Future<bool> _edit(Future<void> Function() operation) async {
    if (_disposed || _editing) {
      return false;
    }
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
    if (_disposed || !isConfigured) {
      return;
    }
    _editTimer = Timer(const Duration(milliseconds: 700), () {
      if (isConfigured && !busy) {
        unawaited(sync());
      }
    });
  }

  Future<void> sync() async {
    if (_disposed || busy || updates?.active == true) {
      return;
    }
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
    if (pending != null) {
      await pending;
    }
  }

  void onResume() {
    setUpdatesForeground(true);
    unawaited(updates?.resume() ?? Future.value());
    _notify();
    if (isConfigured && !busy) {
      unawaited(sync());
    }
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
    if (_token.isNotEmpty) {
      message = message.replaceAll(_token, '••••••');
    }
    return message.replaceFirst(RegExp(r'^\w*Exception:\s*'), '');
  }

  void _notify() {
    _updatePolicy();
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _periodicTimer?.cancel();
    _editTimer?.cancel();
    updates?.removeListener(_notify);
    updates?.dispose();
    _transport.dispose();
    super.dispose();
  }
}
