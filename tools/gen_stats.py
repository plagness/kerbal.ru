#!/usr/bin/env python3
"""kerbal.ru — сбор статистики проекта в data/stats.json.

Два источника:
  • локальный git   — авторы (включая Co-Authored-By), рост по дням;
  • GitHub API      — звёзды, форки, релизы, скачивания ассетов.

GitHub-часть необязательна: без сети берутся прежние значения из stats.json,
файл не деградирует. Сайт читает stats.json как снимок и при загрузке
пробует обновить цифры живым запросом к api.github.com.

Запуск:  python3 tools/gen_stats.py [--offline]
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
import urllib.error
import urllib.request
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "site" / "data" / "stats.json"
REPO = "plagness/kerbal.ru"
API = f"https://api.github.com/repos/{REPO}"

# Роли и био берём из project.json, если участник там описан; всё остальное —
# имя, аватар, ссылка — приходит от GitHub. Ничего не рисуем руками.
#
# Тонкость: `/repos/.../contributors` возвращает только автора коммита, а
# соавторов из трейлера Co-Authored-By — нет (в веб-интерфейсе они есть).
# Поэтому логин соавтора выводим из подписи и ПРОВЕРЯЕМ через /users/<login>:
# берём только реально существующий аккаунт с совпавшим именем.


def git(*args: str) -> str:
    return subprocess.run(["git", "-C", str(ROOT), *args],
                          capture_output=True, text=True, check=True).stdout


def collect_people() -> list[dict]:
    """Автор коммита + все Co-Authored-By. Одна запись на человека/агента."""
    raw = git("log", "--all", "--format=%H%x00%an%x00%ae%x00%ad%x00%b%x1e",
              "--date=short")
    commits = [c for c in raw.split("\x1e") if c.strip()]

    seen: dict[str, dict] = {}
    counts: Counter[str] = Counter()
    first: dict[str, str] = {}
    last: dict[str, str] = {}

    def touch(key: str, name: str, email: str, date: str) -> None:
        counts[key] += 1
        first.setdefault(key, date)
        first[key] = min(first[key], date)
        last[key] = max(last.get(key, date), date)
        seen.setdefault(key, {"name": name, "email": email})

    for c in commits:
        parts = c.strip("\n").split("\x00")
        if len(parts) < 5:
            continue
        _sha, an, ae, date, body = parts[0], parts[1], parts[2], parts[3], parts[4]
        touch(person_key(an, ae), an, ae, date)
        for m in re.finditer(r"^Co-Authored-By:\s*(.+?)\s*<(.+?)>\s*$",
                             body, re.M | re.I):
            touch(person_key(m.group(1), m.group(2)), m.group(1), m.group(2), date)

    cached = {p.get("id"): p for p in prev_people()}
    people = []
    for key, info in seen.items():
        login, account = resolve_account(info["email"], info["name"], cached)
        person = {
            "id": login or key,
            "name": (account or {}).get("name") or info["name"],
            "github": login,
            "avatar": (account or {}).get("avatar_url", ""),
            "url": (account or {}).get("html_url", ""),
            "commits": counts[key],
            "firstCommit": first[key],
            "lastCommit": last[key],
        }
        people.append(person)

    # Роли и био для людей описаны в project.json — не дублируем их здесь.
    described = {}
    pj = ROOT / "site" / "data" / "project.json"
    if pj.exists():
        for person in json.loads(pj.read_text(encoding="utf-8")).get(
                "site", {}).get("contributors", []):
            described[person.get("github", "")] = person
    for person in people:
        extra = described.get(person.get("github", ""))
        if extra:
            person.setdefault("roles", extra.get("roles", []))
            person.setdefault("bio", extra.get("bio", ""))
        person.setdefault("roles", ["Участник"])

    people.sort(key=lambda p: -p["commits"])
    return people


def person_key(name: str, email: str) -> str:
    """Claude меняет версии в подписи — схлопываем в одного участника."""
    if "anthropic.com" in email.lower() or name.lower().startswith("claude"):
        return "claude"
    return email.lower()


def prev_people() -> list[dict]:
    if not OUT.exists():
        return []
    return json.loads(OUT.read_text(encoding="utf-8")).get("people", [])


def user(login: str) -> dict | None:
    try:
        req = urllib.request.Request(
            f"https://api.github.com/users/{login}",
            headers={"Accept": "application/vnd.github+json",
                     "User-Agent": "kerbal.ru-stats"})
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.load(r)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
        return None


def resolve_account(email: str, name: str, cached: dict) -> tuple[str, dict | None]:
    """Логин на GitHub → его карточка. Аккаунт всегда подтверждаем запросом."""
    m = re.match(r"^\d+\+([\w-]+)@users\.noreply\.github\.com$", email, re.I)
    candidates = [m.group(1)] if m else []
    if not candidates:
        # «Claude Opus 4.8» → пробуем claude, claude-opus. Берём тот аккаунт,
        # чьё отображаемое имя совпадает с первым словом подписи.
        words = re.findall(r"[A-Za-z][\w-]*", name)
        if words:
            candidates = [words[0].lower()]
            if len(words) > 1:
                candidates.append(f"{words[0]}-{words[1]}".lower())

    for login in candidates:
        prev = cached.get(login)
        if prev and prev.get("avatar"):
            # Уже подтверждали — не тратим лимит API на каждый прогон.
            return login, {"name": prev["name"], "avatar_url": prev["avatar"],
                           "html_url": prev["url"]}
        account = user(login)
        if not account:
            continue
        if m or (account.get("name") or "").split()[:1] == name.split()[:1]:
            return login, account
    return "", None


def growth() -> list[dict]:
    """Точка на каждый день, когда были коммиты: объём проекта на тот момент."""
    days = sorted(set(git("log", "--all", "--format=%ad", "--date=short").split()))
    series = []
    for day in days:
        sha = git("log", "--all", "--format=%H", "--before", f"{day} 23:59:59",
                  "-1").strip()
        if not sha:
            continue
        files = git("ls-tree", "-r", "--name-only", sha).splitlines()
        commits = len(git("log", sha, "--format=%H").split())
        series.append({
            "date": day,
            "commits": commits,
            "translations": len({f.split("/")[1] for f in files
                                 if f.startswith("translations/") and "/" in f[13:]}),
            # вики принадлежит сборке: builds/<id>/wiki/*.md (без служебных _*)
            "wiki": sum(1 for f in files
                        if re.match(r"^(builds/[^/]+/)?wiki/[^_/][^/]*\.md$", f)),
            "builds": len({f.split("/")[1] for f in files
                           if f.startswith("builds/") and "/" in f[7:]}),
            "kos": sum(1 for f in files if f.startswith("kos/") and f.endswith(".ks")),
        })
    return series


def api(path: str) -> object | None:
    try:
        req = urllib.request.Request(API + path,
                                     headers={"Accept": "application/vnd.github+json",
                                              "User-Agent": "kerbal.ru-stats"})
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.load(r)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
        print(f"  ! GitHub API недоступен ({path}): {e}", file=sys.stderr)
        return None


def repo_stats(prev: dict) -> dict:
    info = api("")
    releases = api("/releases?per_page=100")
    if info is None or releases is None:
        print("  → беру прежние цифры GitHub из stats.json", file=sys.stderr)
        return prev.get("repo", {})

    by_release, downloads = [], 0
    for r in releases:
        n = sum(a["download_count"] for a in r.get("assets", []))
        downloads += n
        by_release.append({
            "version": r["tag_name"],
            "date": (r.get("published_at") or "")[:10],
            "downloads": n,
            "assets": [{"name": a["name"], "downloads": a["download_count"]}
                       for a in r.get("assets", [])],
        })

    # Скачивания разрезаем двояко: по назначению ассета и по сборке.
    # Имена: kerbalru-translations-<версия>.zip        — вся библиотека,
    #        kerbalru-translations-<сборка>-<в>.zip    — пакет сборки,
    #        <сборка>.ckan                             — метапакет CKAN.
    builds = [p.name for p in sorted((ROOT / "builds").iterdir()) if p.is_dir()]
    kinds, by_build = Counter(), Counter()
    for r in by_release:
        for a in r["assets"]:
            name, n = a["name"], a["downloads"]
            build = next((b for b in builds
                          if name == f"{b}.ckan" or f"-{b}-" in name), "")
            if build:
                by_build[build] += n
            if name.endswith(".ckan"):
                kinds["ckan"] += n
            elif build:
                kinds["build"] += n
            else:
                kinds["translations"] += n

    return {
        "stars": info["stargazers_count"],
        "forks": info["forks_count"],
        "watchers": info["subscribers_count"],
        "openIssues": info["open_issues_count"],
        "createdAt": info["created_at"][:10],
        "topics": info.get("topics", []),
        "releases": len(by_release),
        "downloads": downloads,
        "downloadsByKind": dict(kinds),
        "downloadsByBuild": dict(by_build),
        "byRelease": by_release[:20],
    }


SPARK = "▁▂▃▄▅▆▇█"


def spark(values: list[int]) -> str:
    """Кривая роста прямо в тексте — без картинок и внешних сервисов."""
    if not values:
        return ""
    lo, hi = min(values), max(values)
    if hi == lo:
        return SPARK[0] * len(values)
    return "".join(SPARK[round((v - lo) / (hi - lo) * (len(SPARK) - 1))]
                   for v in values)


def readme_block(data: dict) -> str:
    """Блок «Проект в цифрах» для README между маркерами STATS."""
    t, repo, series = data["totals"], data["repo"], data["growth"]
    rows = [
        ("Переводов модов", t["translations"], "translations"),
        ("Статей вики", t["wiki"], "wiki"),
        ("Коммитов", t["commits"], "commits"),
    ]
    lines = [
        "## Проект в цифрах",
        "",
        f"Живой срез на {data['generatedAt'][:10]}. Считается по истории репозитория "
        "и GitHub API генератором `tools/gen_stats.py` — руками этот блок не правится.",
        "",
        "| | Сейчас | Рост по дням |",
        "|---|---:|---|",
    ]
    for label, value, key in rows:
        lines.append(f"| {label} | **{value}** | `{spark([p[key] for p in series])}` |")
    if repo:
        lines += [
            f"| Звёзд на GitHub | **{repo['stars']}** | релизов: {repo['releases']} |",
            f"| Скачиваний релизов | **{repo['downloads']}** | "
            + " · ".join(f"{b}: {n}" for b, n in
                         sorted(repo.get("downloadsByBuild", {}).items())) + " |",
        ]
    if series:
        lines += ["", f"Первый коммит — {series[0]['date']}, дней работы — {t['days']}."]

    lines += ["", "### Кто это делает", ""]
    for p in data["people"]:
        who = f"[{p['name']}]({p['url']})" if p.get("url") else p["name"]
        roles = ", ".join(p.get("roles", [])) or "участник"
        lines.append(f"- **{who}** — {roles} · {p['commits']} коммитов, "
                     f"с {p['firstCommit']}")
    lines += ["", "Список собирается из git и включает соавторов из трейлера "
                  "`Co-Authored-By` — их GitHub в списке контрибьюторов API не показывает."]
    return "\n".join(lines)


def refresh_counts(path: Path, data: dict) -> None:
    """Числа в бейджах и тексте README — те же, что в статистике."""
    t = data["totals"]
    text = path.read_text(encoding="utf-8")
    wiki_word = plural_ru(t["wiki"], "статья", "статьи", "статей")
    subs = [
        (r"переводов-\d+%20модов", f"переводов-{t['translations']}%20модов"),
        (r"вики-\d+%20стат\w+", f"вики-{t['wiki']}%20{wiki_word}"),
        (r"— \d+ стат\w+: связь", f"— {t['wiki']} {wiki_word}: связь"),
    ]
    new, dead = text, []
    for pat, rep in subs:
        if not re.search(pat, new):
            # Текст README поменяли, шаблон больше ни во что не попадает: молча
            # разошедшиеся цифры хуже, чем шумная строка в выводе.
            dead.append(pat)
            continue
        new = re.sub(pat, rep, new)
    for pat in dead:
        print(f"  ! шаблон не нашёл совпадений, число могло устареть: {pat}", file=sys.stderr)
    if new != text:
        path.write_text(new, encoding="utf-8")
        print(f"  → {path.name}: числа в тексте синхронизированы")


def plural_ru(n: int, one: str, few: str, many: str) -> str:
    a, b = abs(n) % 100, abs(n) % 10
    if 10 < a < 20:
        return many
    if 1 < b < 5:
        return few
    if b == 1:
        return one
    return many


def splice(path: Path, marker: str, block: str) -> None:
    text = path.read_text(encoding="utf-8")
    start, end = f"<!-- {marker}:START -->", f"<!-- {marker}:END -->"
    if start not in text or end not in text:
        print(f"  ! в {path.name} нет маркеров {marker} — пропуск", file=sys.stderr)
        return
    head, rest = text.split(start, 1)
    _old, tail = rest.split(end, 1)
    path.write_text(f"{head}{start}\n{block}\n{end}{tail}", encoding="utf-8")
    print(f"  → {path.name}: блок {marker} обновлён")


def main() -> None:
    prev = json.loads(OUT.read_text(encoding="utf-8")) if OUT.exists() else {}
    offline = "--offline" in sys.argv

    people = collect_people()
    series = growth()
    repo = prev.get("repo", {}) if offline else repo_stats(prev)

    data = {
        "_comment": "Генерируется tools/gen_stats.py. Руками не править.",
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "repo": repo,
        "people": people,
        "totals": {
            "commits": series[-1]["commits"] if series else 0,
            "contributors": len(people),
            "translations": series[-1]["translations"] if series else 0,
            "wiki": series[-1]["wiki"] if series else 0,
            "kosScripts": series[-1]["kos"] if series else 0,
            "days": len(series),
        },
        "growth": series,
    }
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n",
                   encoding="utf-8")

    splice(ROOT / "README.md", "STATS", readme_block(data))
    refresh_counts(ROOT / "README.md", data)

    t = data["totals"]
    print(f"✓ {OUT.relative_to(ROOT)}")
    print(f"  участники : {', '.join(p['name'] + ' (' + str(p['commits']) + ')' for p in people)}")
    print(f"  проект    : {t['commits']} коммитов, {t['translations']} переводов, "
          f"{t['wiki']} статей вики, {t['kosScripts']} kOS-скриптов за {t['days']} дн.")
    if repo:
        print(f"  github    : ★{repo['stars']} · {repo['releases']} релизов · "
              f"{repo['downloads']} скачиваний {repo.get('downloadsByKind', {})}")


if __name__ == "__main__":
    main()
