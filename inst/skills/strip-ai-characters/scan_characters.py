#!/usr/bin/env python3
"""
Find characters that mark text as machine-generated, and replace them with
standard ASCII equivalents.

Dry run by default. Nothing is written without --write.

    python3 scan_characters.py                 # report on the current directory
    python3 scan_characters.py --write         # apply the safe replacements
    python3 scan_characters.py PATH [PATH...]  # limit to given paths
    python3 scan_characters.py --show          # print every offending line
    python3 scan_characters.py --skip DIR      # skip a directory by name, repeatable

Two tiers, and the split is the whole point of this script.

  REPLACE  characters with no legitimate use in this project's source. Smart
           quotes, ellipsis, and every invisible character. Replacing these is
           safe because the ASCII form is what the author would have typed and
           what Quarto expects.

  REPORT   characters that are sometimes correct and sometimes a tell. Em
           dashes, en dashes, and the Unicode minus sign. These are never
           touched automatically. House rules commonly grandfather an existing
           em dash in the author's own prose, an en dash in a number range is
           correct, and a Unicode minus is correct in rendered math.

Everything else non-ASCII is left alone and not reported: Greek letters,
currency symbols, mathematical operators, superscripts and subscripts, box
drawing characters used for folder trees, and accented letters in author names.
"""

import argparse
import os
import sys
import unicodedata
from collections import Counter, defaultdict

# --------------------------------------------------------------------------
# Tier 1: replace. No legitimate use in source.
# --------------------------------------------------------------------------
REPLACE = {
    # Quotation marks. Quarto turns straight quotes into typographic ones at
    # render time, so the source should carry the straight form.
    "‘": "'", "’": "'", "‚": "'", "‛": "'",
    "“": '"', "”": '"', "„": '"', "‟": '"',
    "′": "'", "″": '"',
    # Ellipsis.
    "…": "...",
    # Spaces that are not the space character.
    " ": " ", " ": " ", " ": " ", " ": " ",
    " ": " ", " ": " ", " ": " ", " ": " ",
    " ": " ", " ": " ", " ": " ", " ": " ",
    " ": " ", " ": " ", "　": " ",
    # Invisible characters. These are the strongest single tell, because a
    # human typing into an editor does not produce them.
    "­": "", "؜": "", "᠎": "",
    "​": "", "‌": "", "‍": "", "‎": "", "‏": "",
    "⁠": "", "⁡": "", "⁢": "", "⁣": "", "⁤": "",
    "﻿": "",
}

# --------------------------------------------------------------------------
# Tier 2: report only. Context decides whether these are wrong.
# --------------------------------------------------------------------------
# The three keys are built with chr() on purpose: this file is shipped text,
# and a literal em dash in it would trip the very check it exists to serve.
EM_DASH = chr(0x2014)
EN_DASH = chr(0x2013)
MINUS_SIGN = chr(0x2212)

REPORT = {
    EM_DASH: ("EM DASH", "house rules often forbid new ones and grandfather old ones; rebuilding a sentence is a judgement no script can make"),
    EN_DASH: ("EN DASH", "correct in a number range, a tell anywhere else"),
    MINUS_SIGN: ("MINUS SIGN", "correct in rendered math, wrong in prose and code"),
}

TEXT_EXTS = {".qmd", ".md", ".bib", ".yml", ".yaml", ".R", ".r",
             ".txt", ".css", ".json", ".Rmd", ".py", ".sh"}

# Generated, vendored, or machinery. Never edited.
#
#   docs, _book, build, site_libs, .quarto   generated; fix the source instead
#   .git, .Rproj.user, node_modules, renv    machinery
#
# A project's own untouchable directories are named with --skip, not added
# here. Two worth knowing about, because they come up repeatedly:
#
#   --skip chapter_notes   recorded review transcripts, a record of what
#                          someone actually said, so editing them would
#                          falsify the source later revisions were built from
#   --skip bak             superseded drafts
SKIP_DIRS = {".git", ".quarto", "site_libs", ".Rproj.user", "node_modules",
             "docs", "_book", "build", ".superpowers", "renv"}


# This script's own directory. Skipped, because the lookup tables below
# contain one of every character the script hunts for, so scanning itself
# reports a false hit on all of them.
SELF_DIR = os.path.dirname(os.path.realpath(__file__))


def walk(paths, skip=()):
    skipped = SKIP_DIRS | set(skip)
    for p in paths:
        if os.path.isfile(p):
            if not os.path.realpath(p).startswith(SELF_DIR + os.sep):
                yield p
            continue
        for dirpath, dirnames, filenames in os.walk(p):
            dirnames[:] = [d for d in dirnames
                           if d not in skipped and not d.endswith("_files")]
            if os.path.realpath(dirpath).startswith(SELF_DIR):
                continue
            for f in filenames:
                if os.path.splitext(f)[1] in TEXT_EXTS:
                    yield os.path.join(dirpath, f)


def describe(ch):
    try:
        return unicodedata.name(ch)
    except ValueError:
        return "<unnamed>"


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("paths", nargs="*", default=None)
    ap.add_argument("--write", action="store_true",
                    help="apply the tier 1 replacements")
    ap.add_argument("--show", action="store_true",
                    help="print each offending line")
    ap.add_argument("--skip", action="append", default=[], metavar="DIR",
                    help="directory name to skip, repeatable "
                         "(for example --skip chapter_notes --skip bak)")
    args = ap.parse_args()

    # Nothing outside what you name is ever read, and naming nothing means the
    # current directory. There is no wider default and no declared workspace.
    paths = args.paths or ["."]

    replaced = Counter()
    reported = Counter()
    report_files = defaultdict(set)
    changed_files = []
    scanned = 0

    for path in walk(paths, args.skip):
        try:
            original = open(path, encoding="utf-8").read()
        except (UnicodeDecodeError, OSError):
            continue
        scanned += 1
        text = original
        rel = os.path.relpath(path)

        for ch, sub in REPLACE.items():
            n = text.count(ch)
            if n:
                replaced[ch] += n
                report_files[ch].add(rel)
                text = text.replace(ch, sub)

        for ch, (name, why) in REPORT.items():
            n = original.count(ch)
            if n:
                reported[ch] += n
                report_files[ch].add(rel)
                if args.show:
                    for i, line in enumerate(original.split("\n"), 1):
                        if ch in line:
                            print(f"  {rel}:{i}: {line.strip()[:110]}")

        if text != original:
            changed_files.append(rel)
            if args.write:
                with open(path, "w", encoding="utf-8") as fh:
                    fh.write(text)

    verb = "REPLACED" if args.write else "WOULD REPLACE"
    print(f"Scanned {scanned} text files.\n")

    if replaced:
        print(f"{verb}:")
        for ch, n in replaced.most_common():
            files = sorted(report_files[ch])
            shown = ", ".join(files[:3]) + (f" +{len(files)-3} more" if len(files) > 3 else "")
            print(f"  U+{ord(ch):04X}  {describe(ch):<34} {n:>5}  in {len(files)} file(s): {shown}")
        print()
    else:
        print("No replaceable characters found. Source is clean.\n")

    if reported:
        print("REPORT ONLY, never changed automatically:")
        for ch, n in reported.most_common():
            name, why = REPORT[ch]
            files = sorted(report_files[ch])
            print(f"  U+{ord(ch):04X}  {name:<12} {n:>5}  in {len(files)} file(s)")
            print(f"          {why}")
            for f in files[:6]:
                print(f"          {f}")
            if len(files) > 6:
                print(f"          +{len(files)-6} more")
        print()

    if changed_files and not args.write:
        print(f"{len(changed_files)} file(s) would change. Re-run with --write to apply.")
        for f in changed_files[:20]:
            print(f"  {f}")
        if len(changed_files) > 20:
            print(f"  +{len(changed_files)-20} more")
    elif changed_files:
        print(f"Wrote {len(changed_files)} file(s).")
        print("Nothing is committed. Review with `git diff` before committing.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
