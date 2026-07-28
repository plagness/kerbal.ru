#!/usr/bin/env python3
"""kerbal.ru — SEO-разметка сайта: robots.txt, sitemap.xml и мета-теги страниц.

Что делает:
  • site/robots.txt   — разрешает обход, указывает адрес карты сайта;
  • site/sitemap.xml  — все страницы сайта с приоритетами;
  • в каждый .html    — блок между маркерами SEO:START/END:
      canonical  — один адрес страницы вместо десятка вариантов с ?utm и /index.html;
      Open Graph + Twitter Card — превью в Telegram, VK и поиске;
      JSON-LD    — что это за сущность (сайт / приложение / статья вики).

Блок вставляется сразу после <title> и переписывается целиком, поэтому
запускать можно сколько угодно раз. Порядок: сначала генераторы страниц
(gen_wiki, gen_gallery), потом этот — он правит уже готовый HTML.

Запуск: python3 tools/gen_seo.py
"""
from __future__ import annotations

import html
import re
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "site"
BASE = "https://kerbal.ru"
OG_IMAGE = f"{BASE}/assets/og.jpg"

# Приоритет и частота обхода: главная и страницы сборок важнее статей вики.
PRIORITY = [
    (re.compile(r"^index\.html$"), "1.0", "weekly"),
    (re.compile(r"^(Operator/index\.html|KSP-RO\.html)$"), "0.9", "weekly"),
    (re.compile(r"wiki/index\.html$"), "0.8", "weekly"),
    (re.compile(r"wiki/.+\.html$"), "0.6", "monthly"),
]

MARK_START, MARK_END = "<!-- SEO:START -->", "<!-- SEO:END -->"


def url_of(path: Path) -> str:
    """Канонический адрес: без index.html, с ведущим слэшем."""
    rel = path.relative_to(SITE).as_posix()
    if rel == "index.html":
        return f"{BASE}/"
    if rel.endswith("/index.html"):
        return f"{BASE}/{rel[:-len('index.html')]}"
    return f"{BASE}/{rel}"


def meta(text: str, name: str) -> str:
    m = re.search(rf'<meta name="{name}" content="([^"]*)"', text)
    return m.group(1) if m else ""


def title_of(text: str) -> str:
    m = re.search(r"<title>(.*?)</title>", text, re.S)
    return m.group(1).strip() if m else "kerbal.ru"


def jsonld(path: Path, url: str, title: str, desc: str) -> str:
    rel = path.relative_to(SITE).as_posix()
    esc = lambda s: s.replace("\\", "\\\\").replace('"', '\\"')

    if rel == "index.html":
        # Сайт + организация: даёт поиску имя проекта и строку поиска по сайту.
        body = f'''{{
  "@context": "https://schema.org",
  "@graph": [
    {{"@type": "WebSite", "@id": "{BASE}/#website", "url": "{BASE}/",
      "name": "kerbal.ru", "inLanguage": "ru",
      "description": "{esc(desc)}"}},
    {{"@type": "SoftwareApplication", "name": "kerbal.ru — русские сборки Kerbal Space Program",
      "applicationCategory": "GameApplication",
      "operatingSystem": "Windows, macOS, Linux, Steam Deck",
      "inLanguage": "ru", "url": "{BASE}/",
      "description": "{esc(desc)}",
      "offers": {{"@type": "Offer", "price": "0", "priceCurrency": "RUB"}},
      "isAccessibleForFree": true,
      "license": "https://github.com/plagness/kerbal.ru/blob/main/LICENSE.md"}}
  ]
}}'''
    elif "/wiki/" in rel and not rel.endswith("wiki/index.html"):
        body = f'''{{
  "@context": "https://schema.org",
  "@type": "TechArticle",
  "headline": "{esc(title.split(' — ')[0])}",
  "description": "{esc(desc)}",
  "inLanguage": "ru",
  "url": "{url}",
  "isPartOf": {{"@type": "WebSite", "@id": "{BASE}/#website"}},
  "author": {{"@type": "Organization", "name": "kerbal.ru"}}
}}'''
    else:
        body = f'''{{
  "@context": "https://schema.org",
  "@type": "WebPage",
  "name": "{esc(title)}",
  "description": "{esc(desc)}",
  "inLanguage": "ru",
  "url": "{url}",
  "isPartOf": {{"@type": "WebSite", "@id": "{BASE}/#website"}}
}}'''
    return f'<script type="application/ld+json">{body}</script>'


def seo_block(path: Path, text: str) -> str:
    url = url_of(path)
    title = title_of(text)
    desc = meta(text, "description")
    e = html.escape
    return "\n".join([
        MARK_START,
        f'<link rel="canonical" href="{url}">',
        '<meta property="og:type" content="website">',
        f'<meta property="og:url" content="{url}">',
        f'<meta property="og:title" content="{e(title)}">',
        f'<meta property="og:description" content="{e(desc)}">',
        f'<meta property="og:image" content="{OG_IMAGE}">',
        '<meta property="og:image:width" content="1200">',
        '<meta property="og:image:height" content="630">',
        '<meta property="og:site_name" content="kerbal.ru">',
        '<meta property="og:locale" content="ru_RU">',
        '<meta name="twitter:card" content="summary_large_image">',
        f'<meta name="twitter:title" content="{e(title)}">',
        f'<meta name="twitter:description" content="{e(desc)}">',
        f'<meta name="twitter:image" content="{OG_IMAGE}">',
        jsonld(path, url, title, desc),
        MARK_END,
    ])


def patch(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    block = seo_block(path, text)
    if MARK_START in text:
        new = re.sub(re.escape(MARK_START) + r".*?" + re.escape(MARK_END),
                     lambda _: block, text, flags=re.S)
    else:
        m = re.search(r"</title>", text)
        if not m:
            print(f"  ! в {path.name} нет <title> — пропуск")
            return False
        new = text[:m.end()] + "\n" + block + text[m.end():]
    if new == text:
        return False
    path.write_text(new, encoding="utf-8")
    return True


def sitemap(pages: list[Path]) -> str:
    today = date.today().isoformat()
    rows = []
    for p in sorted(pages, key=lambda x: url_of(x)):
        rel = p.relative_to(SITE).as_posix()
        prio, freq = "0.5", "monthly"
        for pat, pr, fr in PRIORITY:
            if pat.search(rel):
                prio, freq = pr, fr
                break
        rows.append(f"  <url>\n    <loc>{url_of(p)}</loc>\n"
                    f"    <lastmod>{today}</lastmod>\n"
                    f"    <changefreq>{freq}</changefreq>\n"
                    f"    <priority>{prio}</priority>\n  </url>")
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<urlset xmlns="http://www.sitemap.org/schemas/sitemap/0.9">\n'
            + "\n".join(rows) + "\n</urlset>\n").replace(
        "www.sitemap.org", "www.sitemaps.org")


ROBOTS = f"""# kerbal.ru — русский хаб KSP-моддинга
User-agent: *
Allow: /

# Служебное: скачивать можно, индексировать как страницы незачем.
Disallow: /dist/
Disallow: /data/

Sitemap: {BASE}/sitemap.xml
"""


def main() -> None:
    pages = [p for p in sorted(SITE.rglob("*.html"))]
    changed = sum(patch(p) for p in pages)

    (SITE / "sitemap.xml").write_text(sitemap(pages), encoding="utf-8")
    (SITE / "robots.txt").write_text(ROBOTS, encoding="utf-8")

    print(f"✓ SEO: {len(pages)} страниц, мета обновлена у {changed}")
    print(f"  → site/sitemap.xml ({len(pages)} адресов)")
    print(f"  → site/robots.txt")


if __name__ == "__main__":
    main()
