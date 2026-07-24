#!/usr/bin/env python3
"""Сгенерировать индексы для сайта/меню установщика из истины-в-файлах.

Пишет два файла (истина — сами build.json и translations/<mod>/translation.json):
  builds/_catalog.json        — каталог сборок (id, name, status, состав, счётчики)
  translations/_index.json    — библиотека переводов (мод, папка, метод, ключи, статус)

Запуск:
  python3 tools/gen_catalog.py           # записать оба индекса
  python3 tools/gen_catalog.py --check    # только проверить, что индексы совпадают с истиной (CI)
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILDS = ROOT / "builds"
TRANSLATIONS = ROOT / "translations"
CATALOG_PATH = BUILDS / "_catalog.json"
TR_INDEX_PATH = TRANSLATIONS / "_index.json"


def build_catalog() -> dict:
    builds = []
    for bj in sorted(BUILDS.glob("*/build.json")):
        b = json.loads(bj.read_text(encoding="utf-8"))
        mods = b.get("mods", {})
        core = mods.get("core", [])
        recommended = mods.get("recommended", [])
        optional = mods.get("optional", [])
        builds.append({
            "id": b.get("id", bj.parent.name),
            "name": b.get("name"),
            "status": b.get("status"),
            "tagline": b.get("tagline"),
            "kspVersion": b.get("kspVersion"),
            "system": b.get("system"),
            "difficulty": b.get("difficulty"),
            "language": b.get("language"),
            "incompatibleWith": b.get("incompatibleWith", []),
            "mods": {
                "core": len(core),
                "recommended": len(recommended),
                "optional": len(optional),
                "total": len(core) + len(recommended) + len(optional),
            },
        })
    builds.sort(key=lambda x: (x.get("status") != "curated", x.get("id") or ""))
    return {"schema": 1, "builds": builds}


def build_translations_index() -> dict:
    mods = []
    keyed = ui = 0
    total_keys = 0
    for tj in sorted(TRANSLATIONS.glob("*/translation.json")):
        t = json.loads(tj.read_text(encoding="utf-8"))
        mod_id = tj.parent.name
        method = t.get("method", "unknown")
        keys = int(t.get("keys", 0) or 0)
        total_keys += keys
        if method == "keyed":
            keyed += 1
        elif method in ("ui-dict", "ui"):
            ui += 1
        mods.append({
            "id": mod_id,
            "mod": t.get("mod", mod_id),
            "folder": t.get("folder", mod_id),
            "method": method,
            "keys": keys,
            "status": t.get("status", "unknown"),
        })
    mods.sort(key=lambda x: x["id"].lower())
    return {
        "schema": 1,
        "totals": {"mods": len(mods), "keyedMods": keyed, "uiMods": ui, "keys": total_keys},
        "mods": mods,
    }


def _stamp(doc: dict) -> dict:
    doc = dict(doc)
    doc["generatedAt"] = dt.date.today().isoformat()
    return doc


def _dump(doc: dict) -> str:
    return json.dumps(doc, ensure_ascii=False, indent=2) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="только проверить совпадение с истиной (для CI), не писать")
    args = ap.parse_args()

    outputs = {
        CATALOG_PATH: build_catalog(),
        TR_INDEX_PATH: build_translations_index(),
    }

    if args.check:
        stale = []
        for path, doc in outputs.items():
            want = doc  # без generatedAt: сравниваем содержимое, дата не считается
            if not path.exists():
                stale.append(f"{path.relative_to(ROOT)} отсутствует")
                continue
            have = json.loads(path.read_text(encoding="utf-8"))
            have.pop("generatedAt", None)
            if have != want:
                stale.append(f"{path.relative_to(ROOT)} устарел")
        if stale:
            print("Индексы рассинхронены:\n  " + "\n  ".join(stale))
            print("Запусти: python3 tools/gen_catalog.py")
            return 1
        print("Индексы актуальны.")
        return 0

    for path, doc in outputs.items():
        path.write_text(_dump(_stamp(doc)), encoding="utf-8")
        rel = path.relative_to(ROOT)
        if path == CATALOG_PATH:
            print(f"✓ {rel}: {len(doc['builds'])} сборок")
        else:
            t = doc["totals"]
            print(f"✓ {rel}: {t['mods']} модов, {t['keys']} ключей "
                  f"(keyed {t['keyedMods']}, ui {t['uiMods']})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
