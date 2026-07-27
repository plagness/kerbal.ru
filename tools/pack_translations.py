#!/usr/bin/env python3
"""Собрать ZIP с русификатором — установка «ручками» на любой ОС (Windows в первую очередь).

Пользователь распаковывает архив в корень папки Kerbal Space Program (в архиве уже есть GameData/),
включает русский язык в настройках игры — готово. Это тот же набор файлов, что раскатывает
install.sh --ru-only, но без CKAN и терминала.

Что кладём в GameData/:
  kerbalru-ui-translator/Plugins/*.dll          движок перевода интерфейса (Harmony)
  kerbalru-ui-translator/KerbalRuUiTranslations/*.txt   ui-словари (все)
  zzz-kerbalru-translations/<mod>/*.cfg         Localization и MM-патчи (все моды библиотеки)
  <конфиг выбранной сборки>                     напр. builds/operator/config/* (фиксы и настройки)

Перевод отсутствующего мода — безвредный no-op: ключи локализации никто не читает,
а MM-патчи не находят целей. Поэтому кладём библиотеку целиком, ничего не гадая.

Запуск:
  python3 tools/pack_translations.py            # общий архив (без конфигов сборок)
  python3 tools/pack_translations.py operator   # + конфиг сборки «Оператор»
"""
from __future__ import annotations

import json
import sys
import zipfile
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"
VERSION = (ROOT / "VERSION").read_text(encoding="utf-8").strip()

README = """kerbal.ru — русификатор модов Kerbal Space Program {ver}
=========================================================

КАК УСТАНОВИТЬ (2 шага, без терминала)

1. Скопируйте ВСЁ содержимое архива в папку игры Kerbal Space Program
   (папки GameData и Ships там уже есть — согласитесь на объединение,
   ничего не потеряется).

   Путь к игре в Steam обычно такой:
     Windows  C:\\Program Files (x86)\\Steam\\steamapps\\common\\Kerbal Space Program
     macOS    ~/Library/Application Support/Steam/steamapps/common/Kerbal Space Program
     Linux    ~/.local/share/Steam/steamapps/common/Kerbal Space Program

2. Запустите игру → Settings (Настройки) → язык → Русский → перезапустите игру.

Готово. Перевод применяется только к тем модам, которые у вас стоят;
для остальных файлы просто ничего не делают.

ЧТО ВНУТРИ
  GameData/kerbalru-ui-translator/     движок перевода интерфейса модов + словари
  GameData/zzz-kerbalru-translations/  переводы деталей, науки, контрактов
{extra}{toolkit}
ОБНОВЛЕНИЕ
  Скачайте новый архив и скопируйте поверх (файлы заменятся).

УДАЛЕНИЕ
  Удалите из GameData папки kerbalru-ui-translator и zzz-kerbalru-translations{extra_rm}.
  Инструментарий (папка kerbal, AGENTS.md, Ships/Script/lib и check) удаляется отдельно —
  он на игру не влияет, это только документация и скрипты.

Сайт и исходники: https://kerbal.ru · https://github.com/plagness/kerbal.ru
Чужие моды в архиве НЕ распространяются — только наши переводы.
"""


def add_tree(z: zipfile.ZipFile, src: Path, arc_prefix: str) -> int:
    n = 0
    for p in sorted(src.rglob("*")):
        if p.is_file() and not p.name.startswith("."):
            z.write(p, f"{arc_prefix}/{p.relative_to(src).as_posix()}")
            n += 1
    return n


def main() -> int:
    bid = sys.argv[1] if len(sys.argv) > 1 else None
    if bid and not (ROOT / "builds" / bid / "build.json").exists():
        print(f"× нет такой сборки: {bid}")
        return 2

    DIST.mkdir(exist_ok=True)
    name = f"kerbalru-translations-{bid}-{VERSION}.zip" if bid else f"kerbalru-translations-{VERSION}.zip"
    out = DIST / name
    engine_n = dict_n = loc_n = cfg_n = 0

    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        # 1. движок
        eng = ROOT / "engine" / "Plugins"
        if eng.exists():
            engine_n = add_tree(z, eng, "GameData/kerbalru-ui-translator/Plugins")

        # 2. библиотека переводов: ui-словари + Localization
        for tdir in sorted((ROOT / "translations").glob("*/")):
            tj = tdir / "translation.json"
            if not tj.exists():
                continue
            tid = tdir.name
            ui = tdir / "KerbalRuUiTranslations"
            if ui.exists():
                dict_n += add_tree(z, ui, "GameData/kerbalru-ui-translator/KerbalRuUiTranslations")
            loc = tdir / "Localization"
            if loc.exists():
                loc_n += add_tree(z, loc, f"GameData/zzz-kerbalru-translations/{tid}")

        # 3. конфиг сборки (фиксы/настройки) — если собираем под конкретную сборку
        extra = extra_rm = ""
        if bid:
            cfg = ROOT / "builds" / bid / "config"
            if cfg.exists():
                cfg_n = add_tree(z, cfg, "GameData")
                b = json.loads((ROOT / "builds" / bid / "build.json").read_text(encoding="utf-8"))
                names = sorted(p.name for p in cfg.iterdir() if p.is_dir())
                extra = (f"  GameData/{', '.join(names)}\n"
                         f"       конфиг и фиксы сборки «{b.get('name', bid)}»\n")
                extra_rm = f", а также {', '.join(names)}"

        # 4. инструментарий: полётные скрипты kOS, вики и инструкция для ИИ-агента.
        # То же, что раскладывает install.sh, — чтобы путь «скачал ZIP» на Windows
        # давал ровно тот же набор, что путь через терминал.
        toolkit = ""
        kos_n = wiki_n = 0
        kos = ROOT / "kos"
        if kos.exists():
            for sub in ("lib", "check"):
                if (kos / sub).exists():
                    kos_n += add_tree(z, kos / sub, f"Ships/Script/{sub}")
            if (kos / "missions").exists():
                kos_n += add_tree(z, kos / "missions", "Ships/Script/missions")
            if (kos / "README.md").is_file():
                z.write(kos / "README.md", "kerbal/kos/README.md")
            if (kos / "tools" / "kos.py").is_file():
                z.write(kos / "tools" / "kos.py", "kerbal/tools/kos.py")

        wiki_bid = bid if bid and (ROOT / "builds" / bid / "wiki").exists() else "operator"
        wiki_dir = ROOT / "builds" / wiki_bid / "wiki"
        if wiki_dir.exists():
            for f in sorted(wiki_dir.glob("*.md")):
                if f.name.startswith("_"):      # _SPEC.md — формат для авторов
                    continue
                z.write(f, f"kerbal/wiki/{f.name}")
                wiki_n += 1

        tpl = ROOT / "tools" / "templates" / "AGENTS.game.md"
        if tpl.exists():
            b = json.loads((ROOT / "builds" / (bid or "operator") / "build.json").read_text(encoding="utf-8"))
            text = tpl.read_text(encoding="utf-8")
            note = ("" if wiki_bid == (bid or "operator") else
                    f"У этой сборки своей вики пока нет — рядом лежит вики сборки "
                    f"«{json.loads((ROOT / 'builds' / wiki_bid / 'build.json').read_text(encoding='utf-8'))['name']}»: "
                    f"связь, наука, kOS и диагностика у них общие, отличается состав модов.")
            for key, val in (("{{BUILD_ID}}", bid or "operator"), ("{{BUILD_NAME}}", b.get("name", bid or "operator")),
                             ("{{WIKI_BUILD_ID}}", wiki_bid), ("{{PAGE_DIR}}", b.get("page", "Operator")),
                             ("{{VERSION}}", f"v{VERSION}"), ("{{DATE}}", date.today().isoformat()),
                             ("{{WIKI_NOTE}}", note)):
                text = text.replace(key, val)
            z.writestr("AGENTS.md", text)

        if kos_n or wiki_n:
            toolkit = (f"  Ships/Script/                        {kos_n} kOS-скриптов: подъём, орбита, наука\n"
                       f"  kerbal/wiki/                         {wiki_n} статей вики сборки\n"
                       f"  kerbal/tools/kos.py                  telnet-клиент к терминалу kOS\n"
                       f"  AGENTS.md                            инструкция для ИИ-агента\n")

        z.writestr("КАК-УСТАНОВИТЬ.txt",
                   README.format(ver=VERSION, extra=extra, extra_rm=extra_rm, toolkit=toolkit))

    size = out.stat().st_size / 1024 / 1024
    print(f"✓ {out.relative_to(ROOT)}  ({size:.1f} МБ)")
    print(f"  движок: {engine_n} файл(ов) · ui-словари: {dict_n} · Localization: {loc_n} · конфиг сборки: {cfg_n}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
