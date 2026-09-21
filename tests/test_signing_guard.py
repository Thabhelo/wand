import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
import unittest
import tempfile

spec = importlib.util.spec_from_file_location('signing_guard', Path(__file__).parents[1] / 'scripts/signing_guard.py')
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


def signed(tmp_path, name, identifier):
    target = tmp_path / name
    shutil.copyfile('/usr/bin/true', target)
    subprocess.run(['codesign', '--force', '--sign', '-', '--identifier', identifier, '--requirements', '=designated => identifier "' + identifier + '"', str(target)], check=True, capture_output=True)
    return target

@unittest.skipUnless(sys.platform == 'darwin', 'Uses macOS code signing')
class SigningGuardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
    def test_same_identity_update_passes(self):
        guard.verify_update(signed(self.folder,'old','wand.test'), signed(self.folder,'new','wand.test'))
    def test_changed_identity_update_rejected(self):
        with self.assertRaisesRegex(ValueError, 'trusted signing identity'):
            guard.verify_update(signed(self.folder,'old','wand.test'), signed(self.folder,'new','other.test'))
    def test_unsigned_update_rejected(self):
        old = signed(self.folder,'old','wand.test')
        new = signed(self.folder,'new','wand.test')
        subprocess.run(['codesign','--remove-signature',str(new)], check=True, capture_output=True)
        with self.assertRaises(subprocess.CalledProcessError): guard.verify_update(old,new)

if __name__ == '__main__': unittest.main()
