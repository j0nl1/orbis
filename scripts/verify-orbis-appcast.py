#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check the generated appcast against the packaged bundle before publishing."""

import base64
import importlib.util
import os
from pathlib import Path
import plistlib
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("release_version", Path(__file__).with_name("orbis-release-version.py"))
VERSION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERSION)
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def verify(plist_path, feed_path, archive_path, tag):
    with open(plist_path, "rb") as source:
        info = plistlib.load(source)
    version, build, _ = VERSION.release_version(tag)
    if (info.get("CFBundleShortVersionString"), info.get("CFBundleVersion")) != (version, build):
        raise ValueError("The packaged bundle version does not match the release tag")
    if len(base64.b64decode(info.get("SUPublicEDKey", ""), validate=True)) != 32:
        raise ValueError("The bundle is missing its Ed25519 public key")
    if not info.get("SURequireSignedFeed") or not info.get("SUVerifyUpdateBeforeExtraction"):
        raise ValueError("The bundle must verify both the feed and the archive")
    items = ET.parse(feed_path).findall("./channel/item")
    if len(items) != 1 or items[0].findtext(SPARKLE + "version") != build:
        raise ValueError("The appcast must contain exactly this release")
    item = items[0]
    if item.findtext(SPARKLE + "shortVersionString") != version:
        raise ValueError("The appcast display version does not match the bundle")
    if item.findtext(SPARKLE + "minimumSystemVersion") != info.get("LSMinimumSystemVersion"):
        raise ValueError("The appcast minimum OS does not match the bundle")
    enclosure = item.find("enclosure")
    repository = os.environ.get("ORBIS_GITHUB_REPOSITORY", "j0nl1/orbis")
    expected = f"https://github.com/{repository}/releases/download/{tag}/{Path(archive_path).name}"
    if enclosure is None or enclosure.get("url") != expected:
        raise ValueError("The archive URL must point to this release")
    if int(enclosure.get("length", "0")) != Path(archive_path).stat().st_size:
        raise ValueError("The appcast archive size is incorrect")
    if len(base64.b64decode(enclosure.get(SPARKLE + "edSignature", ""), validate=True)) != 64:
        raise ValueError("The update archive is missing an Ed25519 signature")


if __name__ == "__main__":
    try:
        verify(*sys.argv[1:])
    except (ValueError, TypeError, ET.ParseError) as error:
        sys.exit(str(error))
