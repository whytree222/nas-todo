"""Exercise real release packaging without network access or publication."""
import base64
import hashlib
import json
import os
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import publish_release as publisher

class ReleasePackagingTests(unittest.TestCase):
    def test_server_embedding_cannot_replace_update_version_code(self):
        previous = Path.cwd()
        with tempfile.TemporaryDirectory() as directory:
            try:
                os.chdir(directory)
                def write(name, data):
                    path = Path(name)
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(data)
                    return path

                source = b'print("server fixture only")\n'
                write('server/app.py', source)
                write('server/Dockerfile', b'FROM python:3.12-slim\n')
                for version in ['0.7.0', '0.10.0', '0.11.0']:
                    write(f'docs/UPGRADE-v{version}.md', b'test guide')
                write('docs/RELEASE-v0.13.0.md', b'Update fixture notes')
                write('client/pubspec.yaml', b'version: 0.13.0+17\n')
                fingerprint = 'a' * 64
                write('client/android/release-cert.sha256', (fingerprint + '\n').encode())
                apk = Path('release-input/android/app-release.apk')
                apk.parent.mkdir(parents=True)
                with zipfile.ZipFile(apk, 'w') as archive:
                    for name in ['AndroidManifest.xml', 'classes.dex', 'lib/arm64-v8a/libflutter.so',
                                 'assets/flutter_assets/fonts/MaterialIcons-Regular.otf']:
                        archive.writestr(name, b'fixture' * 300)
                apk.with_suffix('.identity.json').write_text(json.dumps({
                    'packageName': 'cn.privatetodo.app', 'versionName': '0.13.0', 'versionCode': 17,
                    'certificateSha256': fingerprint, 'size': apk.stat().st_size,
                    'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
                }), 'utf-8')
                pe = bytearray(72)
                pe[:2] = b'MZ'
                struct.pack_into('<I', pe, 0x3c, 64)
                pe[64:68] = b'PE\0\0'
                struct.pack_into('<H', pe, 68, 0x8664)
                for name in ['nas_todo.exe', 'nas_todo_updater.exe', 'flutter_windows.dll']:
                    write('release-input/windows/' + name, pe)
                for name in ['data/icudtl.dat', 'data/flutter_assets/fonts/MaterialIcons-Regular.otf', 'desktop-widget.cmd']:
                    write('release-input/windows/' + name, b'fixture')
                write('release-input/windows/nas_todo.pdb', b'excluded symbols')
                write('release-input/windows/nas_todo.identity.json', json.dumps({
                    'versionName': '0.13.0', 'versionCode': 17,
                    'sha256': hashlib.sha256(pe).hexdigest(),
                }).encode())
                def api(path):
                    if path == 'repos/whytree222/nas-todo':
                        return {'private': False}
                    if '/actions/runs/' in path:
                        return {'conclusion': 'success', 'head_sha': 'b' * 40}
                    if '/contents/server/app.py?' in path:
                        return {'content': base64.b64encode(source).decode()}
                    raise AssertionError('Unexpected network API: ' + path)

                with patch.dict(os.environ, GH_REPO='whytree222/nas-todo'), patch.multiple(
                    publisher, BUILD_RUN=123, BUILD_SHA='b' * 40, VERSION='0.13.0',
                    VISIBILITY='public', TAG='v0.13.0', NOTES='docs/RELEASE-v0.13.0.md',
                ), patch.object(publisher, 'api', side_effect=api), patch.object(publisher, 'publish_updates') as publish:
                    publisher.main()
                    publish.assert_called_once()
                    assets = publish.call_args.args[1]
                    self.assertEqual(len(assets), 7)
                    for filename in ['update.json', 'update-windows.json']:
                        manifest = json.loads(Path('release-dist', filename).read_text('utf-8'))
                        self.assertEqual(manifest['versionCode'], 17)
                        self.assertEqual(manifest['versionName'], '0.13.0')
                    with zipfile.ZipFile('release-dist/nas-todo-windows-v0.13.0-x64.zip') as archive:
                        self.assertNotIn('nas_todo.pdb', archive.namelist())
                        self.assertNotIn('nas_todo.identity.json', archive.namelist())
                    with zipfile.ZipFile('release-dist/nas-todo-server-v0.13.0.zip') as archive:
                        self.assertIn(base64.b64encode(source).decode(), archive.read('command-block.yaml').decode())
            finally:
                os.chdir(previous)

if __name__ == '__main__':
    unittest.main()
