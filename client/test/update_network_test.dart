import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_todo/update_io.dart';
import 'package:nas_todo/update_manifest.dart';

class _Headers extends Fake implements HttpHeaders {
  final Map<String, String> values = {};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = '$value';
  }

  @override
  String? value(String name) => values[name];
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.bytes, {this.statusCode = 200, int? length, String? location})
    : contentLength = length ?? bytes.length {
    if (location != null) headers.values[HttpHeaders.locationHeader] = location;
  }
  final List<int> bytes;
  @override
  final int statusCode;
  @override
  final int contentLength;
  @override
  final _Headers headers = _Headers();
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request extends Fake implements HttpClientRequest {
  _Request(this.response);
  final _Response response;
  @override
  final _Headers headers = _Headers();
  @override
  bool followRedirects = true;
  @override
  Future<HttpClientResponse> close() async => response;
}

class _Client extends Fake implements HttpClient {
  _Client(this.responses);
  final List<_Response> responses;
  final List<Uri> requested = [];
  final List<_Request> requests = [];
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requested.add(url);
    final request = _Request(responses.removeAt(0));
    requests.add(request);
    return request;
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final url = Uri.parse(
    'https://github.com/whytree222/nas-todo/releases/download/v0.13.1/nas-todo-android-v0.13.1.apk',
  );
  final manifest = UpdateManifest.parse(
    jsonEncode({
      'schema': 1,
      'versionCode': 18,
      'versionName': '0.13.1',
      'publishedAt': '2026-10-27T00:00:00Z',
      'apkUrls': [url.toString()],
      'sha256': sha256.convert([1, 2, 3]).toString(),
      'size': 3,
      'notes': '',
      'pageUrl': 'https://github.com/whytree222/nas-todo/releases/tag/v0.13.1',
    }),
    platform: 'android',
  );
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'nas-todo-update-network-test-',
    );
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  test(
    'Streaming download validates exact size and SHA-256 and omits credentials',
    () async {
      final client = _Client([
        _Response([1, 2, 3]),
      ]);
      final network = HttpUpdates(factory: () => client);
      final target = File('${directory.path}/package.part');
      var progress = 0;
      await network.download(url, target, manifest, (n) => progress = n);
      expect(await target.readAsBytes(), [1, 2, 3]);
      expect(progress, 3);
      expect(client.requests.single.followRedirects, isFalse);
      expect(
        client.requests.single.headers.values.containsKey(
          HttpHeaders.authorizationHeader,
        ),
        isFalse,
      );
    },
  );
  for (final entry in <String, _Response>{
    'declared size': _Response([1, 2, 3], length: 9),
    'actual oversized': _Response([1, 2, 3, 4], length: -1),
    'actual incomplete': _Response([1], length: -1),
    'tampered hash': _Response([3, 2, 1]),
  }.entries) {
    test('Rejects ${entry.key}', () async {
      final network = HttpUpdates(factory: () => _Client([entry.value]));
      await expectLater(
        network.download(
          url,
          File('${directory.path}/package.part'),
          manifest,
          (_) {},
        ),
        throwsA(isA<UpdateFailure>()),
      );
    });
  }
  test(
    'A malicious redirect is rejected without requesting its target',
    () async {
      final client = _Client([
        _Response(
          [],
          statusCode: 302,
          location: 'https://evil.example/steal?token=hidden',
        ),
      ]);
      await expectLater(
        HttpUpdates(factory: () => client).download(
          url,
          File('${directory.path}/package.part'),
          manifest,
          (_) {},
        ),
        throwsA(isA<UpdateFailure>()),
      );
      expect(client.requested.length, 1);
    },
  );
  test('Latest manifest can follow GitHub version redirect then signed asset redirect', () async {
    final client = _Client([
      _Response(
        [],
        statusCode: 302,
        location: 'https://github.com/whytree222/nas-todo/releases/download/v0.13.1/update.json',
      ),
      _Response(
        [],
        statusCode: 302,
        location: 'https://release-assets.githubusercontent.com/assets/file?sig=example',
      ),
      _Response(utf8.encode('{}')),
    ]);
    expect(
      await HttpUpdates(factory: () => client).manifest(
        Uri.parse('${updateGithubManifest}update.json?t=123'),
        'android',
      ),
      '{}',
    );
    expect(client.requested.length, 3);
  });
  test('Redirect loops stop after five transitions and oversized manifests are refused', () async {
    final client = _Client(
      List.generate(
        6,
        (_) => _Response(
          [],
          statusCode: 302,
          location: 'https://release-assets.githubusercontent.com/assets/file',
        ),
      ),
    );
    await expectLater(
      HttpUpdates(
        factory: () => client,
      ).download(url, File('${directory.path}/package.part'), manifest, (_) {}),
      throwsA(isA<UpdateFailure>()),
    );
    expect(client.requested.length, 6);
    await expectLater(
      HttpUpdates(factory: () => _Client([_Response(List.filled(65537, 32))]))
          .manifest(Uri.parse('${updateGithubManifest}update.json'), 'android'),
      throwsA(isA<UpdateFailure>()),
    );
  });
}
