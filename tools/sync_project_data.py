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


def plural_ru(value: int, one: str, few: str, many: str) -> str:
    n = abs(value) % 100
    if 11 <= n <= 14:
        return many
    n10 = n % 10
    if n10 == 1:
        return one
    if 2 <= n10 <= 4:
        return few
    return many


def load_and_validate() -> dict:
    data = json.loads(DATA_PATH.read_text(encoding="utf-8"))
    errors: list[str] = []

    if data.get("schemaVersion") != 3:
        errors.append("schemaVersion должен быть 3")

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
    mods = data.get("mods", {})
    if inventory.get("kerbalRuMods") != len(mods):
        errors.append("inventory.kerbalRuMods не равен числу записей в mods")
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

    site = data.get("site", {})
    content = site.get("content", {})
    for section_name in ("hero", "about", "mods", "roadmap", "nuances", "team", "footer"):
        if not isinstance(content.get(section_name), dict) or not content.get(section_name):
            errors.append(f"site.content.{section_name} должен быть непустым объектом")

    installation = site.get("installation", {})
    install_paths = installation.get("paths", [])
    install_by_id = {
        path.get("id"): path for path in install_paths if isinstance(path, dict)
    }
    if set(install_by_id) != {"full", "translation"}:
        errors.append("site.installation.paths должен содержать full и translation")
    for path_id, path in install_by_id.items():
        for field in (
            "title",
            "badge",
            "icon",
            "description",
            "requirements",
            "commands",
            "result",
        ):
            if not path.get(field):
                errors.append(f"site.installation.paths.{path_id}.{field} обязателен")
        if len(path.get("commands", [])) != 2:
            errors.append(
                f"site.installation.paths.{path_id}.commands должен содержать Unix и Windows"
            )
        for command in path.get("commands", []):
            if not command.get("platform") or not command.get("code"):
                errors.append(
                    f"site.installation.paths.{path_id}.commands содержит неполную команду"
                )

    contributors = site.get("contributors", [])
    contributor_ids: list[str] = []
    for person in contributors:
        if not isinstance(person, dict):
            errors.append("site.contributors должен состоять из объектов")
            continue
        contributor_ids.append(person.get("id", ""))
        for field in ("id", "github", "name", "roles", "bio"):
            if not person.get(field):
                errors.append(
                    f"site.contributors.{person.get('id', '?')}.{field} обязателен"
                )
        if not re.fullmatch(
            r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?",
            person.get("github", ""),
        ):
            errors.append(
                f"site.contributors.{person.get('id', '?')}.github не похож на GitHub-логин"
            )
    if len(contributor_ids) != len(set(contributor_ids)):
        errors.append("site.contributors содержит повторяющиеся id")
    known_contributors = set(contributor_ids)
    defaults = site.get("modDefaults", {})
    unknown_defaults = sorted(
        set(defaults.get("contributors", [])) - known_contributors
    )
    if unknown_defaults:
        errors.append(
            "site.modDefaults.contributors содержит неизвестные id: "
            + ", ".join(unknown_defaults)
        )

    catalog = site.get("modCatalog", [])
    catalog_ids = [entry.get("id") for entry in catalog if isinstance(entry, dict)]
    if len(catalog) != inventory.get("kerbalRuMods"):
        errors.append("site.modCatalog должен содержать все поддерживаемые моды")
    if len(catalog_ids) != len(set(catalog_ids)):
        errors.append("site.modCatalog содержит повторяющиеся id")
    missing_catalog = sorted(set(mods) - set(catalog_ids))
    extra_catalog = sorted(set(catalog_ids) - set(mods))
    if missing_catalog:
        errors.append("site.modCatalog не содержит: " + ", ".join(missing_catalog))
    if extra_catalog:
        errors.append("site.modCatalog содержит неизвестные моды: " + ", ".join(extra_catalog))
    required_catalog_fields = {
        "id",
        "name",
        "kicker",
        "teaser",
        "icon",
        "description",
        "tags",
        "source",
    }
    for entry in catalog:
        if not isinstance(entry, dict):
            errors.append("site.modCatalog должен состоять из объектов")
            continue
        missing = sorted(required_catalog_fields - set(entry))
        if missing:
            errors.append(f"site.modCatalog.{entry.get('id', '?')} без полей: {', '.join(missing)}")
        if not re.fullmatch(r"i-[a-z0-9-]+", entry.get("icon", "")):
            errors.append(f"site.modCatalog.{entry.get('id', '?')}.icon должен быть id Tabler-иконки")
        if not isinstance(entry.get("tags"), list) or not entry.get("tags"):
            errors.append(f"site.modCatalog.{entry.get('id', '?')}.tags должен быть непустым списком")
        if not str(entry.get("source", "")).startswith("https://"):
            errors.append(f"site.modCatalog.{entry.get('id', '?')}.source должен быть HTTPS-ссылкой")
        unknown_people = sorted(
            set(entry.get("contributors", [])) - known_contributors
        )
        if unknown_people:
            errors.append(
                f"site.modCatalog.{entry.get('id', '?')}.contributors содержит неизвестные id: "
                + ", ".join(unknown_people)
            )
        for screenshot in entry.get("screenshots", []):
            if not isinstance(screenshot, dict) or not screenshot.get("src"):
                errors.append(
                    f"site.modCatalog.{entry.get('id', '?')}.screenshots содержит неполную запись"
                )

    groups = site.get("inventoryGroups", [])
    groups_by_id = {
        group.get("id"): group for group in groups if isinstance(group, dict)
    }
    expected_group_counts = {
        "upstream": inventory.get("upstreamRussianMods", 0)
        + inventory.get("stockRussian", 0),
        "untranslated": inventory.get("translationCandidates", 0),
        "service": inventory.get("serviceComponents", 0),
    }
    if set(groups_by_id) != set(expected_group_counts):
        errors.append("site.inventoryGroups должен содержать upstream, untranslated и service")
    inventory_names: list[str] = []
    for group_id, expected_count in expected_group_counts.items():
        group = groups_by_id.get(group_id, {})
        entries = group.get("entries", [])
        if len(entries) != expected_count:
            errors.append(
                f"site.inventoryGroups.{group_id}: {len(entries)} записей, ожидается {expected_count}"
            )
        for entry in entries:
            if not isinstance(entry, dict) or not entry.get("name") or not entry.get("note"):
                errors.append(f"site.inventoryGroups.{group_id} содержит неполную запись")
                continue
            unknown_people = sorted(
                set(entry.get("contributors", [])) - known_contributors
            )
            if unknown_people:
                errors.append(
                    f"site.inventoryGroups.{group_id}.{entry.get('name')}.contributors содержит неизвестные id: "
                    + ", ".join(unknown_people)
                )
            inventory_names.append(entry["name"])
    if len(inventory_names) != len(set(inventory_names)):
        errors.append("site.inventoryGroups содержит повторяющиеся компоненты")

    ui = data.get("uiTranslation", {})
    for field in (
        "label",
        "status",
        "statusLabel",
        "summary",
        "modsCovered",
        "linesTranslated",
        "uniqueKeys",
    ):
        if not ui.get(field):
            errors.append(f"uiTranslation.{field} обязателен")
    if ui.get("modsCovered", 0) < len(ui.get("modsNotInstalledInThisBuild", [])):
        errors.append("uiTranslation.modsCovered меньше числа отсутствующих модов")

    performance = site.get("performance", {})
    for field in (
        "eyebrow",
        "title",
        "intro",
        "privacy",
        "methodTitle",
        "actionLabel",
        "metrics",
        "devices",
    ):
        if not performance.get(field):
            errors.append(f"site.performance.{field} обязателен")
    device_ids: list[str] = []
    for device in performance.get("devices", []):
        if not isinstance(device, dict):
            errors.append("site.performance.devices должен состоять из объектов")
            continue
        device_ids.append(device.get("id", ""))
        for field in (
            "id",
            "name",
            "hardware",
            "platform",
            "status",
            "statusLabel",
            "notes",
        ):
            if not device.get(field):
                errors.append(
                    f"site.performance.devices.{device.get('id', '?')}.{field} обязателен"
                )
        if device.get("status") not in {"awaiting", "measured"}:
            errors.append(
                f"site.performance.devices.{device.get('id', '?')}.status должен быть awaiting или measured"
            )
        if device.get("status") == "measured":
            for field in (
                "buildVersion",
                "resolution",
                "preset",
                "averageFps",
                "onePercentLowFps",
                "peakRamGb",
                "loadTimeSeconds",
            ):
                if device.get(field) is None:
                    errors.append(
                        f"site.performance.devices.{device.get('id', '?')}.{field} обязателен для measured"
                    )
    if len(device_ids) != len(set(device_ids)):
        errors.append("site.performance.devices содержит повторяющиеся id")

    required_links = {
        "repository",
        "releases",
        "coverage",
        "discussions",
        "uiTranslation",
        "roadmap",
        "maintaining",
        "performanceReport",
    }
    missing_links = sorted(required_links - set(data.get("links", {})))
    if missing_links:
        errors.append("links не содержит: " + ", ".join(missing_links))

    if errors:
        raise ValueError("\n".join(f"- {error}" for error in errors))
    return data


def generated_readme_block(data: dict) -> str:
    release = data["release"]
    inventory = data["inventory"]
    coverage = data["coverage"]
    ui = data["uiTranslation"]
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
            f'| Интерфейс модов | **{ui["modsCovered"]} {plural_ru(ui["modsCovered"], "словарь", "словаря", "словарей")} · '
            f'{spaced(ui["linesTranslated"])} {plural_ru(ui["linesTranslated"], "строка", "строки", "строк")}** | {ui["statusLabel"]} |',
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
