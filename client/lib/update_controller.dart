import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'update_io.dart';
import 'update_manifest.dart';

enum UpdateStatus {
  unavailable,
  idle,
  checking,
  upToDate,
  available,
  downloading,
  ready,
  failed,
}

class UpdateController extends ChangeNotifier {
  UpdateController({
    required this.native,
    required this.network,
    required this.info,
    required this.preferences,
    this.policy = const UpdateUrls(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;
  final UpdateNative native;
  final UpdateNetwork network;
  final UpdateIdentity info;
  final File preferences;
  final UpdateUrls policy;
  final DateTime Function() _clock;
  UpdateStatus status = UpdateStatus.idle;
  UpdateManifest? manifest;
  String? message;
  int downloaded = 0;
  bool _allowed = true, _disposed = false;
  bool _downloadPending = false;
  bool _notificationQueued = false;
  int _generation = 0;
  Map<String, dynamic> _prefs = {};
  Future<void> _writes = Future.value();
  bool get allowed => _allowed;
  bool get active =>
      status == UpdateStatus.checking || status == UpdateStatus.downloading;
  bool get _snoozed =>
      manifest != null &&
      _prefs['snoozeCode'] == manifest!.versionCode &&
      _prefs['snoozeUntil'] is int &&
      (_prefs['snoozeUntil'] as int) > _clock().millisecondsSinceEpoch;
  bool get hasUpdate =>
      !_snoozed &&
      const {
        UpdateStatus.available,
        UpdateStatus.downloading,
        UpdateStatus.ready,
      }.contains(status);
  bool get requiredUpdate =>
      (manifest?.minSupportedVersionCode ?? 0) > info.versionCode;
  File get _package => File(
    '${info.directory.path}/nas-todo-${manifest!.versionName}.${info.platform == 'android' ? 'apk' : 'zip'}',
  );

  static Future<UpdateController?> create() async {
    if (!Platform.isAndroid && !Platform.isWindows) return null;
    try {
      final native = NativeUpdates();
      final info = await native.identity();
      final updates = UpdateController(
        native: native,
        network: HttpUpdates(),
        info: info,
        preferences: File('${info.directory.parent.path}/update-state.json'),
      );
      await updates.initialize();
      return updates;
    } catch (_) {
      return null;
    }
  }

  Future<void> initialize() async {
    await info.directory.create(recursive: true);
    try {
      _prefs = Map<String, dynamic>.from(
        jsonDecode(await preferences.readAsString()) as Map,
      );
    } catch (_) {
      _prefs = {};
    }
    if (!info.enabled) {
      status = UpdateStatus.unavailable;
      return;
    }
    final ready = _prefs['ready'];
    if (ready is Map) {
      try {
        final candidate = UpdateManifest.parse(
          jsonEncode(ready),
          platform: info.platform,
          policy: policy,
        );
        manifest = candidate;
        if (candidate.versionCode <= info.versionCode ||
            !await _package.exists() ||
            await _package.length() != candidate.size)
          throw const FormatException();
        await native.verify(_package, candidate);
        status = UpdateStatus.ready;
      } catch (_) {
        manifest = null;
        _prefs.remove('ready');
      }
    }
    await _cleanup();
  }

  Future<void> _cleanup() async {
    // Only direct package/partial files in the app-owned update directory.
    await for (final entry in info.directory.list(followLinks: false)) {
      if (entry is! File ||
          !RegExp(r'^nas-todo-\d+\.\d+\.\d+\.(apk|zip)(\.part)?$')
              .hasMatch(entry.uri.pathSegments.last))
        continue;
      if (status == UpdateStatus.ready &&
          manifest != null &&
          entry.path == _package.path)
        continue;
      try {
        await entry.delete();
      } catch (_) {
        /* A system installer may still hold a file. */
      }
    }
  }

  void setAllowed(bool allowed) {
    if (_allowed == allowed || _disposed) return;
    _allowed = allowed;
    if (!allowed && active) cancel();
    _notify();
  }

  Future<void> resume() async {
    if (!info.enabled || _disposed) return;
    if (!active) await _cleanup();
    _notify();
    await check(automatic: true);
  }

  Future<void> check({bool automatic = false}) async {
    if (!info.enabled ||
        !_allowed ||
        active ||
        status == UpdateStatus.ready ||
        _disposed)
      return;
    final now = _clock().millisecondsSinceEpoch;
    bool recent(String field, Duration period) {
      final value = _prefs[field];
      return value is int &&
          now - value >= 0 &&
          now - value < period.inMilliseconds;
    }

    if (automatic &&
        (recent('success', const Duration(hours: 24)) ||
            recent('failure', const Duration(hours: 1))))
      return;
    final generation = ++_generation;
    status = UpdateStatus.checking;
    message = null;
    _notify();
    try {
      UpdateManifest? found;
      for (final url in policy.manifests(info.platform)) {
        try {
          final raw = await network.manifest(
            url.replace(queryParameters: {'t': '$now'}),
            info.platform,
          );
          if (!_current(generation)) return;
          found = UpdateManifest.parse(
            raw,
            platform: info.platform,
            policy: policy,
          );
          break;
        } catch (_) {
          if (!_current(generation)) return;
        }
      }
      if (found == null) throw const UpdateFailure('无法获取有效的更新信息，请检查网络后重试');
      _prefs['success'] = now;
      _prefs.remove('failure');
      manifest = found.versionCode > info.versionCode ? found : null;
      status = manifest == null
          ? UpdateStatus.upToDate
          : UpdateStatus.available;
      await _persist();
    } catch (e) {
      if (!_current(generation)) return;
      _prefs['failure'] = now;
      status = UpdateStatus.failed;
      message = _message(e);
      await _persist();
    } finally {
      if (_current(generation)) _notify();
    }
  }

  Future<void> download() async {
    final candidate = manifest;
    if (!_allowed ||
        candidate == null ||
        active ||
        _downloadPending ||
        status == UpdateStatus.ready ||
        _disposed)
      return;
    _downloadPending = true;
    final generation = ++_generation;
    status = UpdateStatus.downloading;
    downloaded = 0;
    message = null;
    _notify();
    final target = _package, partial = File('${_package.path}.part');
    try {
      if (await native.freeSpace() <
          (candidate.size * (info.platform == 'windows' ? 8 : 1.2)).ceil())
        throw const UpdateFailure('存储空间不足');
      if (!_current(generation)) return;
      var done = false;
      Object? failure;
      for (final url in candidate.urls) {
        try {
          await network.download(url, partial, candidate, (size) {
            if (_current(generation)) {
              downloaded = size;
              _notify();
            }
          });
          if (!_current(generation)) return;
          await partial.rename(target.path);
          await native.verify(target, candidate);
          if (!_current(generation)) return;
          done = true;
          break;
        } catch (e) {
          failure = e;
          for (final file in [partial, target]) {
            if (await file.exists()) await file.delete();
          }
          if (!_current(generation)) return;
        }
      }
      if (!done) throw failure ?? const UpdateFailure('下载失败，请重试');
      status = UpdateStatus.ready;
      downloaded = candidate.size;
      _prefs['ready'] = candidate.toJson();
      await _persist();
    } catch (e) {
      if (_current(generation)) {
        status = UpdateStatus.failed;
        message = _message(e);
      }
    } finally {
      if (await partial.exists()) await partial.delete();
      if (!_current(generation) && await target.exists()) await target.delete();
      _downloadPending = false;
      if (_current(generation)) _notify();
    }
  }

  Future<void> install() async {
    if (!_allowed ||
        status != UpdateStatus.ready ||
        manifest == null ||
        _disposed)
      return;
    try {
      // Recheck file size, hash and platform identity immediately before install.
      await native.verify(_package, manifest!);
    } catch (e) {
      if (await _package.exists()) await _package.delete();
      _prefs.remove('ready');
      await _persist();
      status = UpdateStatus.failed;
      message = _message(e);
      _notify();
      return;
    }
    try {
      if (!_allowed || _disposed) return;
      final result = await native.install(_package, manifest!);
      message = result == 'permission'
          ? '请允许此应用安装更新，返回后再点“安装更新”。'
          : info.platform == 'android'
          ? '请在系统安装器中确认覆盖安装。'
          : '正在退出主程序和组件并更新，完成后自动启动。';
    } catch (e) {
      message = _message(e);
    }
    _notify();
  }

  Future<void> later() async {
    if (active || manifest == null) return;
    _prefs['snoozeCode'] = manifest!.versionCode;
    _prefs['snoozeUntil'] = _clock()
        .add(const Duration(hours: 24))
        .millisecondsSinceEpoch;
    message = '已延后 24 小时提醒，仍可在设置中手动更新。';
    await _persist();
    _notify();
  }

  Future<void> openPage() async {
    final url = manifest?.pageUrl;
    if (url == null ||
        !policy.initial(url, kind: 'page', platform: info.platform))
      return;
    try {
      await native.openPage(url);
    } catch (_) {
      message = '无法打开发布页，请稍后重试';
      _notify();
    }
  }

  void cancel() {
    ++_generation;
    network.cancel();
    status = manifest == null ? UpdateStatus.idle : UpdateStatus.available;
    message = null;
    downloaded = 0;
    _notify();
  }

  bool _current(int generation) =>
      !_disposed && _allowed && generation == _generation;
  String _message(Object error) =>
      error is UpdateFailure ? error.message : '更新未完成，请重试';
  Future<void> _persist() {
    final raw = jsonEncode(_prefs);
    return _writes = _writes.catchError((Object _) {}).then((_) async {
      try {
        final temporary = File('${preferences.path}.tmp');
        await temporary.writeAsString(raw, flush: true);
        await temporary.rename(preferences.path);
      } catch (_) {
        /* Update preferences must never prevent using the todo app. */
      }
    });
  }

  void _notify() {
    if (_disposed) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_notificationQueued) return;
      _notificationQueued = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _notificationQueued = false;
        if (!_disposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    network.cancel();
    super.dispose();
  }
}
