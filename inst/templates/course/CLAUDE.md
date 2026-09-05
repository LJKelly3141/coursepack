# CLAUDE.md

Persistent context for this course repository. Read it before working here.

## What this is

Plain-text source for {{code}}, {{title}}. It builds three things: a public web
site rendered into `docs/`, a Canvas Common Cartridge, and QTI quiz packages.
The toolchain is the coursepack R package, installed rather than vendored; there
are no build scripts in this repository to keep in step with it.

Site: {{site_url}}

## Layout

```
course.yml            course facts: code, term, timezone, URLs, Canvas settings
modules.yml           the module tree, and the page, assignment and quiz definitions
announcements.yml     announcements the cartridge carries, and when they post
reference.yml         the Canvas export to diff against, and the one to carry from
_quarto.yml           the render allowlist and the output directory
Makefile              every target calls a coursepack function

content/pages/        .qmd rendered to docs/ and framed in Canvas
content/canvas/       bodies authored as raw Canvas HTML
content/announcements/ one HTML body per announcement

assessments/          PRIVATE. Quiz and exam sources with answers. Never rendered.
assessments/quizzes/  R/exams definitions, built with make qti
questions/            PRIVATE. Question banks, one JSON file per chapter.

assets/               PUBLIC. Copied into docs/ verbatim: data, images, handouts.
docs/                 PUBLIC. The published site. Committed, never in .gitignore.
reference/            Canvas exports, read-only. See reference/README.md.
```

## The four hard rules

1. **`docs/` is public.** It is served to anyone with the URL. Nothing goes in
   it that a student should not have before the sitting. The repository being
   private does not make the site private.
2. **`assessments/` is never rendered.** It sits outside the `render:` allowlist
   in `_quarto.yml`, and `make leakcheck` reads every byte under `docs/` looking
   for the canary string that lives in it. A hit is a refusal, not a warning.
   Never rewrite the allowlist as a blocklist: it would then fail open.
3. **Nothing is embedded in the cartridge except the course card and quiz
   figures.** Assets live on the published site and the cartridge links to them
   absolutely. Canvas rewrites internal file references through
   `$IMS-CC-FILEBASE$` tokens at import, and getting that wrong is the most
   common way a hand-built cartridge fails. Quiz figures are the one exception,
   because exam content cannot be public.
4. **A zip that builds proves nothing.** Canvas discards malformed content
   silently and reports a successful import. Import into a throwaway shell,
   look at it, export it back out, and compare.

## Working here

Course facts live in the YAML, never in code and never in a skill. Dates come
from the registrar's calendar, never from counting weeks. Every deadline is
stored as a UTC instant and read back in `term: timezone:`, so the zone is worth
checking before the first build rather than after the first missed deadline.

The skills in `.claude/skills/` cover the cartridge, the local preview, the
accessibility audit, the schedule review, question-bank authoring and the paper
forms. They are copies, stamped with the toolchain version they came from;
`make skills` refreshes them.

This repository was scaffolded by coursepack {{version}}. A target named here
exists at that version; when one stops working, `make install-toolchain` and
this file are the two places to look.
