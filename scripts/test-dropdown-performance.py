#!/usr/bin/env python3
"""Exercise the performance gate with synthetic xcresult metric responses."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class DropdownPerformanceTests(unittest.TestCase):
    def gate(self, large, control, relative=False):
        with tempfile.TemporaryDirectory() as directory:
            tool = Path(directory) / "xcrun"
            tool.write_text(
                "#!" + sys.executable + "\nimport json, sys\n"
                + "samples = " + repr({"large": large, "control": control}) + "\n"
                + "values = samples['control' if 'SmallHistory' in sys.argv[-1] else 'large']\n"
                + "print(json.dumps([{'testRuns': [{'metrics': [{'identifier': "
                + "'com.apple.dt.XCTMetric_CPU-house.thezoo.babytrack.time', "
                + "'measurements': values}]}]}]))\n"
            )
            tool.chmod(0o755)
            environment = dict(os.environ, PATH=directory + os.pathsep + os.environ["PATH"])
            command = [sys.executable, str(Path(__file__).with_name("check-ios-dropdown-performance")), "synthetic.xcresult"]
            if relative:
                command.append("--relative")
            return subprocess.run(command, env=environment, capture_output=True, text=True)

    def test_one_slow_recorded_interaction_cannot_be_hidden_by_the_mean(self):
        result = self.gate([0.9] + [0.28] * 9, [0.28] * 10)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("local CPU budget", result.stderr)

    def test_slow_control_samples_cannot_inflate_the_relative_budget(self):
        result = self.gate([0.44] * 5, [0.28, 0.9, 0.8, 0.7, 0.6], relative=True)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("excessive UI work", result.stderr)

    def test_consistently_fast_interactions_pass_both_gates(self):
        for relative in (False, True):
            with self.subTest(relative=relative):
                result = self.gate([0.29] * 5, [0.28] * 5, relative=relative)
                self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
