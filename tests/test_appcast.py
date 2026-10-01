# SPDX-License-Identifier: MIT
"""Verify that release packaging rejects inconsistent or unsigned metadata."""

import base64
import importlib.util
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
SCRIPT = Path(__file__).resolve().parents[1] / "scripts/verify-orbis-appcast.py"
SPEC = importlib.util.spec_from_file_location("verify_appcast", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class AppcastTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.plist = root / "Info.plist"
        self.feed = root / "appcast.xml"
        self.archive = root / "Orbis-v2026.09.30.1-macos-universal.zip"
        self.archive.write_bytes(b"test archive")
        self.info = {
            "CFBundleShortVersionString": "2026.09.30", "CFBundleVersion": "20260930.1",
            "SUPublicEDKey": base64.b64encode(bytes(32)).decode(),
            "SURequireSignedFeed": True, "SUVerifyUpdateBeforeExtraction": True,
            "LSMinimumSystemVersion": "15.0",
        }
        self.root = ET.Element("rss")
        self.item = ET.SubElement(ET.SubElement(self.root, "channel"), "item")
        for key, value in (("version", "20260930.1"), ("shortVersionString", "2026.09.30"),
                           ("minimumSystemVersion", "15.0")):
            ET.SubElement(self.item, MODULE.SPARKLE + key).text = value
        self.enclosure = ET.SubElement(self.item, "enclosure", {
            "url": "https://github.com/j0nl1/orbis/releases/download/v2026.09.30.1/" + self.archive.name,
            "length": str(self.archive.stat().st_size),
            MODULE.SPARKLE + "edSignature": base64.b64encode(bytes(64)).decode(),
        })

    def verify(self):
        self.plist.write_bytes(plistlib.dumps(self.info))
        ET.ElementTree(self.root).write(self.feed)
        MODULE.verify(self.plist, self.feed, self.archive, "v2026.09.30.1")

    def test_consistent_metadata_is_accepted(self):
        self.verify()

    def test_rejects_wrong_bundle_version(self):
        self.info["CFBundleVersion"] = "20260930.2"
        with self.assertRaises(ValueError):
            self.verify()

    def test_rejects_missing_archive_signature(self):
        del self.enclosure.attrib[MODULE.SPARKLE + "edSignature"]
        with self.assertRaises(ValueError):
            self.verify()

    def test_rejects_wrong_release_url(self):
        self.enclosure.set("url", "https://example.com/update.zip")
        with self.assertRaises(ValueError):
            self.verify()

    def test_rejects_incorrect_archive_size(self):
        self.enclosure.set("length", "1")
        with self.assertRaises(ValueError):
            self.verify()

    def test_rejects_disabled_feed_verification(self):
        self.info["SURequireSignedFeed"] = False
        with self.assertRaises(ValueError):
            self.verify()

    def test_rejects_invalid_public_key(self):
        self.info["SUPublicEDKey"] = base64.b64encode(bytes(31)).decode()
        with self.assertRaises(ValueError):
            self.verify()

    def test_rejects_another_minimum_os(self):
        self.item.find(MODULE.SPARKLE + "minimumSystemVersion").text = "14.0"
        with self.assertRaises(ValueError):
            self.verify()


if __name__ == "__main__":
    unittest.main()
