#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Validate release tags and derive a date version and an ordered build number."""

import argparse
import datetime
import re


def release_version(tag):
    match = re.fullmatch(r"v(20[0-9]{2})\.(\d{2})\.(\d{2})\.([1-9][0-9]{0,3})", tag)
    if not match:
        raise ValueError("Release tags must use vYYYY.MM.DD.N (N from 1 to 9999)")
    year, month, day, revision = map(int, match.groups())
    date = datetime.date(year, month, day)
    return date.strftime("%Y.%m.%d"), f"{date:%Y%m%d}.{revision}", (date, revision)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag")
    parser.add_argument("--previous-tag")
    args = parser.parse_args()
    try:
        version, build, order = release_version(args.tag)
        if args.previous_tag and order <= release_version(args.previous_tag)[2]:
            raise ValueError("The new release must be newer than the latest published release")
    except ValueError as error:
        parser.error(str(error))
    print(f"ORBIS_VERSION={version}")
    print(f"ORBIS_BUILD_NUMBER={build}")


if __name__ == "__main__":
    main()
