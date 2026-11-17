# Pre-Go-Live Checks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** DRAFT, 2026-10-20. Nothing built. Proposal approved as a plan by Logan on 2026-10-20; building has not been authorized. Open items at the end need answers first.

**Goal:** a running list of failures that have reached students before, each with a mechanical check, run against what Canvas actually holds after an import and before the material is released. The first entry is the ECON 202 midterm whose quiz images broke on import.

**Why:** the build check stops at "the cartridge is well formed". The midterm cartridge was correct, Canvas mangled it on import, and nothing looked at the course after import. Students took the exam with broken images. A check that reads a post-import course export would have caught it in seconds.

## The first failure (macro_principles, 2026-10-20)

Reported by the macro_principles session. Facts below were re-checked in this session against the export (read-only, unpacked into the scratchpad).

- Midterm Exam: Classic quiz from a `generate:` block, 49 groups, 588 questions, 46 figures.
- Cartridge: every `<img>` was `$IMS-CC-FILEBASE$/quiz_images/<file>.png`; all 46 files shipped under `web_resources/quiz_images/` and were declared as webcontent in the manifest.
- Export `~/Downloads/principles-of-macroeconomics-export.imscc`: the midterm is `gd430402b7893cf40a963bc6e3b2a4401`. Its `non_cc_assessments/gd430402....xml.qti` holds 96 `LINK.PLACEHOLDER_<hash>` references and 3 resolved `$IMS-CC-FILEBASE$` references. The files exist in course Files (`web_resources/quiz_images/`, 83 files in the export).
- Every module quiz in the same course resolved its images.
- The live quiz identifier (`gd430402...`) differs from the cartridge's (`g4635c8b0...`), so a re-import may create a second quiz instead of replacing the first.
- Cause of the failure is not known. Do not record one until it is diagnosed.

## Design (the spec)

### 1. The registry

`inst/golive/checks.yml`, one entry per failure that has happened:

```yaml
- id: GL-001
  title: Quiz images left as LINK.PLACEHOLDER after import
  first_seen: 2026-10-20
  course: macro_principles
  symptom: Broken images in a Classic quiz; students saw them.
  needs: export
  fn: golive_quiz_links
- id: GL-002
  title: Re-import will duplicate a quiz instead of replacing it
  first_seen: 2026-10-20
  course: macro_principles
  symptom: Live quiz identifier differs from the cartridge's.
  needs: [export, cartridge]
  fn: golive_identifier_drift
```

Adding a future failure means one registry entry, one function, and one test built from the real evidence. The registry is the list Logan reads; the functions are what runs.

### 2. Entry point

`golive_check(export, cartridge = NULL, proj = ".")`:
- Unzips each `.imscc` into a temp dir (never into the course project).
- Runs every registry entry whose `needs` are met. An entry whose input is missing is reported as **not run**, never as passed.
- Returns a findings data frame (check id, severity fail/warn, quiz title, quiz id, question ident and title, detail) and prints a short report.
- Exit status for the Makefile: nonzero on any `fail`. A `warn` does not fail the run but is printed.

### 3. GL-001 `golive_quiz_links(export_dir)`

For every quiz in the export, scan both `non_cc_assessments/<id>.xml.qti` and `<id>/assessment_qti.xml`, plus question banks under `non_cc_assessments/` if present:
- Any `LINK.PLACEHOLDER` in a question is a **fail**.
- Any `$IMS-CC-FILEBASE$/<path>` whose `<path>` (URL-decoded) has no file under `web_resources/` is a **fail**.
- The finding names the quiz (title from `assessment_meta.xml`), the question (`item ident` and `title`), and the reference.
- Parsing uses xml2, not regex over the whole file, so the question is identified exactly. A file that does not parse is itself a fail.

Acceptance test against the Oct 20 export: midterm fails with 96 placeholder references; no module quiz fails.

### 4. GL-002 `golive_identifier_drift(export_dir, cartridge_dir)`

For each quiz in the cartridge, look up a live quiz with the same title:
- Same title, same identifier: ok.
- Same title, different identifier: **warn**, "re-importing will create a second quiz; delete or rename the live one first, or import into the existing identifier".
- Title in the cartridge but not live: info (new quiz).

Acceptance test: the rebuilt midterm cartridge against the Oct 20 export warns on Midterm Exam (`g4635c8b0...` vs `gd430402...`).

### 5. Make target and docs

The course template `Makefile` gets:

```make
golive:
	Rscript -e 'coursepack::golive_check("$(EXPORT)", cartridge = "$(CARTRIDGE)")'
```

The course skill's release steps gain one line: after import, export the course from Canvas, run `make golive EXPORT=...`, and do not publish until it passes.

## Global Constraints

- Read-only on every input. The export and cartridge are unzipped to a temp dir; nothing is written into a course project except the report if asked.
- No model calls, no network. A course export can contain course content that should not leave the machine.
- Tests use small fixtures cut from the real export (a few quiz XML files and a stub `web_resources/`), committed under `tests/testthat/fixtures/golive/`. No student data is in a quiz export, but confirm before committing the fixtures.
- Not run is never reported as passed.
- No em-dashes in printed report text.

## File Structure

- `R/golive.R`: `golive_check()`, registry loader, report printer.
- `R/golive-checks.R`: `golive_quiz_links()`, `golive_identifier_drift()`.
- `inst/golive/checks.yml`: the registry.
- `inst/templates/course/Makefile`: `golive` target.
- `tests/testthat/test-golive.R` and `tests/testthat/fixtures/golive/`.
- Skill doc: one release step (which skill file is an open item).

## Tasks

### Task 1: Fixtures
- [ ] Cut a minimal export fixture: the midterm QTI trimmed to a few questions with placeholders and one resolved image, one clean module quiz, matching `assessment_meta.xml`, a stub `web_resources/quiz_images/`.
- [ ] Cut a minimal cartridge fixture with the midterm under its cartridge identifier.
- [ ] Show Logan the fixture file list before committing.

### Task 2: Registry and entry point
- [ ] Failing test: `golive_check()` on the fixture returns one fail and one warn; a missing cartridge marks GL-002 not run.
- [ ] Implement `R/golive.R` and `inst/golive/checks.yml`.

### Task 3: GL-001
- [ ] Failing tests: placeholder found and located by question; missing `$IMS-CC-FILEBASE$` target found; clean quiz passes; unparseable file fails.
- [ ] Implement `golive_quiz_links()`.

### Task 4: GL-002
- [ ] Failing tests: drift warns; same id is ok; new quiz is info.
- [ ] Implement `golive_identifier_drift()`.

### Task 5: Make target, docs
- [ ] Makefile target, skill release step, NEWS entry, roxygen docs.

### Task 6: Live acceptance (Logan runs it)
- [ ] `golive_check("~/Downloads/principles-of-macroeconomics-export.imscc", cartridge = ".../build/resources/midterm/midterm-upload.imscc")` reports 96 placeholders in the midterm, nothing in the module quizzes, and the identifier warning.

## Open items

- Version: ship with 1.4.0 alongside the accuracy audit, or as its own release (1.3.1 or 1.4.0 with the audit moving to 1.5.0)?
- Which skill file gets the release step.
- Whether GL-001 should also cover pages and assignments (`wiki_content/`, `<id>/assignment_settings.xml` bodies), not only quizzes. The failure seen was quiz-only.
- The midterm's root cause is separate diagnosis work, not part of this plan.
- Starting the build needs Logan's go.
