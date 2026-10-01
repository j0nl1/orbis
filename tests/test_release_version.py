# SPDX-License-Identifier: MIT
"""Exercise release ordering and malformed inputs without contacting GitHub."""

import datetime
import importlib.util
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
SCRIPT = Path(__file__).resolve().parents[1] / "scripts/orbis-release-version.py"
SPEC = importlib.util.spec_from_file_location("release_version", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


@unittest.skipUnless(shutil.which("jq"), "Release query tests require jq")
class ReleaseQueryTests(unittest.TestCase):
    def run_query(self, query, pages, status=0):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = root / "releases.json"
            fixture.write_text(pages)
            gh = root / "gh"
            gh.write_text('#!/bin/sh\ncat "$RELEASE_QUERY_FIXTURE"\n'
                          'exit "${RELEASE_QUERY_STATUS:-0}"\n')
            gh.chmod(0o755)
            env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}",
                       GITHUB_REPOSITORY="test/orbis", RELEASE_QUERY_FIXTURE=str(fixture),
                       RELEASE_QUERY_STATUS=str(status))
            return subprocess.run(["bash", "-e", "-o", "pipefail", "-c", query],
                                  env=env, capture_output=True, text=True, check=False)

    def queries(self):
        workflow = SCRIPT.parents[1] / ".github/workflows/macos-release.yml"
        queries = re.findall(r'previous="\$\((.+)\)"', workflow.read_text())
        self.assertEqual(len(queries), 2, "Exercise both version and publication queries")
        return queries

    def test_query_handles_empty_and_paginated_releases(self):
        cases = [
            ("[]", "\n"),
            ('[{"draft":true,"prerelease":false,"tag_name":"draft"}]\n'
             '[{"draft":false,"prerelease":true,"tag_name":"beta"}]', "\n"),
            ('[{"draft":true,"prerelease":false,"tag_name":"draft"}]\n'
             '[{"draft":false,"prerelease":false,"tag_name":"v2026.10.01.3"}]\n'
             '[{"draft":false,"prerelease":false,"tag_name":"v2026.09.30.1"}]',
             "v2026.10.01.3\n"),
        ]
        for query in self.queries():
            for pages, expected in cases:
                with self.subTest(query=query, pages=pages):
                    result = self.run_query(query, pages)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, expected)

    def test_query_propagates_api_failure(self):
        for query in self.queries():
            result = self.run_query(query, "[]", status=1)
            self.assertNotEqual(result.returncode, 0)


class ReleaseVersionTests(unittest.TestCase):
    def test_first_automatic_release_uses_current_date(self):
        self.assertEqual(MODULE.next_release_tag([], datetime.date(2026, 10, 1)),
                         "v2026.10.01.1")

    def test_automatic_revision_uses_all_reserved_tags_in_numeric_order(self):
        tags = ["v2026.10.01.2", "v2026.10.01.10", "v2026.10.01.9",
                "v2026.10.01.10", "v2026.09.30.9999"]
        self.assertEqual(MODULE.next_release_tag(tags, datetime.date(2026, 10, 1)),
                         "v2026.10.01.11")

    def test_new_day_resets_revision(self):
        self.assertEqual(MODULE.next_release_tag(["v2026.09.30.9999"],
                                                datetime.date(2026, 10, 1)),
                         "v2026.10.01.1")

    def test_clock_does_not_generate_a_version_older_than_existing_tags(self):
        self.assertEqual(MODULE.next_release_tag(["v2026.10.02.5"],
                                                datetime.date(2026, 10, 1)),
                         "v2026.10.02.6")

    def test_automatic_release_ignores_unrelated_and_malformed_tags(self):
        tags = ["v1.0.0", "v2026.02.30.1", "v2026.10.01.01",
                "v2026.10.01.500-beta", "\n", " v2026.10.01.3 "]
        self.assertEqual(MODULE.next_release_tag(tags, datetime.date(2026, 10, 1)),
                         "v2026.10.01.4")

    def test_automatic_release_refuses_exhausted_revisions(self):
        with self.assertRaisesRegex(ValueError, "All release revisions"):
            MODULE.next_release_tag(["v2026.10.01.9999"], datetime.date(2026, 10, 1))

    def test_cli_selects_next_reserved_tag_and_emits_build_metadata(self):
        today = datetime.datetime.now(datetime.timezone.utc).date()
        tag_date = f"{today:%Y.%m.%d}"
        with tempfile.TemporaryDirectory() as directory:
            tags_file = Path(directory) / "tags.txt"
            tags_file.write_text(f"v{tag_date}.2\nv{tag_date}.10\n")
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--next-tag", "--existing-tags-file",
                 str(tags_file), "--previous-tag", f"v{tag_date}.12"],
                capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout, f"RELEASE_TAG=v{tag_date}.13\n"
                         f"ORBIS_VERSION={tag_date}\nORBIS_BUILD_NUMBER={today:%Y%m%d}.13\n")

    def test_cli_requires_explicit_selection_mode(self):
        for arguments in ([], ["--next-tag"], ["v2026.10.01.1", "--next-tag"],
                          ["--existing-tags-file", "missing.txt"],
                          ["--next-tag", "--existing-tags-file", "missing.txt"]):
            with self.subTest(arguments=arguments):
                result = subprocess.run([sys.executable, str(SCRIPT), *arguments],
                                        capture_output=True, text=True, check=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")

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
