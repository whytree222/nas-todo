import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'update_manifest.dart';
import 'update_windows.dart';

class UpdateIdentity {
  const UpdateIdentity({
    required this.platform,
    required this.versionName,
    required this.versionCode,
    required this.directory,
    this.enabled = true,
  });
  final String platform, versionName;
  final int versionCode;
  final Directory directory;
  final bool enabled;
}

abstract interface class UpdateNative {
  Future<UpdateIdentity> identity();
  Future<int> freeSpace();
  Future<void> verify(File package, UpdateManifest manifest);

  /// permission: Android unknown-sources screen was opened; started: installing.
  Future<String> install(File package, UpdateManifest manifest);
  Future<void> openPage(Uri uri);
}

class NativeUpdates implements UpdateNative {
  static const _channel = MethodChannel('cn.privatetodo/updates');
  @override
  Future<UpdateIdentity> identity() async {
    final info = await _channel.invokeMapMethod<String, dynamic>('identity');
    if (info == null) throw const UpdateFailure('当前平台暂不支持更新');
    return UpdateIdentity(
      platform: info['platform'] as String,
      versionName: info['versionName'] as String,
      versionCode: info['versionCode'] as int,
      directory: Directory(info['directory'] as String),
      enabled: info['enabled'] == true,
    );
  }

  @override
  Future<int> freeSpace() async =>
      await _channel.invokeMethod<int>('freeSpace') ?? 0;
  Map<String, dynamic> _arguments(File file, UpdateManifest m) => {
    'path': file.absolute.path,
    'versionName': m.versionName,
    'versionCode': m.versionCode,
    'size': m.size,
    'sha256': m.sha256,
  };
  Future<T?> _call<T>(String method, Map<String, dynamic> arguments) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw UpdateFailure(switch (e.code) {
        'signature' => '安装包签名与当前应用不同，无法覆盖更新。请先同步并备份数据，再查看发布说明。',
        'identity' => '安装包的应用标识或版本不符',
        'hash' => 'SHA-256 校验失败，安装包已拒绝',
        'space' => '存储空间不足',
        'installer' => '未找到系统安装器，请打开发布页安装',
        'busy' => '请先结束正在进行的操作，再更新',
        _ => '无法准备更新，请重试或打开发布页',
      });
    }
  }

  @override
  Future<void> verify(File package, UpdateManifest manifest) async {
    if (Platform.isWindows) {
      await prepareWindowsBundle(package, manifest);
    }
    await _call<void>('verify', _arguments(package, manifest));
  }

  @override
  Future<String> install(File package, UpdateManifest manifest) async =>
      await _call<String>('install', _arguments(package, manifest)) ??
      'started';
  @override
  Future<void> openPage(Uri uri) async =>
      _call<void>('openPage', {'url': uri.toString()});
}

abstract interface class UpdateNetwork {
  Future<String> manifest(Uri uri, String platform);
  Future<void> download(
    Uri uri,
    File target,
    UpdateManifest manifest,
    void Function(int) progress,
  );
  void cancel();
}

class HttpUpdates implements UpdateNetwork {
  HttpUpdates({
    this.policy = const UpdateUrls(),
    HttpClient Function()? factory,
  }) : _factory = factory ?? HttpClient.new;
  final UpdateUrls policy;
  final HttpClient Function() _factory;
  final _clients = <HttpClient>{};
  int _epoch = 0;
  Future<HttpClientResponse> _get(
    HttpClient client,
    Uri uri,
    String kind,
    String platform,
    int epoch,
  ) async {
    if (!policy.initial(
      uri,
      kind: kind,
      platform: platform,
      cacheQuery: kind == 'manifest',
    ))
      throw const UpdateFailure('更新地址不受信任');
    for (var redirect = 0; redirect <= 5; redirect++) {
      if (epoch != _epoch) throw const UpdateFailure('更新已取消');
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 10));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'NAS-Todo-Updater');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (const [301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (redirect == 5 || location == null)
          throw const UpdateFailure('更新下载重定向无效');
        final next = uri.resolve(location);
        if (!policy.redirect(next, kind: kind, platform: platform))
          throw const UpdateFailure('更新下载地址不受信任');
        // Close this response without reading an unbounded redirect body.
        await response.listen((_) {}).cancel();
        uri = next;
        continue;
      }
      if (response.statusCode != 200)
        throw const UpdateFailure('暂时无法获取更新，请稍后重试');
      return response;
    }
    throw const UpdateFailure('更新下载重定向过多');
  }

  @override
  Future<String> manifest(Uri uri, String platform) async {
    final client = _factory()..connectionTimeout = const Duration(seconds: 10);
    _clients.add(client);
    final epoch = _epoch;
    try {
      final response = await _get(client, uri, 'manifest', platform, epoch);
      if (response.contentLength > 65536) throw const UpdateFailure('更新信息过大');
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        if (epoch != _epoch) throw const UpdateFailure('更新已取消');
        if (bytes.length + chunk.length > 65536)
          throw const UpdateFailure('更新信息过大');
        bytes.addAll(chunk);
      }
      return utf8.decode(bytes);
    } on UpdateFailure {
      rethrow;
    } on TimeoutException {
      throw const UpdateFailure('连接更新服务超时，请重试');
    } catch (_) {
      throw const UpdateFailure('无法连接更新服务，请检查网络');
    } finally {
      _clients.remove(client);
      client.close(force: true);
    }
  }

  @override
  Future<void> download(
    Uri uri,
    File target,
    UpdateManifest manifest,
    void Function(int) progress,
  ) async {
    final client = _factory()..connectionTimeout = const Duration(seconds: 10);
    _clients.add(client);
    final epoch = _epoch;
    IOSink? file;
    try {
      final response = await _get(
        client,
        uri,
        'package',
        manifest.platform,
        epoch,
      );
      if (response.contentLength >= 0 &&
          response.contentLength != manifest.size)
        throw const UpdateFailure('安装包大小与更新信息不符');
      file = target.openWrite();
      final result = _DigestSink();
      final digest = sha256.startChunkedConversion(result);
      var written = 0, lastProgress = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        if (epoch != _epoch) throw const UpdateFailure('更新已取消');
        written += chunk.length;
        if (written > manifest.size) throw const UpdateFailure('安装包超过预期大小');
        file.add(chunk);
        digest.add(chunk);
        if (written - lastProgress >= 512 * 1024) {
          // Bound the IO queue as well as the amount of UI traffic.
          await file.flush();
          progress(written);
          lastProgress = written;
        }
      }
      digest.close();
      await file.flush();
      if (epoch != _epoch) throw const UpdateFailure('更新已取消');
      if (written != manifest.size) throw const UpdateFailure('安装包下载不完整');
      if (result.value.toString() != manifest.sha256)
        throw const UpdateFailure('SHA-256 校验失败，请重新下载');
      progress(written);
    } on UpdateFailure {
      rethrow;
    } on TimeoutException {
      throw const UpdateFailure('下载超时，请重试');
    } on FileSystemException {
      throw const UpdateFailure('无法写入安装包，请检查存储空间');
    } catch (_) {
      throw const UpdateFailure('下载中断，请检查网络后重试');
    } finally {
      await file?.close();
      _clients.remove(client);
      client.close(force: true);
    }
  }

  @override
  void cancel() {
    _epoch++;
    for (final client in _clients.toList()) {
      client.close(force: true);
    }
    _clients.clear();
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
