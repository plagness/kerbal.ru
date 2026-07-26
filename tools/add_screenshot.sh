#!/usr/bin/env bash
# kerbal.ru — добавить скриншот в галерею сборки.
#
#   tools/add_screenshot.sh <исходник> <сборка> <slug>
#   tools/add_screenshot.sh ~/Downloads/tg_image_1.png operator 02-set-pokrytiya
#
# Ужимает до 2200 px по длинной стороне и JPEG q80 — это стабильно даёт
# 300–500 КБ на кадр KSP: интерфейс остаётся читаемым, страница не толстеет.
# Дальше руками добавь запись в builds/<сборка>/screens/screens.json
# и прогони tools/gen_gallery.py.
set -euo pipefail

SRC="${1:-}"; BUILD="${2:-}"; SLUG="${3:-}"
[ -n "$SRC" ] && [ -n "$BUILD" ] && [ -n "$SLUG" ] || {
  echo "использование: $0 <исходник> <сборка> <slug>" >&2; exit 2; }
[ -f "$SRC" ] || { echo "нет файла: $SRC" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/builds/$BUILD/screens"
[ -d "$ROOT/builds/$BUILD" ] || { echo "нет сборки: $BUILD" >&2; exit 1; }
mkdir -p "$DIR"
OUT="$DIR/$SLUG.jpg"

sips -Z 2200 -s format jpeg -s formatOptions 80 "$SRC" --out "$OUT" >/dev/null

KB=$(( $(stat -f%z "$OUT") / 1024 ))
DIM=$(sips -g pixelWidth -g pixelHeight "$OUT" | awk '/pixel/{printf "%s ", $2}')
printf '%s — %s КБ, %s\n' "${OUT#$ROOT/}" "$KB" "$DIM"
[ "$KB" -gt 600 ] && echo "предупреждение: больше 600 КБ, снизь качество" >&2
exit 0
