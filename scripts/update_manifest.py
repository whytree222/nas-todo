"""Build versioned public manifests only from the exact release bytes."""
import datetime as dt
import hashlib
from pathlib import Path
import re

REPOSITORY='whytree222/nas-todo'

def make_manifest(version,code,platform,package,notes,published_at=None):
    assert re.fullmatch(r'\d{1,4}\.\d{1,4}\.\d{1,4}',version)
    assert 0<code<=65535 and platform in ('android','windows')
    package=Path(package)
    assert 0<package.stat().st_size<=100*1024*1024
    assert len(notes)<=8000
    assert re.fullmatch(r'nas-todo-[A-Za-z0-9_.-]+\.'+('apk' if platform=='android' else 'zip'),package.name)
    with package.open('rb') as source:
        digest=hashlib.file_digest(source,'sha256').hexdigest()
    return {'schema':1,'versionCode':code,'versionName':version,'minSupportedVersionCode':17,
            'publishedAt':published_at or dt.datetime.now(dt.timezone.utc).isoformat(timespec='seconds'),
            'apkUrls' if platform=='android' else 'zipUrls':[f'https://github.com/{REPOSITORY}/releases/download/v{version}/{package.name}'],
            'sha256':digest,'size':package.stat().st_size,
            'notes':notes.replace('\r\n','\n'),'pageUrl':f'https://github.com/{REPOSITORY}/releases/tag/v{version}'}
