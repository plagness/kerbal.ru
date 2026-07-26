#!/usr/bin/env python3
"""Собрать вики сборки из Markdown-исходников: wiki/*.md → Operator/wiki/*.html.

Настоящая вики: категории, боковая навигация, перелинковка [[slug]] (несуществующие
ссылки — красные, как в MediaWiki), оглавление статьи, «связанные статьи», обратные
ссылки («сюда ссылаются»), поиск по названиям. Оформление — палитра сайта kerbal.ru.

Формат исходника описан в wiki/_SPEC.md.

Запуск: python3 tools/gen_wiki.py
"""
from __future__ import annotations

import html
import re
import sys
from pathlib import Path

try:
    import markdown
except ImportError:
    sys.exit("Нужен python-markdown:  pip3 install markdown")

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "wiki"
OUT = ROOT / "Operator" / "wiki"
VERSION = (ROOT / "VERSION").read_text(encoding="utf-8").strip()

# порядок категорий в навигации
CATEGORIES = ["Начало", "Связь и сеть", "Автоматика", "Наука", "Станции и базы", "Техника", "Прогресс"]
CAT_ICON = {
    "Начало": "i-rocket", "Связь и сеть": "i-satellite", "Автоматика": "i-cpu",
    "Наука": "i-atom", "Станции и базы": "i-capsule", "Техника": "i-engine", "Прогресс": "i-route",
}

WIKILINK = re.compile(r"\[\[([a-z0-9\-]+)(?:\|([^\]]+))?\]\]")
FM = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.S)


def parse_front_matter(text: str) -> tuple[dict, str]:
    m = FM.match(text)
    if not m:
        return {}, text
    meta: dict = {}
    for line in m.group(1).split("\n"):
        if not line.strip() or ":" not in line:
            continue
        k, _, v = line.partition(":")
        v = v.strip()
        if v.startswith("[") and v.endswith("]"):
            meta[k.strip()] = [x.strip().strip('"\'') for x in v[1:-1].split(",") if x.strip()]
        else:
            # YAML-строка может быть в кавычках — снимаем
            if len(v) > 1 and v[0] == v[-1] and v[0] in '"\'':
                v = v[1:-1]
            meta[k.strip()] = v
    return meta, text[m.end():]


def load_articles() -> dict:
    arts = {}
    for p in sorted(SRC.glob("*.md")):
        if p.name.startswith("_"):
            continue
        meta, body = parse_front_matter(p.read_text(encoding="utf-8"))
        slug = p.stem
        arts[slug] = {
            "slug": slug,
            "title": meta.get("title", slug),
            "category": meta.get("category", "Прочее"),
            "summary": meta.get("summary", ""),
            "order": int(meta.get("order", 999) or 999),
            "related": meta.get("related", []) or [],
            "body": body,
        }
    return arts


def resolve_links(text: str, arts: dict, backlinks: dict, from_slug: str) -> str:
    """[[slug]] / [[slug|текст]] → ссылка. Нет такой статьи → красная ссылка."""
    def sub(m):
        slug, label = m.group(1), m.group(2)
        target = arts.get(slug)
        if target:
            backlinks.setdefault(slug, set()).add(from_slug)
            text_ = label or target["title"]
            tip = html.escape(target["summary"], quote=True)
            return f'<a class="wikilink" href="{slug}.html" title="{tip}">{html.escape(text_)}</a>'
        return (f'<a class="wikilink is-missing" href="#" title="Статья ещё не написана">'
                f'{html.escape(label or slug)}</a>')
    return WIKILINK.sub(sub, text)


CSS = """
:root{--sans:"Manrope",-apple-system,system-ui,"Segoe UI",sans-serif;--display:"Unbounded","Manrope",sans-serif;
--mono:"JetBrains Mono",monospace;--bg-0:#030806;--bg-1:#07110d;--panel:rgba(10,20,16,.72);
--line:rgba(183,214,190,.13);--line-cyan:rgba(166,232,110,.36);--txt:#edf4eb;--txt-dim:#98a49e;
--txt-faint:#617068;--orange:#ff9d48;--gold:#f0c067;--cyan:#a6e86e;--green:#b9f47b;
--green-glow:rgba(185,244,123,.28);--red:#ff6b6b;}
*{box-sizing:border-box}html{scroll-behavior:smooth}
body{margin:0;font-family:var(--sans);color:var(--txt);background:var(--bg-0);line-height:1.7;-webkit-font-smoothing:antialiased}
.sky{position:fixed;inset:0;z-index:-3;background:
 radial-gradient(ellipse 80% 68% at 86% 10%,rgba(35,105,74,.20) 0%,transparent 62%),
 radial-gradient(ellipse 70% 55% at 12% 20%,rgba(64,116,129,.08) 0%,transparent 64%),
 linear-gradient(180deg,var(--bg-0) 0%,var(--bg-1) 58%,#050c09 100%);}
.sky::before{content:'';position:absolute;inset:0;opacity:.45;background-image:
 radial-gradient(circle,rgba(240,255,244,.7) 0 1px,transparent 1.3px),
 radial-gradient(circle,rgba(185,244,123,.35) 0 1px,transparent 1.2px);
 background-size:113px 113px,71px 71px;background-position:17px 31px,5px 67px;}
a{color:var(--orange);text-decoration:none}a:hover{color:var(--gold)}
/* шапка */
.top{position:sticky;top:0;z-index:20;background:rgba(3,8,6,.82);backdrop-filter:blur(12px);border-bottom:1px solid var(--line)}
.top-in{max-width:1240px;margin:0 auto;padding:14px 22px;display:flex;align-items:center;gap:16px;justify-content:space-between}
.brand{font-family:var(--display);font-weight:800;font-size:1.05rem;color:var(--green);letter-spacing:-.03em}
.brand+span{color:var(--txt-faint);font-family:var(--sans);font-weight:600;font-size:.8rem;margin-left:8px;letter-spacing:0}
.top-links{display:flex;gap:16px;font-size:.82rem;font-weight:600}
.top-links a{color:var(--txt-dim)}.top-links a:hover{color:#fff}
/* каркас */
.shell{max-width:1240px;margin:0 auto;padding:26px 22px 60px;display:grid;grid-template-columns:262px minmax(0,1fr);gap:34px;align-items:start}
.side{position:sticky;top:74px;max-height:calc(100vh - 96px);overflow:auto;padding-right:4px}
.side::-webkit-scrollbar{width:6px}.side::-webkit-scrollbar-thumb{background:var(--line);border-radius:3px}
.search{width:100%;background:rgba(255,255,255,.03);border:1px solid var(--line);border-radius:9px;color:var(--txt);
 font-family:var(--sans);font-size:.84rem;padding:10px 12px;margin-bottom:16px}
.search:focus{outline:none;border-color:var(--line-cyan)}
.cat{margin-bottom:18px}
.cat-h{display:flex;align-items:center;gap:8px;font-family:var(--mono);font-size:.62rem;letter-spacing:.9px;
 text-transform:uppercase;color:var(--txt-faint);margin-bottom:7px}
.cat-h .ic{width:1em;height:1em;color:var(--cyan);font-size:1.05rem}
.side a{display:block;color:var(--txt-dim);font-size:.87rem;padding:5px 10px;border-radius:7px;border-left:2px solid transparent}
.side a:hover{color:#fff;background:rgba(255,255,255,.03)}
.side a.is-on{color:var(--green);background:rgba(166,232,110,.07);border-left-color:var(--green)}
/* статья */
.crumbs{font-size:.78rem;color:var(--txt-faint);margin-bottom:10px}
.crumbs a{color:var(--txt-dim)}
h1{font-family:var(--display);font-weight:800;font-size:clamp(1.7rem,4vw,2.5rem);line-height:1.12;margin:0 0 10px;letter-spacing:-.03em;
 background:linear-gradient(145deg,#fff 10%,#e7f2e7 55%,var(--green) 130%);-webkit-background-clip:text;background-clip:text;color:transparent}
.lede{color:var(--txt-dim);font-size:1.02rem;margin:0 0 22px;padding-bottom:18px;border-bottom:1px solid var(--line)}
.art{background:var(--panel);backdrop-filter:blur(14px);border:1px solid var(--line);border-radius:18px;padding:28px 32px;box-shadow:0 28px 70px -50px #000}
.art h2{font-size:1.22rem;font-weight:750;color:#fff;margin:30px 0 10px;padding-top:6px}
.art h2:first-child{margin-top:0}
.art h3{font-size:1rem;font-weight:700;color:var(--cyan);margin:22px 0 8px}
.art p{margin:0 0 14px}
.art ul,.art ol{margin:0 0 14px;padding-left:22px}.art li{margin:5px 0}
.art strong{color:#fff}
.art code{font-family:var(--mono);font-size:.86em;background:rgba(255,255,255,.05);border:1px solid var(--line);
 border-radius:5px;padding:1px 5px;color:var(--cyan)}
.art pre{background:#030806;border:1px solid var(--line);border-radius:10px;padding:15px 17px;overflow-x:auto;margin:0 0 16px}
.art pre code{background:none;border:none;padding:0;color:var(--cyan);font-size:.82rem;line-height:1.65}
.art blockquote{margin:0 0 16px;padding:10px 16px;border-left:3px solid var(--line-cyan);background:rgba(166,232,110,.05);
 border-radius:0 9px 9px 0;color:var(--txt-dim)}
.art table{width:100%;border-collapse:collapse;margin:0 0 18px;font-size:.9rem;display:block;overflow-x:auto}
.art th{text-align:left;font-weight:700;color:var(--cyan);font-size:.76rem;text-transform:uppercase;letter-spacing:.5px;
 padding:9px 12px;border-bottom:1px solid var(--line-cyan);white-space:nowrap}
.art td{padding:9px 12px;border-bottom:1px solid var(--line);vertical-align:top}
.art tr:hover td{background:rgba(255,255,255,.02)}
.wikilink{color:var(--green);border-bottom:1px dotted rgba(185,244,123,.45)}
.wikilink:hover{color:#dbffb0;border-bottom-style:solid}
.wikilink.is-missing{color:var(--red);border-bottom-color:rgba(255,107,107,.4);cursor:help}
/* оглавление */
.toc{background:rgba(255,255,255,.02);border:1px solid var(--line);border-radius:12px;padding:14px 18px;margin:0 0 22px}
.toc-h{font-family:var(--mono);font-size:.6rem;letter-spacing:.9px;text-transform:uppercase;color:var(--txt-faint);margin-bottom:6px}
.toc ul{list-style:none;margin:0;padding:0}.toc li{margin:3px 0}
.toc a{color:var(--txt-dim);font-size:.86rem}.toc a:hover{color:var(--green)}
.toc ul ul{padding-left:14px}
/* низ статьи */
.rel{margin-top:26px;display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:12px}
.rel a{display:block;background:rgba(255,255,255,.02);border:1px solid var(--line);border-radius:12px;padding:13px 16px;transition:.18s}
.rel a:hover{border-color:var(--line-cyan);transform:translateY(-2px)}
.rel b{display:block;color:#fff;font-size:.92rem;margin-bottom:3px}
.rel span{color:var(--txt-dim);font-size:.8rem;line-height:1.45}
.sec-label{font-family:var(--mono);font-size:.62rem;letter-spacing:.9px;text-transform:uppercase;color:var(--txt-faint);margin:26px 0 4px}
.backlinks{margin-top:20px;font-size:.85rem;color:var(--txt-dim)}
.backlinks a{color:var(--txt-dim);border-bottom:1px dotted var(--line)}
.backlinks a:hover{color:var(--green)}
/* хаб */
.hub-cats{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:18px;margin-top:22px}
.hub-cat{background:var(--panel);border:1px solid var(--line);border-radius:16px;padding:20px 22px}
.hub-cat h3{display:flex;align-items:center;gap:9px;font-family:var(--sans);font-size:1.02rem;font-weight:750;color:#fff;margin:0 0 12px}
.hub-cat h3 .ic{width:1em;height:1em;color:var(--cyan);font-size:1.2rem}
.hub-cat a{display:block;padding:7px 0;border-top:1px solid var(--line);color:var(--txt)}
.hub-cat a:first-of-type{border-top:none}
.hub-cat a:hover{color:var(--green)}
.hub-cat a small{display:block;color:var(--txt-faint);font-size:.79rem;line-height:1.45}
footer{border-top:1px solid var(--line);margin-top:40px;padding:22px 0 0;color:var(--txt-faint);font-size:.8rem}
@media(max-width:900px){.shell{grid-template-columns:1fr;gap:20px}.side{position:static;max-height:none}}
"""

ICONS = """<svg style="display:none" aria-hidden="true">
<symbol id="i-rocket" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M4 13a8 8 0 017-7 6 6 0 016 6 8 8 0 01-7 7l-2-2"/><path d="M13 11a1 1 0 100-2 1 1 0 000 2z"/><path d="M9 12H4l2-4"/><path d="M12 15v5l4-2"/></symbol>
<symbol id="i-satellite" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M3.707 6.293l2.586-2.586a1 1 0 011.414 0l5.586 5.586a1 1 0 010 1.414l-2.586 2.586a1 1 0 01-1.414 0L3.707 7.707a1 1 0 010-1.414z"/><path d="M6 10l-3 3 3 3 3-3M10 6l3-3 3 3-3 3M12 16l4 4M16 12l4 4"/></symbol>
<symbol id="i-cpu" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="5" width="14" height="14" rx="1"/><rect x="9" y="9" width="6" height="6"/><path d="M3 10h2M3 14h2M19 10h2M19 14h2M10 3v2M14 3v2M10 19v2M14 19v2"/></symbol>
<symbol id="i-atom" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="1.5"/><path d="M12 21c4.97 0 9-4.03 9-9s-4.03-9-9-9-9 4.03-9 9 4.03 9 9 9z" opacity=".25"/><ellipse cx="12" cy="12" rx="9" ry="4" transform="rotate(45 12 12)"/><ellipse cx="12" cy="12" rx="9" ry="4" transform="rotate(-45 12 12)"/></symbol>
<symbol id="i-capsule" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M7 4h10l2 12H5L7 4z"/><path d="M5 16h14v4H5z"/><path d="M10 8h4"/></symbol>
<symbol id="i-engine" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M9 3h6l1 8H8l1-8z"/><path d="M8 11h8l2 5H6l2-5z"/><path d="M10 16v3M14 16v3M12 16v5"/></symbol>
<symbol id="i-route" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><circle cx="6" cy="19" r="2"/><circle cx="18" cy="5" r="2"/><path d="M12 19h4a2 2 0 000-4H8a2 2 0 010-4h4"/></symbol>
<symbol id="i-book" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M4 5a2 2 0 012-2h13v16H6a2 2 0 00-2 2V5z"/><path d="M9 7h6M9 11h6"/></symbol>
</svg>"""


def sidebar(arts: dict, current: str | None) -> str:
    out = ['<input class="search" id="wsearch" type="search" placeholder="Поиск по вики…" autocomplete="off">',
           '<nav id="wnav">']
    for cat in CATEGORIES:
        items = sorted([a for a in arts.values() if a["category"] == cat], key=lambda x: (x["order"], x["title"]))
        if not items:
            continue
        out.append(f'<div class="cat" data-cat><div class="cat-h"><svg class="ic"><use href="#{CAT_ICON.get(cat,"i-book")}"/></svg>{html.escape(cat)}</div>')
        for a in items:
            on = " is-on" if a["slug"] == current else ""
            out.append(f'<a class="wnav-item{on}" href="{a["slug"]}.html" data-title="{html.escape(a["title"].lower(),quote=True)}">{html.escape(a["title"])}</a>')
        out.append("</div>")
    out.append("</nav>")
    return "\n".join(out)


def page(title: str, desc: str, body: str, arts: dict, current: str | None) -> str:
    return f"""<!DOCTYPE html>
<html lang="ru"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>{html.escape(title)}</title>
<meta name="description" content="{html.escape(desc, quote=True)}">
<meta name="theme-color" content="#07110d">
<link rel="icon" type="image/svg+xml" href="/assets/favicon.svg">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700;800&family=Unbounded:wght@600;700;800&family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">
<style>{CSS}</style></head>
<body><div class="sky"></div>{ICONS}
<header class="top"><div class="top-in">
  <div><a class="brand" href="/">kerbal.ru</a><span>вики сборки «Оператор»</span></div>
  <nav class="top-links"><a href="/Operator">Сборка</a><a href="/Operator/wiki/">Вики</a><a href="/">Каталог</a><a href="https://github.com/plagness/kerbal.ru">GitHub</a></nav>
</div></header>
<div class="shell">
  <aside class="side">{sidebar(arts, current)}</aside>
  <main>{body}
    <footer>Вики сборки «Оператор» · kerbal.ru {VERSION} · правится в
      <a href="https://github.com/plagness/kerbal.ru/tree/main/wiki">wiki/*.md</a> —
      присылай дополнения через <a href="https://github.com/plagness/kerbal.ru/issues">issue</a>.</footer>
  </main>
</div>
<script>
(function(){{
  var s=document.getElementById('wsearch'); if(!s) return;
  s.addEventListener('input',function(){{
    var q=s.value.trim().toLowerCase();
    document.querySelectorAll('#wnav .wnav-item').forEach(function(a){{
      a.style.display = !q || a.getAttribute('data-title').indexOf(q)>=0 ? '' : 'none';
    }});
    document.querySelectorAll('#wnav [data-cat]').forEach(function(c){{
      var any=[].slice.call(c.querySelectorAll('.wnav-item')).some(function(a){{return a.style.display!=='none'}});
      c.style.display = any ? '' : 'none';
    }});
  }});
}})();
</script>
</body></html>
"""


def main() -> int:
    arts = load_articles()
    if not arts:
        print("× нет статей в wiki/*.md")
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    backlinks: dict = {}

    # 1) статьи
    rendered = {}
    for slug, a in arts.items():
        md = markdown.Markdown(extensions=["tables", "fenced_code", "toc", "sane_lists", "attr_list"],
                               extension_configs={"toc": {"toc_depth": "2-3"}})
        body_md = resolve_links(a["body"], arts, backlinks, slug)
        html_body = md.convert(body_md)
        rendered[slug] = (html_body, md.toc if "<li" in (md.toc or "") else "")

    # 2) записываем (второй проход — backlinks уже собраны)
    for slug, a in arts.items():
        html_body, toc = rendered[slug]
        rel = [arts[r] for r in a["related"] if r in arts]
        rel_html = ""
        if rel:
            cards = "".join(
                f'<a href="{r["slug"]}.html"><b>{html.escape(r["title"])}</b>'
                f'<span>{html.escape(r["summary"])}</span></a>' for r in rel)
            rel_html = f'<div class="sec-label">Связанные статьи</div><div class="rel">{cards}</div>'
        bl = sorted(backlinks.get(slug, set()) - {slug})
        bl_html = ""
        if bl:
            links = ", ".join(f'<a href="{b}.html">{html.escape(arts[b]["title"])}</a>' for b in bl)
            bl_html = f'<div class="backlinks">Сюда ссылаются: {links}</div>'
        toc_html = f'<div class="toc"><div class="toc-h">Содержание</div>{toc}</div>' if toc else ""
        body = (f'<div class="crumbs"><a href="/Operator">Оператор</a> / <a href="./">Вики</a> / '
                f'{html.escape(a["category"])}</div>'
                f'<h1>{html.escape(a["title"])}</h1>'
                f'<p class="lede">{html.escape(a["summary"])}</p>'
                f'{toc_html}<article class="art">{html_body}</article>{rel_html}{bl_html}')
        (OUT / f"{slug}.html").write_text(
            page(f'{a["title"]} — вики kerbal.ru', a["summary"], body, arts, slug), encoding="utf-8")

    # 3) хаб
    cats_html = []
    for cat in CATEGORIES:
        items = sorted([a for a in arts.values() if a["category"] == cat], key=lambda x: (x["order"], x["title"]))
        if not items:
            continue
        links = "".join(
            f'<a href="{a["slug"]}.html">{html.escape(a["title"])}<small>{html.escape(a["summary"])}</small></a>'
            for a in items)
        cats_html.append(f'<div class="hub-cat"><h3><svg class="ic"><use href="#{CAT_ICON.get(cat,"i-book")}"/></svg>'
                         f'{html.escape(cat)}</h3>{links}</div>')
    missing = sorted({m.group(1) for a in arts.values() for m in WIKILINK.finditer(a["body"])} - set(arts))
    todo = (f'<p style="color:var(--txt-faint);font-size:.85rem;margin-top:22px">Ещё не написаны (красные ссылки): '
            + ", ".join(html.escape(s) for s in missing) + "</p>") if missing else ""
    hub = (f'<div class="crumbs"><a href="/Operator">Оператор</a> / Вики</div>'
           f'<h1>Вики сборки «Оператор»</h1>'
           f'<p class="lede">Как играть в эту сборку: связь и сеть спутников, автоматика на kOS, наука и геология, '
           f'станции, техника и контракты. {len(arts)} статей, всё связано перекрёстными ссылками.</p>'
           f'<div class="hub-cats">{"".join(cats_html)}</div>{todo}')
    (OUT / "index.html").write_text(
        page("Вики сборки «Оператор» — kerbal.ru",
             "Документация по сборке: kOS, связь, наука, станции, техника.", hub, arts, None), encoding="utf-8")

    print(f"✓ Operator/wiki/: {len(arts)} статей + хаб")
    by_cat = {}
    for a in arts.values():
        by_cat.setdefault(a["category"], []).append(a["slug"])
    for c in CATEGORIES:
        if c in by_cat:
            print(f"    {c}: {', '.join(sorted(by_cat[c]))}")
    if missing:
        print(f"  ⚠ красные ссылки (нет статьи): {', '.join(missing)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
