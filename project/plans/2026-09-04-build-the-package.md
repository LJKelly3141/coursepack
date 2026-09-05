# Build the coursepack package: scripts and skills, in phases

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the two course toolchains snapshotted under `project/` into one installable R package, `coursepack`, that builds, checks, previews, audits, extracts, and prints a course from plain text, and ships its Claude Code skills, without opening either course repository.

**Architecture:** Every task reads its source from `project/econ730-toolchain/` and `project/econ202-toolchain/` (byte-identical to the live repos at 2026-09-04) and writes only under this repository. The ECON 730 R chain moves first as a pure move, protected by a byte gate: the frozen snapshot builder run against a synthetic fixture course must produce the same staging tree the package produces. Output-changing convergence, the accessibility subsystem, the Python builder's capabilities (carry-through, extraction, bank-generated quizzes, paper forms), the skills and scaffold, and public readiness follow as separate phases, each with its own exit gate. Anything a course repository must do is written into an appendix as a hand-off, never executed here.

**Tech Stack:** R (>= 4.1), testthat 3, roxygen2, xml2, yaml, digest, jsonlite, stringr, magick; `zip` and `pandoc` binaries; `exams` (Suggests) for R/exams QTI; Node/`npx` and Chrome for pa11y (audit only); `quarto` for paper forms (optional); `python3` used only as a test oracle and inside skill helper scripts.

**Spec:** the design record is `project/migration-spec.md`, `project/plans/2026-09-02-portable-coursepack.md`, `project/plans/2026-09-02-builder-merge.md`, `project/inventory.md`, `project/econ202-onboarding.md`, and the two snapshot READMEs. This plan supersedes their task lists (T01 to T30, M01 to M19, spec Tasks 1 to 13); Appendix E maps every one of those to a task here or says why it was dropped. The design sections of those documents still stand and are cited by section number.

## Global Constraints

Copied from the spec and the snapshot READMEs. Every task's requirements include this section.

- **This repository only.** No task creates, modifies, or deletes a file outside `/Users/logankelly/Sync/Developer/coursepack`. Course-side changes are written as hand-offs in Appendix A and B. Reading the live repos is allowed for verification only.
- **No commit without Logan's word for that specific commit.** Every task ends with a proposed commit message; the executor stops there. No `Co-Authored-By`, no AI attribution anywhere: commits, code comments, docs, skills.
- **Every entry point takes `proj` as its first argument.** Package code contains no absolute path, no `Sys.getenv()` for anything with a default, no course name, no course URL, no course number. Course facts live in that course's YAML.
- **Course content never enters the package.** Fixtures are invented: course code `ABCD 101`, hosts under `example.invalid`. The grep `grep -rniE 'econ ?[0-9]|uwrf|kelly|ljkelly|managerial|macro_principles' tests/testthat/fixtures/ inst/ R/` must return nothing (the course number is part of the pattern because a bare `econ` matches "second") at the end of every phase.
- **The byte gate is never regenerated to make a failing test pass.** A regeneration is a deliberate output change, in its own commit, whose message says the cartridge was supposed to change and lists which staged files changed.
- **Refuse loudly, never skip.** A missing body, a missing announcement body, an unknown `post:` form, a published `todo:`, a collapsed quiz ident, an unknown `canvas:` key, a `source_ref` not in the source: all `stop()`.
- **Canvas stores structure, never content.** No `$IMS-CC-FILEBASE$` token and no embedded file except the course card, and, from Phase 4 with decision D15, quiz figures under `web_resources/quiz_images/`.
- **The three answer-key guards stay independent**: truncation at the answer-key heading, the canary stop, the pre-zip byte scan. None is removed because the others cover it.
- **Every check reads what ships** (the staged tree, the zip, the export), never the R object that wrote it.
- **A zip that builds proves nothing.** Every builder prints that in its last two lines. No task reports a Canvas import as verified; Appendix D lists the human gates.
- **No em-dashes in anything shipped or student-facing**: `R/`, `inst/`, `README.md`, `NEWS.md`, `CONTRIBUTING.md`, templates, skills, generated HTML. Rework the sentence instead.
- **Version discipline.** Bump the fourth component of `Version:` in `DESCRIPTION` in every task that changes behaviour, and add a `NEWS.md` line. Every exported entry point prints `coursepack <version>` in its closing summary.
- **R CMD check stays at 0 errors, 0 warnings** from Task 1 onward; the two skeleton NOTEs close in Task 1. Run `R CMD build . && R CMD check --no-manual coursepack_*.tar.gz` from a scratch directory at the end of every task that adds an export.
- **Tests skip, never fail, on a missing system tool**: `zip`, `pandoc`, `python3`, `npx`, `quarto`, and the `exams` package. Use the helpers in `tests/testthat/helper-skips.R` (Task 4).
- **Tools present on the authoring machine on 2026-09-04**, so the executor can rely on them locally: Rscript, pandoc, zip, unzip, python3 3.9 with PyYAML, quarto, npx, node, pdftotext; R packages devtools 2.5.2, roxygen2 8.1.0, testthat 3.3.2, exams 2.4.4, chromote 0.5.1, xml2, yaml, digest, jsonlite, stringr, magick, withr.

Standing commands used throughout:

```bash
# from the package root
Rscript -e 'roxygen2::roxygenise()'                       # regenerate NAMESPACE and man/
Rscript -e 'testthat::test_local(filter = "<name>")'      # one test file: tests/testthat/test-<name>.R
Rscript -e 'testthat::test_local()'                       # whole suite
# full check, in a scratch dir so the tarball never lands in the tree
SCR=$(mktemp -d) && R CMD build --no-build-vignettes . && mv coursepack_*.tar.gz "$SCR"/ && (cd "$SCR" && _R_CHECK_FORCE_SUGGESTS_=false R CMD check --no-manual coursepack_*.tar.gz | tail -5)
```

---

## File structure

What each file is responsible for, so the decomposition is fixed before any task starts. "Move" means the file's contents come from the snapshot with only the edits its task names.

| Path | Responsibility | Origin |
|---|---|---|
| `R/utils.R` | `%||%`, `coursepack_version()`, `version_line()` | new (Task 1) |
| `R/ids.R` | `gid()`, `xesc()`, `xtext()`, `oneline()`, `slugify()`, `writef()`, the `XSI` and `CCV` namespace strings | move from `build_cartridge.R` 132 to 176 (Task 10) |
| `R/config.R` | `read_course()`, `read_modules()`, `read_manifest()`, `read_reference()`, `read_announcements()`, `read_timezone()`, `textbook_docs_path()`, `course_slug()`, `proj_path()` | new (Task 2), announcement validation moved from `build_cartridge.R` 84 to 127 |
| `R/time.R` | `local_to_utc()`, `parse_when()`, `due_stamp()` | new (Task 3); `parse_when()` generalises `ann_when()` |
| `R/resolve.R` | `interp_urls()`, `chapter_url()`, `resolve_target()`, `collect_refs()` | move from `lib/resolve.R` (Task 6) |
| `R/body-homework.R` | `homework_section_html()` | move from `lib/homework_body.R` (Task 7) |
| `R/body-quiz.R` | `LEAK_CANARY`, `ANSWER_KEY_HEADING_RE`, `quiz_student_md()`, `quiz_student_html()` | move from `lib/quiz_body.R` (Task 7) |
| `R/manifests.R` | `check_manifests()` | move from `check_manifests.R` (Task 8) |
| `R/refdiff.R` | `diff_against_reference()`, `divergence_declared()`, `unpack_cartridge()` | move from `diff_against_reference.R` (Task 9) |
| `R/cartridge.R` | `build_cartridge()`: orchestration, staging purge, mtime pinning, zip, closing lines | move (Task 10) |
| `R/cartridge-items.R` | the flat item table: `resolve_items()`, `url_for()` | move from `build_cartridge.R` 177 to 248 (Task 10) |
| `R/cartridge-xml.R` | course settings, groups, grading standard, late policy, files_meta, media_tracks, marker, `module_meta.xml`, weblinks, wiki pages, assignments, manifest | move from 250 to 480 and 522 to 623 and 943 to 1053 (Task 10) |
| `R/cartridge-quiz.R` | R/exams zip embedding with the prefix rewrite and both guards | move from 625 to 780 (Task 10) |
| `R/cartridge-announcements.R` | announcement staging and the read-back checks | move from 782 to 941 and 1140 to 1241 (Task 10) |
| `R/cartridge-checks.R` | the pre-zip scan: declared vs on disk, FILEBASE, sources, canary bytes, dangling and orphan refs, well-formed XML | move from 1055 to 1138 (Task 10) |
| `R/qti.R` | `build_qti()` | move from `build_qti.R` (Task 11) |
| `R/preview.R` | `build_preview()` | move from `build_preview.R` (Task 12) |
| `inst/templates/mockup/` | `index.html`, `mockup.css`, `mockup.js` | copy from `templates/mockup/` (Task 12) |
| `R/gate.R` | `normalize_manifest_date()`, `tree_hashes()`, `write_expected_tree()`, `gate_check()` | new (Task 5) |
| `tools/baseline.R` | runs the frozen snapshot builder against a fixture and writes an expected tree | new (Task 5) |
| `R/groups.R` | `assignment_group_ids()`, `group_id_for()` | new (Task 15) |
| `R/settings.R` | `CANVAS_SETTINGS_KEYS`, `course_settings_xml()` | new (Task 16), replaces the inline block |
| `R/stale.R` | `check_stale_heights()` | new (Task 22), port of `check_stale_measurements()` |
| `R/a11y-serve.R`, `R/a11y-model.R`, `R/a11y-targets.R`, `R/a11y-checks.R`, `R/a11y-cartridge.R`, `R/a11y-report.R` | the six library files | move (Tasks 23 to 25) |
| `R/a11y.R` | `audit_course()` | move from `audit_a11y.R` (Task 26) |
| `R/cartridge-carry.R` | `source_ref` handling, dependency walk, carried transforms | new (Tasks 29 to 31), port of `source_resources()`, `sync_carried_titles()`, `apply_due_dates()`, `fix_accessibility()` |
| `R/extract.R` | `extract_manifest()` | new (Task 32), port of `extract_cartridge_manifest.py` |
| `R/bank.R` | `read_bank()`, `check_bank()`, `check_question()` | new (Task 34), port of `load_bank()`, `check_question()` |
| `R/generate-quiz.R` | `generate_quiz_files()`, `item_xml()`, `answer_ids()`, `normalize_tables()`, `expand_splits()`, `window_utc()` | new (Task 35), port of `generate_resources.py` |
| `R/generate-assignment.R` | `generate_assignment_files()` | new (Task 36) |
| `R/announcements-schedule.R` | `announcements_from_schedule()` | new (Task 38), port of `announcements.py` |
| `R/convert.R` | `convert_python_manifests()`, `gid_py()` | new (Task 39), builder-merge 3.8 |
| `R/print.R` | `print_assessment()` | new (Task 40), M19 |
| `R/skills.R` | `install_skills()` | new (Task 43) |
| `R/init.R` | `render_template()`, `init_course()`, `leak_check()` | new (Tasks 44, 45) |
| `inst/skills/<name>/` | eight skills | Tasks 41, 42 |
| `inst/templates/course/` | the scaffold | Task 44 |
| `tests/testthat/fixtures/minimal-course/` | the synthetic course every gate uses | Task 4 |
| `tests/testthat/fixtures/fake-textbook/docs/` | two Quarto-shaped chapter pages | Task 4 |
| `tests/testthat/fixtures/qti-sample/` | an unzipped R/exams-shaped QTI package | Task 4 |
| `tests/testthat/fixtures/pair/` | two course dirs sharing a basename, two that do not | Task 4 |
| `tests/testthat/fixtures/src/` | an unzipped synthetic Canvas export for carry and extract | Task 29 |
| `tests/testthat/fixtures/bank/` | a synthetic question bank in the JSON schema | Task 34 |
| `tests/testthat/fixtures/minimal-course-expected-tree.txt` | the byte gate | Task 5, regenerated deliberately in Phase 2 |
| `tools/scrub.sh` | the public-readiness greps | Task 47 |
| `.github/workflows/check.yml` | CI | Task 49 |

## Phase map

| Phase | Tasks | Exit gate |
|---|---|---|
| 0 Foundations | 1 to 5 | suite green; `minimal-course-expected-tree.txt` committed; fixture grep clean |
| 1 The ECON 730 chain, pure move | 6 to 13 | `test-cartridge-gate.R` passes; every assertion from `test_resolve.R` and `test_preview.R` ported; check clean |
| 2 Converge, output changes on purpose | 14 to 22 | one deliberate baseline regeneration per output-changing task, each its own commit; NEWS lists every change |
| 3 Accessibility | 23 to 28 | every `check()` of `test_a11y.R` ported into a `test_that()`; pa11y integration test runs locally and skips without `npx` |
| 4 Carry, extract, generate, print | 29 to 40 | synthetic round trip clean; Python parity test green locally |
| 5 Skills and scaffold | 41 to 46 | `inst/` grep clean; scaffold passes `check_manifests()` and `build_cartridge()`; `install_skills()` round-trips |
| 6 Public readiness | 47 to 50 | `tools/scrub.sh` clean; CI green; Logan's decisions in Appendix C recorded |

Dependencies that cross phases: Task 10 needs 5 to 9; Task 14 needs 3; Task 29 needs 10 and 18; Task 32 needs 29; Task 33 needs 32; Task 35 needs 34 and 3; Task 36 needs 15, 35; Task 39 needs 36; Task 40 needs 35; Task 45 needs 32, 43, 44; Task 46 needs 8, 10, 45. Everything else is serial within its phase.

---

# Phase 0: Foundations

### Task 1: Package hygiene, `%||%` once, the version stamp

**Files:**
- Create: `R/utils.R`, `NEWS.md`, `tests/testthat/test-utils.R`
- Modify: `R/tile.R` (delete line 139), `DESCRIPTION` (Version), `.Rbuildignore` (add `^tools$`, `^NEWS\.md$` is NOT added; NEWS ships), `tests/testthat/.gitkeep` (delete)

**Interfaces:**
- Produces: `` `%||%`(a, b) `` internal; `coursepack_version()` exported, returns character; `version_line(what)` internal, prints `"<what>: coursepack <version>"`.

- [ ] **Step 1: Write the failing tests**

```r
# tests/testthat/test-utils.R
test_that("%||% returns the default only for NULL", {
  expect_equal(NULL %||% 2, 2)
  expect_equal(1 %||% 2, 1)
  expect_equal(NA %||% 2, NA)
  expect_equal(list() %||% 2, list())
})

test_that("coursepack_version() matches DESCRIPTION", {
  expect_equal(coursepack_version(), as.character(utils::packageVersion("coursepack")))
})

test_that("version_line prints the version after a label", {
  expect_output(version_line("built"), "built: coursepack [0-9.]+")
})
```

- [ ] **Step 2: Run to verify failure**

Run: `Rscript -e 'testthat::test_local(filter = "utils")'`
Expected: FAIL, `could not find function "coursepack_version"`.

- [ ] **Step 3: Write `R/utils.R`**

```r
# Defined once. The snapshot defines this operator in eight files because each
# had to be sourceable alone; a package defines it once and every file sees it.
`%||%` <- function(a, b) if (is.null(a)) b else a

#' The installed coursepack version
#'
#' Every entry point prints this in its closing summary, because editing `R/`
#' and forgetting to reinstall builds a course with old code silently. The
#' printed version is what tells the two apart.
#' @return The version string, invisibly printed by the entry points.
#' @export
coursepack_version <- function() as.character(utils::packageVersion("coursepack"))

version_line <- function(what) {
  cat(sprintf("%s: coursepack %s\n", what, coursepack_version()))
  invisible(coursepack_version())
}
```

- [ ] **Step 4: Delete the copy in `R/tile.R`**

Delete line 139 of `R/tile.R`: `` `%||%` <- function(a, b) if (is.null(a)) b else a ``. Nothing else in that file changes.

- [ ] **Step 5: Close the two check NOTEs and start NEWS**

```bash
git rm tests/testthat/.gitkeep
printf '^coursepack\\.Rproj$\n^\\.Rproj\\.user$\n^\\.github$\n^project$\n^\\.claude$\n^LICENSE\\.md$\n^tools$\n' > .Rbuildignore
```

The unused-Imports NOTE (`digest`, `jsonlite`, `stringr`, `tools`, `utils`, `xml2`) closes as later tasks use them. Until then, keep the declarations and accept the NOTE; do not remove Imports that Task 10 needs. `utils` is used from this task on (`utils::packageVersion`).

Create `NEWS.md`:

```markdown
# coursepack 0.0.0.9001

* `%||%` is defined once, in `R/utils.R`.
* `coursepack_version()` and the closing version line every entry point prints.
```

Set `Version: 0.0.0.9001` in `DESCRIPTION`.

- [ ] **Step 6: Document, test, check**

```bash
Rscript -e 'roxygen2::roxygenise()'
Rscript -e 'testthat::test_local()'
```
Expected: `utils` 4 pass, `tile` 8 pass. Then the full check command from Global Constraints: 0 errors, 0 warnings, at most the unused-Imports NOTE.

- [ ] **Step 7: Propose the commit and stop**

```
Define %||% once, add the version stamp, close the .gitkeep NOTE
```

---

### Task 2: Config readers

**Files:**
- Create: `R/config.R`, `tests/testthat/test-config.R`

**Interfaces:**
- Consumes: `%||%` (Task 1).
- Produces, all exported unless noted:
  - `proj_path(proj, p)` internal: `p` if it starts with `/`, else `file.path(proj, p)`.
  - `read_course(proj)`: parsed `course.yml`; stops `"no course.yml under <proj>"`.
  - `read_modules(proj)`: parsed `modules.yml`; stops likewise.
  - `read_manifest(proj)`: `list(course, mods, pages, assignments, quizzes)` with `pages` named by `slug`, `assignments` and `quizzes` named by `id`; stops on a duplicate slug or id naming it.
  - `read_reference(proj)`: parsed `reference.yml` or `NULL`.
  - `read_announcements(proj)`: validated list `list(body_dir, tz, first_day, last_day, announcements)` or `NULL` when the file is absent. Validation is the builder's block at snapshot lines 84 to 127, verbatim in behaviour: missing `body_dir`, missing `term` fields, a zone not in `OlsonNames()`, malformed dates, `first_day > last_day`, no announcements, a missing field, a duplicate `id`, `title`, or `body` all `stop()` with the same messages.
  - `read_timezone(course)`: `course$term$timezone`; stops `"course.yml needs term: timezone: <IANA name>"` when absent or not in `OlsonNames()`.
  - `textbook_docs_path(course, proj)`: `NULL` when `textbook_docs` is the string `"none"`; stops `"course.yml needs textbook_docs: a path to the rendered textbook, or none"` when the key is absent; otherwise the absolute path (relative values resolve against `proj`).
  - `course_slug(course)`: `course$slug %||% slugify(course$canvas$course_code %||% course$code)`. `slugify()` arrives in Task 10; until then define a private copy here with the identical body and delete it in Task 10.

- [ ] **Step 1: Write the failing tests**

```r
# tests/testthat/test-config.R
mk <- function(...) {
  d <- withr::local_tempdir(.local_envir = parent.frame())
  for (f in list(...)) writeLines(f$text, file.path(d, f$name))
  d
}
yml <- function(name, text) list(name = name, text = text)

test_that("read_course and read_modules stop on missing files, naming proj", {
  d <- withr::local_tempdir()
  expect_error(read_course(d), "course.yml")
  expect_error(read_modules(d), "modules.yml")
})

test_that("read_manifest names pages by slug and definitions by id", {
  d <- mk(yml("course.yml", "code: ABCD 101\ntitle: T\n"),
          yml("modules.yml", paste(
            "modules:", "  - title: M", "    items:", "      - page: a", "      - assignment: hw",
            "pages:", "  - slug: a", "    title: A", "    body: true",
            "assignments:", "  - id: hw", "    title: HW",
            "quizzes:", "  - id: q1", "    title: Q", "    qti: build/qti/q1.zip", sep = "\n")))
  m <- read_manifest(d)
  expect_named(m$pages, "a"); expect_named(m$assignments, "hw"); expect_named(m$quizzes, "q1")
  expect_equal(m$course$code, "ABCD 101")
})

test_that("read_manifest stops on a duplicate slug or id", {
  d <- mk(yml("course.yml", "code: ABCD 101\n"),
          yml("modules.yml", "modules: []\npages:\n  - slug: a\n  - slug: a\nassignments: []\n"))
  expect_error(read_manifest(d), "duplicate page slug: a")
})

test_that("read_reference and read_announcements return NULL when absent", {
  d <- mk(yml("course.yml", "code: ABCD 101\n"))
  expect_null(read_reference(d)); expect_null(read_announcements(d))
})

test_that("read_announcements validates like the builder did", {
  base <- c("body_dir: content/announcements",
            "term: {timezone: America/Chicago, first_day: 2026-09-01, last_day: 2026-12-15}")
  ok <- c(base, "announcements:", "  - {id: w, title: Welcome, body: w.html, post: immediately}")
  d <- mk(yml("announcements.yml", paste(ok, collapse = "\n")))
  a <- read_announcements(d)
  expect_equal(a$tz, "America/Chicago"); expect_named(a$announcements, "w")
  expect_equal(a$body_dir, file.path(d, "content/announcements"))
  bad_tz <- sub("America/Chicago", "Central", ok)
  d2 <- mk(yml("announcements.yml", paste(bad_tz, collapse = "\n")))
  expect_error(read_announcements(d2), "not an IANA zone name")
  d3 <- mk(yml("announcements.yml", paste(base, collapse = "\n")))
  expect_error(read_announcements(d3), "declares no announcements")
  dup <- c(ok, "  - {id: w, title: Again, body: x.html, post: immediately}")
  d4 <- mk(yml("announcements.yml", paste(dup, collapse = "\n")))
  expect_error(read_announcements(d4), "duplicate id: w")
})

test_that("read_timezone requires a real IANA zone under term:", {
  expect_equal(read_timezone(list(term = list(timezone = "Europe/London"))), "Europe/London")
  expect_error(read_timezone(list(term = "TBD")), "term: timezone")
  expect_error(read_timezone(list(term = list(timezone = "Central"))), "term: timezone")
})

test_that("textbook_docs_path resolves relative paths, honours none, refuses absence", {
  expect_equal(textbook_docs_path(list(textbook_docs = "../book/docs"), "/p/course"),
               "/p/course/../book/docs")
  expect_equal(textbook_docs_path(list(textbook_docs = "/abs/docs"), "/p"), "/abs/docs")
  expect_null(textbook_docs_path(list(textbook_docs = "none"), "/p"))
  expect_error(textbook_docs_path(list(), "/p"), "textbook_docs")
})

test_that("course_slug prefers slug:, then the Canvas course code, then code", {
  expect_equal(course_slug(list(slug = "my-course")), "my-course")
  expect_equal(course_slug(list(code = "ABCD 101", canvas = list(course_code = "ABCD 101-01"))), "abcd-101-01")
  expect_equal(course_slug(list(code = "ABCD 101")), "abcd-101")
})
```

- [ ] **Step 2: Run to verify failure**

Run: `Rscript -e 'testthat::test_local(filter = "config")'`
Expected: FAIL, `could not find function "read_course"`.

- [ ] **Step 3: Write `R/config.R`**

```r
proj_path <- function(proj, p) if (startsWith(p, "/")) p else file.path(proj, p)

read_yaml_under <- function(proj, name) {
  f <- file.path(proj, name)
  if (!file.exists(f)) stop("no ", name, " under ", proj, call. = FALSE)
  yaml::yaml.load_file(f)
}

#' Read a course's manifests
#'
#' `read_course()` and `read_modules()` parse `course.yml` and `modules.yml`
#' under `proj`. `read_manifest()` parses both and names the `pages:`,
#' `assignments:` and `quizzes:` definitions by slug or id, stopping on a
#' duplicate, because every later step indexes by those names.
#' @param proj Course project root.
#' @return `read_manifest()` returns `list(course, mods, pages, assignments, quizzes)`.
#' @export
read_course <- function(proj) read_yaml_under(proj, "course.yml")

#' @rdname read_course
#' @export
read_modules <- function(proj) read_yaml_under(proj, "modules.yml")

named_by <- function(x, key, what) {
  if (is.null(x) || !length(x)) return(setNames(list(), character()))
  keys <- vapply(x, function(e) as.character(e[[key]] %||% ""), "")
  if (any(!nzchar(keys))) stop("a ", what, " has no ", key, ":", call. = FALSE)
  if (anyDuplicated(keys)) stop("duplicate ", what, " ", key, ": ",
                                paste(unique(keys[duplicated(keys)]), collapse = ", "), call. = FALSE)
  setNames(x, keys)
}

#' @rdname read_course
#' @export
read_manifest <- function(proj) {
  course <- read_course(proj); mods <- read_modules(proj)
  list(course = course, mods = mods,
       pages = named_by(mods$pages, "slug", "page"),
       assignments = named_by(mods$assignments, "id", "assignment"),
       quizzes = named_by(mods$quizzes, "id", "quiz"))
}

#' @rdname read_course
#' @export
read_reference <- function(proj) {
  f <- file.path(proj, "reference.yml")
  if (!file.exists(f)) return(NULL)
  yaml::yaml.load_file(f)
}

#' Read and validate announcements.yml
#'
#' Optional as a file, binding once present. Every message below is the one
#' the ECON 730 builder printed; the checks moved here so a defective file
#' stops the build before anything is staged.
#' @param proj Course project root.
#' @return `NULL` when the file is absent, else `list(body_dir, tz, first_day, last_day, announcements)`.
#' @export
read_announcements <- function(proj) {
  ann_file <- file.path(proj, "announcements.yml")
  if (!file.exists(ann_file)) return(NULL)
  ay <- yaml::yaml.load_file(ann_file)
  if (is.null(ay$body_dir) || !nzchar(ay$body_dir))
    stop("announcements.yml has no body_dir:", call. = FALSE)
  body_dir <- proj_path(proj, ay$body_dir)
  tm <- ay$term
  if (is.null(tm$timezone) || is.null(tm$first_day) || is.null(tm$last_day))
    stop("announcements.yml needs term: timezone, first_day and last_day. ",
         "Every post time is read in that zone and must fall inside that window.", call. = FALSE)
  tz <- as.character(tm$timezone)
  if (!tz %in% OlsonNames())
    stop("announcements.yml: timezone '", tz, "' is not an IANA zone name ",
         "(for example America/Chicago)", call. = FALSE)
  ymd <- function(x, what) {
    x <- as.character(x)
    if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x))
      stop("announcements.yml: ", what, " must be YYYY-MM-DD, got: ", x, call. = FALSE)
    d <- as.Date(x); if (is.na(d)) stop("announcements.yml: ", what, " is not a real date: ", x, call. = FALSE)
    d
  }
  first <- ymd(tm$first_day, "term first_day"); last <- ymd(tm$last_day, "term last_day")
  if (first > last) stop("announcements.yml: term first_day is after last_day", call. = FALSE)
  anns <- ay$announcements
  if (is.null(anns) || !length(anns))
    stop("announcements.yml declares no announcements. Delete the file if none are wanted; ",
         "an empty declaration is indistinguishable from a forgotten one.", call. = FALSE)
  for (a in anns) for (need in c("id", "title", "body", "post"))
    if (is.null(a[[need]]) || !nzchar(trimws(as.character(a[[need]]))))
      stop("announcements.yml: an announcement is missing ", need, ": ",
           if (is.null(a$id)) "(no id)" else a$id, call. = FALSE)
  anns <- setNames(anns, vapply(anns, `[[`, "", "id"))
  for (fld in c("id", "title", "body")) {
    v <- vapply(anns, function(a) as.character(a[[fld]]), "")
    if (anyDuplicated(v))
      stop("announcements.yml: duplicate ", fld, ": ", paste(unique(v[duplicated(v)]), collapse = ", "), call. = FALSE)
  }
  list(body_dir = body_dir, tz = tz, first_day = first, last_day = last, announcements = anns)
}

#' The course timezone
#'
#' Read from `course$term$timezone`. There is no default: a default zone is a
#' fact about one instructor, and a wrong zone moves every due date and every
#' announcement by hours while looking fine in the XML.
#' @param course A parsed `course.yml`.
#' @export
read_timezone <- function(course) {
  tz <- course$term$timezone
  if (is.null(tz) || !is.character(tz) || !nzchar(tz) || !tz %in% OlsonNames())
    stop("course.yml needs term: timezone: <IANA name>, for example America/Chicago", call. = FALSE)
  tz
}

#' Where the rendered textbook lives
#'
#' `textbook_docs:` is the one place a checkout location is recorded. The
#' literal value `none` means the course has no separate textbook and every
#' textbook check skips loudly. An absent key is an error, never a guess.
#' @param course A parsed `course.yml`.
#' @param proj Course project root; relative values resolve against it.
#' @return An absolute path, or `NULL` for `none`.
#' @export
textbook_docs_path <- function(course, proj) {
  v <- course$textbook_docs
  if (is.null(v))
    stop("course.yml needs textbook_docs: a path to the rendered textbook, or none", call. = FALSE)
  if (identical(v, "none")) return(NULL)
  proj_path(proj, v)
}

#' The course slug used in the cartridge filename
#'
#' `slug:` in `course.yml` when set, else the slugified Canvas course code,
#' else the slugified `code`. Decision D1 of the portable plan.
#' @param course A parsed `course.yml`.
#' @export
course_slug <- function(course) {
  course$slug %||% slugify(course$canvas$course_code %||% course$code)
}

# Temporary: identical to the copy in the snapshot builder. Task 10 moves the
# real one into R/ids.R and deletes this.
slugify <- function(x) {
  x <- tolower(x)
  x <- gsub("[^a-z0-9]+", "-", x)
  gsub("^-+|-+$", "", x)
}
```

- [ ] **Step 4: Document, test**

```bash
Rscript -e 'roxygen2::roxygenise()'
Rscript -e 'testthat::test_local(filter = "config")'
```
Expected: 9 tests pass. Add `withr` to `Suggests` in `DESCRIPTION` (tests use it). Bump `Version: 0.0.0.9002`; NEWS line: "Config readers: `read_manifest()`, `read_announcements()`, `read_timezone()`, `textbook_docs_path()`, `course_slug()`."

- [ ] **Step 5: Propose the commit and stop**

```
Add the config readers every entry point will share
```

---

### Task 3: The timezone helper

**Files:**
- Create: `R/time.R`, `tests/testthat/test-time.R`

**Interfaces:**
- Produces:
  - `local_to_utc(date, time = "23:59:00", tz)`: `"%Y-%m-%dT%H:%M:%S"` in UTC; `date` is `"YYYY-MM-DD"` or a `Date`; `time` is `"HH:MM"` or `"HH:MM:SS"`; stops on an unparseable date or time or a zone not in `OlsonNames()`.
  - `parse_when(x, tz, what)`: the three announcement forms. `"immediately"` returns `NULL`; `"YYYY-MM-DD"` means midnight local; `"YYYY-MM-DD HH:MM"` or with `:SS` means that local time. Returns a `POSIXct` in `tz`. Anything else stops with `"<what>: post must be 'immediately', a date, or a date and HH:MM in the course zone; got: <x>"`.
  - `due_stamp(due, due_time, tz)`: for Phase 2. A bare date uses `due_time`; `"YYYY-MM-DD HH:MM[:SS]"` is used as given; returns the UTC string. When `due` is bare and `due_time` is `NULL`, stops `"a bare due: date needs due_time: in course.yml (for example \"23:59:59\")"`.

- [ ] **Step 1: Write the failing tests**

```r
# tests/testthat/test-time.R
test_that("local_to_utc reproduces the fixed-offset strings for every live 2026 date", {
  # The 17 ECON 730 due dates all fall before 2026-11-01, so the old builder's
  # `next day T04:59:00` arithmetic must be reproduced character for character.
  # Synthetic list spanning the same window, never read from modules.yml.
  dates <- as.Date("2026-09-11") + c(0, 7, 14, 21, 28, 35, 40, 42, 49)
  for (d in dates) {
    d <- as.Date(d, origin = "1970-01-01")
    expect_equal(local_to_utc(d, "23:59:00", "America/Chicago"),
                 paste0(format(d + 1, "%Y-%m-%d"), "T04:59:00"))
  }
})

test_that("local_to_utc handles the two 2026 daylight-time boundaries", {
  expect_equal(local_to_utc("2026-10-31", "23:59:00", "America/Chicago"), "2026-11-01T04:59:00")
  expect_equal(local_to_utc("2026-11-01", "23:59:00", "America/Chicago"), "2026-11-02T05:59:00")
  expect_equal(local_to_utc("2026-03-07", "23:59:00", "America/Chicago"), "2026-03-08T05:59:00")
  expect_equal(local_to_utc("2026-03-08", "23:59:00", "America/Chicago"), "2026-03-09T04:59:00")
})

test_that("local_to_utc: a midnight post and an in-person morning exam", {
  expect_equal(local_to_utc("2026-09-08", "00:00", "America/Chicago"), "2026-09-08T05:00:00")
  expect_equal(local_to_utc("2026-12-22", "09:45:00", "America/Chicago"), "2026-12-22T15:45:00")
  expect_equal(local_to_utc("2026-09-08", "00:00", "Europe/London"), "2026-09-07T23:00:00")
})

test_that("local_to_utc refuses bad input", {
  expect_error(local_to_utc("2026-13-01", "23:59", "America/Chicago"), "not a real date")
  expect_error(local_to_utc("2026-09-01", "25:00", "America/Chicago"), "time must be HH:MM")
  expect_error(local_to_utc("2026-09-01", "23:59", "Central"), "IANA")
})

test_that("parse_when accepts exactly three forms", {
  tz <- "America/Chicago"
  expect_null(parse_when("immediately", tz, "a"))
  expect_equal(format(parse_when("2026-09-08", tz, "a"), "%Y-%m-%d %H:%M", tz = tz), "2026-09-08 00:00")
  expect_equal(format(parse_when("2026-09-08 07:30", tz, "a"), "%H:%M", tz = tz), "07:30")
  expect_equal(format(parse_when("2026-09-08 07:30:15", tz, "a"), "%H:%M:%S", tz = tz), "07:30:15")
  expect_error(parse_when("now", tz, "welcome"), "welcome: post must be 'immediately'")
  expect_error(parse_when("2026-09-31", tz, "a"), "not a real date-time")
})

test_that("due_stamp uses due_time for a bare date and refuses a bare date without one", {
  expect_equal(due_stamp("2026-09-13", "23:59:59", "America/Chicago"), "2026-09-14T04:59:59")
  expect_equal(due_stamp("2026-12-22 09:45:00", "23:59:59", "America/Chicago"), "2026-12-22T15:45:00")
  expect_error(due_stamp("2026-09-13", NULL, "America/Chicago"), "needs due_time")
})
```

- [ ] **Step 2: Run to verify failure**

Run: `Rscript -e 'testthat::test_local(filter = "time")'`
Expected: FAIL, `could not find function "local_to_utc"`.

- [ ] **Step 3: Write `R/time.R`**

```r
#' Local course time to the UTC stamp Canvas stores
#'
#' Canvas stores every date in UTC with no zone marker and displays it in the
#' course zone. The old builder used a fixed UTC-5 and refused any date after
#' the 2026 daylight-time boundary; this does the arithmetic per date from the
#' IANA zone, so a spring course crossing the March boundary gets each date
#' right. No default zone exists anywhere in the package.
#' @param date `"YYYY-MM-DD"` or a `Date`.
#' @param time `"HH:MM"` or `"HH:MM:SS"`, local.
#' @param tz An IANA zone name.
#' @return `"YYYY-MM-DDTHH:MM:SS"` in UTC.
#' @export
local_to_utc <- function(date, time = "23:59:00", tz) {
  if (!is.character(tz) || length(tz) != 1L || !tz %in% OlsonNames())
    stop("timezone must be an IANA zone name (for example America/Chicago), got: ",
         paste(tz, collapse = ","), call. = FALSE)
  d <- if (inherits(date, "Date")) date else {
    x <- as.character(date)
    if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x)) stop("date must be YYYY-MM-DD, got: ", x, call. = FALSE)
    dd <- as.Date(x, optional = TRUE)
    if (is.na(dd) || format(dd) != x) stop("not a real date: ", x, call. = FALSE)
    dd
  }
  time <- as.character(time)
  if (!grepl("^[0-9]{2}:[0-9]{2}(:[0-9]{2})?$", time)) stop("time must be HH:MM or HH:MM:SS, got: ", time, call. = FALSE)
  if (nchar(time) == 5L) time <- paste0(time, ":00")
  hh <- as.integer(substr(time, 1, 2)); mm <- as.integer(substr(time, 4, 5)); ss <- as.integer(substr(time, 7, 8))
  if (hh > 23L || mm > 59L || ss > 59L) stop("time must be HH:MM or HH:MM:SS within a day, got: ", time, call. = FALSE)
  t <- as.POSIXct(paste(format(d), time), format = "%Y-%m-%d %H:%M:%S", tz = tz)
  if (is.na(t)) stop("not a real date-time in ", tz, ": ", format(d), " ", time, call. = FALSE)
  format(t, "%Y-%m-%dT%H:%M:%S", tz = "UTC")
}

#' Parse a post or due time in one of exactly three forms
#'
#' `immediately` (returns `NULL`), `YYYY-MM-DD` (midnight local), or
#' `YYYY-MM-DD HH:MM[:SS]`. Anything else stops, because a value that fails to
#' parse must never quietly become "post now".
#' @param x The value from YAML.
#' @param tz IANA zone.
#' @param what A label for the error message (the announcement or assignment id).
#' @return `NULL`, or a `POSIXct` in `tz`.
#' @export
parse_when <- function(x, tz, what) {
  x <- trimws(as.character(x))
  if (identical(x, "immediately")) return(NULL)
  if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x)) x <- paste(x, "00:00:00")
  if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$", x)) x <- paste0(x, ":00")
  if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$", x))
    stop(what, ": post must be 'immediately', a date, or a date and HH:MM in the course zone; got: ",
         x, call. = FALSE)
  t <- as.POSIXct(x, format = "%Y-%m-%d %H:%M:%S", tz = tz)
  if (is.na(t) || format(t, "%Y-%m-%d %H:%M:%S", tz = tz) != x)
    stop(what, ": post is not a real date-time: ", x, call. = FALSE)
  t
}

#' The UTC stamp for a due date
#'
#' A bare date takes `due_time` from `course.yml`; a date with a clock time is
#' used as given (an in-person exam ending at 09:45 is due at 09:45, not at
#' midnight). Decision D6: the package has no default `due_time`.
#' @param due `"YYYY-MM-DD"` or `"YYYY-MM-DD HH:MM[:SS]"`.
#' @param due_time `"HH:MM:SS"` from `course.yml`, or `NULL`.
#' @param tz IANA zone.
#' @export
due_stamp <- function(due, due_time, tz) {
  due <- trimws(as.character(due))
  if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", due)) {
    if (is.null(due_time))
      stop("a bare due: date needs due_time: in course.yml (for example \"23:59:59\"); got due: ", due, call. = FALSE)
    return(local_to_utc(due, due_time, tz))
  }
  if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}(:[0-9]{2})?$", due))
    stop("due must be YYYY-MM-DD or YYYY-MM-DD HH:MM[:SS], got: ", due, call. = FALSE)
  local_to_utc(substr(due, 1, 10), substr(due, 12, nchar(due)), tz)
}
```

- [ ] **Step 4: Document, test, bump**

```bash
Rscript -e 'roxygen2::roxygenise()'
Rscript -e 'testthat::test_local(filter = "time")'
```
Expected: 6 tests pass. `Version: 0.0.0.9003`; NEWS: "Timezone helper: `local_to_utc()`, `parse_when()`, `due_stamp()`; replaces the fixed UTC-5 arithmetic and the 2026-11-01 stop."

- [ ] **Step 5: Propose the commit and stop**

```
Add the timezone helper, tested at both 2026 boundaries
```

---

### Task 4: Synthetic fixtures and the test helpers

**Files:**
- Create: `tests/testthat/helper-skips.R`, `tests/testthat/helper-fixtures.R`, `tests/testthat/test-fixtures.R`
- Create under `tests/testthat/fixtures/`: `minimal-course/` (files listed below), `fake-textbook/docs/ch01.html`, `fake-textbook/docs/ch02.html`, `qti-sample/quiz-sample/assessment_meta.xml`, `qti-sample/quiz-sample/quiz-sample.xml`, `pair/alpha/site/index.html`, `pair/beta/site/index.html`, `pair/other/alpha/site/index.html`

**Interfaces:**
- Produces:
  - `skip_if_no("zip")`, `skip_if_no("pandoc")`, `skip_if_no("python3")`, `skip_if_no("npx")`, `skip_if_no("quarto")`: `testthat::skip()` when `Sys.which(tool)` is empty. `skip_if_no_exams()`: skip when `!requireNamespace("exams")`.
  - `fixture_path(...)`: `testthat::test_path("fixtures", ...)`.
  - `copy_course(name = "minimal-course", to = withr::local_tempdir())`: copies `fixtures/<name>` to `<to>/<name>` and `fixtures/fake-textbook` beside it so `textbook_docs: ../fake-textbook/docs` resolves; returns the course path.
  - `zip_fixture_qti(course_dir)`: zips `fixtures/qti-sample/quiz-sample/` into `<course_dir>/build/qti/quiz-sample.zip` (needs `zip`); returns the zip path.

- [ ] **Step 1: Write the helpers**

```r
# tests/testthat/helper-skips.R
skip_if_no <- function(tool) {
  if (!nzchar(Sys.which(tool))) testthat::skip(paste(tool, "is not on the PATH"))
}
skip_if_no_exams <- function() {
  if (!requireNamespace("exams", quietly = TRUE)) testthat::skip("the exams package is not installed")
}
```

```r
# tests/testthat/helper-fixtures.R
fixture_path <- function(...) testthat::test_path("fixtures", ...)

copy_course <- function(name = "minimal-course", to = withr::local_tempdir(.local_envir = parent.frame())) {
  ok <- file.copy(fixture_path(name), to, recursive = TRUE)
  ok2 <- file.copy(fixture_path("fake-textbook"), to, recursive = TRUE)
  stopifnot(all(ok), all(ok2))
  normalizePath(file.path(to, name))
}

zip_fixture_qti <- function(course_dir) {
  src <- fixture_path("qti-sample", "quiz-sample")
  out_dir <- file.path(course_dir, "build", "qti")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  zipf <- normalizePath(file.path(out_dir, "quiz-sample.zip"), mustWork = FALSE)
  old <- setwd(dirname(src)); on.exit(setwd(old), add = TRUE)
  utils::zip(zipf, list.files(basename(src), recursive = TRUE, full.names = TRUE), flags = "-q -X")
  zipf
}
```

- [ ] **Step 2: Write the fixture course**

`tests/testthat/fixtures/minimal-course/course.yml`:

```yaml
# A synthetic course. Every value is invented. It exercises every item form the
# builder knows so that the byte gate reaches every code path.
code: ABCD 101
section: "01"
title: Example Course
institution: Example University
term:
  name: Example Term
  first_day: 2026-09-01
  last_day: 2026-12-15
  timezone: America/Chicago
  breaks: []
urls:
  textbook: https://example.invalid/book
  site: https://example.invalid/course
  media: https://example.invalid/course/media
textbook_docs: ../fake-textbook/docs
canvas:
  course_code: ABCD 101-01
  default_view: modules
  is_public: false
  license: private
  indexed: false
  grading_standard_enabled: true
  group_weighting_scheme: percent
  restrict_enrollments_to_course_dates: false
assignment_groups:
  - name: Assignments
    position: 1
    weight: 100.0
grading_standard:
  title: Example Standard
  data: '[["A",0.9],["B",0.8],["C",0.7],["F",0.0]]'
late_policy:
  missing_submission_deduction_enabled: false
  late_submission_deduction_enabled: false
  late_submission_minimum_percent_enabled: false
assignment_defaults:
  points: 50
  submission_types: online_upload
  allowed_extensions: doc,docx
  group: Assignments
```

`tests/testthat/fixtures/minimal-course/modules.yml`:

```yaml
# Item forms: header, page (iframe and body), link (chapter and url),
# assignment (homework, quiz_file, todo), quiz (R/exams zip).
modules:
  - title: "Module 1: Start Here"
    published: true
    sequential: true
    items:
      - header: "1. Read the welcome page"
      - page: welcome
        indent: 1
      - page: chapter-one
        indent: 1
      - link: "Reading: the first chapter"
        chapter: ch01
        anchor: sec-intro
        indent: 1
      - link: "Textbook home"
        chapter: ""
      - link: "An outside page"
        url: "{site}/extra.html"
        new_tab: true
      - assignment: hw-1
      - assignment: quiz-1
      - assignment: todo-1
      - quiz: q-sample
  - title: "Module 2: Unpublished"
    published: false
    items:
      - header: "Coming later"
      - link: "Second chapter"
        chapter: ch02
pages:
  - slug: welcome
    title: Welcome
    iframe: "{site}/welcome.html"
    width: "100%"
    height: "800"
  - slug: chapter-one
    title: Chapter One
    body: true
assignments:
  - id: hw-1
    title: Homework 1
    points: 50
    due: 2026-09-15
    published: true
    homework:
      chapter: ch01
      anchor: homework-assignment
      title: Chapter One Homework
  - id: quiz-1
    title: Module 1 Quiz
    points: 20
    due: 2026-09-20
    published: true
    quiz_file: assessments/quizzes/quiz01.md
  - id: todo-1
    title: Placeholder Assignment
    published: false
    todo: "write this once the chapter exists"
    homework:
      chapter: ch02
quizzes:
  - id: q-sample
    title: Sample R/exams Quiz
    qti: build/qti/quiz-sample.zip
    published: true
```

`tests/testthat/fixtures/minimal-course/announcements.yml`:

```yaml
body_dir: content/announcements
term:
  timezone: America/Chicago
  first_day: 2026-09-01
  last_day: 2026-12-15
announcements:
  - id: welcome
    title: Welcome to the course
    body: welcome.html
    post: immediately
  - id: week-2
    title: Week 2 begins
    body: week-2.html
    post: 2026-09-08
```

`tests/testthat/fixtures/minimal-course/content/announcements/welcome.html`:

```html
<h2>Welcome to the course</h2>
<p>Read the syllabus before the first meeting.</p>
```

`tests/testthat/fixtures/minimal-course/content/announcements/week-2.html`:

```html
<h2>Week 2 begins</h2>
<p>Module 2 opens today. Its work is due at the end of next week.</p>
```

`tests/testthat/fixtures/minimal-course/content/canvas/chapter-one.html`:

```html
<h3>Objectives</h3>
<ul><li>State what the chapter is about.</li></ul>
<p><a href="https://example.invalid/book/ch01.html">Read the chapter</a>.</p>
```

`tests/testthat/fixtures/minimal-course/assessments/quizzes/quiz01.md`:

```markdown
# 1. Instructions

Answer every question in a few sentences.

# 2. Questions

1. What does the figure show? ![figure](../../assets/quiz/fig.png)
2. Name one limitation of the method.

# 3. ANSWER KEY

CANARY_ANSWER_KEY_MUST_NEVER_BE_PUBLIC

1. It shows the trend.
```

`tests/testthat/fixtures/minimal-course/assessments/README.md`: one line, `Never rendered, never in the cartridge as source.`

`tests/testthat/fixtures/fake-textbook/docs/ch01.html` (Quarto-shaped, with a walkthrough subsection that must be dropped and a bold-only paragraph that must become a heading):

```html
<!DOCTYPE html><html><head><title>Chapter One</title></head><body>
<main>
<section id="sec-intro" class="level2">
<h2 class="anchored" data-anchor-id="sec-intro">Introduction<a class="anchorjs-link " href="#sec-intro"></a></h2>
<p>Text.</p>
</section>
<section id="homework-assignment" class="level2">
<h2 class="anchored" data-anchor-id="homework-assignment">Homework</h2>
<section id="objective" class="level3">
<h3 class="anchored">Objective</h3>
<p>Estimate the relationship.</p>
</section>
<section id="the-data" class="level3">
<h3 class="anchored">The Data</h3>
<section id="step-1" class="level4">
<h4>Step 1</h4>
<pre><code>x &lt;- 1</code></pre>
</section>
</section>
<section id="instructions" class="level3">
<h3 class="anchored">Instructions</h3>
<p><strong>1. Write your specification first</strong></p>
<p>Download <a href="data/example.csv">https://example.invalid/book/data/example.csv</a> and <img src="img/plot.png" alt="a plot"> read it.</p>
</section>
</section>
</main></body></html>
```

`tests/testthat/fixtures/fake-textbook/docs/ch02.html`:

```html
<!DOCTYPE html><html><head><title>Chapter Two</title></head><body>
<section id="sec-two" class="level2"><h2>Two</h2><p>Text.</p></section>
</body></html>
```

`tests/testthat/fixtures/qti-sample/quiz-sample/assessment_meta.xml` and `quiz-sample.xml` reproduce the R/exams shape the builder's rewrite expects: an assessment with `ident="quiz-sample_123456789"`, a meta with `<quiz identifier="quiz-sample_987654321">`, an `<assignment identifier="AID_quiz-sample_987654321">`, `<assignment_group_identifierref>GID_quiz-sample_987654321</assignment_group_identifierref>`, `<available>false</available>`, `<title>quiz-sample</title>`, and two items `ident="quiz-sample_123456789_section_1_item_01_num"` and `_02_num` each with a `<response_num>` and a `<varequal>`. Write them by hand from that description; they are 30 and 60 lines. The item idents must share the base `quiz-sample` and differ after it, so the prefix rewrite and the distinct-idents check both have work to do. Add a `<!DOCTYPE questestinterop>` line to `quiz-sample.xml`, because the builder strips it.

`pair/`: three `site/index.html` files each containing `<html lang="en"><title>p</title><body>p</body></html>`.

- [ ] **Step 3: Write the fixture tests**

```r
# tests/testthat/test-fixtures.R
test_that("the fixture course parses and reaches every item form", {
  p <- copy_course()
  m <- read_manifest(p)
  forms <- unlist(lapply(m$mods$modules, function(mod) vapply(mod$items, function(it)
    intersect(c("header", "page", "link", "assignment", "quiz"), names(it))[1], "")))
  expect_setequal(unique(forms), c("header", "page", "link", "assignment", "quiz"))
  expect_true(isTRUE(m$pages[["chapter-one"]]$body))
  expect_true(!is.null(m$assignments[["quiz-1"]]$quiz_file))
  expect_true(!is.null(m$assignments[["todo-1"]]$todo))
  expect_equal(read_timezone(m$course), "America/Chicago")
  expect_true(dir.exists(textbook_docs_path(m$course, p)))
})

test_that("no course fact leaked into the fixtures", {
  hits <- suppressWarnings(system2("grep", c("-rniE", shQuote("econ ?[0-9]|uwrf|kelly|ljkelly|managerial|macro_principles"),
                            shQuote(fixture_path())), stdout = TRUE, stderr = FALSE))
  expect_length(hits, 0)
})

test_that("the sample QTI zips and holds exactly two distinct item idents sharing the base", {
  skip_if_no("zip")
  p <- copy_course()
  z <- zip_fixture_qti(p)
  expect_true(file.exists(z))
  files <- utils::unzip(z, list = TRUE)$Name
  expect_true(any(grepl("assessment_meta\\.xml$", files)))
  d <- withr::local_tempdir(); utils::unzip(z, exdir = d)
  ass <- setdiff(list.files(d, "\\.xml$", recursive = TRUE, full.names = TRUE),
                 list.files(d, "assessment_meta\\.xml$", recursive = TRUE, full.names = TRUE))
  expect_length(ass, 1L)
  x <- paste(readLines(ass), collapse = "\n")
  idents <- regmatches(x, gregexpr('<item ident="[^"]*"', x))[[1]]
  expect_length(idents, 2L); expect_length(unique(idents), 2L)
  expect_true(all(grepl('ident="quiz-sample_[0-9]+_section_1_item_0[12]_num"', idents)))
  expect_match(x, "<!DOCTYPE")
})
```

- [ ] **Step 4: Run**

Run: `Rscript -e 'testthat::test_local(filter = "fixtures")'`
Expected: 3 pass. The fixture files carry no version bump; add NEWS line "Synthetic fixture course, fake textbook, sample QTI, and the skip helpers."

- [ ] **Step 5: Propose the commit and stop**

```
Add the synthetic fixture course and the test helpers
```

---

### Task 5: The byte gate and the baseline tool

**Files:**
- Create: `R/gate.R`, `tools/baseline.R`, `tests/testthat/test-gate.R`, `tests/testthat/test-cartridge-gate.R`, `tests/testthat/fixtures/minimal-course-expected-tree.txt` (generated by running the tool)

**Interfaces:**
- Consumes: the fixture (Task 4), `%||%`.
- Produces:
  - `normalize_manifest_date(text)`: replaces the one `<lomimscc:dateTime>...</lomimscc:dateTime>` with `<lomimscc:dateTime>DATE</lomimscc:dateTime>`.
  - `tree_hashes(dir)`: character vector `"<32 hex> <relative path>"`, sorted by path, `imsmanifest.xml` hashed after normalization, every other file hashed as bytes.
  - `write_expected_tree(dir, path)`: writes `tree_hashes(dir)` one per line.
  - `gate_check(dir, expected)`: compares; returns `invisible(list(missing, extra, changed))`; stops with a readable diff when any is non-empty. Exported, because the ECON 730 hand-off uses it against the real course (Appendix A).
  - `tools/baseline.R`: `Rscript tools/baseline.R script <fixture-course> <out-file>` builds the fixture with the frozen snapshot builder; `Rscript tools/baseline.R package <fixture-course> <out-file>` builds it with the installed package (used only for deliberate regenerations in Phase 2).

- [ ] **Step 1: Write the failing gate tests**

```r
# tests/testthat/test-gate.R
test_that("normalize_manifest_date pins the one dated line", {
  x <- "<a>\n            <lomimscc:dateTime>2026-09-04</lomimscc:dateTime>\n</a>"
  expect_equal(normalize_manifest_date(x),
               "<a>\n            <lomimscc:dateTime>DATE</lomimscc:dateTime>\n</a>")
  expect_equal(normalize_manifest_date("<b/>"), "<b/>")
})

test_that("tree_hashes is stable across the manifest date and sorted by path", {
  d <- withr::local_tempdir()
  dir.create(file.path(d, "sub"))
  writeLines("<lomimscc:dateTime>2026-01-01</lomimscc:dateTime>", file.path(d, "imsmanifest.xml"))
  writeLines("b", file.path(d, "sub", "b.txt")); writeLines("a", file.path(d, "a.txt"))
  h1 <- tree_hashes(d)
  writeLines("<lomimscc:dateTime>2027-05-05</lomimscc:dateTime>", file.path(d, "imsmanifest.xml"))
  expect_identical(tree_hashes(d), h1)
  expect_equal(sub("^[0-9a-f]{32} ", "", h1), c("a.txt", "imsmanifest.xml", "sub/b.txt"))
  expect_true(all(grepl("^[0-9a-f]{32} ", h1)))
})

test_that("gate_check names missing, extra and changed files, and passes on identity", {
  d <- withr::local_tempdir(); writeLines("x", file.path(d, "x.txt"))
  # The expected tree is written OUTSIDE the tree it describes, as the real
  # one is (tests/testthat/fixtures/, not the staging directory).
  exp <- tempfile(fileext = ".txt"); write_expected_tree(d, exp)
  expect_no_error(gate_check(d, exp))
  writeLines("stray", file.path(d, "extra.txt"))
  expect_error(gate_check(d, exp), "extra: extra.txt")
  unlink(file.path(d, "extra.txt"))
  writeLines("y", file.path(d, "x.txt"))
  expect_error(gate_check(d, exp), "changed: x.txt")
  unlink(file.path(d, "x.txt"))
  expect_error(gate_check(d, exp), "missing: x.txt")
})
```

- [ ] **Step 2: Write the cartridge gate test, skipping until Task 10**

```r
# tests/testthat/test-cartridge-gate.R
test_that("the package builds the fixture into the frozen builder's tree", {
  skip_if_no("zip"); skip_if_no("pandoc")
  skip_if(!exists("build_cartridge"), "build_cartridge has not moved into the package yet")
  p <- copy_course(); zip_fixture_qti(p)
  build_cartridge(p)
  gate_check(file.path(p, "build", "coursepack", "staging"),
             fixture_path("minimal-course-expected-tree.txt"))
})
```

- [ ] **Step 3: Run to verify failure**

Run: `Rscript -e 'testthat::test_local(filter = "gate")'`
Expected: `test-gate.R` FAILs on `normalize_manifest_date` not found; `test-cartridge-gate.R` shows 1 skip.

- [ ] **Step 4: Write `R/gate.R`**

```r
#' The byte gate
#'
#' A cartridge's staging tree, hashed file by file. `imsmanifest.xml` embeds
#' the build date, so that one line is normalized before hashing (spec 2f);
#' everything else is hashed as bytes. The gate compares two such listings and
#' refuses on any difference. Never regenerate an expected tree to make a
#' failing gate pass: a regeneration is a declaration that the cartridge was
#' supposed to change.
#' @param dir A staging directory.
#' @param path,expected A file of `<md5> <path>` lines.
#' @name gate
NULL

normalize_manifest_date <- function(text) {
  sub("<lomimscc:dateTime>[^<]*</lomimscc:dateTime>",
      "<lomimscc:dateTime>DATE</lomimscc:dateTime>", text)
}

#' @rdname gate
#' @export
tree_hashes <- function(dir) {
  files <- sort(list.files(dir, recursive = TRUE, all.files = TRUE, no.. = TRUE))
  vapply(files, function(f) {
    full <- file.path(dir, f)
    h <- if (identical(basename(f), "imsmanifest.xml")) {
      txt <- paste(readLines(full, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
      digest::digest(normalize_manifest_date(txt), algo = "md5", serialize = FALSE)
    } else unname(tools::md5sum(full))
    paste(h, f)
  }, "", USE.NAMES = FALSE)
}

#' @rdname gate
#' @export
write_expected_tree <- function(dir, path) {
  writeLines(tree_hashes(dir), path)
  invisible(path)
}

#' @rdname gate
#' @export
gate_check <- function(dir, expected) {
  want <- readLines(expected, warn = FALSE)
  got <- tree_hashes(dir)
  split2 <- function(v) {
    p <- sub("^[0-9a-f]{32} ", "", v); h <- substr(v, 1, 32); setNames(h, p)
  }
  w <- split2(want); g <- split2(got)
  missing <- setdiff(names(w), names(g)); extra <- setdiff(names(g), names(w))
  common <- intersect(names(w), names(g))
  changed <- common[w[common] != g[common]]
  res <- list(missing = missing, extra = extra, changed = changed)
  if (length(missing) || length(extra) || length(changed)) {
    stop("GATE FAILED against ", expected, "\n",
         paste0(c(paste0("  missing: ", missing), paste0("  extra: ", extra),
                  paste0("  changed: ", changed)), collapse = "\n"),
         "\nRead the diff before touching anything. A regeneration is a deliberate output change.",
         call. = FALSE)
  }
  invisible(res)
}
```

- [ ] **Step 5: Write `tools/baseline.R`**

```r
#!/usr/bin/env Rscript
# Build a fixture course with the FROZEN snapshot builder and write its hashed
# staging tree. This is the only legitimate way the first expected tree is
# produced. Usage:
#   Rscript tools/baseline.R script  <fixture-course> <out-file>
#   Rscript tools/baseline.R package <fixture-course> <out-file>
# `script` copies the fixture and its sibling fake-textbook into a scratch
# directory, copies project/econ730-toolchain/scripts/{build_cartridge.R,lib/}
# beside it (the frozen script sources lib/ via PROJ), zips the sample QTI,
# and runs the script with PROJ set. That is the last legitimate use of PROJ.
# `package` builds with the installed package, for deliberate regenerations.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) stop("usage: baseline.R script|package <fixture-course> <out-file>")
mode <- args[1]; fixture <- normalizePath(args[2]); out <- args[3]
source("R/utils.R"); source("R/gate.R")

scratch <- tempfile("baseline-"); dir.create(scratch)
file.copy(fixture, scratch, recursive = TRUE)
file.copy(file.path(dirname(fixture), "fake-textbook"), scratch, recursive = TRUE)
proj <- file.path(scratch, basename(fixture))

qti_src <- file.path(dirname(fixture), "qti-sample", "quiz-sample")
dir.create(file.path(proj, "build", "qti"), recursive = TRUE)
old <- setwd(dirname(qti_src))
utils::zip(file.path(proj, "build", "qti", "quiz-sample.zip"),
           list.files(basename(qti_src), recursive = TRUE, full.names = TRUE), flags = "-q -X")
setwd(old)

if (mode == "script") {
  snap <- "project/econ730-toolchain/scripts"
  dir.create(file.path(proj, "scripts", "lib"), recursive = TRUE)
  file.copy(file.path(snap, "build_cartridge.R"), file.path(proj, "scripts"))
  file.copy(list.files(file.path(snap, "lib"), full.names = TRUE), file.path(proj, "scripts", "lib"))
  # PROJ only. Do NOT export TEXTBOOK_DOCS, even empty: the frozen script reads
  # Sys.getenv("TEXTBOOK_DOCS", default) at its line 507, and an empty string
  # defeats the default, which is exactly the make-export trap the gotchas record.
  status <- system2("Rscript", file.path(proj, "scripts", "build_cartridge.R"),
                    env = paste0("PROJ=", proj))
  if (status != 0) stop("the frozen builder failed; fix the fixture, not the builder")
} else if (mode == "package") {
  coursepack::build_cartridge(proj)
} else stop("mode must be script or package")

stage <- file.path(proj, "build", "coursepack", "staging")
write_expected_tree(stage, out)
cat(length(readLines(out)), "files hashed into", out, "\n")
```

- [ ] **Step 6: Generate the expected tree, once**

```bash
Rscript -e 'roxygen2::roxygenise()'
Rscript tools/baseline.R script tests/testthat/fixtures/minimal-course tests/testthat/fixtures/minimal-course-expected-tree.txt
```
Expected: the frozen builder prints its pre-zip validation lines and `=== built ===`; the tool prints a file count (about 25: course_settings 7, module_meta, weblinks 3, wiki pages 2, assignments 3 x 2, quiz 3, announcements 4, manifest). Open the file: every line reads `<32 hex> <path>`. If the frozen builder stops, the fixture is wrong (a missing body, a bad anchor); fix the fixture and rerun. Never edit the snapshot script.

- [ ] **Step 7: Test**

Run: `Rscript -e 'testthat::test_local()'`
Expected: `gate` 3 pass; `cartridge-gate` 1 skip with the reason text; everything else green. Bump `Version: 0.0.0.9004`; NEWS: "The byte gate: `gate_check()`, `tree_hashes()`; `tools/baseline.R`; the first expected tree from the frozen builder."

- [ ] **Step 8: Propose the commit and stop**

```
Add the byte gate and freeze the fixture's expected tree from the snapshot builder
```

# Phase 1: The ECON 730 chain, as a pure move

Every task in this phase moves code from `project/econ730-toolchain/scripts/` with only the edits it names. The byte gate (Task 5) is the proof that nothing else changed. If the gate fails in Task 10, read the diff; a genuine mismatch is a bug in the move or a bug in the old generator, and the second is a finding for Logan, never a reason to regenerate.

### Task 6: Move the resolution helpers

**Files:**
- Create: `R/resolve.R`, `tests/testthat/test-resolve.R`
- Source: `project/econ730-toolchain/scripts/lib/resolve.R` lines 24 to 71 (four functions; `getenv_or()` at 19 to 22 is not carried)

**Interfaces:**
- Produces, exported: `interp_urls(s, urls)`, `chapter_url(chapter, anchor, base)`, `resolve_target(chapter, anchor, tb_docs)` returning `list(state, detail)` with `state` one of `"ok"`, `"missing-chapter"`, `"missing-anchor"`, `"unchecked"`, `collect_refs(mods)` returning a list of `list(ch, anc, what)`.

- [ ] **Step 1: Write the failing tests, porting every assertion of `test_resolve.R`**

```r
# tests/testthat/test-resolve.R
u <- list(textbook = "https://tb.example", site = "https://site.example", legacy = "https://old.example")

test_that("interp_urls replaces each named token and passes NULL through", {
  expect_equal(interp_urls("{textbook}/ch.html", u), "https://tb.example/ch.html")
  expect_equal(interp_urls("{legacy}/w.html", u), "https://old.example/w.html")
  expect_equal(interp_urls("{site}/x.html", u), "https://site.example/x.html")
  expect_equal(interp_urls("https://youtube/embed/1", u), "https://youtube/embed/1")
  expect_null(interp_urls(NULL, u))
})

test_that("chapter_url builds the textbook link, root for an empty chapter", {
  expect_equal(chapter_url("030_regression", NULL, "https://tb.example"), "https://tb.example/030_regression.html")
  expect_equal(chapter_url("030_regression", "homework", "https://tb.example"), "https://tb.example/030_regression.html#homework")
  expect_equal(chapter_url(NULL, NULL, "https://tb.example"), "https://tb.example/")
  expect_equal(chapter_url("", NULL, "https://tb.example"), "https://tb.example/")
})

test_that("resolve_target reports the four states, and empty chapter is unchecked even with a real dir", {
  tmp <- withr::local_tempdir()
  writeLines('<h2 id="homework-assignment">HW</h2>', file.path(tmp, "030_regression.html"))
  expect_equal(resolve_target("030_regression", "homework-assignment", tmp)$state, "ok")
  expect_equal(resolve_target("030_regression", "nope", tmp)$state, "missing-anchor")
  expect_equal(resolve_target("999_nope", NULL, tmp)$state, "missing-chapter")
  expect_equal(resolve_target("030_regression", NULL, tmp)$state, "ok")
  expect_equal(resolve_target("030_regression", NULL, "/definitely/not/here")$state, "unchecked")
  # Regression: the fail-open scar. An empty chapter with a real textbook dir
  # must come back unchecked, not silently resolved.
  expect_equal(resolve_target("", NULL, tmp)$state, "unchecked")
})

test_that("collect_refs includes chapter items and homework chapters, excludes the empty root link", {
  mods_t <- list(
    modules = list(list(items = list(
      list(chapter = "010_intro-R", anchor = NULL, link = "Reading: Chapter 1"),
      list(chapter = "", anchor = NULL, link = "Textbook root")))),
    assignments = list(list(id = "homework-1",
      homework = list(chapter = "015_case-first_look", anchor = "homework-assignment")))
  )
  refs <- collect_refs(mods_t)
  expect_length(refs, 2L)
  expect_length(Filter(function(r) identical(r$ch, "010_intro-R"), refs), 1L)
  expect_length(Filter(function(r) identical(r$ch, ""), refs), 0L)
  expect_length(Filter(function(r) identical(r$ch, "015_case-first_look"), refs), 1L)
})
```

- [ ] **Step 2: Run to verify failure**

Run: `Rscript -e 'testthat::test_local(filter = "resolve")'`
Expected: FAIL, `could not find function "interp_urls"`.

- [ ] **Step 3: Move the four functions**

Copy snapshot lines 24 to 71 into `R/resolve.R` verbatim, then: delete nothing inside the bodies; prepend one roxygen block per function with `@export`; replace the header comment's sentence "Sourced by scripts/check_manifests.R and scripts/build_preview.R" with "Used by `check_manifests()`, `build_preview()` and `build_cartridge()`"; replace the comment "Mirrors the link URL construction in build_cartridge.R:103-106" with "Mirrors `url_for()` in `R/cartridge-items.R`". The roxygen for `resolve_target()` documents the four states and the two-scar rule from the test.

- [ ] **Step 4: Document, test, bump**

```bash
Rscript -e 'roxygen2::roxygenise()'
Rscript -e 'testthat::test_local(filter = "resolve")'
```
Expected: 4 tests, 18 expectations pass. `Version: 0.0.0.9005`; NEWS: "`interp_urls()`, `chapter_url()`, `resolve_target()`, `collect_refs()` moved from `scripts/lib/resolve.R`."

- [ ] **Step 5: Propose the commit and stop**

```
Move the resolution helpers into the package
```

---

### Task 7: Move the body helpers

**Files:**
- Create: `R/body-homework.R`, `R/body-quiz.R`, `tests/testthat/test-body.R`
- Source: `lib/homework_body.R` (whole file), `lib/quiz_body.R` (whole file)

**Interfaces:**
- Produces, exported: `homework_section_html(chapter, anchor, tb_docs, tb_base, id = chapter)`; `quiz_student_md(path, id = basename(path))`; `quiz_student_html(path, id = basename(path), site_base = NULL)`. Package constants, documented in `R/body-quiz.R` as the convention a course must follow (not yet configurable, recorded in NEWS): `LEAK_CANARY <- "CANARY_ANSWER_KEY_MUST_NEVER_BE_PUBLIC"` and `ANSWER_KEY_HEADING_RE <- "^#+\\s*3\\.\\s*ANSWER\\s*KEY"`. `QUIZ_CANARY` in the source becomes `LEAK_CANARY`; the pre-zip scan (Task 10) uses the same constant instead of its own literal.

- [ ] **Step 1: Write the failing tests**

```r
# tests/testthat/test-body.R
tb <- function() fixture_path("fake-textbook", "docs")

test_that("homework_section_html keeps the instruction subsections and drops the walkthrough", {
  h <- homework_section_html("ch01", "homework-assignment", tb(), "https://example.invalid/book", "hw-1")
  expect_match(h, "Objective"); expect_match(h, "Instructions")
  expect_no_match(h, "The Data"); expect_no_match(h, "Step 1")
})

test_that("heading levels normalise to h2, a bold-only paragraph becomes h3, links and images go absolute", {
  h <- homework_section_html("ch01", "homework-assignment", tb(), "https://example.invalid/book/", "hw-1")
  expect_match(h, "<h2[ >]"); expect_no_match(h, "<h3 class=\"anchored\">Objective")
  expect_match(h, "<h3>1\\. Write your specification first</h3>")
  expect_match(h, 'href="https://example.invalid/book/data/example.csv"[^>]*>example.csv</a>')
  expect_match(h, 'src="https://example.invalid/book/img/plot.png"')
  expect_no_match(h, "anchorjs-link")
})

test_that("homework_section_html refuses a missing chapter, a missing anchor, and an anchor with no instruction subsections", {
  expect_error(homework_section_html("nope", "x", tb(), "https://b", "a"), "not rendered")
  expect_error(homework_section_html("ch01", "no-such-anchor", tb(), "https://b", "a"), "not found")
  expect_error(homework_section_html("ch02", "sec-two", tb(), "https://b", "a"), "Refusing to build")
})

test_that("quiz_student_md truncates at the answer key and never returns the canary", {
  q <- fixture_path("minimal-course", "assessments", "quizzes", "quiz01.md")
  kept <- quiz_student_md(q, "quiz-1")
  expect_true(any(grepl("^# 2\\. Questions", kept)))
  expect_false(any(grepl("ANSWER KEY", kept)))
  expect_false(any(grepl(LEAK_CANARY, kept, fixed = TRUE)))
})

test_that("a quiz without an answer-key heading, or with the canary above it, stops", {
  d <- withr::local_tempdir()
  writeLines(c("# 1. Instructions", "text"), file.path(d, "nokey.md"))
  expect_error(quiz_student_md(file.path(d, "nokey.md"), "a"), "no ANSWER KEY heading")
  writeLines(c("# 1. Instructions", LEAK_CANARY, "# 3. ANSWER KEY"), file.path(d, "leak.md"))
  expect_error(quiz_student_md(file.path(d, "leak.md"), "a"), "leak canary survived")
  expect_error(quiz_student_md(file.path(d, "absent.md"), "a"), "does not exist")
})

test_that("quiz_student_html rewrites relative asset paths to the site and refuses one that survives", {
  skip_if_no("pandoc")
  q <- fixture_path("minimal-course", "assessments", "quizzes", "quiz01.md")
  h <- quiz_student_html(q, "quiz-1", "https://example.invalid/course")
  expect_match(h, 'src="https://example.invalid/course/assets/quiz/fig.png"')
  expect_error(quiz_student_html(q, "quiz-1", NULL), "relative asset path survived")
})
```

- [ ] **Step 2: Run to verify failure**

Run: `Rscript -e 'testthat::test_local(filter = "body")'`
Expected: FAIL, `could not find function "homework_section_html"`.

- [ ] **Step 3: Move the two files**

`R/body-homework.R`: the whole of `lib/homework_body.R`, header comment kept in full (it is the record of why the cost is accepted), with a roxygen block above the function carrying `@export` and the two sentences "Reads the rendered textbook, never the .qmd" and "Refuses rather than falling back to the whole case study". Change the comment "build_cartridge.R inlines this ... build_preview.R shows" to name `build_cartridge()` and `build_preview()`.

`R/body-quiz.R`: the whole of `lib/quiz_body.R`. Rename `QUIZ_CANARY` to `LEAK_CANARY` (two occurrences), add `ANSWER_KEY_HEADING_RE` and use it in the `grep()` at the cut line, keep the three-guards comment verbatim, roxygen with `@export` on both functions. Above the constants:

```r
# The answer-key convention a course must follow today: the heading that ends
# the student-facing part matches ANSWER_KEY_HEADING_RE, and LEAK_CANARY is the
# string a course plants inside its keys so a leak is detectable as bytes.
# Making both configurable per course is recorded in NEWS as not yet done.
LEAK_CANARY <- "CANARY_ANSWER_KEY_MUST_NEVER_BE_PUBLIC"
ANSWER_KEY_HEADING_RE <- "^#+\\s*3\\.\\s*ANSWER\\s*KEY"
```

- [ ] **Step 4: Document, test, bump**

```bash
Rscript -e 'roxygen2::roxygenise()'
Rscript -e 'testthat::test_local(filter = "body")'
```
Expected: 6 tests pass (the pandoc one may skip on a machine without pandoc). `Version: 0.0.0.9006`; NEWS: "Body helpers moved; `LEAK_CANARY` and `ANSWER_KEY_HEADING_RE` are package constants and not yet configurable."

- [ ] **Step 5: Propose the commit and stop**

```
Move the homework and quiz body helpers, with their three guards
```

---

### Task 8: Move the manifest checker; introduce `reference.yml`

**Files:**
- Create: `R/manifests.R`, `tests/testthat/test-manifests.R`
- Source: `check_manifests.R` (whole file)

**Interfaces:**
- Consumes: `read_manifest()`, `read_reference()`, `textbook_docs_path()`, `resolve_target()`, `collect_refs()`, `proj_path()`.
- Produces, exported: `check_manifests(proj = ".", textbook_docs = NULL)` returning `invisible(list(fails = character(), skipped = character()))`, stopping with every failure listed when `fails` is non-empty, printing every skip in the closing summary followed by the version line. Behaviour changes from the script, each deliberate: the literal `9`, `73` and the expect vector become `reference.yml`'s optional `counts:` block (`modules`, `items`, `header`, `page`, `link`, `assignment`, `quiz`), and a count mismatch is a **failure** when `counts:` is present (spec 1c, adopting the recommendation); when `reference.yml` or its `counts:` is absent, the counts are printed and the skip is reported. New check: every `group:` named by an assignment or by `assignment_defaults$group` must exist in `course$assignment_groups` (portable plan T08). `textbook_docs = NULL` means read `course.yml`; `none` skips loudly.

- [ ] **Step 1: Write the failing tests**

```r
# tests/testthat/test-manifests.R
# Every test that expects a pass needs the sample QTI zip in place, because the
# checker fails on a missing zip before anything else is judged.
ready <- function() {
  skip_if_no("zip")
  to <- withr::local_tempdir(.local_envir = parent.frame())   # bind the tempdir to the TEST, not to this helper
  p <- copy_course(to = to)
  zip_fixture_qti(p)
  p
}

test_that("the fixture course passes, reporting the textbook skip when docs are absent", {
  p <- ready()
  res <- check_manifests(p)
  expect_length(res$fails, 0)
  expect_true(any(grepl("counts", res$skipped)))       # no reference.yml -> counts skipped, loudly
  unlink(file.path(dirname(p), "fake-textbook"), recursive = TRUE)
  res2 <- check_manifests(p)
  expect_true(any(grepl("textbook docs not found", res2$skipped)))
})

test_that("counts in reference.yml are fatal when they disagree", {
  p <- ready()
  writeLines(c("counts:", "  modules: 2", "  items: 12", "  header: 2", "  page: 2", "  link: 4",
               "  assignment: 3", "  quiz: 1"), file.path(p, "reference.yml"))
  expect_no_error(check_manifests(p))
  writeLines(c("counts:", "  modules: 9"), file.path(p, "reference.yml"))
  expect_error(check_manifests(p), "modules: 2 vs 9")
})

test_that("referential integrity: undefined and orphan definitions fail", {
  p <- copy_course()
  y <- readLines(file.path(p, "modules.yml"))
  writeLines(sub("- page: welcome", "- page: nowhere", y), file.path(p, "modules.yml"))
  expect_error(check_manifests(p), "page slug not defined: nowhere")
  expect_error(check_manifests(p), "orphan pages: welcome")
})

test_that("a broken anchor fails when the textbook is present and is a manifest defect when empty", {
  p <- copy_course()
  y <- readLines(file.path(p, "modules.yml"))
  writeLines(sub("anchor: sec-intro", "anchor: sec-missing", y), file.path(p, "modules.yml"))
  expect_error(check_manifests(p), "anchor missing: ch01#sec-missing")
})

test_that("todo plus published is a violation; a missing QTI zip fails before build time", {
  p <- copy_course()
  y <- readLines(file.path(p, "modules.yml"))
  y <- sub("    todo: \"write this once the chapter exists\"", "    todo: x", y)
  i <- grep("id: todo-1", y); y[i + 2] <- "    published: true"
  writeLines(y, file.path(p, "modules.yml"))
  expect_error(check_manifests(p), "VIOLATION: todo-1 has todo AND published: true")
  p2 <- copy_course()
  expect_error(check_manifests(p2), "quiz 'q-sample' QTI zip missing")
})

test_that("an assignment group that is not declared fails", {
  p <- ready()
  c1 <- readLines(file.path(p, "course.yml"))
  writeLines(sub("  group: Assignments", "  group: Homework", c1), file.path(p, "course.yml"))
  expect_error(check_manifests(p), "assignment_defaults.group 'Homework' is not a declared assignment group")
})

test_that("textbook_docs: none skips the target checks loudly", {
  p <- ready()
  c1 <- readLines(file.path(p, "course.yml"))
  writeLines(sub("textbook_docs: .*", "textbook_docs: none", c1), file.path(p, "course.yml"))
  res <- check_manifests(p)
  expect_true(any(grepl("textbook_docs: none", res$skipped)))
})
```

- [ ] **Step 2: Run to verify failure**

Run: `Rscript -e 'testthat::test_local(filter = "manifests")'`
Expected: FAIL, `could not find function "check_manifests"`.

- [ ] **Step 3: Write `R/manifests.R`**

Port `check_manifests.R` into one function. The always-run half (referential integrity, item-form validation, textbook target checks with the `unchecked`-is-a-failure asymmetry when the directory exists, the todo/published rule, the QTI zip presence check) keeps its semantics and its printed lines. The changed parts:

```r
#' Validate course.yml and modules.yml before anything generates a cartridge
#'
#' Referential integrity (every slug and id defined and used), item-form
#' validation, textbook target resolution against the rendered textbook, the
#' todo/published rule, and the assignment-group check. Structural counts are
#' compared against `reference.yml`'s `counts:` block and are fatal when it is
#' present; absent, they are printed and the skip is reported, never hidden.
#' @param proj Course project root.
#' @param textbook_docs Override for `course.yml`'s `textbook_docs:`; `NULL` reads it.
#' @return `invisible(list(fails, skipped))`. Stops when `fails` is non-empty.
#' @export
check_manifests <- function(proj = ".", textbook_docs = NULL) {
  m <- read_manifest(proj); course <- m$course; mods <- m$mods
  pages <- m$pages; asg <- m$assignments; quiz <- m$quizzes
  fails <- character(); skipped <- character()
  fail <- function(...) fails <<- c(fails, paste0(...))
  skip <- function(...) { skipped <<- c(skipped, paste0(...)); cat("  SKIPPED: ", paste0(...), "\n", sep = "") }
  tb_docs <- if (!is.null(textbook_docs)) textbook_docs else textbook_docs_path(course, proj)

  cat("both files parse as YAML: OK\n\n")
  # ---- 1. structure ------------------------------------------------------
  forms <- c("header", "page", "link", "assignment", "quiz")
  counts <- setNames(integer(length(forms)), forms); n_items <- 0L
  for (mm in mods$modules) for (it in mm$items) {
    n_items <- n_items + 1L
    k <- forms[forms %in% names(it)]
    if (length(k) != 1L) fail("item has ", length(k), " type keys: ", paste(names(it), collapse = ","))
    else counts[k] <- counts[k] + 1L
  }
  ref <- read_reference(proj)
  cat(sprintf("modules: %d   items: %d\n", length(mods$modules), n_items))
  for (k in forms) cat(sprintf("  %-11s %2d\n", k, counts[k]))
  if (is.null(ref$counts)) skip("counts: no reference.yml counts block; structural counts not enforced")
  else {
    want <- ref$counts
    chk <- function(label, got) if (!is.null(want[[label]]) && got != want[[label]])
      fail("count mismatch, ", label, ": ", got, " vs ", want[[label]], " in reference.yml")
    chk("modules", length(mods$modules)); chk("items", n_items)
    for (k in forms) chk(k, unname(counts[k]))
  }
  # ---- 2. referential integrity: verbatim from the script ----------------
  # (used_p / used_a / used_q loops, orphan checks, the QTI zip presence check;
  #  note the script's `used_q <<-` is a plain `<-` inside this function)
  # ---- 2b. assignment groups ---------------------------------------------
  groups <- vapply(course$assignment_groups %||% list(), function(g) as.character(g$name), "")
  dg <- course$assignment_defaults$group
  if (!is.null(dg) && !dg %in% groups)
    fail("assignment_defaults.group '", dg, "' is not a declared assignment group (", paste(groups, collapse = ", "), ")")
  for (k in names(asg)) if (!is.null(asg[[k]]$group) && !asg[[k]]$group %in% groups)
    fail("assignment '", k, "' names group '", asg[[k]]$group, "', which is not declared")
  # ---- 3. textbook targets: verbatim, with the none case -----------------
  cat("\n=== textbook targets ===\n")
  refs <- collect_refs(mods)
  if (is.null(tb_docs)) skip("textbook_docs: none, so ", length(refs), " chapter/anchor targets are not checked")
  else if (!dir.exists(tb_docs)) skip("textbook docs not found at ", tb_docs)
  else { # the script's loop, including the unchecked-is-a-failure rule
  }
  # ---- the safety rule: verbatim -----------------------------------------
  # ---- verdict -----------------------------------------------------------
  cat("\n")
  if (length(fails)) {
    cat("FAILURES (", length(fails), "):\n", sep = ""); for (f in fails) cat("  ! ", f, "\n", sep = "")
    stop(length(fails), " manifest check(s) failed:\n  ", paste(fails, collapse = "\n  "), call. = FALSE)
  }
  if (length(skipped)) cat("skipped (", length(skipped), "): ", paste(skipped, collapse = "; "), "\n", sep = "")
  cat("All checks passed.\n"); version_line("check_manifests")
  invisible(list(fails = fails, skipped = skipped))
}
```

Fill the three "verbatim" regions with the script's code (lines 66 to 94, 111 to 137, 139 to 149), changing `quit(status = 1)` to the `stop()` above and `used_q <<-` to `used_q <-`.

- [ ] **Step 4: Document, test, bump**

```bash
Rscript -e 'roxygen2::roxygenise()'
Rscript -e 'testthat::test_local(filter = "manifests")'
```
Expected: 7 tests pass. `Version: 0.0.0.9007`; NEWS: "`check_manifests()`; counts come from `reference.yml` and are fatal when declared; new assignment-group check."

- [ ] **Step 5: Propose the commit and stop**

```
Move the manifest checker; counts move to reference.yml and become fatal when declared
```

---

### Task 9: Move the reference diff

**Files:**
- Create: `R/refdiff.R`, `tests/testthat/test-refdiff.R`, `tests/testthat/helper-cartridge.R`
- Source: `diff_against_reference.R` (whole file)

**Interfaces:**
- Consumes: `read_reference()`, `proj_path()`.
- Produces, exported: `diff_against_reference(proj = ".", generated = NULL)` returning `invisible(list(divergences, accounted, unexpected))`, stopping when `unexpected` is non-empty; `divergence_declared(d, declared)` returning the reason string or `NA`; `unpack_cartridge(zip)` returning a temp directory. `reference.yml` schema: `export:` (path, relative to `proj`), `divergences:` a list of `{match:, why:}`. No `reference.yml`, or one without `export:`, prints `SKIPPED: no reference export declared` and returns `invisible(list(divergences = character(0), ...))`.
- The test helper `write_mini_cartridge(dir, modules)` writes an unpacked cartridge with `course_settings/module_meta.xml`, `imsmanifest.xml` (one webcontent resource per item), and one `assignment_settings.xml`, then zips it; `modules` is a list of `list(title, items = list(list(title, ctype, indent, newtab, url)))`.

- [ ] **Step 1: Write the helper and the failing tests**

```r
# tests/testthat/helper-cartridge.R
write_mini_cartridge <- function(zip_path, modules, due = "") {
  d <- withr::local_tempdir(.local_envir = parent.frame())
  dir.create(file.path(d, "course_settings")); dir.create(file.path(d, "a1"))
  mm <- c('<?xml version="1.0" encoding="UTF-8"?>', '<modules xmlns="http://canvas.instructure.com/xsd/cccv1p0">')
  res <- character(); n <- 0L
  for (i in seq_along(modules)) {
    m <- modules[[i]]
    mm <- c(mm, sprintf('<module identifier="m%d"><title>%s</title><workflow_state>active</workflow_state><position>%d</position><require_sequential_progress>false</require_sequential_progress><items>', i, m$title, i))
    for (it in m$items) {
      n <- n + 1L
      mm <- c(mm, sprintf('<item identifier="i%d"><content_type>%s</content_type><workflow_state>active</workflow_state><title>%s</title><identifierref>r%d</identifierref>%s<position>%d</position><new_tab>%s</new_tab><indent>%s</indent></item>',
                          n, it$ctype, it$title, n, if (is.null(it$url)) "" else sprintf("<url>%s</url>", it$url), n, it$newtab %||% "false", it$indent %||% "0"))
      res <- c(res, sprintf('<resource identifier="r%d" type="%s" href="x%d.html"><file href="x%d.html"/></resource>', n,
                            if (it$ctype == "ExternalUrl") "imswl_xmlv1p1" else "webcontent", n, n))
      writeLines("x", file.path(d, sprintf("x%d.html", n)))
    }
    mm <- c(mm, "</items></module>")
  }
  writeLines(c(mm, "</modules>"), file.path(d, "course_settings", "module_meta.xml"))
  writeLines(c('<?xml version="1.0" encoding="UTF-8"?>', '<manifest xmlns="http://www.imsglobal.org/xsd/imsccv1p1/imscp_v1p1"><resources>', res, '</resources></manifest>'),
             file.path(d, "imsmanifest.xml"))
  writeLines(c('<?xml version="1.0" encoding="UTF-8"?>', '<assignment xmlns="http://canvas.instructure.com/xsd/cccv1p0"><title>HW</title>',
               sprintf('<due_at>%s</due_at>', due), '<workflow_state>published</workflow_state><points_possible>50.0</points_possible></assignment>'),
             file.path(d, "a1", "assignment_settings.xml"))
  old <- setwd(d); on.exit(setwd(old), add = TRUE)
  utils::zip(zip_path, list.files(".", recursive = TRUE), flags = "-q -X")
  zip_path
}
```

```r
# tests/testthat/test-refdiff.R
one_module <- function(extra = list()) list(list(title = "M1", items = c(list(
  list(title = "A", ctype = "WikiPage"), list(title = "B", ctype = "ExternalUrl", url = "https://example.invalid/b")), extra)))

test_that("no reference.yml means a loud skip and an empty result", {
  p <- copy_course()
  expect_output(res <- diff_against_reference(p, generated = tempfile(fileext = ".imscc")), "SKIPPED: no reference export declared")
  expect_length(res$divergences, 0)
})

test_that("an identical cartridge reports no divergence", {
  skip_if_no("zip")
  p <- copy_course(); dir.create(file.path(p, "reference"))
  ref <- write_mini_cartridge(file.path(p, "reference", "ref.imscc"), one_module())
  gen <- write_mini_cartridge(file.path(p, "gen.imscc"), one_module())
  writeLines("export: reference/ref.imscc", file.path(p, "reference.yml"))
  res <- diff_against_reference(p, gen)
  expect_length(res$divergences, 0)
})

test_that("an undeclared divergence stops; a declared one is accounted for by substring", {
  skip_if_no("zip")
  p <- copy_course(); dir.create(file.path(p, "reference"))
  write_mini_cartridge(file.path(p, "reference", "ref.imscc"), one_module())
  gen <- write_mini_cartridge(file.path(p, "gen.imscc"), one_module(list(list(title = "C", ctype = "WikiPage"))))
  writeLines("export: reference/ref.imscc", file.path(p, "reference.yml"))
  expect_error(diff_against_reference(p, gen), "UNEXPECTED divergences")
  writeLines(c("export: reference/ref.imscc", "divergences:",
               "  - match: 'items: 2 -> 3'", "    why: one page added on purpose",
               "  - match: 'WikiPage: 1 -> 2'", "    why: same page",
               "  - match: 'webcontent: 1 -> 2'", "    why: same page",
               "  - match: 'item added: WikiPage|C'", "    why: same page"), file.path(p, "reference.yml"))
  res <- diff_against_reference(p, gen)
  expect_length(res$unexpected, 0); expect_length(res$accounted, 4)
})

test_that("divergence_declared matches on substring, first hit wins", {
  decl <- list(list(match = "due_at", why = "dates set by hand"), list(match = "items: 72 -> 73", why = "added link"))
  expect_equal(divergence_declared("assignment HW due_at: x -> y", decl), "dates set by hand")
  expect_true(is.na(divergence_declared("modules: 9 -> 11", decl)))
})
```

- [ ] **Step 2: Run to verify failure**

Run: `Rscript -e 'testthat::test_local(filter = "refdiff")'`
Expected: FAIL, `could not find function "diff_against_reference"`.

- [ ] **Step 3: Write `R/refdiff.R`**

Port the script. Changes, and only these: `proj` and `generated` are arguments (`generated = NULL` means the newest `build/coursepack/*.imscc`, stopping if none); the reference path and the `EXPECTED` vector come from `reference.yml` (`export:`, `divergences:`), so the ten ECON 730 entries are **not** carried into package code (they go to the ECON 730 hand-off, Appendix A, transcribed verbatim from snapshot lines 33 to 54); `match_expected()` becomes `divergence_declared(d, declared)` with `grepl(fixed = TRUE)`, first hit wins; every `quit()` becomes a `return(invisible(...))` or a `stop()`; the `note()` closure stays. The printed sections (modules, items, item types, in-reference-only, in-generated-only, field mismatches, resource types, assignments) stay byte for byte in wording. Add `unpack_cartridge()` as the exported form of `unpack()` (a tempdir named by the zip's basename, emptied first). End with `version_line("diff_against_reference")`.

- [ ] **Step 4: Document, test, bump**

```bash
Rscript -e 'roxygen2::roxygenise()'
Rscript -e 'testthat::test_local(filter = "refdiff")'
```
Expected: 4 tests pass. `Version: 0.0.0.9008`; NEWS: "`diff_against_reference()`; the reference export and the declared divergences move to `reference.yml`."

- [ ] **Step 5: Propose the commit and stop**

```
Move the reference diff; declared divergences live in reference.yml
```

---

### Task 10: Move the cartridge builder, in one sitting

This is the task the gate exists for. It lands whole or not at all: a half-split builder that builds is the worst outcome.

**Files:**
- Create: `R/ids.R`, `R/cartridge.R`, `R/cartridge-items.R`, `R/cartridge-xml.R`, `R/cartridge-quiz.R`, `R/cartridge-announcements.R`, `R/cartridge-checks.R`, `tests/testthat/test-cartridge.R`, `tests/testthat/test-announcements.R`
- Modify: `R/config.R` (delete the temporary `slugify()`), `tests/testthat/test-cartridge-gate.R` (remove the `skip_if(!exists(...))` line)
- Source: `build_cartridge.R` 1 to 1274

**Interfaces:**
- Consumes: everything from Tasks 1 to 9.
- Produces, exported: `build_cartridge(proj = ".")` returning `invisible(list(imscc = <path>, stage = <path>))`. Internal: `gid()`, `xesc()`, `xtext()`, `oneline()`, `slugify()`, `writef()`, `XSI`, `CCV`; `resolve_items(m, ids)`; the writer functions in `cartridge-xml.R`, each taking `stage` and what it writes and returning what the manifest needs; `embed_quiz(k, q, ids, ag_id, stage, proj)`; `stage_announcements(ann, stage)` and `check_announcements(stage, ann, ann_res, p_fail)`; `prezip_checks(stage, settings_res, ann_res, p_fail)`; `zip_cartridge(stage, outfile)`. These are the one form of each signature; the move map and the body below use them unchanged.

**The move map.** The builder is organised by its own banner comments (`# ---- <name> ----`), which sit at lines 80, 131, 182, 251, 274, 347, 380, 393, 480, 625, 777, 927, 1056, 1137, and 1251 of the snapshot. Every range below runs from one banner to the line before the next, so each is a set of complete top-level expressions. Where a banner block splits across destinations, the sub-block is located by the first line of its content, quoted, never by a line number.

| Lines | Content | Destination | Edit |
|---|---|---|---|
| 1 to 63 | header: usage, identifier model, what it does not do | `R/cartridge.R` top comment, verbatim | the usage lines become `build_cartridge(proj)`; "See CLAUDE.md" becomes "See the package README" |
| 65 to 78 | `proj`, `out_root`, `stage`, `source()`, the staging purge, reading the two manifests | `build_cartridge()` body | `proj` is the argument; `out_root <- file.path(proj, "build", "coursepack")`; no `source()`; `m <- read_manifest(proj)` |
| 80 to 130 | announcements load and validate | already `read_announcements()` (Task 2) | `ann <- read_announcements(proj)` |
| 131 to 181 | helpers: `gid` through `writef`, `XSI`, `CCV`, then `url_for` | `R/ids.R` verbatim up to and including `CCV`; `url_for` (the block beginning `url_for <- function(it) {`) to `R/cartridge-items.R` | `digest::digest` fully qualified; `url_for()` takes `urls` as an argument |
| 182 to 250 | pages/asg/quiz tables, the three quiz ids, `asg_res`, `page_res`, the item walk | `R/cartridge-items.R` as `resolve_items(m)` returning `list(items, modmeta, ids = list(quiz_res, quiz_meta, quiz_aid, asg_res, asg_pos, page_res))` | none inside the loop; comments kept |
| 251 to 273 | course card | `R/cartridge-xml.R` `stage_course_card(proj, stage)` returning `list(has_tile, tile_href, tile_res)` | "Generate it with scripts/make_course_tile.R" becomes "Generate it with `course_tile()`" |
| 274 to 346 | `course_settings.xml` (from `cs <- course$canvas`), one assignment group (from `ag <- course$assignment_groups[[1]]`), grading standard (from `gs <- course$grading_standard`), late policy (from `lp <- course$late_policy`), then `files_meta.xml`, `media_tracks.xml`, `canvas_export.txt` | `write_course_settings(stage, course, tile)`; `write_assignment_groups(stage, course)` returning `ag_id`; `write_course_settings_files(stage, course)` for the rest | none in this task (Task 15 rewrites the group block; Task 16 makes two files optional) |
| 347 to 379 | `module_meta.xml` | `write_module_meta(stage, modmeta)` | none |
| 380 to 392 | weblinks | `write_weblinks(stage, items)` | none |
| 393 to 479 | wiki pages | `write_wiki_pages(stage, proj, pages, page_res, urls)` | the `stop()` for a missing body file stops naming `scripts/build_canvas_pages.R`: "the course must generate content/canvas/<slug>.html before building" |
| 480 to 624 | assignments: the two `source()` lines, `default_tb_docs` and `tb_docs`, `quiz_body`, `submit_para`, `body_for`, the assignments loop with due dates | `R/cartridge-xml.R`: `assignment_body(a, course, tb_docs)` (from `body_for <- function(a) {`) and `write_assignments(stage, asg, ids, course, tb_docs, ag_id, proj, tz)` (from `d <- course$assignment_defaults`) | the two `source()` lines go; `tb_docs` comes from `textbook_docs_path(course, proj)` (no `Sys.getenv`); `submit_para` stays as a constant named `HOMEWORK_SUBMISSION_NOTE` with a comment that Task 19 moves it to YAML; the four-line `if (due_d >= as.Date("2026-11-01")) stop(...)` goes; the `due_xml <- paste0(...)` line becomes `due_xml <- paste0("  <due_at>", local_to_utc(due_d, "23:59:00", tz), "</due_at>\n")` |
| 625 to 776 | quizzes | `R/cartridge-quiz.R` `embed_quiz(k, q, ids, ag_id, stage, proj)` | none; every comment kept |
| 777 to 926 | announcements | `R/cartridge-announcements.R` `stage_announcements(ann, stage)` returning `list(ann_res, ann_meta, ann_past)` | `ann_when()` is replaced by `parse_when(a$post, ann$tz, k)`; the window check reads `ann$first_day`, `ann$last_day` |
| 927 to 1055 | manifest | `write_manifest(stage, course, modmeta, items, ids, tile, ann_ids, m)` returning `settings_res` | none |
| 1056 to 1136 | pre-zip scan | `R/cartridge-checks.R` `prezip_checks(stage, settings_res, ann_res, p_fail)` | `canary` literal becomes `LEAK_CANARY`; `p_fail` is passed in, not `<<-` to a global |
| 1137 to 1250 | announcement read-back | `R/cartridge-announcements.R` `check_announcements(stage, ann, ann_res, p_fail)` | none |
| 1251 to 1274 | zip and closing lines | `R/cartridge.R` `zip_cartridge(stage, outfile)` | filename `sprintf("%s-%s.imscc", course_slug(course), format(Sys.Date()))`; `quit()` becomes `stop()`; closing two lines kept |

Before copying any range, confirm its first and last lines against the snapshot with `sed -n '<from>,<to>p'`: the first line is a banner or the line after one, and the last line closes a top-level expression. If a range does not, the snapshot has moved and the banner list above is re-derived with `grep -n '^# ----' project/econ730-toolchain/scripts/build_cartridge.R`.

`p_fail` becomes a local accumulator in `build_cartridge()`:

```r
problems <- character()
p_fail <- function(...) problems <<- c(problems, paste0(...))   # <<- into the build's own frame
```

and after the checks: `if (length(problems)) { cat("\nBUILD FAILED:\n"); for (p in problems) cat("  ! ", p, "\n", sep = ""); stop("BUILD FAILED: ", length(problems), " problem(s); see above", call. = FALSE) }`.

- [ ] **Step 1: Write the failing tests**

Two helpers go into `tests/testthat/helper-fixtures.R`, because later phases' test files (`test-carry.R`, `test-generate-quiz.R`) use them too:

```r
# append to tests/testthat/helper-fixtures.R
built <- function() {
  skip_if_no("zip"); skip_if_no("pandoc")
  to <- withr::local_tempdir(.local_envir = parent.frame())   # bind the tempdir to the TEST, not to this helper
  p <- copy_course(to = to); zip_fixture_qti(p)
  res <- build_cartridge(p)
  list(p = p, stage = res$stage, imscc = res$imscc,
       man = paste(readLines(file.path(res$stage, "imsmanifest.xml")), collapse = "\n"),
       mm = paste(readLines(file.path(res$stage, "course_settings", "module_meta.xml")), collapse = "\n"))
}
# Replace one literal line fragment in a fixture YAML file. `from` is matched
# fixed, so regex metacharacters in YAML need no escaping.
edit_yaml <- function(p, file, from, to) {
  y <- paste(readLines(file.path(p, file)), collapse = "\n")
  stopifnot(grepl(from, y, fixed = TRUE))
  writeLines(sub(from, to, y, fixed = TRUE), file.path(p, file))
}
```

```r
# tests/testthat/test-cartridge.R
test_that("an ExternalUrl carries two distinct ids: module_meta self-references, the manifest names the weblink", {
  b <- built()
  item_ids <- regmatches(b$mm, gregexpr('(?<=<item identifier=")[^"]+', b$mm, perl = TRUE))[[1]]
  mm_refs  <- regmatches(b$mm, gregexpr('(?<=<identifierref>)[^<]+', b$mm, perl = TRUE))[[1]]
  self <- intersect(item_ids, mm_refs)
  expect_length(self, 4L)                                   # the four link items
  man_refs <- regmatches(b$man, gregexpr('(?<=identifierref=")[^"]+', b$man, perl = TRUE))[[1]]
  expect_length(intersect(self, man_refs), 0L)              # never the item id in the manifest
})

test_that("a published todo refuses to build; an absent published: means unpublished", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  y <- readLines(file.path(p, "modules.yml")); i <- grep("id: todo-1", y); y[i + 2] <- "    published: true"
  writeLines(y, file.path(p, "modules.yml"))
  expect_error(build_cartridge(p), "REFUSING TO BUILD: todo-1")
  b <- built()
  expect_match(b$mm, "<title>Module 2: Unpublished</title>\\s*<workflow_state>unpublished")
})

test_that("two builds on the same day are byte-identical", {
  b <- built()
  h1 <- tree_hashes(b$stage); z1 <- unname(tools::md5sum(b$imscc))
  build_cartridge(b$p)
  expect_identical(tree_hashes(b$stage), h1)
  expect_identical(unname(tools::md5sum(b$imscc)), z1)
})

test_that("no IMS-CC-FILEBASE token, no assessment source, no canary, in the staged tree", {
  b <- built()
  files <- list.files(b$stage, recursive = TRUE, full.names = TRUE)
  expect_false(any(grepl("\\.(Rmd|qmd|R|Rnw|md)$", files)))
  for (f in files) {
    bytes <- readBin(f, "raw", file.info(f)$size)
    expect_length(grepRaw("IMS-CC-FILEBASE", bytes, fixed = TRUE), 0)
    expect_length(grepRaw(LEAK_CANARY, bytes, fixed = TRUE), 0)
  }
})

test_that("a body page with a missing or empty body file refuses to build", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  f <- file.path(p, "content", "canvas", "chapter-one.html")
  writeLines("", f); expect_error(build_cartridge(p), "empty body file")
  unlink(f);        expect_error(build_cartridge(p), "content/canvas/chapter-one.html")
})

test_that("the quiz assignment body carries the questions and not the key; the homework body carries the directions", {
  b <- built()
  qdir <- list.files(b$stage, pattern = "module-1-quiz\\.html$", recursive = TRUE, full.names = TRUE)
  expect_length(qdir, 1L)
  q <- paste(readLines(qdir), collapse = "\n")
  expect_match(q, "Questions"); expect_no_match(q, "ANSWER KEY")
  hw <- paste(readLines(list.files(b$stage, pattern = "homework-1\\.html$", recursive = TRUE, full.names = TRUE)), collapse = "\n")
  expect_match(hw, "Instructions"); expect_no_match(hw, "Step 1")
})

test_that("due dates route through the timezone helper", {
  b <- built()
  s <- paste(readLines(list.files(b$stage, pattern = "assignment_settings\\.xml$", recursive = TRUE, full.names = TRUE)[1]), collapse = "")
  expect_match(paste(list.files(b$stage, recursive = TRUE), collapse = " "), "assignment_settings")
  all_due <- unlist(lapply(list.files(b$stage, pattern = "assignment_settings\\.xml$", recursive = TRUE, full.names = TRUE),
                           function(f) regmatches(x <- paste(readLines(f), collapse = ""), gregexpr("(?<=<due_at>)[^<]+", x, perl = TRUE))[[1]]))
  expect_setequal(all_due, c("2026-09-16T04:59:00", "2026-09-21T04:59:00"))
})

test_that("the R/exams quiz embeds with the prefix rewritten and two distinct idents", {
  b <- built()
  qti <- list.files(file.path(b$stage, "non_cc_assessments"), full.names = TRUE)
  expect_length(qti, 1L)
  x <- paste(readLines(qti), collapse = "\n")
  expect_no_match(x, "quiz-sample_[0-9]+")
  idents <- regmatches(x, gregexpr('<item ident="[^"]*"', x))[[1]]
  expect_length(unique(idents), 2L)
  expect_no_match(x, "DOCTYPE")
})

test_that("the cartridge filename comes from the course slug", {
  b <- built()
  expect_match(basename(b$imscc), "^abcd-101-01-[0-9]{4}-[0-9]{2}-[0-9]{2}\\.imscc$")
})
```

```r
# tests/testthat/test-announcements.R
test_that("announcements: two topics, two metas, the right states and a UTC stamp from the declared zone", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  res <- build_cartridge(p)
  man <- paste(readLines(file.path(res$stage, "imsmanifest.xml")), collapse = "\n")
  expect_length(gregexpr('type="imsdt_xmlv1p1"', man)[[1]], 2L)
  metas <- list.files(res$stage, pattern = "\\.xml$", full.names = TRUE)
  metas <- metas[vapply(metas, function(f) any(grepl("<topicMeta", readLines(f, warn = FALSE))), TRUE)]
  expect_length(metas, 2L)
  txt <- vapply(metas, function(f) paste(readLines(f), collapse = "\n"), "")
  expect_true(any(grepl("<workflow_state>active</workflow_state>", txt) & !grepl("delayed_post_at", txt)))
  expect_true(any(grepl("<delayed_post_at>2026-09-08T05:00:00</delayed_post_at>", txt, fixed = TRUE)))
  # the body lost its <h2>
  topics <- list.files(res$stage, pattern = "\\.xml$", full.names = TRUE)
  topics <- topics[vapply(topics, function(f) any(grepl("<topic ", readLines(f, warn = FALSE))), TRUE)]
  expect_false(any(grepl("&lt;h2&gt;", vapply(topics, function(f) paste(readLines(f), collapse = ""), ""))))
})

test_that("a different zone produces a different stamp, and a missing body stops", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  y <- readLines(file.path(p, "announcements.yml"))
  writeLines(sub("America/Chicago", "Europe/London", y), file.path(p, "announcements.yml"))
  res <- build_cartridge(p)
  allx <- vapply(list.files(res$stage, pattern = "\\.xml$", full.names = TRUE), function(f) paste(readLines(f), collapse = ""), "")
  expect_true(any(grepl("<delayed_post_at>2026-09-07T23:00:00</delayed_post_at>", allx, fixed = TRUE)))
  unlink(file.path(p, "content", "announcements", "week-2.html"))
  expect_error(build_cartridge(p), "names a body file that does not exist")
})

test_that("an unknown post: form stops, and a body whose h2 disagrees with the title stops", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  y <- readLines(file.path(p, "announcements.yml"))
  writeLines(sub("post: 2026-09-08", "post: next monday", y), file.path(p, "announcements.yml"))
  expect_error(build_cartridge(p), "post must be 'immediately'")
  writeLines(y, file.path(p, "announcements.yml"))
  writeLines(c("<h2>Different</h2>", "<p>x</p>"), file.path(p, "content", "announcements", "week-2.html"))
  expect_error(build_cartridge(p), "the body's <h2> reads")
})
```

- [ ] **Step 2: Run to verify failure**

Run: `Rscript -e 'testthat::test_local(filter = "cartridge|announcements")'`
Expected: every test FAILs on `build_cartridge` not found; the gate test still skips.

- [ ] **Step 3: Perform the move, file by file, in the map's order**

Create `R/ids.R` first (lines 129 to 176 verbatim, `digest::digest`). Delete the temporary `slugify()` from `R/config.R`. Then `R/cartridge-items.R`, `R/cartridge-xml.R`, `R/cartridge-quiz.R`, `R/cartridge-announcements.R`, `R/cartridge-checks.R`, and last `R/cartridge.R`, whose body is:

```r
#' Build a Canvas-importable Common Cartridge from course.yml and modules.yml
#'
#' (header comment from the snapshot, lines 7 to 63, follows here as roxygen
#'  sections: The identifier model; What this does not do, on purpose)
#' @param proj Course project root.
#' @return `invisible(list(imscc, stage))`.
#' @export
build_cartridge <- function(proj = ".") {
  proj <- normalizePath(proj, mustWork = TRUE)
  out_root <- file.path(proj, "build", "coursepack"); stage <- file.path(out_root, "staging")
  unlink(stage, recursive = TRUE)                       # purge, see the snapshot's comment at 70 to 75
  m <- read_manifest(proj); course <- m$course; mods <- m$mods
  ann <- read_announcements(proj)
  # The zone is read only when something needs it: a due: on any definition,
  # or announcements. An extracted course (Phase 4) has neither and must build
  # without a term: block.
  tz <- if (needs_timezone(m, ann)) read_timezone(course) else NULL
  tb_docs <- textbook_docs_path(course, proj)

  r <- resolve_items(m)                                  # items, modmeta, ids
  tile <- stage_course_card(proj, stage)
  write_course_settings(stage, course, tile)
  ag_id <- write_assignment_groups(stage, course)
  write_course_settings_files(stage, course)
  write_module_meta(stage, r$modmeta)
  write_weblinks(stage, r$items)
  write_wiki_pages(stage, proj, m$pages, r$ids$page_res, course$urls)
  write_assignments(stage, m$assignments, r$ids, course, tb_docs, ag_id, proj, tz)
  for (k in names(m$quizzes)) embed_quiz(k, m$quizzes[[k]], r$ids, ag_id, stage, proj)
  ann_ids <- if (is.null(ann)) list(ann_res = character(), ann_meta = character(), ann_past = character())
             else stage_announcements(ann, stage)
  settings_res <- write_manifest(stage, course, r$modmeta, r$items, r$ids, tile, ann_ids, m)

  cat("=== pre-zip validation ===\n")
  problems <- character(); p_fail <- function(...) problems <<- c(problems, paste0(...))
  prezip_checks(stage, settings_res, ann_ids$ann_res, p_fail)
  check_announcements(stage, ann, ann_ids$ann_res, p_fail)
  if (length(problems)) {
    cat("\nBUILD FAILED:\n"); for (p in problems) cat("  ! ", p, "\n", sep = "")
    stop("BUILD FAILED: ", length(problems), " problem(s); see above", call. = FALSE)
  }
  outfile <- file.path(out_root, sprintf("%s-%s.imscc", course_slug(course), format(Sys.Date())))
  zip_cartridge(stage, outfile)                          # lines 1253 to 1267: mtime pin, zip -q -X
  cat("\n=== built ===\n")
  cat(sprintf("  %s  (%s KB, %d entries)\n", outfile, format(round(file.size(outfile) / 1024, 1), nsmall = 1),
              length(list.files(stage, recursive = TRUE))))
  version_line("build_cartridge")
  cat("\nA zip that builds proves NOTHING. Canvas discards malformed cartridges\n")
  cat("without reporting an error. Import into a throwaway shell and look.\n")
  invisible(list(imscc = outfile, stage = stage))
}
```

`zip_cartridge()` stops with `"zip binary not found on the PATH; install zip"` when `Sys.which("zip")` is empty, before touching mtimes. `needs_timezone(m, ann)` is `!is.null(ann) || any(vapply(c(m$assignments, m$quizzes), function(d) !is.null(d$due), TRUE))`, defined in `R/cartridge.R`.

Every comment block the snapshot carries moves with its code. That is not optional: the identifier-model header, the quiz three-file layout, the prefix-rewrite rationale, the staging-purge rationale, the leftover-token check, the distinct-idents check, the manifest-never-declares-itself exemption, the answer-key containment rationale, and the announcement traps are the operational record of real failures.

- [ ] **Step 4: Un-skip the gate and run everything**

Delete the `skip_if(!exists("build_cartridge"), ...)` line from `tests/testthat/test-cartridge-gate.R`.

```bash
Rscript -e 'roxygen2::roxygenise()'
Rscript -e 'testthat::test_local()'
```
Expected: the gate passes; `cartridge` 9 tests, `announcements` 3 tests pass. If the gate reports a `changed:` line, unpack both trees, `diff` the named file, and find the edit that was not in the map. The two most likely: the `body: true` error text (it is inside a `stop()`, so it is not in the tree; fine) and whitespace from a reflowed `paste0()`.

- [ ] **Step 5: Check, bump**

Run the full check. Expected: 0 errors, 0 warnings; the unused-Imports NOTE now lists at most `jsonlite`, `stringr`. `Version: 0.0.0.9009`; NEWS: "`build_cartridge()` moved, split across seven files along the script's own banners; due dates route through `local_to_utc()`; the filename is `<slug>-<date>.imscc`."

- [ ] **Step 6: Propose the commit and stop**

```
Move the cartridge builder into the package behind the byte gate
```

---

### Task 11: Move the QTI builder

**Files:**
- Create: `R/qti.R`, `tests/testthat/test-qti.R`
- Source: `build_qti.R`

**Interfaces:**
- Produces, exported: `build_qti(quiz_file, proj = ".")` returning the zip path invisibly. The definition file assigns a list `quiz` with `name`, `exercises`, `n`, optional `points`, `quiztype`; exercises resolve against `dirname(dirname(quiz_file))/exercises`; output goes to `file.path(proj, "build", "qti")` (the one behaviour change: `proj`, not `getwd()`). Guards `requireNamespace("exams")` with `"install.packages(\"exams\") to build QTI packages"`. `converter = "pandoc-mathjax"` unchanged.

- [ ] **Step 1: Write the failing tests**

```r
# tests/testthat/test-qti.R
defn <- function(dir, body) { f <- file.path(dir, "quizzes", "q.R"); dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE); writeLines(body, f); f }

test_that("a missing definition file and missing required fields stop with the field names", {
  d <- withr::local_tempdir()
  expect_error(build_qti(file.path(d, "nope.R"), d), "does not exist")
  f <- defn(d, 'quiz <- list(name = "q")')
  expect_error(build_qti(f, d), "missing: exercises, n")
})

test_that("absent exercise files are listed", {
  d <- withr::local_tempdir()
  f <- defn(d, 'quiz <- list(name = "q", exercises = c("a.Rmd", "b.Rmd"), n = 1)')
  expect_error(build_qti(f, d), "exercise files not found:.*a.Rmd.*b.Rmd")
})

test_that("with exams installed, a one-exercise quiz writes build/qti/<name>.zip under proj", {
  skip_if_no_exams(); skip_if_no("pandoc"); skip_if_no("zip")
  d <- withr::local_tempdir(); dir.create(file.path(d, "exercises"))
  writeLines(c("Question", "========", "What is 1 + 1?", "", "Solution", "========", "2", "",
               "Meta-information", "================", "extype: num", "exsolution: 2", "exname: onePlusOne"),
             file.path(d, "exercises", "one.Rmd"))
  f <- defn(d, 'quiz <- list(name = "tiny", exercises = "one.Rmd", n = 1)')
  z <- build_qti(f, d)
  expect_equal(normalizePath(z), normalizePath(file.path(d, "build", "qti", "tiny.zip")))
})
```

- [ ] **Step 2: Run to verify failure**

Run: `Rscript -e 'testthat::test_local(filter = "qti")'`
Expected: FAIL, `could not find function "build_qti"`.

- [ ] **Step 3: Write `R/qti.R`**

Port the script into the function: the `commandArgs()` block goes; `quiz_file <- normalizePath(quiz_file, mustWork = FALSE)` and an explicit `if (!file.exists(quiz_file)) stop("quiz definition does not exist: ", quiz_file)`; `source(quiz_file, local = TRUE)`; the required-field check stops with `"quiz definition is missing: <fields>"`; `out_dir <- file.path(proj, "build", "qti")`; `exams::exams2canvas(...)` with the same arguments and the pandoc-mathjax comment; the three closing NOT VERIFIED lines; `version_line("build_qti")`. Keep the header comment about the swappable generator contract.

- [ ] **Step 4: Document, test, bump**

Expected: 3 tests pass (the third may take ten seconds; it renders through R/exams). `Version: 0.0.0.9010`; NEWS: "`build_qti()`; output goes under `proj`."

- [ ] **Step 5: Propose the commit and stop**

```
Move the QTI builder; output lands under proj
```

---

### Task 12: Move the preview builder and the mockup templates

**Files:**
- Create: `R/preview.R`, `inst/templates/mockup/index.html`, `inst/templates/mockup/mockup.css`, `inst/templates/mockup/mockup.js`, `tests/testthat/test-preview.R`
- Source: `build_preview.R`, `templates/mockup/` (three files, copied byte for byte)

**Interfaces:**
- Consumes: `read_manifest()`, `textbook_docs_path()`, the resolve helpers, the body helpers.
- Produces, exported: `build_preview(proj = ".", base = c("local", "live"), textbook_docs = NULL)` returning the model invisibly and writing `build/mockup/` under `proj`. Changes from the script, each deliberate: `base` is an argument (no `MOCKUP_BASE`); `textbook_docs = NULL` reads `course.yml` (no `TEXTBOOK_DOCS`, no sibling-layout fallback: lines 39 to 44 are deleted); templates come from `system.file("templates", "mockup", package = "coursepack")`; the missing `content/canvas/` NOTE stops naming `scripts/build_canvas_pages.R`. Serving stays in the Makefile (`python3 -m http.server`), documented in the roxygen.

- [ ] **Step 1: Write the failing tests, porting every `test_preview.R` assertion**

```r
# tests/testthat/test-preview.R
model <- function(base = "local") {
  skip_if_no("pandoc")
  to <- withr::local_tempdir(.local_envir = parent.frame())
  p <- copy_course(to = to)
  j <- build_preview(p, base = base)
  list(p = p, j = jsonlite::fromJSON(file.path(p, "build", "mockup", "course.json"), simplifyVector = FALSE),
       items = unlist(lapply(j$modules, function(m) m$items), recursive = FALSE))
}

test_that("shape: course block, stats block, modules, textbook_present TRUE against the fake textbook", {
  m <- model()
  expect_false(is.null(m$j$course$code)); expect_false(is.null(m$j$stats$items))
  expect_true(length(m$j$modules) > 0); expect_true(isTRUE(m$j$course$textbook_present))
  expect_equal(length(m$j$modules), m$j$stats$modules); expect_equal(length(m$items), m$j$stats$items)
})

test_that("every item is well formed and type rules hold", {
  m <- model(); it <- m$items
  expect_true(all(vapply(it, function(i) i$form %in% c("header", "page", "link", "assignment", "quiz"), TRUE)))
  expect_true(all(vapply(it, function(i) i$content_type %in% c("ContextModuleSubHeader", "WikiPage", "ExternalUrl", "Assignment", "Quizzes::Quiz"), TRUE)))
  expect_true(all(vapply(it, function(i) i$target$state %in% c("ok", "missing-chapter", "missing-anchor", "unchecked", "none", "external"), TRUE)))
  expect_true(all(vapply(it, function(i) nzchar(i$title), TRUE)))
  hdr <- Filter(function(i) i$form == "header", it); lnk <- Filter(function(i) i$form == "link", it); pag <- Filter(function(i) i$form == "page", it)
  expect_true(all(vapply(hdr, function(i) is.null(i$url), TRUE)))
  expect_true(length(lnk) > 0 && all(vapply(lnk, function(i) !is.null(i$url), TRUE)))
  bare <- function(x) !is.null(x) && grepl("^[0-9]+$", as.character(x))
  expect_true(all(vapply(pag, function(i) !is.null(i$frame$width) && !is.null(i$frame$height), TRUE)))
  expect_false(any(vapply(pag, function(i) bare(i$frame$width) || bare(i$frame$height), TRUE)))
})

test_that("todo items are unpublished and the stats reconcile", {
  m <- model(); it <- m$items
  td <- Filter(function(i) !is.null(i$todo), it)
  expect_true(all(vapply(td, function(i) isFALSE(i$published), TRUE)))
  brk <- Filter(function(i) i$target$state %in% c("missing-chapter", "missing-anchor"), it)
  expect_equal(length(brk), m$j$stats$broken); expect_equal(length(td), m$j$stats$todo)
})

test_that("body pages, homework directions and quiz questions are written as same-origin pages", {
  m <- model()
  expect_true(file.exists(file.path(m$p, "build", "mockup", "pages", "chapter-one.html")))
  expect_true(file.exists(file.path(m$p, "build", "mockup", "assignments", "hw-1.html")))
  expect_true(file.exists(file.path(m$p, "build", "mockup", "quizzes", "quiz-1.html")))
  q <- paste(readLines(file.path(m$p, "build", "mockup", "quizzes", "quiz-1.html")), collapse = "\n")
  expect_no_match(q, "ANSWER KEY")
  expect_true(file.exists(file.path(m$p, "build", "mockup", "mockup.js")))
  expect_true(Sys.readlink(file.path(m$p, "build", "mockup", "textbook")) != "")
})

test_that("live mode points links at the published textbook and creates no symlink", {
  m <- model("live")
  lnk <- Filter(function(i) i$form == "link" && !is.null(i$url) && grepl("ch01", i$url), m$items)
  expect_match(lnk[[1]]$url, "^https://example.invalid/book/")
  expect_false(file.exists(file.path(m$p, "build", "mockup", "textbook")))
})

test_that("an absent textbook_docs key is an error, not a sibling-layout guess", {
  p <- copy_course()
  y <- readLines(file.path(p, "course.yml")); writeLines(y[!grepl("^textbook_docs:", y)], file.path(p, "course.yml"))
  expect_error(build_preview(p), "textbook_docs")
})
```

- [ ] **Step 2: Run to verify failure**

Run: `Rscript -e 'testthat::test_local(filter = "preview")'`
Expected: FAIL, `could not find function "build_preview"`.

- [ ] **Step 3: Move the script and the templates**

```bash
mkdir -p inst/templates/mockup
cp project/econ730-toolchain/templates/mockup/* inst/templates/mockup/
```

`R/preview.R`: the script body inside `build_preview()`, with `base <- match.arg(base)`; `tb_docs <- if (!is.null(textbook_docs)) textbook_docs else textbook_docs_path(course, proj)`; `tpl <- system.file("templates", "mockup", package = "coursepack")` with a stop if empty; `pages`, `asg` from `read_manifest()`; the `build_item()` closure and the model exactly as written; `jsonlite::write_json`; the closing `cat()` lines plus `version_line("build_preview")`. Keep every comment, including the `css_len()` one and the file:// origin one. The header note about the model-not-HTML decision stays.

- [ ] **Step 4: Document, test, bump, check**

Expected: 6 tests pass; check clean (the `jsonlite` NOTE closes). `Version: 0.0.0.9011`; NEWS: "`build_preview()`; mockup templates ship in `inst/templates/mockup/`; the sibling-layout textbook fallback is gone."

- [ ] **Step 5: Propose the commit and stop**

```
Move the preview builder and the mockup templates into the package
```

---

### Task 13: Close Phase 1

**Files:**
- Modify: `DESCRIPTION` (Version 0.1.0), `NEWS.md`, `README.md` (status line only)

- [ ] **Step 1: Full suite and full check**

```bash
Rscript -e 'testthat::test_local()'
```
Expected: 0 failures; skips only for missing tools. Full check: 0 errors, 0 warnings, 0 notes other than `stringr` unused (Phase 3 uses it).

- [ ] **Step 2: Residue greps**

```bash
grep -rn 'Sys.getenv' R/ ; grep -rnE '/Users/|~/' R/ ; grep -rniE 'econ|uwrf|kelly|ljkelly|managerial|macro' R/ inst/ tests/
```
Expected: nothing.

- [ ] **Step 3: README status line**

Replace the paragraph beginning `**Status: skeleton.**` with: `**Status: the ECON 730 chain has moved.** \`check_manifests()\`, \`build_cartridge()\`, \`diff_against_reference()\`, \`build_qti()\`, \`build_preview()\`, and \`course_tile()\` are in the package and pass the byte gate against the frozen script. Nothing has been imported into Canvas from this package yet.` Set `Version: 0.1.0`; NEWS header `# coursepack 0.1.0` collecting the 0.0.0.9001 to 9011 lines under it.

- [ ] **Step 4: Confirm Appendix A's ECON 730 hand-off block for Phase 1 is complete** (it is written below; read it against what actually landed and correct any function name that drifted).

- [ ] **Step 5: Propose the commit and stop**

```
Close phase 1: the cartridge chain is in the package
```

# Phase 2: Converge, changing output on purpose

From here the package is the builder and the frozen script cannot produce a baseline. Every task that changes staged bytes follows this procedure, referred to below as **the regeneration procedure**:

1. Before editing code: `Rscript -e 'pkgload::load_all(); p <- file.path(tempdir(), "before"); dir.create(p); file.copy(testthat::test_path("fixtures", "minimal-course"), p, recursive = TRUE); file.copy(testthat::test_path("fixtures", "fake-textbook"), p, recursive = TRUE); source("tests/testthat/helper-fixtures.R"); zip_fixture_qti(file.path(p, "minimal-course")); build_cartridge(file.path(p, "minimal-course")); cat(p, "\n")'` and keep that staging tree as `before/`.
2. Make the code and fixture changes the task lists.
3. Run the suite. The gate must fail, and its `changed:` / `extra:` / `missing:` lines must equal the task's **Output changes** list exactly. Any other file is a defect in the change; stop.
4. `diff -r before/minimal-course/build/coursepack/staging <new staging>` and read every hunk against the task's description.
5. `Rscript tools/baseline.R package tests/testthat/fixtures/minimal-course tests/testthat/fixtures/minimal-course-expected-tree.txt`.
6. The suite is green. The commit message names each changed staged file and says the cartridge was supposed to change.

First edit to the tool, in Task 14: `package` mode uses `pkgload::load_all(".", quiet = TRUE)` and then `build_cartridge(proj)`, so the tool builds with the working tree, not an installed copy.

### Task 14: `due_time` and the three `due:` forms

**Files:**
- Modify: `R/cartridge-xml.R` (`write_assignments()`), `tools/baseline.R`, `tests/testthat/fixtures/minimal-course/course.yml`, `tests/testthat/test-cartridge.R`
- Regenerate: `tests/testthat/fixtures/minimal-course-expected-tree.txt`

**Interfaces:**
- Consumes: `due_stamp()` (Task 3).
- Schema: `course.yml` gains `due_time: "HH:MM:SS"`. `due:` on an assignment is `YYYY-MM-DD` (takes `due_time`) or `YYYY-MM-DD HH:MM[:SS]`. A bare date with no `due_time` stops (D6: no package default).
- Output changes: `<asg-res>/assignment_settings.xml` for `hw-1` and `quiz-1` (the seconds).

- [ ] **Step 1: Run the regeneration procedure step 1.**

- [ ] **Step 2: Write the failing tests** (append to `test-cartridge.R`; replace the earlier due-date test)

```r
test_that("a bare due: takes due_time; a clock time is used as given; no due_time is a stop", {
  b <- built()
  all_due <- unlist(lapply(list.files(b$stage, pattern = "assignment_settings\\.xml$", recursive = TRUE, full.names = TRUE),
                           function(f) regmatches(x <- paste(readLines(f), collapse = ""), gregexpr("(?<=<due_at>)[^<]+", x, perl = TRUE))[[1]]))
  expect_setequal(all_due, c("2026-09-16T04:59:59", "2026-09-21T04:59:59"))
  p <- b$p
  edit_yaml(p, "modules.yml", "due: 2026-09-15", 'due: "2026-09-15 09:45"')
  build_cartridge(p)
  s <- paste(unlist(lapply(list.files(b$stage, pattern = "assignment_settings\\.xml$", recursive = TRUE, full.names = TRUE), readLines)), collapse = "")
  expect_match(s, "2026-09-15T14:45:00")
  edit_yaml(p, "course.yml", 'due_time: "23:59:59"', "")
  edit_yaml(p, "modules.yml", 'due: "2026-09-15 09:45"', "due: 2026-09-15")
  expect_error(build_cartridge(p), "needs due_time")
})
```

- [ ] **Step 3: Change the code and the fixture**

In `write_assignments()` replace the `due_xml` block with:

```r
  due_xml <- "  <due_at/>\n"
  if (!is.null(a$due))
    due_xml <- paste0("  <due_at>", due_stamp(a$due, course$due_time, tz), "</due_at>\n")
```

and keep the comment above it, rewritten to say the seconds now match what Canvas writes for an end-of-day deadline (`T04:59:59`, verified against the 2026-09-02 round trip) and that the clock time is the course's `due_time`. Add to the fixture `course.yml`, after `term:`: `due_time: "23:59:59"`. Edit `tools/baseline.R`'s package mode as described above.

- [ ] **Step 4: Regeneration procedure steps 3 to 6.** Expected `changed:` list: exactly the two `assignment_settings.xml` files. `Version: 0.1.0.9001`; NEWS: "Due dates: `due_time:` in `course.yml`; `due:` accepts a clock time; seconds now match Canvas (`:59`)."

- [ ] **Step 5: Propose the commit and stop**

```
Emit due_at from due_time; the cartridge was supposed to change (two assignment_settings.xml)
```

---

### Task 15: Every declared assignment group, routed by name

**Files:**
- Create: `R/groups.R`, `tests/testthat/test-groups.R`
- Modify: `R/cartridge-xml.R` (`write_assignment_groups()`, `write_assignments()`), `R/cartridge-quiz.R` (`embed_quiz()`), `R/cartridge.R` (pass the group map), fixture `course.yml` and `modules.yml`
- Regenerate the expected tree.

**Interfaces:**
- Produces: `assignment_group_ids(course)`: named character, group name to id, `g$id %||% gid("assignmentgroup", g$name)`; stops when `group_weighting_scheme` is `percent` and the weights do not sum to 100 (within 0.01). `group_id_for(name, groups, what)`: the id, or stops `"<what> names assignment group '<name>', which is not declared (declared: ...)"`.
- Routing: an assignment's group is `a$group %||% course$assignment_defaults$group`; a quiz's is `q$group %||% course$assignment_defaults$group`; neither present stops.
- Output changes: `course_settings/assignment_groups.xml` (two groups), `quiz-1`'s `assignment_settings.xml` (group ref), `<q-sample>/assessment_meta.xml` (group ref).

- [ ] **Step 1: Regeneration procedure step 1.**

- [ ] **Step 2: Write the failing tests**

```r
# tests/testthat/test-groups.R
test_that("assignment_group_ids derives or honours ids and checks the percent sum", {
  c1 <- list(canvas = list(group_weighting_scheme = "percent"),
             assignment_groups = list(list(name = "A", weight = 80), list(name = "B", weight = 20, id = "g0123456789abcdef0123456789abcdef")))
  g <- assignment_group_ids(c1)
  expect_named(g, c("A", "B")); expect_equal(unname(g["B"]), "g0123456789abcdef0123456789abcdef")
  expect_match(unname(g["A"]), "^g[0-9a-f]{32}$")
  c1$assignment_groups[[1]]$weight <- 70
  expect_error(assignment_group_ids(c1), "sum to 90, not 100")
  expect_error(group_id_for("Homework", g, "assignment 'hw-1'"), "assignment 'hw-1' names assignment group 'Homework', which is not declared")
})
```

Append to `test-cartridge.R`:

```r
test_that("both groups are emitted with their weights and each assignment and quiz lands in its own", {
  b <- built()
  ag <- paste(readLines(file.path(b$stage, "course_settings", "assignment_groups.xml")), collapse = "\n")
  expect_length(gregexpr("<assignmentGroup ", ag)[[1]], 2L)
  expect_match(ag, "<title>Quizzes</title>\\s*<position>2</position>\\s*<group_weight>20.0</group_weight>")
  gids <- regmatches(ag, gregexpr('(?<=identifier=")[^"]+', ag, perl = TRUE))[[1]]
  quiz_meta <- paste(readLines(list.files(b$stage, pattern = "assessment_meta\\.xml$", recursive = TRUE, full.names = TRUE)), collapse = "")
  expect_match(quiz_meta, gids[2], fixed = TRUE)
  q1 <- paste(readLines(list.files(b$stage, pattern = "module-1-quiz", recursive = TRUE, full.names = TRUE, include.dirs = TRUE)[1]), collapse = "")
  settings <- list.files(b$stage, pattern = "assignment_settings\\.xml$", recursive = TRUE, full.names = TRUE)
  refs <- vapply(settings, function(f) sub(".*<assignment_group_identifierref>([^<]+).*", "\\1", paste(readLines(f), collapse = "")), "")
  expect_setequal(unique(unname(refs)), gids)
})

test_that("an undeclared group on an assignment stops the build", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  edit_yaml(p, "modules.yml", "    quiz_file: assessments/quizzes/quiz01.md", "    quiz_file: assessments/quizzes/quiz01.md\n    group: Nowhere")
  expect_error(build_cartridge(p), "names assignment group 'Nowhere'")
})
```

- [ ] **Step 3: Change the code and the fixture**

`R/groups.R` as specified. `write_assignment_groups(stage, course, groups)` loops every group in declared order, `format(as.numeric(g$weight), nsmall = 1)`, returns nothing. `write_assignments()` takes `groups` and uses `group_id_for(a$group %||% d$group, groups, paste0("assignment '", k, "'"))`. `embed_quiz()` takes the quiz's own group id the same way; the `gsub` that stamps `assignment_group_identifierref` and the `GID_` rewrite both use it. Fixture `course.yml`: `assignment_groups:` becomes `Assignments` weight `80.0` position 1 and `Quizzes` weight `20.0` position 2 with an explicit `id: g0000000000000000000000000000000b` (this exercises the override, and Phase 4's carried resources reference this id). Fixture `modules.yml`: `quiz-1` gains `group: Quizzes`; `q-sample` gains `group: Quizzes`. Add to the test above: `expect_true("g0000000000000000000000000000000b" %in% gids)`.

- [ ] **Step 4: Regeneration procedure.** Expected `changed:`: `course_settings/assignment_groups.xml`, the `quiz-1` `assignment_settings.xml`, the `q-sample` `assessment_meta.xml`. `Version: 0.1.0.9002`; NEWS line.

- [ ] **Step 5: Propose the commit and stop**

```
Emit every assignment group and route each item by name; the cartridge was supposed to change (three files)
```

---

### Task 16: Optional grading standard and late policy; one list of known `canvas:` keys

**Files:**
- Create: `R/settings.R`, `tests/testthat/test-settings.R`
- Modify: `R/cartridge-xml.R` (`write_course_settings()` becomes a call into `settings.R`; `write_course_settings_files()` and `write_manifest()` become conditional)

**Interfaces:**
- Produces: `CANVAS_SETTINGS_KEYS`, a character vector in the ECON 730 export's element order: `course_code`, `is_public`, `indexed`, `default_view`, `license`, `grading_standard_enabled`, `group_weighting_scheme`, `restrict_enrollments_to_course_dates`, `allow_student_wiki_edits`, `restrict_student_future_view`, `restrict_student_past_view`. `course_settings_xml(course, tile, has_grading_standard)`: emits `<title>`, then every key of `course$canvas` that is in the list, in list order, lowercasing logicals; `image_identifier_ref` after `course_code` when the tile exists; `grading_standard_identifier_ref` after `grading_standard_enabled` only when `course$grading_standard` exists; an unknown key under `canvas:` stops naming it; a missing `course_code` stops.
- Behaviour: `grading_standards.xml` and `late_policy.xml` are written and declared only when their blocks exist.
- Output changes: none for the fixture (it declares both blocks; of the eleven known keys it declares eight, and the three it omits were never emitted). The gate must stay green without regeneration; that is this task's proof.

- [ ] **Step 1: Write the failing tests**

```r
# tests/testthat/test-settings.R
base <- list(title = "T", canvas = list(course_code = "ABCD 101-01", is_public = FALSE, default_view = "modules"))
test_that("keys are emitted in canonical order, logicals lowercased, unknown keys refused", {
  x <- course_settings_xml(base, list(has_tile = FALSE), has_grading_standard = FALSE)
  expect_match(x, "<course_code>ABCD 101-01</course_code>\\s*<is_public>false</is_public>\\s*<default_view>modules</default_view>")
  expect_no_match(x, "grading_standard_identifier_ref")
  bad <- base; bad$canvas$foo <- 1
  expect_error(course_settings_xml(bad, list(has_tile = FALSE), FALSE), "unknown canvas: key: foo")
  nocode <- base; nocode$canvas$course_code <- NULL
  expect_error(course_settings_xml(nocode, list(has_tile = FALSE), FALSE), "canvas: course_code")
})
```

Append to `test-cartridge.R`:

```r
test_that("without grading_standard: and late_policy: the two files are neither written nor declared", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  y <- readLines(file.path(p, "course.yml"))
  cut <- function(y, start) { i <- grep(start, y); j <- i; while (j < length(y) && grepl("^  ", y[j + 1])) j <- j + 1; y[-(i:j)] }
  y <- cut(y, "^grading_standard:"); y <- cut(y, "^late_policy:")
  y <- sub("grading_standard_enabled: true", "grading_standard_enabled: false", y)
  writeLines(y, file.path(p, "course.yml"))
  res <- build_cartridge(p)
  expect_false(file.exists(file.path(res$stage, "course_settings", "grading_standards.xml")))
  expect_false(file.exists(file.path(res$stage, "course_settings", "late_policy.xml")))
  man <- paste(readLines(file.path(res$stage, "imsmanifest.xml")), collapse = "\n")
  expect_length(gregexpr('<file href="course_settings/', man)[[1]], 6L)
  cs <- paste(readLines(file.path(res$stage, "course_settings", "course_settings.xml")), collapse = "\n")
  expect_no_match(cs, "grading_standard_identifier_ref")
})
```

- [ ] **Step 2: Run, verify failure.** Then implement `R/settings.R`, make the two writers conditional on `!is.null(course$grading_standard)` and `!is.null(course$late_policy)`, and make `write_manifest()` build the settings-resource file list from what was written (`course_settings.xml`, `module_meta.xml`, `assignment_groups.xml`, then `grading_standards.xml` if present, `files_meta.xml`, then `late_policy.xml` if present, `media_tracks.xml`, `canvas_export.txt`), preserving the export's order.

- [ ] **Step 3: Run the whole suite.** Expected: gate green with no regeneration; new tests pass. `Version: 0.1.0.9003`; NEWS: "Grading standard and late policy are optional; `canvas:` keys come from one known-key list and an unknown key stops the build."

- [ ] **Step 4: Propose the commit and stop**

```
Make the grading standard and late policy optional; refuse unknown canvas: keys
```

---

### Task 17: The one iframe page template

**Files:**
- Modify: `R/cartridge-xml.R` (`write_wiki_pages()` iframe branch), fixture `modules.yml` (add a `video: true` page), `tests/testthat/test-cartridge.R`
- Regenerate the expected tree.

**Interfaces:**
- Template (builder-merge 4a; the ECON 202 shape with the R builder's title rule and video allow-list):

```html
<div style="width: 100%; max-width: 100%; margin: 0 auto;">
  <iframe title="{title}" src="{src}" width="{width}" height="{height}" style="border: 0;" loading="lazy" allowfullscreen=""{allow}></iframe>
  <p style="margin-top: 10px; font-size: 0.9em;">
    <a href="{src}" target="_blank" style="color: #0066cc;">Open in new tab</a>
  </p>
</div>
```

where `{allow}` is ` allow="accelerometer; clipboard-write; encrypted-media; gyroscope; picture-in-picture"` when `video: true` and empty otherwise. `height` is written as given; a page without `height` stops (`"page '<slug>' declares iframe: but no height:"`), never a silent `1000px`. The empty-title stop stays.
- Output changes: `wiki_content/welcome.html`; `extra:` the new `wiki_content/video-one.html` and its manifest entry (so `imsmanifest.xml` and `course_settings/module_meta.xml` also change).

- [ ] **Step 1: Regeneration procedure step 1.**

- [ ] **Step 2: Tests**

```r
test_that("iframe pages use the one titled template, with the allow list only for video", {
  b <- built()
  w <- paste(readLines(file.path(b$stage, "wiki_content", "welcome.html")), collapse = "\n")
  expect_match(w, '<iframe title="Welcome" src="https://example.invalid/course/welcome.html" width="100%" height="800" style="border: 0;" loading="lazy" allowfullscreen=""></iframe>', fixed = TRUE)
  expect_match(w, '<a href="https://example.invalid/course/welcome.html" target="_blank"', fixed = TRUE)
  v <- paste(readLines(file.path(b$stage, "wiki_content", "video-one.html")), collapse = "\n")
  expect_match(v, 'allow="accelerometer; clipboard-write; encrypted-media; gyroscope; picture-in-picture"', fixed = TRUE)
  p <- b$p; edit_yaml(p, "modules.yml", '    height: "800"', "")
  expect_error(build_cartridge(p), "no height:")
})
```

- [ ] **Step 3: Code and fixture.** Replace the `inner <- paste0('<p><iframe ...` construction with the template above (keep the comment block on why every frame is titled). Fixture `modules.yml`: add under `pages:` `- slug: video-one`, `title: A Video`, `iframe: "https://www.youtube-nocookie.com/embed/xyz"`, `width: "560"`, `height: "315"`, `video: true`, and an item `- page: video-one` at the end of Module 1 (after every existing item, so no other item's position-derived id changes). The `items` and `page` fixture counts in `test-manifests.R` become 13 and 3.

- [ ] **Step 4: Regeneration procedure.** Expected: `changed:` `wiki_content/welcome.html`, `imsmanifest.xml`, `course_settings/module_meta.xml`; `extra:` `wiki_content/video-one.html`. `Version: 0.1.0.9004`; NEWS line.

- [ ] **Step 5: Propose the commit and stop**

```
Emit one titled iframe template for every iframe page; the cartridge was supposed to change
```

---

### Task 18: Schema additions with no output change

**Files:**
- Modify: `R/cartridge-items.R`, `R/cartridge-xml.R`, `R/config.R` (accept `height_measured`), `R/cartridge.R` (report `source:`), `tests/testthat/test-cartridge.R`

**Interfaces:**
- `published:` on any module item: header, page, and link items default to the module's state as today; an explicit `published: false` on an item makes its `workflow_state` `unpublished`. For assignment and quiz items the definition's `published` wins unless the item sets one, and an item `published: true` over a definition `published: false` stops (`"item <title> is published but its definition is not"`), because the definition is what Canvas shows.
- `item_id:` on an item, `module_id:` on a module, `resource_id:` on a page, assignment, or quiz definition: override the derived id. Each must match `^g[0-9a-f]{32}$` or stop.
- `height_measured:` on an iframe page is accepted and ignored by the builder (Task 22 reads it).
- `reference.yml`'s `source:` is read; when present and no definition carries `source_ref`, the build prints `source declared, 0 resources carried`.
- Output changes: none for the fixture. Gate stays green.

- [ ] **Step 1: Tests**

```r
test_that("item, module and resource id overrides appear where the derived ids would", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  edit_yaml(p, "modules.yml", '  - title: "Module 1: Start Here"', '  - title: "Module 1: Start Here"\n    module_id: gaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
  edit_yaml(p, "modules.yml", "      - page: welcome\n        indent: 1", "      - page: welcome\n        indent: 1\n        item_id: gbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
  edit_yaml(p, "modules.yml", "    title: Welcome\n", "    title: Welcome\n    resource_id: gcccccccccccccccccccccccccccccccc\n")
  res <- build_cartridge(p)
  mm <- paste(readLines(file.path(res$stage, "course_settings", "module_meta.xml")), collapse = "\n")
  expect_match(mm, 'module identifier="gaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"', fixed = TRUE)
  expect_match(mm, 'item identifier="gbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"', fixed = TRUE)
  expect_match(mm, "<identifierref>gcccccccccccccccccccccccccccccccc</identifierref>", fixed = TRUE)
  expect_true(file.exists(file.path(res$stage, "wiki_content", "welcome.html")))
  man <- paste(readLines(file.path(res$stage, "imsmanifest.xml")), collapse = "\n")
  expect_match(man, 'resource identifier="gcccccccccccccccccccccccccccccccc"', fixed = TRUE)
  edit_yaml(p, "modules.yml", "gcccccccccccccccccccccccccccccccc", "not-an-id")
  expect_error(build_cartridge(p), "resource_id must be g plus 32 hex")
})

test_that("an item-level published: false unpublishes a page item; published over an unpublished definition stops", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  edit_yaml(p, "modules.yml", "      - page: welcome\n        indent: 1", "      - page: welcome\n        indent: 1\n        published: false")
  res <- build_cartridge(p)
  mm <- paste(readLines(file.path(res$stage, "course_settings", "module_meta.xml")), collapse = "\n")
  expect_match(mm, "<workflow_state>unpublished</workflow_state>\\s*<title>Welcome</title>")
  edit_yaml(p, "modules.yml", "      - assignment: todo-1", "      - assignment: todo-1\n        published: true")
  expect_error(build_cartridge(p), "is published but its definition is not")
})

test_that("height_measured is accepted, and a declared source with nothing carried is reported", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  edit_yaml(p, "modules.yml", '    height: "800"', '    height: "800"\n    height_measured: "2026-09-01T10:00:00"')
  writeLines("source: reference/none.imscc", file.path(p, "reference.yml"))
  expect_output(build_cartridge(p), "source declared, 0 resources carried")
})
```

- [ ] **Step 2: Implement.** In `resolve_items()`: `mrow$id <- check_gid(m$module_id) %||% gid("module", m$title)`; `r$item_id <- check_gid(it$item_id) %||% gid("item", key)`; page/assignment/quiz resource ids come from `check_gid(def$resource_id) %||% gid(...)` computed once in the ids block and used everywhere (`page_res`, `asg_res`, `quiz_res`). `check_gid(x)` returns `NULL` for `NULL`, stops unless `grepl("^g[0-9a-f]{32}$", x)`. Item state: `if (isFALSE(it$published)) r$state <- "unpublished"`; for assignment and quiz items, `if (isTRUE(it$published) && !isTRUE(def$published)) stop(...)`. In `build_cartridge()`: `ref <- read_reference(proj); if (!is.null(ref$source) && !any_source_ref(m)) cat("  source declared, 0 resources carried\n")` where `any_source_ref()` scans the three definition lists for `source_ref` (always `FALSE` until Task 29).

- [ ] **Step 3: Suite green, gate green, no regeneration.** `Version: 0.1.0.9005`; NEWS: "Schema: `published:` on items, `item_id:`, `module_id:`, `resource_id:` overrides, `height_measured:`, `source:` in `reference.yml`."

- [ ] **Step 4: Propose the commit and stop**

```
Accept id overrides, item-level published, height_measured and source: with no output change
```

---

### Task 19: Assignment body prose moves to YAML

**Files:**
- Modify: `R/cartridge-xml.R` (`assignment_body()`, `HOMEWORK_SUBMISSION_NOTE` deleted), `tests/testthat/test-cartridge.R`
- Regenerate the expected tree.

**Interfaces:**
- Schema: `assignment_defaults.homework_intro`, an HTML template with `{title}` and `{href}`; package default `"<p>The directions below are copied from <a class=\"inline_disabled\" title=\"Link\" href=\"{href}\" target=\"_blank\">{title}</a> in the course textbook, which is the source of record.</p>"`. `assignment_defaults.submission_note`, HTML appended after the directions; package default empty, so nothing is appended. Both may be overridden per assignment with the same keys. The `todo`/no-anchor "not ready" paragraph stays as it is (it names no course).
- Output changes: `hw-1`'s `homework-1.html` (the ECON 730 intro sentence and the Quarto-to-Word paragraph leave).

- [ ] **Step 1: Regeneration procedure step 1.**

- [ ] **Step 2: Tests**

```r
test_that("the homework body uses the package intro and no submission note unless the course declares them", {
  b <- built()
  hw <- paste(readLines(list.files(b$stage, pattern = "homework-1\\.html$", recursive = TRUE, full.names = TRUE)), collapse = "\n")
  expect_match(hw, "copied from <a[^>]*>Chapter One Homework</a> in the course textbook")
  expect_no_match(hw, "Quarto"); expect_no_match(hw, "MS Word")
  p <- b$p
  edit_yaml(p, "course.yml", "  group: Assignments", "  group: Assignments\n  submission_note: \"<p>Upload a PDF.</p>\"\n  homework_intro: \"<p>See {title}.</p>\"")
  build_cartridge(p)
  hw <- paste(readLines(list.files(b$stage, pattern = "homework-1\\.html$", recursive = TRUE, full.names = TRUE)), collapse = "\n")
  expect_match(hw, "<p>See Chapter One Homework.</p>", fixed = TRUE)
  expect_match(hw, "<p>Upload a PDF.</p>", fixed = TRUE)
})
```

- [ ] **Step 3: Code.** `assignment_body(a, course, tb_docs, tz)`:

```r
  d <- course$assignment_defaults
  intro <- a$homework_intro %||% d$homework_intro %||% HOMEWORK_INTRO_DEFAULT
  note  <- a$submission_note %||% d$submission_note %||% ""
  intro <- gsub("{title}", xesc(hw$title %||% hw$chapter), gsub("{href}", xesc(href), intro, fixed = TRUE), fixed = TRUE)
  paste0(intro, "\n<hr>\n", directions, if (nzchar(note)) paste0("\n<hr>\n", note) else "")
```

Delete `HOMEWORK_SUBMISSION_NOTE`. Add `HOMEWORK_INTRO_DEFAULT` with the string above and a comment that a course puts its own workflow prose in `course.yml`.

- [ ] **Step 4: Regeneration procedure.** Expected `changed:`: the one `homework-1.html`. `Version: 0.1.0.9006`; NEWS: "The homework intro and submission note come from `course.yml`; no course prose remains in package code." Appendix A carries ECON 730's two paragraphs for its `course.yml`.

- [ ] **Step 5: Propose the commit and stop**

```
Move the assignment body prose to course.yml; the cartridge was supposed to change (homework-1.html)
```

---

### Task 20: `textbook_docs: none` through the builder and the preview; the local `{site}` base

**Files:**
- Modify: `R/cartridge-xml.R`, `R/preview.R`, `tests/testthat/test-cartridge.R`, `tests/testthat/test-preview.R`

**Interfaces:**
- Builder with `tb_docs == NULL`: a `homework:` assignment with an anchor stops `"assignment '<id>' inlines directions from the textbook but textbook_docs is none"`; `link:` items with `chapter:` still emit their URL (nothing to check); `todo` and `quiz_file` assignments are unaffected.
- Preview with `tb_docs == NULL`: `textbook_present = FALSE`, no symlink, every chapter target `unchecked` with detail `textbook_docs: none`, the closing NOTE says so.
- The local `{site}` base. Decision 10 of the extraction design named "the known `{site}` token divergence between the mockup and the cartridge" and no snapshot document defines it. This plan's reading: in local mode the mockup serves `{textbook}` same-origin but leaves `{site}` pointing at the published site, so a local preview can show an unpushed chapter beside a pushed syllabus. The fix under that reading: when `base == "local"` and `<proj>/docs` exists, symlink `build/mockup/site` to it and rewrite `{site}` to `/site`; record `site_base` in the model. **Confirm the reading with Logan before executing this half; if it is wrong, re-scope this half, do not skip it.**
- Output changes: none.

- [ ] **Step 1: Tests**

```r
# test-cartridge.R
test_that("textbook_docs: none refuses a homework assignment that inlines directions", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  edit_yaml(p, "course.yml", "textbook_docs: ../fake-textbook/docs", "textbook_docs: none")
  expect_error(build_cartridge(p), "textbook_docs is none")
})
# test-preview.R
test_that("textbook_docs: none previews with every chapter target unchecked and no symlink", {
  skip_if_no("pandoc")
  p <- copy_course()
  edit_yaml(p, "course.yml", "textbook_docs: ../fake-textbook/docs", "textbook_docs: none")
  build_preview(p)
  j <- jsonlite::fromJSON(file.path(p, "build", "mockup", "course.json"), simplifyVector = FALSE)
  expect_false(isTRUE(j$course$textbook_present))
  expect_false(file.exists(file.path(p, "build", "mockup", "textbook")))
})
test_that("in local mode a rendered docs/ is served as /site and {site} points at it", {
  skip_if_no("pandoc")
  p <- copy_course(); dir.create(file.path(p, "docs")); writeLines("<p>w</p>", file.path(p, "docs", "welcome.html"))
  build_preview(p)
  j <- jsonlite::fromJSON(file.path(p, "build", "mockup", "course.json"), simplifyVector = FALSE)
  welcome <- Filter(function(i) identical(i$title, "Welcome"), unlist(lapply(j$modules, function(m) m$items), recursive = FALSE))[[1]]
  expect_equal(welcome$url, "/site/welcome.html")
  expect_true(nzchar(Sys.readlink(file.path(p, "build", "mockup", "site"))))
})
```

- [ ] **Step 2: Implement** as specified. `Version: 0.1.0.9007`; NEWS: "`textbook_docs: none` is threaded through the builder and the preview; local previews serve the course's own `docs/` as `/site`."

- [ ] **Step 3: Propose the commit and stop**

```
Thread textbook_docs: none through the builder and preview; serve docs/ as /site locally
```

---

### Task 21: The marker and header checks; announcements read the course term

**Files:**
- Modify: `R/cartridge-checks.R`, `R/cartridge-announcements.R`, `R/config.R` (`read_announcements()` term optional), `tests/testthat/test-cartridge.R`, `tests/testthat/test-announcements.R`

**Interfaces:**
- Pre-zip scan gains two stops (builder-merge 4a, mechanics 5a): `course_settings/canvas_export.txt` must exist on disk and be declared by the settings resource; the manifest header (everything before `<organizations>`) must contain `xmlns:lomimscc`, `xsi:schemaLocation`, `<lomimscc:lom>`, and `<schemaversion>1.1.0</schemaversion>`. Both are guards against a future edit, so the test writes a deliberately stripped `imsmanifest.xml` into a scratch staging directory and calls `prezip_checks()` on it directly.
- `announcements.yml`'s `term:` block becomes optional. When absent, `tz`, `first_day`, and `last_day` come from `course$term`; when `course$term` lacks any of the three, the old error text names both files.
- Output changes: none.

- [ ] **Step 1: Tests**

```r
# test-cartridge.R
test_that("the pre-zip scan refuses a manifest whose header lost its load-bearing tokens", {
  p_fail_msgs <- character(); p_fail <- function(...) p_fail_msgs <<- c(p_fail_msgs, paste0(...))
  d <- withr::local_tempdir(); dir.create(file.path(d, "course_settings"))
  writeLines("<?xml version=\"1.0\"?><manifest><organizations/><resources/></manifest>", file.path(d, "imsmanifest.xml"))
  prezip_checks(d, settings_res = "gx", ann_res = character(), p_fail = p_fail)
  expect_true(any(grepl("manifest header is missing xmlns:lomimscc", p_fail_msgs)))
  expect_true(any(grepl("canvas_export.txt", p_fail_msgs)))
})
# test-announcements.R
test_that("announcements.yml without term: reads the zone and window from course.yml", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  y <- readLines(file.path(p, "announcements.yml")); y <- y[!grepl("^term:|^  (timezone|first_day|last_day):", y)]
  writeLines(y, file.path(p, "announcements.yml"))
  res <- build_cartridge(p)
  allx <- vapply(list.files(res$stage, pattern = "\\.xml$", full.names = TRUE), function(f) paste(readLines(f), collapse = ""), "")
  expect_true(any(grepl("<delayed_post_at>2026-09-08T05:00:00</delayed_post_at>", allx, fixed = TRUE)))
})
```

- [ ] **Step 2: Implement.** `read_announcements(proj, course = NULL)`: when `ay$term` is `NULL`, take the three values from `course$term` (stop with `"announcements.yml has no term: and course.yml term: lacks timezone, first_day or last_day"` if any is missing). `build_cartridge()` passes `course`. The two new checks in `prezip_checks()` read `imsmanifest.xml` from `stage` like every other check there.

- [ ] **Step 3: Suite green; no regeneration.** `Version: 0.1.0.9008`; NEWS line.

- [ ] **Step 4: Propose the commit and stop**

```
Guard the Canvas marker and manifest header; announcements fall back to the course term
```

---

### Task 22: The stale-height check

**Files:**
- Create: `R/stale.R`, `tests/testthat/test-stale.R`
- Modify: `R/cartridge.R` (call it and print its lines)

**Interfaces:**
- `check_stale_heights(proj, course, pages)`: for every `iframe:` page whose resolved src starts with `course$urls$site`, map the URL tail under `<proj>/docs`; classify as `undated` (no `height_measured`), `stale` (the local file's mtime is after `height_measured`), `fresh`, or `unmappable` (no local file under `docs/`); returns `list(undated, stale, fresh, unmappable)` as character vectors of slugs and prints one line per non-empty class. An iframe page with no `height` is already a stop (Task 17). Warning-level: the build proceeds. Review finding 11 (fail-open) is fixed: `unmappable` is counted and printed, never silently exempt.
- Output changes: none.

- [ ] **Step 1: Tests**

```r
# tests/testthat/test-stale.R
test_that("undated, stale, fresh and unmappable are each reported by slug", {
  p <- copy_course(); dir.create(file.path(p, "docs"))
  writeLines("x", file.path(p, "docs", "welcome.html"))
  course <- read_course(p); pages <- read_manifest(p)$pages
  r <- check_stale_heights(p, course, pages)
  expect_equal(r$undated, "welcome")
  pages$welcome$height_measured <- format(Sys.time() + 3600, "%Y-%m-%dT%H:%M:%S")
  expect_equal(check_stale_heights(p, course, pages)$fresh, "welcome")
  Sys.setFileTime(file.path(p, "docs", "welcome.html"), Sys.time() + 7200)
  expect_equal(check_stale_heights(p, course, pages)$stale, "welcome")
  pages$welcome$iframe <- "{site}/nowhere/else.html"
  expect_equal(check_stale_heights(p, course, pages)$unmappable, "welcome")
})
```

- [ ] **Step 2: Implement** as specified; `build_cartridge()` calls it after `read_manifest()` and prints e.g. `  heights: 1 undated (welcome), 0 stale, 0 fresh, 0 unmappable`. `Version: 0.1.0.9009`; NEWS line.

- [ ] **Step 3: Propose the commit and stop**

```
Report undated, stale, fresh and unmappable iframe heights on every build
```

**Phase 2 close.** Suite green, check clean, greps clean. `Version: 0.2.0`; NEWS header. Appendix A's Phase 2 block lists the ECON 730 YAML edits that keep its output equivalent (`due_time`, `term:`, `assignment_defaults.group`, the two prose paragraphs, `slug`). Propose the commit `Close phase 2: the builder has converged`.

# Phase 3: Accessibility

7,037 lines move: six library files (3,543 lines), the driver (388), and `test_a11y.R` (3,106 lines, 390 `check()` calls and 10 `skip()` calls in 62 sections). The libraries are already argument-driven; the work is the test port and the sharp edges the spec's Task 11 lists. No task in this phase touches cartridge output.

**The port rule for `test_a11y.R`, applied in Tasks 23 to 26.** Each `cat("=== <section> ===\n")` opens one `test_that("<section>", { ... })`. Each `check("<label>", actual, expected)` becomes `expect_identical(actual, expected, info = "<label>")`. Each `skip("<label>", "<reason>")` becomes `testthat::skip("<reason>")` at the top of its block. The `fails`, `skips`, and verdict bookkeeping is dropped; testthat counts. Every `source(file.path(proj, "scripts", "lib", ...))` line is dropped. A section that reads a real repository path (`/Users/...`, `../real-world-statistics-with-r`, the reference export) is rewritten against `fixtures/pair/` or `fixtures/minimal-course/`; when no fixture can carry the assertion, the section is replaced by the synthetic equivalent the task names, and the replacement is recorded in NEWS. A section that needs the network keeps its injected-fetcher form and skips on `!nzchar(Sys.getenv("COURSEPACK_NETWORK_TESTS"))`. **Verification of completeness:** for each task, `sed -n '<from>,<to>p' project/econ730-toolchain/scripts/test_a11y.R | grep -c '^check('` over the sections listed must not exceed `grep -c 'expect_' tests/testthat/test-a11y-<file>.R`. Negative controls port faithfully; several exist because a check once passed while proving nothing.

Section map (line numbers in `test_a11y.R`, first line of each `cat("===`):

| Destination test file | Sections |
|---|---|
| `test-a11y-serve.R` | 42 serve_dir; 60 pa11y_raw fixture check (skips without `npx`); 2054 a broken pa11y run must FAIL, not SKIP |
| `test-a11y-model.R` | 106 finding_id; 127 from_pa11y aggregation; 250 axe_criterion; 377 diff_findings; 391 round trip; 1872 distinct ids in one file; 1929 report_and_dedup; 2109 collision halts, duplicate does not; 2514 M12 JSON names; 3003 M11 no criterion |
| `test-a11y-targets.R` | 448 discover_target synthetic; 482, 502, 547, 564, 599, 619 find_stylesheet and find_output_dir; 707 discover_target real repos (replace: run against `fixtures/pair/alpha` and assert framework `quarto` when a `_quarto.yml` is written into it); 2211 declared surfaces through `intended_surfaces()`; 2705 declared pass-through dirs excluded; 2794 exclusion entries are globs (the tripwire); 2981 I8 same-basename halt; 3056 unproduced sources |
| `test-a11y-checks.R` | 758 contrast; 784 filename-as-alt; 809 missing fig-alt; 845 rendered vs source-heuristic; 918 colour-only; 2638 I5 source checks not blind; 2857 containment: assessment sources never scanned |
| `test-a11y-cartridge.R` | 947 real reference export (replace: a synthetic cartridge zipped in the test with two iframes, one untitled, one weblink `click here`); 1018 discrimination fixture; 1069 empty-title and case-insensitivity; 1129 broken-embed with injected fetcher; 1169 two courses never merge; 1224 caption state synthetic payloads; 1302 network wrapper with injected fetcher; 1331, 1343 network (skip unless `COURSEPACK_NETWORK_TESTS`); 1367 media inventory fixture; 1398 real textbook repo (replace: `fixtures/pair/alpha` with one PNG and one PDF written by the test); 2198 caption never `none` without proof; 2527 C2 caption states; 2887 undetermined video; 3020 I4 inventory reaches the report |
| `test-a11y-report.R` | 1434, 1462 classify_fixes; 1480 notices filtered once; 1530 broken embeds per item; 1560, 1628, 1688 render_report pages_examined and surfaces; 1725, 1754 1.1.1 routing; 1773 level_for; 1791, 1810, 1839 render; 2150 cross-engine classification; 2909 review severity keeps target; 2926 I6; 2961 I7 |
| `test-a11y-driver.R` | 2002 the audit must FAIL on broken input; 2175 pages_examined catches a zero-finding surface; 2334 C1 two signals from two code paths; 2474 the page count says what it means |

### Task 23: `a11y_serve.R` and `a11y_model.R`

**Files:**
- Create: `R/a11y-serve.R`, `R/a11y-model.R`, `tests/testthat/test-a11y-serve.R`, `tests/testthat/test-a11y-model.R`
- Source: `lib/a11y_serve.R` (186), `lib/a11y_model.R` (734)

**Interfaces:**
- Produces: everything the two files define, unchanged in name and signature: `port_is_free(port)`, `serve_dir(dir, port = 8766L)` returning `list(url, port, pid, stop)` (all four fields kept; the ported `serve_dir` test asserts `port` and `pid` as well as `url`), `pa11y_condition()`, `pa11y_classify_output()`, `pa11y_raw(url, timeout_s = 120L)`; `FINDING_COLS`, `finding_id()`, `finding()`, `AXE_CRITERION` (74 entries), `AXE_NO_WCAG_TAG` (30), `axe_criterion()`, `pa11y_*()`, `from_pa11y()`, `write_findings()`, `read_findings()`, `diff_findings()`, `report_and_dedup()`, `halt_on_collision()`. Exported: `serve_dir`, `pa11y_raw`, `finding`, `write_findings`, `read_findings`, `diff_findings`; the rest internal. `PA11Y_VERSION <- "9.1.1"` stays in `a11y-serve.R`, the one place.
- Edits: delete the `%||%` line in each; delete `suppressPackageStartupMessages(library(...))` lines (Imports cover `jsonlite`, `digest`); `serve_dir()` gains, before spawning, `if (!nzchar(Sys.which("python3"))) stop("python3 is needed to serve pages for the audit; install it")`; `pa11y_raw()` gains `if (!nzchar(Sys.which("npx"))) stop("npx (Node.js) is needed to run pa11y; install Node.js")`. `.axe_unrecognized_warned` stays a package-level environment.

- [ ] **Step 1: Port the tests per the rule** (sections in the map). The pa11y fixture check and the broken-run negative control both begin with `skip_if_no("npx")`.

- [ ] **Step 2: Run to verify failure.** `Rscript -e 'testthat::test_local(filter = "a11y-serve|a11y-model")'`; expected: function-not-found failures.

- [ ] **Step 3: Move the two files** with the edits listed; roxygen on the exported six; `@keywords internal` on the rest that need a page.

- [ ] **Step 4: Verify the two table sizes and the port counts**

```bash
Rscript -e 'pkgload::load_all(quiet=TRUE); stopifnot(length(AXE_CRITERION) == 74L, length(AXE_NO_WCAG_TAG) == 30L)'
Rscript -e 'testthat::test_local(filter = "a11y-serve|a11y-model")'
```
Then the completeness count from the port rule. `Version: 0.2.0.9001`; NEWS line.

- [ ] **Step 5: Propose the commit and stop**

```
Move the audit's serving and finding-model libraries with their tests
```

---

### Task 24: `a11y_targets.R` and `a11y_checks.R`

**Files:**
- Create: `R/a11y-targets.R`, `R/a11y-checks.R`, `tests/testthat/test-a11y-targets.R`, `tests/testthat/test-a11y-checks.R`
- Source: `lib/a11y_targets.R` (514), `lib/a11y_checks.R` (631)

**Interfaces:**
- Produces: all functions unchanged. Exported: `discover_target()`, `intended_surfaces()`, `check_filename_alt()`, `check_missing_fig_alt()`, `check_colour_only()`, `contrast_ratio()`, `suggest_passing_colour()`. `SOURCE_EXCLUDE_RE` keeps `assessments` (spec note 6). `exclude` stays a required argument on both source checks.
- **Byte-level copy of `a11y_checks.R`.** `glob_to_regex()` at snapshot lines 304 to 336 carries the literal bytes 0x01, 0x02, 0x03 as sentinels. Copy with `cp`, never through an editor paste:

```bash
cp project/econ730-toolchain/scripts/lib/a11y_checks.R R/a11y-checks.R
cp project/econ730-toolchain/scripts/lib/a11y_targets.R R/a11y-targets.R
grep -c $'\x01' R/a11y-checks.R   # expected: 2 (one gsub writing it, one restoring it)
```

Then make the edits (delete `%||%`, delete `library()` lines) with `sed -i ''` on those exact lines, not by retyping the file.

- [ ] **Step 1: Port the tests.** The tripwire is ported first and verbatim in meaning:

```r
test_that("exclusion entries are globs, and a literal-only match is a silent no-op", {
  expect_true(exclusion_matches("assets/a/b.qmd", "assets/**"))
  expect_false(exclusion_matches("assetsfoo.qmd", "assets/**"))
  expect_true(exclusion_matches("a.qmd", "*.qmd"))
  expect_false(exclusion_matches("sub/a.qmd", "*.qmd"))
  expect_true(exclusion_matches("lecture_notes/x/y.qmd", "lecture_notes"))
})
```

(plus the rest of section 2794 as written). Section 707 is replaced as the map says.

- [ ] **Step 2: Failure, move, edits, tests, counts.** `Version: 0.2.0.9002`; NEWS line noting the replaced section.

- [ ] **Step 3: Propose the commit and stop**

```
Move target discovery and the source checks, copying the glob sentinels byte for byte
```

---

### Task 25: `a11y_cartridge.R` and `a11y_report.R`

**Files:**
- Create: `R/a11y-cartridge.R`, `R/a11y-report.R`, `tests/testthat/test-a11y-cartridge.R`, `tests/testthat/test-a11y-report.R`
- Source: `lib/a11y_cartridge.R` (668), `lib/a11y_report.R` (810)

**Interfaces:**
- Edits in `a11y-cartridge.R`: `CART_GENERATOR <- "modules.yml or the coursepack cartridge builder"` (finding text only; `fix_target` is not hashed into ids, verify by reading `finding_id()` before believing it); `CARTRIDGE_SEARCH_DIRS` stays the default and `cartridges_in(repo, dirs = CARTRIDGE_SEARCH_DIRS)` gains the argument; `audit_cartridge(imscc_path, surface, video_fetch = default_youtube_fetch)` keeps its required `surface`; `.video_state_cache` stays a package environment; `inventory_media()`'s `bibtex/` exclusion stays with a comment that it is a textbook-repo convention riding along. Exported: `audit_cartridge`, `cartridges_in`, `check_untitled_iframes`, `check_weak_link_text`, `video_caption_state`, `inventory_media`, `classify_fixes`, `render_report`, `render_plan`, `level_for`.
- Replacement for section 947 (the real reference export): a `write_mini_cartridge()` variant in `helper-cartridge.R`, `write_a11y_cartridge(zip_path)`, that writes two wiki pages (`<iframe src="x"></iframe>` untitled; `<iframe title="Syllabus" src="y"></iframe>`), one weblink whose title is `click here`, and one YouTube embed; the test asserts exactly one untitled-iframe finding, one weak-link finding, and that `attr(res, "wiki_pages_read") == 2L`.

- [ ] **Step 1: Port the tests; write the replacement.**
- [ ] **Step 2: Failure, move, edits, tests, counts.** `Version: 0.2.0.9003`.
- [ ] **Step 3: Propose the commit and stop**

```
Move the cartridge audit and the report renderer with their tests
```

---

### Task 26: `audit_course()`, the driver

**Files:**
- Create: `R/a11y.R`, `tests/testthat/test-a11y-driver.R`
- Source: `audit_a11y.R` (388)

**Interfaces:**
- Produces, exported: `audit_course(repos, proj = ".", out_dir = file.path(proj, "project", "accessibility"), port = 8766L, cartridge_dirs = c("build/coursepack", "reference"), video_fetch = default_youtube_fetch)` returning `invisible(list(findings = <data.frame>, meta = <list>, files = <character>))`. The body is the script from `halt_on_surface_collision(args)` down, with `args` replaced by `repos`, `outdir` by `out_dir`, `cartridges_in(repo)` by `cartridges_in(repo, cartridge_dirs)`, `serve_dir(tgt$output_dir, port = 8766L)` by `port`, and `audit_cartridge(z, surface = cart_surface)` gaining `video_fetch`. Every comment stays, above all the C1 block on the two coverage signals. `getenv_or()` and the `source()` loop go. Empty `repos` stops with the script's usage text. The closing console block prints the version line last.

- [ ] **Step 1: Port the driver-level sections (2002, 2175, 2334, 2474)** and add:

```r
test_that("audit_course refuses no repos and refuses two repos with one basename before serving anything", {
  expect_error(audit_course(character()), "no repo is assumed")
  a <- fixture_path("pair", "alpha"); b <- fixture_path("pair", "other", "alpha")
  expect_error(audit_course(c(a, b), out_dir = withr::local_tempdir()), "same surface")
})
```

- [ ] **Step 2: Failure, move, tests.** Then the manual coverage tripwire the spec requires: comment out the cartridge loop in `R/a11y.R`, run `audit_course(fixture_path("pair", "alpha"), out_dir = tempdir())` with `npx` available, confirm `*** SHORTFALL ***` prints, restore the loop, confirm the file is byte-identical to the committed version (`git diff --stat R/a11y.R` empty). Record the result in the commit message. `Version: 0.2.0.9004`.

- [ ] **Step 3: Propose the commit and stop**

```
Move the audit driver as audit_course(); repos, output and port are arguments
```

---

### Task 27: The pa11y integration test

**Files:**
- Create: `tests/testthat/test-a11y-integration.R`, `tests/testthat/fixtures/pair/alpha/site/bad.html`, `tests/testthat/fixtures/pair/alpha/_quarto.yml`

- [ ] **Step 1: Write the fixture page and the test**

`bad.html`: `<html><head><title>Bad</title></head><body><img src="chart1.png" alt="chart1.png"><p><a href="x.html">click here</a></p></body></html>` (no `lang`, filename-as-alt, weak link). `_quarto.yml`: `project:\n  type: website\n  output-dir: site\n`.

```r
test_that("a real pa11y run against the fixture finds the planted defects with both runners", {
  skip_if_no("npx"); skip_if_no("python3")
  skip_if(!nzchar(Sys.getenv("COURSEPACK_PA11Y_TESTS")), "set COURSEPACK_PA11Y_TESTS=1 to run pa11y (downloads Chromium on first use)")
  out <- withr::local_tempdir()
  res <- audit_course(fixture_path("pair", "alpha"), proj = out, out_dir = out, port = 8794L)
  df <- res$findings
  expect_setequal(unique(df$source), c("pa11y", "custom"))
  expect_true(any(df$criterion == "1.1.1" & grepl("filename", df$issue, ignore.case = TRUE)))
  expect_true(any(df$criterion == "3.1.1"))
  expect_length(list.files(out, pattern = "-findings\\.json$"), 1L)
})
```

- [ ] **Step 2: Run it once for real** with `COURSEPACK_PA11Y_TESTS=1`; expected pass on the authoring machine. Without the variable it skips with the stated reason. `Version: 0.2.0.9005`.

- [ ] **Step 3: Propose the commit and stop**

```
Add the pa11y integration test, opt-in by environment variable
```

---

### Task 28: Announcement bodies as an audit surface

**Files:**
- Modify: `R/a11y-cartridge.R` (`audit_cartridge()`), `tests/testthat/test-a11y-cartridge.R`, `tests/testthat/helper-cartridge.R`

**Interfaces:**
- `audit_cartridge()` also reads every `imsdt_xmlv1p1` topic's `<text texttype="text/html">` body (XML-unescaped), writes each to a temp `.html`, and runs `check_untitled_iframes()` and `check_weak_link_text()`-equivalent rules over it with `file = "<topic id>.xml"` and `fix_target = "the announcement body file"`. Returns `attr(res, "topics_read")` beside `wiki_pages_read`. A new-coverage change, so finding counts on a real course rise; recorded in NEWS as such.

- [ ] **Step 1: Test**

```r
test_that("a topic body with a bare-URL link produces one 2.4.4 finding, attributed to the body file", {
  skip_if_no("zip")
  z <- write_a11y_cartridge(tempfile(fileext = ".imscc"),
         topics = list(list(id = "gtopic1", title = "Week 1", html = '<p>See <a href="https://example.invalid/x">https://example.invalid/x</a></p>')))
  res <- audit_cartridge(z, surface = "t-cartridge",
                         video_fetch = function(id) unavailable_page)
  hit <- res[res$criterion == "2.4.4" & res$file == "gtopic1.xml", ]
  expect_equal(nrow(hit), 1L)
  expect_equal(attr(res, "topics_read"), 1L)
})
```

- [ ] **Step 2: Extend `write_a11y_cartridge()` with a `topics` argument and implement.** `Version: 0.2.0.9006`; NEWS: "The cartridge audit reads announcement bodies; counts on a course with announcements rise."

- [ ] **Step 3: Propose the commit and stop**

```
Audit announcement bodies inside the cartridge
```

**Phase 3 close.** Suite green; check clean with pa11y tests skipping; `stringr` NOTE closed. `Version: 0.3.0`. Appendix A's Phase 3 block: the real-run diff against `project/accessibility/2026-09-01-findings.json` and the deletion list, both in the ECON 730 repo. Propose `Close phase 3: the accessibility audit is in the package`.

# Phase 4: Carry, extract, generate, print

The Python builder's capabilities arrive here, in R, against synthetic fixtures. Exam pools (M11) are not ported: ECON 202 retired `exam_pools` on 2026-09-04 and both exams are generated from banks, so the arithmetic has no consumer. Every review finding in builder-merge section 5 that touches ported code has a test here written to fail against the Python behaviour.

Fixture changes in this phase: `copy_course()` (Task 29) also zips `fixtures/src/` into `<course>/reference/source.imscc`, and `tools/baseline.R` does the same, so every build of the fixture has a source cartridge to carry from.

### Task 29: The source cartridge fixture and the carry core

**Files:**
- Create: `R/cartridge-carry.R`, `tests/testthat/test-carry.R`, `tests/testthat/fixtures/src/` (files below)
- Modify: `R/cartridge-items.R`, `R/cartridge-xml.R` (`write_manifest()`), `R/cartridge-checks.R`, `R/cartridge.R`, `tests/testthat/helper-fixtures.R`, `tools/baseline.R`, fixture `modules.yml`, fixture `reference.yml` (new)
- Regenerate the expected tree.

**Interfaces:**
- Schema (builder-merge 3.2): a `pages:`, `assignments:`, or `quizzes:` definition may carry `source_ref: g<hex>` and then no other body key (`iframe`, `body`, `homework`, `quiz_file`, `todo`, `qti`, `bank`, `description`); `title:` is required. `reference.yml` `source:` names the cartridge (defaults to `export:`). Any `source_ref` with neither key stops naming the definition.
- Produces: `read_source_cartridge(path)` returning `list(zip, names, resources)` where `resources` is a named list by identifier of `list(raw, type, href, files, deps, self_closing)`; the manifest is parsed with `xml2` to find each `<resource>` node and its attributes, and the raw text span is taken from the manifest text between the node's opening tag (located by `identifier="<id>"`) and its own `</resource>` or `/>`. `carry_resources(defs, src, stage)` walks `deps` from each `source_ref`, writes every declared file's bytes into `stage` unchanged, and returns `list(raw = <character of resource spans in walk order>, carried = <ids>, files = <paths>)`; a `source_ref` absent from the source stops `"definition '<id>' carries source_ref <ref>, which is not in <source>"`; a declared file absent from the zip stops. **Path validation before any write** (the Python it ports joins archive names straight under staging): `carry_resources()` first completes the dependency walk for every `source_ref` and collects every declared `href` and `<file href>`; it then runs `safe_stage_path(stage, href)` over the whole collected set, and only when every path passes does it write any bytes. A path that is absolute, contains a `..` segment, contains a backslash, or whose normalized destination is not inside `stage` stops `"source cartridge declares an unsafe path: <href>"` with nothing staged from the source. `safe_stage_path()` returns the destination path; the write loop uses the returned paths, never the raw hrefs.
- Module items for carried definitions use the same emitter: page becomes `WikiPage` with idref `resource_id %||% source_ref`; assignment `Assignment`; quiz `Quizzes::Quiz` with `new_tab` empty.
- `write_manifest()` appends the carried raw spans after the generated resources, in walk order.
- Pre-zip extensions: every file a carried `<resource>` declares exists in staging (the existing declared-vs-on-disk check covers it once the spans are in the manifest); carried resource ids unique across the manifest (`"carried resource <id> declared twice"`); every `assignment_group_identifierref` inside a carried `assignment_settings.xml` or `assessment_meta.xml` names a declared group id (`"carried <file> references assignment group <id>, which course.yml does not declare"`).
- Output changes: `extra:` every carried file and `changed:` `imsmanifest.xml`, `course_settings/module_meta.xml` (a third module).

- [ ] **Step 1: Write the fixture cartridge tree**

`tests/testthat/fixtures/src/` holds an unzipped synthetic Canvas export. Identifiers (all `g` plus 32 hex):

| Id | What |
|---|---|
| `g00000000000000000000000000000c01` | wiki page `wiki_content/carried-page.html`: `<html><head><title>Carried Page</title><meta name="identifier" content="g00000000000000000000000000000c01"/><meta name="editing_roles" content="teachers"/><meta name="workflow_state" content="active"/></head><body><p>Hand-written in Canvas.</p><table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table></body></html>` |
| `g00000000000000000000000000000c02` | wiki page `wiki_content/wrapper-page.html`: exactly the Task 17 template with `title="Wrapped"`, `src="https://example.invalid/course/wrapped.html"`, `height="1200px"` and nothing else in the body |
| `g00000000000000000000000000000a01` | assignment dir `g...a01/carried-assignment.html` (a body) and `g...a01/assignment_settings.xml` with `<title>Old Assignment Title</title>`, `<due_at>2025-02-01T05:59:59</due_at>`, `<all_day_date>2025-01-31</all_day_date>`, `<assignment_group_identifierref>g0000000000000000000000000000000b</assignment_group_identifierref>`, `<workflow_state>published</workflow_state>`, `<points_possible>10.0</points_possible>` |
| `g00000000000000000000000000000q01` | quiz: `g...q01/assessment_qti.xml` (empty root_section stub), depends on `g00000000000000000000000000000m01` |
| `g00000000000000000000000000000m01` | LAR href `g...q01/assessment_meta.xml` (with two `<title>Old Quiz Title</title>` elements, outer `<due_at/>` empty, nested `<assignment identifier="g...s01">` with `<due_at></due_at>`, `<all_day_date></all_day_date>`, group ref `g...0b`, `<description>&lt;p&gt;&lt;strong&gt;Read this first&lt;/strong&gt;&lt;/p&gt;&lt;p&gt;Then answer.&lt;/p&gt;</description>`) and file `non_cc_assessments/g...q01.xml.qti` with two groups inside `root_section`, each with two items |
| `g00000000000000000000000000000b01` | LAR `non_cc_assessments/g...b01.xml.qti`, an `<objectbank>`; referenced by nothing |
| `g00000000000000000000000000000e01` | a self-closing `<resource identifier="g...e01" type="webcontent" href="wiki_content/empty.html"/>` with no `<file>` child (review 19); the file exists and is empty |

Plus `course_settings/course_settings.xml` (`<title>Source Course</title>`, `<course_code>SRC 100</course_code>`, `is_public false`, `default_view modules`, `group_weighting_scheme percent`, `grading_standard_enabled false`, `allow_student_wiki_edits false`), `course_settings/assignment_groups.xml` (one group `g0000000000000000000000000000000b` "Quizzes" position 1 weight 100.0), `course_settings/module_meta.xml` (one module "Source Module", items: `WikiPage` Carried Page idref c01, `WikiPage` Wrapped idref c02, `Assignment` Old Assignment Title idref a01, `Quizzes::Quiz` Old Quiz Title idref q01, `ContextModuleSubHeader` "A header", `ExternalUrl` "Outside" with `<url>https://example.invalid/out</url>` and identifierref `g00000000000000000000000000000w01`), a weblink `g...w01.xml`, `course_settings/canvas_export.txt`, and `imsmanifest.xml` declaring all of it with the CC 1.1.0 header (copy the header block from `R/cartridge-xml.R`'s `write_manifest()`).

Helper additions in `helper-fixtures.R`:

```r
zip_fixture_source <- function(course_dir) {
  src <- fixture_path("src")
  dir.create(file.path(course_dir, "reference"), showWarnings = FALSE)
  zipf <- normalizePath(file.path(course_dir, "reference", "source.imscc"), mustWork = FALSE)
  old <- setwd(src); on.exit(setwd(old), add = TRUE)
  utils::zip(zipf, list.files(".", recursive = TRUE), flags = "-q -X")
  zipf
}
```

and `copy_course()` calls `zip_fixture_source()` after copying when `zip` is available (`if (nzchar(Sys.which("zip")))`). `tools/baseline.R` zips it the same way.

Fixture course additions. `reference.yml`: `source: reference/source.imscc`. `modules.yml`: a third module

```yaml
  - title: "Module 3: Carried"
    published: true
    items:
      - page: carried-page
      - assignment: carried-asg
      - quiz: carried-quiz
```

and definitions `- slug: carried-page` `title: Carried Page` `source_ref: g00000000000000000000000000000c01`; `- id: carried-asg` `title: Carried Assignment` `published: true` `source_ref: g00000000000000000000000000000a01`; `- id: carried-quiz` `title: Carried Quiz` `published: true` `source_ref: g00000000000000000000000000000q01`. No `due:` yet (Task 30 adds them).

- [ ] **Step 2: Write the failing tests**

```r
# tests/testthat/test-carry.R
test_that("read_source_cartridge parses every resource, including a self-closing one, with files and deps", {
  skip_if_no("zip")
  p <- copy_course(); src <- read_source_cartridge(file.path(p, "reference", "source.imscc"))
  r <- src$resources
  expect_true("g00000000000000000000000000000e01" %in% names(r))
  expect_true(r[["g00000000000000000000000000000e01"]]$self_closing)
  expect_equal(r[["g00000000000000000000000000000q01"]]$deps, "g00000000000000000000000000000m01")
  expect_setequal(r[["g00000000000000000000000000000m01"]]$files,
                  c("g00000000000000000000000000000q01/assessment_meta.xml", "non_cc_assessments/g00000000000000000000000000000q01.xml.qti"))
  expect_match(r[["g00000000000000000000000000000q01"]]$raw, "^<resource identifier=\"g00000000000000000000000000000q01\"")
})

test_that("carried files are byte-identical to the source, the objectbank is dropped, module items point at the carried ids", {
  b <- built()
  src <- fixture_path("src")
  for (f in c("g00000000000000000000000000000q01/assessment_meta.xml",
              "non_cc_assessments/g00000000000000000000000000000q01.xml.qti",
              "g00000000000000000000000000000q01/assessment_qti.xml",
              "wiki_content/carried-page.html",
              "g00000000000000000000000000000a01/assignment_settings.xml"))
    expect_identical(unname(tools::md5sum(file.path(b$stage, f))), unname(tools::md5sum(file.path(src, f))), info = f)
  expect_false(file.exists(file.path(b$stage, "non_cc_assessments", "g00000000000000000000000000000b01.xml.qti")))
  expect_match(b$mm, "<identifierref>g00000000000000000000000000000c01</identifierref>", fixed = TRUE)
  expect_match(b$man, 'identifier="g00000000000000000000000000000m01"', fixed = TRUE)
})

test_that("a source_ref not in the source, a missing source:, and a carried group the course does not declare all stop", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  edit_yaml(p, "modules.yml", "source_ref: g00000000000000000000000000000c01", "source_ref: g00000000000000000000000000000fff")
  expect_error(build_cartridge(p), "carries source_ref g00000000000000000000000000000fff, which is not in")
  edit_yaml(p, "modules.yml", "source_ref: g00000000000000000000000000000fff", "source_ref: g00000000000000000000000000000c01")
  unlink(file.path(p, "reference.yml"))
  expect_error(build_cartridge(p), "carried-page.*needs reference.yml with source: or export:")
  writeLines("source: reference/source.imscc", file.path(p, "reference.yml"))
  edit_yaml(p, "course.yml", "    id: g0000000000000000000000000000000b", "    id: g0000000000000000000000000000000c")
  expect_error(build_cartridge(p), "references assignment group g0000000000000000000000000000000b, which course.yml does not declare")
})

test_that("a definition with source_ref and a body key is refused", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  edit_yaml(p, "modules.yml", "    source_ref: g00000000000000000000000000000c01", "    source_ref: g00000000000000000000000000000c01\n    body: true")
  expect_error(build_cartridge(p), "carried-page.*source_ref and body")
})

test_that("a source cartridge that declares an unsafe path is refused before anything is written", {
  skip_if_no("zip")
  st <- withr::local_tempdir()
  expect_error(safe_stage_path(st, "../evil.html"), "unsafe path: ../evil.html")
  expect_error(safe_stage_path(st, "/etc/passwd"), "unsafe path")
  expect_error(safe_stage_path(st, "a/../../b.html"), "unsafe path")
  expect_error(safe_stage_path(st, "a\\b.html"), "unsafe path")
  expect_equal(safe_stage_path(st, "wiki_content/ok.html"), file.path(st, "wiki_content", "ok.html"))
  # A whole cartridge carrying one bad href, placed on the LAST file the walk
  # reaches: the quiz meta's pooling file, which sits behind a <dependency>
  # edge from the last carried definition. Per-write validation would have
  # staged the page and the assignment before reaching it; whole-walk
  # validation stages nothing. The test tells the two apart.
  p <- copy_course(); zip_fixture_qti(p)
  src <- fixture_path("src"); d <- withr::local_tempdir(); file.copy(src, d, recursive = TRUE)
  man <- file.path(d, "src", "imsmanifest.xml")
  m <- readLines(man)
  bad <- sub('<file href="non_cc_assessments/g00000000000000000000000000000q01.xml.qti"/>',
             '<file href="../g00000000000000000000000000000q01.xml.qti"/>', m, fixed = TRUE)
  expect_false(identical(bad, m))
  writeLines(bad, man)
  old <- setwd(file.path(d, "src")); utils::zip(file.path(p, "reference", "source.imscc"), list.files(".", recursive = TRUE), flags = "-q -X"); setwd(old)
  expect_error(build_cartridge(p), "unsafe path: ../g00000000000000000000000000000q01.xml.qti")
  expect_false(file.exists(file.path(p, "build", "coursepack", "g00000000000000000000000000000q01.xml.qti")))
  st <- file.path(p, "build", "coursepack", "staging")
  for (f in c("wiki_content/carried-page.html",
              "g00000000000000000000000000000a01/assignment_settings.xml",
              "g00000000000000000000000000000a01/carried-assignment.html",
              "g00000000000000000000000000000q01/assessment_qti.xml",
              "g00000000000000000000000000000q01/assessment_meta.xml"))
    expect_false(file.exists(file.path(st, f)), info = f)
})
```

- [ ] **Step 3: Implement.** `R/cartridge-carry.R` as specified. In `resolve_items()`, a carried definition's resource id is `check_gid(def$resource_id) %||% def$source_ref`. In `build_cartridge()`, after the generated writers: `if (any_source_ref(m)) { src <- read_source_cartridge(source_path(ref, proj)); carried <- carry_resources(carried_defs(m), src, stage) }`. `write_manifest()` takes `carried$raw`. `write_wiki_pages()`, `write_assignments()`, `embed_quiz()` skip carried definitions. The definition-shape check (`source_ref` plus a body key) lives in `read_manifest()` so the checker sees it too.

- [ ] **Step 4: Regeneration procedure.** Expected: `extra:` the six carried files the walk reaches (c01, a01's two, q01's one, m01's two; c02, e01, b01 and w01 are in the fixture on purpose and nothing carries them) and `changed:` `imsmanifest.xml`, `course_settings/module_meta.xml`. The fixture directory is `fixtures/src/` (a three-letter name: its Canvas-shaped paths, a 33-character identifier under `non_cc_assessments/`, reach 99 bytes in the tarball against the 100-byte limit R CMD check enforces). `Version: 0.3.0.9001`; NEWS: "Carry-through: `source_ref` on any definition, bytes from `reference.yml`'s `source:`."

- [ ] **Step 5: Propose the commit and stop**

```
Carry resources through from a source cartridge by source_ref; the cartridge was supposed to change
```

---

### Task 30: Carried titles and dates

**Files:**
- Modify: `R/cartridge-carry.R` (`sync_carried_titles()`, `apply_carried_dates()`), fixture `modules.yml` (two `due:` values), `tests/testthat/test-carry.R`
- Regenerate the expected tree.

**Interfaces:**
- `sync_carried_titles(carried, defs, stage)`: for each carried assignment or quiz definition, rewrite the first `<title>` in `assignment_settings.xml` and in the carried HTML, and **both** `<title>` elements in `assessment_meta.xml` (outer quiz and nested assignment; review 18) to `xesc(def$title)`; comparison is on the unescaped text (review 4). Returns the count of files changed. Wiki page titles are not touched (the page's `<title>` is what Canvas shows and a carried page has no YAML title to push).
- `apply_carried_dates(carried, defs, stage, course, tz)`: for a carried assignment or quiz with `due:`, rewrite `<due_at>...</due_at>` and `<due_at/>` (review 5) to `due_stamp(due, course$due_time, tz)` and `<all_day_date>`/`<all_day_date/>` to the local date, in `assignment_settings.xml` or in **both** places in `assessment_meta.xml`; without `due:`, blank them to `<due_at></due_at>` and `<all_day_date></all_day_date>` (never inherit a stale date); a `due:` that rewrites nothing stops `"definition '<id>' has due: but its carried file has no due_at to rewrite"` (review 13). Returns `list(dated, blanked)`.
- Order: titles, then dates (3.3). Both operate on carried files only.
- Output changes: `g...a01/assignment_settings.xml`, `g...a01/carried-assignment.html`, `g...q01/assessment_meta.xml`.

- [ ] **Step 1: Tests**

```r
test_that("carried titles follow the definition in every title slot, and dates come from due: or are blanked", {
  b <- built()
  meta <- paste(readLines(file.path(b$stage, "g00000000000000000000000000000q01", "assessment_meta.xml")), collapse = "\n")
  expect_length(gregexpr("<title>Carried Quiz</title>", meta, fixed = TRUE)[[1]], 2L)
  expect_no_match(meta, "Old Quiz Title")
  expect_length(gregexpr("<due_at>2026-10-03T04:59:59</due_at>", meta, fixed = TRUE)[[1]], 2L)
  expect_match(meta, "<all_day_date>2026-10-02</all_day_date>", fixed = TRUE)
  st <- paste(readLines(file.path(b$stage, "g00000000000000000000000000000a01", "assignment_settings.xml")), collapse = "\n")
  expect_match(st, "<title>Carried Assignment</title>", fixed = TRUE)
  expect_match(st, "<due_at>2026-10-02T04:59:59</due_at>", fixed = TRUE)
})

test_that("a carried date is blanked when the definition has no due:, and a due: with nothing to rewrite stops", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  edit_yaml(p, "modules.yml", "    due: 2026-10-01\n    source_ref: g00000000000000000000000000000a01", "    source_ref: g00000000000000000000000000000a01")
  res <- build_cartridge(p)
  st <- paste(readLines(file.path(res$stage, "g00000000000000000000000000000a01", "assignment_settings.xml")), collapse = "\n")
  expect_match(st, "<due_at></due_at>", fixed = TRUE); expect_no_match(st, "2025-02-01")
  edit_yaml(p, "modules.yml", "    source_ref: g00000000000000000000000000000c01", "    due: 2026-10-05\n    source_ref: g00000000000000000000000000000c01")
  expect_error(build_cartridge(p), "has due: but its carried file has no due_at")
})
```

Fixture: `carried-asg` gains `due: 2026-10-01`; `carried-quiz` gains `due: 2026-10-02`.

- [ ] **Step 2: Implement; regeneration procedure.** Expected `changed:` the three files above. `Version: 0.3.0.9002`; NEWS line.

- [ ] **Step 3: Propose the commit and stop**

```
Sync carried titles and rewrite carried due dates from YAML; the cartridge was supposed to change
```

---

### Task 31: `repair_carried_html()`

**Files:**
- Modify: `R/cartridge-carry.R`, `R/config.R` (read `course$carry$repair_html`), `tests/testthat/test-carry.R`
- Regenerate the expected tree.

**Interfaces:**
- `repair_carried_html(carried, stage)`: on carried `.html` files, every `<th>` without `scope` gets `scope="col"` in the first row of its table and `scope="row"` afterwards (no `<thead>` insertion, for the reason the Python comment gives); on carried `.xml` files, inside each `<description>` (unescaped, repaired, re-escaped without quote escaping), a leading `<p><strong>X</strong></p>` becomes `<h2>X</h2>` once, and tables get scope the same way. Returns `list(th = <n>, headings = <n>)`, printed. Controlled by `course$carry$repair_html`, default `TRUE`; `FALSE` leaves carried bytes untouched.
- Output changes: `wiki_content/carried-page.html`, `g...q01/assessment_meta.xml`.

- [ ] **Step 1: Tests**

```r
test_that("carried tables gain scope and a leading bold paragraph becomes a heading; generated pages are untouched; the switch turns it off", {
  b <- built()
  cp <- paste(readLines(file.path(b$stage, "wiki_content", "carried-page.html")), collapse = "\n")
  expect_match(cp, '<th scope="col">A</th><th scope="col">B</th>', fixed = TRUE)
  meta <- paste(readLines(file.path(b$stage, "g00000000000000000000000000000q01", "assessment_meta.xml")), collapse = "\n")
  expect_match(meta, "&lt;h2&gt;Read this first&lt;/h2&gt;", fixed = TRUE)
  gen <- paste(readLines(file.path(b$stage, "wiki_content", "chapter-one.html")), collapse = "\n")
  expect_identical(gen, paste(readLines(file.path(b$stage, "wiki_content", "chapter-one.html")), collapse = "\n"))
  p <- b$p; edit_yaml(p, "course.yml", "due_time: \"23:59:59\"", "due_time: \"23:59:59\"\ncarry:\n  repair_html: false")
  build_cartridge(p)
  cp2 <- paste(readLines(file.path(b$stage, "wiki_content", "carried-page.html")), collapse = "\n")
  expect_no_match(cp2, 'scope="col"')
})
```

The "generated pages untouched" assertion is strengthened by adding a table to `content/canvas/chapter-one.html` without `scope` and asserting it stays without: add `<table><tr><th>X</th></tr></table>` to the fixture body and `expect_no_match(gen, 'scope=')`. That changes `wiki_content/chapter-one.html` too (fixture edit), so it is in this task's output list.

- [ ] **Step 2: Implement; regeneration procedure.** Expected `changed:` the three files. `Version: 0.3.0.9003`; NEWS line.

- [ ] **Step 3: Propose the commit and stop**

```
Repair carried HTML on the way into the cartridge, scoped and switchable
```

---

### Task 32: `extract_manifest()`

**Files:**
- Create: `R/extract.R`, `tests/testthat/test-extract.R`

**Interfaces:**
- Produces, exported: `extract_manifest(imscc, out_dir, overwrite = FALSE)` returning `invisible(out_dir)`. Writes `course.yml`, `modules.yml`, `reference.yml` in the package schema and copies the export to `<out_dir>/reference/<basename>`. Refuses when any of the three exists unless `overwrite = TRUE` (the Python extractor's "destroyed those edits twice" comment, kept as the reason in the roxygen).
- `course.yml`: `code` and `canvas.course_code` from `<course_code>`, `title`, `urls.site` (the longest common prefix of every iframe target, truncated at the last `/`, review 10; `""` when no iframe page), `textbook_docs: none`, a `term:` block with `timezone: null` and the comment `# set this; every due: and announcement is read in it`, `canvas:` holding every key in `CANVAS_SETTINGS_KEYS` present in `course_settings.xml` (one shared list, review 12), `assignment_groups` with `id`, `position`, `weight`. `due_time` is not written (no `due:` is written).
- `modules.yml`: each module with `module_id`, `title`, `published`, `sequential`; each item as the keyed form with `item_id`, `indent`, `published`: `ContextModuleSubHeader` becomes `header:`; `ExternalUrl` becomes `link:` with `url:`; `WikiPage` becomes `page: <slug>` where the slug is the href stem; `Assignment` becomes `assignment: <slug>`; `Quizzes::Quiz` becomes `quiz: <slug>`, slugs from `slugify(title)` made unique by stopping on a duplicate (review 16). Definitions: a wiki page whose body is exactly the Task 17 template (whitespace-normalized) and nothing else becomes `iframe:` with `src`, `width`, `height`, and `title` (review 9); any other page becomes `source_ref:` with `title:`; every assignment and quiz becomes `source_ref:` with `title:` and `published:` from the item state. `height_measured` is never written.
- `reference.yml`: `export: reference/<basename>` and `source: reference/<basename>`.
- Announcements, grading standards, late policy, LTI: not extracted (E8); printed as counts under "not extracted".

- [ ] **Step 1: Tests**

```r
# tests/testthat/test-extract.R
extracted <- function() {
  skip_if_no("zip")
  to <- withr::local_tempdir(.local_envir = parent.frame())
  p <- copy_course(to = to); out <- withr::local_tempdir(.local_envir = parent.frame())
  extract_manifest(file.path(p, "reference", "source.imscc"), out)
  out
}

test_that("extract writes three files the package can read, and copies the export", {
  out <- extracted()
  expect_true(all(file.exists(file.path(out, c("course.yml", "modules.yml", "reference.yml", "reference/source.imscc")))))
  m <- read_manifest(out)
  expect_equal(m$course$code, "SRC 100"); expect_equal(m$course$urls$site, "https://example.invalid/course")
  expect_equal(m$course$assignment_groups[[1]]$id, "g0000000000000000000000000000000b")
  expect_equal(read_reference(out)$source, "reference/source.imscc")
})

test_that("a pure wrapper page becomes iframe:, everything else becomes source_ref:", {
  out <- extracted(); m <- read_manifest(out)
  w <- m$pages[["wrapper-page"]]; expect_equal(w$iframe, "https://example.invalid/course/wrapped.html"); expect_equal(w$height, "1200px"); expect_null(w$source_ref)
  cp <- m$pages[["carried-page"]]; expect_equal(cp$source_ref, "g00000000000000000000000000000c01"); expect_null(cp$iframe)
  expect_equal(m$assignments[["old-assignment-title"]]$source_ref, "g00000000000000000000000000000a01")
  expect_equal(m$quizzes[["old-quiz-title"]]$source_ref, "g00000000000000000000000000000q01")
  forms <- vapply(m$mods$modules[[1]]$items, function(it) intersect(c("header", "page", "link", "assignment", "quiz"), names(it))[1], "")
  expect_equal(forms, c("page", "page", "assignment", "quiz", "header", "link"))
  expect_equal(m$mods$modules[[1]]$items[[6]]$url, "https://example.invalid/out")
  expect_null(w$height_measured)
})

test_that("extract never overwrites unless told", {
  out <- extracted()
  p <- copy_course()
  expect_error(extract_manifest(file.path(p, "reference", "source.imscc"), out), "already exist")
  expect_no_error(extract_manifest(file.path(p, "reference", "source.imscc"), out, overwrite = TRUE))
})

test_that("the site URL is a directory, never a truncated segment", {
  skip_if_no("zip")
  d <- withr::local_tempdir()
  z <- write_a11y_cartridge(file.path(d, "c.imscc"), pages = list(
    list(slug = "a", title = "A", src = "https://example.invalid/pages/ch01/CH01.html"),
    list(slug = "b", title = "B", src = "https://example.invalid/pages/ch02/CH02.html")))
  out <- file.path(d, "out"); extract_manifest(z, out)
  expect_equal(read_course(out)$urls$site, "https://example.invalid/pages")
})
```

(`write_a11y_cartridge()` gains a `pages` argument writing wrapper-template pages plus a minimal `course_settings/`, `assignment_groups.xml`, and `module_meta.xml`, so it can stand in for an export.)

- [ ] **Step 2: Implement `R/extract.R`.** YAML is written with `yaml::write_yaml()` after building lists, then the two comment headers are prepended by `writeLines(c(header, yaml_text))`; `yaml::write_yaml` quotes strings that need it. Booleans come through as `true`/`false`. `Version: 0.3.0.9004`; NEWS: "`extract_manifest()`: a Canvas export becomes `course.yml`, `modules.yml`, `reference.yml` in the package schema."

- [ ] **Step 3: Propose the commit and stop**

```
Add extract_manifest(), the R port of the export extractor, writing the package schema
```

---

### Task 33: The synthetic round trip

**Files:**
- Create: `tests/testthat/test-roundtrip.R`

- [ ] **Step 1: Write the test**

```r
test_that("build, extract, build reproduces the staging tree", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  # Announcements, the grading standard and the late policy are not extracted
  # (decision E8), so they are removed from the source before the first build.
  unlink(file.path(p, "announcements.yml"))
  y <- readLines(file.path(p, "course.yml"))
  cut <- function(y, start) { i <- grep(start, y); j <- i; while (j < length(y) && grepl("^  ", y[j + 1])) j <- j + 1; y[-(i:j)] }
  y <- cut(y, "^grading_standard:"); y <- cut(y, "^late_policy:")
  writeLines(sub("grading_standard_enabled: true", "grading_standard_enabled: false", y), file.path(p, "course.yml"))
  one <- build_cartridge(p)
  h1 <- tree_hashes(one$stage)
  out <- withr::local_tempdir()
  extract_manifest(one$imscc, out)
  two <- build_cartridge(out)
  h2 <- tree_hashes(two$stage)
  expect_identical(h2, h1)
})
```

- [ ] **Step 2: Run.** Expected: identical trees. If they differ, the difference is a schema-symmetry bug in `extract_manifest()` or the builder, not a reason to loosen the test. Known candidates: an attribute order in a regenerated wrapper page (the extractor must reproduce `width` before `height`), a group weight format, a module `sequential` default. What the first run actually found (12 of 29 files), and the fixes that closed them: the two whole-course identifiers (`course_id:` and `manifest_id:` overrides in `course.yml`, written by the extractor from the export); `new_tab:` on link items never read back; exported `<due_at>` values not extracted (now `due:` under `term: timezone: UTC`); `all_day_date:` on carried definitions; blanking rewrote `<due_at/>` to the paired form; `sync_carried_titles()` stripped the `Assignment: ` prefix; and carried `<resource>` blocks were appended after the generated ones rather than written in their definition's slot. That last fix is the one deliberate output change of this task: `imsmanifest.xml` reorders the carried blocks (a pure reordering; the frozen hash is reproduced by moving them back), so the expected tree is regenerated with that one hash and the commit message names it. The extractor also writes `carry: repair_html: false` so the first rebuild reproduces the export. `Version: 0.3.0.9005`; NEWS line.

- [ ] **Step 3: Propose the commit and stop**

```
Prove extract and build are inverses on the synthetic course
```

---

### Task 34: The question bank reader and its checks

**Files:**
- Create: `R/bank.R`, `tests/testthat/test-bank.R`, `tests/testthat/fixtures/bank/chapter_01.json`, `tests/testthat/fixtures/bank/chapter_02.json`, `tests/testthat/fixtures/bank/images/CH01_Q002.png`

**Interfaces:**
- Schema (from the ECON 202 README section 3 and `generate_resources.py`'s docstring): `{chapter, title, source, sections: [{section, questions: [{id, type, difficulty, objective, question, options: {A: .., B: .., ...}, answer, explanation, image, figure: {file, script, alt}}]}]}`.
- Produces, exported: `read_bank(dir, chapter)`: parses `<dir>/chapter_<NN>.json`, stops `"question bank <path> does not exist"`. `check_question(q, where)`: `type` is `multiple_choice` (default when absent), at least two options, `answer` names an option; stops with `where` prefixed. `check_bank(bank, images_dir)`: every question passes; ids unique within the chapter; every `image` exists under `images_dir`; returns `list(warnings = <character>)` where a figure without `alt` is a warning naming the item. Exported so the bank-authoring skill (Task 42) can call it.

- [ ] **Step 1: Write the fixture banks and the test**

`chapter_01.json`: chapter 1, title "Sample Chapter One", two sections ("1.1 First Ideas", "1.2 Second Ideas"), three questions each with ids 1 to 6, one (`id 2`) carrying `"image": "CH01_Q002.png", "figure": {"file": "CH01_Q002.png", "script": "CH01_Q002.py", "alt": "A rising line from left to right."}`, one (`id 4`) whose `question` is `"Use the table.<br><table><tr><th>x</th><th>y</th></tr><tr><td>1</td><td>2</td></tr></table>"`, explanations ending with the section number. `chapter_02.json`: chapter 2, title "Sample Chapter Two", one section named "Sample Chapter Two" (Task 35's ordering test expects the chapter's own name) with four questions ids 1 to 4. The PNG: `Rscript -e 'png("tests/testthat/fixtures/bank/images/CH01_Q002.png", 8, 8); par(mar=c(0,0,0,0)); plot.new(); dev.off()'`.

```r
# tests/testthat/test-bank.R
test_that("read_bank loads a chapter and refuses a missing one", {
  b <- read_bank(fixture_path("bank"), 1)
  expect_equal(b$chapter, 1L); expect_length(b$sections, 2L)
  expect_error(read_bank(fixture_path("bank"), 9), "does not exist")
})

test_that("check_question refuses the three malformed shapes with the location in the message", {
  ok <- list(type = "multiple_choice", options = list(A = "a", B = "b"), answer = "A")
  expect_no_error(check_question(ok, "Q1"))
  expect_error(check_question(modifyList(ok, list(type = "essay")), "Q1"), "Q1: question type 'essay' is not supported")
  expect_error(check_question(list(options = list(A = "a"), answer = "A"), "Q1"), "needs at least two options")
  expect_error(check_question(modifyList(ok, list(answer = "C")), "Q1"), "answer 'C' is not one of")
})

test_that("check_bank enforces unique ids and existing images, and warns on a figure without alt", {
  b <- read_bank(fixture_path("bank"), 1)
  expect_length(check_bank(b, fixture_path("bank", "images"))$warnings, 0L)
  b2 <- b; b2$sections[[1]]$questions[[2]]$figure$alt <- NULL
  expect_match(check_bank(b2, fixture_path("bank", "images"))$warnings, "id 2.*no alt")
  b3 <- b; b3$sections[[2]]$questions[[1]]$id <- 1L
  expect_error(check_bank(b3, fixture_path("bank", "images")), "duplicate question id")
  b4 <- b; b4$sections[[1]]$questions[[2]]$image <- "missing.png"
  expect_error(check_bank(b4, fixture_path("bank", "images")), "image .*missing.png does not exist")
})
```

- [ ] **Step 2: Implement `R/bank.R`** (`jsonlite::fromJSON(simplifyVector = FALSE)`; ids coerced to integer). `Version: 0.3.0.9006`; NEWS line.

- [ ] **Step 3: Propose the commit and stop**

```
Read and check question banks in the JSON schema
```

---

### Task 35: Generate a quiz from a bank, with parity against the Python generator

**Files:**
- Create: `R/generate-quiz.R`, `tests/testthat/test-generate-quiz.R`, `tests/testthat/oracle/generate_quiz.py`

**Interfaces:**
- Schema: a `quizzes:` definition with a `bank:` block:

```yaml
  - id: q-bank
    title: Module 1 Bank Quiz
    group: Quizzes
    published: true
    due: 2026-09-25
    bank:
      dir: questions            # relative to proj; the fixture uses ../bank-copy or copies the bank in
      chapters: [1, 2]
      draws: [2, 1, 2]          # one per group, chapter then section order; a list entry means splits
      splits: {}
      group_by: section         # or chapter
      points: 5                 # must equal sum(draws)
      allowed_attempts: -1      # unlimited
      shuffle_answers: true
      scoring_policy: keep_highest
      quiz_type: assignment
      show_correct_answers: true
      one_question_at_a_time: false
      description: null         # default text names the module
      unlock_at: null           # "YYYY-MM-DD HH:MM:SS" in the course zone
      lock_at: null
      position: 1
```

- Produces (internal unless noted): `bank_groups(spec, proj, title)` returning `list(groups = list(list(ch, name, qs)), draws = <integer>)` after `expand_splits()` and every refusal in `generate_quiz()`'s validation (empty chapters, missing points, unknown `group_by`, wrong draw count with the expected order listed, points not equal to the sum, negative draw, draw larger than the group); `answer_ids(ident, letters)` (salt-and-retry, identical arithmetic to the Python: `strtoi(substr(md5(key), 1, 6), 16L) %% 9000 + 1000`); `normalize_tables(html)` (caption, `scope="col"`, `thead`/`tbody`); `stem_html(q, image_base)`; `item_xml(ident, title, q, meta_fields, image_base, indent, ids)`; `window_utc(value, tz, title, field)`; `generate_quiz_files(q, module_title, course, proj, stage, ids, groups)` writing the three files and copying images to `web_resources/quiz_images/<file>`, returning `list(resources = list(list(id, raw)), images = <hrefs>)`. Exported: `bank_groups()` (the paper form reuses it) and `normalize_tables()`.
- Identifiers: quiz `ids$quiz_res[[k]]`, meta `ids$quiz_meta[[k]]`, assignment `ids$quiz_aid[[k]]` (the R conventions from `resolve_items()`); item `gid("q", ch, name, id)`; `aq <- gid("aq", ident)`; group `gid("group", ch, name)`; image resource `gid("file", href)`.
- Templates `QUIZ_META` (snapshot lines 307 to 381), `QTI_GROUPED` (382 to 396), `QTI_FLAT` (397 to 423), `GROUP` (424 to 434) copied verbatim from `generate_resources.py` into R strings, filled by a `fill(template, values)` helper that replaces `{name}` tokens with `gsub(fixed = TRUE)`.
- Escaping: text nodes through `xtext()` (matches Python `escape`); attribute values through `xesc()`; the `alt` and `src` inside the stem's `<img>` through an `html_escape()` that also maps `"` to `&quot;` and `'` to `&#x27;` (Python `html.escape(quote=True)`), then the whole stem through `xtext()` once.
- Image src: `$IMS-CC-FILEBASE$/quiz_images/<file>` (decision D15).

- [ ] **Step 1: Write the oracle script**

```python
# tests/testthat/oracle/generate_quiz.py
# Test oracle only. Runs the snapshot Python generator on a bank so the R port
# can be compared against it. Never shipped as behaviour.
import json, sys, importlib.util, pathlib, types
snap, bank_dir, spec_json, stage = sys.argv[1:5]
spec = importlib.util.spec_from_file_location("generate_resources", pathlib.Path(snap) / "generate_resources.py")
gr = importlib.util.module_from_spec(spec); spec.loader.exec_module(gr)
s = json.loads(pathlib.Path(spec_json).read_text())
item = {"title": s["title"], "type": "Quizzes::Quiz", "published": s.get("published", True), "generate": dict(s["bank"], kind="quiz", bank=".")}
module = {"title": s["module_title"]}
course = {"assignment_groups": [{"name": s["group"], "id": s["group_id"]}], "term": {"timezone": s["tz"]}}
res = gr.generate_item(item, module, course, bank_dir, stage, rid=s["quiz_id"], warnings=[])
print(json.dumps([r[0] for r in res]))
```

- [ ] **Step 2: Write the tests**

```r
# tests/testthat/test-generate-quiz.R
# A list-valued override REPLACES the default outright. modifyList() merges one
# list into the other, so spec(draws = list(2L, 1L)) would come back as the
# three-entry default and every refusal below would go untested.
spec <- function(...) {
  base <- list(dir = "bank", chapters = list(1L, 2L), draws = list(2L, 1L, 2L), points = 5,
               group_by = "section", allowed_attempts = -1L)
  over <- list(...)
  for (n in names(over)) base[n] <- list(over[[n]])
  base
}
with_bank <- function() {
  to <- withr::local_tempdir(.local_envir = parent.frame())
  p <- copy_course(to = to); file.copy(fixture_path("bank"), p, recursive = TRUE); p
}

test_that("bank_groups orders chapter then section and enforces every refusal", {
  p <- with_bank()
  g <- bank_groups(spec(), p, "T")
  expect_equal(vapply(g$groups, `[[`, "", "name"), c("1.1 First Ideas", "1.2 Second Ideas", "Sample Chapter Two"))
  expect_equal(g$draws, c(2L, 1L, 2L))
  expect_error(bank_groups(spec(chapters = list()), p, "T"), "T: bank.chapters is empty")
  expect_error(bank_groups(spec(points = NULL), p, "T"), "bank.points is required")
  expect_error(bank_groups(spec(group_by = "topic"), p, "T"), "group_by must be section or chapter")
  expect_error(bank_groups(spec(draws = list(2L, 1L)), p, "T"), "2 draws given for 3 bank sections")
  expect_error(bank_groups(spec(points = 4), p, "T"), "draws sum to 5 but points is 4")
  expect_error(bank_groups(spec(draws = list(2L, 9L, 2L), points = 13), p, "T"), "has 3 questions, cannot draw 9")
  gc <- bank_groups(spec(group_by = "chapter", draws = list(3L, 2L)), p, "T")
  expect_equal(vapply(gc$groups, `[[`, "", "name"), c("Sample Chapter One", "Sample Chapter Two"))
  expect_length(gc$groups[[1]]$qs, 6L)
})

test_that("splits expand a section into parts and refuse gaps, overlaps and unused entries", {
  p <- with_bank()
  sp <- spec(draws = list(list(1L, 1L), 1L, 2L), splits = list(`1.1 First Ideas` = list(list(1L, 2L), list(3L))))
  g <- bank_groups(sp, p, "T")
  expect_equal(g$groups[[1]]$name, "1.1 First Ideas (part 1)"); expect_equal(g$groups[[2]]$name, "1.1 First Ideas (part 2)")
  expect_equal(g$draws, c(1L, 1L, 1L, 2L))
  bad <- sp; bad$splits[[1]] <- list(list(1L, 2L), list(2L, 3L)); expect_error(bank_groups(bad, p, "T"), "lists ids in two parts")
  bad$splits[[1]] <- list(list(1L), list(3L)); expect_error(bank_groups(bad, p, "T"), "splits leave ids out")
  bad$splits <- list(`1.2 Second Ideas` = list(list(4L, 5L, 6L))); bad$draws <- list(2L, 1L, 2L)
  expect_error(bank_groups(bad, p, "T"), "splits names sections whose draw is not a list")
})

test_that("answer ids are unique within an item and stable; a forced collision is salted", {
  ids <- answer_ids("gabc", c("A", "B", "C", "D"))
  expect_length(unique(unlist(ids)), 4L); expect_identical(ids, answer_ids("gabc", c("A", "B", "C", "D")))
  expect_true(all(unlist(ids) >= 1000 & unlist(ids) <= 9999))
})

test_that("normalize_tables adds a caption, scope and thead, and leaves an already-normal table alone", {
  t <- "<table><tr><th>x</th><th>y</th></tr><tr><td>1</td><td>2</td></tr></table>"
  n <- normalize_tables(t)
  expect_match(n, "<caption>Data for this question</caption>", fixed = TRUE)
  expect_match(n, '<thead><tr><th scope="col">x</th><th scope="col">y</th></tr></thead><tbody>', fixed = TRUE)
  expect_identical(normalize_tables(n), n)
})

test_that("window_utc converts a course-zone stamp and refuses a bad format", {
  expect_equal(window_utc("2026-10-25 09:00:00", "America/Chicago", "T", "unlock_at"), "2026-10-25T14:00:00")
  expect_equal(window_utc(NULL, "America/Chicago", "T", "unlock_at"), "")
  expect_error(window_utc("2026-10-25", "America/Chicago", "T", "unlock_at"), "unlock_at must be 'YYYY-MM-DD HH:MM:SS'")
})

test_that("the generated files match the Python generator after id normalisation", {
  skip_if_no("python3")
  snap <- testthat::test_path("..", "..", "project", "econ202-toolchain", "scripts")
  skip_if(!file.exists(file.path(snap, "generate_resources.py")), "the Python snapshot is not present (R CMD check tarball)")
  p <- with_bank(); stage_r <- withr::local_tempdir(); stage_py <- withr::local_tempdir()
  q <- list(id = "q-bank", title = "Module 1 Bank Quiz", group = "Quizzes", published = TRUE, bank = spec())
  ids <- list(quiz_res = c(`q-bank` = "g00000000000000000000000000000d01"), quiz_meta = c(`q-bank` = "g00000000000000000000000000000d02"),
              quiz_aid = c(`q-bank` = "g00000000000000000000000000000d03"))
  course <- read_course(p); groups <- assignment_group_ids(course)
  generate_quiz_files(q, "Module 1: Start Here", course, p, stage_r, ids, groups)
  sj <- tempfile(fileext = ".json")
  jsonlite::write_json(list(title = q$title, module_title = "Module 1: Start Here", group = "Quizzes", group_id = unname(groups["Quizzes"]),
                            tz = "America/Chicago", quiz_id = "g00000000000000000000000000000d01", published = TRUE,
                            bank = list(chapters = c(1, 2), draws = c(2, 1, 2), points = 5, group = "Quizzes")), sj, auto_unbox = TRUE)
  system2("python3", c(testthat::test_path("oracle", "generate_quiz.py"), snap, file.path(p, "bank"), sj, stage_py))
  norm <- function(f) { x <- paste(readLines(f, warn = FALSE), collapse = "\n")
    x <- gsub("g[0-9a-f]{32}", "GID", x); x <- gsub('ident="[0-9]{4}"', 'ident="AID"', x)
    x <- gsub("(<varequal respident=\"response1\">)[0-9]{4}", "\\1AID", x)
    x <- gsub("(<fieldentry>)[0-9]{4}(,[0-9]{4})*", "\\1AIDS", x); x }
  for (f in c("non_cc_assessments/g00000000000000000000000000000d01.xml.qti",
              "g00000000000000000000000000000d01/assessment_qti.xml",
              "g00000000000000000000000000000d01/assessment_meta.xml"))
    expect_identical(norm(file.path(stage_r, f)), norm(file.path(stage_py, f)), info = f)
  expect_true(file.exists(file.path(stage_r, "web_resources", "quiz_images", "CH01_Q002.png")))
})
```

- [ ] **Step 3: Run to verify failure; implement `R/generate-quiz.R`** as a line-for-line port of `generate_resources.py`'s quiz half (functions `answer_ids`, `normalize_table`, `normalize_tables`, `stem_html`, `item_xml`, `expand_splits`, `window_utc`, `generate_quiz`), keeping the Python comments as R comments (the answer-id collision story, the flat-copy rule, the "escape ONCE" rule). `quiz_identifiers()` is not ported: ids come from `ids` (a `resource_id` on the definition already overrides `quiz_res` in `resolve_items()`; `meta` and `assignment` ids derive from it as in `embed_quiz()`).

- [ ] **Step 4: Tests green, including parity.** If parity fails on whitespace inside `QUIZ_META`, the R template lost a trailing space or a blank line; diff the two files with `diff <(norm r) <(norm py)`. `Version: 0.3.0.9007`; NEWS: "Quizzes generated from JSON question banks (`bank:` on a quiz definition), verified against the Python generator."

- [ ] **Step 5: Propose the commit and stop**

```
Generate Classic quizzes from question banks, at parity with the Python generator
```

---

### Task 36: Wire generated quizzes and assignments into the builder

**Files:**
- Create: `R/generate-assignment.R`
- Modify: `R/cartridge.R`, `R/cartridge-items.R`, `R/cartridge-xml.R`, `R/cartridge-checks.R`, `R/config.R` (definition shape rules), fixture `modules.yml`, `tests/testthat/helper-fixtures.R` (`copy_course()` copies the bank in), `tests/testthat/test-cartridge.R`
- Regenerate the expected tree.

**Interfaces:**
- A quiz definition has exactly one of `qti:`, `bank:`, `source_ref:`; an assignment exactly one of `homework:`, `quiz_file:`, `todo:`, `description:`, `source_ref:` (a `todo:` may sit beside `homework:` as today). `read_manifest()` enforces this.
- `description:` assignments (the Python `generate: kind: assignment`): HTML body from `description`, plus per-assignment `points`, `grading_type` (`points`, `pass_fail`, `percent`, `letter_grade`; anything else stops), `submission_types` (string or list, comma-joined), `allowed_extensions`, `group`, `published`, `due`. Written with the **R** `assignment_settings.xml` template (the ECON 730 export shape, gate-pinned); the Python template's extra elements are not emitted, recorded in NEWS and declared in the ECON 202 equivalence gate (Appendix B).
- Generated quizzes: `write_generated_quiz(k, q, ...)` calls `generate_quiz_files()` with the module title of the first module item referencing the quiz; `published` drives `<available>` and the nested `workflow_state`; `unlock_at`/`lock_at` through `window_utc()` with the course zone; a `due:` on a bank quiz fills both `<due_at>` slots in the meta through `due_stamp()` (the Python left this to `apply_due_dates`; here the definition is the handle). Module item: `Quizzes::Quiz`, idref `quiz_res`, `new_tab` empty.
- Pre-zip rule for decision D15: `$IMS-CC-FILEBASE$` may appear only inside `non_cc_assessments/*.xml.qti` and `<qid>/assessment_qti.xml`, only in the form `$IMS-CC-FILEBASE$/quiz_images/<file>`, and every such `<file>` must exist under `web_resources/quiz_images/` and be declared. Anywhere else it is still a failure.
- Output changes: `extra:` the three quiz files for `q-bank`, `web_resources/quiz_images/CH01_Q002.png`, the `memo-1` assignment directory (two files); `changed:` `imsmanifest.xml`, `course_settings/module_meta.xml`.

- [ ] **Step 1: Fixture and tests.** `copy_course()` also copies `fixtures/bank` into `<course>/questions`, and `tools/baseline.R` does the same in both modes (the frozen script ignores the directory). Fixture `modules.yml`: Module 1 gains `- quiz: q-bank` and `- assignment: memo-1`; definitions:

```yaml
  - id: q-bank
    title: Module 1 Bank Quiz
    group: Quizzes
    published: true
    due: 2026-09-25
    bank:
      dir: questions
      chapters: [1, 2]
      draws: [2, 1, 2]
      points: 5
      unlock_at: "2026-09-18 08:00:00"
  - id: memo-1
    title: Position Memo Draft
    points: 2
    grading_type: pass_fail
    submission_types: online_upload
    group: Assignments
    published: true
    due: "2026-09-17 09:30"
    description: "<p>Upload your draft before class on Thursday.</p>"
```

```r
test_that("a bank quiz is generated with its window and due date; its figure is staged, declared and the only FILEBASE user", {
  b <- built()
  qdirs <- list.files(b$stage, pattern = "assessment_meta\\.xml$", recursive = TRUE, full.names = TRUE)
  bank_meta <- qdirs[vapply(qdirs, function(f) any(grepl("Module 1 Bank Quiz", readLines(f, warn = FALSE))), TRUE)]
  expect_length(bank_meta, 1L)
  meta <- paste(readLines(bank_meta), collapse = "\n")
  expect_match(meta, "<unlock_at>2026-09-18T13:00:00</unlock_at>", fixed = TRUE)
  expect_length(gregexpr("<due_at>2026-09-26T04:59:59</due_at>", meta, fixed = TRUE)[[1]], 2L)
  expect_match(meta, "<available>true</available>", fixed = TRUE)
  expect_true(file.exists(file.path(b$stage, "web_resources", "quiz_images", "CH01_Q002.png")))
  expect_match(b$man, 'href="web_resources/quiz_images/CH01_Q002.png"', fixed = TRUE)
  users <- Filter(function(f) any(suppressWarnings(grepl("IMS-CC-FILEBASE", readLines(f, warn = FALSE), fixed = TRUE))),
                  list.files(b$stage, recursive = TRUE, full.names = TRUE))
  expect_true(all(grepl("non_cc_assessments/|/assessment_qti\\.xml$", users)))
  expect_match(b$mm, "<content_type>Quizzes::Quiz</content_type>\\s*<workflow_state>active</workflow_state>\\s*<title>Module 1 Bank Quiz</title>")
})

test_that("a FILEBASE token outside the quiz files, or pointing at an undeclared image, fails the build", {
  msgs <- character(); p_fail <- function(...) msgs <<- c(msgs, paste0(...))
  d <- withr::local_tempdir(); dir.create(file.path(d, "wiki_content"))
  writeLines('<img src="$IMS-CC-FILEBASE$/quiz_images/x.png">', file.path(d, "wiki_content", "p.html"))
  writeLines('<?xml version="1.0"?><manifest xmlns:lomimscc="x" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="y"><metadata><schemaversion>1.1.0</schemaversion><lomimscc:lom/></metadata><organizations/><resources/></manifest>', file.path(d, "imsmanifest.xml"))
  prezip_checks(d, "gx", character(), p_fail)
  expect_true(any(grepl("IMS-CC-FILEBASE in p.html", msgs)))
})

test_that("a description: assignment writes the R settings template with its grading type and body", {
  b <- built()
  f <- list.files(b$stage, pattern = "position-memo-draft\\.html$", recursive = TRUE, full.names = TRUE)
  expect_length(f, 1L)
  expect_match(paste(readLines(f), collapse = ""), "Upload your draft before class on Thursday.", fixed = TRUE)
  s <- paste(readLines(file.path(dirname(f), "assignment_settings.xml")), collapse = "\n")
  expect_match(s, "<grading_type>pass_fail</grading_type>", fixed = TRUE)
  expect_match(s, "<points_possible>2.0</points_possible>", fixed = TRUE)
  expect_match(s, "<due_at>2026-09-17T14:30:00</due_at>", fixed = TRUE)
  p <- b$p; edit_yaml(p, "modules.yml", "grading_type: pass_fail", "grading_type: gold_star")
  expect_error(build_cartridge(p), "grading_type must be points, pass_fail, percent, or letter_grade")
})

test_that("a quiz with two body forms, or an assignment with none, is refused by read_manifest", {
  p <- copy_course()
  edit_yaml(p, "modules.yml", "    qti: build/qti/quiz-sample.zip", "    qti: build/qti/quiz-sample.zip\n    source_ref: g00000000000000000000000000000q01")
  expect_error(read_manifest(p), "quiz 'q-sample' declares more than one of")
})
```

- [ ] **Step 2: Implement; regeneration procedure.** `Version: 0.3.0.9008`; NEWS: "Bank quizzes and `description:` assignments build; the FILEBASE rule admits quiz figures under `web_resources/quiz_images/` only (decision D15)."

- [ ] **Step 3: Propose the commit and stop**

```
Build bank quizzes and description assignments; admit quiz figures under D15; the cartridge was supposed to change
```

---

### Task 37: Staged builds by module title

**Files:**
- Modify: `R/cartridge.R`, `R/cartridge-items.R`, `tests/testthat/test-cartridge.R`

**Interfaces:**
- `build_cartridge(proj = ".", modules = NULL)`: `modules` is a character vector of module titles; when given, only those modules are staged, and only the definitions their items reference are written; an unknown title stops listing the known ones. Announcements are course-level and are staged regardless. The stale-height report covers only selected pages. `resolve_items()` returns `used = list(pages, assignments, quizzes)` and every writer loops over `used`, which is output-neutral for a course that passes `check_manifests()` (an unreferenced definition is already an orphan failure).
- Output changes: none.

- [ ] **Step 1: Tests**

```r
test_that("modules= stages only the named modules and the definitions they reference; unknown names stop", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  res <- build_cartridge(p, modules = "Module 2: Unpublished")
  mm <- paste(readLines(file.path(res$stage, "course_settings", "module_meta.xml")), collapse = "\n")
  expect_length(gregexpr("<module identifier=", mm)[[1]], 1L)
  expect_false(dir.exists(file.path(res$stage, "wiki_content")) && file.exists(file.path(res$stage, "wiki_content", "welcome.html")))
  expect_true(any(grepl("imsdt_xmlv1p1", readLines(file.path(res$stage, "imsmanifest.xml")))))
  expect_error(build_cartridge(p, modules = "Module 9"), "modules= names modules not in modules.yml: Module 9")
})
```

- [ ] **Step 2: Implement.** `Version: 0.3.0.9009`; NEWS line.

- [ ] **Step 3: Propose the commit and stop**

```
Stage a build by module title
```

---

### Task 38: Weekly announcements from a schedule

**Files:**
- Create: `R/announcements-schedule.R`, `tests/testthat/test-schedule-announcements.R`, `tests/testthat/fixtures/minimal-course/schedule.yml`

**Interfaces:**
- Produces, exported: `announcements_from_schedule(proj = ".", schedule = "schedule.yml", out_dir = "content/announcements", release_time = "07:00", calendar_url = NULL)` returning `invisible(<data.frame: id, title, post, body>)`. Port of `announcements.py`: one announcement per `weeks:` entry; title `"{label or Week N}: {module}"`; body: the plan paragraph, `notes`, one `<h3>` block per class day present in the entry (any of `monday` to `sunday`, in weekday order) with `holiday` or `In class`, `Assigned`, each due item that falls on that weekday with `Due, <time>` or `Exam, <time>` (label `Exam` when the title contains `Exam`), `Prepare before class`; then `<h3>Due by {Sunday}, 11:59 pm</h3>` listing items due Friday to Sunday, or "Nothing is due this Sunday."; a closing paragraph with the calendar link when `calendar_url` is given and the sentence `All times are {course$term$timezone_label %||% course$term$timezone}.` Due items come from the manifest's definitions with `due:` (assignments and quizzes), never from a title-keyed map. Each body is written as `<out_dir>/<id>.html` opening with `<h2>{title}</h2>`, `id = "week-<monday>"`, `post = "<monday> <release_time>"`. `announcements.yml` is written with `body_dir: <out_dir>` and the course term when absent; when it exists, `announcements.generated.yml` is written instead and the function says so. Past weeks are not skipped here; the builder reports past posts.
- No em-dash anywhere in the generated HTML.

- [ ] **Step 1: Fixture `schedule.yml`**

```yaml
weeks:
  - monday: 2026-09-14
    module: "Module 1: Start Here"
    notes: "The term is under way."
    tuesday:
      class: "How the course works."
      assigned: "Module 1 is open."
      prepare: "Read the welcome page."
    thursday:
      class: "First chapter."
  - monday: 2026-09-21
    module: "Module 2"
    tuesday:
      holiday: "No class today"
    thursday:
      class: "Second chapter."
  - monday: 2026-09-28
    module: "Module 3"
    thursday:
      class: "Third chapter."
```

The fixture's due dates by then: `hw-1` Tuesday 2026-09-15, `quiz-1` Sunday 2026-09-20, `memo-1` Thursday 2026-09-17 09:30, `q-bank` Friday 2026-09-25, and the carried definitions on 2026-10-01 (that week's Thursday) and 2026-10-02 (its Friday), which fall inside the third week, Monday 2026-09-28 to Sunday 2026-10-04. Friday to Sunday dues land in the Sunday list, so week 2 lists the bank quiz, and week 3 lists the carried assignment under Thursday and the carried quiz in its Sunday list. The empty-Sunday sentence is exercised by a separate one-week schedule (Monday 2026-10-05) in its own test.

- [ ] **Step 2: Tests**

```r
test_that("one announcement per week, dues placed by weekday, bodies and yml written", {
  p <- copy_course(); unlink(file.path(p, "announcements.yml"))
  a <- announcements_from_schedule(p, calendar_url = "https://example.invalid/course/calendar.html")
  expect_equal(a$id, c("week-2026-09-14", "week-2026-09-21", "week-2026-09-28"))
  expect_equal(a$post[1], "2026-09-14 07:00")
  b1 <- paste(readLines(file.path(p, "content", "announcements", "week-2026-09-14.html")), collapse = "\n")
  expect_match(b1, "^<h2>Week 1: Module 1: Start Here</h2>")
  expect_match(b1, "<h3>Tuesday, September 15</h3>"); expect_match(b1, "Due, 11:59 pm:</b> Homework 1")
  expect_match(b1, "<h3>Thursday, September 17</h3>"); expect_match(b1, "Due, 9:30 am:</b> Position Memo Draft")
  expect_match(b1, "<h3>Due by Sunday, September 20, 11:59 pm</h3>\\s*<ul><li>Module 1 Quiz</li></ul>")
  expect_match(b1, "All times are America/Chicago.")
  b2 <- paste(readLines(file.path(p, "content", "announcements", "week-2026-09-21.html")), collapse = "\n")
  expect_match(b2, "<li><b>No class today.</b></li>")
  expect_match(b2, "<h3>Due by Sunday, September 27, 11:59 pm</h3>\\s*<ul><li>Module 1 Bank Quiz</li></ul>")
  b3 <- paste(readLines(file.path(p, "content", "announcements", "week-2026-09-28.html")), collapse = "\n")
  expect_match(b3, "<h3>Thursday, October 1</h3>")
  expect_match(b3, "Due, 11:59 pm:</b> Carried Assignment")
  expect_match(b3, "<h3>Due by Sunday, October 4, 11:59 pm</h3>\\s*<ul><li>Carried Quiz</li></ul>")
  y <- yaml::yaml.load_file(file.path(p, "announcements.yml"))
  expect_equal(y$body_dir, "content/announcements"); expect_length(y$announcements, 3L)
  expect_false(any(grepl("—", c(b1, b2, b3))))
})

test_that("an existing announcements.yml is never overwritten", {
  p <- copy_course()
  expect_message(announcements_from_schedule(p), "announcements.generated.yml")
  expect_true(file.exists(file.path(p, "announcements.generated.yml")))
})

test_that("the generated announcements build into the cartridge", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p); unlink(file.path(p, "announcements.yml"))
  announcements_from_schedule(p)
  res <- build_cartridge(p)
  expect_length(gregexpr('type="imsdt_xmlv1p1"', paste(readLines(file.path(res$stage, "imsmanifest.xml")), collapse = ""))[[1]], 3L)
})
```

- [ ] **Step 3: Implement.** `Version: 0.3.0.9010`; NEWS line.

- [ ] **Step 4: Propose the commit and stop**

```
Generate weekly announcements from a schedule into the announcements contract
```

---

### Task 39: The Python-schema converter

**Files:**
- Create: `R/convert.R`, `tests/testthat/test-convert.R`, `tests/testthat/fixtures/python-schema/course.yml`, `tests/testthat/fixtures/python-schema/modules.yml`

**Interfaces:**
- Produces, exported: `convert_python_manifests(course_py, modules_py, out_dir, bank_dir = "questions")` returning `invisible(out_dir)`; `gid_py(...)` returning `"g"` plus the md5 of the arguments joined by `"::"` (the Python convention; needed to pin ids of items ECON 202 has already imported).
- Conversion (builder-merge 3.8, updated for the 09-04 Python schema): `course.yml`: `code` and `canvas.course_code` from `course_code`, `title`, `urls` as is, `term` as is, `due_time`, `canvas:` keys filtered through `CANVAS_SETTINGS_KEYS` (an unknown key stops, except `course_image`, below), `assignment_groups` with ids, `textbook_docs: none`; `due_dates` dissolves into definitions; `exam_pools` is dropped, with a printed note when non-empty. **`canvas.course_image`** is not a Canvas setting and is not written; the converter prints `course image: copy <path> to assets/images/course-tile.png; the builder ships it as web_resources/course_image/course_img.png` (the R builder's card mechanism), and the differing href and resource id are a declared divergence in the ECON 202 equivalence gate. **Generated quizzes without `group`** get `group: "Module Quizzes"` written explicitly (the Python default at `generate_resources.py` line 586); a generated assignment without `group` stops, as the Python did. `modules.yml`: modules with `module_id`, `title`, `published`, `sequential: require_sequential_progress`; items keyed by form with `item_id`, `indent`, `published`; definitions: `WikiPage` with `url` and no `carry_through` becomes `iframe:` with `width: "100%"`, `height`, `height_measured`, `resource_id` when present; `carry_through` pages become `source_ref: resource_id`; `Quizzes::Quiz` with `generate:` becomes `bank:` (`dir: bank_dir`, `chapters`, `draws`, `splits`, `group_by`, `points`, `allowed_attempts`, `shuffle_answers`, `quiz_type`, `description`, `unlock_at`, `lock_at`, `position`) with `group`, `published`, `due` from `due_dates[title]`, and `resource_id` pinned to the item's `resource_id` or `gid_py("res", module title, item title)`; `Quizzes::Quiz` without `generate:` becomes `source_ref`; `Assignment` with `generate:` becomes `description:` with `points`, `grading_type`, `submission_types`, `allowed_extensions`, `group`, `published`, `due`, `resource_id` pinned the same way; `Assignment` without becomes `source_ref`; `ExternalUrl` becomes `link:` with `url`. Definition ids are `slugify(title)`. Asserts before writing: module positions are strictly increasing and unique across the file, and item positions are strictly increasing and unique within each module (they restart at 1 in every module; the ECON 202 snapshot's modules run 1 to 15 then 17 after a merge, so `1..n` is not required); the R schema's positions are implicit in file order, so a gap is renumbered by order and the converter prints `positions renumbered: <old> -> <new>` for each module or item affected, which the equivalence gate declares; titles unique within kind (a duplicate stops `"titles are not unique within kind: <title>"`, review 16); every `due_dates` key matched a definition (an unmatched key stops, review 13). The Python file's header comment block (every leading `#` line) is copied verbatim to the top of the new `modules.yml`.

- [ ] **Step 1: Fixture** `python-schema/course.yml` and `modules.yml`: two modules with positions 1 and 3 (a deliberate gap), six items (an iframe page with `height_measured`, a `carry_through` page, a generated quiz **without** `group`, a generated quiz with `group`, a generated assignment, a carried assignment), one `due_dates` map with three entries, two groups with ids (`Module Quizzes` and one other), `canvas.course_image: images/card.png`, a `# header` comment block of three lines.

- [ ] **Step 2: Tests**

```r
test_that("the converter writes the R schema with pinned ids, dissolved due dates and the header comments", {
  out <- withr::local_tempdir()
  convert_python_manifests(fixture_path("python-schema", "course.yml"), fixture_path("python-schema", "modules.yml"), out)
  m <- read_manifest(out)
  expect_equal(m$course$textbook_docs, "none"); expect_equal(m$course$due_time, "23:59:59")
  q <- m$quizzes[[1]]; expect_equal(q$bank$chapters, c(1L, 2L)); expect_equal(q$due, "2026-09-13")
  expect_equal(q$resource_id, gid_py("res", m$mods$modules[[1]]$title, q$title))
  expect_true(any(vapply(m$pages, function(p) !is.null(p$source_ref), TRUE)))
  expect_true(any(vapply(m$pages, function(p) !is.null(p$height_measured), TRUE)))
  expect_equal(readLines(file.path(out, "modules.yml"), n = 1), readLines(fixture_path("python-schema", "modules.yml"), n = 1))
  groups <- vapply(m$quizzes, function(q) q$group, "")
  expect_true(all(nzchar(groups))); expect_true("Module Quizzes" %in% groups)
  expect_null(m$course$canvas$course_image)
})

test_that("a position gap is renumbered with a printed note; the course image produces a printed instruction", {
  out <- withr::local_tempdir()
  expect_output(convert_python_manifests(fixture_path("python-schema", "course.yml"), fixture_path("python-schema", "modules.yml"), out),
                "positions renumbered: 3 -> 2")
  expect_output(convert_python_manifests(fixture_path("python-schema", "course.yml"), fixture_path("python-schema", "modules.yml"), file.path(out, "b")),
                "course image: copy images/card.png to assets/images/course-tile.png")
})

test_that("an unmatched due_dates key, a duplicate title, and a non-increasing position each stop", {
  out <- withr::local_tempdir()
  c1 <- fixture_path("python-schema", "course.yml"); m1 <- fixture_path("python-schema", "modules.yml")
  cbad <- file.path(out, "c.yml"); writeLines(c(readLines(c1), '  "Nowhere Quiz": 2026-10-01'), cbad)
  expect_error(convert_python_manifests(cbad, m1, file.path(out, "a")), "due_dates names an item that does not exist: Nowhere Quiz")
  y <- readLines(m1); i <- grep("position: 2$", y)[1]; y[i] <- "        position: 1"
  mbad <- file.path(out, "m.yml"); writeLines(y, mbad)
  expect_error(convert_python_manifests(c1, mbad, file.path(out, "b")), "positions are not strictly increasing")
  y2 <- readLines(m1); titles <- grep("^      - title: ", y2); y2[titles[2]] <- y2[titles[1]]
  mdup <- file.path(out, "d.yml"); writeLines(y2, mdup)
  expect_error(convert_python_manifests(c1, mdup, file.path(out, "c")), "titles are not unique within kind")
})

test_that("gid_py matches the Python convention", {
  expect_equal(gid_py("res", "M", "T"), paste0("g", digest::digest("res::M::T", algo = "md5", serialize = FALSE)))
})

test_that("the ECON 202 snapshot converts and parses, when present", {
  snap <- testthat::test_path("..", "..", "project", "econ202-toolchain", "inputs")
  skip_if(!file.exists(file.path(snap, "modules.yml")), "snapshot not present")
  out <- withr::local_tempdir()
  convert_python_manifests(file.path(snap, "course.yml"), file.path(snap, "modules.yml"), out)
  m <- read_manifest(out); py <- yaml::yaml.load_file(file.path(snap, "modules.yml"))
  expect_length(m$mods$modules, length(py$modules))
  expect_equal(sum(lengths(lapply(m$mods$modules, `[[`, "items"))), sum(lengths(lapply(py$modules, `[[`, "items"))))
})
```

- [ ] **Step 3: Implement.** `Version: 0.3.0.9011`; NEWS line.

- [ ] **Step 4: Propose the commit and stop**

```
Add the one-off converter from the Python schema to the package schema
```

---

### Task 40: `print_assessment()`, a paper form of any assessment

**Files:**
- Create: `R/print.R`, `tests/testthat/test-print.R`

**Interfaces:**
- Produces, exported: `print_assessment(proj = ".", id, seed, out_dir = file.path(proj, "build", "paper"), formats = c("docx", "pdf"), render = TRUE)` returning `invisible(list(qmd, key, rendered))`. For a `bank:` quiz: `bank_groups()` gives the groups and draws; `set.seed(seed)`; `sample()` without replacement within each group in group order; writes `<id>-seed<seed>.qmd` (front matter: title, `date: today`, `format: docx` and `pdf`) with a numbered list of stems converted from HTML to Markdown through `pandoc -f html -t markdown` (tables become pipe tables; images copied beside the qmd and referenced relatively with their alt), options `A.` to `D.` in bank order; and `<id>-seed<seed>-key.qmd` with a table of number, chapter, section, bank id, answer, plus the seed and the package version. For an assignment with `description:` or `homework:`: one document with the title and the body converted the same way; no key. For `qti:`, `source_ref:` or `quiz_file:` definitions: stops with a message saying which forms are printable. With `render = TRUE` and `quarto` on the PATH, runs `quarto render <qmd> --to <format>` for each format; without quarto, writes the qmd files and prints where they are.
- Determinism: the qmd carries no timestamp, so a re-run with the same seed is byte-identical.

- [ ] **Step 1: Tests**

```r
# tests/testthat/test-print.R
test_that("a bank quiz prints a deterministic form and a key that matches it item for item", {
  skip_if_no("pandoc")
  p <- copy_course()
  r1 <- print_assessment(p, "q-bank", seed = 7, render = FALSE)
  r2 <- print_assessment(p, "q-bank", seed = 7, render = FALSE, out_dir = file.path(p, "build", "paper2"))
  expect_identical(readLines(r1$qmd), readLines(r2$qmd))
  r3 <- print_assessment(p, "q-bank", seed = 8, render = FALSE, out_dir = file.path(p, "build", "paper3"))
  expect_false(identical(readLines(r1$qmd), readLines(r3$qmd)))
  key <- readLines(r1$key)
  rows <- key[grepl("^\\| *[0-9]+ *\\|", key)]
  expect_length(rows, 5L)                                   # sum(draws)
  expect_true(any(grepl("seed 7", key)))
  expect_true(file.exists(file.path(dirname(r1$qmd), "CH01_Q002.png")) || !any(grepl("CH01_Q002", readLines(r1$qmd))))
})

test_that("a description assignment prints its body; an R/exams or carried quiz is refused", {
  skip_if_no("pandoc")
  p <- copy_course()
  r <- print_assessment(p, "memo-1", seed = 1, render = FALSE)
  expect_match(paste(readLines(r$qmd), collapse = "\n"), "Upload your draft before class on Thursday.")
  expect_null(r$key)
  expect_error(print_assessment(p, "q-sample", seed = 1), "printable forms are bank quizzes")
})

test_that("with quarto available the form renders to docx", {
  skip_if_no("pandoc"); skip_if_no("quarto")
  p <- copy_course()
  r <- print_assessment(p, "q-bank", seed = 3, formats = "docx")
  expect_true(file.exists(r$rendered[["docx"]]))
})
```

- [ ] **Step 2: Implement.** `Version: 0.3.0.9012`; NEWS: "`print_assessment()`: a fixed draw under a seed, as Word and PDF, with a key."

- [ ] **Step 3: Propose the commit and stop**

```
Print a paper form of a bank quiz or an assignment under a seed, with its key
```

**Phase 4 close.** Suite green including parity and round trip; check clean (the parity and snapshot tests skip in the tarball). `Version: 0.4.0`. Appendix B's ECON 202 blocks (M15, M16, E7) are written against what landed. Propose `Close phase 4: carry, extract, generate and print are in the package`.

# Phase 5: Skills and the scaffold

Canonical skills live in `inst/skills/<name>/SKILL.md` and install with the package (portable plan section 6). A course gets them by copy: `init_course()` for a new course, `install_skills()` for an existing one. Decision D9 applies throughout: incidents stay, course names go. Every skill is student-adjacent published text: no em-dashes, and every command names a function or Makefile target that exists at this version.

### Task 41: Generalize the five existing skills

**Files:**
- Create: `inst/skills/make-coursepack/SKILL.md`, `inst/skills/preview-course/SKILL.md`, `inst/skills/course-accessibility-review/SKILL.md`, `inst/skills/course-schedule-review/SKILL.md`, `inst/skills/strip-ai-characters/SKILL.md`, `inst/skills/strip-ai-characters/scan_characters.py`, `tests/testthat/test-skills-content.R`
- Source: `project/econ730-toolchain/skills/<name>/`

**Interfaces:**
- Each `SKILL.md` keeps its frontmatter `name` and `description` (the trigger phrases are the skill's value). The body changes are listed per skill below; nothing else is rewritten. The residue test at the end is the acceptance.

**make-coursepack** (378 lines). Edits:
1. The status block becomes: `**Status: verified by a real Canvas round trip** of the first course built with this toolchain (9 modules, 74 items sent, 74 returned, 0 lost). Round-tripping is the technique that makes this verifiable.` The verification table stays under a new heading `## The first verification, as a record` with its rows unchanged (they name counts, not a course).
2. The script table becomes:

| Entry point | Role |
|---|---|
| `coursepack::check_manifests(".")` | validates `course.yml` and `modules.yml` |
| `coursepack::build_cartridge(".")` | emits the `.imscc`; `modules = c("Module 5", ...)` stages a partial build |
| `coursepack::diff_against_reference(".")` | fails on any divergence not declared in `reference.yml` |
| `make coursepack` | chains all three |

3. Inputs table: the reference row becomes `reference.yml` `export:` pointing at **your course's own Canvas export, the specification**; add rows for `announcements.yml` (optional), `reference.yml` `source:` (the cartridge carried resources come from), and `questions/` (banks for `bank:` quizzes). Output: `build/coursepack/<slug>-<date>.imscc`.
4. "The reference export is the spec": the filename and the counts line go; "taken 2026-08-12" goes; the paragraph on a real export containing the course's own mistakes keeps its four examples introduced as "one real export had".
5. Identifier model: "Verified across all 72 items of the reference" becomes "Verified across all 72 items of one real export". The read-first table's row `course_settings/module_meta.xml | the 9 modules and 72 items, in order` becomes `the modules and items, in order`. The paragraph beginning "Zero quizzes in THIS export" is rewritten: "A course whose export has no quizzes is not evidence that cartridges cannot carry them; a real export of a second course carried 36 Classic quizzes."
6. "Embedding quizzes" gains three subsections after the existing text: `### Three ways a quiz reaches the cartridge` (`qti:` an R/exams zip, embedded with the prefix rewrite; `bank:` generated from a JSON question bank, pools per section or per chapter, with `splits`, `unlock_at` and `lock_at`; `source_ref:` copied from `reference.yml`'s `source:`), each with a four-line YAML example; `### Carried resources` (copied byte for byte from the source cartridge, then transformed in a fixed order: titles and `due:` rewritten from YAML, carried HTML repaired unless `carry: {repair_html: false}`; everything else in a carried file is exactly what the source held, and the package cannot judge whether it is current or right); `### Quiz figures` (the one admitted use of `$IMS-CC-FILEBASE$`, under `web_resources/quiz_images/`, checked file by file before zipping); and `### Starting from an export` (builder-merge M18): the call `coursepack::extract_manifest("export.imscc", "path/to/new-course")`, what it writes (`course.yml`, `modules.yml`, `reference.yml`, a copy under `reference/`), that it never overwrites an existing file unless `overwrite = TRUE` because a re-run has destroyed hand edits before, what is not recovered (announcements, grading standards, late policy, LTI links, and the link from any resource back to its plain-text source, so a course that authored its pages gets a structurally exact but source-blind manifest), and that the first build after extraction reports every iframe height as undated.
7. Workflow step 2 names `check_manifests()`; step 7 names `diff_against_reference()`.
8. Hard rules: the `web_resources/` row of the omit table becomes `web_resources/ except the course card and quiz figures | the course card is 18 KB and uses image_identifier_ref; quiz figures are exam content and must not be public`. The "Never embed files" rule gains the sentence "The only exceptions are the course card and quiz figures, both checked file by file."
9. Gotchas: unchanged.
10. Verification: "Log the outcome in `log/sessions/`... `log/gotchas.md`" becomes "Log the outcome in the course's own log if it keeps one."
11. Reference section: `reference.yml` `export:`, the package `NEWS.md`, and "the course's own decision record, if it keeps one".

**preview-course** (134 lines). Edits: "`scripts/build_preview.R` emits a data model" becomes "`coursepack::build_preview()` emits a data model"; the Run-it block stays (`make mockup`, `MOCKUP_BASE=live`, `MOCKUP_PORT`), because the scaffold Makefile (Task 44) provides those targets; "the textbook is reached through a symlink inside the served directory" gains "and so is the course's own `docs/`, as `/site`"; the templates sentence becomes "The page and its stylesheet ship inside the package under `templates/mockup/` and are copied into `build/mockup/` on every run."

**course-accessibility-review** (395 lines). Edits: every `scripts/audit_a11y.R` and `scripts/lib/a11y_*.R` mention becomes `coursepack::audit_course()` or "the package's audit library"; "Read this before every run" lists `CLAUDE.md` and "the course's decision record, if it keeps them" and drops `TODO.md` and decision 011 by number; "the counts below are this course's numbers on the day decision 009 was written" goes, with the sentence "Which pages exist under each surface comes from `discover_target()`, not from a fixed list"; the cartridge row's fix target becomes "`modules.yml` or the coursepack cartridge builder"; "The exact commands" becomes:

```bash
make a11y                                                   # from the scaffold Makefile
Rscript -e 'coursepack::audit_course(c(".", "/path/to/textbook-repo"))'
Rscript -e 'testthat::test_local()'                         # in the package checkout
npx --yes pa11y@9.1.1 --standard WCAG2AA --reporter json --runner htmlcs --runner axe --include-warnings --include-notices <url>
```

The gotcha naming `log/gotchas.md` for the corrupted-cache recovery says instead: "reinstall the browser with `@puppeteer/browsers install`, always passing `--path`, so the browser lands in the Puppeteer cache and not the current directory"; "Recorded in `TODO.md`" becomes "recorded in the package NEWS as an open design question". Announcement bodies join the cartridge surface list (Task 28).

**course-schedule-review** (239 lines). Edits, per D9: the opening keeps the incident anonymized ("This skill exists because that happened on a live course on the first day of a term: every date in `modules.yml` was seven days late, and every one was still a Friday."). Step 1: the command becomes `pdftotext -layout reference/policy/<academic-calendar>.pdf -`; "The UWRF calendar is a Microsoft print-to-PDF" becomes "Registrar calendars are often print-to-PDF"; the "What it yielded for Fall 2026" paragraph goes. Step 3: the two examples become "a prior session reasoned backward from a later session's start date and was wrong; the correct date came from the author" and "to make a printed 'opens Monday' rule fit a term that starts midweek, an assistant invented an opening Monday before the term began". Step 4: the quoted rule is introduced as "for example, one course prints:". Step 7: "two items landed on Friday 23 October, which is Fall Break" becomes "two items landed on a break day". Step 8: dates go. Step 9's table becomes generic rows: `modules.yml` (`due:` on every assignment and quiz), the syllabus page, the welcome page, `content/announcements/` bodies, Canvas. Step 10: the quoted note becomes "a note in front matter reading, in effect, 'this date was derived and is probably wrong; ask'". Output: "all seventeen rows" becomes "every row"; the worked Fall 2026 schedule block goes, replaced by two sentences: "Two of seven modules in that course deviated from the printed rule, for reasons the calendar supplied. That is the normal shape of a real term, and it is why the rule alone cannot generate the schedule." The Hard rule stays verbatim. "Open, not decided" is updated: `course.yml` now carries `term: {first_day, last_day, breaks}`; computing due dates from a rule is still not built.

**strip-ai-characters** (93 lines plus `scan_characters.py`, 223). Edits: the script's default scope becomes the current directory (`.`); the two declared-workspace paths in the script go, and the "exits with a refusal" bullet becomes "Anything outside the paths you name, or outside the current directory when you name none"; `--skip DIR` is added to the script for the `chapter_notes/`, `bak/` cases, which leave the hard-coded skip list and become documented examples; the "What was actually found here, 2026-08-16" section goes; "The author's standing rule forbids new ones" becomes "House rules often forbid new ones and grandfather old ones; rebuilding a sentence is a judgement no script can make"; the Run-it commands point at `.claude/skills/strip-ai-characters/scan_characters.py`.

- [ ] **Step 1: Write the residue test**

```r
# tests/testthat/test-skills-content.R
skills <- function() list.dirs(system.file("skills", package = "coursepack"), recursive = FALSE)

test_that("every shipped skill has frontmatter and no course residue", {
  for (d in skills()) {
    s <- readLines(file.path(d, "SKILL.md"), warn = FALSE)
    expect_equal(s[1], "---", info = d)
    expect_true(any(grepl("^name: ", s)), info = d); expect_true(any(grepl("^description:", s)), info = d)
    txt <- paste(readLines(list.files(d, recursive = TRUE, full.names = TRUE), warn = FALSE), collapse = "\n")
    expect_no_match(txt, "(?i)econ ?730|econ ?202|managerial|macro_principles|ljkelly3141|uwrf|river falls|real-world-statistics|kellyecon|My_Books|Teaching/|/Users/", perl = TRUE, info = d)
    expect_no_match(txt, "scripts/(build_|check_|diff_|audit_)", info = d)
    expect_false(grepl(intToUtf8(8212L), txt, fixed = TRUE), info = d)
  }
})

test_that("every coursepack:: call in a skill names an exported function", {
  ex <- getNamespaceExports("coursepack")
  for (d in skills()) {
    txt <- paste(readLines(file.path(d, "SKILL.md"), warn = FALSE), collapse = "\n")
    called <- unique(regmatches(txt, gregexpr("(?<=coursepack::)[A-Za-z_][A-Za-z0-9_.]*", txt, perl = TRUE))[[1]])
    expect_true(all(called %in% ex), info = paste(d, ":", paste(setdiff(called, ex), collapse = ", ")))
  }
})
```

- [ ] **Step 2: Copy and edit each skill** as listed; `cp` the source file first, then edit, so the unedited prose is byte-identical to the record.

- [ ] **Step 3: Run the residue test; read each skill top to bottom once.** `Version: 0.4.0.9001`; NEWS: "Five skills ship in `inst/skills/`, generalized."

- [ ] **Step 4: Propose the commit and stop**

```
Ship the five course skills, generalized and free of course residue
```

---

### Task 42: Three new skills

**Files:**
- Create: `inst/skills/new-course/SKILL.md`, `inst/skills/question-bank-authoring/SKILL.md`, `inst/skills/question-bank-authoring/scripts/{fetch_openstax.py,measure_bank.py,bank_checks.py,dump_imscc.py}`, `inst/skills/question-bank-authoring/briefs/{author.md,reviewer.md}`, `inst/skills/paper-assessment/SKILL.md`
- Source for the scripts and briefs: `project/econ202-toolchain/helpers/`, `project/econ202-toolchain/agent-briefs/`

**new-course** (`SKILL.md`, about 80 lines): frontmatter `name: new-course`, description triggering on "start a new course", "scaffold a course", "set up a course repo", "new coursepack". Body: what `init_course()` asks (code, title, the Pages site URL, the IANA timezone with `Sys.timezone()` shown as a suggestion and never used silently, optional institution and textbook URL); the exact call:

```r
coursepack::init_course("path/to/new-course", code = "ABCD 101", title = "Introduction to Something",
                        site_url = "https://<user>.github.io/<repo>", timezone = "America/Chicago")
```

the second entry point `from_export = "export.imscc"`; the file list it writes (Task 44's table); the four hard rules the course's `CLAUDE.md` carries (docs is public; assessments is never rendered; nothing is embedded in the cartridge except the card and quiz figures; a zip proves nothing); the next steps in order (render, push, enable Pages from `main /docs`, `make coursepack`, import into a throwaway shell, look, export back, compare); and the closing sentence "The scaffold is unverified until someone has imported it."

**question-bank-authoring** (`SKILL.md`, about 200 lines): frontmatter triggering on "write the question bank", "author chapter N questions", "review the bank", "generate quiz questions for chapter". Body, generalized from the ECON 202 README section 5 and the two briefs:
1. The schema, verbatim from Task 34, with the authoring conventions: twelve items per section, difficulty recall/application/analysis at 5/5/2, keys balanced three per letter per section, `explanation` ends with the section number, figures as scripts under `figures/` writing PNGs under `images/`, named by the item that uses them.
2. The loop: an author agent reads every section through `scripts/fetch_openstax.py` (refuses under 300 words, so a failed fetch cannot pass as a read), writes the bank, draws figures, runs `scripts/measure_bank.py` and `coursepack::check_bank()`, reports; a reviewer agent re-reads the sections and checks the eight criteria (key quoted against the text; single defensible answer; agreement with the text; arithmetic recomputed; figure integrity; stands alone; option-length rule; leakage), writing `review_chapter_NN.json` with exact replacement wording; the author applies only the required changes; the reviewer confirms with a recheck block; the orchestrator re-measures and presents eight sampled items; the instructor admits. The sentence "The phrase scans caught almost none of the real leaks; the reviewer reading each key against its neighbours did" stays.
3. The briefs: `briefs/author.md` and `briefs/reviewer.md`, the Chapter 13 briefs with every course fact replaced by `{{chapter}}`, `{{sections}}`, `{{bank_dir}}`, `{{source_name}}` placeholders and one paragraph on how to fill them.
4. Rules: no em-dashes in stems, options, explanations or alt text; no attribution to AI tools; measure, never recall.
5. The scripts are copied from the ECON 202 helpers after `grep -niE 'econ|uwrf|kelly|macro' scripts/*` returns nothing; `measure_bank.py` and `bank_checks.py` take the bank directory as an argument; `dump_imscc.py` is the cartridge dump used to read a zip back.

**paper-assessment** (`SKILL.md`, about 70 lines): frontmatter triggering on "paper version", "print the quiz", "paper exam", "printable final". Body: what `print_assessment()` does (one fixed draw under a seed from the same pools, Word and PDF, a key naming item ids and the seed); the call:

```r
coursepack::print_assessment(".", id = "final-exam", seed = 2026, formats = c("docx", "pdf"))
```

the rule that the seed and the key are kept with the sitting so a form can be re-created and graded against the bank; which definitions are printable (bank quizzes, `description:` and `homework:` assignments) and which are not; that the same `bank_groups()` the cartridge uses draws the items, so the paper form and the Canvas quiz draw from identical pools; and that a rendered document is reviewed by a person before it is sat.

- [ ] **Step 1: Write the three skills and copy the scripts and briefs.**
- [ ] **Step 2: Run `test-skills-content.R`** (it covers every directory). `Version: 0.4.0.9002`; NEWS line.
- [ ] **Step 3: Propose the commit and stop**

```
Add the new-course, question-bank-authoring and paper-assessment skills
```

---

### Task 43: `install_skills()`

**Files:**
- Create: `R/skills.R`, `tests/testthat/test-skills.R`

**Interfaces:**
- Produces, exported: `install_skills(proj = ".", which = NULL, overwrite = FALSE)`: copies `system.file("skills", package = "coursepack")/<name>/` to `<proj>/.claude/skills/<name>/` for every name (or `which`); refuses when a destination exists unless `overwrite = TRUE`, naming the ones it would overwrite; appends `\n<!-- installed from coursepack <version> -->\n` to each copied `SKILL.md`; prints what it wrote and the version; returns the destinations invisibly. Never writes outside `proj`.

- [ ] **Step 1: Tests**

```r
# tests/testthat/test-skills.R
test_that("install_skills copies every skill, stamps the version, refuses to overwrite, overwrites when told", {
  p <- withr::local_tempdir()
  out <- install_skills(p)
  expect_setequal(basename(out), basename(list.dirs(system.file("skills", package = "coursepack"), recursive = FALSE)))
  s <- readLines(file.path(p, ".claude", "skills", "make-coursepack", "SKILL.md"))
  expect_match(tail(s, 1), paste0("installed from coursepack ", coursepack_version()))
  expect_true(file.exists(file.path(p, ".claude", "skills", "strip-ai-characters", "scan_characters.py")))
  expect_error(install_skills(p), "already exist.*make-coursepack")
  expect_no_error(install_skills(p, which = "preview-course", overwrite = TRUE))
  expect_error(install_skills(p, which = "no-such-skill"), "unknown skill: no-such-skill")
})

test_that("an installed copy differs from inst/ only by the version line", {
  p <- withr::local_tempdir(); install_skills(p, which = "preview-course")
  a <- readLines(file.path(p, ".claude", "skills", "preview-course", "SKILL.md"))
  b <- readLines(system.file("skills", "preview-course", "SKILL.md", package = "coursepack"))
  expect_identical(head(a, length(b)), b); expect_length(a, length(b) + 2L)
})
```

- [ ] **Step 2: Implement.** `Version: 0.4.0.9003`; NEWS line.
- [ ] **Step 3: Propose the commit and stop**

```
Add install_skills(), which copies the shipped skills into a course and stamps the version
```

---

### Task 44: The course templates, `render_template()`, `leak_check()`

**Files:**
- Create: `R/init.R` (the two helpers; `init_course()` arrives in Task 45), `inst/templates/course/` (files below), `tests/testthat/test-templates.R`

**Interfaces:**
- `render_template(text, values)`: replaces every `{{key}}` with `values[[key]]`; an unreplaced `{{...}}` left in the output stops naming it; no new dependency.
- `leak_check(proj = ".", docs = "docs")`: greps every file under `<proj>/<docs>` for `LEAK_CANARY` as bytes; stops `"LEAK: assessments/ content reached <docs>. Do not push."` listing the files; prints `leakcheck: clean` and returns `invisible(character(0))` otherwise; a missing docs directory is a stop, not a pass.
- Templates, every file in the portable plan's section 5 table, with `{{code}}`, `{{title}}`, `{{institution}}`, `{{slug}}`, `{{site_url}}`, `{{textbook_url}}`, `{{textbook_docs}}`, `{{timezone}}`, `{{canary}}`, `{{version}}` placeholders:

| File | Content |
|---|---|
| `course.yml` | `code`, `title`, `institution`, `slug`, `term:` (`name: TBD`, `first_day: null`, `last_day: null`, `timezone`, `breaks: []`) with the comment "dates come from the registrar's calendar, never from counting", `due_time: "23:59:59"`, `urls: {site, textbook}` (the textbook line only when given), `textbook_docs`, `canvas:` (`course_code`, `default_view: modules`, `is_public: false`, `group_weighting_scheme: percent`, `grading_standard_enabled: false`), one group `Assignments` weight 100.0, `assignment_defaults` (`points: 100`, `submission_types: online_upload`, `group: Assignments`), no grading standard, no late policy |
| `modules.yml` | the item-form legend as a comment; one module "Start here" with a header, `page: welcome`, and `assignment: first-assignment` with `todo: "replace me"` and `published: false`; `pages:` welcome as `iframe: "{site}/content/pages/welcome.html"`, `width: "100%"`, `height: "800"`; `assignments:` the todo |
| `announcements.yml` | `body_dir: content/announcements`; one entry `welcome` with `post: immediately` |
| `content/pages/welcome.qmd`, `content/pages/syllabus.qmd` | a title and one paragraph |
| `content/canvas/.gitkeep`, `content/announcements/welcome.html` | the body contract directory; `<h2>Welcome</h2><p>Read the syllabus before the first meeting.</p>` |
| `assessments/README.md`, `assessments/leak-canary.qmd`, `assessments/quizzes/.gitkeep` | the containment README (generic) and the canary page carrying `{{canary}}` |
| `assets/images/.gitkeep`, `assets/data/.gitkeep`, `assets/files/.gitkeep`, `assets/README.md` | "Everything here is public." |
| `questions/README.md` | the bank schema pointer and "never rendered" |
| `_quarto.yml` | `type: default`, `output-dir: docs`, `render: ["index.qmd", "content/**/*.qmd"]`, `resources: ["assets/**"]`, `embed-resources: true`, the allowlist comment |
| `index.qmd`, `style.css` | minimal |
| `Makefile` | targets: `site` (quarto render, touch `docs/.nojekyll`, `leakcheck`), `leakcheck` (`Rscript -e 'coursepack::leak_check(".")'`), `checkyml`, `coursepack` (`checkyml`, `build_cartridge`, `refdiff`), `refdiff`, `mockup` (`MOCKUP_BASE ?= local`, `MOCKUP_PORT ?= 8765`, `build_preview(".", base = "$(MOCKUP_BASE)")`, `python3 -m http.server`, `open` with an `xdg-open` fallback), `qti` (`QUIZ ?=`, usage message), `a11y` (`A11Y_REPOS ?= .`), `tile` (`course_tile(".")`), `skills` (`install_skills(".", overwrite = TRUE)`), `paper` (`ID ?=`, `SEED ?=`), `test` (the package suite, `testthat::test_local` in the package checkout is not a course concern; `test` runs `check_manifests` and `leak_check`), `clean` (`rm -rf build .quarto`; never `docs/`, with the comment why), `install-toolchain` (`COURSEPACK ?=` optional; `remotes::install_github("LJKelly3141/coursepack")` when unset, `remotes::install_local` when set) |
| `.gitignore` | `build/`, `.quarto/`, `*_files/`, `.Rproj.user/`, `.DS_Store` |
| `README.md` | ten lines: what the repo is, the three commands, where content goes |
| `CLAUDE.md` | the layout, the four hard rules, a pointer to `.claude/skills/` |
| `reference/README.md` | how to export a Canvas course and where to put it; what `reference.yml` `export:` and `source:` mean |

The `install-toolchain` target names the package's GitHub path, which is the one place a repository identifier appears in a template; it is the package's own address, not a course fact, and Task 47's grep allows it by name.

- [ ] **Step 1: Tests**

```r
# tests/testthat/test-templates.R
test_that("render_template fills every placeholder and refuses a leftover", {
  expect_equal(render_template("a {{x}} b {{y}}", list(x = 1, y = "z")), "a 1 b z")
  expect_error(render_template("a {{x}} {{q}}", list(x = 1)), "unfilled template key: q")
})

test_that("every template renders with example values and the YAML ones parse", {
  tpl <- system.file("templates", "course", package = "coursepack")
  vals <- list(code = "ABCD 101", title = "A Course", institution = "Example U", slug = "abcd-101",
               site_url = "https://example.invalid/c", textbook_url = "", textbook_docs = "none",
               timezone = "America/Chicago", canary = LEAK_CANARY, version = coursepack_version())
  for (f in list.files(tpl, recursive = TRUE, all.files = TRUE, full.names = TRUE)) {
    out <- render_template(paste(readLines(f, warn = FALSE), collapse = "\n"), vals)
    if (grepl("\\.ya?ml$", f)) expect_error(yaml::yaml.load(out), NA, info = f)
  }
})

test_that("leak_check stops on the canary in docs and passes a clean docs", {
  d <- withr::local_tempdir(); dir.create(file.path(d, "docs"))
  writeLines("<p>fine</p>", file.path(d, "docs", "a.html"))
  expect_output(leak_check(d), "leakcheck: clean")
  writeLines(LEAK_CANARY, file.path(d, "docs", "b.html"))
  expect_error(leak_check(d), "LEAK: assessments/ content reached docs")
  expect_error(leak_check(withr::local_tempdir()), "no docs directory")
})
```

- [ ] **Step 2: Write the templates and the two helpers.** `Version: 0.4.0.9004`; NEWS line.
- [ ] **Step 3: Propose the commit and stop**

```
Add the course templates, render_template() and leak_check()
```

---

### Task 45: `init_course()`

**Files:**
- Modify: `R/init.R`
- Create: `tests/testthat/test-init.R`

**Interfaces:**
- Produces, exported: `init_course(path, code, title, site_url, timezone, institution = NULL, textbook_url = NULL, textbook_docs = "none", skills = TRUE, claude_md = TRUE, git = TRUE, from_export = NULL, ask = interactive())`, the portable plan's section 5 signature plus `from_export` (builder-merge 3.7). Returns `path` invisibly. Rules: `path` must not exist or must be empty; `code`, `title`, `site_url` required (prompted only when `ask` and interactive, otherwise stop); `site_url` must start with `https://`; `timezone` validated against `OlsonNames()` with `Sys.timezone()` offered as the suggestion in the prompt and never used silently; writes every template through `render_template()`; `skills = TRUE` calls `install_skills(path)`; `claude_md = FALSE` skips `CLAUDE.md`; `git = TRUE` runs `git init` only, never a commit; `from_export` names an `.imscc`: the scaffold is written, then `extract_manifest(from_export, path, overwrite = TRUE)` replaces `course.yml`, `modules.yml`, `reference.yml`, after which `init_course()` re-applies the caller's `code`, `title`, `site_url`, `timezone`, `textbook_docs`, and `due_time` into the extracted `course.yml` (the export does not carry a zone or a due time). Prints the file list, the version, and the next steps ending with "a zip that builds proves nothing". Never overwrites anything.

- [ ] **Step 1: Tests**

```r
# tests/testthat/test-init.R
new_course <- function(...) {
  d <- withr::local_tempdir(.local_envir = parent.frame()); p <- file.path(d, "c")
  init_course(p, code = "ABCD 101", title = "A Course", site_url = "https://example.invalid/c",
              timezone = "America/Chicago", ask = FALSE, git = FALSE, ...)
  p
}

test_that("the scaffold writes every file, parses, and installs the skills", {
  p <- new_course()
  for (f in c("course.yml", "modules.yml", "announcements.yml", "_quarto.yml", "Makefile", "CLAUDE.md", "README.md",
              "content/pages/welcome.qmd", "content/announcements/welcome.html", "assessments/leak-canary.qmd",
              "reference/README.md", ".claude/skills/make-coursepack/SKILL.md", "questions/README.md"))
    expect_true(file.exists(file.path(p, f)), info = f)
  m <- read_manifest(p)
  expect_equal(m$course$code, "ABCD 101"); expect_equal(read_timezone(m$course), "America/Chicago")
  expect_equal(m$course$slug, "abcd-101"); expect_true(!is.null(m$assignments[["first-assignment"]]$todo))
  q <- yaml::yaml.load_file(file.path(p, "_quarto.yml"))
  expect_equal(q$project$render, c("index.qmd", "content/**/*.qmd"))
  expect_true(any(grepl(LEAK_CANARY, readLines(file.path(p, "assessments", "leak-canary.qmd")), fixed = TRUE)))
})

test_that("refusals: non-empty path, bad site_url, unknown timezone, missing required args when not asking", {
  d <- withr::local_tempdir(); writeLines("x", file.path(d, "f"))
  expect_error(init_course(d, "ABCD 101", "T", "https://x", "America/Chicago", ask = FALSE), "not empty")
  expect_error(init_course(file.path(d, "a"), "ABCD 101", "T", "http://x", "America/Chicago", ask = FALSE), "must start with https://")
  expect_error(init_course(file.path(d, "b"), "ABCD 101", "T", "https://x", "Central", ask = FALSE), "IANA")
  expect_error(init_course(file.path(d, "c"), title = "T", site_url = "https://x", timezone = "UTC", ask = FALSE), "code is required")
})

test_that("from_export replaces the manifests with the extracted ones and keeps the caller's zone", {
  skip_if_no("zip")
  src <- copy_course(); imscc <- file.path(src, "reference", "source.imscc")
  d <- withr::local_tempdir(); p <- file.path(d, "x")
  init_course(p, code = "SRC 100", title = "Source Course", site_url = "https://example.invalid/course",
              timezone = "Europe/London", ask = FALSE, git = FALSE, from_export = imscc)
  m <- read_manifest(p)
  expect_true(!is.null(m$pages[["carried-page"]]$source_ref)); expect_equal(read_timezone(m$course), "Europe/London")
  expect_true(file.exists(file.path(p, "reference", "source.imscc")))
  expect_equal(read_reference(p)$source, "reference/source.imscc")
})
```

- [ ] **Step 2: Implement.** `Version: 0.4.0.9005`; NEWS: "`init_course()`, with `from_export`."
- [ ] **Step 3: Propose the commit and stop**

```
Add init_course(), the scaffold entry point, with from_export
```

---

### Task 46: The scaffold builds

**Files:**
- Create: `tests/testthat/test-scaffold.R`

- [ ] **Step 1: Test**

```r
test_that("a fresh scaffold passes check_manifests, builds a cartridge with one module and one page, and contains nothing it should not", {
  skip_if_no("zip"); skip_if_no("pandoc")
  d <- withr::local_tempdir(); p <- file.path(d, "c")
  init_course(p, code = "ABCD 101", title = "A Course", site_url = "https://example.invalid/c",
              timezone = "America/Chicago", ask = FALSE, git = FALSE)
  expect_no_error(check_manifests(p))
  res <- build_cartridge(p)
  mm <- paste(readLines(file.path(res$stage, "course_settings", "module_meta.xml")), collapse = "\n")
  expect_length(gregexpr("<module identifier=", mm)[[1]], 1L)
  expect_length(list.files(file.path(res$stage, "wiki_content")), 1L)
  expect_false(dir.exists(file.path(res$stage, "assessments")))
  files <- list.files(res$stage, recursive = TRUE, full.names = TRUE)
  expect_false(any(vapply(files, function(f) length(grepRaw("IMS-CC-FILEBASE", readBin(f, "raw", file.info(f)$size), fixed = TRUE)) > 0, TRUE)))
  # the containment gate: a fake render that leaks the canary is caught
  dir.create(file.path(p, "docs")); file.copy(file.path(p, "assessments", "leak-canary.qmd"), file.path(p, "docs", "leak.html"))
  expect_error(leak_check(p), "LEAK")
})
```

- [ ] **Step 2: Run.** A Canvas import of the scaffold cartridge is the human gate (Appendix D). `Version: 0.5.0`; NEWS header for the phase.
- [ ] **Step 3: Propose the commit and stop**

```
Close phase 5: a scaffolded course checks, builds and contains
```

# Phase 6: Public readiness

### Task 47: The scrub audit

**Files:**
- Create: `tools/scrub.sh`, `tests/testthat/test-scrub.R`

**Interfaces:**
- `tools/scrub.sh` runs the portable plan's section 10 content greps and exits non-zero on any hit outside the allowed set. The allowed set is exactly: the string `LJKelly3141/coursepack` inside `inst/templates/course/Makefile`, `README.md`, and `DESCRIPTION` (the package's own address), and nothing else.

```bash
#!/usr/bin/env bash
# Public-readiness greps. Exit 1 on any hit outside the allowed set.
set -u
status=0
hits=$(grep -rniE 'econ ?730|econ ?202|managerial|macro_principles|logankelly|uwrf|river falls|real-world-statistics|kellyecon|My_Books|Teaching/' \
  R/ inst/ tests/ man/ NAMESPACE README.md NEWS.md CONTRIBUTING.md DESCRIPTION 2>/dev/null)
[ -n "$hits" ] && { echo "course residue:"; echo "$hits"; status=1; }
addr=$(grep -rn 'ljkelly3141' -i R/ inst/ tests/ man/ NAMESPACE README.md NEWS.md CONTRIBUTING.md DESCRIPTION 2>/dev/null \
  | grep -viE '^(inst/templates/course/Makefile|README\.md|DESCRIPTION):.*LJKelly3141/coursepack')
[ -n "$addr" ] && { echo "repository address outside the allowed files:"; echo "$addr"; status=1; }
env=$(grep -rn 'Sys.getenv' R/); [ -n "$env" ] && { echo "Sys.getenv in R/:"; echo "$env"; status=1; }
paths=$(grep -rnE '~/|/Users/|/home/' R/ inst/ tests/); [ -n "$paths" ] && { echo "absolute paths:"; echo "$paths"; status=1; }
dash=$(grep -rn -- '—' R/ inst/ README.md NEWS.md CONTRIBUTING.md 2>/dev/null); [ -n "$dash" ] && { echo "em-dashes in shipped text:"; echo "$dash"; status=1; }
secrets=$(git log -p --all | grep -cE '[0-9]{4,5}~[A-Za-z0-9]{40,}|Bearer |CANVAS_API_TOKEN'); [ "$secrets" != "0" ] && { echo "token shapes in history: $secrets"; status=1; }
[ $status -eq 0 ] && echo "scrub: clean"
exit $status
```

- [ ] **Step 1: Test** `tests/testthat/test-scrub.R`: skips unless the script exists relative to the package root (`test_path("..", "..", "tools", "scrub.sh")`, absent in the tarball); runs it with `system2()` and expects exit status 0.
- [ ] **Step 2: Run it; fix every hit in the file that owns it.** `Version: 0.5.0.9001`.
- [ ] **Step 3: Propose the commit and stop**

```
Add the public-readiness scrub and make it pass
```

---

### Task 48: README, CONTRIBUTING, NEWS

**Files:**
- Modify: `README.md`, `NEWS.md`
- Create: `CONTRIBUTING.md`

- [ ] **Step 1: Rewrite `README.md` for a stranger** in this order: what it is (two sentences); the architecture in five sentences (Canvas holds structure, Pages holds content; containment by allowlist and canary; deterministic ids; a zip proves nothing; import and round-trip); requirements in two rows ("to build a cartridge: R, `zip`, `pandoc`" and "to preview or audit: `python3`; Node, `npx`, Chrome for the audit; `quarto` for paper forms"); the quick start (`remotes::install_github("LJKelly3141/coursepack")`, `init_course()`, edit, `make coursepack`, import into a throwaway shell, export, compare); the two entry points (scaffold, `from_export`); and the status table:

| Entry point | Verified by a real Canvas import | Date |
|---|---|---|
| `build_cartridge()` (generated items, announcements, embedded R/exams quiz) | the ECON 730 chain it descends from, before the move | 2026-08-12, 2026-09-02 |
| `build_cartridge()` from this package | not yet | |
| carried resources, bank quizzes, `description:` assignments | not yet | |
| `extract_manifest()` | synthetic round trip only | |
| `init_course()` scaffold | not yet | |
| `audit_course()` | ran end to end on two real courses before the move | 2026-09-01 |

The rows naming the descent are written without the course names ("the toolchain this package descends from"). The separation rule paragraph stays. The licence section stays.

- [ ] **Step 2: Write `CONTRIBUTING.md`**: the arrival rule (entry points take `proj`; no `Sys.getenv` with a default; no absolute paths; course facts in YAML); the gate rule (never regenerate to pass; a regeneration is its own commit naming the files); the no-course-content rule and the scrub; the two-courses rule in the package's words; how to run the tests with and without Chrome (`COURSEPACK_PA11Y_TESTS=1`) and the parity test (needs `python3` and the `project/` snapshots); the no-em-dash rule for shipped text; whether outside contributions are accepted is decision D11 and the file says so until Logan decides.

- [ ] **Step 3: `NEWS.md`**: one heading per phase version (0.1.0 to 0.5.0) with the lines accumulated, plus a "Known limitations" section: `LEAK_CANARY` and the answer-key heading are package constants; `description:` assignments use the one settings template; announcements, grading standards, late policy and LTI are not extracted; the a11y surface identity is a path basename; exam pools are not ported (retired upstream); the local `{site}` base reading (Task 20) is recorded as a reading. `Version: 0.5.0.9002`.

- [ ] **Step 4: Propose the commit and stop**

```
Write the README, CONTRIBUTING and NEWS for a reader who has never seen the courses
```

---

### Task 49: CI

**Files:**
- Create: `.github/workflows/check.yml`

- [ ] **Step 1: Write the workflow**

```yaml
name: check
on: [push, pull_request]
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: r-lib/actions/setup-pandoc@v2
      - uses: r-lib/actions/setup-r@v2
        with: { use-public-rspm: true }
      - run: sudo apt-get update && sudo apt-get install -y zip libmagick++-dev
      - uses: r-lib/actions/setup-r-dependencies@v2
        with: { extra-packages: any::rcmdcheck, needs: check }
      - uses: r-lib/actions/check-r-package@v2
        with: { error-on: '"warning"' }
  pa11y:
    runs-on: ubuntu-latest
    continue-on-error: true            # decision D12: optional, informative
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - uses: r-lib/actions/setup-pandoc@v2
      - uses: r-lib/actions/setup-r@v2
        with: { use-public-rspm: true }
      - run: sudo apt-get update && sudo apt-get install -y zip libmagick++-dev python3
      - uses: r-lib/actions/setup-r-dependencies@v2
      - run: npx --yes pa11y@9.1.1 --version
      - run: Rscript -e 'testthat::test_local(filter = "a11y-integration")'
        env: { COURSEPACK_PA11Y_TESTS: "1" }
```

- [ ] **Step 2: Add `^\.github$` is already in `.Rbuildignore`; confirm.** The workflow cannot be verified green from this repository until it is pushed; the task's done-when is Logan's push (Appendix D). `Version: 0.5.0.9003`.

- [ ] **Step 3: Propose the commit and stop**

```
Add CI: R CMD check, and an optional pa11y job
```

---

### Task 50: The `project/` decision and the go-public checklist

No code. A checklist for Logan, each line a command or a yes/no, with the plan's own findings attached.

- [ ] `tools/scrub.sh` clean on the final tree.
- [ ] **`project/` contents (decision D10, re-opened).** `project/` holds: `econ202-toolchain/inputs/questions/chapter_13.json` and `review_chapter_13.json` (a live exam bank with keys), `econ730-toolchain/inputs/content/canvas/` (38 pages of course prose), both courses' full `modules.yml` and `course.yml`, both `CLAUDE.md`s with directory layouts, and every plan naming `/Users/logankelly`. Options: (a) move `project/` to a private companion repository and leave a one-paragraph README pointing at it; (b) keep `project/` and delete the two question-bank files and `inputs/content/canvas/` before the flip, rewriting nothing else; (c) keep it all. Recommendation, marked as such: (a). Whatever is chosen, `git log -p | grep -c 'chapter_13'` will still find the bank in history; going public with history that ever held it means the bank is public. If that matters, the choice is a fresh repository or a history rewrite, both Logan's to make.
- [ ] `git log -p --all | grep -c '/Users/logankelly'` is 0 outside `project/`.
- [ ] `R CMD check --as-cran` on a machine without Node or Chrome: 0 errors, 0 warnings; pa11y and parity tests report as skipped.
- [ ] Every exported function has a roxygen page whose example runs in `tempdir()` (`R CMD check` runs them).
- [ ] `DESCRIPTION` `Authors@R` carries the email Logan chooses (D8); the package name stays `coursepack` unless he says otherwise.
- [ ] README quick start followed on a clean machine from `install_github()` to an imported scaffold, by Logan pretending to be a stranger.
- [ ] Repository description and topics set; issues on or off (D11).
- [ ] The visibility flip, by Logan, by hand.

`Version: 1.0.0` when the flip happens, not before. Propose `Close phase 6: ready to go public` when every line above is checked.

---

# Appendix A: ECON 730 hand-offs

Everything here runs in an ECON 730 session, in that repository, with Logan. Nothing here is executed from the package repository. Each block names the package version it assumes.

**A1. After Phase 1 (package 0.1.0; tag it `v0.1.0`).**

1. `Makefile`: add

```make
# Path to the local coursepack checkout. A machine path defaulted in a course
# Makefile is acceptable; the same default inside package code would not be.
COURSEPACK ?= /Users/logankelly/Sync/Developer/coursepack
install-toolchain:
	Rscript -e 'remotes::install_local("$(COURSEPACK)", upgrade = "never", force = TRUE)'
```

and repoint: `checkyml: Rscript -e 'coursepack::check_manifests(".")'`; `coursepack: checkyml` then `Rscript -e 'coursepack::build_cartridge(".")'` then `$(MAKE) refdiff`; `refdiff: Rscript -e 'coursepack::diff_against_reference(".")'`; `qti: Rscript -e 'coursepack::build_qti("$(QUIZ)", ".")'`; `mockup: Rscript -e 'coursepack::build_preview(".", base = "$(MOCKUP_BASE)")'` with `MOCKUP_BASE ?= local` and the `ifdef` export blocks deleted; `test` runs `Rscript scripts/test_a11y.R` only until A3.
2. `course.yml`: add a `term:` block by copying `timezone`, `first_day`, `last_day` from `announcements.yml`'s `term:` (they are the course's own dates), replacing the scalar `term: TBD`. Nothing else reads it yet.
3. `reference.yml`, new, transcribing the ten `EXPECTED` entries verbatim from `scripts/diff_against_reference.R` lines 33 to 54:

```yaml
export: reference/managerial-statistics-fall-2025-export.imscc
divergences:
  - match: "items: 72 -> 73"
    why: "modules.yml divergence 2: ch.12 homework link the export never made"
  - match: "ExternalUrl: 32 -> 33"
    why: "same added link"
  - match: "imswl_xmlv1p1: 32 -> 33"
    why: "same added link, seen as a resource"
  - match: "item added: ExternalUrl|Homework: Pricing Policy Recommendation"
    why: "same added link, seen as an item"
  - match: "webcontent: 8 -> 6"
    why: "6 wiki pages kept; udoit.json and the 1.95 MB course image omitted"
  - match: "imsbasiclti_xmlv1p0: 2 -> 0"
    why: "LTI links do not round-trip through import"
  - match: "item dropped: Assignment|Homework 7 Dropbox "
    why: "EXPORT TYPO: trailing space in the live course title, corrected here"
  - match: "item added: Assignment|Homework 7 Dropbox"
    why: "the same assignment, with the trailing space removed"
  - match: "newtab:  -> false"
    why: "EXPORT INCONSISTENCY: 2 of 10 assignments write <new_tab/> empty; normalized"
  - match: "due_at"
    why: "course.yml: Fall 2025 dates are stale and set manually after import"
```

Decision D2, recommended: point `export:` at `build/coursepack/managerial-statistics-export.imscc` (the 2026-09-02 round trip, which matches the rebuilt structure) and start the divergences list empty, adding entries as the first run reports them. The Fall 2025 export stays in `reference/` as the format record.
4. **The real-course gate.** Before repointing `coursepack:`, with the old script still in place: `Rscript scripts/build_cartridge.R`, then `Rscript -e 'coursepack::write_expected_tree("build/coursepack/staging", "project/coursepack-gate/expected-tree.txt")'` (D7: committed, not under `build/`). Then `make install-toolchain`, `make coursepack`, and `Rscript -e 'coursepack::gate_check("build/coursepack/staging", "project/coursepack-gate/expected-tree.txt")'`. A clean gate is the proof the move changed nothing for the real course. A `changed:` line is read, not regenerated.
5. `make checkyml` will report `assignment_defaults.group 'Homework' is not a declared assignment group`. That is a finding: change it to `Case Studies` with Logan's approval.
6. Logan builds the next real cartridge with the package, imports it into a throwaway shell, exports, and compares field by field (`skill/make-coursepack` Verification). Not verified until then.

**A2. After Phase 2 (package 0.2.0).** Each is an output change the course accepts on purpose; the real gate baseline is regenerated once, after all of them, in its own commit.

1. `course.yml`: `slug: econ-730` (D1, preserves the filename exactly); `due_time: "23:59:59"` (D6; seventeen `due_at` values change from `:00` to `:59`, matching what Canvas holds); `assignment_defaults.homework_intro` and `submission_note` carrying the two paragraphs the builder used to hold, verbatim:

```yaml
assignment_defaults:
  homework_intro: >-
    <p>The full directions are reproduced below. They are copied from
    <a class="inline_disabled" title="Link" href="{href}" target="_blank">{title}</a>
    in the course textbook, which is the source of record. If the two ever
    disagree, follow the textbook and tell me.</p>
  submission_note: >-
    <p>This assignment is to be conducted within the class assignment workspace provided to you.
    You will create an R Quarto document, incorporating code and analysis as demonstrated in the
    provided examples. Follow the structure provided in the example code and explanations to guide
    your analysis. Each required step should correspond to a separate section within your R Quarto
    document. Utilize the headings feature in Quarto to organize your document (<code>#</code>&nbsp;for
    main sections,&nbsp;<code>##</code>&nbsp;for subsections). Once you have completed the analysis and
    are satisfied with your document, compile it into an MS Word document and submit the document here.</p>
```

2. `modules.yml`: the seven quiz assignments gain `group: Quizzes` so the second group is emitted and routed (Task 15); the eight iframe pages change shape once (Task 17); each iframe page may carry `height_measured: "<ISO timestamp>"` so the build reports it as fresh or stale instead of undated (Task 22). `assignment_defaults.group` must name a declared group (A1 item 5), and every assignment or quiz without its own `group:` falls into it.
2b. `course.yml`: every key under `canvas:` must be one of the eleven the package knows (`course_code`, `is_public`, `indexed`, `default_view`, `license`, `grading_standard_enabled`, `group_weighting_scheme`, `restrict_enrollments_to_course_dates`, `allow_student_wiki_edits`, `restrict_student_future_view`, `restrict_student_past_view`); any other key stops the build (Task 16). `grading_standard:` and `late_policy:` stay optional. `textbook_docs:` keeps its path; `none` is for a course without a textbook (Task 20).
3. `announcements.yml`: the `term:` block may be deleted once `course.yml` carries it (Task 21). Decision D5: keep bodies under gitignored `semester/` (a clone cannot build; `semester/README.md` says so) or move them to `content/announcements/`.
4. One import into a throwaway shell verifies all of the above together, then the live course when Logan says.

**A3. After Phase 3 (package 0.3.0).**

1. `Rscript -e 'coursepack::audit_course(c(".", "/Users/logankelly/Sync/UWRF/My_Books/real-world-statistics-with-r"))'` from the primary checkout path (surface identity is a basename); diff the new findings JSON against `project/accessibility/2026-09-01-findings.json` with `diff_findings()`: 0 fixed, 0 new expected, allowing the known axe-core contrast non-determinism; announcement-body findings (Task 28) are the one expected class of new rows.
2. Makefile: `a11y: Rscript -e 'coursepack::audit_course(c(".", "$(TEXTBOOK_REPO)"))'`; `test: Rscript -e 'coursepack::check_manifests(".")'`.
3. With Logan's approval, shown as a list first: delete `scripts/audit_a11y.R`, `scripts/lib/a11y_*.R`, `scripts/test_a11y.R`.

**A4. After Phase 5 (package 0.5.0).** `Rscript -e 'coursepack::install_skills(".", overwrite = TRUE)'` installs the generalized skills into `.claude/skills/`; the four files under `skill/` gain a one-line header pointing at `inst/skills/` and stay as the record.

**A5. Deletions, last, with Logan's approval, shown as a list first:** `scripts/build_cartridge.R`, `scripts/build_preview.R`, `scripts/build_qti.R`, `scripts/check_manifests.R`, `scripts/diff_against_reference.R`, `scripts/lib/resolve.R`, `scripts/lib/homework_body.R`, `scripts/lib/quiz_body.R`, `scripts/test_preview.R`, `scripts/test_resolve.R`, `scripts/make_course_tile.R`, `templates/mockup/`. Header comments marking `build_canvas_pages.R`, `build_outlines.R`, `build_media_players.R`, `migrate_data.R`, and `scripts/quiz-artifacts/` as course-specific. `CLAUDE.md` and `TODO.md` updated (the arrival-rule section now describes a finished extraction; the stale items spec 2e lists), each content statement with Logan's approval.

# Appendix B: ECON 202 hand-offs

Everything here runs in an ECON 202 session, in that repository, under its UPDATE ONLY rule: files are added or edited only as named. Package 0.4.0 or later.

**B1. Convert (M15).**
1. `Rscript -e 'coursepack::convert_python_manifests("course.yml", "modules.yml", "build/converted")'`; read `build/converted/modules.yml` against the original; every generated quiz and assignment carries a pinned `resource_id` (Python-derived, so a re-import updates in place).
2. E5: `urls.site` loses its `/pages` suffix in the converted `course.yml`, so the stale-height mapping resolves under `docs/`; nothing else reads `site`. E6 is moot: every current group carries an `id:`.
3. Copy `econ202-export.imscc` into `reference/` (a copy; the root file stays), write `reference.yml` with `export:` and `source:` naming it, and the minimal `Makefile` from the onboarding memo item 4 (`install-toolchain`, `checkyml`, `coursepack`, `refdiff`, `mockup`, `a11y`; no render targets).
4. Move the converted manifests into place only when `check_manifests()` passes on them. The Python builder and its YAML inputs are not deleted.
5. **Equivalence gate**, declared before the run: `diff_against_reference()` against `build/modules5-13-final-v4.imscc` (the 09-04 build, not v10) reports only: the `new_tab` form on every item; the manifest, course, and settings-resource identifiers; the `course_settings.xml` element set; `files_meta.xml` and `media_tracks.xml` written empty (E4); the assignment-settings element set on generated assignments (the package's one template); the second `<title>` in quiz metas; the last module's position (17 in the source, 16 after the converter renumbers by order; its `module_id` is unchanged); the course image's href and resource id (`web_resources/course_image/course_img.png` staged from `assets/images/course-tile.png`, so copy `images/course_card_econ202_524x292.png` there first, as the converter's note says); the zip mtimes. Every carried file must be byte-identical to v4's and every generated wrapper page byte-identical apart from the `title` attribute if v4's pages lacked one. Anything else is a bug in the port or a finding about v4; stop.
6. Five further divergences, declared before the run because Phase 4 produced them (Tasks 36 and 39): a generated quiz's figure is a webcontent resource that the quiz meta resource depends on (the Python emitted it with no edge); resource attributes are written `identifier` before `type` (the Python's order differs); wiki page filenames are `wiki_content/<slugify(title)>.html` while the resource ids are pinned, so the Canvas objects are the same and only the hrefs differ; a link item's weblink resource takes a package-derived id (the schema has no override for it), so carried links are recreated on import; and `imsmanifest.xml` writes carried resource blocks in definition order rather than after the generated ones.
7. The converted `course.yml` carries no comment block (the converter copies the header comments of `modules.yml` only), so the course's deadline and weighting rationale, about twenty-six comment lines, is pasted in by hand after the conversion.

**B2. Verify (M16).** (1) `extract_manifest("reference/econ202-export.imscc", "build/roundtrip")`, build it, `diff_against_reference()` against the export itself: only the thumbnail, the objectbank, `context.xml`, and the template-versus-export page differences may appear. (2) Build the converted course and Logan imports it into a throwaway shell, exports it, and compares field by field; the iframe pages render their content; the two exams arrive with their pools intact; the module quizzes draw as declared. Then E7 (retiring `build_cartridge.py`, `generate_resources.py`, `extract_cartridge_manifest.py`, `announcements.py`) is decidable.

**B3. Announcements.** `announcements_from_schedule(".", calendar_url = "<the calendar page>")` replaces `announcements.py --announcements`; the generated bodies land under `content/announcements/` and are committed.

**B4. The paper final (M19).** `print_assessment(".", id = "<final exam definition id>", seed = <chosen>, formats = c("docx", "pdf"))` before 2026-12-22; the seed and the key are kept with the sitting.

# Appendix C: Decisions adopted as working assumptions

Each is overridable by Logan; the plan says where the override lands.

| # | Adopted | Where it lives |
|---|---|---|
| D1 | `slug:` in `course.yml`, defaulting to the slugified Canvas course code | Task 2, A2 |
| D2 | the reference export is pointed at the latest round trip; divergences declared one at a time | A1 item 3 |
| D3 | `textbook_docs: none` | Tasks 2, 8, 20 |
| D4 | `term:` block carries the timezone | Tasks 2, 3 |
| D5 | announcement body directory is declared in YAML; the scaffold uses `content/announcements/` | Tasks 2, 44; A2 |
| D6 | `due_time` in `course.yml`, no package default; seconds match Canvas | Tasks 3, 14 |
| D7 | the real-course gate baseline is committed under `project/coursepack-gate/` | A1 item 4 |
| D8 | email and package name: Logan's | Task 50 |
| D9 | skills anonymized, incidents kept | Tasks 41, 42 |
| D10 | re-opened by the question bank in `project/`; recommendation (a) in Task 50 | Task 50 |
| D11 | CONTRIBUTING says the question is open | Task 48 |
| D12 | CI browser job optional | Task 49 |
| D13 | ECON 202 direction: convert to the R schema, port the Python capabilities | Phase 4, Appendix B |
| D14 | `new-course` skill ships | Task 42 |
| D15 (new) | `$IMS-CC-FILEBASE$` is admitted for quiz figures under `web_resources/quiz_images/` only, checked file by file, because exam figures must not be public on the Pages site | Task 36 |
| E1 | dissolved: convergence happens in the package against the synthetic gate | Phase 2 |
| E2 | the R schema is the one schema | Task 39 |
| E3 | exam pools not ported; retired upstream 2026-09-04 | Phase 4 preamble |
| E4 | `files_meta.xml` and `media_tracks.xml` written empty | B1 item 5 |
| E5, E6 | hand-off | B1 |
| E7 | after M16 | B2 |
| E8 | announcements, grading standards, late policy not extracted | Task 32 |
| E9 | done 2026-09-02 upstream | none |
| decision 10 | the `{site}` local base, as read in Task 20; confirm before executing | Task 20 |

# Appendix D: Human gates

Nothing below can be done from this repository. Each is the point at which a phase's work becomes verified rather than built.

| After | Gate | Who |
|---|---|---|
| Phase 1 | the real-course byte gate in ECON 730 (A1 item 4) | Logan, ECON 730 session |
| Phase 2 | build the real cartridge with 0.2.0, import into a throwaway shell, export, compare field by field | Logan |
| Phase 3 | the real audit diff (A3 item 1) | Logan, ECON 730 session |
| Phase 4 | B1 equivalence gate; B2 two round trips and one import | Logan, ECON 202 session |
| Phase 5 | import the scaffold cartridge into a throwaway shell | Logan |
| Phase 6 | push, CI green, the checklist, the flip | Logan |
| Any | `COURSEPACK_PA11Y_TESTS=1` run on the authoring machine after each a11y task | executor |

# Appendix E: Where the old task numbers went

| Old | Here |
|---|---|
| spec Task 1 | dissolved (nothing to confirm in a course repo; the snapshots are the state) |
| spec Task 2, T02 | Tasks 1, 2 |
| spec Task 3, T05 | Task 5 (package half); A1 item 4 (course half) |
| spec Task 4, T06 | Task 6 |
| spec Task 5, T13 | Task 12 |
| spec Task 6, T08 | Task 8 |
| spec Task 7, T09 | Task 9 |
| spec Task 8, T10 | Task 10 |
| spec Task 9, T12 | Task 11 |
| spec Task 10, T14 | A5 |
| spec Task 11, T15 to T20 | Tasks 23 to 27; A3 |
| spec 12a, T11, M03 | Task 15 |
| spec 12b, M04 | Task 16 |
| spec 12c, M05 | Task 17 |
| spec 12d | Task 19 |
| spec 12e | Task 20 (the `{site}` reading) |
| spec 12f | Tasks 8, 20 |
| spec Task 13, T30, M15, M16 | Appendix B |
| T01 | dissolved |
| T03 | Task 3 |
| T04 | Task 4 (plus Tasks 29, 34 fixtures) |
| T07 | Task 7 |
| T21 | Task 28 |
| T22 | Tasks 41, 42 |
| T23 | Task 43 |
| T24 | Task 44 |
| T25, M14 | Tasks 45, 46 |
| T26 | Task 47 |
| T27 | Task 48 |
| T28 | Task 49 |
| T29 | Task 50 |
| M01 | landed upstream 2026-09-02 (the snapshot carries it) |
| M02 | Task 14 |
| M06 | Tasks 18, 21 |
| M07 | Task 29 |
| M08 | Task 30 |
| M09 | Task 31 |
| M10 | Task 22 |
| M11 | dropped (exam pools retired upstream 2026-09-04) |
| M12 | Task 32 |
| M13 | Task 33 |
| M17 | A1 item 6 variant: extract the ECON 730 round trip and diff, as a report |
| M18 | Task 48 |
| M19 | Task 40 |
| new | Task 35 (bank quizzes), 36, 37 (staged builds), 38 (schedule announcements), 39 (converter): the Python capabilities the 09-02 plans listed under 4a without tasks |

**Left behind on purpose, in the course repositories, never in the package:** ECON 730's `build_canvas_pages.R`, `build_outlines.R`, `build_media_players.R`, `migrate_data.R`, `scripts/quiz-artifacts/`, `measure_page_heights.sh`, `transcribe_media.sh` (course-specific content and media pipelines; the package's only knowledge of them is the `content/canvas/<slug>.html` input contract); ECON 202's `measure_iframe_heights.R` and `apply_iframe_heights.py` (they produce `height_measured`; the package reads it), `build_qti_groups.py` (retired with exam pools), `schedule_grid.R` and `schedule_table.R` (they render the course's own calendar page; the package reads `schedule.yml` only to write announcements), the YouTube and NotebookLM pipelines, and the dead Canvas API scripts. `session-startup` stays Logan's own opener and does not ship.

