---
name: new-course
description: >
  Scaffold a new plain-text course repository that builds a Canvas cartridge, a
  public Pages site and a local preview. Use when the user says "start a new
  course", "scaffold a course", "set up a course repo", "new coursepack", or
  asks to move an existing Canvas course into plain text. Covers what the
  scaffold writes, the four hard rules it carries, and the order the first
  build has to happen in.
---

# Starting a course

A course is a directory of YAML, Quarto and JSON. `init_course()` writes it,
and everything after that is editing text and running `make`.

## What it asks for

Five facts, and two more if the course has them.

| Argument | What it is |
|---|---|
| `code` | the course code, as the registrar writes it |
| `title` | the course title |
| `site_url` | the GitHub Pages URL the rendered site will live at. Must start with `https://`, and it is where every asset in the cartridge is linked from |
| `timezone` | an IANA zone name, such as `America/Chicago`. Every deadline is stored in UTC and read back in this zone |
| `institution` | optional |
| `textbook_url` | optional, for a course whose reading lives in a second repository |

Interactively it prompts for what is missing, and `Sys.timezone()` is offered
as the suggestion for the zone. It is a suggestion. The machine's zone is the
zone the author happens to be sitting in, which is not necessarily the zone the
course meets in, so it is never used silently: an unrecognized zone stops.

```r
coursepack::init_course("path/to/new-course", code = "ABCD 101", title = "Introduction to Something",
                        site_url = "https://<user>.github.io/<repo>", timezone = "America/Chicago")
```

## The other entry point: a course already in Canvas

A course that already exists does not start from a blank manifest. Export it
from Canvas, then:

```r
coursepack::init_course("path/to/new-course", code = "ABCD 101", title = "Introduction to Something",
                        site_url = "https://<user>.github.io/<repo>", timezone = "America/Chicago",
                        from_export = "export.imscc")
```

The scaffold is written first, then the export replaces `course.yml`,
`modules.yml` and `reference.yml` with the extracted ones and is copied under
`reference/`. The zone and the due time are re-applied afterwards, because an
export carries neither: Canvas stored every deadline as a UTC instant and the
local day it belongs to is a reading, not a stored fact.

## What it writes

| Path | What it is |
|---|---|
| `course.yml` | code, title, institution, slug, `term:` with the timezone and an empty `breaks:`, `due_time:`, the site and textbook URLs, the `canvas:` settings, and one assignment group at weight 100 |
| `modules.yml` | the item-form legend as a comment, and one module, "Start here", holding a header, the welcome page, and a placeholder assignment carrying `todo:` and `published: false` |
| `announcements.yml` | the body directory, and one welcome announcement posted immediately |
| `content/pages/` | `welcome.qmd` and `syllabus.qmd`, a title and a paragraph each |
| `content/announcements/welcome.html` | the announcement body. A body file is the contract: the cartridge carries what is here |
| `content/canvas/` | bodies for anything authored as raw Canvas HTML |
| `assessments/` | the containment README, the leak canary page, and `quizzes/` |
| `assets/` | `images/`, `data/`, `files/`, and a README saying everything here is public |
| `questions/README.md` | the question bank schema, and that banks are never rendered |
| `_quarto.yml` | `output-dir: docs`, the render allowlist, and `embed-resources: true` |
| `index.qmd`, `style.css` | the site's front page |
| `Makefile` | `site`, `leakcheck`, `checkyml`, `coursepack`, `refdiff`, `mockup`, `qti`, `a11y`, `tile`, `skills`, `paper`, `test`, `clean`, `install-toolchain` |
| `.gitignore` | `build/`, `.quarto/`, `*_files/`, and the editor droppings |
| `README.md` | what the repository is, the three commands, and where content goes |
| `CLAUDE.md` | the layout and the four hard rules below |
| `reference/README.md` | how to export a Canvas course, where to put it, and what `export:` and `source:` mean in `reference.yml` |
| `.claude/skills/` | these skills, copied in when `skills = TRUE` |

Nothing is ever overwritten. The path must not exist, or must be empty.

## The four hard rules the course carries

`CLAUDE.md` states them, and every one of them has been learned the expensive
way somewhere:

1. **`docs/` is public.** It is served from GitHub Pages to anyone with the
   URL. Nothing goes in it that a student should not have before the sitting.
2. **`assessments/` is never rendered.** It is outside the render allowlist,
   and `leak_check()` scans `docs/` for the canary string that lives in it. A
   hit is a stop, not a warning.
3. **Nothing is embedded in the cartridge except the course card and the quiz
   figures.** Assets live on Pages and the cartridge links to them absolutely.
   Quiz figures are the one exception, because exam content cannot be public.
4. **A zip that builds proves nothing.** Canvas discards malformed content
   silently and reports success.

## The first run, in order

1. `make site`, and read the rendered pages.
2. Push, with `docs/` committed.
3. Enable GitHub Pages on the repository, from `main` and the `/docs` folder.
   Wait for the site to answer at `site_url` before building anything, because
   the cartridge links to it absolutely and a 404 is invisible in Canvas.
4. `make coursepack`.
5. Import the `.imscc` into a throwaway Canvas shell, never a live course.
   Imports add content; they do not replace it.
6. Look at it. Module structure, page rendering, and one asset link followed to
   a live Pages URL.
7. Export the shell back out of Canvas.
8. Compare the export against what you sent, item by item, on title and content
   type rather than on identifier. Canvas regenerates every identifier on
   import, so identifiers always differ and that is not a finding.

The scaffold is unverified until someone has imported it.
