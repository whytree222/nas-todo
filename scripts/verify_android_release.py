"""Verify the release APK against the public, pinned signing certificate."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

def verify_signing_output(output, expected):
    # v3.1 prints SDK-range signers rather than the older "Signer #1" label.
    counts = re.findall(r'^Number of signers:\s*(\d+)\s*$', output, re.M)
    lines = [line.strip() for line in output.splitlines()
             if line.startswith('Signer ') and 'certificate SHA-256 digest:' in line]
    label = r'(?:#1|\(minSdkVersion=\d+(?: \(dev release=true\))?, maxSdkVersion=\d+\))'
    pattern = re.compile(r'Signer ' + label + r' certificate SHA-256 digest:\s*([0-9a-fA-F]{64})')
    matches = [pattern.fullmatch(line) for line in lines]
    assert counts == ['1'] and lines and all(matches), 'Release must have one recognized APK signer'
    certificates = {match.group(1).lower() for match in matches}
    assert certificates == {expected}, 'Release signing certificate mismatch'

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--apk',required=True)
    parser.add_argument('--sdk',required=True)
    args=parser.parse_args()
    root=Path(__file__).resolve().parent.parent
    apk=Path(args.apk).resolve()
    version, code=re.search(r'^version: (\d+\.\d+\.\d+)\+(\d+)\s*$', (root/'client/pubspec.yaml').read_text('utf-8'),re.M).groups()
    expected=(root/'client/android/release-cert.sha256').read_text('utf-8').strip()
    tools=sorted((Path(args.sdk)/'build-tools').glob('*/apksigner'))
    assert tools, 'Android signing verifier is unavailable'
    tool=tools[-1]
    result=subprocess.run([str(tool),'verify','--verbose','--print-certs',str(apk)],capture_output=True,text=True,check=True)
    print('Public APK signing certificate diagnostics: ' + json.dumps([
        line.strip() for line in result.stdout.splitlines() if 'certificate SHA-256 digest:' in line
    ]))
    print('Expected public certificate SHA256: ' + expected)
    verify_signing_output(result.stdout, expected)
    info=subprocess.run([str(tool.with_name('aapt')),'dump','badging',str(apk)],capture_output=True,text=True,check=True).stdout
    identity=re.search(r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'",info)
    assert identity and identity.groups()==('cn.privatetodo.app',code,version), 'APK identity/version mismatch'
    assert 0<apk.stat().st_size<=100*1024*1024, 'Release APK exceeds the update size limit'
    metadata={'packageName':'cn.privatetodo.app','versionCode':int(code),'versionName':version,
              'certificateSha256':expected,'sha256':hashlib.file_digest(apk.open('rb'),'sha256').hexdigest(),'size':apk.stat().st_size}
    apk.with_suffix('.identity.json').write_text(json.dumps(metadata,indent=2)+'\n','utf-8')
    print('Verified fixed release signature, package/version, size and SHA256')

if __name__=='__main__': main()
