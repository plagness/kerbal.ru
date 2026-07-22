#!/usr/bin/env bash
# kerbal.ru — установщик русификатора для Linux / macOS / Steam Deck
# Скачивает переводы и копирует их в GameData уже собранной сборки RO/RSS/RP-1,
# затем включает русский язык. Существующие моды не трогает, только добавляет ru.cfg.
#
#   ./install-ru.sh                       # автопоиск установки KSP
#   ./install-ru.sh "/путь/к/Kerbal Space Program"   # явный путь
set -euo pipefail

REPO_ZIP="https://github.com/plagness/kerbal.ru/archive/refs/heads/main.zip"

say(){ printf '\033[1;36m» %s\033[0m\n' "$*"; }
err(){ printf '\033[1;31m× %s\033[0m\n' "$*" >&2; }

# 1. Найти установку KSP -----------------------------------------------------
KSP="${1:-}"
if [ -z "$KSP" ]; then
  for c in \
    "$HOME/.local/share/Steam/steamapps/common/Kerbal Space Program" \
    "$HOME/.steam/steam/steamapps/common/Kerbal Space Program" \
    "$HOME/Library/Application Support/Steam/steamapps/common/Kerbal Space Program" \
    "/run/media/deck"/*/steamapps/common/"Kerbal Space Program"; do
    [ -d "$c/GameData" ] && KSP="$c" && break
  done
fi
if [ -z "$KSP" ] || [ ! -d "$KSP/GameData" ]; then
  err "Не нашёл установку KSP. Укажи путь вручную:"
  err "  ./install-ru.sh \"/путь/к/Kerbal Space Program\""
  exit 1
fi
say "Установка KSP: $KSP"

# 2. Скачать и распаковать русификатор --------------------------------------
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
say "Скачиваю переводы…"
curl -fsSL -o "$TMP/ru.zip" "$REPO_ZIP"
say "Распаковываю…"
if command -v unzip >/dev/null 2>&1; then
  unzip -q "$TMP/ru.zip" -d "$TMP"
else
  python3 -c "import zipfile,sys;zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$TMP/ru.zip" "$TMP"
fi
SRC="$(find "$TMP" -maxdepth 2 -type d -name GameData | head -n1)"
[ -d "$SRC" ] || { err "В архиве не найдена папка GameData"; exit 1; }

# 3. Скопировать локализацию ------------------------------------------------
say "Копирую файлы локализации в GameData…"
cp -R "$SRC/." "$KSP/GameData/"

# 4. Включить русский язык ---------------------------------------------------
CFG="$KSP/settings.cfg"
if [ -f "$CFG" ]; then
  cp "$CFG" "$CFG.bak-kerbalru"
  if grep -q '^LANGUAGE' "$CFG"; then
    tmp="$(mktemp)"; sed 's/^LANGUAGE = .*/LANGUAGE = ru/' "$CFG" > "$tmp" && mv "$tmp" "$CFG"
  else
    printf '\nLANGUAGE = ru\n' >> "$CFG"
  fi
  say "Язык переключён на русский (бэкап settings.cfg рядом)."
else
  say "settings.cfg пока нет (создастся после первого запуска)."
  say "После первого запуска выбери язык в настройках игры → Русский."
fi

printf '\033[1;32m✓ Готово! Русификатор установлен. Запускай игру.\033[0m\n'
