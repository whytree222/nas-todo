import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_todo/update_controller.dart';
import 'package:nas_todo/update_io.dart';
import 'package:nas_todo/update_manifest.dart';
import 'package:nas_todo/update_windows.dart';
import 'package:nas_todo/ui/update_card.dart';

Map<String, dynamic> _json({String platform = 'android'}) => {
  'schema': 1,
  'versionCode': 18,
  'versionName': '0.13.1',
  'minSupportedVersionCode': 17,
  'publishedAt': '2026-10-27T00:00:00Z',
  platform == 'android' ? 'apkUrls' : 'zipUrls': [
    'https://github.com/whytree222/nas-todo/releases/download/v0.13.1/nas-todo-${platform == 'android' ? 'android-v0.13.1.apk' : 'windows-v0.13.1-x64.zip'}',
  ],
  'sha256': sha256.convert([1, 2, 3]).toString(),
  'size': 3,
  'notes': '更新说明\r\n第二行',
  'pageUrl': 'https://github.com/whytree222/nas-todo/releases/tag/v0.13.1',
};

class _Native implements UpdateNative {
  _Native(this.info);
  final UpdateIdentity info;
  bool reject = false;
  int installs = 0, verifies = 0;
  int space = 10000000;
  String installResult = 'started';
  @override
  Future<UpdateIdentity> identity() async => info;
  @override
  Future<int> freeSpace() async => space;
  @override
  Future<void> verify(File file, UpdateManifest manifest) async {
    verifies++;
    if (reject) throw const UpdateFailure('签名不符');
    if (await file.length() != manifest.size ||
        (await sha256.bind(file.openRead()).first).toString() !=
            manifest.sha256)
      throw const UpdateFailure('哈希不符');
  }

  @override
  Future<String> install(File file, UpdateManifest manifest) async {
    installs++;
    return installResult;
  }

  @override
  Future<void> openPage(Uri uri) async {}
}

class _Network implements UpdateNetwork {
  int checks = 0, downloads = 0;
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<String> manifest(Uri url, String platform) async {
    checks++;
    if (fail) throw const UpdateFailure('离线');
    return jsonEncode(_json(platform: platform));
  }

  @override
  Future<void> download(
    Uri url,
    File target,
    UpdateManifest manifest,
    void Function(int) progress,
  ) async {
    downloads++;
    await target.writeAsBytes([1]);
    if (gate != null) await gate!.future;
    await target.writeAsBytes([1, 2, 3]);
    progress(3);
  }

  @override
  void cancel() {
    if (gate != null && !gate!.isCompleted) gate!.complete();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const policy = UpdateUrls();
  test('Android and Windows manifests require pinned project URLs and matching tags', () {
    for (final platform in ['android', 'windows']) {
      final result = UpdateManifest.parse(
        jsonEncode(_json(platform: platform)),
        platform: platform,
      );
      expect(result.versionCode, 18);
      expect(result.notes, '更新说明\n第二行');
      final malformed = _json(platform: platform)
        ..['pageUrl'] = 'https://github.com/other/project/releases/tag/v0.13.1';
      expect(
        () => UpdateManifest.parse(jsonEncode(malformed), platform: platform),
        throwsA(isA<UpdateFailure>()),
      );
    }
  });
  test(
    'Malformed schema, size, version, notes and hashes are rejected entirely',
    () {
      for (final change in [
        {'schema': 1.0},
        {'versionCode': 0},
        {'versionCode': 2100000001},
        {'versionName': 'v0.13.1'},
        {'minSupportedVersionCode': 19},
        {'size': 104857601},
        {'size': 0},
        {'sha256': 'A' * 64},
        {'publishedAt': 'invalid'},
        {'notes': 'x' * 8001},
        {'apkUrls': []},
        {
          'apkUrls': [
            'https://github.com/whytree222/nas-todo/releases/download/v0.13.0/nas-todo-android.apk',
          ],
        },
      ]) {
        expect(
          () => UpdateManifest.parse(
            jsonEncode({..._json(), ...change}),
            platform: 'android',
          ),
          throwsA(isA<UpdateFailure>()),
        );
      }
      expect(
        () => UpdateManifest.parse(' ' * 65537, platform: 'android'),
        throwsA(isA<UpdateFailure>()),
      );
    },
  );
  test('URL policy rejects credentials, plaintext, fragments, traversal, ports and arbitrary redirects', () {
    for (final value in [
      'http://github.com/whytree222/nas-todo/releases/latest/download/update.json',
      'https://name:password@github.com/whytree222/nas-todo/releases/latest/download/update.json',
      'https://github.com:8443/whytree222/nas-todo/releases/latest/download/update.json',
      'https://github.com/whytree222/nas-todo/releases/latest/download/update.json#fragment',
      'https://github.com/whytree222/nas-todo/releases/latest/download/update.json?token=secret',
      'https://github.com/whytree222/nas-todo/../else/releases/latest/download/update.json',
      'https://127.0.0.1/whytree222/nas-todo/releases/latest/download/update.json',
    ]) {
      expect(
        policy.initial(
          Uri.parse(value),
          kind: 'manifest',
          platform: 'android',
          cacheQuery: true,
        ),
        isFalse,
        reason: value,
      );
    }
    expect(
      policy.redirect(
        Uri.parse(
          'https://github.com/whytree222/nas-todo/releases/download/v0.13.1/update.json',
        ),
        kind: 'manifest',
        platform: 'android',
      ),
      isTrue,
    );
    expect(
      policy.redirect(
        Uri.parse(
          'https://release-assets.githubusercontent.com/file?sig=example',
        ),
        kind: 'package',
        platform: 'android',
      ),
      isTrue,
    );
    expect(
      policy.redirect(
        Uri.parse('https://evil.example/file'),
        kind: 'package',
        platform: 'android',
      ),
      isFalse,
    );
    expect(policy.manifests('android').length, 1);
    expect(
      const UpdateUrls(giteeRepository: 'owner/todo-release')
          .manifests('windows')
          .first
          .host,
      'gitee.com',
    );
  });
  test('Windows extraction forbids zip slip, alternate streams, device files and unrelated root files', () {
    for (final name in [
      '../escape.exe',
      '/absolute.exe',
      'data/../../escape',
      'data/a\\b',
      'data/NUL.txt',
      'data/x:stream',
      'README.txt',
      'data/trailing.',
      'data//empty',
    ]) {
      expect(safeBundlePath(name), isFalse, reason: name);
    }
    for (final name in [
      'nas_todo.exe',
      'flutter_windows.dll',
      'desktop-widget.cmd',
      'data/flutter_assets/fonts/material.otf',
    ]) {
      expect(safeBundlePath(name), isTrue);
    }
  });

  late Directory root;
  late _Native native;
  late _Network network;
  late UpdateController updates;
  var now = DateTime(2026, 10, 27);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('nas-todo-update-test-');
    final info = UpdateIdentity(
      platform: 'android',
      versionName: '0.13.0',
      versionCode: 17,
      directory: Directory('${root.path}/updates'),
    );
    native = _Native(info);
    network = _Network();
    now = DateTime(2026, 10, 27);
    updates = UpdateController(
      native: native,
      network: network,
      info: info,
      preferences: File('${root.path}/update-state.json'),
      clock: () => now,
    );
    await updates.initialize();
  });
  tearDown(() async {
    updates.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });
  test('Successful automatic checks are throttled for 24 hours while manual checks bypass it', () async {
    await updates.check(automatic: true);
    expect(updates.status, UpdateStatus.available);
    await updates.later();
    await updates.check(automatic: true);
    expect(network.checks, 1);
    await updates.check();
    expect(network.checks, 2);
    await updates.later();
    now = now.add(const Duration(hours: 25));
    await updates.resume();
    expect(updates.status, UpdateStatus.available);
  });
  test(
    'Failure retries wait an hour and safety gate blocks every action',
    () async {
      network.fail = true;
      await updates.check(automatic: true);
      expect(updates.status, UpdateStatus.failed);
      await updates.check(automatic: true);
      expect(network.checks, 1);
      now = now.add(const Duration(hours: 2));
      await updates.check(automatic: true);
      expect(network.checks, 2);
      updates.setAllowed(false);
      await updates.check();
      await updates.download();
      await updates.install();
      expect(network.checks, 2);
      expect(native.installs, 0);
    },
  );
  test('Download is checked, persists Ready across restart and requires an install action', () async {
    await updates.check();
    await updates.download();
    expect(updates.status, UpdateStatus.ready);
    expect(native.installs, 0);
    final restarted = UpdateController(
      native: native,
      network: network,
      info: native.info,
      preferences: updates.preferences,
    );
    await restarted.initialize();
    expect(restarted.status, UpdateStatus.ready);
    restarted.dispose();
    await updates.install();
    expect(native.installs, 1);
    expect(native.verifies, greaterThanOrEqualTo(3));
  });
  test(
    'Signature rejection deletes packages and never opens an installer',
    () async {
      native.reject = true;
      await updates.check();
      await updates.download();
      expect(updates.status, UpdateStatus.failed);
      expect(await native.info.directory.list().toList(), isEmpty);
      expect(native.installs, 0);
    },
  );
  test('A background transition cancels partial writes without leaving a Ready package', () async {
    await updates.check();
    network.gate = Completer<void>();
    final downloading = updates.download();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    updates.setAllowed(false);
    await downloading;
    expect(updates.status, UpdateStatus.available);
    expect(await native.info.directory.list().toList(), isEmpty);
    expect(native.installs, 0);
  });
  test(
    'Storage and install-time tamper checks fail before installation',
    () async {
      await updates.check();
      native.space = 0;
      await updates.download();
      expect(updates.status, UpdateStatus.failed);
      expect(network.downloads, 0);
      native.space = 1000000;
      await updates.download();
      expect(updates.status, UpdateStatus.ready);
      await native.info.directory
          .list()
          .where((f) => f is File)
          .first
          .then((file) => File(file.path).writeAsBytes([9]));
      await updates.install();
      expect(updates.status, UpdateStatus.failed);
      expect(native.installs, 0);
    },
  );
  testWidgets(
    'Narrow update UI shows notes, download and explicit system installation confirmation',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await updates.check();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: UpdateCard(updates: updates),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 0.13.1'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('update-download')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('update-install')));
      await tester.tap(find.byKey(const ValueKey('update-install')));
      await tester.pumpAndSettle();
      expect(find.text('安装更新？'), findsOneWidget);
      expect(native.installs, 0);
      await tester.tap(find.text('继续安装'));
      await tester.pumpAndSettle();
      expect(native.installs, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
