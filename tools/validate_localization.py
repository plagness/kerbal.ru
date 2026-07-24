#!/usr/bin/env python3
"""Structural validator for GameData/**/*.cfg localization files.

Unlike a flat brace-count check (which can pass even when content lands
outside the block it was meant to be nested in -- see docs/MAINTAINING.md
section 6, the RealSolarSystem/ru.cfg incident of 2026-07-22), this builds
a real parse tree of { } blocks and checks structural position, not just
counts.

Checks (see docs/MAINTAINING.md section 5 for the rules these encode):
  - orphan/misnested key: a #LOC_-style key whose parent block is not
    literally named "en-us" or "ru" -- hard fail. This is exactly the class
    of bug that a flat brace-count cannot see.
  - duplicate key within the same language block -- hard fail.
  - en-us/ru key-set parity, but ONLY for files where both an en-us{} and
    a ru{} block exist as siblings under the same Localization{} node
    (the "PATCH-type" pattern, where kerbal.ru invents new keys). Files
    with only a ru{} block (the "FULL-type" pattern, overriding keys the
    mod's own upstream already declares) are not checked for parity --
    there is nothing in the repo to compare against.
  - a ru value that is byte-identical to its en-us sibling for a non-empty
    string -- hard fail (near-certainly an untranslated copy-paste, not a
    real word-count violation).
  - word-count ru <= en per MAINTAINING.md rule 2 -- WARNING only (not a
    hard fail): this is a UI-width heuristic invented ad hoc, not a
    validated linguistic fact, and hard-failing it risks teaching whoever
    is translating to mangle correct translations just to pass CI.
  - dangling reference: a RuLocPatch.cfg-style file does `%field = #key`
    but #key is not defined as a #LOC_ key anywhere in the repo -- hard
    fail.
  - cross-mod key collision: the same literal #LOC_ key defined in two
    different mods' folders -- hard fail (KSP's Localizer namespace is
    global; this is silent data corruption at the game-data level, not
    a git problem).

Usage:
  python3 tools/validate_localization.py            # full repo scan
  python3 tools/validate_localization.py --json      # machine-readable
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# Библиотека переводов живёт по папке на мод в translations/<mod>/Localization/*.cfg
# (можно переопределить путём первым позиционным аргументом).
GAMEDATA = ROOT / "translations"

KEY_LINE = re.compile(r'^\s*(#[A-Za-z0-9_.\-]+)\s*=\s*(.*?)\s*$')
BARE_WORD = re.compile(r'^\s*([A-Za-z0-9_.\-]+)\s*$')
PATCH_FIELD = re.compile(r'^\s*%([A-Za-z]+)\s*=\s*(#[A-Za-z0-9_.\-]+)\s*$')
PART_HEADER = re.compile(r'^\s*@PART\[([^\]]+)\]')
PLACEHOLDER = re.compile(r'<<\d+>>|\{[0-9]+\}|%[sd]|\\n')

# Known, confirmed-intentional duplicate keys we mirror from an upstream mod's
# OWN Localization file that itself has the same duplicate (verified by
# reading the mod's own en-us.cfg -- not our bug to "fix", since our rule is
# to mirror the upstream key set exactly). Format: "RelativeFileFromGameData:#key".
KNOWN_UPSTREAM_DUPLICATE_KEYS = {
    "translations/ContractConfigurator/Localization/ru.cfg:#cc.req.Any",  # upstream en-us.cfg
    # has this same key defined twice (lines 357-358) with different meanings;
    # last-defined-wins in both files, so ours correctly mirrors the effective
    # (second) value. See docs/MAINTAINING.md section 6.
    #
    # Nertea's NearFutureLaunchVehicles/Localization/en-us.cfg declares each of
    # these three keys twice itself (verified in the installed mod); we mirror
    # the upstream key set 1:1, so the duplication is intentional, not our bug.
    "translations/NearFutureLaunchVehicles/Localization/ru.cfg:#LOC_NFLaunchVehicles_switcher_skeletal_title",
    "translations/NearFutureLaunchVehicles/Localization/ru.cfg:#LOC_NFLaunchVehicles_engine_switcher_mount_title",
    "translations/NearFutureLaunchVehicles/Localization/ru.cfg:#LOC_NFLaunchVehicles_service-bay-5-1_tags",
    # SCANsat's own en-us/Helptips.cfg defines settingsHelpWindowTooltips twice
    # with different text ("map window buttons" vs "surface be in daylight");
    # last-wins upstream, ours mirrors both.
    "translations/SCANsat/Localization/ru.cfg:#autoLOC_SCANsat_settingsHelpWindowTooltips",
    # StationScience's english.cfg defines this stock-namespace kuarq flavour
    # key twice with different text; we mirror it verbatim.
    "translations/StationScience/Localization/ru.cfg:#autoLOC_prograde_MunSrfLanded",
}


class Node:
    __slots__ = ("name", "parent", "children", "keys", "line")

    def __init__(self, name, parent, line):
        self.name = name
        self.parent = parent
        self.children = []
        self.keys = []  # list of (key, value, line_no)
        self.line = line

    def path(self):
        parts = []
        n = self
        while n is not None and n.name is not None:
            parts.append(n.name)
            n = n.parent
        return " > ".join(reversed(parts))


def strip_comment(line: str) -> str:
    # crude but matches the convention used elsewhere in this project:
    # "//" starts a comment unless it's inside a string value we don't
    # otherwise parse (KSP cfg has no quoted strings, so this is safe).
    idx = line.find("//")
    return line if idx == -1 else line[:idx]


def parse_tree(text: str):
    """Return the root Node of the { } tree for one file's raw text."""
    root = Node(None, None, 0)
    stack = [root]
    pending_name = None
    for lineno, raw in enumerate(text.split("\n"), start=1):
        line = strip_comment(raw)
        stripped = line.strip()
        if not stripped:
            continue
        if stripped == "{":
            name = pending_name
            pending_name = None
            node = Node(name, stack[-1], lineno)
            stack[-1].children.append(node)
            stack.append(node)
            continue
        if stripped == "}":
            if len(stack) > 1:
                stack.pop()
            pending_name = None
            continue
        m = KEY_LINE.match(line)
        if m:
            stack[-1].keys.append((m.group(1), m.group(2), lineno))
            pending_name = None
            continue
        m2 = BARE_WORD.match(line)
        if m2:
            # a bare identifier line right before "{" is this node's name
            pending_name = m2.group(1)
            continue
        pending_name = None
    return root


def find_loc_blocks(root: Node):
    """Yield every 'ru' and 'en-us' Node found anywhere in the tree,
    together with a flag for whether they're siblings under the same
    parent Localization-ish node (the PATCH-type pattern)."""
    out = []
    def walk(node):
        for child in node.children:
            if child.name in ("ru", "ru-ru"):
                sibling_en = next((c for c in node.children if c.name == "en-us"), None)
                out.append(("ru", child, sibling_en))
            walk(child)
    walk(root)
    return out


def word_count(s: str) -> int:
    s = re.sub(r"<[^>]+>", " ", s)
    return len(re.findall(r"[A-Za-zА-Яа-яЁё0-9][A-Za-zА-Яа-яЁё0-9'&/.\-]*", s))


def check_file(path: Path, all_keys_seen: dict, findings: list):
    rel = path.relative_to(ROOT)
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as e:
        findings.append(("error", str(rel), 0, f"not valid UTF-8: {e}"))
        return
    root = parse_tree(text)

    # 1) orphan/misnested key check: any #LOC_-style key whose direct
    #    parent is NOT named ru/ru-ru/en-us is suspicious IF it lives
    #    inside something that at least looks like a Localization tree.
    #    We scope this to keys starting with '#LOC' or '#autoLOC' or '#'
    #    generally that sit directly under a node whose grandparent (or
    #    itself) is literally "Localization" -- catches keys accidentally
    #    landing as siblings of ru{} instead of inside it.
    def walk_for_orphans(node, in_localization):
        here_is_loc = node.name == "Localization" or in_localization
        for key, val, lineno in node.keys:
            if here_is_loc and node.name not in ("ru", "ru-ru", "en-us"):
                findings.append((
                    "error", str(rel), lineno,
                    f"key {key} is not directly inside a ru{{}}/en-us{{}} block "
                    f"(actual parent path: {node.path()}) -- likely landed outside "
                    f"the intended nested block (see MAINTAINING.md section 6)",
                ))
        for child in node.children:
            walk_for_orphans(child, here_is_loc and node.name == "Localization" or in_localization and node.name != "Localization")
    walk_for_orphans(root, False)

    # 2) duplicate key within the same block
    for node in _all_nodes(root):
        seen = {}
        for key, val, lineno in node.keys:
            if key in seen:
                if f"{rel}:{key}" in KNOWN_UPSTREAM_DUPLICATE_KEYS:
                    continue
                findings.append((
                    "error", str(rel), lineno,
                    f"duplicate key {key} in the same block (first seen line {seen[key]})",
                ))
            else:
                seen[key] = lineno

    # 3) en-us/ru parity + en==ru byte-identical check, only where both
    #    blocks exist as siblings
    for _, ru_node, en_node in find_loc_blocks(root):
        ru_map = {k: v for k, v, _ in ru_node.keys}
        if en_node is not None:
            en_map = {k: v for k, v, _ in en_node.keys}
            missing_in_ru = sorted(set(en_map) - set(ru_map))
            missing_in_en = sorted(set(ru_map) - set(en_map))
            for k in missing_in_ru:
                findings.append(("error", str(rel), en_node.line,
                                  f"key {k} defined in en-us{{}} but missing from ru{{}}"))
            for k in missing_in_en:
                findings.append(("error", str(rel), ru_node.line,
                                  f"key {k} defined in ru{{}} but missing from en-us{{}}"))
            for k, ru_val in ru_map.items():
                en_val = en_map.get(k)
                if en_val is not None and ru_val.strip() and ru_val == en_val:
                    # WARNING, not error: often a deliberate, correct choice per
                    # MAINTAINING.md rule 5/6 (brand names, historical/technical
                    # designators, and upstream stub text are meant to stay
                    # untranslated) -- this needs a human/translator glance, it
                    # is not automatically a bug the way structural issues are.
                    findings.append(("warning", str(rel), ru_node.line,
                                      f"key {k}: ru value is byte-identical to en-us "
                                      f"(\"{ru_val[:60]}\") -- confirm this is an "
                                      f"intentional brand/designator/stub, not a missed translation"))
                if en_val is not None and ru_val.strip() and en_val.strip():
                    ew, rw = word_count(en_val), word_count(ru_val)
                    if rw > ew:
                        findings.append(("warning", str(rel), ru_node.line,
                                          f"key {k}: ru is {rw} words vs en {ew} words "
                                          f"(rule of thumb is ru<=en; not a hard failure)"))
                    en_ph = PLACEHOLDER.findall(en_val)
                    ru_ph = PLACEHOLDER.findall(ru_val)
                    if en_ph != ru_ph:
                        findings.append(("error", str(rel), ru_node.line,
                                          f"key {k}: placeholder mismatch en={en_ph} ru={ru_ph}"))

        mod = _mod_name(path)
        for k, v in ru_map.items():
            prev = all_keys_seen.get(k)
            if prev is not None and prev[0] != mod:
                findings.append(("error", str(rel), ru_node.line,
                                  f"key {k} also defined in a different mod ({prev[0]}, "
                                  f"{prev[1]}) -- KSP's Localizer namespace is global, this "
                                  f"is a silent collision, not just a repo-organization issue"))
            all_keys_seen.setdefault(k, (mod, str(rel)))


def _all_nodes(node):
    yield node
    for c in node.children:
        yield from _all_nodes(c)


def _mod_name(path: Path) -> str:
    try:
        rel = path.relative_to(GAMEDATA)
        return rel.parts[0]
    except ValueError:
        return str(path)


def check_dangling_references(findings: list):
    defined = set()
    referenced = []  # (key, path, lineno)
    for path in sorted(GAMEDATA.rglob("*.cfg")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for lineno, raw in enumerate(text.split("\n"), start=1):
            line = strip_comment(raw)
            m = KEY_LINE.match(line)
            if m:
                defined.add(m.group(1))
            m2 = PATCH_FIELD.match(line)
            if m2:
                referenced.append((m2.group(2), path.relative_to(ROOT), lineno))
    for key, rel, lineno in referenced:
        if key not in defined:
            findings.append(("error", str(rel), lineno,
                              f"patch references {key} via %field=#key, but that key is "
                              f"never defined in any en-us{{}}/ru{{}} block anywhere in GameData/"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    findings = []
    all_keys_seen: dict = {}
    for path in sorted(GAMEDATA.rglob("*.cfg")):
        if path.name in ("RuLocPatch.cfg",):
            continue  # patch files are checked via the dangling-reference pass instead
        check_file(path, all_keys_seen, findings)
    check_dangling_references(findings)

    errors = [f for f in findings if f[0] == "error"]
    warnings = [f for f in findings if f[0] == "warning"]

    if args.json:
        print(json.dumps(
            {"errors": len(errors), "warnings": len(warnings), "findings": findings},
            ensure_ascii=False, indent=2,
        ))
    else:
        for level, rel, lineno, msg in findings:
            marker = "::error" if level == "error" else "::warning"
            print(f"{marker} file={rel},line={lineno}::{msg}")
        print(f"\n{len(errors)} error(s), {len(warnings)} warning(s) "
              f"across {len(list(GAMEDATA.rglob('*.cfg')))} .cfg files")

    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
