#!/usr/bin/env python3
"""Comprehensive one-shot audit: for each of our 20 translated mods, how many of
its parts actually resolve to Russian text in the FINAL ModuleManager.ConfigCache
(the authoritative, already-patched config the game reads), across title /
description / manufacturer. Uses only artifacts already on disk from a prior
launch -- does not launch the game.

Usage: python3 audit_ru_coverage.py "/path/to/Kerbal Space Program"
(defaults to the common Steam paths for Linux/macOS/Steam Deck if omitted)
"""
import re, os, sys

_CANDIDATES = [
    os.path.expanduser('~/.local/share/Steam/steamapps/common/Kerbal Space Program'),
    os.path.expanduser('~/.steam/steam/steamapps/common/Kerbal Space Program'),
    os.path.expanduser('~/Library/Application Support/Steam/steamapps/common/Kerbal Space Program'),
]
if len(sys.argv) > 1:
    KSP = sys.argv[1]
else:
    KSP = next((c for c in _CANDIDATES if os.path.isdir(os.path.join(c, 'GameData'))), _CANDIDATES[0])
GD = os.path.join(KSP, 'GameData')
CACHE = os.path.join(GD, 'ModuleManager.ConfigCache')

OURS_FULL = ["AJE", "BackgroundThrust", "ContractConfigurator", "EditorExtensionsRedux",
             "KerbalChangelog", "KerbalEngineer", "ROCapsules", "RealismOverhaul", "SXT",
             "SpaceTuxLibrary", "Trajectories", "VenStockRevamp"]
OURS_PATCH = ["ModularLaunchPads", "ProceduralFairings", "ProceduralParts", "ROEngines",
              "ROHeatshields", "ROSolar", "ROTanks", "RealChute"]
OURS = OURS_FULL + OURS_PATCH

CYR = re.compile(r'[а-яА-ЯёЁ]')
def has_cyr(s):
    return bool(s) and bool(CYR.search(s))

PART_HEADER = re.compile(r'^[ \t]*([+@!%])?PART(?:\[([^\]]+)\])?(?=[\s{]|$)', re.MULTILINE)
FIELD = re.compile(r'^[ \t]*([A-Za-z]+)\s*=\s*(.*?)\s*$')

def owned_part_names(mod_dir):
    """Return the set of real part `name` values this mod's source declares/edits."""
    names = set()
    for root, dirs, files in os.walk(mod_dir):
        if 'Localization' in root.split(os.sep):
            continue
        for fn in files:
            if not fn.lower().endswith('.cfg'):
                continue
            path = os.path.join(root, fn)
            try:
                with open(path, encoding='utf-8', errors='replace') as f:
                    text = f.read()
            except OSError:
                continue
            for m in PART_HEADER.finditer(text):
                prefix, bracket = m.group(1), m.group(2)
                if prefix == '@' and bracket:
                    # pure edit of an existing part -- bracket IS the real name
                    names.add(bracket)
                else:
                    # fresh declaration or +PART[base]:FIRST clone -- the real
                    # name is the block's OWN `name = X` field, not the bracket
                    snippet = text[m.end():m.end() + 3000]
                    nm = re.search(r'(?<![A-Za-z])name\s*=\s*([^\s{}]+)', snippet)
                    if nm:
                        names.add(nm.group(1).strip())
                    elif bracket:
                        names.add(bracket)
    return names

def parse_cache(path):
    """Parse ModuleManager.ConfigCache into name -> {title, description, manufacturer}."""
    parts = {}
    with open(path, encoding='utf-8', errors='replace') as f:
        lines = f.readlines()
    n = len(lines)
    i = 0
    while i < n:
        if lines[i].strip() == 'PART':
            j = i + 1
            while j < n and lines[j].strip() != '{':
                if lines[j].strip():
                    break
                j += 1
            if j >= n or lines[j].strip() != '{':
                i += 1
                continue
            depth = 1
            j += 1
            name = title = desc = manu = None
            while j < n and depth > 0:
                l = lines[j].strip()
                if l == '{':
                    depth += 1
                elif l == '}':
                    depth -= 1
                    if depth == 0:
                        break
                elif depth == 1:
                    fm = FIELD.match(lines[j])
                    if fm:
                        key, val = fm.group(1), fm.group(2)
                        if key == 'name' and name is None:
                            name = val
                        elif key == 'title' and title is None:
                            title = val
                        elif key == 'description' and desc is None:
                            desc = val
                        elif key == 'manufacturer' and manu is None:
                            manu = val
                j += 1
            if name:
                parts[name] = {'title': title, 'description': desc, 'manufacturer': manu}
            i = j
        else:
            i += 1
    return parts

def main():
    print(f'Разбираю кэш: {CACHE}', file=sys.stderr)
    cache_parts = parse_cache(CACHE)
    print(f'Партов в кэше всего: {len(cache_parts)}', file=sys.stderr)

    rows = []
    for mod in OURS:
        mod_dir = os.path.join(GD, mod)
        if not os.path.isdir(mod_dir):
            rows.append([mod, 0, 0, 0, 0, 0, 'нет папки'])
            continue
        owned = owned_part_names(mod_dir)
        total = len(owned)
        title_ru = desc_ru = manu_ru = missing = 0
        broken_examples = []
        for name in owned:
            entry = cache_parts.get(name)
            if entry is None:
                missing += 1
                continue
            t, d, m = entry['title'], entry['description'], entry['manufacturer']
            if has_cyr(t):
                title_ru += 1
            elif t and len(broken_examples) < 3:
                broken_examples.append(f'{name}: title="{t}"')
            if has_cyr(d):
                desc_ru += 1
            if has_cyr(m):
                manu_ru += 1
        rows.append([mod, total, title_ru, desc_ru, manu_ru, missing, '; '.join(broken_examples)])

    hdr = ['мод', 'парт', 'title-ru', 'desc-ru', 'manuf-ru', 'нет-в-кэше', 'примеры НЕ-ru title']
    widths = [22, 6, 9, 8, 9, 10, 60]
    print(''.join(h.ljust(w) for h, w in zip(hdr, widths)))
    totals = [0, 0, 0, 0, 0]
    for mod, total, tr, dr, mr, miss, ex in rows:
        vals = [mod, str(total), str(tr), str(dr), str(mr), str(miss), ex]
        print(''.join(v.ljust(w) for v, w in zip(vals, widths)))
        totals[0] += total; totals[1] += tr; totals[2] += dr; totals[3] += mr; totals[4] += miss
    print(''.join(v.ljust(w) for v, w in zip(
        ['ИТОГО', str(totals[0]), str(totals[1]), str(totals[2]), str(totals[3]), str(totals[4]), ''],
        widths)))

    if totals[0]:
        print(f'\nОбщий процент партов с русским title: {100*totals[1]/totals[0]:.1f}%')
        print(f'Общий процент партов с русским description: {100*totals[2]/totals[0]:.1f}%')
        print(f'Общий процент партов с русским manufacturer: {100*totals[3]/totals[0]:.1f}%')

if __name__ == '__main__':
    main()
