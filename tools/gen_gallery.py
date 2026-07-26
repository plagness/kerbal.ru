#!/usr/bin/env python3
"""kerbal.ru — генератор галереи скриншотов сборки.

Источник истины: builds/<сборка>/screens/screens.json
Файлы кладёт tools/add_screenshot.sh (2200 px, JPEG q80, 300–500 КБ).

Пишет в два места, оба между маркерами:
  <сборка-с-заглавной>/index.html         блок GALLERY:<build>
  builds/<сборка>/screens/README.md       целиком (обзорный .md с картинками)

Запуск: python3 tools/gen_gallery.py [сборка ...]   (по умолчанию — все)
"""
from __future__ import annotations

import html
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = "https://github.com/plagness/kerbal.ru/blob/main"

# сборка -> (папка страницы на сайте, название сборки, заголовок раздела, номер раздела)
PAGES = {
    "operator": ("Operator", "Оператор", "Как это выглядит", "03 / СКРИНШОТЫ"),
}


def load(build: str) -> list[dict]:
    path = ROOT / "builds" / build / "screens" / "screens.json"
    if not path.exists():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    shots = data.get("screens", [])
    for s in shots:
        f = ROOT / "builds" / build / "screens" / s["file"]
        if not f.exists():
            raise SystemExit(f"нет файла скриншота: {f}")
        s["_kb"] = f.stat().st_size // 1024
    return shots


def render_html(build: str, shots: list[dict], title: str, num: str) -> str:
    """Полоса с горизонтальной прокруткой; клик открывает полный кадр."""
    items = []
    for s in shots:
        src = f"/builds/{build}/screens/{s['file']}"
        items.append(
            f'<a class="gal-item" href="{src}" target="_blank" rel="noopener">'
            f'<img src="{src}" alt="{html.escape(s["alt"])}" loading="lazy" decoding="async" width="2200" height="1237">'
            f'<span class="gal-cap"><b>{html.escape(s["title"])}</b>{html.escape(s["caption"])}</span>'
            f"</a>"
        )
    strip = "\n        ".join(items)
    return f"""  <section class="reveal" id="screens">
    <div class="sec-head"><span class="sec-ico"><svg class="ic"><use href="#i-world"/></svg></span><span class="sec-num">{num}</span><h2>{html.escape(title)}</h2><span class="rule"></span></div>
    <div class="card gallery">
      <div class="gal-strip" tabindex="0" aria-label="Скриншоты сборки">
        {strip}
      </div>
      <div class="gal-nav"><button class="gal-btn" type="button" data-gal="-1" aria-label="Назад">←</button><button class="gal-btn" type="button" data-gal="1" aria-label="Вперёд">→</button></div>
    </div>
  </section>"""


def render_md(build: str, shots: list[dict]) -> str:
    page_dir, name = PAGES[build][0], PAGES[build][1]
    esc = lambda s: s.replace("[", "\\[").replace("]", "\\]")
    lines = [
        f"# Скриншоты сборки «{name}»",
        "",
        "Кадры из живой игры на этой сборке — используются в галерее на "
        f"[kerbal.ru/{page_dir}](https://kerbal.ru/{page_dir}/#screens) и в обзорных документах.",
        "",
        "Добавить новый: `tools/add_screenshot.sh <исходник> "
        f"{build} <slug>`, затем дописать запись в `screens.json` и прогнать "
        "`python3 tools/gen_gallery.py`. Файл не должен превышать ~500 КБ.",
        "",
    ]
    for s in shots:
        lines += [
            f"## {s['title']}",
            "",
            f"![{esc(s['alt'])}]({s['file']})",
            "",
            f"{s['caption']}",
            "",
            f"<sub>`{s['file']}` — {s['_kb']} КБ</sub>",
            "",
        ]
    return "\n".join(lines)


def splice(path: Path, marker: str, block: str) -> bool:
    text = path.read_text(encoding="utf-8")
    start, end = f"<!-- {marker}:START -->", f"<!-- {marker}:END -->"
    pat = re.compile(re.escape(start) + r".*?" + re.escape(end), re.S)
    if not pat.search(text):
        raise SystemExit(f"в {path.name} нет маркеров {start} … {end}")
    new = pat.sub(lambda _: f"{start}\n{block}\n  {end}", text, count=1)
    if new == text:
        return False
    path.write_text(new, encoding="utf-8")
    return True


def main() -> None:
    builds = sys.argv[1:] or list(PAGES)
    for build in builds:
        page_dir, _name, title, num = PAGES[build]
        shots = load(build)
        if not shots:
            print(f"— {build}: скриншотов нет, пропуск")
            continue

        splice(ROOT / page_dir / "index.html", f"GALLERY:{build}",
               render_html(build, shots, title, num))
        md = ROOT / "builds" / build / "screens" / "README.md"
        md.write_text(render_md(build, shots), encoding="utf-8")

        total = sum(s["_kb"] for s in shots)
        print(f"✓ {build}: {len(shots)} шт., {total} КБ → {page_dir}/index.html + {md.relative_to(ROOT)}")
        for s in shots:
            flag = "  ⚠ тяжёлый" if s["_kb"] > 500 else ""
            print(f"    {s['file']:<34} {s['_kb']:>4} КБ{flag}")


if __name__ == "__main__":
    main()
