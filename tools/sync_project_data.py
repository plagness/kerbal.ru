#!/usr/bin/env python3
"""Validate project data and sync its generated Markdown/version consumers.

Usage:
  python3 tools/sync_project_data.py --write
  python3 tools/sync_project_data.py --check

The JSON is the source of truth. The website reads it at runtime; this script
keeps GitHub-rendered files and the release VERSION marker in lockstep.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA_PATH = ROOT / "data/project.json"
README_PATH = ROOT / "README.md"
VERSION_PATH = ROOT / "VERSION"
CITATION_PATH = ROOT / "CITATION.cff"

START = "<!-- project-data:start -->"
END = "<!-- project-data:end -->"
FIELDS = ("title", "description", "manufacturer")


def percent(translated: int, total: int) -> float:
    return round(100 * translated / total, 1) if total else 0.0


def ru_percent(value: float) -> str:
    if value.is_integer():
        return f"{int(value)}%"
    return f"{value:.1f}%".replace(".", ",")


def spaced(value: int) -> str:
    return f"{value:,}".replace(",", " ")


def load_and_validate() -> dict:
    data = json.loads(DATA_PATH.read_text(encoding="utf-8"))
    errors: list[str] = []

    release = data.get("release", {})
    version = release.get("version", "")
    match = re.fullmatch(r"v(\d{2})\.([1-9]\d*)", version)
    if not match:
        errors.append("release.version должен выглядеть как v26.1")
    else:
        if release.get("year") != 2000 + int(match.group(1)):
            errors.append("release.year не совпадает с годом в версии")
        if release.get("sequence") != int(match.group(2)):
            errors.append("release.sequence не совпадает с номером в версии")

    inventory = data.get("inventory", {})
    russian_sum = (
        inventory.get("kerbalRuMods", 0)
        + inventory.get("upstreamRussianMods", 0)
        + inventory.get("stockRussian", 0)
    )
    if inventory.get("withRussian") != russian_sum:
        errors.append("inventory.withRussian не равен сумме источников русского")
    classified = (
        inventory.get("withRussian", 0)
        + inventory.get("translationCandidates", 0)
        + inventory.get("serviceComponents", 0)
    )
    if inventory.get("components") != classified:
        errors.append("inventory.components не равен сумме категорий")

    coverage = data.get("coverage", {})
    active = coverage.get("active")
    if active not in {"verified", "projected"}:
        errors.append("coverage.active должен быть verified или projected")

    mods = data.get("mods", {})
    for stage_name in ("verified", "projected"):
        stage = coverage.get(stage_name, {})
        total_parts = sum(mod.get("parts", 0) for mod in mods.values())
        if stage.get("parts") != total_parts:
            errors.append(f"coverage.{stage_name}.parts не равен сумме деталей модов")
        for field in FIELDS:
            translated = sum(
                mod.get(stage_name, mod.get("verified", {})).get(field, 0)
                for mod in mods.values()
            )
            field_data = stage.get("fields", {}).get(field, {})
            if field_data.get("translated") != translated:
                errors.append(f"coverage.{stage_name}.{field} не равен сумме модов")
            expected = percent(translated, total_parts)
            if field_data.get("percent") != expected:
                errors.append(
                    f"coverage.{stage_name}.{field}.percent должен быть {expected}"
                )

    for mod_name, mod in mods.items():
        parts = mod.get("parts", 0)
        if mod.get("audit") == "not-applicable":
            if parts != 0:
                errors.append(f"{mod_name}: not-applicable должен иметь 0 деталей")
            continue
        for stage_name in ("verified", "projected"):
            counts = mod.get(stage_name, mod.get("verified", {}))
            for field in FIELDS:
                value = counts.get(field, 0)
                if not 0 <= value <= parts:
                    errors.append(f"{mod_name}.{stage_name}.{field} вне диапазона")

    if errors:
        raise ValueError("\n".join(f"- {error}" for error in errors))
    return data


def generated_readme_block(data: dict) -> str:
    release = data["release"]
    inventory = data["inventory"]
    coverage = data["coverage"]
    active = coverage[coverage["active"]]
    verified = coverage["verified"]
    composition = percent(inventory["withRussian"], inventory["components"])

    title = active["fields"]["title"]
    description = active["fields"]["description"]
    manufacturer = active["fields"]["manufacturer"]
    verified_fields = verified["fields"]

    return "\n".join(
        [
            START,
            "| Что измеряем | Сейчас | Источник |",
            "|---|---:|---|",
            f'| Версия русификатора | **[{release["version"]}]({release["url"]})** | `data/project.json` |',
            f'| Поддерживаемые нами моды | **{inventory["kerbalRuMods"]}** | Собственные `ru.cfg` и MM-патчи |',
            f'| Состав с русским блоком | **{inventory["withRussian"]} / {inventory["components"]} · {ru_percent(composition)}** | Полная инвентаризация `GameData` |',
            f'| Проверено деталей | **{spaced(active["parts"])}** | `ModuleManager.ConfigCache` |',
            f'| Названия деталей | **{ru_percent(title["percent"])} · {title["translated"]}/{active["parts"]}** | {active["label"]} |',
            f'| Описания деталей | **{ru_percent(description["percent"])} · {description["translated"]}/{active["parts"]}** | {active["label"]} |',
            f'| Производители | **{ru_percent(manufacturer["percent"])} · {manufacturer["translated"]}/{active["parts"]}** | {active["label"]} |',
            "",
            f'> Активные показатели: **{active["label"].lower()}** от {active["auditedAt"]}. '
            f'Последняя подтверждённая кэшем база: **{ru_percent(verified_fields["title"]["percent"])} названий / '
            f'{ru_percent(verified_fields["description"]["percent"])} описаний / '
            f'{ru_percent(verified_fields["manufacturer"]["percent"])} производителей**. '
            "[Методика и таблица по модам →](docs/COVERAGE.md)",
            END,
        ]
    )


def replace_block(text: str, replacement: str) -> str:
    pattern = re.compile(re.escape(START) + r"[\s\S]*?" + re.escape(END))
    if not pattern.search(text):
        raise ValueError("В README.md не найдены project-data markers")
    return pattern.sub(replacement, text, count=1)


def expected_files(data: dict) -> dict[Path, str]:
    readme = replace_block(README_PATH.read_text(encoding="utf-8"), generated_readme_block(data))
    version = data["release"]["version"].removeprefix("v") + "\n"
    citation = CITATION_PATH.read_text(encoding="utf-8")
    citation = re.sub(r"(?m)^version: .*?$", f"version: {version.strip()}", citation, count=1)
    citation = re.sub(
        r"(?m)^date-released: .*?$",
        f'date-released: {data["release"]["date"]}',
        citation,
        count=1,
    )
    return {README_PATH: readme, VERSION_PATH: version, CITATION_PATH: citation}


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    args = parser.parse_args()

    try:
        data = load_and_validate()
        expected = expected_files(data)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"project data invalid:\n{error}", file=sys.stderr)
        return 1

    stale: list[Path] = []
    for path, content in expected.items():
        current = path.read_text(encoding="utf-8") if path.exists() else ""
        if current == content:
            continue
        stale.append(path)
        if args.write:
            path.write_text(content, encoding="utf-8")
            print(f"updated {path.relative_to(ROOT)}")

    if args.check and stale:
        print("Generated project data is stale:", file=sys.stderr)
        for path in stale:
            print(f"- {path.relative_to(ROOT)}", file=sys.stderr)
        print("Run: python3 tools/sync_project_data.py --write", file=sys.stderr)
        return 1

    if not stale:
        print("project data: in sync")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
