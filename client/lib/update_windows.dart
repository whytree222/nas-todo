import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'update_manifest.dart';

bool safeBundlePath(String name) {
  if (name.isEmpty ||
      name.length > 220 ||
      name.startsWith('/') ||
      name.contains('\\') ||
      name.contains(':') ||
      name.contains('\u0000'))
    return false;
  final parts = name.split('/');
  if (parts.any(
    (p) =>
        p.isEmpty ||
        p == '.' ||
        p == '..' ||
        p.endsWith(' ') ||
        p.endsWith('.') ||
        RegExp(
          r'^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(\.|$)',
          caseSensitive: false,
        ).hasMatch(p),
  ))
    return false;
  return parts.length == 1
      ? RegExp(
          r'^[A-Za-z0-9_.-]+\.(exe|dll|cmd)$',
          caseSensitive: false,
        ).hasMatch(name)
      : parts.first == 'data';
}

Future<void> prepareWindowsBundle(File package, UpdateManifest manifest) async {
  if (await package.length() != manifest.size ||
      (await sha256.bind(package.openRead()).first).toString() !=
          manifest.sha256)
    throw const UpdateFailure('SHA-256 校验失败，请重新下载');
  final stage = Directory('${package.path}.stage');
  // App-owned deterministic staging sibling; never use an archive-supplied root.
  if (await stage.exists()) await stage.delete(recursive: true);
  await stage.create();
  try {
    final archive = ZipDecoder().decodeBytes(
      await package.readAsBytes(),
      verify: true,
    );
    final names = <String>{};
    final records = <String>[];
    var total = 0;
    if (archive.length > 4096) throw const UpdateFailure('更新包文件过多');
    for (final entry in archive) {
      final name = entry.name;
      if (entry.isSymbolicLink) throw const UpdateFailure('更新包包含不允许的链接');
      if (!entry.isFile) continue;
      if (!safeBundlePath(name) || !names.add(name.toLowerCase()))
        throw const UpdateFailure('更新包包含无效路径');
      total += entry.size;
      if (entry.size < 0 || total > 512 * 1024 * 1024)
        throw const UpdateFailure('更新包展开大小超限');
      final content = entry.content;
      if (content.length != entry.size) throw const UpdateFailure('更新包文件大小无效');
      final file = File('${stage.path}/$name');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(content, flush: true);
      records.add('${sha256.convert(content)} $name');
    }
    if (!names.containsAll({
      'nas_todo.exe',
      'nas_todo_updater.exe',
      'flutter_windows.dll',
      'data/icudtl.dat',
    }))
      throw const UpdateFailure('Windows 更新包不完整');
    await File('${stage.path}/update-files.txt').writeAsString(
      'NAS_TODO_UPDATE_V1\n${manifest.versionName}\n${manifest.versionCode}\n${records.join('\n')}\n',
      encoding: utf8,
      flush: true,
    );
  } catch (_) {
    if (await stage.exists()) await stage.delete(recursive: true);
    rethrow;
  }
}
