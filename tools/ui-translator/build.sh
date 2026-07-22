#!/bin/bash
# Builds GameData/kerbalru-ui-translator/Plugins/KerbalRuUiTranslator.dll via Mono's mcs.
# Requires KSP installed locally (used only for compile-time reference DLLs, not redistributed).
set -euo pipefail

KSP_ROOT="${1:-/Users/plag/Library/Application Support/Steam/steamapps/common/Kerbal Space Program}"
MANAGED="$KSP_ROOT/KSP.app/Contents/Resources/Data/Managed"
HARMONY="$KSP_ROOT/GameData/000_Harmony/0Harmony.dll"

if [ ! -d "$MANAGED" ]; then
  echo "Managed assemblies not found at: $MANAGED" >&2
  exit 1
fi
if [ ! -f "$HARMONY" ]; then
  echo "0Harmony.dll not found at: $HARMONY" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/../../GameData/kerbalru-ui-translator/Plugins"
mkdir -p "$OUT_DIR"

mcs -target:library \
  -out:"$OUT_DIR/KerbalRuUiTranslator.dll" \
  -r:"$MANAGED/Assembly-CSharp.dll" \
  -r:"$MANAGED/UnityEngine.dll" \
  -r:"$MANAGED/UnityEngine.CoreModule.dll" \
  -r:"$MANAGED/UnityEngine.IMGUIModule.dll" \
  -r:"$MANAGED/UnityEngine.UI.dll" \
  -r:"$HARMONY" \
  "$SCRIPT_DIR/src/KerbalRuUiTranslator.cs"

echo "Built: $OUT_DIR/KerbalRuUiTranslator.dll"
