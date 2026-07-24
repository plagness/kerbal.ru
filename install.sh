#!/usr/bin/env bash
# kerbal.ru — менеджер сборок KSP 1.12.5.
# Выбирает/обновляет/меняет курируемую сборку из каталога builds/ и накатывает русик.
# Философия: чужие моды НЕ храним — ставим их официальным CKAN (headless), храним только
# свои дескрипторы сборок и переводы. Состояние установки пишем в $KSP/.kerbalru-build.json.
set -euo pipefail

REPO="plagness/kerbal.ru"
RAW="https://raw.githubusercontent.com/$REPO/main"
STATE_FILE=".kerbalru-build.json"
CKAN_REPO="KSP-CKAN/CKAN"

# Каталог сборок: локально (запуск из репо) или скачиваем из релиза (curl-режим).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
BUILDS_DIR=""
KSP_PATH=""
WANT_BUILD=""
MODE=""            # "" | update | switch | ru-only | list
ASSUME_YES=false

say(){ printf '\033[1;36m» %s\033[0m\n' "$*"; }
ok(){  printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
warn(){ printf '\033[1;33m! %s\033[0m\n' "$*"; }
err(){ printf '\033[1;31m× %s\033[0m\n' "$*" >&2; }
tty_ok(){ { true > /dev/tty; } 2>/dev/null; }   # есть ли управляющий терминал для интерактива

usage(){ cat <<'EOF'
kerbal.ru — установка и управление сборками KSP

Использование:
  install.sh [путь к KSP] [параметры]

Параметры:
  --build <id>     поставить/сменить на конкретную сборку (без интерактива)
  --update         обновить текущую установленную сборку
  --ru-only        только обновить переводы поверх текущей сборки
  --list           показать каталог сборок и выйти
  --yes            не спрашивать подтверждений (для CI/скриптов)
  --help           показать справку

Без параметров: если сборка уже стоит — предложит обновить/сменить; иначе — выбор сборки.
EOF
}

# ── аргументы ────────────────────────────────────────────────────────────────
while [ "$#" -gt 0 ]; do
  case "$1" in
    --build) [ "$#" -ge 2 ] || { err "После --build нужен id сборки"; exit 2; }; WANT_BUILD="$2"; shift ;;
    --update)  MODE="update" ;;
    --ru-only) MODE="ru-only" ;;
    --list)    MODE="list" ;;
    --yes|-y)  ASSUME_YES=true ;;
    --help|-h) usage; exit 0 ;;
    --*) err "Неизвестный параметр: $1"; usage; exit 2 ;;
    *) [ -z "$KSP_PATH" ] || { err "Путь к KSP уже указан"; exit 2; }; KSP_PATH="$1" ;;
  esac
  shift
done

# ── каталог сборок (локально или скачать) ────────────────────────────────────
WORK_DIR="$(mktemp -d)"; trap 'rm -rf "$WORK_DIR"' EXIT
if [ -n "$SCRIPT_DIR" ] && [ -d "$SCRIPT_DIR/builds" ]; then
  BUILDS_DIR="$SCRIPT_DIR/builds"
else
  say "Скачиваю каталог сборок…"
  curl -fsSL -o "$WORK_DIR/catalog.tar.gz" "https://github.com/$REPO/archive/refs/heads/main.tar.gz"
  tar -xzf "$WORK_DIR/catalog.tar.gz" -C "$WORK_DIR"
  BUILDS_DIR="$(find "$WORK_DIR" -maxdepth 2 -type d -name builds | head -n1)"
fi
[ -d "$BUILDS_DIR" ] || { err "Не нашёл каталог сборок (builds/)"; exit 1; }

# builds список = имена подпапок с build.json
list_build_ids(){ for d in "$BUILDS_DIR"/*/; do [ -f "$d/build.json" ] && basename "$d"; done; }
bj(){ # bj <build-id> <python-выражение над d>
  python3 -c "import json;d=json.load(open('$BUILDS_DIR/$1/build.json'));print($2)" 2>/dev/null
}
build_install_ids(){ # список id для установки: core + recommended (optional ставит юзер отдельно)
  python3 - "$BUILDS_DIR/$1/build.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); m=d.get('mods',{})
print(' '.join(list(m.get('core',[]))+list(m.get('recommended',[]))))
PY
}

show_catalog(){
  say "Каталог сборок kerbal.ru:"
  local i=0
  for id in $(list_build_ids); do
    i=$((i+1))
    printf '  \033[1m%d) %-10s\033[0m %s\n' "$i" "$id" "$(bj "$id" "d['name']")"
    printf '       %s\n' "$(bj "$id" "d.get('tagline','')")"
  done
}
if [ "$MODE" = "list" ]; then show_catalog; exit 0; fi

# ── найти KSP ────────────────────────────────────────────────────────────────
if [ -z "$KSP_PATH" ]; then
  for c in \
    "$HOME/.local/share/Steam/steamapps/common/Kerbal Space Program" \
    "$HOME/.steam/steam/steamapps/common/Kerbal Space Program" \
    "$HOME/Library/Application Support/Steam/steamapps/common/Kerbal Space Program" \
    /run/media/deck/*/steamapps/common/"Kerbal Space Program"; do
    [ -d "$c/GameData" ] && KSP_PATH="$c" && break
  done
fi
[ -n "$KSP_PATH" ] && [ -d "$KSP_PATH/GameData" ] || { err "Не нашёл KSP. Укажи путь: install.sh \"/путь/к/Kerbal Space Program\""; exit 1; }
say "Установка KSP: $KSP_PATH"

# ── определить текущую сборку ─────────────────────────────────────────────────
CURRENT=""
if [ -f "$KSP_PATH/$STATE_FILE" ]; then
  CURRENT="$(python3 -c "import json;print(json.load(open('$KSP_PATH/$STATE_FILE')).get('build',''))" 2>/dev/null || echo "")"
fi

# ── CKAN (mono + ckan.exe: свой из окружения, из PATH или скачать) ────────────
MONO="$(command -v mono || echo /Library/Frameworks/Mono.framework/Versions/Current/Commands/mono)"
CKAN_EXE="${KERBALRU_CKAN:-}"
run_ckan(){
  if [ -n "$CKAN_EXE" ]; then "$MONO" "$CKAN_EXE" "$@";
  elif command -v ckan >/dev/null 2>&1; then command ckan "$@";
  else "$MONO" "$WORK_DIR/ckan.exe" "$@"; fi
}
ensure_ckan(){
  [ -n "$CKAN_EXE" ] && return 0
  command -v ckan >/dev/null 2>&1 && return 0
  [ -f "$WORK_DIR/ckan.exe" ] && return 0
  command -v "$MONO" >/dev/null 2>&1 || { err "Нужен mono (brew install mono / apt install mono-complete)"; exit 1; }
  say "Скачиваю CKAN…"
  local url; url="$(curl -fsSL "https://api.github.com/repos/$CKAN_REPO/releases/latest" | sed -n 's/.*"browser_download_url": *"\([^"]*\/ckan\.exe\)".*/\1/p' | head -n1)"
  curl -fsSL -o "$WORK_DIR/ckan.exe" "$url"
}

confirm(){ # confirm "вопрос"  → 0 если да
  [ "$ASSUME_YES" = true ] && return 0
  local ans=""; printf '\033[1;33m! %s [y/N]: \033[0m' "$1" > /dev/tty
  read -r ans < /dev/tty 2>/dev/null || ans=""
  case "$ans" in y|Y|yes|да|Да) return 0 ;; *) return 1 ;; esac
}

# ── операции над установкой ───────────────────────────────────────────────────
clean_to_stock(){
  warn "Удаляю моды текущей сборки (стоковый Squad остаётся; сейвы в saves/ не трогаю)…"
  local mods; mods="$(run_ckan list --porcelain --gamedir "$KSP_PATH" 2>/dev/null | grep -v '^[[:space:]]*$' | tr '\n' ' ' || true)"
  if [ -n "$mods" ]; then run_ckan uninstall --headless --gamedir "$KSP_PATH" $mods >/dev/null 2>&1 || true; fi
  find "$KSP_PATH/GameData" -mindepth 1 -maxdepth 1 ! -name 'Squad' ! -name 'SquadExpansion' -exec rm -rf {} + 2>/dev/null || true
  ok "GameData очищен до стока."
}

apply_translations(){ # русик: язык + движок(engine/) + переводы(translations/) под установленные моды
  local settings="$KSP_PATH/settings.cfg"
  if [ -f "$settings" ]; then
    [ -f "$settings.bak-kerbalru" ] || cp -p "$settings" "$settings.bak-kerbalru"
    if grep -q '^LANGUAGE' "$settings"; then
      local t; t="$(mktemp)"; sed 's/^LANGUAGE = .*/LANGUAGE = ru/' "$settings" > "$t"; mv "$t" "$settings"
    else printf '
LANGUAGE = ru
' >> "$settings"; fi
  fi
  local root; root="$(dirname "$BUILDS_DIR")"
  # движок ui-translator
  if [ -d "$root/engine/Plugins" ]; then
    mkdir -p "$KSP_PATH/GameData/kerbalru-ui-translator/Plugins"
    cp -p "$root/engine/Plugins/"*.dll "$KSP_PATH/GameData/kerbalru-ui-translator/Plugins/" 2>/dev/null || true
  fi
  # библиотека переводов — ТОЛЬКО под реально установленные моды (translation.json.folder).
  # Localization → zzz-kerbalru-translations/ (сортируется ПОСЛЕ RealismOverhaul: наши :FINAL-title выигрывают).
  # ui-словари → в папку движка (DLL грузит все KerbalRuUiTranslations/*.txt).
  rm -rf "$KSP_PATH/GameData/zzz-kerbalru-translations" 2>/dev/null || true
  local lib="$root/translations" tc=0
  if [ -d "$lib" ]; then
    for tdir in "$lib"/*/; do
      [ -f "${tdir}translation.json" ] || continue
      local folder; folder="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('folder',''))" "${tdir}translation.json" 2>/dev/null || echo "")"
      # folder="*" — общий словарь (напр. PAW-метки), деплоится всегда; иначе — только под установленный мод
      [ "$folder" = "*" ] || { [ -n "$folder" ] && [ -d "$KSP_PATH/GameData/$folder" ]; } || continue
      local tid; tid="$(basename "$tdir")"
      if ls "${tdir}Localization/"*.cfg >/dev/null 2>&1; then
        mkdir -p "$KSP_PATH/GameData/zzz-kerbalru-translations/$tid"
        cp -p "${tdir}Localization/"*.cfg "$KSP_PATH/GameData/zzz-kerbalru-translations/$tid/" 2>/dev/null || true
        tc=$((tc+1))
      fi
      if ls "${tdir}KerbalRuUiTranslations/"*.txt >/dev/null 2>&1; then
        mkdir -p "$KSP_PATH/GameData/kerbalru-ui-translator/KerbalRuUiTranslations"
        cp -p "${tdir}KerbalRuUiTranslations/"*.txt "$KSP_PATH/GameData/kerbalru-ui-translator/KerbalRuUiTranslations/" 2>/dev/null || true
      fi
    done
  fi
  ok "Русский язык + переводы под установленные моды ($tc мод(ов))."
}

disable_burst_on_mac(){ # KSPBurst-компилятор (Unity Burst) не компилируется на macOS/Apple Silicon и
  # спамит исключениями (BackgroundResourceProcessing) → просадка FPS, глюки. Убираем компилятор,
  # плагины оставляем → BRP переходит на managed-код без ошибок. См. память burst-mac-incompat.
  [ "$(uname -s)" = "Darwin" ] || return 0
  [ -d "$KSP_PATH/GameData/000_KSPBurst" ] || return 0
  local hit=0 f
  for f in "$KSP_PATH/GameData/000_KSPBurst/"com.unity.burst@*.zip; do [ -f "$f" ] && { rm -f "$f"; hit=1; }; done
  for f in "$KSP_PATH/PluginData/"KSPBurst@*; do [ -e "$f" ] && { rm -rf "$f"; hit=1; }; done
  [ "$hit" = 1 ] && ok "macOS: Burst-компилятор KSPBurst отключён (несовместим с Apple Silicon; BRP → managed-код, −~1.2 ГБ)."
  return 0
}

write_state(){ # write_state <build-id>
  local bid="$1" ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # porcelain: "<статус> <id> <версия>" → берём id (2-е поле)
  local installed; installed="$(run_ckan list --porcelain --gamedir "$KSP_PATH" 2>/dev/null | awk 'NF{print $2}' | tr '\n' ' ' || true)"
  KRU_TS="$ts" KRU_INST="$installed" python3 - "$BUILDS_DIR/$bid/build.json" "$KSP_PATH/$STATE_FILE" <<'PY'
import json,sys,os
d=json.load(open(sys.argv[1]))
state={
  "build": d["id"], "buildName": d["name"], "status": d.get("status"),
  "installedAt": os.environ["KRU_TS"], "kspVersion": d.get("kspVersion"),
  "system": d.get("system"),
  "mods": d.get("mods",{}),
  "ckan": d.get("ckan",{}),
  "installed": [x for x in os.environ["KRU_INST"].split() if x],
}
json.dump(state, open(sys.argv[2],"w"), ensure_ascii=False, indent=2)
PY
  ok "Состояние записано: $KSP_PATH/$STATE_FILE"
}

install_build(){ # install_build <build-id> ; предполагает уже чистую под сборку установку
  local bid="$1"
  ensure_ckan
  say "Обновляю индекс модов CKAN…"; run_ckan update --headless >/dev/null 2>&1 || run_ckan update >/dev/null 2>&1 || true
  # совместимые версии (для модов с отставшим тегом, напр. CommNet Constellation @1.11)
  local compat; compat="$(bj "$bid" "' '.join(d.get('ckan',{}).get('compatVersions',[]))")"
  if [ -n "$compat" ]; then say "Помечаю совместимыми версии: $compat"; run_ckan compat add --gamedir "$KSP_PATH" $compat >/dev/null 2>&1 || true; fi
  local ids; ids="$(build_install_ids "$bid")"
  # Курируемая сборка: ставим ровно core+recommended (+обязательные depends), без фаззи-recommends CKAN — детерминизм.
  local rflag="--no-recommends"
  say "Ставлю сборку «$(bj "$bid" "d['name']")» через CKAN (несколько ГБ, надолго)…"
  say "  моды: $ids"
  run_ckan install --headless $rflag --gamedir "$KSP_PATH" $ids
  disable_burst_on_mac
  apply_translations
  # конфиг сборки (напр. мягкий пресет KCT) → GameData, структура config/ зеркалит GameData/
  if [ -d "$BUILDS_DIR/$bid/config" ]; then
    cp -R "$BUILDS_DIR/$bid/config/." "$KSP_PATH/GameData/"
    ok "Конфиг сборки развёрнут (config/ → GameData/)."
  fi
  write_state "$bid"
  ok "Сборка «$(bj "$bid" "d['name']")» установлена. Запускай игру."
}

do_switch(){ # do_switch <build-id>
  local bid="$1"
  if [ -n "$CURRENT" ] && [ "$CURRENT" != "$bid" ]; then
    warn "Смена сборки «$CURRENT» → «$bid». Текущие моды будут удалены (сейвы сохранятся, но могут не загрузиться в новой сборке)."
    confirm "Продолжить смену сборки?" || { say "Отменено."; exit 0; }
    clean_to_stock
  fi
  install_build "$bid"
}

# ── маршрутизация ─────────────────────────────────────────────────────────────
select_build_interactive(){
  show_catalog
  local ids=($(list_build_ids)) choice=""
  printf '\033[1;36m» Номер сборки для установки: \033[0m' > /dev/tty
  read -r choice < /dev/tty 2>/dev/null || choice=""
  [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#ids[@]}" ] || { err "Неверный выбор"; exit 2; }
  echo "${ids[$((choice-1))]}"
}

# явный флаг --build
if [ -n "$WANT_BUILD" ]; then
  [ -f "$BUILDS_DIR/$WANT_BUILD/build.json" ] || { err "Нет такой сборки: $WANT_BUILD (см. --list)"; exit 2; }
  if [ "$MODE" = "ru-only" ]; then apply_translations; exit 0; fi
  do_switch "$WANT_BUILD"; exit 0
fi

# режимы --update / --ru-only
if [ "$MODE" = "ru-only" ]; then apply_translations; exit 0; fi
if [ "$MODE" = "update" ]; then
  [ -n "$CURRENT" ] || { err "Сборка не установлена — нечего обновлять. Запусти без --update для выбора."; exit 2; }
  install_build "$CURRENT"; exit 0
fi

# интерактив требует терминал
if ! tty_ok; then
  if [ -n "$CURRENT" ]; then
    err "Нет терминала для интерактива. Текущая сборка: «$CURRENT». Используй --update, --build <id> или --ru-only."
  else
    err "Нет терминала для интерактивного выбора. Укажи явно --build <id> (список: --list)."
  fi
  exit 2
fi

# интерактив
if [ -n "$CURRENT" ]; then
  say "Обнаружена установленная сборка: «$(bj "$CURRENT" "d['name']" 2>/dev/null || echo "$CURRENT")» ($CURRENT)"
  cat > /dev/tty <<EOF
  [1] Обновить текущую сборку «$CURRENT»
  [2] Поставить другую сборку
  [3] Только обновить переводы
  [4] Отмена
EOF
  printf '\033[1;36m» Выбор [1-4]: \033[0m' > /dev/tty
  a=""; read -r a < /dev/tty 2>/dev/null || a=""
  case "$a" in
    1) install_build "$CURRENT" ;;
    2) do_switch "$(select_build_interactive)" ;;
    3) apply_translations ;;
    *) say "Отменено." ;;
  esac
else
  say "Установленной сборки нет — выбери из каталога."
  do_switch "$(select_build_interactive)"
fi
