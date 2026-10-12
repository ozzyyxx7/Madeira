#!/usr/bin/env python3
"""Compare a local Madeira.app with a reference release IPA.

The exit status is nonzero when a file in the reference app is missing from
the local app. Content differences are reported for review because a fork's
code, signing, and locally rebuilt libraries are expected to differ.
"""

import argparse
from pathlib import Path
import sys
import zipfile
import zlib


def crc32_file(path: Path) -> int:
    crc = 0
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            crc = zlib.crc32(chunk, crc)
    return crc


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference_ipa", type=Path)
    parser.add_argument("app_bundle", type=Path)
    args = parser.parse_args()

    if not args.app_bundle.is_dir():
        parser.error(f"app bundle does not exist: {args.app_bundle}")

    with zipfile.ZipFile(args.reference_ipa) as archive:
        roots = {
            "/".join(item.filename.split("/")[:2]) + "/"
            for item in archive.infolist()
            if item.filename.startswith("Payload/")
            and len(item.filename.split("/")) > 2
            and item.filename.split("/")[1].endswith(".app")
        }
        if len(roots) != 1:
            parser.error(f"expected one app in IPA, found {len(roots)}")
        root = roots.pop()
        reference = {
            item.filename[len(root) :]: item
            for item in archive.infolist()
            if item.filename.startswith(root) and not item.is_dir()
        }

    local = {
        str(path.relative_to(args.app_bundle)): path
        for path in args.app_bundle.rglob("*")
        if path.is_file()
    }
    missing = sorted(reference.keys() - local.keys())
    extra = sorted(local.keys() - reference.keys())
    different = sorted(
        name
        for name in reference.keys() & local.keys()
        if reference[name].file_size != local[name].stat().st_size
        or reference[name].CRC != crc32_file(local[name])
    )

    print(
        f"reference={len(reference)} local={len(local)} "
        f"missing={len(missing)} extra={len(extra)} different={len(different)}"
    )
    for label, names in (("MISSING", missing), ("EXTRA", extra), ("DIFFERENT", different)):
        for name in names:
            print(f"{label} {name}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
