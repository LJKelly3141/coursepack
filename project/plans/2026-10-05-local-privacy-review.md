# Privacy Sweep Gate (1.3.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the order "anonymize, then the local privacy sweep, then and only then grading" enforced by the tooling: `anonymize()` releases `anon/` only to a SWEEP_PENDING state, and a new exported `anon_sweep()` (a local vision model, Gemma in LM Studio on localhost) is the only thing that can clear it.

**Why (2026-10-05):** on Case Studies 5 and 6 frontier graders were started while the sweep was still running. Nothing in the toolchain stopped them; the sweep was a script in a trial folder and the order was advice. The instructor's rule: "Grading should first be anonymized. Then checked by Gemma. Then and only then is it graded by the frontier model."

**Architecture:** A new `R/anon-review.R` owns the model call (OpenAI-compatible chat API on localhost, structured JSON output), a content-hash cache beside the key, and applying findings. `anonymize()` ends by writing `anon/SWEEP_PENDING` instead of leaving `anon/` open. `anon_sweep(proj, assignment)` reads every coded file with its images, redacts verified text findings, holds flagged images and long findings for the instructor, and replaces SWEEP_PENDING with `anon/SWEEP_PASSED` only when every file was reviewed and every held item is decided. `relink()` refuses an `anon/` that never passed. The anonymized-grading skill forbids dispatching a grader while SWEEP_PENDING exists.

**Tech Stack:** R, jsonlite and digest (already imported), curl (new, in Suggests, needed by `anon_sweep()`), testthat 3 with mocked model calls. LM Studio with `gemma-4-31b-it-mlx` for real runs.

**Spec:** The design agreed with the instructor on 2026-10-05, restated as the Design section below. Evidence it rests on: the Case Study 3 trials in the ECON 730 repo, `semester/fall-2026/CaseStudy03/gemma_trial/privacy/` (real papers: 4 of 5 leftover code tokens caught, 0 false flags, 0 invented; planted test: 78 of 78 invented identifiers caught, 0 new false flags; about 16 to 31 minutes for 26 files). The working prototype is `gemma_privacy_sweep.R` and `sweep_prompt.md` in that folder; read them, do not copy student data from that folder.

## Design (the spec)

0. **The gate.** Three states of `anon/`, each a marker file inside it: `NOT_READY` (anonymize running or stopped, as today), `SWEEP_PENDING` (anonymize finished; not yet swept; NO GRADER MAY READ anon/), `SWEEP_PASSED` (swept and every held item decided; grading may start). `anonymize()` now ends by removing NOT_READY and writing SWEEP_PENDING (text of the marker: "Privacy sweep not done. Do not grade. Run coursepack::anon_sweep()."); its final console line says so. Re-running `anonymize()` always returns to SWEEP_PENDING (it rebuilds anon/); the sweep cache makes the re-sweep fast. `anon_sweep()` writes SWEEP_PASSED only when: every coded file got a valid reply (0 failed), every held text finding has a decision in `anon_review.csv`, and every image it flagged has a decision in `anon_images.csv`. Otherwise SWEEP_PENDING stays and it stops naming what is missing (codes, files, counts). `relink()` refuses unless `anon/SWEEP_PASSED` exists, or the log records an instructor waiver (item 13). There is no fallback that releases the folder when the model is unavailable.
1. **An exported function.** `anon_sweep(proj, assignment, anon_dir = NULL, model = "gemma-4-31b-it-mlx", url = "http://localhost:1234", context = NULL)`, the same `proj`/`assignment` style as `anonymize()` and `relink()`. It refuses an `anon/` with NOT_READY ("finish anonymize() first") and does nothing but report on one already SWEEP_PASSED unless `force = TRUE`.
2. **Local only.** `url` must be `http://localhost` or `http://127.0.0.1` (any port); anything else stops. Nothing is sent anywhere else.
3. **Check before anything.** `anon_sweep()` first checks that the `curl` package is installed, that the server answers `GET <url>/v1/models`, and that `model` is in its list. Each failure stops with an instruction (`install.packages("curl")`, `lms server start`, `lms load <model>`) and leaves SWEEP_PENDING in place.
4. **What is reviewed.** Each coded `.md` file in `anon/` (from the manifest) is sent with that file's own images (png, jpg, jpeg, gif, webp under `<file>_media/`), one request at a time. The prompt is `inst/review/prompt.md` (shipped), plus the instructor phrases from `anon_keep.txt` ("never flag") and the terms in `review_context` (a file path; default `<assignment>/review_context.txt` when present; one term per line, `#` comments allowed) ("course and data terms, never flag").
5. **What comes back.** Structured JSON: a list of findings, each with `text`, `kind` (person_name, organization, place, contact, id_number, personal_detail, signature, code_token, image_person, image_name, image_account, other), `where` (text or image), `image_number`, `reason`.
6. **Text findings: flag and redact.** A text finding is applied only when its text occurs in the file (case-insensitive, exact characters); otherwise it is counted as unverified and ignored. A verified finding is replaced everywhere in that file by a token by kind: person_name, signature, code_token -> `[name]`; organization -> `[ORG]`; place -> `[PLACE]`; contact -> `[CONTACT]`; id_number -> `[ID]`; personal_detail -> `[DETAIL]`; other -> `[REDACTED]`. Never inside a protected phrase from `anon_keep.txt` (masked during replacement). Never a finding that is itself only a redaction token, or that equals (case-insensitive) a `review_context` term. A finding longer than 200 characters is not replaced automatically; it is held (see 8).
7. **Image findings: held for a decision.** An image the model flags is held with reason `review`: SWEEP_PENDING stays until `anon_images.csv` beside the key says keep or remove for it. `anon_sweep()` applies those decisions itself with the existing `apply_image_decisions()` (remove deletes the image and replaces its links with `[image removed]`). An image_number that does not match an attached image holds every image of that file.
8. **The instructor's record and undo.** `anon_review.csv` beside the key (never in `anon/`) lists every text finding: `code,file,kind,text,action,decision`. `action` is what the run did (`redacted`, `unverified`, `held`); `decision` is the instructor's (`redact` or `keep`), blank by default. On the next run, a row with `decision = keep` is not redacted, and a held row with `decision = redact` is redacted. A held row with a blank decision stops the run like an undecided image, naming code and file only. The file holds flagged text and is the instructor's: messages never print its contents.
9. **Cache.** Each reply is cached in `<assignment>/anon_review_cache/<md5>.json`, the md5 of the exact request body (model, prompt, text, images). A re-run (after image decisions, say) reuses replies, so only changed files are sent again. The cache sits beside the key and is never in `anon/`; `anon_forget()` deletes it with the key.
10. **Failures stop.** A request that fails, times out, or returns invalid JSON is retried once; a second failure stops the sweep with SWEEP_PENDING in place, naming code and file and the server's error message only. Completed files stay cached, so the next run resumes.
11. **What is shown and logged.** One progress line per file to the console: `[i/n] S04 file2 (3 images)  4.1 min elapsed, about 9 min left  2 redacted, 1 image held`. Never flagged text. The same line is also written to `<assignment>/anon_sweep_progress.txt` (beside the key, counts only), so an agent can wait on progress without reading findings. The de-identification log gains an `anon_sweep` entry: model, files, images, text redacted by token, unverified, kept by instructor, held, images held, decisions, and the result (passed, or pending with the reason). `anon_sweep()` returns those counts and `passed = TRUE/FALSE` invisibly.
12. **Leftover check after the sweep.** After applying findings, `anon_sweep()` re-runs the 1.2.6 leftover check on the swept text; a leftover keeps SWEEP_PENDING.
13. **Instructor waiver, explicit only.** For a machine with no local model (the package is public), `anon_sweep_waive(proj, assignment, reason)` replaces SWEEP_PENDING with SWEEP_WAIVED and logs the reason. It requires `interactive()` and a typed confirmation, so an agent running Rscript cannot call it; `relink()` accepts SWEEP_PASSED or SWEEP_WAIVED. This is the only way past the gate without a sweep.

## Global Constraints

- Messages, the console and the de-identification log name codes, anon/ paths, counts, kinds and token names only; never a name, id, login, original filename, redacted value, protected phrase or flagged text.
- Nothing is written outside the assignment folder; `anon_review.csv` and `anon_review_cache/` live beside `anon_key.csv`, never inside `anon/`.
- `url` must be localhost; the request never leaves the machine.
- `curl` goes in Suggests, not Imports; no other new package. `jsonlite` and `digest` are already imported.
- Tests never need LM Studio: the model call goes through one function, `review_call()`, which tests mock. A live smoke test runs only when `COURSEPACK_LIVE_REVIEW=1`.
- R sources pure ASCII (`grep -nP "[^\x00-\x7F]" R/*.R` empty). testthat 3; invented names only. No em-dashes in code, comments, docs, NEWS or commit messages. Never touch `inst/skills/uwrf-syllabus/`.
- Version 1.3.0 (a feature release). NEWS, DESCRIPTION, `R/coursepack-package.R` status line and `SETUP.md` install tag, as earlier releases did.

## Review Focus

1. A model that flags course or data content (a vehicle model, an app name) would gut a paper. Expected: a `review_context` term is never redacted; the instructor can set `decision = keep` and re-run. Test in Task 2.
2. A flagged string that also occurs inside a longer innocent word ("Ann" in "Annual"). Expected: replacement is bounded like a name form (no letter or digit directly before or after when the finding starts or ends with a letter or digit). Test in Task 2.
3. A grader (or relink) reaching anon/ before the sweep passed. Expected: SWEEP_PENDING exists from the moment anonymize() finishes; relink() refuses without SWEEP_PASSED or SWEEP_WAIVED. Test in Task 3.
4. The server dies mid-sweep, or is not running at all. Expected: stop naming code and file (or what to start), SWEEP_PENDING stays, completed files cached, the next run resumes. Test in Task 3.
5. A re-run of anonymize() after a passed sweep (for a key change) must send anon/ back to SWEEP_PENDING, and the re-sweep must reuse the cache for unchanged files. Test in Task 3.

---

## File Structure

| File | Responsibility |
|---|---|
| `inst/review/prompt.md` (create) | the generic privacy-review prompt |
| `R/anon-review.R` (create) | model call, prompt, cache, applying findings, the decision record |
| `R/anon-sweep.R` (create) | exported `anon_sweep()` and `anon_sweep_waive()`, the gate markers, progress file, log entry |
| `R/anon-grading.R` (modify) | `anonymize()` ends at SWEEP_PENDING; `relink()` refuses without SWEEP_PASSED or SWEEP_WAIVED; `list_submissions()` ignores the new files beside the key |
| `R/anon-key.R` (modify) | `anon_forget()` also deletes `anon_review_cache/` and `anon_sweep_progress.txt` |
| `tests/testthat/test-anon-review.R`, `test-anon-sweep.R` (create); `test-anon.R` (modify) | tests |
| `NAMESPACE`, `DESCRIPTION`, `NEWS.md`, `R/coursepack-package.R`, `SETUP.md`, `README.md`, `inst/skills/anonymized-grading/SKILL.md`, `man/*.Rd` | exports, docs, version |

---

### Task 1: The model call, the prompt and the cache

**Files:**
- Create: `inst/review/prompt.md`, `R/anon-review.R`, `tests/testthat/test-anon-review.R`
- Modify: `DESCRIPTION` (Suggests: curl)

**Interfaces:**
- Produces:
  - `review_check_server(url, model) -> invisible(TRUE)`; stops with an instruction when curl is missing, the url is not localhost, the server does not answer, or the model is not loaded.
  - `review_images(anon_dir, code, file) -> character` (absolute paths, sorted).
  - `review_body(text, images, prompt, model) -> character(1)` JSON.
  - `review_call(body, url) -> list(findings = list(...))` or `list(fail = "<short reason>")`. The only function that does network I/O; tests mock it.
  - `review_file(anon_dir, code, file, prompt, model, url, cache_dir) -> list(findings, cached = TRUE/FALSE)`; retries once; stops on a second failure naming code and file.
  - `review_prompt(keep, context) -> character(1)`.

- [ ] **Step 1: Write `inst/review/prompt.md`**

Use this text verbatim (it is the trial's `sweep_prompt.md`, generalised; no em-dashes):

```
You are a privacy reviewer for student homework that has already been de-identified. Your only job is to find anything that could still identify the student who wrote it, or another student. You do not grade.

The paper is a student's homework file converted to text. The student's name, ids, login, home-folder paths, email addresses, phone numbers, street addresses, birth dates, profile links and social handles have already been replaced. The images that were in this file are attached.

FLAG any of these that remain:
- person_name: the name of any person other than a published author being cited or the instructor (a classmate, teammate, friend, family member, manager, the student's own name in any spelling or nickname).
- organization: an employer, workplace, school other than this university, team, club or church that is about the student's own life.
- place: a hometown, street, neighbourhood or personal location tied to the student.
- contact: an email, phone, username, account name or link that survived, in any spelling (including "name at domain dot com" or a phone number with spaces).
- id_number: a student id, Canvas id, employee id or other personal number.
- personal_detail: a personal fact that points to one person (my job as ..., my daughter ..., when I worked at ..., my age, a medical or family detail).
- signature: a sign-off, initials or a signed name at the start or end.
- code_token: a token of the form S followed by two digits (S01, S04, S15) or SXX appearing in the text. These are internal student codes and must not appear in a paper.
- image_person: an image showing a face or a person.
- image_name: an image showing a name, a name tag, a signature or a username.
- image_account: a screenshot showing a desktop, a login, a file path with a user folder, an account, a browser profile or an email.
- other: anything else that could identify a student.

DO NOT FLAG:
- Course and data content: the assignment's dataset, its rows and values (product names, companies, places and people that are part of the data), column names, code, functions and packages, data file names, the textbook, chapters, the assignment title, the university, the course name.
- The instructor of the course, wherever named.
- Published authors and works cited as references.
- Redaction marks: [name], USER, EMAIL, [PHONE], [SSN], [DOB], [ADDRESS], [PROFILE], [HANDLE], [ORG], [PLACE], [CONTACT], [ID], [DETAIL], [REDACTED], [image removed].
- Generic statements (I am a student, I used R).

For each finding, copy the EXACT text from the paper (or describe the image region for an image finding), give the kind, say whether it is in the text or in image number N (1-based, in the attached order), and give a short reason. If nothing identifying remains, return an empty list. Do not invent findings: every text finding must be copied exactly from the paper.
```

- [ ] **Step 2: Write the failing tests** (`tests/testthat/test-anon-review.R`)

```r
fake_reply <- function(findings) list(findings = findings)

test_that("review_check_server refuses a non-local url", {
  expect_error(review_check_server("http://example.com:1234", "m"), "localhost")
})

test_that("review_check_server stops when the model is not loaded", {
  local_mocked_bindings(review_models = function(url) c("other-model"))
  expect_error(review_check_server("http://localhost:1234", "gemma-x"), "lms load gemma-x")
})

test_that("review_check_server stops when the server does not answer", {
  local_mocked_bindings(review_models = function(url) NULL)
  expect_error(review_check_server("http://localhost:1234", "gemma-x"), "lms server start")
})

test_that("review_prompt adds instructor phrases and context terms", {
  p <- review_prompt(keep = c("Avery J. Thorn"), context = c("Tesla Model 3"))
  expect_match(p, "Avery J. Thorn", fixed = TRUE)
  expect_match(p, "Tesla Model 3", fixed = TRUE)
  expect_match(p, "privacy reviewer", fixed = TRUE)
})

test_that("review_body sends text and images as one user message", {
  d <- withr::local_tempdir(); img <- file.path(d, "a.png")
  magick::image_write(magick::image_blank(10, 10, "white"), img, format = "png")
  b <- jsonlite::fromJSON(review_body("hello", img, "PROMPT", "m"), simplifyVector = FALSE)
  expect_equal(b$model, "m")
  expect_equal(b$messages[[1]]$content, "PROMPT")
  parts <- b$messages[[2]]$content
  expect_equal(parts[[1]]$type, "text")
  expect_match(parts[[2]]$image_url$url, "^data:image/png;base64,")
  expect_equal(b$response_format$json_schema$schema$required, list("findings"))
})

test_that("review_file caches replies and retries once", {
  a <- withr::local_tempdir(); dir.create(file.path(a, "S01"))
  writeLines("Thanks to Jordan Whitfield.", file.path(a, "S01", "file1.md"))
  cache <- withr::local_tempdir()
  calls <- 0L
  local_mocked_bindings(review_call = function(body, url) {
    calls <<- calls + 1L
    if (calls == 1L) list(fail = "HTTP 500") else
      fake_reply(list(list(text = "Jordan Whitfield", kind = "person_name", where = "text",
                           image_number = 0L, reason = "a classmate")))
  })
  r1 <- review_file(a, "S01", "file1", "P", "m", "http://localhost:1234", cache)
  expect_equal(calls, 2L); expect_false(r1$cached); expect_length(r1$findings, 1)
  r2 <- review_file(a, "S01", "file1", "P", "m", "http://localhost:1234", cache)
  expect_equal(calls, 2L); expect_true(r2$cached)
})

test_that("review_file stops after a second failure, naming code and file only", {
  a <- withr::local_tempdir(); dir.create(file.path(a, "S02"))
  writeLines("Secret Name here.", file.path(a, "S02", "file1.md"))
  local_mocked_bindings(review_call = function(body, url) list(fail = "HTTP 500 server error"))
  e <- tryCatch(review_file(a, "S02", "file1", "P", "m", "http://localhost:1234", withr::local_tempdir()),
                error = function(e) conditionMessage(e))
  expect_match(e, "S02 file1", fixed = TRUE)
  expect_false(grepl("Secret", e))
})
```

- [ ] **Step 3: Run to verify they fail**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-anon-review.R")'`
Expected: FAIL, functions not found.

- [ ] **Step 4: Implement `R/anon-review.R` (first half)**

```r
# Optional local privacy review. A vision model served by LM Studio on
# localhost reads each coded file with its images after the rule-based
# redaction and returns anything that could still identify a student.
# review_call() is the only network I/O; everything else is testable.

REVIEW_KINDS <- c("person_name", "organization", "place", "contact", "id_number",
                  "personal_detail", "signature", "code_token", "image_person",
                  "image_name", "image_account", "other")
REVIEW_IMAGE_EXTS <- c("png", "jpg", "jpeg", "gif", "webp")

review_local <- function(url) grepl("^http://(localhost|127\\.0\\.0\\.1)(:[0-9]+)?/?$", url)

review_models <- function(url) {
  tryCatch(jsonlite::fromJSON(paste0(sub("/$", "", url), "/v1/models"))$data$id,
           error = function(e) NULL)
}

review_check_server <- function(url, model) {
  if (!review_local(url)) {
    stop("url must be http://localhost or http://127.0.0.1; the review never leaves this machine.",
         call. = FALSE)
  }
  if (!requireNamespace("curl", quietly = TRUE)) {
    stop("anon_sweep() needs the curl package: install.packages(\"curl\").", call. = FALSE)
  }
  ids <- review_models(url)
  if (is.null(ids)) {
    stop("No model server answers at ", url, ". Start LM Studio's server (lms server start) and load ",
         model, ".", call. = FALSE)
  }
  if (!model %in% ids) {
    stop(model, " is not loaded. Load it (lms load ", model, ") and re-run.", call. = FALSE)
  }
  invisible(TRUE)
}

review_prompt <- function(keep = character(), context = character()) {
  p <- paste(readLines(system.file("review", "prompt.md", package = "coursepack"),
                       warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  if (length(keep)) p <- paste0(p, "\n\nINSTRUCTOR NAME PHRASES (never flag):\n",
                                paste("-", keep, collapse = "\n"))
  if (length(context)) p <- paste0(p, "\n\nCOURSE AND DATA TERMS FOR THIS ASSIGNMENT (never flag):\n",
                                   paste("-", context, collapse = "\n"))
  p
}

review_images <- function(anon_dir, code, file) {
  d <- file.path(anon_dir, code, paste0(file, "_media"))
  f <- if (dir.exists(d)) list.files(d, recursive = TRUE, full.names = TRUE) else character()
  sort(f[tolower(tools::file_ext(f)) %in% REVIEW_IMAGE_EXTS])
}

review_schema <- function() list(
  type = "object",
  properties = list(findings = list(type = "array", items = list(
    type = "object",
    properties = list(text = list(type = "string"),
                      kind = list(type = "string", enum = REVIEW_KINDS),
                      where = list(type = "string", enum = c("text", "image")),
                      image_number = list(type = "integer"),
                      reason = list(type = "string")),
    required = c("text", "kind", "where", "image_number", "reason")))),
  required = I("findings"))   # I(): a one-element vector must stay a JSON array

review_mime <- function(p) switch(tolower(tools::file_ext(p)), jpg = , jpeg = "image/jpeg",
                                  gif = "image/gif", webp = "image/webp", "image/png")

review_body <- function(text, images, prompt, model) {
  parts <- c(list(list(type = "text", text = paste0(
    "THE PAPER (one file of the student's submission):\n\n", text,
    "\n\nIMAGES ATTACHED: ", length(images), "\n\nList every finding as instructed, or an empty list."))),
    lapply(images, function(p) list(type = "image_url", image_url = list(
      url = paste0("data:", review_mime(p), ";base64,",
                   jsonlite::base64_enc(readBin(p, "raw", file.info(p)$size)))))))
  jsonlite::toJSON(list(model = model, temperature = 0, max_tokens = 8000,
                        messages = list(list(role = "system", content = prompt),
                                        list(role = "user", content = parts)),
                        response_format = list(type = "json_schema", json_schema = list(
                          name = "privacy", strict = TRUE, schema = review_schema()))),
                   auto_unbox = TRUE)
}

# The one function that talks to the server. Returns the parsed findings or
# a short failure reason; never the reply text.
review_call <- function(body, url) {
  h <- curl::new_handle(post = TRUE, postfields = body,
                        timeout = getOption("coursepack.review_timeout", 3600))
  curl::handle_setheaders(h, "Content-Type" = "application/json")
  res <- tryCatch(curl::curl_fetch_memory(paste0(sub("/$", "", url), "/v1/chat/completions"), handle = h),
                  error = function(e) list(error = conditionMessage(e)))
  if (!is.null(res$error)) return(list(fail = paste("connection:", substr(res$error, 1, 100))))
  fr <- tryCatch(jsonlite::fromJSON(rawToChar(res$content), simplifyVector = FALSE),
                 error = function(e) NULL)
  if (res$status_code != 200) {
    e <- fr$error
    return(list(fail = substr(paste("HTTP", res$status_code,
                                    if (is.list(e)) e$message else paste(e)), 1, 160)))
  }
  g <- tryCatch(jsonlite::fromJSON(fr$choices[[1]]$message$content, simplifyVector = FALSE),
                error = function(e) NULL)
  if (is.null(g) || !is.list(g$findings)) {
    return(list(fail = sprintf("reply was not valid (stop: %s)",
                               fr$choices[[1]]$finish_reason %||% "?")))
  }
  list(findings = g$findings)
}

review_file <- function(anon_dir, code, file, prompt, model, url, cache_dir) {
  text <- paste(readLines(file.path(anon_dir, code, paste0(file, ".md")), warn = FALSE,
                          encoding = "UTF-8"), collapse = "\n")
  body <- review_body(text, review_images(anon_dir, code, file), prompt, model)
  hit <- file.path(cache_dir, paste0(digest::digest(body, algo = "md5", serialize = FALSE), ".json"))
  if (file.exists(hit)) {
    return(list(findings = jsonlite::fromJSON(hit, simplifyVector = FALSE)$findings, cached = TRUE))
  }
  r <- review_call(body, url)
  if (!is.null(r$fail)) r <- review_call(body, url)
  if (!is.null(r$fail)) {
    stop("privacy review failed for ", code, " ", file, ": ", r$fail,
         ". anon/ stays NOT_READY; re-run to resume (finished files are cached).", call. = FALSE)
  }
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(jsonlite::toJSON(list(findings = r$findings), auto_unbox = TRUE), hit)
  list(findings = r$findings, cached = FALSE)
}
```

Add `curl` to `Suggests:` in DESCRIPTION (alphabetical, above `exams`).

- [ ] **Step 5: Run to verify they pass** (same command). Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add inst/review/prompt.md R/anon-review.R tests/testthat/test-anon-review.R DESCRIPTION
git commit -m "anon: local privacy review call, prompt and cache"
```

---

### Task 2: Applying findings and the instructor's record

**Files:**
- Modify: `R/anon-review.R`, `tests/testthat/test-anon-review.R`

**Interfaces:**
- Consumes: `mask_keep()`, `unmask_keep()` (R/anon-keep.R), `rx_escape()` (R/anon-redact.R).
- Produces:
  - `REVIEW_TOKENS`: named character, kind -> token.
  - `apply_text_findings(lines, findings, keep, context, decisions, code, file) -> list(text, record, counts)` where `record` is a data.frame `code,file,kind,text,action` and `counts` a named integer by token plus `unverified`, `kept`, `held`.
  - `read_review_decisions(assignment_dir) -> data.frame(code,file,kind,text,decision)` (empty when no file).
  - `write_review_record(assignment_dir, record, decisions)`: writes `anon_review.csv`, keeping existing decisions for matching rows (`code,file,text` case-insensitive).

- [ ] **Step 1: Write the failing tests** (append)

```r
f <- function(text, kind = "person_name") list(text = text, kind = kind, where = "text",
                                              image_number = 0L, reason = "r")
no_dec <- data.frame(code = character(), file = character(), kind = character(),
                     text = character(), decision = character())

test_that("verified findings are redacted by kind; unverified are ignored", {
  x <- c("Thanks to Jordan Whitfield.", "I work at Lakeshore Dental Associates.")
  r <- apply_text_findings(x, list(f("Jordan Whitfield"), f("Lakeshore Dental Associates", "organization"),
                                   f("Nobody Here")), character(), character(), no_dec, "S01", "file1")
  expect_equal(r$text, c("Thanks to [name].", "I work at [ORG]."))
  expect_equal(r$counts[["unverified"]], 1L)
  expect_setequal(r$record$action, c("redacted", "redacted", "unverified"))
})

test_that("a finding inside a longer word is not replaced there", {
  r <- apply_text_findings("Ann wrote the Annual report.", list(f("Ann")), character(), character(),
                           no_dec, "S01", "file1")
  expect_equal(r$text, "[name] wrote the Annual report.")
})

test_that("context terms, protected phrases and redaction tokens are never replaced", {
  x <- "Dr. Avery J. Thorn compared the Tesla Model 3 with [name]."
  r <- apply_text_findings(x, list(f("Tesla Model 3", "other"), f("Avery J. Thorn"), f("[name]")),
                           keep = "Avery J. Thorn", context = "Tesla Model 3", no_dec, "S01", "file1")
  expect_equal(r$text, x)
})

test_that("an instructor keep decision is respected; a long finding is held", {
  long <- strrep("my very personal story ", 10)
  x <- c("Priya Castellano helped.", long)
  dec <- data.frame(code = "S01", file = "file1", kind = "person_name",
                    text = "priya castellano", decision = "keep")
  r <- apply_text_findings(x, list(f("Priya Castellano"), f(trimws(long), "personal_detail")),
                           character(), character(), dec, "S01", "file1")
  expect_equal(r$text[1], "Priya Castellano helped.")
  expect_equal(r$counts[["kept"]], 1L); expect_equal(r$counts[["held"]], 1L)
})

test_that("anon_review.csv keeps the instructor's decisions across runs", {
  a <- withr::local_tempdir()
  rec <- data.frame(code = "S01", file = "file1", kind = "person_name",
                    text = "Jordan Whitfield", action = "redacted")
  write_review_record(a, rec, read_review_decisions(a))
  d <- utils::read.csv(file.path(a, "anon_review.csv"), colClasses = "character")
  d$decision <- "keep"; utils::write.csv(d, file.path(a, "anon_review.csv"), row.names = FALSE)
  write_review_record(a, rec, read_review_decisions(a))
  d2 <- utils::read.csv(file.path(a, "anon_review.csv"), colClasses = "character")
  expect_equal(d2$decision, "keep")
})
```

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement** (append to `R/anon-review.R`)

```r
REVIEW_TOKENS <- c(person_name = "[name]", signature = "[name]", code_token = "[name]",
                   organization = "[ORG]", place = "[PLACE]", contact = "[CONTACT]",
                   id_number = "[ID]", personal_detail = "[DETAIL]", other = "[REDACTED]")
REVIEW_MAX_CHARS <- 200L
REVIEW_MARKS <- "^\\[(name|ORG|PLACE|CONTACT|ID|DETAIL|REDACTED|PHONE|SSN|DOB|ADDRESS|PROFILE|HANDLE|image removed)\\]$|^(USER|EMAIL)$"

# A finding is bounded like a name form: no letter or digit right before it
# when it starts with one, none right after it when it ends with one.
review_rx <- function(s) {
  paste0(if (grepl("^[[:alnum:]]", s)) "(?<![[:alnum:]])" else "",
         rx_escape(s),
         if (grepl("[[:alnum:]]$", s)) "(?![[:alnum:]])" else "")
}

apply_text_findings <- function(lines, findings, keep, context, decisions, code, file) {
  counts <- c(setNames(integer(length(unique(REVIEW_TOKENS))), unique(REVIEW_TOKENS)),
              unverified = 0L, kept = 0L, held = 0L)
  rec <- data.frame(code = character(), file = character(), kind = character(),
                    text = character(), action = character(), stringsAsFactors = FALSE)
  joined <- paste(lines, collapse = "\n")
  m <- mask_keep(joined, keep)
  txt <- m$text
  dec_of <- function(s) {
    d <- decisions[decisions$code == code & decisions$file == file & tolower(decisions$text) == tolower(s), ]
    if (nrow(d)) tolower(d$decision[1]) else ""
  }
  for (g in findings) {
    if (!identical(g$where, "text") || !nzchar(trimws(g$text))) next
    s <- trimws(g$text)
    if (grepl(REVIEW_MARKS, s) || tolower(s) %in% tolower(context) || tolower(s) %in% tolower(keep)) next
    add <- function(action) rec[nrow(rec) + 1, ] <<- list(code, file, g$kind, s, action)
    if (!grepl(tolower(s), tolower(joined), fixed = TRUE)) { counts[["unverified"]] <- counts[["unverified"]] + 1L; add("unverified"); next }
    d <- dec_of(s)
    if (d == "keep") { counts[["kept"]] <- counts[["kept"]] + 1L; add("kept"); next }
    if (nchar(s) > REVIEW_MAX_CHARS && d != "redact") { counts[["held"]] <- counts[["held"]] + 1L; add("held"); next }
    tok <- REVIEW_TOKENS[[if (g$kind %in% names(REVIEW_TOKENS)) g$kind else "other"]]
    txt <- gsub(review_rx(s), tok, txt, perl = TRUE, ignore.case = TRUE)
    counts[[tok]] <- counts[[tok]] + 1L
    add("redacted")
  }
  out <- strsplit(paste0(unmask_keep(txt, m), "\n"), "\n", fixed = TRUE)[[1]]
  list(text = out, record = rec, counts = counts)
}

read_review_decisions <- function(assignment_dir) {
  p <- file.path(assignment_dir, "anon_review.csv")
  empty <- data.frame(code = character(), file = character(), kind = character(),
                      text = character(), decision = character())
  if (!file.exists(p)) return(empty)
  d <- utils::read.csv(p, colClasses = "character", na.strings = character(), fileEncoding = "UTF-8-BOM")
  if (!all(c("code", "file", "text", "decision") %in% names(d))) {
    stop("anon_review.csv needs the columns code,file,kind,text,action,decision", call. = FALSE)
  }
  bad <- !tolower(trimws(d$decision)) %in% c("", "keep", "redact")
  if (any(bad)) stop("anon_review.csv: decision must be keep, redact or blank", call. = FALSE)
  d$decision <- tolower(trimws(d$decision))
  d[, intersect(c("code", "file", "kind", "text", "decision"), names(d))]
}

write_review_record <- function(assignment_dir, record, decisions) {
  key <- function(d) paste(d$code, d$file, tolower(d$text))
  record$decision <- decisions$decision[match(key(record), key(decisions))]
  record$decision[is.na(record$decision)] <- ""
  utils::write.csv(record[, c("code", "file", "kind", "text", "action", "decision")],
                   file.path(assignment_dir, "anon_review.csv"), row.names = FALSE)
  invisible(record)
}
```

- [ ] **Step 4: Run to verify they pass.** If `rec[nrow(rec) + 1, ] <<- list(...)` is awkward on an empty data.frame, collect rows in a list and `rbind` at the end; keep the behaviour.

- [ ] **Step 5: Commit**

```bash
git add R/anon-review.R tests/testthat/test-anon-review.R
git commit -m "anon: apply privacy-review findings and keep the instructor's decisions"
```

---

### Task 3: The gate: anon_sweep(), SWEEP_PENDING, relink refusal

**Files:**
- Create: `R/anon-sweep.R`, `tests/testthat/test-anon-sweep.R`
- Modify: `R/anon-grading.R` (end of `anonymize()`; `relink()` start; `list_submissions()` ignore list), `R/anon-key.R` (`anon_forget()`), `tests/testthat/test-anon.R` (existing tests that assert anon/ is "ready" after anonymize now assert SWEEP_PENDING; existing relink tests first mark the folder passed with a test helper)

**Interfaces:**
- Consumes: `review_check_server()`, `review_prompt()`, `review_file()`, `review_images()`, `apply_text_findings()`, `read_review_decisions()`, `write_review_record()`, `REVIEW_TOKENS` (Tasks 1 and 2); `read_keep_phrases()`, `key_terms()`, `find_leftovers()`, `read_image_decisions()`, `apply_image_decisions()`, `append_log()`, `read_key()`, `anon_proj()`, `proj_path()` (existing).
- Produces:
  - `SWEEP_PENDING <- "SWEEP_PENDING"`, `SWEEP_PASSED <- "SWEEP_PASSED"`, `SWEEP_WAIVED <- "SWEEP_WAIVED"` (marker file names inside anon/).
  - `sweep_state(anon_dir) -> one of "not_ready", "pending", "passed", "waived", "none"`.
  - `anon_sweep(proj, assignment, key = file.path(assignment, "anon_key.csv"), anon_dir = NULL, model = "gemma-4-31b-it-mlx", url = "http://localhost:1234", context = NULL, force = FALSE, dict = default_dict()) -> invisible(list(passed, files, images, redacted, unverified, kept, held, images_held, cached))` (exported).
  - `anon_sweep_waive(proj, assignment, reason, anon_dir = NULL)` (exported; interactive only).
  - `test_pass_sweep(anon_dir)` in `tests/testthat/helper-anon.R`: writes SWEEP_PASSED and removes SWEEP_PENDING, for relink tests that are not about the gate.

- [ ] **Step 1: Write the failing tests** (`test-anon-sweep.R`, using `test-anon.R`'s fixture helpers; every test mocks `review_models` and `review_call`; none needs LM Studio)

```r
mock_up <- function(findings = list()) {
  local_mocked_bindings(review_models = function(url) "gemma-4-31b-it-mlx",
                        review_call = function(body, url) list(findings = findings),
                        .env = parent.frame())
}

test_that("anonymize() ends at SWEEP_PENDING, never open", {
  # fixture run via the file's anon() helper
  expect_true(file.exists(file.path(a, "anon", "SWEEP_PENDING")))
  expect_false(file.exists(file.path(a, "anon", "NOT_READY")))
  expect_false(file.exists(file.path(a, "anon", "SWEEP_PASSED")))
  expect_match(readLines(file.path(a, "anon", "SWEEP_PENDING"))[1], "Do not grade")
})

test_that("relink() refuses an anon/ that never passed the sweep", {
  # after anonymize() and fixture feedback, without a sweep
  expect_error(relink(p, "semester/A1"), "anon_sweep")
})

test_that("anon_sweep() stops and keeps the gate shut when the server is down", {
  local_mocked_bindings(review_models = function(url) NULL)
  expect_error(anon_sweep(p, "semester/A1"), "lms server start")
  expect_true(file.exists(file.path(a, "anon", "SWEEP_PENDING")))
})

test_that("a clean sweep passes the gate and logs it", {
  mock_up()
  res <- anon_sweep(p, "semester/A1")
  expect_true(res$passed)
  expect_true(file.exists(file.path(a, "anon", "SWEEP_PASSED")))
  expect_false(file.exists(file.path(a, "anon", "SWEEP_PENDING")))
  log <- readLines(file.path(a, "deidentification_log.md"))
  expect_true(any(grepl("^## anon_sweep, ", log)))
  expect_true(any(grepl("result: passed", log, fixed = TRUE)))
})

test_that("a held long finding keeps the gate shut until decided", {
  long <- strrep("my very personal story ", 10)   # fixture text must contain this
  mock_up(list(list(text = trimws(long), kind = "personal_detail", where = "text",
                    image_number = 0L, reason = "r")))
  expect_error(anon_sweep(p, "semester/A1"), "anon_review.csv")
  expect_true(file.exists(file.path(a, "anon", "SWEEP_PENDING")))
  d <- utils::read.csv(file.path(a, "anon_review.csv"), colClasses = "character")
  d$decision[d$action == "held"] <- "redact"
  utils::write.csv(d, file.path(a, "anon_review.csv"), row.names = FALSE)
  expect_true(anon_sweep(p, "semester/A1")$passed)
})

test_that("a flagged image keeps the gate shut until anon_images.csv decides it", {
  skip_if_no("pandoc")
  # fixture with one embedded PNG
  mock_up(list(list(text = "a face", kind = "image_person", where = "image",
                    image_number = 1L, reason = "r")))
  expect_error(anon_sweep(p, "semester/A1"), "anon_images.csv")
  expect_true(file.exists(file.path(a, "anon", "SWEEP_PENDING")))
  # write keep for the flagged image (path from image_files()) and re-run: passes
})

test_that("a failure mid-sweep stops naming code and file, gate stays shut, re-run resumes", {
  n <- 0L
  local_mocked_bindings(review_models = function(url) "gemma-4-31b-it-mlx",
                        review_call = function(body, url) { n <<- n + 1L
                          if (n >= 3L) list(fail = "HTTP 500") else list(findings = list()) })
  expect_error(anon_sweep(p, "semester/A1"), "privacy review failed for S")
  expect_true(file.exists(file.path(a, "anon", "SWEEP_PENDING")))
  sent <- n
  mock_up()
  expect_true(anon_sweep(p, "semester/A1")$passed)
  # the first file came from the cache: fewer new requests than files
})

test_that("anonymize() after a passed sweep returns to SWEEP_PENDING", {
  mock_up(); anon_sweep(p, "semester/A1")
  anonymize(p, "semester/A1", dict = NULL)
  expect_true(file.exists(file.path(a, "anon", "SWEEP_PENDING")))
  expect_false(file.exists(file.path(a, "anon", "SWEEP_PASSED")))
})

test_that("anon_sweep() refuses a NOT_READY folder", {
  writeLines("x", file.path(a, "anon", "NOT_READY"))
  mock_up()
  expect_error(anon_sweep(p, "semester/A1"), "finish anonymize")
})

test_that("anon_sweep_waive() refuses outside an interactive session", {
  expect_error(anon_sweep_waive(p, "semester/A1", reason = "no model here"), "interactive")
  expect_true(file.exists(file.path(a, "anon", "SWEEP_PENDING")))
})

test_that("the progress file and the log carry counts only", {
  mock_up(list(list(text = "Jordan Whitfield", kind = "person_name", where = "text",
                    image_number = 0L, reason = "r")))   # fixture text contains it
  anon_sweep(p, "semester/A1")
  prog <- readLines(file.path(a, "anon_sweep_progress.txt"))
  log <- readLines(file.path(a, "deidentification_log.md"))
  expect_false(any(grepl("Whitfield", c(prog, log))))
})
```

Replace the fixture placeholders with `test-anon.R`'s own helpers; the assertions are the requirement. In `test-anon.R`, change assertions that anon/ is ready after `anonymize()` to SWEEP_PENDING, and call `test_pass_sweep(anon_dir)` before every existing `relink()` call; say in the report which tests changed.

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement**

At the end of `anonymize()`, replace `unlink(file.path(anon_dir, "NOT_READY"))` with: write `SWEEP_PENDING` (text: "Privacy sweep not done. Do not grade. Run coursepack::anon_sweep()."), remove any `SWEEP_PASSED` or `SWEEP_WAIVED`, then remove NOT_READY; keep the timestamp reset after. Change the final console line to "anon/ is anonymized; run anon_sweep() before grading." The log line for anonymize gains "gate: SWEEP_PENDING".

`R/anon-sweep.R`: `anon_sweep()` resolves paths like `anonymize()`, checks `sweep_state()` (stop on not_ready or none; on passed return a report unless `force`), calls `review_check_server(url, model)` before writing anything, reads `keep` and `context` (default `<assignment>/review_context.txt`), builds the prompt, then for each manifest file in code/position order: `review_file()`, `apply_text_findings()` with `read_review_decisions()`, write the file back, collect image hits (same mapping as described in Design 7), write one progress line to the console and append it to `<assignment>/anon_sweep_progress.txt` (truncate at the start of a run). Then: `write_review_record()`; apply image decisions for the review-flagged images with `apply_image_decisions(anon_dir, flagged, read_image_decisions(assignment_dir))`; re-run `find_leftovers()` on anon/ texts with the key's terms and `keep`. Decide: held undecided > 0, images undecided > 0, or leftovers > 0 -> append the log entry with "result: pending (<reason counts>)", leave SWEEP_PENDING, and stop with a message naming codes, files and counts and saying which file to edit. Otherwise write SWEEP_PASSED, remove SWEEP_PENDING, reset the anon/ timestamps to the same epoch `anonymize()` uses, append the log entry with "result: passed", print one summary line, return counts.

`anon_sweep_waive()`: stop unless `interactive()`; show the reason; `readline("Type WAIVE to release anon/ without a privacy sweep: ")` must equal "WAIVE"; then write SWEEP_WAIVED, remove SWEEP_PENDING, log "anon_sweep_waive: <reason>".

`relink()`: at the start, after paths resolve, stop unless `sweep_state(anon_dir) %in% c("passed", "waived")`, with "anon/ has not passed the privacy sweep; run anon_sweep() (or anon_sweep_waive()) first."

`list_submissions()`: skip `anon_review.csv`, `review_context.txt`, `anon_sweep_progress.txt` and the `anon_review_cache` directory beside the key. `anon_forget()`: delete `anon_review_cache/` and `anon_sweep_progress.txt` with the key; keep `anon_review.csv` and the log (the instructor's records).

Export `anon_sweep` and `anon_sweep_waive` with roxygen (`@export`, `@examples` guarded by `if (interactive() && nzchar(Sys.getenv("COURSEPACK_LIVE_REVIEW")))`).

- [ ] **Step 4: Run** all anon test files. All pass.

- [ ] **Step 5: Commit**

```bash
git add R/anon-sweep.R R/anon-grading.R R/anon-key.R NAMESPACE tests/testthat/test-anon-sweep.R tests/testthat/test-anon.R tests/testthat/helper-anon.R
git commit -m "anon: privacy sweep gate; anonymize ends at SWEEP_PENDING, relink needs SWEEP_PASSED"
```

---

### Task 4: Two fixes from today's runs

**Files:** `R/anon-keep.R`, `R/anon-redact.R`, `R/anon-grading.R` (`list_submissions()` / type check), tests.

- [ ] **Step 1: Course URLs in anon_keep.txt.** On Case Study 6 the profile-URL rule redacted the dataset's public GitHub address (PROFILE 5). A line in `anon_keep.txt` that is a URL (starts with `http://`, `https://` or `github.com/` etc.) is allowed as a single "word", and that URL is protected from the PROFILE and HANDLE patterns as well as from name redaction (mask it before `redact_patterns()`). A URL line that contains a student's login or name form is still refused by `check_keep_phrases()`. Test: `https://github.com/course-org/data-repo` listed survives; an unlisted `github.com/someone` is still `[PROFILE]`.
- [ ] **Step 2: Text after the extension.** A Canvas download named like `..._spec.md Case #5` stopped anonymize() as an unsupported type. When a file's extension is not supported, look for a supported extension inside the name (`\.(md|qmd|rmd|docx|odt|pdf|txt|r)\b` before trailing text) and use it; if none, the stop message names the code and says "rename the file so it ends in its real extension". Test with an invented filename.
- [ ] **Step 3: Run the anon tests; commit** `git commit -m "anon: course URLs in anon_keep.txt; extension found inside a trailing name"`.

---

### Task 5: Docs, skill, live smoke test, version, full suite

**Files:** roxygen for `anonymize()`, `anon_sweep()`, `anon_sweep_waive()`, `relink()`, `anon_forget()`; `README.md`; `inst/skills/anonymized-grading/SKILL.md`; `SETUP.md`; `DESCRIPTION` (Version 1.3.0); `NEWS.md` ("# coursepack 1.3.0"); `R/coursepack-package.R`; `man/*.Rd`; `tests/testthat/test-anon-review-live.R` (create).

- [ ] **Step 1: Live smoke test**, skipped unless `COURSEPACK_LIVE_REVIEW=1`: one coded file with an invented planted sentence ("My roommate Jordan Whitfield checked my code."), real `review_file()` against `http://localhost:1234`, expect a finding containing "Whitfield". Never runs in CI.

- [ ] **Step 2: The skill.** In `inst/skills/anonymized-grading/SKILL.md`:
  - The opening rule gains: "Never dispatch a grader, and never open a coded file for grading, while `anon/SWEEP_PENDING` exists or `anon/SWEEP_PASSED` (or SWEEP_WAIVED) is missing. The sweep is never run in parallel with grading. 'It was clean last time' is not a reason."
  - The pipeline table gets a new row between Anonymize and Grade: `4. Privacy sweep | instructor's machine | coursepack::anon_sweep(".", "semester/<term>/<Assignment>")`, then the instructor reviews `anon_review.csv` and any `anon_images.csv` rows it asks for. Renumber the rest.
  - The agent may run `anon_sweep()`, watch `anon_sweep_progress.txt` and read the counts; it never opens `anon_review.csv`, `anon_review_cache/`, or the instructor's `review_context.txt`; it builds `review_context.txt` from course files only, when asked. It never calls `anon_sweep_waive()`.
  - The common-mistakes table gains: "Graders started while the sweep was running (Case Studies 5 and 6, 2026-10-05) | coded files read before the privacy check finished | wait for SWEEP_PASSED; relink() refuses otherwise".
- [ ] **Step 3: README, SETUP, NEWS, roxygen.** Say plainly: the new order and the three markers; `anon_sweep()` needs LM Studio with a vision model (`gemma-4-31b-it-mlx` by default) and the curl package; what it flags and the tokens it writes; images it flags wait for keep/remove; `anon_review.csv` is the instructor's record and undo (holds flagged text, never opened by an agent); `review_context.txt`; time (15 to 30 minutes per assignment; re-runs use the cache); the waiver; the trial evidence in one sentence and its limits in one. NEWS states the reason (graders started before the sweep finished, twice) and that `relink()` now refuses an unswept folder. No em-dashes.
- [ ] **Step 4: Regenerate and run the full suite.** `devtools::document()`, then `devtools::test()`: only the pre-existing uwrf-syllabus failures. R sources ASCII. No `_problems`.
- [ ] **Step 5: Commit**

```bash
git add -A -- . ':!inst/skills/uwrf-syllabus'
git commit -m "Release 1.3.0: the privacy sweep gate between anonymize() and grading"
```

(No tag, push or install without the instructor's go-ahead.)
