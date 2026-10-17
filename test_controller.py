import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class TickContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.base = self.home / '.config/battery-home'
        self.base.mkdir(parents=True)
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        self.commands = self.home / 'commands'
        self.commands.write_text('')
        self.write_executable('open', '[[ "$*" == *Discharge* ]] && echo discharge >> "$HOME/commands" || echo "open $*" >> "$HOME/commands"')
        self.write_executable('sleep', ':')
        self.write_executable('caffeinate', ':')
        self.write_executable('ipconfig', 'cat "$HOME/gateway"')
        self.write_executable('pmset', 'echo " -InternalBattery-0 80%; discharging"')
        self.base.joinpath('config').write_text(f'HOME_GATEWAY="home"\nCAFFEINATE_CLI="{self.bin / "caffeinate"}"\n')
        self.base.joinpath('calendar-url').write_text('synthetic')
        self.base.joinpath('venv/bin').mkdir(parents=True)
        p = self.base / 'venv/bin/python'
        p.write_text('#!/bin/zsh\ncat "$HOME/mode"\n'); p.chmod(0o755)
        self.home.joinpath('gateway').write_text('home')
        self.home.joinpath('mode').write_text('home')

    def write_executable(self, name, code):
        p = self.bin / name
        p.write_text('#!/bin/zsh\n' + code + '\n'); p.chmod(0o755)

    def tick(self, previous, mode='home', gateway='home'):
        self.home.joinpath('.battery-home-state').write_text(previous)
        self.home.joinpath('mode').write_text(mode)
        self.home.joinpath('gateway').write_text(gateway)
        self.commands.write_text('')
        r = subprocess.run(['/bin/zsh', str(Path(__file__).with_name('battery-home.sh'))],
                           env={**os.environ, 'HOME': str(self.home), 'PATH': str(self.bin) + ':/usr/bin:/bin:/usr/sbin:/sbin'},
                           text=True, capture_output=True)
        return r, self.commands.read_text(), self.home.joinpath('.battery-home-state').read_text().strip()

    def test_charging_window_interrupts_home_discharge(self):
        r, log, state = self.tick('home-discharge', 'prepare')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('aldente://limit/100', log)
        self.assertNotIn('discharge', log)
        self.assertEqual(state, 'prepare')

    def test_end_of_charge_window_drains_to_home_limit(self):
        r, log, state = self.tick('prepare', 'home')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('aldente://limit/50', log)
        self.assertIn('discharge', log)
        self.assertEqual(state, 'home-discharge')

    def test_return_home_starts_aldente_discharge(self):
        r, log, state = self.tick('away', 'home')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('discharge', log)
        self.assertEqual(state, 'home-discharge')

    def test_discharge_continues_until_limit(self):
        r, log, state = self.tick('home-discharge', 'home')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(log, '')
        self.assertEqual(state, 'home-discharge')

    def test_discharge_ends_at_limit(self):
        self.write_executable('pmset', 'echo " -InternalBattery-0 50%; AC attached; not charging"')
        _, _, state = self.tick('home-discharge', 'home')
        self.assertEqual(state, 'home')

    def test_lost_gateway_or_expired_calendar_leaves_discharge_state(self):
        for mode, gateway in [('home', ''), ('unknown', 'home')]:
            with self.subTest(mode=mode, gateway=gateway):
                _, _, state = self.tick('home-discharge', mode, gateway)
                self.assertEqual(state, 'home')

    def test_failed_limit_change_retries_next_tick(self):
        self.write_executable('open', 'exit 1')
        r, _, state = self.tick('home', 'prepare')
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(state, 'home')


if __name__ == '__main__':
    unittest.main()
