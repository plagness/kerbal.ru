#!/usr/bin/env python3
"""Advance the project release in data/project.json and sync consumers.

With no argument, increments the sequence for the current calendar year:
  python3 tools/bump_release.py

An explicit release is useful for a controlled correction:
  python3 tools/bump_release.py v26.2
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA_PATH = ROOT / "data/project.json"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("version", nargs="?", help="версия вида v26.2; без неё номер увеличится сам")
    args = parser.parse_args()

    data = json.loads(DATA_PATH.read_text(encoding="utf-8"))
    today = dt.date.today()
    current = data["release"]
    if args.version:
        version = args.version
    else:
        sequence = current["sequence"] + 1 if current["year"] == today.year else 1
        version = f"v{today.year % 100:02d}.{sequence}"

    match = re.fullmatch(r"v(\d{2})\.([1-9]\d*)", version)
    if not match:
        parser.error("версия должна выглядеть как v26.2")
    year = 2000 + int(match.group(1))
    if year != today.year:
        parser.error(f"год версии должен быть текущим ({today.year})")

    current.update(
        {
            "version": version,
            "year": year,
            "sequence": int(match.group(2)),
            "date": today.isoformat(),
            "url": f"https://github.com/plagness/kerbal.ru/releases/tag/{version}",
        }
    )
    data["updatedAt"] = today.isoformat()
    DATA_PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    result = subprocess.run(
        [sys.executable, str(ROOT / "tools/sync_project_data.py"), "--write"],
        cwd=ROOT,
        check=False,
    )
    if result.returncode:
        return result.returncode
    print(f"release advanced: {version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
