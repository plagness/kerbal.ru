#!/usr/bin/env bash
# kerbal.ru — установщик "всё в одном" для Linux / macOS / Steam Deck.
# Два пути: полностью автоматическая установка сборки RP-1-ExpressInstall через CKAN
# + русификатор, либо только русификатор поверх уже поставленных модов.
#
# Мы не храним и не распространяем чужие моды или сам CKAN — только скачиваем
# официальные релизы KSP-CKAN/CKAN и вызываем их headless-режимом.
set -euo pipefail

CKAN_REPO="KSP-CKAN/CKAN"
# RP-1-ExpressInstall в headless-режиме НЕ доустанавливает сам RP-1 (OR-зависимость
# "RP-1 OR RONoCareer" не резолвится без интерактивного выбора) — без явного RP-1
# карьеры не будет. Ставим все три пакета проверенной командой (см. docs/FOR-AGENTS.md).
CKAN_PACKAGES=(RP-1-ExpressInstall RP-1-ExpressInstall-Graphics-Low RP-1)
CKAN_LABEL="RP-1-ExpressInstall"
RU_INSTALLER_URL="https://kerbal.ru/install-ru.sh"

KSP_PATH=""
MODE=""          # full | ru-only | "" (решить по контексту)
CHECK_ONLY=false
PASSTHROUGH=()    # флаги для install-ru.sh: --check/--version/--channel/--force

say(){ printf '\033[1;36m» %s\033[0m\n' "$*"; }
ok(){ printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
err(){ printf '\033[1;31m× %s\033[0m\n' "$*" >&2; }
usage(){
  cat <<'EOF'
kerbal.ru — установка сборки RO/RSS/RP-1 и русификатора «всё в одном»

Использование:
  install.sh [путь к KSP] [параметры]

Два пути:
  --full       поставить сборку RP-1-ExpressInstall через CKAN (если её ещё нет) и сразу русификатор
  --ru-only    только русификатор — если сборка уже стоит (то же самое, что install-ru.sh)

Без --full/--ru-only:
  - если сборка RO/RSS/RP-1 уже найдена в GameData — ставится только русификатор;
  - иначе, если есть терминал — спросит, что делать;
  - без терминала (например в CI) — покажет обе команды и ничего не сделает.

Параметры русификатора (передаются в install-ru.sh):
  --check                  только проверить, ничего не ставить
  --version v26.1          установить или откатить конкретный релиз
  --channel stable|main    канал русификатора (по умолчанию stable)
  --force                  переустановить ту же версию
  --help                   показать эту справку
EOF
}

FULL_FLAG=false
RUONLY_FLAG=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --full) MODE="full"; FULL_FLAG=true ;;
    --ru-only) MODE="ru-only"; RUONLY_FLAG=true ;;
    --check) CHECK_ONLY=true; PASSTHROUGH+=("--check") ;;
    --force) PASSTHROUGH+=("--force") ;;
    --version)
      [ "$#" -ge 2 ] || { err "После --version нужна версия"; exit 2; }
      PASSTHROUGH+=("--version" "$2"); shift ;;
    --channel)
      [ "$#" -ge 2 ] || { err "После --channel нужен stable или main"; exit 2; }
      PASSTHROUGH+=("--channel" "$2"); shift ;;
    --help|-h) usage; exit 0 ;;
    --*) err "Неизвестный параметр: $1"; usage; exit 2 ;;
    *)
      [ -z "$KSP_PATH" ] || { err "Путь к KSP уже указан"; exit 2; }
      KSP_PATH="$1" ;;
  esac
  shift
done

if [ "$FULL_FLAG" = true ] && [ "$RUONLY_FLAG" = true ]; then
  err "--full и --ru-only нельзя использовать вместе"
  exit 2
fi

# Найти KSP (та же логика, что в install-ru.sh).
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
  err "Не нашёл установку KSP. Сначала поставь лицензионную Kerbal Space Program через Steam,"
  err "потом укажи путь первым аргументом:"
  err "  install.sh \"/путь/к/Kerbal Space Program\" --full"
  exit 1
fi
say "Установка KSP: $KSP_PATH"

MODS_PRESENT=false
if [ -d "$KSP_PATH/GameData/RealismOverhaul" ] && [ -d "$KSP_PATH/GameData/RP-1" ]; then
  MODS_PRESENT=true
fi

# Решить путь, если не задан явно флагом --full/--ru-only.
TTY_OK=false
if ( exec 3</dev/tty ) 2>/dev/null; then
  TTY_OK=true
fi
if [ -z "$MODE" ]; then
  if [ "$MODS_PRESENT" = true ]; then
    MODE="ru-only"
  elif [ "$TTY_OK" = true ]; then
    say "Сборка RO/RSS/RP-1 не найдена в $KSP_PATH/GameData."
    say "[1] Поставить всё автоматически через CKAN (RP-1-ExpressInstall) + русификатор — Enter"
    say "[2] Моды поставлю сам(а) — поставить только русификатор"
    printf '\033[1;36m» Выбор [1/2]: \033[0m' > /dev/tty
    CHOICE=""
    read -r CHOICE < /dev/tty 2>/dev/null || CHOICE=""
    case "$CHOICE" in
      2) MODE="ru-only" ;;
      *) MODE="full" ;;
    esac
  else
    say "Сборка RO/RSS/RP-1 не найдена, а терминала для вопроса нет (неинтерактивный запуск)."
    say "Укажи явно один из двух путей:"
    say "  curl -fsSL https://kerbal.ru/install.sh | bash -s -- --full      # поставить всё автоматически"
    say "  curl -fsSL https://kerbal.ru/install.sh | bash -s -- --ru-only   # только русификатор (моды уже свои)"
    exit 0
  fi
fi

if [ "$MODE" = "full" ]; then
  if [ "$MODS_PRESENT" = true ]; then
    if [ "$CHECK_ONLY" = true ]; then
      say "Сборка RO/RSS/RP-1 уже установлена — шаг CKAN будет пропущен."
    else
      ok "Сборка RO/RSS/RP-1 уже установлена — пропускаю шаг CKAN."
    fi
  elif [ "$CHECK_ONLY" = true ]; then
    say "Сборка RO/RSS/RP-1 не установлена — при обычном запуске будет поставлена через CKAN ($CKAN_LABEL)."
  else
    MONO_PREFIX=()
    case "$(uname -s)" in
      Linux)
        if ! command -v mono >/dev/null 2>&1; then
          err "Для автоматической установки модов через CKAN на Linux нужен mono."
          err "Поставь его (например 'sudo apt install mono-complete', 'sudo dnf install mono-complete')"
          err "или на Steam Deck — через контейнер distrobox, и запусти установщик снова."
          err "Либо поставь сборку вручную через CKAN GUI и используй --ru-only."
          exit 1
        fi
        MONO_PREFIX=(mono) ;;
      Darwin)
        if ! command -v mono >/dev/null 2>&1; then
          err "Для автоматической установки модов через CKAN на macOS нужен mono (brew install mono)."
          err "Поставь его и запусти установщик снова, либо поставь сборку вручную через CKAN GUI"
          err "и используй --ru-only."
          exit 1
        fi
        MONO_PREFIX=(mono) ;;
      *)
        err "Автоматическая установка модов через CKAN поддерживается только на Linux/macOS/Steam Deck."
        exit 1 ;;
    esac

    WORK_DIR="$(mktemp -d)"
    trap 'rm -rf "$WORK_DIR"' EXIT

    say "Ищу свежий релиз CKAN…"
    CKAN_URL="$(curl -fsSL "https://api.github.com/repos/$CKAN_REPO/releases/latest" \
      | sed -n 's/.*"browser_download_url": *"\([^"]*\/ckan\.exe\)".*/\1/p' | head -n1)"
    [ -n "$CKAN_URL" ] || { err "Не удалось найти ckan.exe в последнем релизе $CKAN_REPO"; exit 1; }
    say "Скачиваю CKAN…"
    curl -fsSL -o "$WORK_DIR/ckan.exe" "$CKAN_URL"

    say "Обновляю индекс модов CKAN…"
    "${MONO_PREFIX[@]}" "$WORK_DIR/ckan.exe" update --headless --gamedir "$KSP_PATH"

    say "Ставлю сборку $CKAN_LABEL через CKAN (это надолго — несколько гигабайт)…"
    "${MONO_PREFIX[@]}" "$WORK_DIR/ckan.exe" install --headless --no-recommends --gamedir "$KSP_PATH" "${CKAN_PACKAGES[@]}"
    ok "Сборка RO/RSS/RP-1 установлена через CKAN."
  fi
fi

say "Ставлю русификатор…"
curl -fsSL "$RU_INSTALLER_URL" | bash -s -- "$KSP_PATH" "${PASSTHROUGH[@]}"
