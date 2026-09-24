import importlib.util
import hashlib
import io
import os
import re
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('ci_release', Path(__file__).resolve().parents[1]/'scripts/ci_release.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class ReleaseInputs(unittest.TestCase):
    def test_rejects_shell_input(self):
        for v, b in [('0.12.1; echo bad','33'),('0.12.1','33\nfoo'),('0.12.1','-1')]:
            with patch.dict(os.environ, RELEASE_VERSION=v, RELEASE_BUILD=b):
                with self.assertRaises(SystemExit): m.release()
    def test_rejects_reused_build(self):
        with patch.dict(os.environ, RELEASE_VERSION='0.12.1', RELEASE_BUILD='32'):
            with self.assertRaises(SystemExit): m.validate()
    def test_accepts_next_build(self):
        with patch.dict(os.environ, RELEASE_VERSION='999.0.0', RELEASE_BUILD=str(int(re.search(r'Build (\d+)', (m.ROOT/'site/public/download/index.html').read_text())[1])+1)): m.validate()
    def test_rejects_version_downgrade(self):
        with patch.dict(os.environ, RELEASE_VERSION='0.11.0', RELEASE_BUILD='33'):
            with self.assertRaises(SystemExit): m.validate()

class SigningIdentity(unittest.TestCase):
    def identity(self, team, fingerprint='A'*40, kind='Developer ID Application'):
        return f'  1) {fingerprint} "{kind}: Test Publisher ({team})"\n'

    def test_preserves_legacy_team_when_variable_is_unset_or_empty(self):
        for values in ({}, {'WAND_SIGNING_TEAM_ID': ''}):
            with patch.dict(os.environ, values, clear=True):
                self.assertEqual(m.signing_team_id(), 'AX35NK3J3A')

    def test_accepts_explicit_owner_team(self):
        with patch.dict(os.environ, WAND_SIGNING_TEAM_ID='AB12CD34EF'):
            self.assertEqual(m.signing_team_id(), 'AB12CD34EF')

    def test_rejects_malformed_team_before_any_signing_command(self):
        for team in ('wrong', 'ab12cd34ef', 'AB12CD34EF ', 'AB12CD34EF\n', 'AX35.*', 'AB12CD34EF;echo bad'):
            with self.subTest(team=team), patch.dict(os.environ, WAND_SIGNING_TEAM_ID=team), patch.object(m, 'run') as command:
                with self.assertRaises(SystemExit): m.package()
                command.assert_not_called()

    def test_selects_only_the_configured_team(self):
        ids = self.identity('AX35NK3J3A') + self.identity('AB12CD34EF', fingerprint='B'*40)
        self.assertEqual(m.signing_identity(ids, 'AB12CD34EF'), 'B'*40)
        self.assertEqual(m.signing_identity(ids, 'AX35NK3J3A'), 'A'*40)

    def test_rejects_missing_wrong_type_or_ambiguous_identities(self):
        for ids in ('', self.identity('AX35NK3J3A'),
                    self.identity('AB12CD34EF', kind='Apple Development'),
                    self.identity('AB12CD34EF', kind='Developer ID Installer'),
                    self.identity('AB12CD34EF') + self.identity('AB12CD34EF', fingerprint='B'*40)):
            with self.subTest(identities=ids):
                with self.assertRaises(SystemExit): m.signing_identity(ids, 'AB12CD34EF')

class ReleaseCredentials(unittest.TestCase):
    def environment(self):
        return dict(RELEASE_VERSION='999.0.0', RELEASE_BUILD='999999',
                    WAND_SIGNING_TEAM_ID='58XWD3LBSS',
                    **{key: 'Zml4dHVyZQ==' for key in m.SIGNING_SECRETS})

    def test_artifact_preflight_accepts_only_apple_secrets(self):
        with patch.dict(os.environ, self.environment(), clear=True), patch.object(m, 'run') as command:
            m.preflight()
            command.assert_not_called()

    def test_missing_apple_credentials_fail_without_commands_or_secret_values(self):
        for value in (None, ''):
            environment = self.environment()
            if value is None: environment.pop('WAND_NOTARY_KEY_BASE64')
            else: environment['WAND_NOTARY_KEY_BASE64'] = value
            with self.subTest(value=value), patch.dict(os.environ, environment, clear=True), patch.object(m, 'run') as command:
                with self.assertRaises(SystemExit) as error: m.preflight()
                self.assertEqual(str(error.exception), 'Missing release secrets: WAND_NOTARY_KEY_BASE64')
                command.assert_not_called()

    def test_publish_preflight_requires_deployment_credentials_before_commands(self):
        with patch.dict(os.environ, self.environment(), clear=True), patch.object(m, 'run') as command:
            with self.assertRaises(SystemExit) as error: m.preflight(publish=True)
            self.assertEqual(str(error.exception), 'Missing release secrets: GH_RELEASE_TOKEN, CLOUDFLARE_API_TOKEN')
            command.assert_not_called()

    def test_publish_preflight_accepts_all_seven_secrets(self):
        environment = self.environment() | {key: 'fixture' for key in m.PUBLICATION_SECRETS}
        with patch.dict(os.environ, environment, clear=True), patch.object(m, 'run') as command:
            m.preflight(publish=True)
            command.assert_not_called()

    def test_package_reaches_signing_setup_without_deployment_credentials(self):
        class StopBeforeSigning(Exception): pass
        with tempfile.TemporaryDirectory(prefix='wand-release-credentials-test-') as folder:
            environment = self.environment() | {'RUNNER_TEMP': folder}
            with patch.dict(os.environ, environment, clear=True), patch.object(m, 'run', side_effect=StopBeforeSigning) as command:
                with self.assertRaises(StopBeforeSigning): m.package()
                self.assertEqual(command.call_args.args[:2], ('security', 'create-keychain'))

class PublishedRelease(unittest.TestCase):
    name = 'Wand-0.13.0-build33'
    artifact = b'notarized release fixture'

    def verify(self, page, artifact=None):
        with tempfile.TemporaryDirectory(prefix='wand-release-verifier-') as folder:
            root = Path(folder)
            release = root/'dist/release'
            release.mkdir(parents=True)
            (release/(self.name+'.sha256')).write_text(hashlib.sha256(self.artifact).hexdigest()+'  '+self.name+'.dmg\n')
            def response(request, timeout):
                if request.full_url == 'https://getwand.app/download': return io.BytesIO(page.encode())
                self.assertEqual(request.full_url, 'https://getwand.app/releases/'+self.name+'.dmg')
                return io.BytesIO(self.artifact if artifact is None else artifact)
            with patch.object(m, 'ROOT', root), patch.dict(os.environ, RELEASE_VERSION='0.13.0', RELEASE_BUILD='33'), patch.object(m.urllib.request, 'urlopen', side_effect=response), patch('builtins.print'):
                m.verify()

    def test_accepts_expected_build_link_and_matching_artifact(self):
        self.verify(f'<p>Build 33</p><a class="download" href=\'/releases/{self.name}.dmg\'>Download</a>')

    def test_rejects_build_number_prefix_match(self):
        with self.assertRaisesRegex(SystemExit, 'expected release'):
            self.verify(f'<p>Build 330</p><a href="/releases/{self.name}.dmg">Download</a>')

    def test_rejects_stale_or_missing_download_link(self):
        for link in ('', '<a href="/releases/Wand-0.12.0-build32.dmg">Download</a>', f'<div data-href="/releases/{self.name}.dmg">Download</div>'):
            with self.subTest(link=link), self.assertRaisesRegex(SystemExit, 'expected release'):
                self.verify('<p>Build 33</p>'+link)

    def test_rejects_wrong_artifact_even_when_page_matches(self):
        with self.assertRaisesRegex(SystemExit, 'checksum mismatch'):
            self.verify(f'<p>Build 33</p><a href="/releases/{self.name}.dmg">Download</a>', artifact=b'wrong build')

if __name__=='__main__': unittest.main()
