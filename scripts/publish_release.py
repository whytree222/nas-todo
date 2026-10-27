"""Publish a successful build with an explicitly selected repository visibility."""
import hashlib
import base64
import json
import os
import re
from pathlib import Path
import shutil
import struct
import subprocess
import zipfile
from update_manifest import make_manifest

BUILD_RUN = int(os.environ.get('NAS_TODO_BUILD_RUN', '37900998859'))
BUILD_SHA = os.environ.get('NAS_TODO_BUILD_SHA', 'bc35fc387f926ffb9370369974961cb257a0ceb2')
VERSION = os.environ.get('NAS_TODO_RELEASE_VERSION', '0.1.0')
VISIBILITY = os.environ.get('NAS_TODO_RELEASE_VISIBILITY', 'private')
if VISIBILITY not in {'private', 'public'}:
    raise ValueError('Invalid approved repository visibility')
if not re.fullmatch(r'\d+\.\d+\.\d+', VERSION) or not re.fullmatch(r'[0-9a-f]{40}', BUILD_SHA):
    raise ValueError('Invalid release version or source commit')
TAG = 'v' + VERSION
NOTES = f'docs/RELEASE-{TAG}.md'


def gh(*args):
    result = subprocess.run(['gh', *args], text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return result.stdout


def api(path):
    return json.loads(gh('api', path))


def check(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def verify_pe(path):
    with path.open('rb') as source:
        check(source.read(2) == b'MZ', f'Invalid executable: {path}')
        source.seek(0x3c)
        offset = struct.unpack('<I', source.read(4))[0]
        source.seek(offset)
        check(source.read(4) == b'PE\0\0', f'Invalid PE header: {path}')
        check(struct.unpack('<H', source.read(2))[0] == 0x8664,
              f'Expected Windows x64: {path}')


def publish_updates(repo, assets, expected, repository):
    # New updater releases are append-only; never clobber an existing release.
    check(not any(r['tag_name'] == TAG for r in api(f'repos/{repo}/releases?per_page=100')),
          'Existing releases are never overwritten')
    tags = api(f'repos/{repo}/tags?per_page=100')
    tag = next((t for t in tags if t['name'] == TAG), None)
    check(tag is None or tag['commit']['sha'] == BUILD_SHA, 'Existing tag source mismatch')
    created = False
    try:
        gh('release', 'create', TAG, '--target', BUILD_SHA, '--draft',
           '--title', f'私有待办 {TAG}', '--notes-file', NOTES)
        created = True
        packages = [p for p in assets if p.name not in {'update.json', 'update-windows.json'}]
        manifests = [p for p in assets if p.name in {'update.json', 'update-windows.json'}]
        gh('release', 'upload', TAG, *(str(p) for p in packages))
        # Both manifests are uploaded last, while the release is still a draft.
        gh('release', 'upload', TAG, *(str(p) for p in manifests))
        release = next(r for r in api(f'repos/{repo}/releases?per_page=100') if r['tag_name'] == TAG)
        uploaded = {a['name']: a for a in release['assets']}
        check(set(uploaded) == set(expected), 'Unexpected or missing assets')
        for name, (size, hash_value) in expected.items():
            check(uploaded[name]['state'] == 'uploaded' and uploaded[name]['size'] == size and uploaded[name].get('digest') == hash_value,
                  'Release asset integrity mismatch: ' + name)
        gh('release', 'edit', TAG, '--draft=false', '--prerelease=false', '--latest')
        published = api(f'repos/{repo}/releases/tags/{TAG}')
        check(not published['draft'] and not published['prerelease'], 'Stable update channel publication failed')
        check(api(f'repos/{repo}/releases/latest')['tag_name'] == TAG, 'Latest update channel mismatch')
        check(api(f'repos/{repo}/commits/{TAG}')['sha'] == BUILD_SHA, 'Published tag source mismatch')
        print('RELEASE_VERIFIED ' + json.dumps({
            'url': published['html_url'], 'tag': TAG, 'source_sha': BUILD_SHA,
            'private': repository['private'], 'visibility': VISIBILITY, 'prerelease': False,
            'update_manifests': {p.name: json.loads(p.read_text('utf-8')) for p in manifests},
            'assets': [{k: a[k] for k in ('name', 'size', 'digest', 'browser_download_url')} for a in published['assets']],
        }, ensure_ascii=False))
    except Exception:
        if created:
            release = next((r for r in api(f'repos/{repo}/releases?per_page=100') if r['tag_name'] == TAG), None)
            if release and release['draft']:
                gh('release', 'delete', TAG, '--yes')  # Only this run's still-private draft.
        raise


def main():
    repo = os.environ['GH_REPO']
    repository = api(f'repos/{repo}')
    expected_private = VISIBILITY == 'private'
    check(repository['private'] == expected_private,
          f'Publication requires the approved {VISIBILITY} repository visibility')
    run = api(f'repos/{repo}/actions/runs/{BUILD_RUN}')
    check(run['conclusion'] == 'success' and run['head_sha'] == BUILD_SHA,
          'Source build must be successful at the verified commit')

    modern = tuple(map(int, VERSION.split('.'))) >= (0, 13, 0)
    android = Path('release-input/android/' + ('app-release.apk' if modern else 'app-debug.apk'))
    check(android.is_file(), 'Android APK missing')
    with zipfile.ZipFile(android) as apk:
        check(apk.testzip() is None, 'APK ZIP integrity failed')
        names = set(apk.namelist())
        check({'AndroidManifest.xml', 'classes.dex'} <= names,
              'APK manifest or bytecode missing')
        check(any(n.endswith('/libflutter.so') for n in names), 'Flutter engine missing')
        if tuple(map(int, VERSION.split('.'))) >= (0, 9, 0):
            icons = 'assets/flutter_assets/fonts/MaterialIcons-Regular.otf'
            check(icons in names and apk.getinfo(icons).file_size > 1000,
                  'Material icon font missing from APK')
    if modern:
        metadata = json.loads(Path('release-input/android/app-release.identity.json').read_text('utf-8'))
        version, code = re.search(r'^version: (\d+\.\d+\.\d+)\+(\d+)\s*$', Path('client/pubspec.yaml').read_text('utf-8'), re.M).groups()
        check(version == VERSION and metadata['versionName'] == version and metadata['versionCode'] == int(code)
              and metadata['packageName'] == 'cn.privatetodo.app' and metadata['size'] == android.stat().st_size
              and metadata['sha256'] == digest(android)
              and metadata['certificateSha256'] == Path('client/android/release-cert.sha256').read_text('utf-8').strip(),
              'Signed APK identity does not match the tested, pinned release')
    windows = Path('release-input/windows')
    for name in ('nas_todo.exe', 'flutter_windows.dll', 'data/icudtl.dat'):
        check((windows / name).is_file(), f'Windows file missing: {name}')
    check((windows / 'data/flutter_assets').is_dir(), 'Flutter assets missing')
    if tuple(map(int, VERSION.split('.'))) >= (0, 9, 0):
        check((windows / 'data/flutter_assets/fonts/MaterialIcons-Regular.otf').is_file(),
              'Material icon font missing from Windows package')
    if tuple(map(int, VERSION.split('.'))) >= (0, 3, 0):
        check((windows / 'desktop-widget.cmd').is_file(), 'Independent widget launcher missing')
    if modern:
        check((windows / 'nas_todo_updater.exe').is_file(), 'Windows updater missing')
        identity = json.loads((windows / 'nas_todo.identity.json').read_text('utf-8'))
        check(identity['versionName'] == VERSION and identity['versionCode'] == int(code)
              and identity['sha256'] == digest(windows / 'nas_todo.exe'), 'Windows PE identity mismatch')
        verify_pe(windows / 'nas_todo_updater.exe')
    verify_pe(windows / 'nas_todo.exe')
    verify_pe(windows / 'flutter_windows.dll')
    print('Verified successful source build, APK integrity and complete Windows x64 directory')

    dist = Path('release-dist')
    dist.mkdir(exist_ok=True)
    apk_output = dist / (f'nas-todo-android-{TAG}.apk' if modern else f'nas-todo-android-{TAG}-test.apk')
    shutil.copyfile(android, apk_output)
    windows_output = dist / f'nas-todo-windows-{TAG}-x64.zip'
    with zipfile.ZipFile(windows_output, 'w', zipfile.ZIP_DEFLATED) as archive:
        for file in sorted(windows.rglob('*')):
            if file.is_file() and file.suffix.lower() not in {'.lib', '.exp', '.pdb'} and not file.name.endswith('.identity.json'):
                relative = file.relative_to(windows).as_posix()
                if modern:
                    check(relative.startswith('data/') or re.fullmatch(r'[A-Za-z0-9_.-]+\.(exe|dll|cmd)', relative, re.I),
                          'Unexpected file in Windows update bundle: ' + relative)
                archive.write(file, relative)
    with zipfile.ZipFile(windows_output) as archive:
        check(archive.testzip() is None, 'Windows ZIP integrity failed')
        check('nas_todo.exe' in archive.namelist(), 'Windows EXE not at archive root')
    guide = dist / 'INSTALL.md'
    shutil.copyfile(NOTES, guide)
    assets = [apk_output, windows_output, guide]
    if tuple(map(int, VERSION.split('.'))) >= (0, 7, 0):
        tested_source = api(f'repos/{repo}/contents/server/app.py?ref={BUILD_SHA}')
        check(base64.b64decode(tested_source['content']) == Path('server/app.py').read_bytes(),
              'Server upgrade code must match the tested source commit')
        server_output = dist / f'nas-todo-server-{TAG}.zip'
        with zipfile.ZipFile(server_output, 'w', zipfile.ZIP_DEFLATED) as archive:
            server_files = ['server/app.py', 'server/Dockerfile', 'docs/UPGRADE-v0.7.0.md']
            if tuple(map(int, VERSION.split('.'))) >= (0, 10, 0):
                server_files.append('docs/UPGRADE-v0.10.0.md')
            if tuple(map(int, VERSION.split('.'))) >= (0, 11, 0):
                server_files.append('docs/UPGRADE-v0.11.0.md')
            for name in server_files:
                archive.write(name, name)
            if tuple(map(int, VERSION.split('.'))) >= (0, 11, 0):
                code = base64.b64encode(Path('server/app.py').read_bytes()).decode('ascii')
                boot = "import base64, pathlib, os\npathlib.Path('/tmp/app.py').write_bytes(base64.b64decode('" + code + "'))\nos.execvp('python', ['python', '-u', '/tmp/app.py'])\n"
                block = 'command:\n  - python\n  - -u\n  - -c\n  - |\n' + ''.join('      ' + line + '\n' for line in boot.splitlines())
                archive.writestr('command-block.yaml', block)
                archive.writestr('todo-upgrade.override.yaml', 'services:\n  todo-sync:\n' + ''.join('    ' + line + '\n' for line in block.splitlines()))
        with zipfile.ZipFile(server_output) as archive:
            check(archive.testzip() is None and 'server/app.py' in archive.namelist(), 'Server upgrade package incomplete')
            if tuple(map(int, VERSION.split('.'))) >= (0, 10, 0):
                check('docs/UPGRADE-v0.10.0.md' in archive.namelist(), 'Personal-feature upgrade guide missing')
        assets.append(server_output)
    if modern:
        notes = Path(NOTES).read_text('utf-8')
        for platform, package, filename in [('android', apk_output, 'update.json'), ('windows', windows_output, 'update-windows.json')]:
            manifest = dist / filename
            temporary = manifest.with_suffix('.tmp')
            temporary.write_text(json.dumps(make_manifest(VERSION, int(code), platform, package, notes), ensure_ascii=False, indent=2) + '\n', 'utf-8')
            temporary.replace(manifest)
            assets.append(manifest)
    hashes = dist / 'SHA256SUMS.txt'
    hashes.write_text(''.join(f'{digest(p)}  {p.name}\n' for p in assets), encoding='utf-8')
    assets.append(hashes)
    expected = {p.name: (p.stat().st_size, 'sha256:' + digest(p)) for p in assets}

    if modern:
        publish_updates(repo, assets, expected, repository)
        return

    releases = api(f'repos/{repo}/releases?per_page=100')
    existing = next((r for r in releases if r['tag_name'] == TAG), None)
    if existing:
        check(existing['draft'] and existing['prerelease']
              and existing['target_commitish'] == BUILD_SHA,
              'An existing non-matching or published release will not be overwritten')
    else:
        tags = api(f'repos/{repo}/tags?per_page=100')
        tag = next((t for t in tags if t['name'] == TAG), None)
        check(tag is None or tag['commit']['sha'] == BUILD_SHA, 'Existing tag targets different code')
        gh('release', 'create', TAG, '--target', BUILD_SHA, '--draft', '--prerelease',
           '--title', f'私有待办 {TAG} 测试版', '--notes-file', NOTES)
    gh('release', 'upload', TAG, *(str(p) for p in assets), '--clobber')
    release = next(r for r in api(f'repos/{repo}/releases?per_page=100') if r['tag_name'] == TAG)
    uploaded = {a['name']: a for a in release['assets']}
    check(set(uploaded) == set(expected), 'Unexpected or missing release assets')
    for name, (size, sha256) in expected.items():
        asset = uploaded[name]
        check(asset['state'] == 'uploaded' and asset['size'] == size,
              f'Upload incomplete: {name}')
        check(asset.get('digest') == sha256, f'Uploaded SHA256 mismatch: {name}')
    gh('release', 'edit', TAG, '--draft=false', '--prerelease')
    published = api(f'repos/{repo}/releases/tags/{TAG}')
    check(not published['draft'] and published['prerelease'], 'Prerelease publication failed')
    check(api(f'repos/{repo}/commits/{TAG}')['sha'] == BUILD_SHA, 'Published tag source mismatch')
    print('RELEASE_VERIFIED ' + json.dumps({
        'url': published['html_url'], 'tag': TAG, 'source_sha': BUILD_SHA,
        'private': repository['private'], 'visibility': VISIBILITY,
        'prerelease': published['prerelease'],
        'assets': [{k: a[k] for k in ('name', 'size', 'digest', 'browser_download_url')}
                   for a in published['assets']],
    }, ensure_ascii=False))
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with open(summary, 'a', encoding='utf-8') as output:
            output.write(f"{VISIBILITY.capitalize()} test release published: {published['html_url']}\n")


if __name__ == '__main__':
    main()
