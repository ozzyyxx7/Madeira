#!/usr/bin/env python3
"""Check direct DLL imports within Madeira's bundled Windows binaries."""

import argparse
from pathlib import Path
import re
import subprocess
import sys


ARCH_DIRS = ("i386-windows", "aarch64-windows", "arm64ec-windows")
IMPORT_PATTERN = re.compile(r"^\s*DLL Name:\s*(\S+)", re.MULTILINE)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle_root", type=Path, help="Madeira source or built .app folder")
    parser.add_argument("--objdump", type=Path, required=True, help="llvm-objdump executable")
    args = parser.parse_args()

    missing_total = 0
    for arch in ARCH_DIRS:
        folder = args.bundle_root / arch
        if not folder.is_dir():
            parser.error(f"missing binary directory: {folder}")
        names = {path.name.lower() for path in folder.iterdir() if path.is_file()}
        scanned = imports = missing = 0
        for path in sorted(folder.iterdir()):
            if not path.is_file() or path.name.startswith("."):
                continue
            result = subprocess.run(
                [str(args.objdump), "-p", str(path)],
                capture_output=True,
                text=True,
                check=False,
            )
            if result.returncode:
                continue  # A few resources are not PE files.
            scanned += 1
            for dependency in IMPORT_PATTERN.findall(result.stdout):
                imports += 1
                name = dependency.lower()
                if name.startswith(("api-ms-win-", "ext-ms-win-")):
                    continue  # Resolved through Windows API-set mappings.
                if name not in names:
                    print(f"MISSING {arch}/{path.name} -> {dependency}")
                    missing += 1
        missing_total += missing
        print(f"{arch}: PE={scanned} imports={imports} missing={missing}")
    return 1 if missing_total else 0


if __name__ == "__main__":
    sys.exit(main())
