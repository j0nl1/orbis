#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Select or validate release tags and derive an ordered build number."""

import argparse
import datetime
from pathlib import Path
import re


def release_version(tag):
    match = re.fullmatch(r"v(20[0-9]{2})\.(\d{2})\.(\d{2})\.([1-9][0-9]{0,3})", tag)
    if not match:
        raise ValueError("Release tags must use vYYYY.MM.DD.N (N from 1 to 9999)")
    year, month, day, revision = map(int, match.groups())
    date = datetime.date(year, month, day)
    return date.strftime("%Y.%m.%d"), f"{date:%Y%m%d}.{revision}", (date, revision)


def next_release_tag(existing_tags, today):
    latest = (today, 0)
    for tag in existing_tags:
        try:
            order = release_version(tag.strip())[2]
        except ValueError:
            continue
        latest = max(latest, order)
    date, revision = latest
    if revision == 9999:
        raise ValueError("All release revisions for this date have been used")
    tag = f"v{date:%Y.%m.%d}.{revision + 1}"
    release_version(tag)
    return tag


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag", nargs="?")
    parser.add_argument("--next-tag", action="store_true")
    parser.add_argument("--existing-tags-file", type=Path)
    parser.add_argument("--previous-tag")
    args = parser.parse_args()
    if args.next_tag:
        if args.tag or not args.existing_tags_file:
            parser.error("--next-tag requires --existing-tags-file and no positional tag")
    elif not args.tag or args.existing_tags_file:
        parser.error("Supply a tag or use --next-tag with --existing-tags-file")
    try:
        tag = args.tag
        if args.next_tag:
            existing_tags = args.existing_tags_file.read_text().splitlines()
            if args.previous_tag:
                existing_tags.append(args.previous_tag)
            today = datetime.datetime.now(datetime.timezone.utc).date()
            tag = next_release_tag(existing_tags, today)
        version, build, order = release_version(tag)
        if args.previous_tag and order <= release_version(args.previous_tag)[2]:
            raise ValueError("The new release must be newer than the latest published release")
    except (ValueError, OSError) as error:
        parser.error(str(error))
    if args.next_tag:
        print(f"RELEASE_TAG={tag}")
    print(f"ORBIS_VERSION={version}")
    print(f"ORBIS_BUILD_NUMBER={build}")


if __name__ == "__main__":
    main()
