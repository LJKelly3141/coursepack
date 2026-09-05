#!/usr/bin/env python3
"""Measure one chapter of a question bank against the authoring rules. Read-only.

    measure_bank.py <bank-dir> <chapter-number> [--sample N] [--seed S]
                    [--modules <modules.yml>]

<bank-dir> holds chapter_NN.json, images/ and figures/. With --modules the
section titles in the file are compared against the item titles the course
manifest records for this chapter, which is the check that catches a title
that reads right and does not match character for character.

Prints one table per chapter and, with --sample, N randomly chosen questions
in full (stem, options, key, explanation, figure path) for the instructor's
review.
"""
import collections
import json
import random
import re
import sys
from pathlib import Path

VALID_DIFF = {"recall", "application", "analysis"}


def canonical_sections(modules_yml, ch):
    """Section titles for this chapter as the course manifest records them."""
    text = Path(modules_yml).read_text()
    pat = re.compile(r'title: "(%d\.\d+ [^"]+)"' % ch)
    seen = []
    for m in pat.finditer(text):
        if m.group(1) not in seen:
            seen.append(m.group(1))
    return seen


def opt(argv, name, cast, default):
    return cast(argv[argv.index(name) + 1]) if name in argv else default


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    new = Path(sys.argv[1])
    ch = int(sys.argv[2])
    sample = opt(sys.argv, "--sample", int, 0)
    seed = opt(sys.argv, "--seed", int, 2026)
    modules_yml = opt(sys.argv, "--modules", str, None)
    path = new / f"chapter_{ch:02d}.json"
    if not path.exists():
        sys.exit(f"MISSING {path}")
    d = json.loads(path.read_text())
    canon = canonical_sections(modules_yml, ch) if modules_yml else None
    have = [s["section"] for s in d.get("sections", [])]
    problems = []
    keys = collections.Counter()
    diffs = collections.Counter()
    stems = {}
    ids = []
    figs = set()
    all_q = []
    key_longest = []
    print(f"# {path}  title={d.get('title')!r}")
    if canon is None:
        print(f"sections in file: {len(have)}   (no --modules given, titles not "
              f"cross-checked)")
    else:
        print(f"sections in the manifest: {len(canon)}   in file: {len(have)}")
        for t in canon:
            if t not in have:
                problems.append(f"section missing from file: {t}")
        for t in have:
            if t not in canon:
                problems.append(f"section not in the manifest: {t}")
    print()
    print(f"{'section':<62} {'n':>3} {'rec':>4} {'app':>4} {'ana':>4} {'fig':>4}")
    for s in d.get("sections", []):
        qs = s.get("questions", [])
        dc = collections.Counter(q.get("difficulty") for q in qs)
        nf = sum(1 for q in qs if q.get("image"))
        print(f"{s['section'][:62]:<62} {len(qs):>3} {dc.get('recall',0):>4} {dc.get('application',0):>4} {dc.get('analysis',0):>4} {nf:>4}")
        for q in qs:
            all_q.append((s["section"], q))
            ids.append(q.get("id"))
            keys[q.get("answer")] += 1
            diffs[q.get("difficulty")] += 1
            qid = q.get("id")
            opts = q.get("options") or {}
            if q.get("type") != "multiple_choice":
                problems.append(f"q{qid}: type {q.get('type')!r}")
            if q.get("difficulty") not in VALID_DIFF:
                problems.append(f"q{qid}: difficulty {q.get('difficulty')!r}")
            if sorted(opts.keys()) != ["A", "B", "C", "D"]:
                problems.append(f"q{qid}: option letters {sorted(opts.keys())}")
            if len(set(str(v).strip().lower() for v in opts.values())) != len(opts):
                problems.append(f"q{qid}: duplicate option text")
            if q.get("answer") not in opts:
                problems.append(f"q{qid}: key {q.get('answer')!r} not among options")
            for bad in ("all of the above", "none of the above", "both a and b"):
                if any(bad in str(v).lower() for v in opts.values()):
                    problems.append(f"q{qid}: option contains '{bad}'")
            if not str(q.get("explanation", "")).strip():
                problems.append(f"q{qid}: empty explanation")
            if not str(q.get("objective", "")).strip():
                problems.append(f"q{qid}: empty objective")
            stem = re.sub(r"\s+", " ", str(q.get("question", ""))).strip().lower()
            if not stem:
                problems.append(f"q{qid}: empty stem")
            elif stem in stems:
                problems.append(f"q{qid}: duplicate stem of q{stems[stem]}")
            else:
                stems[stem] = qid
            # longest-answer cue: the key must not stand out by length
            if opts and q.get("answer") in opts:
                L = {k: len(str(v)) for k, v in opts.items()}
                others = [v for k, v in L.items() if k != q["answer"]]
                if others and L[q["answer"]] > max(others):
                    key_longest.append(qid)
                if others and L[q["answer"]] > max(others) * 1.15:
                    problems.append(f"q{qid}: keyed option longest by >15% ({L[q['answer']]} vs {max(others)} chars)")
            if q.get("image"):
                png = new / "images" / q["image"]
                if not png.exists():
                    problems.append(f"q{qid}: image {q['image']} missing")
                figs.add(q["image"])
                f = q.get("figure") or {}
                if not f.get("alt", "").strip():
                    problems.append(f"q{qid}: figure without alt text")
                if f.get("script") and not (new / "figures" / f["script"]).exists():
                    problems.append(f"q{qid}: figure script {f['script']} missing")
    n = len(ids)
    print()
    print(f"total questions {n}; unique ids {len(set(ids))}; figures referenced {len(figs)}")
    print(f"difficulty: {dict(diffs)}")
    print(f"keys: {dict(sorted(keys.items()))}" + ("" if n == 0 else f"  (max share {max(keys.values())/n:.0%})"))
    if n:
        share = len(key_longest) / n
        print(f"key is the single longest option in {len(key_longest)} of {n} ({share:.0%}); chance is 25%")
        if share > 0.35:
            problems.append(f"length cue: key is the single longest option in {share:.0%} of items")
    if len(set(ids)) != n:
        problems.append("duplicate ids")
    print()
    if problems:
        print(f"PROBLEMS ({len(problems)}):")
        for p in problems:
            print("  -", p)
    else:
        print("PROBLEMS: none")

    if sample and all_q:
        random.seed(seed)
        picks = random.sample(all_q, min(sample, len(all_q)))
        print(f"\n# sample of {len(picks)} (seed {seed})")
        for sec, q in picks:
            print(f"\n--- q{q['id']} [{q.get('difficulty')}] {sec}")
            print(q["question"])
            for k in "ABCD":
                mark = "*" if k == q.get("answer") else " "
                print(f"  {mark}{k}. {q['options'].get(k)}")
            if q.get("image"):
                print(f"  figure: {new / 'images' / q['image']}")
                print(f"  alt: {(q.get('figure') or {}).get('alt')}")
            print(f"  why: {q.get('explanation')}")


if __name__ == "__main__":
    main()
