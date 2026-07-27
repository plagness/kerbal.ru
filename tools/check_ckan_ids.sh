#!/usr/bin/env bash
# kerbal.ru — сверить id модов всех сборок с индексом CKAN.
#
# Зачем: мод могут переименовать, снять с поддержки или пометить несовместимым
# с 1.12.5 — и тогда установка сборки падает у пользователя, а не у нас.
# Проверка делается против того же индекса, которым пользуется install.sh.
#
#   tools/check_ckan_ids.sh [путь к KSP]
#
# Путь нужен только как «якорь» для CKAN (он определяет версию игры по нему).
# Если не указан — создаётся временная пустышка KSP 1.12.5, игра не требуется.
# Нужен mono; ckan.exe скачивается во временную папку, если его нет в PATH.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
KSP="${1:-}"

say(){ printf '\033[1;36m» %s\033[0m\n' "$*"; }
ok(){  printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
err(){ printf '\033[1;31m× %s\033[0m\n' "$*" >&2; }

MONO="$(command -v mono || echo /Library/Frameworks/Mono.framework/Versions/Current/Commands/mono)"
command -v "$MONO" >/dev/null 2>&1 || { err "нужен mono (brew install mono / apt install mono-complete)"; exit 1; }

if command -v ckan >/dev/null 2>&1; then
  CKAN=(command ckan)
else
  say "скачиваю CKAN…"
  url="$(curl -fsSL https://api.github.com/repos/KSP-CKAN/CKAN/releases/latest \
        | sed -n 's/.*"browser_download_url": *"\([^"]*\/ckan\.exe\)".*/\1/p' | head -n1)"
  curl -fsSL -o "$WORK/ckan.exe" "$url"
  CKAN=("$MONO" "$WORK/ckan.exe")
fi

# CKAN опознаёт установку по buildID/readme — этого достаточно, файлы игры не нужны.
if [ -z "$KSP" ]; then
  KSP="$WORK/Kerbal Space Program"
  mkdir -p "$KSP/GameData/Squad" "$KSP/KSP_x64_Data"
  printf 'Version 1.12.5\n' > "$KSP/readme.txt"
  printf 'build id = 03243\n2021-12-03\n' > "$KSP/buildID.txt"
  cp "$KSP/buildID.txt" "$KSP/buildID64.txt"
fi

export HOME="$WORK/home"; mkdir -p "$HOME"
"${CKAN[@]}" instance add check "$KSP" >/dev/null 2>&1 || true
say "обновляю индекс модов…"
"${CKAN[@]}" update >/dev/null 2>&1 || { err "не удалось обновить индекс CKAN"; exit 1; }

# Совместимые версии из сборок — как их выставляет install.sh перед установкой.
compat="$(python3 - "$ROOT" <<'PY'
import json, sys
from pathlib import Path
vs = set()
for bj in sorted((Path(sys.argv[1]) / "builds").glob("*/build.json")):
    vs.update(json.loads(bj.read_text(encoding="utf-8")).get("ckan", {}).get("compatVersions", []))
print(" ".join(sorted(vs)))
PY
)"
[ -n "$compat" ] && "${CKAN[@]}" compat add --gamedir "$KSP" $compat >/dev/null 2>&1 || true

"${CKAN[@]}" available --gamedir "$KSP" 2>/dev/null | sed -n 's/^\* \([^ ]*\) .*/\1/p' > "$WORK/avail.txt"
total_avail="$(wc -l < "$WORK/avail.txt" | tr -d ' ')"
[ "$total_avail" -gt 100 ] || { err "индекс подозрительно мал ($total_avail) — проверка недостоверна"; exit 1; }
say "в индексе $total_avail модов, совместимых с игрой"

python3 - "$ROOT" "$WORK/avail.txt" <<'PY'
import json, sys
from pathlib import Path

root, avail_path = Path(sys.argv[1]), Path(sys.argv[2])
avail = set(avail_path.read_text(encoding="utf-8").split())
bad, total = [], 0
for bj in sorted((root / "builds").glob("*/build.json")):
    d = json.loads(bj.read_text(encoding="utf-8"))
    for kind in ("core", "recommended", "optional"):
        for mod in d.get("mods", {}).get(kind, []):
            total += 1
            if mod not in avail:
                bad.append((d["id"], kind, mod))

for bid, kind, mod in bad:
    blocking = kind in ("core", "recommended")
    mark = "✗ СТАВИТСЯ" if blocking else "✗ optional"
    print(f"  {mark}  {bid}/{kind}: {mod}")
print(f"\nпроверено {total} id, недоступно {len(bad)}")
# Падаем только на том, что установщик реально ставит: core и recommended.
sys.exit(1 if any(k in ("core", "recommended") for _, k, _ in bad) else 0)
PY
ok "id сборок сверены с индексом CKAN"
