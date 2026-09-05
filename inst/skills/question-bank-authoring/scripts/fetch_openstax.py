#!/usr/bin/env python3
"""Fetch an OpenStax section page and write its full body text to a file.

    python3 fetch_openstax.py <openstax-url> <out.txt>

Extracts the text of the page's main content element (the div with
data-type="page", falling back to <main>), keeps paragraph breaks, and marks
figures, captions, and tables so a reader knows where they were. Prints the
word count. Exits non-zero if the page did not fetch or yielded fewer than
300 words, so a silent failure cannot pass as a read.
"""
import subprocess
import sys
from html.parser import HTMLParser

BLOCK = {"p", "div", "li", "h1", "h2", "h3", "h4", "h5", "h6", "tr", "section",
         "figure", "figcaption", "table", "ul", "ol", "blockquote", "dd", "dt"}
SKIP = {"script", "style", "nav", "noscript", "svg", "button"}


class Grab(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.depth = 0          # depth inside the target element; 0 = outside
        self.stack = []
        self.skip = 0
        self.out = []
        self.found = False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if not self.found:
            if a.get("data-type") == "page" or tag == "main":
                self.found = True
                self.depth = 1
            return
        self.depth += 1
        if tag in SKIP:
            self.skip += 1
        if tag == "figure":
            self.out.append("\n[FIGURE]")
        if tag == "figcaption":
            self.out.append("\n[CAPTION] ")
        if tag == "table":
            self.out.append("\n[TABLE]\n")
        if tag in ("td", "th"):
            self.out.append(" | ")
        if tag == "img" and a.get("alt"):
            self.out.append(f"\n[IMAGE ALT] {a['alt']}\n")

    def handle_endtag(self, tag):
        if not self.found or self.depth == 0:
            return
        if tag in SKIP and self.skip:
            self.skip -= 1
        if tag in BLOCK:
            self.out.append("\n")
        if tag == "table":
            self.out.append("[/TABLE]\n")
        self.depth -= 1
        if self.depth == 0:
            self.found = "done"

    def handle_data(self, data):
        if self.found is True and self.depth > 0 and not self.skip:
            self.out.append(data)


def main():
    url, out = sys.argv[1], sys.argv[2]
    r = subprocess.run(["curl", "-sL", "--max-time", "60", url], capture_output=True)
    if r.returncode != 0 or not r.stdout:
        sys.exit(f"fetch failed: {url}")
    g = Grab()
    g.feed(r.stdout.decode("utf8", "ignore"))
    text = "".join(g.out)
    lines = [" ".join(l.split()) for l in text.splitlines()]
    text = "\n".join(l for l in lines if l)
    words = len(text.split())
    with open(out, "w") as f:
        f.write(f"SOURCE: {url}\n\n{text}\n")
    print(f"{words} words -> {out}")
    if words < 300:
        sys.exit(f"only {words} words extracted from {url}; treat as a failed read")


if __name__ == "__main__":
    main()
