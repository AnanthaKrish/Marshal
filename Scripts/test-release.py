#!/usr/bin/env python3
"""Release guardrails: rejected input must stop before building or using credentials."""
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
with (ROOT / 'Resources/Info.plist').open('rb') as stream:
    VERSION = plistlib.load(stream)['CFBundleShortVersionString']


class ReleaseGuardrails(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.marker = Path(self.temp.name) / 'unexpected-build'
        fake_swift = Path(self.temp.name) / 'swift'
        fake_swift.write_text('#!/bin/sh\ntouch "$RELEASE_TEST_MARKER"\nexit 99\n')
        fake_swift.chmod(0o755)
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith(('MARSHAL_', 'APPLE_', 'DEVELOPER_ID_'))}
        self.env.update(PATH=self.temp.name + ':' + os.environ['PATH'],
                        RELEASE_TEST_MARKER=str(self.marker), GITHUB_ACTIONS='false')

    def rejects(self, script, args, expected, **environment):
        result = subprocess.run(['bash', str(ROOT / 'Scripts' / script), *args],
                                env={**self.env, **environment}, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(expected, result.stderr)
        self.assertFalse(self.marker.exists(), 'A rejected release must not start a build')

    def test_shell_syntax(self):
        for script in (ROOT / 'Scripts').glob('*.sh'):
            with self.subTest(script=script.name):
                subprocess.run(['bash', '-n', str(script)], check=True)

    def test_bad_tags_are_rejected(self):
        for tag in ['../v0.1.0', '0.1.0', 'v01.2.3', 'v0.1', 'v0.1.0;echo unsafe', 'v0.1.0/extra']:
            with self.subTest(tag=tag):
                self.rejects('package-release.sh', [tag], 'Use a tag')

    def test_tag_must_match_app_version(self):
        self.rejects('package-release.sh', ['v9999.0.0'], 'must match')

    def test_release_cannot_fall_back_to_adhoc(self):
        for identity in ['', '-', 'Apple Development: Example (TESTTEAMID)']:
            with self.subTest(identity=identity):
                self.rejects('package-release.sh', ['v' + VERSION], 'Developer ID Application',
                             MARSHAL_SIGNING_IDENTITY=identity)

    def test_release_requires_notarization(self):
        self.rejects('package-release.sh', ['v' + VERSION], 'MARSHAL_NOTARY_PROFILE',
                     MARSHAL_SIGNING_IDENTITY='Developer ID Application: Example (TESTTEAMID)')

    def test_prerelease_tags_are_validated(self):
        self.rejects('package-release.sh', ['v' + VERSION + '-beta.1'], 'Developer ID Application')

    def test_preview_still_checks_version_and_architecture(self):
        self.rejects('package-release.sh', ['--preview', 'v9999.0.0'], 'must match')
        self.rejects('package-release.sh', ['--preview', 'v' + VERSION], 'Apple silicon', MARSHAL_ARCH='x86_64')

    def test_build_rejects_invalid_settings(self):
        self.rejects('build-app.sh', ['invalid'], 'configuration')
        self.rejects('build-app.sh', [], 'architectures', MARSHAL_ARCH='invalid')
        self.rejects('build-app.sh', [], 'positive integer', MARSHAL_BUILD_NUMBER='0')
        self.rejects('build-app.sh', [], 'Developer ID Application', MARSHAL_SIGNING_IDENTITY='Apple Development: Example')

    def test_import_helper_does_not_touch_local_keychain(self):
        self.rejects('import-signing.sh', [], 'only for GitHub Actions')


if __name__ == '__main__':
    unittest.main(verbosity=2)
