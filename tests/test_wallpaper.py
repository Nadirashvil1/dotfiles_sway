from pathlib import Path
import json
import os
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/wallpaper'


class WallpaperTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sway-wallpaper-test-')
        self.root = Path(self.temp.name)
        self.images = self.root / 'images'
        self.images.mkdir()
        commands = self.root / 'bin'
        commands.mkdir()
        mock = commands / 'swaymsg'
        mock.write_text('#!/bin/sh\nprintf "%s\\n" "$1" > "$SWAY_TEST_COMMAND"\n')
        mock.chmod(0o755)
        self.env = dict(os.environ, SWAY_RICE_WALLPAPERS=str(self.images),
                        XDG_STATE_HOME=str(self.root / 'state'),
                        SWAY_TEST_COMMAND=str(self.root / 'command'),
                        PATH=str(commands) + os.pathsep + os.environ['PATH'])

    def tearDown(self):
        self.temp.cleanup()

    def run_action(self, action):
        result = subprocess.run(['bash', str(SCRIPT), action], env=self.env,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_start_next_previous_and_wrap(self):
        for name in ['a.png', 'b.png']:
            (self.images / name).touch()
        for action, name in [('start', 'a.png'), ('next', 'b.png'),
                             ('next', 'a.png'), ('previous', 'b.png')]:
            self.run_action(action)
            actual = (self.root / 'state/sway-rice/wallpaper').read_text().strip()
            self.assertEqual(actual, str(self.images / name))

    def test_filename_is_quoted_for_sway_ipc(self):
        image = self.images / 'a "quoted"; exec something.png'
        image.touch()
        self.run_action('start')
        command = (self.root / 'command').read_text().strip()
        self.assertEqual(command, 'output * bg ' + json.dumps(str(image)) + ' fill')

    def test_empty_directory_does_not_invoke_sway(self):
        self.run_action('start')
        self.assertFalse((self.root / 'command').exists())
        self.assertFalse((self.root / 'state').exists())
