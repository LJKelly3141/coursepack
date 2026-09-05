# assessments/

**Private. Never rendered. Never public.**

Quiz and exam sources, with the correct answers marked in plain text.

This directory is absent from the `project: render:` list in `_quarto.yml`, so
Quarto never renders it and nothing here reaches `docs/`. `docs/` is the only
directory the published site serves, so nothing here is publicly reachable.

## The render list is an allowlist, and it has to stay one

Quarto renders what the list names and nothing else, so a directory added to
this repository tomorrow is excluded until somebody names it. Rewriting the
list as a blocklist, a `"*.qmd"` glob with exclusions after it, inverts that: it
would then fail open, and the first assessment written outside the exclusion
would publish itself.

## The canary

`leak-canary.qmd` carries a string that exists nowhere else in the repository.
`make leakcheck` reads every byte under `docs/` looking for it and refuses on a
hit; `make site` runs it after every render, so a broken allowlist is caught by
the render that broke it rather than by a student.

It reads bytes rather than lines, so the canary cannot hide inside a rendered
PDF, an image, or a self-contained page's base64 payload. A missing `docs/` is a
refusal too: nothing was scanned, so nothing is known.

## What the canary does not cover

`_quarto.yml` also declares `resources:`, and everything matching those globs is
copied into `docs/` verbatim. That door is fail-open by construction: name a
directory and everything under it ships, including whatever is added to it
later. A canary cannot guard it, because everything under `assets/` is supposed
to be published, so the canary would fire on every correct build.

You can only put a canary on a door that is meant to be shut. **Putting a file
under `assets/` publishes it, and no check will stop you.**

## Quiz sources

`quizzes/` holds R/exams definitions. `make qti QUIZ=assessments/quizzes/<name>.R`
builds one into a QTI 1.2 package, and a `quiz:` in `modules.yml` carries it
into the cartridge. Classic quizzes only: New Quizzes are LTI-backed and do not
round-trip through an import.

Canvas fails silently on invalid QTI. A malformed quiz produces no error and
simply never appears, so every generated quiz is previewed in Canvas after
import. That is a required step, not advice.
