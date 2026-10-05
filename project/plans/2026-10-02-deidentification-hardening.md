# De-identification Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close four gaps between `anonymize()` and FERPA's de-identification standard: personal details in fixed patterns, text inside images and image metadata, timing and lateness hints in the coded folder, and the missing record that de-identification was done.

**Architecture:** All four changes sit inside the existing pipeline in `R/anon-redact.R`, `R/anon-convert.R`, `R/anon-grading.R` and `R/anon-key.R`. A new `R/anon-images.R` owns image scanning and a new `R/anon-log.R` owns the de-identification log. Nothing changes in what a grader is given (`anon/` only) or in relink's outputs, except that relink and `anon_forget()` append to the log.

**Tech Stack:** R (base, `magick` already in Imports), the `tesseract` command-line program for OCR (system requirement, like pandoc), testthat 3.

**Spec:** The design approved in conversation on 2026-10-02 (items 1, 2, 3(a) and 4 of the de-identification gap list). It is restated as the Design section below; executors treat that section as the spec.

## Design (the spec)

1. **Images.** After a submission is converted, every image extracted beside it is (a) stripped of metadata (EXIF, comments, GPS, author fields) and (b) read with OCR. The OCR text is checked with the same name, id and fixed-pattern checks as the document text. An image whose text hits, and any image that cannot be scanned (a format OCR cannot read, such as `.emf` or `.wmf`), needs an instructor decision before `anon/` is released. Decisions live in `<assignment>/anon_images.csv` (columns `image,decision`, decision `keep` or `remove`), beside the key and never inside `anon/`. `remove` deletes the image from `anon/` and replaces every markdown link to it with `[image removed]`. Without a decision for every flagged image, anonymize stops naming only the code and the image path inside `anon/`, and `NOT_READY` stays.
2. **No timing or lateness hints.** `anon/manifest.csv` no longer carries `late`. Every file and folder under `anon/` gets the same modification time, so the order students were processed in (alphabetical by name in the downloads) cannot be read off the folder. Students are processed in shuffled order. Within one student, `file1`, `file2` still follow upload order (the grader needs it to know which draft came last); no date or time appears anywhere in `anon/`.
3. **Fixed-pattern redaction (3a).** Before the name redaction, document text and OCR text are scrubbed of: US Social Security numbers -> `[SSN]`; phone numbers -> `[PHONE]`; dates following "born", "DOB", "date of birth" or "birthday" -> `[DOB]`; street addresses (number, street name, street-type word) -> `[ADDRESS]`; profile URLs on GitHub, LinkedIn, X/Twitter, Instagram, Facebook, TikTok and YouTube -> `[PROFILE]`; social handles (`@name` not preceded by a word character) -> `[HANDLE]`. Counts by type are reported. A fixed pattern found in text after redaction (impossible by construction) is not a leftover; the patterns are a scrub, not a key.
4. **De-identification log.** `<assignment>/deidentification_log.md`, beside the key, never in `anon/`, appended (never rewritten) by `anonymize()`, `relink()` and `anon_forget()`. It records when, the coursepack version, counts (students, files, name replacements, fixed-pattern replacements by type, images scanned, metadata stripped, images flagged with each decision), the leftover check result, relink's feedback count and cross-student check, and the key's deletion. It never contains a name, id, login, original filename, or any redacted value. It is the record of the "reasonable determination" FERPA asks for.

## Global Constraints

- Messages and the log name codes, image paths inside `anon/`, counts and types; never a name, Canvas id, login, original filename or a redacted value.
- Nothing is written outside the assignment folder; `anon_images.csv` and `deidentification_log.md` live in the assignment folder beside `anon_key.csv`, never inside `anon/`.
- `tesseract` is a system requirement. If it is not on the PATH, `anonymize()` stops before writing anything, with an install hint (`brew install tesseract`).
- No new R package in Imports. `magick` is already imported; OCR uses the `tesseract` command line through `run_tool()`.
- Tests: testthat 3; skip with the package's `skip_if_no("tesseract")` style helper where OCR is needed; fixtures use invented names only.
- Version 1.2.5 (a fix release, per the instructor). NEWS, DESCRIPTION, `R/coursepack-package.R` status line and `SETUP.md` install tag, as earlier releases did. No em-dashes anywhere.
- Never touch `inst/skills/uwrf-syllabus/` (another session's untracked work).

## Review Focus

1. OCR of a plot produces a false name hit (axis text that happens to match a short name form). Expected: the image is flagged by path; `keep` in `anon_images.csv` releases it on re-run. Test in Task 3.
2. Statistical output that looks like a pattern (`2019-2023`, `12.5-13.5`, `0.912`, `1e-8`, an R slot `obj@slot`, a 10-digit Canvas-style number inside a table). Expected: left alone. Test in Task 1.
3. `tesseract` missing. Expected: stop before anything is written, with an install hint. Test in Task 3 (mock `Sys.which`).
4. A re-run after decisions were recorded, where an image named in `anon_images.csv` no longer exists. Expected: stale rows ignored, current images decided. Test in Task 3.
5. A removed image linked with pandoc attributes (`![](file1_media/media/image1.png){width="3in"}`). Expected: the whole link, attributes included, becomes `[image removed]`. Test in Task 3.

---

## File Structure

| File | Responsibility |
|---|---|
| `R/anon-redact.R` (modify) | add `redact_patterns()`; `redact_paths()` gains counts |
| `R/anon-images.R` (create) | `image_files()`, `strip_image_metadata()`, `ocr_image()`, `scan_images()`, `apply_image_decisions()`, `read_image_decisions()` |
| `R/anon-log.R` (create) | `log_path()`, `append_log()` |
| `R/anon-grading.R` (modify) | wire patterns, images, timing, log into `anonymize()`; log in `relink()` |
| `R/anon-key.R` (modify) | `anon_forget()` appends to the log |
| `tests/testthat/test-anon-patterns.R`, `test-anon-images.R`, `test-anon-log.R` (create); `test-anon.R` (modify) | tests |
| `DESCRIPTION`, `NEWS.md`, `R/coursepack-package.R`, `SETUP.md`, `README.md`, `inst/skills/anonymized-grading/SKILL.md`, `man/*.Rd` | docs and version |

---

### Task 1: Fixed-pattern redaction

**Files:**
- Modify: `R/anon-redact.R`
- Create: `tests/testthat/test-anon-patterns.R`

**Interfaces:**
- Produces: `redact_patterns(text) -> list(text = character, counts = named integer c(SSN=, PHONE=, DOB=, ADDRESS=, PROFILE=, HANDLE=))`; `redact_paths(text, counts = FALSE)`: unchanged when `counts = FALSE`; when TRUE returns `list(text, counts = c(PATH=, EMAIL=))`.

- [ ] **Step 1: Write the failing tests**

```r
test_that("fixed patterns are redacted by type, with counts", {
  x <- c("Call me at (715) 555-0142 or 715.555.0199.",
         "SSN 123-45-6789 on file.",
         "I was born on March 4, 2003 and my DOB: 03/04/2003.",
         "I live at 1410 N Main Street in town.",
         "See github.com/patquill and https://www.linkedin.com/in/pat-quill-12",
         "Follow @patq_22 for updates.")
  r <- redact_patterns(x)
  expect_equal(r$text[1], "Call me at [PHONE] or [PHONE].")
  expect_equal(r$text[2], "SSN [SSN] on file.")
  expect_equal(r$text[3], "I was born on [DOB] and my DOB: [DOB].")
  expect_equal(r$text[4], "I live at [ADDRESS] in town.")
  expect_equal(r$text[5], "See [PROFILE] and [PROFILE]")
  expect_equal(r$text[6], "Follow [HANDLE] for updates.")
  expect_equal(unname(r$counts[c("PHONE","SSN","DOB","ADDRESS","PROFILE","HANDLE")]),
               c(2L, 1L, 2L, 1L, 2L, 1L))
})

test_that("statistical output and code are left alone", {
  keep <- c("Years 2019-2023, range 12.5-13.5, R^2 0.912, tol 1e-8.",
            "summary(fit)@coef and obj@slot are R slots.",
            "Canvas id 10970338 and 114224481 in a table.",
            "Estimate -63.2274 SE 107.0997 t -0.590 p 0.5581",
            "Dates 2026-09-30 and 09/30/2026 with no birth context.",
            "Route 66 Road Trip is a phrase.")
  expect_identical(redact_patterns(keep)$text, keep)
})
```

Note on the last line: `Route 66 Road Trip` must stay. The address pattern requires a street-type word right after one to three capitalized name words that follow the number, and the street name must not itself be a street-type word; "66 Road Trip" has no name word between the number and "Road".

- [ ] **Step 2: Run to verify they fail**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-anon-patterns.R")'`
Expected: FAIL, `could not find function "redact_patterns"`.

- [ ] **Step 3: Implement**

Append to `R/anon-redact.R`:

```r
# Fixed patterns that identify a person without naming them. Applied before
# the name redaction, to document text and to OCR text. Each match becomes a
# bracketed type token; counts are reported by type, never the value.
STREET_TYPES <- c("Street","St","Avenue","Ave","Road","Rd","Drive","Dr","Lane",
                  "Ln","Boulevard","Blvd","Court","Ct","Way","Place","Pl",
                  "Circle","Cir","Trail","Trl","Parkway","Pkwy","Highway","Hwy")

# Each entry: the pattern and its replacement. DOB keeps its label ("born on",
# "DOB:") and replaces only the date; PCRE has no variable-length lookbehind,
# so the label is captured and written back as \\1\\2.
PII_PATTERNS <- list(
  SSN   = list(p = "(?<![0-9-])[0-9]{3}-[0-9]{2}-[0-9]{4}(?![0-9-])", r = "[SSN]"),
  PHONE = list(p = "(?<![0-9.\\-])(?:\\+?1[ .\\-]?)?(?:\\([0-9]{3}\\)\\s?|[0-9]{3}[ .\\-])[0-9]{3}[ .\\-][0-9]{4}(?![0-9.\\-])",
               r = "[PHONE]"),
  DOB   = list(p = paste0("(?i)\\b(born(?: on)?|dob|d\\.o\\.b\\.|date of birth|birthday)([:\\s]{1,3})",
                          "(?:[0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4}|[0-9]{4}-[0-9]{2}-[0-9]{2}|",
                          "(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\\.?\\s+[0-9]{1,2},?\\s+[0-9]{4})"),
               r = "\\1\\2[DOB]"),
  PROFILE = list(p = paste0("(?i)(?:https?://)?(?:www\\.)?",
                            "(?:github\\.com|linkedin\\.com/in|twitter\\.com|x\\.com|instagram\\.com|",
                            "facebook\\.com|tiktok\\.com/@?|youtube\\.com/(?:@|c/|channel/|user/))",
                            "/?[A-Za-z0-9_.\\-]+/?"),
                 r = "[PROFILE]"),
  HANDLE = list(p = "(?<![A-Za-z0-9_@.)\\]])@[A-Za-z0-9_]{2,30}\\b", r = "[HANDLE]"),
  ADDRESS = list(p = paste0("\\b[0-9]{1,6}\\s+(?:[NSEW]\\.?\\s+)?",
                            "(?:(?!(?:", paste(STREET_TYPES, collapse = "|"), ")\\b)[A-Z][a-z]+\\s+){1,3}",
                            "(?:", paste(STREET_TYPES, collapse = "|"), ")\\b\\.?"),
                 r = "[ADDRESS]")
)

redact_patterns <- function(text) {
  counts <- integer(0)
  for (type in names(PII_PATTERNS)) {
    p <- PII_PATTERNS[[type]]$p
    hits <- gregexpr(p, text, perl = TRUE)
    counts[type] <- sum(vapply(hits, function(h) sum(h > 0), integer(1)))
    text <- gsub(p, PII_PATTERNS[[type]]$r, text, perl = TRUE)
  }
  list(text = text, counts = counts)
}
```

Change `redact_paths()` to optionally count:

```r
redact_paths <- function(text, counts = FALSE) {
  n_path <- 0L
  p1 <- "(?i)(/users/|/hom[e]/)[^/\\\\\\s]+"
  p2 <- "(?i)([A-Za-z]:(?:\\\\)+Users(?:\\\\)+)[^\\\\\\s]+"
  p3 <- "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
  cnt <- function(p) sum(vapply(gregexpr(p, text, perl = TRUE), function(h) sum(h > 0), integer(1)))
  n_path <- cnt(p1) + cnt(p2); n_email <- cnt(p3)
  text <- gsub(p1, "\\1USER", text, perl = TRUE)
  text <- gsub(p2, "\\1USER", text, perl = TRUE)
  text <- gsub(p3, "EMAIL", text, perl = TRUE)
  if (isTRUE(counts)) list(text = text, counts = c(PATH = n_path, EMAIL = n_email)) else text
}
```

Emails are replaced before `redact_patterns()` runs (the anonymize order is paths, patterns, names), so `HANDLE` never sees the local part of an email; the HANDLE lookbehind also excludes a preceding `.`, `)` or `]` so R slot access like `summary(fit)@coef` is left alone.

- [ ] **Step 4: Run to verify they pass**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-anon-patterns.R")'`
Expected: PASS. If a negative case fails, tighten that one pattern and re-run both tests; never loosen a positive case to pass.

- [ ] **Step 5: Commit**

```bash
git add R/anon-redact.R tests/testthat/test-anon-patterns.R
git commit -m "anon: redact fixed personal-detail patterns (SSN, phone, DOB, address, profiles, handles)"
```

---

### Task 2: De-identification log

**Files:**
- Create: `R/anon-log.R`, `tests/testthat/test-anon-log.R`

**Interfaces:**
- Produces: `log_path(assignment_dir) -> character` (`file.path(assignment_dir, "deidentification_log.md")`); `append_log(assignment_dir, event, lines) -> invisible(path)`: appends `## <event>, <ISO time>, coursepack <version>` then the given bullet lines, creating the file with a one-line header if absent.

- [ ] **Step 1: Write the failing test**

```r
test_that("append_log appends, never rewrites, and carries the version", {
  d <- withr::local_tempdir()
  append_log(d, "anonymize", c("students: 3", "files: 4"))
  append_log(d, "relink", "feedback files: 3")
  txt <- readLines(log_path(d))
  expect_equal(txt[1], "# De-identification log")
  expect_true(any(grepl("^## anonymize, .*coursepack ", txt)))
  expect_true(any(grepl("^## relink, ", txt)))
  expect_true(which(grepl("^## anonymize", txt)) < which(grepl("^## relink", txt)))
  expect_true("- students: 3" %in% txt)
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-anon-log.R")'`
Expected: FAIL, `could not find function "append_log"`.

- [ ] **Step 3: Implement**

```r
# The de-identification log: the record that each grading run was
# de-identified and how. Lives beside the key, never inside anon/. Appended,
# never rewritten. Holds counts, types, codes and anon/ paths only.
log_path <- function(assignment_dir) file.path(assignment_dir, "deidentification_log.md")

append_log <- function(assignment_dir, event, lines) {
  p <- log_path(assignment_dir)
  head <- if (file.exists(p)) character() else c("# De-identification log", "")
  stamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  block <- c(head, sprintf("## %s, %s, coursepack %s", event, stamp, coursepack_version()),
             "", paste0("- ", lines), "")
  cat(block, file = p, sep = "\n", append = TRUE)
  invisible(p)
}
```

- [ ] **Step 4: Run to verify it passes** (same command). Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/anon-log.R tests/testthat/test-anon-log.R
git commit -m "anon: append-only de-identification log beside the key"
```

---

### Task 3: Images: strip metadata, OCR, decisions

**Files:**
- Create: `R/anon-images.R`, `tests/testthat/test-anon-images.R`

**Interfaces:**
- Consumes: `run_tool()`, `redact_paths()`, `redact_patterns()`, `word_rx()`, `loose_terms()` (existing / Task 1).
- Produces:
  - `image_files(dir) -> character` (all files under `dir` recursively whose extension is in `IMAGE_EXTS`)
  - `IMAGE_EXTS <- c("png","jpg","jpeg","gif","bmp","tif","tiff","webp","emf","wmf","svg")`; `OCR_EXTS <- c("png","jpg","jpeg","gif","bmp","tif","tiff","webp")`
  - `strip_image_metadata(path) -> logical` (TRUE if stripped)
  - `ocr_image(path) -> character` (OCR text; requires tesseract)
  - `scan_images(anon_dir, terms) -> data.frame(image, code, reason)`: `image` is the path relative to `anon_dir`, `code` the student folder, `reason` one of `"name"`, `"pattern"`, `"unscannable"`; also attribute `"scanned"` (integer) and `"stripped"` (integer)
  - `read_image_decisions(assignment_dir) -> data.frame(image, decision)` (empty if no file)
  - `apply_image_decisions(anon_dir, flagged, decisions) -> list(removed = int, kept = int, undecided = data.frame)`

- [ ] **Step 1: Write the failing tests**

```r
make_png <- function(path, label) {
  img <- magick::image_blank(600, 120, "white")
  img <- magick::image_annotate(img, label, size = 40, location = "+10+30", color = "black")
  img <- magick::image_comment(img, "author Pat Quill")
  magick::image_write(img, path, format = "png")
}
fake_terms <- function() data.frame(term = c("Pat Quill", "Quill"), code = "S01",
                                    loose = c(TRUE, FALSE), stringsAsFactors = FALSE)

test_that("metadata is stripped from extracted images", {
  d <- withr::local_tempdir(); p <- file.path(d, "a.png"); make_png(p, "y = 3x")
  expect_true(strip_image_metadata(p))
  expect_identical(magick::image_comment(magick::image_read(p)), "")
})

test_that("an image showing a name is flagged; a plot label is not", {
  skip_if_no("tesseract")
  a <- withr::local_tempdir(); dir.create(file.path(a, "S01", "file1_media"), recursive = TRUE)
  make_png(file.path(a, "S01", "file1_media", "name.png"), "Written by Pat Quill")
  make_png(file.path(a, "S01", "file1_media", "plot.png"), "MSRP vs MPG")
  f <- scan_images(a, fake_terms())
  expect_equal(f$image, "S01/file1_media/name.png")
  expect_equal(f$code, "S01"); expect_equal(f$reason, "name")
  expect_equal(attr(f, "scanned"), 2L)
})

test_that("an unscannable image is flagged for a decision", {
  skip_if_no("tesseract")
  a <- withr::local_tempdir(); dir.create(file.path(a, "S02", "file1_media"), recursive = TRUE)
  writeBin(as.raw(1:10), file.path(a, "S02", "file1_media", "chart.emf"))
  f <- scan_images(a, fake_terms())
  expect_equal(f$reason, "unscannable")
})

test_that("decisions remove an image and its link, keep another, and ignore stale rows", {
  a <- withr::local_tempdir(); m <- file.path(a, "S01", "file1_media"); dir.create(m, recursive = TRUE)
  file.create(file.path(m, c("x.png", "y.png")))
  writeLines(c("See ![](file1_media/x.png){width=\"3in\"} here.",
               "And ![plot](file1_media/y.png)."), file.path(a, "S01", "file1.md"))
  flagged <- data.frame(image = c("S01/file1_media/x.png", "S01/file1_media/y.png"),
                        code = "S01", reason = "name")
  dec <- data.frame(image = c("S01/file1_media/x.png", "S01/file1_media/y.png", "S09/gone.png"),
                    decision = c("remove", "keep", "remove"))
  r <- apply_image_decisions(a, flagged, dec)
  expect_equal(c(r$removed, r$kept), c(1L, 1L)); expect_equal(nrow(r$undecided), 0L)
  expect_false(file.exists(file.path(m, "x.png")))
  md <- readLines(file.path(a, "S01", "file1.md"))
  expect_equal(md[1], "See [image removed] here.")
  expect_equal(md[2], "And ![plot](file1_media/y.png).")
})

test_that("ocr_image stops with an install hint when tesseract is missing", {
  local_mocked_bindings(Sys.which = function(names) c(tesseract = ""), .package = "base")
  expect_error(ocr_image("x.png"), "brew install tesseract")
})
```

- [ ] **Step 2: Run to verify they fail**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-anon-images.R")'`
Expected: FAIL, functions not found. (If `local_mocked_bindings` cannot mock a base function in this testthat version, replace that test with one that calls a small wrapper `tesseract_path <- function() Sys.which("tesseract")[[1]]` and mocks `tesseract_path` instead; `ocr_image()` must use that wrapper.)

- [ ] **Step 3: Implement `R/anon-images.R`**

```r
# Images extracted from submissions. Each is stripped of metadata and read
# with OCR; the OCR text gets the same checks as the document text. Anything
# that hits, and anything OCR cannot read, waits for an instructor decision in
# <assignment>/anon_images.csv (image,decision with keep|remove).
IMAGE_EXTS <- c("png","jpg","jpeg","gif","bmp","tif","tiff","webp","emf","wmf","svg")
OCR_EXTS <- c("png","jpg","jpeg","gif","bmp","tif","tiff","webp")

image_files <- function(dir) {
  f <- list.files(dir, recursive = TRUE, full.names = TRUE)
  f[tolower(tools::file_ext(f)) %in% IMAGE_EXTS]
}

strip_image_metadata <- function(path) {
  if (!tolower(tools::file_ext(path)) %in% OCR_EXTS) return(FALSE)
  fmt <- magick::image_info(magick::image_read(path))$format[1]
  img <- magick::image_strip(magick::image_read(path))
  magick::image_write(img, path, format = tolower(fmt))
  TRUE
}

tesseract_path <- function() Sys.which("tesseract")[[1]]

ocr_image <- function(path) {
  if (!nzchar(tesseract_path())) {
    stop("tesseract is not installed; image text cannot be checked. ",
         "Install it (brew install tesseract) and re-run.", call. = FALSE)
  }
  paste(run_tool("tesseract", c(shQuote(path), "stdout", "--psm", "11")), collapse = "\n")
}

scan_images <- function(anon_dir, terms) {
  imgs <- image_files(anon_dir)
  loose <- loose_terms(terms)
  out <- data.frame(image = character(), code = character(), reason = character(),
                    stringsAsFactors = FALSE)
  stripped <- 0L
  for (p in imgs) {
    rel <- sub(paste0("^", rx_escape(normalizePath(anon_dir)), "/?"), "", normalizePath(p))
    code <- strsplit(rel, "/", fixed = TRUE)[[1]][1]
    if (!tolower(tools::file_ext(p)) %in% OCR_EXTS) {
      out <- rbind(out, data.frame(image = rel, code = code, reason = "unscannable"))
      next
    }
    if (strip_image_metadata(p)) stripped <- stripped + 1L
    txt <- redact_paths(ocr_image(p))
    low <- tolower(txt)
    name_hit <- any(vapply(terms$term, function(t) grepl(word_rx(t), txt, perl = TRUE,
                                                         ignore.case = TRUE), TRUE)) ||
      any(vapply(loose$term, function(t) grepl(t, low, fixed = TRUE), TRUE))
    pat_hit <- sum(redact_patterns(txt)$counts) > 0
    if (name_hit || pat_hit) {
      out <- rbind(out, data.frame(image = rel, code = code,
                                   reason = if (name_hit) "name" else "pattern"))
    }
  }
  attr(out, "scanned") <- length(imgs)
  attr(out, "stripped") <- stripped
  out
}

read_image_decisions <- function(assignment_dir) {
  p <- file.path(assignment_dir, "anon_images.csv")
  if (!file.exists(p)) return(data.frame(image = character(), decision = character()))
  d <- utils::read.csv(p, colClasses = "character", na.strings = character(),
                       strip.white = TRUE)
  if (!all(c("image", "decision") %in% names(d))) {
    stop("anon_images.csv needs the columns image,decision", call. = FALSE)
  }
  bad <- !tolower(d$decision) %in% c("keep", "remove")
  if (any(bad)) stop("anon_images.csv: decision must be keep or remove", call. = FALSE)
  d$decision <- tolower(d$decision)
  d
}

apply_image_decisions <- function(anon_dir, flagged, decisions) {
  m <- match(flagged$image, decisions$image)
  undecided <- flagged[is.na(m), , drop = FALSE]
  dec <- decisions$decision[m]
  removed <- 0L; kept <- 0L
  for (i in which(!is.na(m))) {
    if (dec[i] == "keep") { kept <- kept + 1L; next }
    rel <- flagged$image[i]
    unlink(file.path(anon_dir, rel))
    code <- flagged$code[i]
    inside <- sub(paste0("^", rx_escape(code), "/"), "", rel)
    link <- paste0("!\\[[^\\]]*\\]\\(", rx_escape(inside), "\\)(\\{[^}]*\\})?")
    for (md in list.files(file.path(anon_dir, code), "\\.md$", full.names = TRUE)) {
      txt <- readLines(md, warn = FALSE, encoding = "UTF-8")
      writeLines(gsub(link, "[image removed]", txt, perl = TRUE), md, useBytes = TRUE)
    }
    removed <- removed + 1L
  }
  list(removed = removed, kept = kept, undecided = undecided)
}
```

- [ ] **Step 4: Run to verify they pass** (same command). Expected: PASS (OCR tests skip only where tesseract is absent).

- [ ] **Step 5: Commit**

```bash
git add R/anon-images.R tests/testthat/test-anon-images.R
git commit -m "anon: strip image metadata, OCR images, and hold flagged ones for a decision"
```

---

### Task 4: Wire it into anonymize(), relink() and anon_forget()

**Files:**
- Modify: `R/anon-grading.R` (anonymize ~158-257, relink success path), `R/anon-key.R` (anon_forget), `tests/testthat/test-anon.R`

**Interfaces:**
- Consumes: everything from Tasks 1 to 3.
- Produces: anonymize's return list gains `patterns` (named integer), `images` (list scanned, stripped, flagged, removed, kept).

- [ ] **Step 1: Write the failing tests** (add to `tests/testthat/test-anon.R`, using the file's existing fixture helpers for a key and a Canvas-named submission)

```r
test_that("the coded folder carries no lateness or timing", {
  # build a fixture assignment with one LATE and one on-time submission
  # (use the existing helpers that write quillpat_LATE_1001_5001_x.md etc.)
  res <- anonymize(p, "semester/A1", dict = NULL)
  man <- utils::read.csv(file.path(a, "anon", "manifest.csv"))
  expect_false("late" %in% names(man))
  info <- file.info(list.files(file.path(a, "anon"), recursive = TRUE,
                               full.names = TRUE, include.dirs = TRUE))
  expect_equal(length(unique(as.numeric(info$mtime))), 1L)
})

test_that("anonymize redacts fixed patterns and logs counts, with no names in the log", {
  # fixture text: "Reach me at 715-555-0142. Pat Quill"
  res <- anonymize(p, "semester/A1", dict = NULL)
  txt <- readLines(file.path(a, "anon", code_for_fixture, "file1.md"))
  expect_true(any(grepl("[PHONE]", txt, fixed = TRUE)))
  log <- readLines(file.path(a, "deidentification_log.md"))
  expect_true(any(grepl("fixed patterns: PHONE 1", log, fixed = TRUE)))
  expect_false(any(grepl("Quill|715-555|1001", log)))
})

test_that("a flagged image holds anon/ at NOT_READY until decided, then releases", {
  skip_if_no("tesseract"); skip_if_no("pandoc")
  # fixture: a .docx (built with pandoc from markdown embedding a PNG that reads "Pat Quill")
  expect_error(anonymize(p, "semester/A1", dict = NULL), "anon_images.csv")
  expect_true(file.exists(file.path(a, "anon", "NOT_READY")))
  flagged_rel <- ...  # read from the error message or list image_files() under anon/
  utils::write.csv(data.frame(image = flagged_rel, decision = "remove"),
                   file.path(a, "anon_images.csv"), row.names = FALSE)
  anonymize(p, "semester/A1", dict = NULL)
  expect_false(file.exists(file.path(a, "anon", "NOT_READY")))
  expect_false(file.exists(file.path(a, "anon", flagged_rel)))
})

test_that("relink and anon_forget append to the log", {
  # after a successful anonymize + fixture feedback + relink + anon_forget
  log <- readLines(file.path(a, "deidentification_log.md"))
  expect_true(any(grepl("^## relink, ", log)))
  expect_true(any(grepl("^## anon_forget, ", log)))
})
```

Replace the `...` and fixture placeholders above with the file's own helpers when writing the tests; the assertions are the requirement. The flagged image's relative path is `<code>/file1_media/media/image1.png` for a pandoc-extracted .docx image (read the code from `manifest.csv`).

- [ ] **Step 2: Run to verify they fail**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-anon.R")'`
Expected: the four new tests FAIL; all existing tests still pass.

- [ ] **Step 3: Implement in `anonymize()`**

Changes, in order, in the body after `terms <- key_terms(...)`:

```r
  if (!nzchar(tesseract_path())) {
    stop("tesseract is not installed; image text cannot be checked. ",
         "Install it (brew install tesseract) and re-run.", call. = FALSE)
  }
```
(placed BEFORE `dir.create(anon_dir ...)` and the unlink, so nothing is written).

Process in shuffled order:

```r
  n <- 0L
  pattern_counts <- c(SSN = 0L, PHONE = 0L, DOB = 0L, ADDRESS = 0L, PROFILE = 0L, HANDLE = 0L)
  path_counts <- c(PATH = 0L, EMAIL = 0L)
  for (r in shuffle(seq_len(nrow(subs)))) {
    s <- subs[r, ]
    ... existing convert_to_text call ...
    rp <- redact_paths(readLines(out_md, warn = FALSE, encoding = "UTF-8"), counts = TRUE)
    path_counts <- path_counts + rp$counts
    pt <- redact_patterns(rp$text)
    pattern_counts <- pattern_counts + pt$counts[names(pattern_counts)]
    red <- redact_text(pt$text, terms)
    writeLines(red$text, out_md, useBytes = TRUE)
    n <- n + red$n
  }
```

Manifest without `late`:

```r
  utils::write.csv(data.frame(code = subs$code, file = subs$anon_name,
                              ext = tolower(tools::file_ext(subs$file)), spec = subs$spec,
                              target = subs$target),
                   file.path(anon_dir, "manifest.csv"), row.names = FALSE)
```

Images, after the manifest and before the leftover check:

```r
  flagged <- scan_images(anon_dir, terms)
  decided <- apply_image_decisions(anon_dir, flagged, read_image_decisions(assignment_dir))
  if (nrow(decided$undecided)) {
    for (i in seq_len(nrow(decided$undecided))) {
      message("IMAGE: ", decided$undecided$image[i], " (", decided$undecided$reason[i],
              ") needs a decision")
    }
    stop(nrow(decided$undecided), " image(s) need a decision before anon/ is ready. ",
         "Open each listed image under anon/, then add a row per image to ",
         "anon_images.csv beside the key: image,decision with keep or remove. ",
         "Re-run anonymize().", call. = FALSE)
  }
```

Note: a re-run rebuilds `anon/`, so decisions are re-applied each run from `anon_images.csv`; image paths are stable because codes and file positions are stable for the same run.

Uniform timestamps, just before `unlink(NOT_READY)`:

```r
  all_paths <- list.files(anon_dir, recursive = TRUE, full.names = TRUE,
                          include.dirs = TRUE, all.files = TRUE)
  epoch <- as.POSIXct("2000-01-01 00:00:00", tz = "UTC")
  invisible(Sys.setFileTime(c(all_paths, anon_dir), epoch))
```
(`NOT_READY` is removed after this; its removal changes `anon_dir`'s own mtime, so call `Sys.setFileTime(anon_dir, epoch)` once more after the unlink.)

Log, after the leftover check passes:

```r
  pc <- pattern_counts[pattern_counts > 0]
  append_log(assignment_dir, "anonymize", c(
    sprintf("students: %d; files: %d", length(unique(subs$code)), nrow(subs)),
    sprintf("name and id replacements: %d", n),
    sprintf("home-folder paths: %d; email addresses: %d", path_counts[["PATH"]], path_counts[["EMAIL"]]),
    sprintf("fixed patterns: %s", if (length(pc)) paste(names(pc), pc, collapse = ", ") else "none"),
    sprintf("images: %d scanned, %d metadata stripped, %d flagged (%d removed, %d kept by instructor decision)",
            attr(flagged, "scanned"), attr(flagged, "stripped"), nrow(flagged),
            decided$removed, decided$kept),
    "leftover check: 0 leftovers",
    "manifest: no lateness or submission times; all anon/ timestamps set to one value"))
```

Extend the console summary to print the pattern and image counts, and the return list:

```r
  invisible(list(students = length(unique(subs$code)), files = nrow(subs), replacements = n,
                 patterns = pattern_counts,
                 images = list(scanned = attr(flagged, "scanned"), stripped = attr(flagged, "stripped"),
                               flagged = nrow(flagged), removed = decided$removed, kept = decided$kept)))
```

In `relink()`, after the zip check passes and before `version_line("relink")`:

```r
  append_log(assignment_dir, "relink", c(
    sprintf("feedback files written: %d", length(finished)),
    "cross-student check: passed",
    "zip entries match target submission names exactly"))
```

In `anon_forget()`, after the key file is removed:

```r
  append_log(assignment_dir, "anon_forget", "key deleted; this run's codes can no longer be linked to students")
```

- [ ] **Step 4: Run the full anon tests**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-anon.R")'`
Expected: PASS, including every pre-existing test. An existing test that asserted a `late` manifest column changes only to assert its absence; say so in the report.

- [ ] **Step 5: Commit**

```bash
git add R/anon-grading.R R/anon-key.R tests/testthat/test-anon.R
git commit -m "anonymize: patterns, image checks, no timing hints, and the de-identification log"
```

---

### Task 5: Docs, skill, version, full suite

**Files:**
- Modify: roxygen in `R/anon-grading.R`, `R/anon-key.R`; `README.md` ("Grading without student identity"); `inst/skills/anonymized-grading/SKILL.md`; `DESCRIPTION` (Version 1.2.5; SystemRequirements adds "tesseract, for checking text in submitted images"); `NEWS.md` ("# coursepack 1.2.5"); `R/coursepack-package.R`; `SETUP.md` (install tag; add tesseract to the install table); `man/*.Rd` via `devtools::document()`.

- [ ] **Step 1: Write the doc changes**

SKILL.md additions, in the anonymize step:
- anonymize now also redacts phone numbers, SSNs, birth dates, street addresses, profile URLs and handles, and reads text in images.
- When it stops on images: open each listed image yourself (the instructor, on the instructor's machine), then write `anon_images.csv` beside the key with `image,decision` rows (`keep` or `remove`) and re-run. The agent never opens the images; it may relay the list of paths.
- After the run, the instructor can read `deidentification_log.md` beside the key; it holds counts only and is the record of de-identification. Keep it with the course records; `anon_forget()` does not delete it.
- The coded folder no longer shows lateness or submission times.

README: one short paragraph covering the same four points and the tesseract requirement.

- [ ] **Step 2: Regenerate docs and run the full suite**

Run: `Rscript -e 'devtools::document()'` then `Rscript -e 'devtools::test()'`
Expected: all new and existing anon tests pass; the only failures are the pre-existing ones from the untracked `inst/skills/uwrf-syllabus/` (`test-scrub.R`, `test-skills-content.R`). Delete any `tests/testthat/_problems` or `testthat-problems.rds` left behind.

- [ ] **Step 3: Commit**

```bash
git add -A -- . ':!inst/skills/uwrf-syllabus'
git commit -m "Release 1.2.5: de-identification hardening"
git tag -a v1.2.5 -m "coursepack 1.2.5"
```

(Push, and install from the tag with `git archive v1.2.5 | tar -x -C <tmp> && R CMD INSTALL <tmp>`, only with the instructor's go-ahead.)
