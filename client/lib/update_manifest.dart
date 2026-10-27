import 'dart:convert';

const updateGithubRepository = 'whytree222/nas-todo';
const updateGiteeRepository = String.fromEnvironment('UPDATE_GITEE_REPOSITORY');
const updateGithubManifest =
    'https://github.com/$updateGithubRepository/releases/latest/download/';

class UpdateFailure implements Exception {
  const UpdateFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class UpdateUrls {
  const UpdateUrls({this.giteeRepository = updateGiteeRepository});
  final String giteeRepository;
  static final _repo = RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$');
  List<Uri> manifests(String platform) => [
    if (_repo.hasMatch(giteeRepository))
      Uri.https(
        'gitee.com',
        '/$giteeRepository/raw/master/${platform == 'android' ? 'update.json' : 'update-windows.json'}',
      ),
    Uri.parse(
      '$updateGithubManifest${platform == 'android' ? 'update.json' : 'update-windows.json'}',
    ),
  ];

  bool _base(Uri u) =>
      u.scheme == 'https' &&
      (u.port == 443) &&
      u.userInfo.isEmpty &&
      u.fragment.isEmpty &&
      !u.pathSegments.any((s) => s == '..' || s == '.' || s.contains('\\')) &&
      !u.path.contains('%');
  bool initial(
    Uri u, {
    required String kind,
    required String platform,
    bool cacheQuery = false,
  }) {
    if (!_base(u) || (!cacheQuery && u.hasQuery)) return false;
    if (cacheQuery &&
        u.hasQuery &&
        (u.queryParameters.length != 1 ||
            !RegExp(r'^\d+$').hasMatch(u.queryParameters['t'] ?? '')))
      return false;
    final repo = u.host == 'github.com'
        ? updateGithubRepository
        : u.host == 'gitee.com' && _repo.hasMatch(giteeRepository)
        ? giteeRepository
        : null;
    if (repo == null) return false;
    final prefix = '/$repo/';
    if (kind == 'manifest')
      return u.path ==
              '${prefix}releases/latest/download/${platform == 'android' ? 'update.json' : 'update-windows.json'}' ||
          (u.host == 'gitee.com' &&
              u.path ==
                  '${prefix}raw/master/${platform == 'android' ? 'update.json' : 'update-windows.json'}');
    if (kind == 'page')
      return RegExp(
        '^${RegExp.escape(prefix)}releases/tag/v[0-9]+\\.[0-9]+\\.[0-9]+\$',
      ).hasMatch(u.path);
    final suffix = platform == 'android' ? 'apk' : 'zip';
    return RegExp(
      '^${RegExp.escape(prefix)}releases/download/v[0-9]+\\.[0-9]+\\.[0-9]+/nas-todo-[A-Za-z0-9_.-]+\\.$suffix\$',
    ).hasMatch(u.path);
  }

  bool redirect(Uri u, {required String kind, required String platform}) {
    if (!_base(u)) return false;
    if (kind == 'manifest' &&
        u.host == 'github.com' &&
        !u.hasQuery &&
        RegExp(
          '^/${RegExp.escape(updateGithubRepository)}/releases/download/v[0-9]+\\.[0-9]+\\.[0-9]+/update(-windows)?\\.json\$',
        ).hasMatch(u.path))
      return true;
    if (u.host == 'github.com' || u.host == 'gitee.com')
      return initial(
        u,
        kind: kind,
        platform: platform,
        cacheQuery: kind == 'manifest',
      );
    return const {
      'release-assets.githubusercontent.com',
      'objects.githubusercontent.com',
      'raw.giteeusercontent.com',
      'foruda.gitee.com',
    }.contains(u.host);
  }
}

class UpdateManifest {
  const UpdateManifest({
    required this.versionCode,
    required this.versionName,
    required this.minSupportedVersionCode,
    required this.publishedAt,
    required this.urls,
    required this.sha256,
    required this.size,
    required this.notes,
    required this.pageUrl,
    required this.platform,
  });
  final int versionCode, minSupportedVersionCode, size;
  final String versionName, publishedAt, sha256, notes, platform;
  final List<Uri> urls;
  final Uri pageUrl;
  factory UpdateManifest.parse(
    String raw, {
    required String platform,
    UpdateUrls policy = const UpdateUrls(),
  }) {
    try {
      if (!const {'android', 'windows'}.contains(platform) ||
          utf8.encode(raw).length > 65536)
        throw const FormatException();
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          value['schema'] is! int ||
          value['schema'] != 1)
        throw const FormatException();
      final code = value['versionCode'];
      final name = value['versionName'];
      final minimum = value['minSupportedVersionCode'] ?? code;
      final time = value['publishedAt'];
      final hash = value['sha256'];
      final size = value['size'];
      final notes = value['notes'];
      final urls = value[platform == 'android' ? 'apkUrls' : 'zipUrls'];
      if (code is! int ||
          code < 1 ||
          code > 2100000000 ||
          minimum is! int ||
          minimum < 1 ||
          minimum > code ||
          name is! String ||
          !RegExp(r'^\d{1,4}\.\d{1,4}\.\d{1,4}$').hasMatch(name) ||
          time is! String ||
          time.isEmpty ||
          time.length > 40 ||
          DateTime.tryParse(time) == null ||
          hash is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
          size is! int ||
          size < 1 ||
          size > 100 * 1024 * 1024 ||
          notes is! String ||
          notes.length > 8000 ||
          urls is! List ||
          urls.isEmpty ||
          urls.length > 4 ||
          urls.any((u) => u is! String))
        throw const FormatException();
      final parsed = urls.cast<String>().map(Uri.parse).toList();
      final page = Uri.parse(value['pageUrl'] as String);
      if (parsed.any(
            (u) => !policy.initial(u, kind: 'package', platform: platform),
          ) ||
          !policy.initial(page, kind: 'page', platform: platform))
        throw const FormatException();
      // A manifest cannot mix the version being advertised with another tag.
      if (parsed.any((u) => !u.path.contains('/download/v$name/')) ||
          !page.path.endsWith('/v$name'))
        throw const FormatException();
      return UpdateManifest(
        versionCode: code,
        versionName: name,
        minSupportedVersionCode: minimum,
        publishedAt: time,
        urls: List.unmodifiable(parsed),
        sha256: hash,
        size: size,
        notes: notes.replaceAll('\r\n', '\n'),
        pageUrl: page,
        platform: platform,
      );
    } catch (_) {
      throw const UpdateFailure('更新信息无效，请稍后重试');
    }
  }
  Map<String, dynamic> toJson() => {
    'schema': 1,
    'versionCode': versionCode,
    'versionName': versionName,
    'minSupportedVersionCode': minSupportedVersionCode,
    'publishedAt': publishedAt,
    platform == 'android' ? 'apkUrls' : 'zipUrls': urls
        .map((u) => u.toString())
        .toList(),
    'sha256': sha256,
    'size': size,
    'notes': notes,
    'pageUrl': pageUrl.toString(),
  };
}
