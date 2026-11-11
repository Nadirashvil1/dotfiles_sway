"""Installer checks confined to disposable target homes; never runs pacman."""
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sway-rice-test-')
        self.target = Path(self.temp.name) / 'test-home'

    def tearDown(self):
        self.temp.cleanup()

    def run_install(self, *args):
        return subprocess.run(
            ['bash', str(REPO / 'install.sh'), '--no-packages', '--yes',
             '--target-home', str(self.target), *args],
            capture_output=True, text=True,
        )

    def test_dry_run_writes_nothing(self):
        result = self.run_install('--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.target.exists())

    def test_existing_directory_is_backed_up(self):
        old = self.target / '.config/sway'
        old.mkdir(parents=True)
        (old / 'config').write_text('original desktop')
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stderr)
        backups = list((self.target / '.local/state/sway-rice/backups').iterdir())
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / '.config/sway/config').read_text(), 'original desktop')
        self.assertIn('set $mod Mod1', (old / 'config').read_text())
        self.assertTrue((self.target / '.local/bin/sway-rice/screenshot').stat().st_mode & 0o111)

    def test_symlink_preserved_and_unrelated_files_untouched(self):
        original = Path(self.temp.name) / 'original-rofi'
        original.mkdir()
        (original / 'config.rasi').write_text('original theme')
        config = self.target / '.config'
        config.mkdir(parents=True)
        (config / 'rofi').symlink_to(original, target_is_directory=True)
        unrelated = self.target / '.local/bin/sway-rice/my-helper'
        unrelated.parent.mkdir(parents=True)
        unrelated.write_text('keep this')
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stderr)
        backups = list((self.target / '.local/state/sway-rice/backups').iterdir())
        self.assertTrue((backups[0] / '.config/rofi').is_symlink())
        self.assertFalse((config / 'rofi').is_symlink())
        self.assertEqual((original / 'config.rasi').read_text(), 'original theme')
        self.assertEqual(unrelated.read_text(), 'keep this')

    def test_repeated_install_has_distinct_backups(self):
        for _ in range(2):
            result = self.run_install()
            self.assertEqual(result.returncode, 0, result.stderr)
        backups = list((self.target / '.local/state/sway-rice/backups').iterdir())
        self.assertEqual(len(backups), 2)
        self.assertTrue(any((p / '.config/sway/config').is_file() for p in backups))

    def test_invalid_options_do_not_write(self):
        for args in [('--unknown',), ('--target-home',), ('--build-wallpaper-tools',)]:
            result = self.run_install(*args)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(self.target.exists())


if __name__ == '__main__':
    unittest.main()
