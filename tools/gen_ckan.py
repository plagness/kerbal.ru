#!/usr/bin/env python3
"""Сгенерировать .ckan-метапакеты сборок — путь установки БЕЗ терминала (Windows и не только).

CKAN умеет ставить «модпак» из файла: в GUI — File → Install from .ckan (или перетащить файл в окно).
Метапакет сам ничего не скачивает: он объявляет зависимости (список модов сборки), а CKAN подтягивает
их из своего репозитория. Переводы в метапакет не входят — их ставит отдельный ZIP (tools/pack_translations.py).

Запуск:
  python3 tools/gen_ckan.py            # собрать для всех сборок каталога
  python3 tools/gen_ckan.py operator   # только для одной

Кладёт в dist/<id>.ckan (файл прикладывается к GitHub Release и лежит на сайте).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILDS = ROOT / "builds"
DIST = ROOT / "dist"
VERSION = (ROOT / "VERSION").read_text(encoding="utf-8").strip()

# id сборки → человекочитаемый слаг страницы на сайте
SITE_SLUG = {"operator": "Operator", "rp1": "KSP-RO"}


def build_ckan(bid: str) -> dict:
    b = json.loads((BUILDS / bid / "build.json").read_text(encoding="utf-8"))
    mods = b.get("mods", {})
    core = mods.get("core", [])
    recommended = mods.get("recommended", [])
    optional = mods.get("optional", [])
    slug = SITE_SLUG.get(bid, bid)

    # core + recommended = обязательный состав сборки (как в install.sh);
    # optional → suggests, чтобы CKAN предложил, но не тянул принудительно.
    depends = [{"name": m} for m in core + recommended]
    suggests = [{"name": m} for m in optional]

    doc = {
        "spec_version": "v1.6",
        "identifier": f"kerbalru-{bid}",
        "name": f"kerbal.ru: {b.get('name', bid)}",
        "abstract": b.get("tagline", "")[:200],
        "author": ["kerbal.ru"],
        "version": VERSION,
        "ksp_version": b.get("kspVersion", "1.12.5"),
        "license": "MIT",
        "kind": "metapackage",
        "release_status": "stable",
        "resources": {
            "homepage": f"https://kerbal.ru/{slug}",
            "repository": "https://github.com/plagness/kerbal.ru",
            "bugtracker": "https://github.com/plagness/kerbal.ru/issues",
        },
        "depends": depends,
    }
    if suggests:
        doc["suggests"] = suggests
    return doc


def main() -> int:
    ids = sys.argv[1:] or [d.name for d in sorted(BUILDS.iterdir())
                           if (d / "build.json").exists()]
    DIST.mkdir(exist_ok=True)
    for bid in ids:
        if not (BUILDS / bid / "build.json").exists():
            print(f"× нет такой сборки: {bid}")
            return 2
        doc = build_ckan(bid)
        out = DIST / f"{bid}.ckan"
        out.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"✓ {out.relative_to(ROOT)}: {len(doc['depends'])} модов "
              f"(+{len(doc.get('suggests', []))} опциональных), версия {doc['version']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
