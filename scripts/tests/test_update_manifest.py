import hashlib
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from update_manifest import make_manifest
from verify_android_release import verify_signing_output

class SigningCertificateTests(unittest.TestCase):
    fingerprint = 'a' * 64

    def test_legacy_single_signer_is_pinned(self):
        verify_signing_output('Number of signers: 1\nSigner #1 certificate SHA-256 digest: ' + self.fingerprint, self.fingerprint)

    def test_sdk_range_output_and_identical_v3_and_v31_certificates_are_supported(self):
        output = ('Number of signers: 1\n'
                  'Signer (minSdkVersion=24, maxSdkVersion=32) certificate SHA-256 digest: ' + self.fingerprint + '\n'
                  'Signer (minSdkVersion=33, maxSdkVersion=2147483647) certificate SHA-256 digest: ' + self.fingerprint)
        verify_signing_output(output, self.fingerprint)

    def test_unrecognized_wrong_rotated_or_multiple_signers_are_rejected(self):
        for output in [
            'Number of signers: 1\nSigner #1 certificate SHA-256 digest: ' + 'b' * 64,
            'Number of signers: 2\nSigner #1 certificate SHA-256 digest: ' + self.fingerprint,
            'Number of signers: 1\nSigner #2 certificate SHA-256 digest: ' + self.fingerprint,
            'Number of signers: 1\nSigner #1 certificate SHA-256 digest: ' + self.fingerprint + '\nSigner (minSdkVersion=33, maxSdkVersion=2147483647) certificate SHA-256 digest: ' + 'b' * 64,
            'Number of signers: 1\nSource Stamp Signer certificate SHA-256 digest: ' + self.fingerprint,
            'Number of signers: 1\nSigner (unknown) certificate SHA-256 digest: ' + self.fingerprint,
        ]:
            with self.assertRaises(AssertionError):
                verify_signing_output(output, self.fingerprint)

class ManifestTests(unittest.TestCase):
    def test_platform_urls_are_versioned_and_describe_exact_package_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            for platform,filename in [('android','nas-todo-android-v0.13.0.apk'),('windows','nas-todo-windows-v0.13.0-x64.zip')]:
                path=Path(directory)/filename; path.write_bytes(b'exact release bytes')
                result=make_manifest('0.13.0',17,platform,path,'line1\r\nline2','2026-10-27T00:00:00Z')
                self.assertEqual(result['sha256'],hashlib.sha256(path.read_bytes()).hexdigest())
                self.assertEqual(result['size'],len(path.read_bytes()))
                self.assertEqual(result['notes'],'line1\nline2')
                self.assertEqual(result['apkUrls' if platform=='android' else 'zipUrls'],[f'https://github.com/whytree222/nas-todo/releases/download/v0.13.0/{filename}'])
    def test_empty_packages_and_oversized_notes_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'nas-todo-android-v0.13.0.apk'; path.write_bytes(b'')
            with self.assertRaises(AssertionError): make_manifest('0.13.0',17,'android',path,'')
            path.write_bytes(b'a')
            with self.assertRaises(AssertionError): make_manifest('0.13.0',17,'android',path,'x'*8001)
    def test_invalid_identity_and_windows_resource_version_overflow_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'nas-todo-android-v0.13.0.apk'; path.write_bytes(b'a')
            for version,code,platform in [('v0.13.0',17,'android'),('0.13.0',0,'windows'),('0.13.0',65536,'windows'),('0.13.0',17,'linux')]:
                with self.assertRaises(AssertionError): make_manifest(version,code,platform,path,'')

if __name__=='__main__': unittest.main()
