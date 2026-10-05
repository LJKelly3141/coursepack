# Neutral Redaction Token Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop `anonymize()` from writing a student's code wherever that student's name form matches, which links one student's paper to another student (found on a real ECON 730 run: the instructor's first name matched student S04's first name, so S08's paper read "Professor Dr. S04 J. Kelly"). Add a course-level list of protected phrases (instructor, TA) so their names survive whole.

**Architecture:** `redact_text()` in `R/anon-redact.R` replaces every matched name, id, login and file prefix with one fixed token, `[name]`, that carries no code. A new `R/anon-keep.R` reads `<proj>/anon_keep.txt` and masks protected phrases around the name redaction, the image text check and the leftover check. `relink()` is unchanged: it only turns the feedback file's own code back into a name, and its guard looks only at feedback.

**Tech Stack:** R (base), testthat 3. No new package.

**Spec:** Decided with the instructor on 2026-10-04 (option 2 of the ECON 730 session's report: fix A + C + D; C as whole phrases only, in a course-root file). Restated as the Design section below; executors treat that section as the spec.

## Design (the spec)

1. **Neutral token (A).** Every match of a key term (name form, nickname, file prefix, login, Canvas id) in submission text becomes `[name]`, whichever student the term belongs to. No student code appears in submission text inside `anon/` any more (codes still name folders, the manifest and feedback files). `SXX` no longer appears in submission text either. The replacement count is unchanged in meaning (one per match). Path and email redaction (`USER`, `EMAIL`) and the fixed-pattern tokens (`[PHONE]` etc.) are unchanged.
2. **Protected phrases (C).** `<proj>/anon_keep.txt`, at the course root, one phrase per line; blank lines and lines starting with `#` are ignored. Each phrase must contain at least two words (a line without whitespace stops anonymize with a message naming the line number only); a single name can never be protected, so a student who shares the instructor's first name is still redacted in their own paper. anonymize() reads the file automatically when it exists; no argument. Matching is case-insensitive, any run of whitespace (including a line break) matches a space, and the phrase is bounded like a name form (no letter directly before or after). A protected phrase is left whole by the name redaction, does not flag an image, and is not a leftover. Text outside a protected phrase is redacted as before: "Professor Dr. Logan J. Kelly" stays whole when "Logan J. Kelly" is listed; "Thanks, Logan" becomes "Thanks, [name]".
3. **Tests and docs (D).** Fixtures: student A's document contains student B's first name; the instructor's phrase contains a student's first name. Assert A's coded text contains no student code at all, the count still reports the redaction, and a protected phrase survives. NEWS, README, roxygen, and the anonymized-grading skill say what the token looks like and how `anon_keep.txt` works.

## Global Constraints

- Messages and the de-identification log name codes, anon/ paths, counts and types only; never a name, id, login, original filename, redacted value, or a protected phrase (the log records only how many protected-phrase occurrences were kept).
- Nothing written outside the assignment folder by anonymize(); `anon_keep.txt` is read, never written.
- No new package in Imports. testthat 3; fixtures use invented names only (never the real instructor's name).
- Version 1.2.6. NEWS, DESCRIPTION, `R/coursepack-package.R` status line, `SETUP.md` install tag, as 1.2.5 did. No em-dashes in anything published.
- Never touch `inst/skills/uwrf-syllabus/` (another session's untracked work).
- Commit per task (authorized for this plan only when the instructor approves it). No push, tag move or install without the instructor's go-ahead.

## Review Focus

1. A term that is itself inside the token (a student nicknamed "name"): the redaction must not re-match its own output or inflate the count. Use a sentinel during the loop (Task 1).
2. Leftover check after a protected phrase is restored: "Logan J. Kelly" contains the term "Logan"; the check must not report it (Task 2).
3. A protected phrase split across a line break in converted markdown (Task 2).
4. Existing tests that assert a code appears in coded text: change them to assert `[name]`, and say so in the report (Task 1).
5. relink() still restores the feedback file's own code, and still refuses feedback naming another student (Task 1, no code change expected; one test confirms).

---

## File Structure

| File | Responsibility |
|---|---|
| `R/anon-redact.R` (modify) | `redact_text()` writes `[name]` via a sentinel |
| `R/anon-keep.R` (create) | `keep_path()`, `read_keep_phrases()`, `keep_rx()`, `mask_keep()`, `unmask_keep()`, `drop_keep()` |
| `R/anon-grading.R` (modify) | wire protected phrases into the text loop, the image scan and the leftover check; log count |
| `R/anon-images.R` (modify) | `scan_images()` / `text_reason()` accept `keep` and drop protected phrases before the name check |
| `tests/testthat/test-anon-redact-token.R`, `test-anon-keep.R` (create); `test-anon.R`, `test-anon-images.R` (modify) | tests |
| `DESCRIPTION`, `NEWS.md`, `R/coursepack-package.R`, `SETUP.md`, `README.md`, `inst/skills/anonymized-grading/SKILL.md`, `man/*.Rd` | docs and version |

---

### Task 1: Neutral token

**Files:** Modify `R/anon-redact.R`; create `tests/testthat/test-anon-redact-token.R`; modify `tests/testthat/test-anon.R` (and `test-anon-images.R` only if it asserts codes in text).

**Interfaces:** Produces `redact_text(text, terms) -> list(text, n)` (unchanged signature); output contains `[name]` where it used to contain a code.

- [ ] **Step 1: Failing tests**

```r
test_that("a match becomes [name] and carries no code", {
  terms <- data.frame(term = c("Pat Quill", "Quill", "Robin"), code = c("S01", "S01", "S02"),
                      loose = c(TRUE, FALSE, FALSE), stringsAsFactors = FALSE)
  r <- redact_text(c("By Pat Quill.", "Robin helped me."), terms)
  expect_equal(r$text, c("By [name].", "[name] helped me."))
  expect_equal(r$n, 2L)
  expect_false(any(grepl("S0[0-9]|SXX", r$text)))
})

test_that("the token is never re-matched", {
  terms <- data.frame(term = c("name", "Pat"), code = c("S01", "S02"),
                      loose = FALSE, stringsAsFactors = FALSE)
  r <- redact_text("Pat wrote my name here.", terms)
  expect_equal(r$text, "[name] wrote my [name] here.")
  expect_equal(r$n, 2L)
})
```

In `test-anon.R`, add an end-to-end test with the file's fixture helpers: student A's document mentions student B's first name; after anonymize(), A's coded file contains `[name]`, contains no `S\d\d` or `SXX`, and the run's `replacements` count includes it. Update every existing assertion that expected a code inside coded submission text to expect `[name]`.

- [ ] **Step 2: Run, verify the new tests fail** (`Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-anon-redact-token.R")'`).

- [ ] **Step 3: Implement**

```r
# Every match becomes [name], whichever student the term belongs to: a code
# in one student's paper would say whose name it was. A sentinel holds the
# place during the loop so a later term can never match inside the token.
NAME_TOKEN <- "[name]"
redact_text <- function(text, terms) {
  n <- 0L
  s <- "\u0001"
  for (i in seq_len(nrow(terms))) {
    p <- word_rx(terms$term[i])
    hits <- gregexpr(p, text, perl = TRUE, ignore.case = TRUE)
    n <- n + sum(vapply(hits, function(h) sum(h > 0, na.rm = TRUE), integer(1)))
    text <- gsub(p, s, text, perl = TRUE, ignore.case = TRUE)
  }
  list(text = gsub(s, NAME_TOKEN, text, fixed = TRUE), n = n)
}
```

Update the comments at the top of `R/anon-redact.R` and in `key_terms()` (R/anon-key.R) that say a term is replaced by its code or `SXX`; `key_terms()` itself is unchanged (codes there still feed `find_leftovers()` messages and relink's guard).

- [ ] **Step 4: Run** the new file, `test-anon.R`, `test-anon-images.R`, `test-anon-patterns.R`; all pass. Confirm a relink test still passes (relink restores the feedback file's own code; its foreign-student guard unchanged).

- [ ] **Step 5: Commit** `git add R/anon-redact.R R/anon-key.R tests/testthat/test-anon-redact-token.R tests/testthat/test-anon.R` (plus test-anon-images.R if changed) and `git commit -m "anon: redact names to a neutral [name] token, never a student code"`.

---

### Task 2: Protected phrases

**Files:** Create `R/anon-keep.R`, `tests/testthat/test-anon-keep.R`; modify `R/anon-grading.R`, `R/anon-images.R`, `tests/testthat/test-anon.R`, `tests/testthat/test-anon-images.R`.

**Interfaces:**
- `keep_path(proj) -> file.path(proj, "anon_keep.txt")`
- `read_keep_phrases(proj) -> character` (empty if no file; stops on a one-word line naming only its line number)
- `keep_rx(phrase) -> character` (case-insensitive is applied by callers; whitespace runs match `\s+`; letter boundaries as `word_rx()`)
- `mask_keep(text, keep) -> list(text, n)`: each protected occurrence replaced by `"\u0002<k>\u0002"` (k = phrase index), n = occurrences
- `unmask_keep(text, masked_from)`: restores each occurrence's original text (store originals in order; simplest is to keep a vector of the matched strings and restore by index token `\u0002<j>\u0002`, j = occurrence index)
- `drop_keep(text, keep) -> character`: protected occurrences replaced by a single space (for checks only)
- `scan_images(anon_dir, terms, keep = character())`, `text_reason(txt, terms, loose, keep = character())`: drop protected phrases before the name check only (paths, emails and fixed patterns still checked on the full text)

- [ ] **Step 1: Failing tests** (`test-anon-keep.R`)

```r
test_that("protected phrases survive; the same name alone does not", {
  terms <- data.frame(term = c("Logan", "Quill"), code = c("S04", "S04"),
                      loose = FALSE, stringsAsFactors = FALSE)
  keep <- c("Logan J. Kelly")
  x <- c("Professor Dr. Logan J. Kelly", "Thanks, Logan", "logan  j.\nkelly wrote")
  m <- mask_keep(x, keep)
  r <- redact_text(m$text, terms)
  out <- unmask_keep(r$text, m)
  expect_equal(out[1], "Professor Dr. Logan J. Kelly")
  expect_equal(out[2], "Thanks, [name]")
  expect_equal(out[3], "logan  j.\nkelly wrote")
  expect_equal(m$n, 2L)
})

test_that("a one-word line in anon_keep.txt stops with its line number only", {
  d <- withr::local_tempdir()
  writeLines(c("# instructor", "Logan J. Kelly", "", "Logan"), file.path(d, "anon_keep.txt"))
  expect_error(read_keep_phrases(d), "line 4")
  expect_error(read_keep_phrases(d), regexp = "^((?!Logan).)*$", perl = TRUE)
})

test_that("no file means no protected phrases", {
  expect_identical(read_keep_phrases(withr::local_tempdir()), character())
})

test_that("a protected phrase is not a leftover and does not flag an image", {
  # find_leftovers on a file containing only "Dr. Logan J. Kelly" with term "Logan"
  # and keep = "Logan J. Kelly" returns 0 rows; text_reason on that text returns NA.
})
```

Fill the last test with real assertions. In `test-anon.R`, add an end-to-end run with `anon_keep.txt` at the fixture project root containing the invented instructor phrase, where the instructor's first name equals a student's first name: the phrase survives whole in every coded file, the student's own standalone first name is `[name]`, no leftover is reported, and the log contains "protected phrases kept: <n>" and not the phrase.

- [ ] **Step 2: Run, verify they fail.**

- [ ] **Step 3: Implement** `R/anon-keep.R` per the interfaces. Wire in `anonymize()`: read `keep <- read_keep_phrases(proj)` before anything is written (so a bad file stops the run before writing, like the tesseract check); in the text loop, `mask_keep()` on `pt$text` before `redact_text()` and `unmask_keep()` after, accumulating a `kept` count; pass `keep` to `scan_images()`; change `find_leftovers(files, terms, keep = character())` to drop protected phrases from each file's text before both checks. Append to the log line list: `sprintf("protected phrases kept: %d", kept)`. Add `kept` to the console summary and the return list (`protected = kept`).

- [ ] **Step 4: Run** test-anon-keep.R, test-anon.R, test-anon-images.R, test-anon-patterns.R, test-anon-log.R, test-anon-redact-token.R; all pass.

- [ ] **Step 5: Commit** the files above: `git commit -m "anon: anon_keep.txt protects whole instructor and TA phrases from redaction"`.

---

### Task 3: Docs, skill, version, full suite

**Files:** roxygen in `R/anon-grading.R` (anonymize: the `[name]` token, `anon_keep.txt`, `protected` in `@return`); `README.md` ("Grading without student identity"); `inst/skills/anonymized-grading/SKILL.md` (what the token looks like; that the grader never sees whose name was redacted; how to set up `anon_keep.txt` at the course root, whole phrases of two or more words, e.g. "Dr. Kelly", and why single names are refused); `DESCRIPTION` (Version 1.2.6); `NEWS.md` ("# coursepack 1.2.6", the leak and the fix stated plainly); `R/coursepack-package.R`; `SETUP.md` install tag; `man/*.Rd` via `devtools::document()`.

- [ ] **Step 1:** write the doc changes. No em-dashes; no mention of AI.
- [ ] **Step 2:** `Rscript -e 'devtools::document()'`, then `Rscript -e 'devtools::test()'`. Expected: only the pre-existing uwrf-syllabus failures. Delete any `_problems` / `testthat-problems.rds`.
- [ ] **Step 3: Commit** `git add -A -- . ':!inst/skills/uwrf-syllabus'` (check `git status --short` first) and `git commit -m "Release 1.2.6: neutral redaction token and protected phrases"`. Tag `v1.2.6` only after the final review's fixes are in, and only with the instructor's go-ahead; no push, no install.
