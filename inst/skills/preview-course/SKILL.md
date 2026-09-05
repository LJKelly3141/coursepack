---
name: preview-course
description: Use when previewing, reviewing, or reorganizing a course's module structure locally before importing into Canvas, or when collecting a list of things to fix about a course. Triggers on "show me the course layout", "preview the modules", "does this ordering make sense", "check the course structure", "mockup the course", "make mockup", "are any homework links broken", "review the course and tell me what to fix", "leave notes on the mockup", or any request to see how a course is organized without uploading to an LMS.
---

# Preview a course locally

Renders `course.yml` plus `modules.yml` into a browsable mockup showing module
organization and previewing each item's content. No LMS, no upload, no network
required when the content is built locally.

Works for any course using the two-file manifest pattern. Nothing is
course-specific.

## Run it

    make mockup                              # local textbook, default
    make mockup MOCKUP_BASE=live             # published site
    make mockup MOCKUP_PORT=9000             # if 8765 is taken

## What it shows

Collapsible module cards with one row per item: content type, indent hierarchy,
publish state, `todo:` placeholders, and a red pill on any chapter or anchor that
does not resolve. Clicking a row opens the target inline.

Light and dark themes. A header button toggles between them, and with no explicit
choice the page follows the operating system. Only an explicit choice is stored.

## The review loop

Every item row and every module header carries a note affordance. Write what is
wrong, then use **Copy review prompt**, which composes the notes into a markdown
prompt on the clipboard. Paste that into a session and the issues become work.

Each note carries the module title and position, the item position and title, the
content type, and the resolved URL, so the receiving session can find the exact
thing without guessing. Publish state and `todo:` come along too, because they
usually explain the note. The prompt walks the course in module order rather than
the order the notes were written, so it reads top to bottom like the page.

**Notes are deliberately one-shot and live only in memory.** Two structural
reasons, and both must hold before anyone tries to make them persist:

- The server is `python3 -m http.server`, which is `SimpleHTTPRequestHandler`.
  It answers GET and HEAD. It cannot accept a write, so a note has nowhere to
  POST itself.
- `build_preview()` starts by deleting `build/mockup/` entirely, deliberately,
  because stale build files caused a real bug. A notes file written there would
  be destroyed by the next `make mockup`.

Persisting notes therefore means both replacing the server with one that accepts
writes and choosing a location outside `build/`. That is a real feature, not a
small addition. The page warns on close while notes exist, because a reload loses
the review.

### What the notes will surface, and it is worth expecting

The first real review of a course produced four notes, and two of them pointed at
content in a repository outside the project's writable workspace. That is normal
rather than a defect: the mockup shows a course as assembled, and a course
assembles content from wherever it lives. **Triage notes by who owns the target
before promising fixes.** A note about a page this project only links to is a
report, not a task.

## The trap that costs an hour

**A `file://` page cannot iframe a `file://` target in Chrome.** Each document
gets a unique opaque origin. Open `build/mockup/index.html` from disk and you get
a fully working tree with a permanently blank preview pane, and nothing in the
console that obviously explains why.

This is why `make mockup` runs an HTTP server rather than just opening a file,
and why the textbook is reached through a symlink inside the served directory
instead of an absolute path, and so is the course's own `docs/`, as `/site`.
Both exist for that one reason. Do not "simplify" either away.

Serving over HTTP buys a second thing worth knowing: `navigator.clipboard` needs
a secure context, and browsers treat `http://localhost` as one. The copy button
works because the page is served, not opened. There is an `execCommand` fallback
for anyone who opens it another way.

## Local versus live, and why the default is local

| Mode | Shows | Misses |
|---|---|---|
| `local` (default) | uncommitted content edits, works offline | anything broken only in production |
| `live` | exactly what a student gets, proves links resolve publicly | your unpushed work |

Local is the default because the common task is checking work in progress. Switch
to live before an import, because a link that resolves locally still fails for
students if the content was never pushed.

## Architecture, and the one thing not to change

`coursepack::build_preview()` emits a **data model** to
`build/mockup/course.json`. The page builds its DOM from that model at runtime.
The page and its stylesheet ship inside the package under `templates/mockup/`
and are copied into `build/mockup/` on every run.

Do not collapse this into direct HTML generation, even though it would be less
code. Drag-to-reorder writing back into `modules.yml` is planned, and it needs a
model to mutate. Generating markup directly makes that a rewrite. The note
anchors depend on the same model: they key off module and item positions the
model already carries.

Every colour in `mockup.css` is a custom property. Adding dark mode meant
tokenising a dozen literals that had been inlined into individual rules, and a
literal left behind shows up as a bright patch on exactly one row. If you add a
rule, use a token or add one.

## Before adding write-back

`modules.yml` is roughly 40 percent comments, and those comments carry the reason
for every deliberate divergence from the reference export. **Most YAML libraries
discard comments on round trip.** Any write-back path must preserve them or it
destroys the most valuable part of the file. Verify comment preservation on a
copy before pointing it at the real file.

## Relationship to the cartridge build

This previews. It proves nothing about Canvas. `make coursepack` builds the
importable artifact, and only a real import into a throwaway shell proves that
works. Never report a course as verified on the strength of the mockup.

The mockup must mirror the cartridge generator's semantics exactly, because a
preview that disagrees with what ships is lying about its only job. Publish state
is the worked example: `build_cartridge()` uses `isTRUE()`, so a missing
`published:` key means unpublished, and the mockup does the same. If the two ever
disagree, the mockup is wrong by definition.

## Output locations

Everything lands in `build/mockup/`, which is gitignored. Nothing is written to
`docs/`, which on this project is the public GitHub Pages directory. Keep it that
way: a preview tool has no business writing to a published site.
