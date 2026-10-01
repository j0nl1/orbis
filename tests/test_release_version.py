# SPDX-License-Identifier: MIT
"""Exercise release ordering and malformed inputs without contacting GitHub."""

import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
SCRIPT = Path(__file__).resolve().parents[1] / "scripts/orbis-release-version.py"
SPEC = importlib.util.spec_from_file_location("release_version", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ReleaseVersionTests(unittest.TestCase):
    def test_build_number_orders_revisions_and_dates(self):
        first = MODULE.release_version("v2026.09.30.1")
        second = MODULE.release_version("v2026.09.30.10")
        tomorrow = MODULE.release_version("v2026.10.01.1")
        self.assertEqual(first[:2], ("2026.09.30", "20260930.1"))
        self.assertLess(first[2], second[2])
        self.assertLess(second[2], tomorrow[2])

    def test_rejects_invalid_dates_and_ambiguous_tags(self):
        for tag in ("v2026.02.30.1", "v2026.9.30.1", "v2026.09.30.0",
                    "v2026.09.30.01", "v2026.09.30.1-beta", "v2026.09.30.10000"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                MODULE.release_version(tag)

    def test_cli_rejects_duplicate_and_older_releases(self):
        for tag in ("v2026.09.30.1", "v2026.09.29.5"):
            result = subprocess.run(
                [sys.executable, str(SCRIPT), tag, "--previous-tag", "v2026.09.30.1"],
                capture_output=True, text=True, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")

    def test_cli_emits_environment_values_for_newer_release(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "v2026.09.30.2", "--previous-tag", "v2026.09.30.1"],
            capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout, "ORBIS_VERSION=2026.09.30\nORBIS_BUILD_NUMBER=20260930.2\n")


if __name__ == "__main__":
    unittest.main()
