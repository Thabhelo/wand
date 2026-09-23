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

if __name__=='__main__': unittest.main()
