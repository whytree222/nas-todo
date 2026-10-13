import 'dart:convert';
import 'dart:io';
import 'sync_core.dart';
import 'achievement_core.dart';

class FileDataStore implements DataStore {
  final File file;
  bool _primaryIsValid = false;
  FileDataStore(this.file);
  File get _backup => File('${file.path}.bak');

  @override
  Future<Map<String, dynamic>?> read() async {
    // Never silently replace a damaged file with an empty task list.
    Object? originalError;
    for (final candidate in [file, _backup]) {
      if (!await candidate.exists()) continue;
      try {
        final state = Map<String, dynamic>.from(jsonDecode(await candidate.readAsString()) as Map);
        if (state['schema'] != 1 || state['tasks'] is! List ||
            state['operations'] is! List || state['conflicts'] is! List ||
            state['cursor'] is! int) {
          throw const FormatException('Invalid local state');
        }
        for (final raw in state['tasks'] as List) {
          Task.fromJson(Map<String, dynamic>.from(raw as Map));
        }
        for (final raw in state['conflicts'] as List) {
          SyncConflict.fromJson(Map<String, dynamic>.from(raw as Map));
        }
        if (state['achievement'] != null) AchievementState.fromJson(Map<String, dynamic>.from(state['achievement'] as Map));
        _primaryIsValid = candidate.path == file.path;
        return state;
      } catch (error) {
        originalError ??= error;
      }
    }
    if (originalError != null) throw StateError('本地数据读取失败，请保留数据文件并恢复备份：$originalError');
    return null;
  }

  @override
  Future<void> write(Map<String, dynamic> state) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(state), flush: true);
    if (_primaryIsValid && await file.exists()) await file.copy(_backup.path);
    await temp.rename(file.path);
    _primaryIsValid = true;
  }
}

class HttpSyncTransport implements SyncTransport {
  String _baseUrl;
  String _token;
  final HttpClient _client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  HttpSyncTransport(String baseUrl, String token) : _baseUrl = baseUrl, _token = token;

  void configure(String baseUrl, String token) {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null || !['http', 'https'].contains(uri.scheme) || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw ArgumentError('请输入完整的 NAS 地址，如 http://192.168.1.10:8787');
    }
    if (token.trim().length < 32) throw ArgumentError('同步密钥至少需要 32 个字符');
    _baseUrl = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    _token = token.trim();
  }

  @override
  Future<Map<String, dynamic>> sync(Map<String, dynamic> payload) async {
    if (_baseUrl.isEmpty || _token.isEmpty) throw StateError('请先设置 NAS 地址和同步密钥');
    return _send(payload).timeout(const Duration(seconds: 15), onTimeout: () {
      throw const SocketException('NAS 连接超时，本地修改已保留');
    });
  }

  Future<Map<String, dynamic>> _send(Map<String, dynamic> payload) async {
    final request = await _client.postUrl(Uri.parse('$_baseUrl/api/sync'));
    // Credentials must never follow a redirect to a different host.
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
    final encoded = utf8.encode(jsonEncode(payload));
    request.contentLength = encoded.length;
    request.add(encoded);
    final response = await request.close();
    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > 32 * 1024 * 1024) {
        throw StateError('NAS 响应过大，请检查服务配置');
      }
      bytes.addAll(chunk);
    }
    Map<String, dynamic> body;
    try { body = Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map); }
    catch (_) { throw StateError('NAS 返回的不是待办服务数据，请检查地址和端口'); }
    if (response.statusCode != HttpStatus.ok) {
      final code = body['error'] as String? ?? 'http_${response.statusCode}';
      final message = switch (code) {
        'unauthorized' => '同步密钥不正确，请检查 NAS 设置',
        'instance_mismatch' => 'NAS 数据库与已绑定的数据库不同，请检查服务地址；本地修改已保留',
        'future_cursor' => 'NAS 已恢复到较早的备份，正在重新读取数据',
        _ => body['message'] as String? ?? '同步失败（${response.statusCode}），本地修改已保留',
      };
      throw SyncServerException(code, message);
    }
    return body;
  }

  void dispose() => _client.close(force: true);
}
