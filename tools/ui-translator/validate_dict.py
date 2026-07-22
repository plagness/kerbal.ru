#!/usr/bin/env python3
"""Validate KerbalRuUiTranslations/*.txt files: format, duplicates, tab-separation, encoding."""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TDIR = ROOT / "GameData" / "kerbalru-ui-translator" / "KerbalRuUiTranslations"

# Same English key genuinely means something different in these mods' UIs (confirmed by manual
# review, not an accidental collision): "Bottom" is a reorder-to-end button in MechJeb2's Custom
# Info Window editor, but a part-geometry direction in ProceduralParts. A flat global dictionary
# can't disambiguate by caller, so one of the two wins at runtime (whichever file loads last) -
# accepted trade-off, see docs/UI-TRANSLATION.md.
KNOWN_CROSS_MOD_AMBIGUITIES = {"Bottom"}

def main():
    errors = []
    warnings = []
    total_entries = 0
    all_keys = {}
    for f in sorted(TDIR.glob("*.txt")):
        seen = set()
        count = 0
        try:
            text = f.read_text(encoding="utf-8")
        except UnicodeDecodeError as e:
            errors.append(f"{f.name}: not valid UTF-8: {e}")
            continue
        for i, raw in enumerate(text.splitlines(), 1):
            line = raw.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            if "\t" not in line:
                errors.append(f"{f.name}:{i}: no TAB separator: {line[:60]!r}")
                continue
            en, _, ru = line.partition("\t")
            if not en:
                errors.append(f"{f.name}:{i}: empty English key")
                continue
            if not ru:
                errors.append(f"{f.name}:{i}: empty Russian value for {en!r}")
                continue
            if en in seen:
                errors.append(f"{f.name}:{i}: duplicate key within file: {en!r}")
                continue
            seen.add(en)
            count += 1
            if en in all_keys and all_keys[en][1] != ru:
                msg = (
                    f"{f.name}:{i}: key {en!r} also in {all_keys[en][0]} with DIFFERENT translation "
                    f"({all_keys[en][1]!r} vs {ru!r}) -- last-loaded file wins at runtime, confirm intentional"
                )
                if en in KNOWN_CROSS_MOD_AMBIGUITIES:
                    warnings.append(msg)
                else:
                    errors.append(msg)
            all_keys[en] = (f.name, ru)
        total_entries += count
        print(f"{f.name}: {count} entries")

    print(f"\nTotal files: {len(list(TDIR.glob('*.txt')))}, total entries: {total_entries}, unique keys: {len(all_keys)}")
    if warnings:
        print(f"\n{len(warnings)} known accepted ambiguit{'y' if len(warnings) == 1 else 'ies'} (not blocking):")
        for w in warnings:
            print(" -", w)
    if errors:
        print(f"\n{len(errors)} issue(s):")
        for e in errors:
            print(" -", e)
        return 1
    print("\nOK: no format errors.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
