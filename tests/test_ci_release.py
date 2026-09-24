import importlib.util
import os
import re
from pathlib import Path
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

if __name__=='__main__': unittest.main()
