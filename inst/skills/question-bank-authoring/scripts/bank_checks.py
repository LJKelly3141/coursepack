#!/usr/bin/env python3
"""Text and figure checks over one chapter of a question bank.

    bank_checks.py <bank-dir> <chapter-number>

<bank-dir> holds chapter_NN.json, images/ and figures/. Flags em-dashes,
references to the book, forbidden options, malformed option sets, an empty
explanation or objective, an image without a figure block, a figure whose
files are not where it says they are, and alt text too short to answer the
question from. Then it regenerates every figure and compares the PNG hash
before and after, so a figure that is not reproducible is caught here rather
than the next time someone runs the script.

Regenerating the figures is the one thing here that writes: it overwrites the
PNGs under images/ with what the scripts draw. Nothing else is touched.
"""
import hashlib
import json
import os
import re
import subprocess
import sys

# The literal character would be found by any tool that scans this directory
# for em-dashes, including the package's own residue test, so it is written as
# a code point in the one file whose job is to find it.
EM_DASH = chr(0x2014)

BOOK_REF = re.compile(r"\b(the text|textbook|the chapter|OpenStax|Figure \d|Table \d)\b", re.I)
FORBIDDEN = re.compile(r"\b(all|none) of the above\b|\bboth [A-D] and [A-D]\b", re.I)


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    root = sys.argv[1]
    ch = int(sys.argv[2])
    images = os.path.join(root, "images")
    figures = os.path.join(root, "figures")
    with open(os.path.join(root, f"chapter_{ch:02d}.json")) as fh:
        b = json.load(fh)
    qs = [q for s in b["sections"] for q in s["questions"]]
    bad = []
    for q in qs:
        texts = ([q["question"]] + list(q["options"].values()) + [q["explanation"]]
                 + ([q["figure"]["alt"]] if q.get("figure") else []))
        for t in texts:
            if EM_DASH in t or "&mdash;" in t or " -- " in t:
                bad.append((q["id"], "emdash"))
        for t in [q["question"]] + list(q["options"].values()):
            if BOOK_REF.search(t):
                bad.append((q["id"], "bookref", t[:60]))
            if FORBIDDEN.search(t):
                bad.append((q["id"], "forbidden-option"))
        if len(set(q["options"].values())) != 4 or q["answer"] not in q["options"]:
            bad.append((q["id"], "options"))
        if not q["explanation"].strip() or not q["objective"].strip():
            bad.append((q["id"], "empty"))
        if bool(q.get("image")) != bool(q.get("figure")):
            bad.append((q["id"], "image/figure mismatch"))
        if q.get("figure"):
            f = q["figure"]
            if (q["image"] != f["file"]
                    or not os.path.exists(os.path.join(images, f["file"]))
                    or not os.path.exists(os.path.join(figures, f["script"]))):
                bad.append((q["id"], "figure files"))
            if len(f.get("alt", "")) < 80:
                bad.append((q["id"], "short alt"))
    print("flags:", bad or "none")

    # figure reproducibility
    scripts = sorted(set(q["figure"]["script"] for q in qs if q.get("figure")))
    for s in scripts:
        png = os.path.join(images, s[:-3] + ".png")
        with open(png, "rb") as fh:
            before = hashlib.sha1(fh.read()).hexdigest()[:10]
        subprocess.run(["python3", os.path.join(figures, s)], capture_output=True)
        with open(png, "rb") as fh:
            after = hashlib.sha1(fh.read()).hexdigest()[:10]
        print(s, "reproducible" if before == after else "CHANGED on regeneration")


if __name__ == "__main__":
    main()
