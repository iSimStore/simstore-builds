"""Select only available iOS devices compatible with the app's actual minimum."""
from __future__ import annotations

import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from simulator import Simulators, main, parse_launch_pid, select_device, smoke_test


class SimulatorTests(unittest.TestCase):
    def setUp(self) -> None:
        work = tempfile.TemporaryDirectory()
        self.addCleanup(work.cleanup)
        self.app = Path(work.name) / 'Example.app'
        self.app.mkdir()
        self.simulators: Simulators = {
            'runtimes': [
                {'identifier': 'com.apple.CoreSimulator.SimRuntime.iOS-17-0', 'version': '17.0', 'isAvailable': True},
                {'identifier': 'com.apple.CoreSimulator.SimRuntime.iOS-27-0', 'version': '27.0', 'isAvailable': True},
                {'identifier': 'com.apple.CoreSimulator.SimRuntime.tvOS-28-0', 'version': '28.0', 'isAvailable': True},
            ],
            'devices': {
                'com.apple.CoreSimulator.SimRuntime.iOS-17-0': [
                    {'udid': 'old', 'state': 'Booted', 'isAvailable': True}],
                'com.apple.CoreSimulator.SimRuntime.iOS-27-0': [
                    {'udid': 'new', 'state': 'Shutdown', 'isAvailable': True}],
                'com.apple.CoreSimulator.SimRuntime.tvOS-28-0': [
                    {'udid': 'tv', 'state': 'Booted', 'isAvailable': True}],
            },
        }

    def test_selects_newest_compatible_ios_runtime(self) -> None:
        self.assertEqual(select_device(self.simulators, (17, 0, 0)), ('new', False))

    def test_prefers_booted_device_on_the_same_runtime(self) -> None:
        self.simulators['devices']['com.apple.CoreSimulator.SimRuntime.iOS-27-0'].append(
            {'udid': 'booted', 'state': 'Booted', 'isAvailable': True})
        self.assertEqual(select_device(self.simulators, (27, 0, 0)), ('booted', True))

    def test_skips_unavailable_devices(self) -> None:
        self.simulators['devices']['com.apple.CoreSimulator.SimRuntime.iOS-27-0'][0]['isAvailable'] = False
        self.assertEqual(select_device(self.simulators, (17, 0, 0)), ('old', True))

    def test_skips_unavailable_runtimes(self) -> None:
        self.simulators['runtimes'][1]['isAvailable'] = False
        self.assertEqual(select_device(self.simulators, (17, 0, 0)), ('old', True))

    def test_fails_if_no_compatible_ios_device_exists(self) -> None:
        with self.assertRaisesRegex(ValueError, 'No available iOS Simulator'):
            select_device(self.simulators, (28, 0, 0))

    def test_parses_pid_from_main_ci_launch_format(self) -> None:
        self.assertEqual(parse_launch_pid('org.videolan.vlc-ios: 22551\n', 'org.videolan.vlc-ios'), 22551)

    def test_rejects_missing_invalid_or_ambiguous_launch_pid(self) -> None:
        for output in ('', 'launched', 'org.simstore.example: 0', 'org.simstore.example: -12',
                       'org.other.example: 22551', 'org.simstore.example: 22551 extra',
                       'org.simstore.example: 22551\norg.simstore.example: 22552'):
            with self.subTest(output=output), self.assertRaises(ValueError):
                parse_launch_pid(output, 'org.simstore.example')

    def test_startup_check_accepts_a_living_process(self) -> None:
        with subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)']) as process:
            try:
                output = f'org.simstore.example: {process.pid}\n'
                with patch('simulator.validate', return_value=({'CFBundleIdentifier': 'org.simstore.example'}, [], (17, 0, 0))), \
                     patch('simulator.subprocess.run', return_value=subprocess.CompletedProcess([], 0, stdout=output)), \
                     patch('simulator.sleep') as sleep, \
                     patch('sys.stdout', new_callable=io.StringIO) as stdout:
                    smoke_test(self.app, target='booted')
                    sleep.assert_called_once_with(30)
                    self.assertIn(output.strip(), stdout.getvalue())
                    self.assertIn(f'PID {process.pid} is still alive after 30 seconds', stdout.getvalue())
            finally:
                process.terminate()

    def test_process_exiting_during_startup_fails_the_cli(self) -> None:
        with subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)']) as process:
            try:
                def exit_during_wait(seconds: float) -> None:
                    process.terminate()
                    process.wait(timeout=5)

                output = f'org.simstore.example: {process.pid}\n'
                with patch('simulator.validate', return_value=({'CFBundleIdentifier': 'org.simstore.example'}, [], (17, 0, 0))), \
                     patch('simulator.subprocess.run', return_value=subprocess.CompletedProcess([], 0, stdout=output)), \
                     patch('simulator.sleep', side_effect=exit_during_wait) as sleep, \
                     patch('sys.argv', ['simulator.py', str(self.app), 'booted']), \
                     patch('sys.stdout', new_callable=io.StringIO), \
                     patch('sys.stderr', new_callable=io.StringIO) as stderr:
                    self.assertEqual(main(), 1)
                    sleep.assert_called_once_with(30)
                    self.assertIn(f'PID {process.pid}', stderr.getvalue())
                    self.assertIn('exited before the 30-second startup check', stderr.getvalue())
            finally:
                process.terminate()

    def test_launch_deadline_allows_four_minutes_but_rejects_more_than_five(self) -> None:
        with subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)']) as process:
            try:
                for duration, expected in ((240, 0), (301, 1)):
                    with self.subTest(duration=duration):
                        def run_simctl(command: list[str], *, check: bool, timeout: int,
                                       stdout: int | None = None, text: bool = False,
                                       duration: int = duration) -> subprocess.CompletedProcess[str]:
                            if command[2] == 'launch' and duration > timeout:
                                raise subprocess.TimeoutExpired(command, timeout)
                            return subprocess.CompletedProcess(command, 0, stdout=f'org.simstore.example: {process.pid}\n')

                        with patch('simulator.validate', return_value=({'CFBundleIdentifier': 'org.simstore.example'}, [], (17, 0, 0))), \
                             patch('simulator.subprocess.run', side_effect=run_simctl), \
                             patch('simulator.sleep') as sleep, \
                             patch('sys.argv', ['simulator.py', str(self.app), 'booted']), \
                             patch('sys.stdout', new_callable=io.StringIO), \
                             patch('sys.stderr', new_callable=io.StringIO) as stderr:
                            self.assertEqual(main(), expected)
                            if expected == 0:
                                sleep.assert_called_once_with(30)
                            else:
                                sleep.assert_not_called()
                                self.assertIn('timed out', stderr.getvalue())
            finally:
                process.terminate()

    def test_manifest_minimum_is_honored_before_booting(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / 'Example.app'
            app.mkdir()
            with patch('simulator.validate', return_value=({'CFBundleIdentifier': 'org.simstore.example'}, [], (17, 0, 0))), \
                 patch('simulator.check_manifest', return_value='28.0'), \
                 patch('simulator.subprocess.check_output', return_value=json.dumps(self.simulators)), \
                 patch('simulator.subprocess.run') as run:
                with self.assertRaisesRegex(ValueError, 'No available iOS Simulator'):
                    smoke_test(app, Path(temporary) / 'manifest.yaml')
                run.assert_not_called()

    def test_failed_launch_propagates(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / 'Example.app'
            app.mkdir()
            with patch('simulator.validate', return_value=({'CFBundleIdentifier': 'org.simstore.example'}, [], (17, 0, 0))), \
                 patch('simulator.subprocess.check_output', return_value=json.dumps(self.simulators)), \
                 patch('simulator.subprocess.run') as run:
                run.side_effect = [subprocess.CompletedProcess([], 0), subprocess.CompletedProcess([], 0),
                                   subprocess.CompletedProcess([], 0), subprocess.CalledProcessError(1, 'simctl launch')]
                with self.assertRaises(subprocess.CalledProcessError):
                    smoke_test(app)


if __name__ == '__main__':
    unittest.main()
