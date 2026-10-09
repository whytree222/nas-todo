import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'storage_io.dart';
import 'sync_core.dart';

/// Keeps local edits available even when the NAS cannot be reached.
class AppController extends ChangeNotifier {
  AppController._(this.engine, this._transport, this._configFile, this._vault);

  @visibleForTesting
  factory AppController.forTesting(SyncEngine engine) => AppController._(
        engine,
        HttpSyncTransport('', ''),
        File('unused-test-config.json'),
        const FlutterSecureStorage(),
      );

  final SyncEngine engine;
  final HttpSyncTransport _transport;
  final File _configFile;
  final FlutterSecureStorage _vault;
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
      SyncEngine(FileDataStore(File('${directory.path}/tasks.json')), transport),
      transport,
      File('${directory.path}/config.json'),
      const FlutterSecureStorage(),
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

  Future<void> _initialize() async {
    // Stop startup on corrupt storage, preserving the original data files.
    await engine.load();
    try {
      if (await _configFile.exists()) {
        final config = jsonDecode(await _configFile.readAsString())
            as Map<String, dynamic>;
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
    return _edit(() => engine.setCompleted(id, completed));
  }

  Future<bool> deleteTask(String id) async {
    return _edit(() => engine.deleteTask(id));
  }

  Future<bool> resolveConflict(String id, {required bool keepLocal}) async {
    return _edit(() => engine.resolveConflict(id, keepLocal: keepLocal));
  }

  Future<bool> _edit(Future<void> Function() operation) async {
    if (_editing) return false;
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
    if (isConfigured && !busy) unawaited(sync());
  }

  void clearError() {
    _error = null;
    _notify();
  }

  void _setError(Object error) {
    var message = error.toString();
    if (_token.isNotEmpty) message = message.replaceAll(_token, '••••••');
    _error = message.replaceFirst(RegExp(r'^\w*Exception:\s*'), '');
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
