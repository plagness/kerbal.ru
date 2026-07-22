#!/usr/bin/env python3
"""Audit Russian part coverage in the final ModuleManager.ConfigCache.

Examples:
  python3 tools/audit_ru_coverage.py "/path/to/Kerbal Space Program"
  python3 tools/audit_ru_coverage.py --json
  python3 tools/audit_ru_coverage.py --write-project-data data/project.json

The last form updates the authoritative verified counters, per-mod counters and
audit date, then switches the website from a projection to live-cache data.
Run tools/sync_project_data.py --write afterwards to refresh README/VERSION.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PROJECT_DATA = ROOT / "data/project.json"
_CANDIDATES = [
    os.path.expanduser("~/.local/share/Steam/steamapps/common/Kerbal Space Program"),
    os.path.expanduser("~/.steam/steam/steamapps/common/Kerbal Space Program"),
    os.path.expanduser("~/Library/Application Support/Steam/steamapps/common/Kerbal Space Program"),
]

OURS_FULL = [
    "AJE",
    "BackgroundThrust",
    "ContractConfigurator",
    "EditorExtensionsRedux",
    "KerbalChangelog",
    "KerbalEngineer",
    "ROCapsules",
    "RealismOverhaul",
    "SXT",
    "SpaceTuxLibrary",
    "Trajectories",
    "VenStockRevamp",
]
OURS_PATCH = [
    "ModularLaunchPads",
    "ProceduralFairings",
    "ProceduralParts",
    "ROEngines",
    "ROHeatshields",
    "ROSolar",
    "ROTanks",
    "RealChute",
]
OURS = OURS_FULL + OURS_PATCH

CYR = re.compile(r"[а-яА-ЯёЁ]")
PART_HEADER = re.compile(r"^[ \t]*([+@!%])?PART(?:\[([^\]]+)\])?(?=[\s{]|$)", re.MULTILINE)
FIELD = re.compile(r"^[ \t]*([A-Za-z]+)\s*=\s*(.*?)\s*$")


def has_cyr(value: str | None) -> bool:
    return bool(value) and bool(CYR.search(value))


def owned_part_names(mod_dir: str) -> set[str]:
    """Return real part names declared or edited by a mod."""
    names: set[str] = set()
    for root, _dirs, files in os.walk(mod_dir):
        if "Localization" in root.split(os.sep):
            continue
        for filename in files:
            if not filename.lower().endswith(".cfg"):
                continue
            path = os.path.join(root, filename)
            try:
                text = Path(path).read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            for match in PART_HEADER.finditer(text):
                prefix, bracket = match.group(1), match.group(2)
                if prefix == "@" and bracket:
                    names.add(bracket)
                    continue
                snippet = text[match.end() : match.end() + 3000]
                part_name = re.search(r"(?<![A-Za-z])name\s*=\s*([^\s{}]+)", snippet)
                if part_name:
                    names.add(part_name.group(1).strip())
                elif bracket:
                    names.add(bracket)
    return names


def parse_cache(path: str) -> dict[str, dict[str, str | None]]:
    """Parse the final cache into name -> translated fields."""
    parts: dict[str, dict[str, str | None]] = {}
    lines = Path(path).read_text(encoding="utf-8", errors="replace").splitlines()
    total_lines = len(lines)
    index = 0
    while index < total_lines:
        if lines[index].strip() != "PART":
            index += 1
            continue
        cursor = index + 1
        while cursor < total_lines and lines[cursor].strip() != "{":
            if lines[cursor].strip():
                break
            cursor += 1
        if cursor >= total_lines or lines[cursor].strip() != "{":
            index += 1
            continue
        depth = 1
        cursor += 1
        name = title = description = manufacturer = None
        while cursor < total_lines and depth > 0:
            line = lines[cursor].strip()
            if line == "{":
                depth += 1
            elif line == "}":
                depth -= 1
                if depth == 0:
                    break
            elif depth == 1:
                field_match = FIELD.match(lines[cursor])
                if field_match:
                    key, value = field_match.group(1), field_match.group(2)
                    if key == "name" and name is None:
                        name = value
                    elif key == "title" and title is None:
                        title = value
                    elif key == "description" and description is None:
                        description = value
                    elif key == "manufacturer" and manufacturer is None:
                        manufacturer = value
            cursor += 1
        if name:
            parts[name] = {
                "title": title,
                "description": description,
                "manufacturer": manufacturer,
            }
        index = cursor
    return parts


def audit(game_data: str, cache_path: str) -> tuple[list[dict], dict, int]:
    print(f"Разбираю кэш: {cache_path}", file=sys.stderr)
    cache_parts = parse_cache(cache_path)
    print(f"Партов в кэше всего: {len(cache_parts)}", file=sys.stderr)

    rows: list[dict] = []
    totals = {"parts": 0, "title": 0, "description": 0, "manufacturer": 0, "missing": 0}
    for mod in OURS:
        mod_dir = os.path.join(game_data, mod)
        if not os.path.isdir(mod_dir):
            rows.append(
                {
                    "mod": mod,
                    "parts": 0,
                    "title": 0,
                    "description": 0,
                    "manufacturer": 0,
                    "missing": 0,
                    "examples": [],
                    "folderMissing": True,
                }
            )
            continue

        owned = owned_part_names(mod_dir)
        counts = {"title": 0, "description": 0, "manufacturer": 0}
        missing = 0
        examples: list[str] = []
        for part_name in owned:
            entry = cache_parts.get(part_name)
            if entry is None:
                missing += 1
                continue
            for field in ("title", "description", "manufacturer"):
                if has_cyr(entry[field]):
                    counts[field] += 1
            if not has_cyr(entry["title"]) and entry["title"] and len(examples) < 3:
                examples.append(f'{part_name}: title="{entry["title"]}"')

        row = {
            "mod": mod,
            "parts": len(owned),
            **counts,
            "missing": missing,
            "examples": examples,
            "folderMissing": False,
        }
        rows.append(row)
        totals["parts"] += row["parts"]
        totals["title"] += row["title"]
        totals["description"] += row["description"]
        totals["manufacturer"] += row["manufacturer"]
        totals["missing"] += row["missing"]

    return rows, totals, len(cache_parts)


def result_payload(rows: list[dict], totals: dict, cache_parts: int) -> dict:
    parts = totals["parts"]
    return {
        "auditedAt": dt.date.today().isoformat(),
        "cacheParts": cache_parts,
        "totals": {
            **totals,
            "percent": {
                field: round(100 * totals[field] / parts, 1) if parts else 0.0
                for field in ("title", "description", "manufacturer")
            },
        },
        "mods": rows,
    }


def print_table(payload: dict) -> None:
    headers = ["мод", "парт", "title-ru", "desc-ru", "manuf-ru", "нет-в-кэше", "примеры НЕ-ru title"]
    widths = [22, 6, 9, 8, 9, 10, 60]
    print("".join(header.ljust(width) for header, width in zip(headers, widths)))
    for row in payload["mods"]:
        examples = "нет папки" if row["folderMissing"] else "; ".join(row["examples"])
        values = [
            row["mod"],
            str(row["parts"]),
            str(row["title"]),
            str(row["description"]),
            str(row["manufacturer"]),
            str(row["missing"]),
            examples,
        ]
        print("".join(value.ljust(width) for value, width in zip(values, widths)))
    totals = payload["totals"]
    print(
        "".join(
            value.ljust(width)
            for value, width in zip(
                [
                    "ИТОГО",
                    str(totals["parts"]),
                    str(totals["title"]),
                    str(totals["description"]),
                    str(totals["manufacturer"]),
                    str(totals["missing"]),
                    "",
                ],
                widths,
            )
        )
    )
    print()
    for field, label in (
        ("title", "title"),
        ("description", "description"),
        ("manufacturer", "manufacturer"),
    ):
        print(f'Общий процент партов с русским {label}: {totals["percent"][field]:.1f}%')


def update_project_data(path: Path, payload: dict) -> None:
    missing_folders = [row["mod"] for row in payload["mods"] if row["folderMissing"]]
    if missing_folders:
        raise ValueError("Нельзя обновить project.json: отсутствуют папки " + ", ".join(missing_folders))

    project = json.loads(path.read_text(encoding="utf-8"))
    totals = payload["totals"]
    verified = project["coverage"]["verified"]
    verified.update(
        {
            "label": "Подтверждено игровым кэшем",
            "status": "cache-verified",
            "auditedAt": payload["auditedAt"],
            "parts": totals["parts"],
            "cacheParts": payload["cacheParts"],
        }
    )
    for field in ("title", "description", "manufacturer"):
        verified["fields"][field] = {
            "translated": totals[field],
            "percent": totals["percent"][field],
        }

    for row in payload["mods"]:
        mod = project["mods"].setdefault(row["mod"], {})
        mod["parts"] = row["parts"]
        if row["parts"] == 0:
            mod["audit"] = "not-applicable"
            mod.pop("verified", None)
        else:
            if row["mod"] != "RealismOverhaul":
                mod.pop("audit", None)
            mod["verified"] = {
                field: row[field] for field in ("title", "description", "manufacturer")
            }

    project["coverage"]["active"] = "verified"
    project["updatedAt"] = payload["auditedAt"]
    path.write_text(json.dumps(project, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Обновлено: {path}", file=sys.stderr)


def resolve_ksp(explicit_path: str | None) -> str:
    if explicit_path:
        return os.path.expanduser(explicit_path)
    return next(
        (candidate for candidate in _CANDIDATES if os.path.isdir(os.path.join(candidate, "GameData"))),
        _CANDIDATES[0],
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("ksp", nargs="?", help="путь к Kerbal Space Program")
    parser.add_argument("--json", action="store_true", help="вывести машиночитаемый результат")
    parser.add_argument(
        "--write-project-data",
        nargs="?",
        const=str(DEFAULT_PROJECT_DATA),
        metavar="PATH",
        help="обновить verified-метрики project.json и сделать их активными",
    )
    args = parser.parse_args()

    ksp = resolve_ksp(args.ksp)
    game_data = os.path.join(ksp, "GameData")
    cache_path = os.path.join(game_data, "ModuleManager.ConfigCache")
    if not os.path.isfile(cache_path):
        print(f"Не найден игровой кэш: {cache_path}", file=sys.stderr)
        return 1

    try:
        rows, totals, cache_parts = audit(game_data, cache_path)
        payload = result_payload(rows, totals, cache_parts)
        if args.json:
            print(json.dumps(payload, ensure_ascii=False, indent=2))
        else:
            print_table(payload)
        if args.write_project_data:
            update_project_data(Path(args.write_project_data).resolve(), payload)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"Ошибка аудита: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
