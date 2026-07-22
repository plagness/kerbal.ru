#!/usr/bin/env bash
# kerbal.ru — установщик и обновлятор для Linux / macOS / Steam Deck.
set -euo pipefail

REPO="plagness/kerbal.ru"
CHANNEL="stable"
REQUESTED_VERSION=""
KSP_PATH=""
CHECK_ONLY=false
FORCE=false

say(){ printf '\033[1;36m» %s\033[0m\n' "$*"; }
ok(){ printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
err(){ printf '\033[1;31m× %s\033[0m\n' "$*" >&2; }
usage(){
  cat <<'EOF'
kerbal.ru — установка и обновление русификатора

Использование:
  install-ru.sh [путь к KSP] [параметры]

Параметры:
  --check                 только проверить наличие обновления
  --version v26.1         установить или откатить конкретный релиз
  --channel stable|main   стабильный релиз (по умолчанию) или main
  --force                 переустановить ту же версию
  --help                  показать справку
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) CHECK_ONLY=true ;;
    --force) FORCE=true ;;
    --version)
      [ "$#" -ge 2 ] || { err "После --version нужна версия"; exit 2; }
      REQUESTED_VERSION="$2"; shift ;;
    --channel)
      [ "$#" -ge 2 ] || { err "После --channel нужен stable или main"; exit 2; }
      CHANNEL="$2"; shift ;;
    --help|-h) usage; exit 0 ;;
    --*) err "Неизвестный параметр: $1"; usage; exit 2 ;;
    *)
      [ -z "$KSP_PATH" ] || { err "Путь к KSP уже указан"; exit 2; }
      KSP_PATH="$1" ;;
  esac
  shift
done

case "$CHANNEL" in stable|main) ;; *) err "Канал должен быть stable или main"; exit 2 ;; esac
if [ -n "$REQUESTED_VERSION" ] && [ "$CHANNEL" = "main" ]; then
  err "--version и --channel main нельзя использовать вместе"
  exit 2
fi

# Найти KSP.
if [ -z "$KSP_PATH" ]; then
  for candidate in \
    "$HOME/.local/share/Steam/steamapps/common/Kerbal Space Program" \
    "$HOME/.steam/steam/steamapps/common/Kerbal Space Program" \
    "$HOME/Library/Application Support/Steam/steamapps/common/Kerbal Space Program" \
    /run/media/deck/*/steamapps/common/"Kerbal Space Program"; do
    [ -d "$candidate/GameData" ] && KSP_PATH="$candidate" && break
  done
fi
if [ -z "$KSP_PATH" ] || [ ! -d "$KSP_PATH/GameData" ]; then
  err "Не нашёл установку KSP. Укажи путь первым аргументом:"
  err "  install-ru.sh \"/путь/к/Kerbal Space Program\""
  exit 1
fi
say "Установка KSP: $KSP_PATH"

CURRENT_VERSION="не установлена"
[ -f "$KSP_PATH/.kerbalru-version" ] && CURRENT_VERSION="$(head -n1 "$KSP_PATH/.kerbalru-version" | tr -d '\r\n')"

# Выбрать источник и версию.
if [ -n "$REQUESTED_VERSION" ]; then
  REMOTE_VERSION="${REQUESTED_VERSION#v}"
  if ! [[ "$REMOTE_VERSION" =~ ^[0-9]{2}\.[1-9][0-9]*$ ]]; then
    err "Версия должна выглядеть как v26.1"
    exit 2
  fi
  ARCHIVE_URL="https://github.com/$REPO/archive/refs/tags/v$REMOTE_VERSION.zip"
elif [ "$CHANNEL" = "main" ]; then
  MAIN_JSON="$(curl -fsSL "https://api.github.com/repos/$REPO/commits/main")"
  MAIN_SHA="$(printf '%s' "$MAIN_JSON" | sed -n 's/^[[:space:]]*"sha": "\([^"]*\)",*$/\1/p' | head -n1)"
  [ -n "$MAIN_SHA" ] || { err "Не удалось определить commit ветки main"; exit 1; }
  REMOTE_VERSION="main-$(printf '%.7s' "$MAIN_SHA")"
  ARCHIVE_URL="https://github.com/$REPO/archive/refs/heads/main.zip"
else
  if RELEASE_JSON="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null)"; then
    RELEASE_TAG="$(printf '%s' "$RELEASE_JSON" | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  else
    RELEASE_TAG=""
  fi
  if [ -n "$RELEASE_TAG" ]; then
    REMOTE_VERSION="${RELEASE_TAG#v}"
    ARCHIVE_URL="https://github.com/$REPO/archive/refs/tags/$RELEASE_TAG.zip"
  else
    say "Стабильных релизов пока нет — использую текущую main."
    MAIN_JSON="$(curl -fsSL "https://api.github.com/repos/$REPO/commits/main")"
    MAIN_SHA="$(printf '%s' "$MAIN_JSON" | sed -n 's/^[[:space:]]*"sha": "\([^"]*\)",*$/\1/p' | head -n1)"
    [ -n "$MAIN_SHA" ] || { err "Не удалось определить commit ветки main"; exit 1; }
    REMOTE_VERSION="main-$(printf '%.7s' "$MAIN_SHA")"
    ARCHIVE_URL="https://github.com/$REPO/archive/refs/heads/main.zip"
  fi
fi

say "Установлено: $CURRENT_VERSION"
say "Доступно: $REMOTE_VERSION ($CHANNEL)"
if [ "$CHECK_ONLY" = true ]; then
  [ "$CURRENT_VERSION" = "$REMOTE_VERSION" ] && ok "Установлена актуальная версия." || say "Доступно обновление. Запусти установщик без --check."
  exit 0
fi
if [ "$CURRENT_VERSION" = "$REMOTE_VERSION" ] && [ "$FORCE" = false ]; then
  ok "Уже установлена актуальная версия. Для переустановки добавь --force."
  exit 0
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
say "Скачиваю ${REMOTE_VERSION}…"
curl -fsSL -o "$WORK_DIR/kerbalru.zip" "$ARCHIVE_URL"
say "Распаковываю…"
if command -v unzip >/dev/null 2>&1; then
  unzip -q "$WORK_DIR/kerbalru.zip" -d "$WORK_DIR/archive"
else
  python3 -c "import zipfile,sys;zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$WORK_DIR/kerbalru.zip" "$WORK_DIR/archive"
fi
SOURCE_DATA="$(find "$WORK_DIR/archive" -maxdepth 3 -type d -name GameData | head -n1)"
[ -d "$SOURCE_DATA" ] || { err "В архиве не найдена папка GameData"; exit 1; }

# Построить manifest только из файлов kerbal.ru.
NEW_MANIFEST="$WORK_DIR/new-manifest"
find "$SOURCE_DATA" -type f | while IFS= read -r source_file; do
  relative="${source_file#"$SOURCE_DATA"/}"
  printf 'GameData/%s\n' "$relative"
done | LC_ALL=C sort > "$NEW_MANIFEST"
[ -s "$NEW_MANIFEST" ] || { err "Архив не содержит файлов локализации"; exit 1; }

OLD_MANIFEST="$KSP_PATH/.kerbalru-files"
ALL_MANAGED="$WORK_DIR/all-managed"
{ [ -f "$OLD_MANIFEST" ] && cat "$OLD_MANIFEST" || true; cat "$NEW_MANIFEST"; } | LC_ALL=C sort -u > "$ALL_MANAGED"

# Сохранить всё, что будет заменено или удалено.
BACKUP_DIR="$KSP_PATH/kerbal.ru-backups/${CURRENT_VERSION//\//-}-$(date +%Y%m%d-%H%M%S)"
BACKUP_CREATED=false
while IFS= read -r relative; do
  case "$relative" in GameData/*) ;; *) continue ;; esac
  case "$relative" in *..*) err "Небезопасный путь в manifest: $relative"; exit 1 ;; esac
  target="$KSP_PATH/$relative"
  if [ -f "$target" ]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$relative")"
    cp -p "$target" "$BACKUP_DIR/$relative"
    BACKUP_CREATED=true
  fi
done < "$ALL_MANAGED"

# Удалить только старые managed-файлы, которых больше нет в новом релизе.
if [ -f "$OLD_MANIFEST" ]; then
  while IFS= read -r relative; do
    case "$relative" in GameData/*) ;; *) continue ;; esac
    case "$relative" in *..*) err "Небезопасный путь в старом manifest: $relative"; exit 1 ;; esac
    if ! grep -Fqx "$relative" "$NEW_MANIFEST"; then
      rm -f "$KSP_PATH/$relative"
    fi
  done < "$OLD_MANIFEST"
fi

say "Копирую файлы локализации…"
cp -R "$SOURCE_DATA/." "$KSP_PATH/GameData/"
cp "$NEW_MANIFEST" "$OLD_MANIFEST"
printf '%s\n' "$REMOTE_VERSION" > "$KSP_PATH/.kerbalru-version"

# Включить русский язык, сохранив первый исходный settings.cfg.
SETTINGS="$KSP_PATH/settings.cfg"
if [ -f "$SETTINGS" ]; then
  [ -f "$SETTINGS.bak-kerbalru" ] || cp -p "$SETTINGS" "$SETTINGS.bak-kerbalru"
  if grep -q '^LANGUAGE' "$SETTINGS"; then
    SETTINGS_TMP="$(mktemp)"
    sed 's/^LANGUAGE = .*/LANGUAGE = ru/' "$SETTINGS" > "$SETTINGS_TMP"
    mv "$SETTINGS_TMP" "$SETTINGS"
  else
    printf '\nLANGUAGE = ru\n' >> "$SETTINGS"
  fi
else
  say "settings.cfg появится после первого запуска; затем выбери Русский в настройках."
fi

[ "$BACKUP_CREATED" = true ] && say "Резервная копия: $BACKUP_DIR"
ok "kerbal.ru $REMOTE_VERSION установлен. Запускай игру."
