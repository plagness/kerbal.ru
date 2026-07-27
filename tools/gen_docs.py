#!/usr/bin/env python3
"""kerbal.ru — единая навигация в шапке документов.

В каждый .md сразу под заголовком первого уровня вставляется одна строка
ссылок на соседние документы; текущий документ в ней не ссылка, а жирный текст.
Строка живёт между маркерами и переписывается целиком:

    <!-- NAV:START -->
    ...
    <!-- NAV:END -->

Маркеры генератор ставит сам при первом прогоне. Запуск: python3 tools/gen_docs.py
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Порядок = порядок в строке навигации. Ключ — путь от корня репозитория.
NAV: list[tuple[str, str]] = [
    ("README.md", "Обзор"),
    ("docs/STATUS.md", "Статус"),
    ("docs/QUICKSTART.md", "Установка"),
    ("docs/MAINTAINING.md", "Переводы"),
    ("docs/COVERAGE.md", "Охват"),
    ("docs/ROADMAP.md", "Планы"),
    ("kos/README.md", "kOS"),
    ("CONTRIBUTING.md", "Участие"),
]
# Документы, которые сами в строке не участвуют, но шапку получают.
EXTRA = [
    "docs/UPDATING.md", "docs/UI-TRANSLATION.md", "docs/PERFORMANCE.md",
    "docs/FOR-AGENTS.md", "AGENTS.md", "CHANGELOG.md", "GOVERNANCE.md",
    "SUPPORT.md", "SECURITY.md", "CODE_OF_CONDUCT.md", "perf/README.md",
]


def rel(from_doc: str, to_doc: str) -> str:
    """Относительная ссылка между двумя файлами репозитория."""
    up = "../" * from_doc.count("/")
    target = to_doc
    # Ссылка внутри той же папки — без ведущего пути.
    from_dir, to_dir = from_doc.rsplit("/", 1)[0], to_doc.rsplit("/", 1)[0]
    if "/" in from_doc and from_dir == to_dir:
        return to_doc.rsplit("/", 1)[1]
    return up + target


def nav_line(doc: str) -> str:
    parts = []
    for path, label in NAV:
        if path == doc:
            parts.append(f"**{label}**")
        else:
            parts.append(f"[{label}]({rel(doc, path)})")
    return " · ".join(parts)


def apply(doc: str) -> bool:
    path = ROOT / doc
    if not path.exists():
        print(f"  ! нет файла: {doc}")
        return False
    text = path.read_text(encoding="utf-8")
    block = f"<!-- NAV:START -->\n{nav_line(doc)}\n<!-- NAV:END -->"

    if "<!-- NAV:START -->" in text:
        new = re.sub(r"<!-- NAV:START -->.*?<!-- NAV:END -->", block, text, flags=re.S)
    else:
        # Ставим после заголовка первого уровня; в README — после шапки div.
        m = re.search(r"^# .+$", text, re.M)
        if not m:
            print(f"  ! в {doc} нет заголовка H1 — пропуск")
            return False
        cut = m.end()
        new = text[:cut] + "\n\n" + block + text[cut:]

    if new == text:
        return False
    path.write_text(new, encoding="utf-8")
    return True


def main() -> None:
    docs = [d for d, _ in NAV if d != "README.md"] + EXTRA
    changed = sum(apply(d) for d in docs)
    print(f"✓ навигация: обновлено {changed} из {len(docs)} документов")


if __name__ == "__main__":
    main()
