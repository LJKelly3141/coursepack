# Course Accuracy Audit (Ombudsman) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** DRAFT, 2026-10-18. Nothing built. All design decisions answered by Logan on 2026-10-18 (listed below); building has not been authorized.

**Goal:** An accuracy audit for the materials an instructor writes, the counterpart of the accessibility audit. It looks for wrong facts, wrong numbers, wrong or unsupported citations, wrong answer keys, and other mistakes, and it uses two different frontier models (Claude Fable and Codex) as independent reviewers so that each one checks the other.

**Why:** the accessibility audit answers "can every student reach this?"; nothing answers "is what they reach correct?". One model reviewing alone has blind spots that look the same every run. Two different model families reviewing blind, then verifying each other, separates real errors (both see it, or one sees it and the other confirms it) from model noise (the other model rejects it).

**Decisions already made (Logan, 2026-10-18):**
1. **Home: skill plus R helpers.** A `course-accuracy-review` skill runs the models (Fable as a Claude Code subagent, Codex through `codex exec`). The package's R functions do everything deterministic: scope, chunking, reply validation, finding ids, merge, diff, report. No API keys and no model calls in the package, so tests never need a model.
2. **Dual check: both blind, then cross-verify.** Each model reviews every chunk independently with the same prompt. Then every finding from one model is sent to the other to verify. The report marks each finding as agreed, confirmed, disputed, or unverified.
3. **Scope is variable and set by Logan.** Default scope is the materials he created: textbook chapters he wrote, course shell pages, question banks and quizzes, slides, assignments. A published (third-party) textbook is out of scope by default. Scope comes from a config file in the course project and can be narrowed per run.
4. **Version 1.4.0.**
5. **A third, non-model citation check.** DOI and Crossref lookup from the `.bib`, in R. `curl` in Suggests (already there for the privacy sweep if still present; check).
6. **Answer-key findings live in `audit/accuracy-private/`** (gitignored, in the course project). The committed report shows counts only.
7. **Cost guard: always ask before a full-course run.** A narrowed run (`scope` given) goes without asking.
8. **Codex: its default model (none pinned), with web search on**, so it can look up sources the way Fable can.

**Architecture:** R prepares and judges; the skill dispatches.

```
accuracy_prepare(proj, scope)       R: resolve scope, chunk sources, write tasks + prompts
        |
        v
  Pass 1 (blind)   Fable subagents  ||  codex exec          skill: one reply JSON per chunk per model
        |
accuracy_collect(proj)              R: validate replies, drop unverifiable quotes, build verify tasks
        |
        v
  Pass 2 (cross)   Fable verifies Codex findings  ||  Codex verifies Fable findings
        |
accuracy_report(proj)               R: merge, status, coverage, diff vs last run, report + review CSV
```

**Tech Stack:** R, jsonlite, digest, yaml (all already imported); curl (Suggests) for the Crossref check. Codex CLI 0.153.4 (`codex exec --output-schema`, read-only sandbox, default model, web search on). Claude Code Agent tool with `model: "fable"`. testthat 3 with recorded fake replies and recorded Crossref responses.

## Design (the spec)

0. **What counts as an error.** Seven categories, each finding carries one:
   - `fact`: a factual or conceptual statement that is wrong (a definition, a property of an estimator, a historical or institutional fact).
   - `number`: a number in prose that does not match the code output, the table, the data, or arithmetic (a mean quoted as 4.2 when the chunk prints 4.3; percentages that do not sum).
   - `citation`: a reference that does not exist, has wrong metadata (authors, year, title, journal, DOI), or does not support the claim it is attached to. Also an in-text key with no `.bib` entry, and a `.bib` entry never cited.
   - `answer_key`: a quiz or bank item whose keyed answer is wrong, has a second defensible answer, or whose feedback contradicts the key.
   - `code`: code that does not do what the surrounding text says, uses a deprecated or removed function, or would not run.
   - `consistency`: the course contradicts itself (a due date in the syllabus vs the schedule, point totals, chapter or figure cross-references, a term defined two ways).
   - `other`: typos that change meaning, wrong formula notation, a mislabelled axis described in text, outdated information (software versions, policies, URLs that moved).
   Style, tone and wording preferences are NOT findings. The prompt says so, and the schema has no category for them.

1. **Scope file.** `accuracy.yml` at the course project root:
   ```yaml
   include:            # globs, Quarto semantics (reuse the a11y glob matcher)
     - "chapters/**/*.qmd"
     - "modules/**/*.qmd"
     - "slides/**/*.qmd"
     - "assessments/**"
     - "banks/**/*.yml"
   exclude:
     - "reference/**"
   external_repos:     # other repos Logan names, read-only, e.g. his own textbook
     - path: "../real-world-statistics-with-r"
       include: ["**/*.qmd", "*.bib"]
   ```
   `accuracy_prepare(proj, scope = NULL)` reads it; `scope` (a character vector of globs) narrows it for one run ("just chapter 4"). No file and no `scope` stops with a message naming the file to create; there is no built-in default that silently scans everything. Hard excludes that no config can override: `build/`, `docs/`, `_freeze/`, `.quarto/`, any `anon/` or `.anon_build/`, anything beside an `anon_key.csv`, and `semester/*/` grading folders. Student work never reaches either model.

2. **Chunks.** Each in-scope file is split at level-2 headings (or per question for banks), with line spans, capped at a size both models handle well (start at about 400 lines, tune in the pilot). A chunk carries: file, line range, text, the rendered output of its R chunks when a frozen or rendered copy exists (so `number` findings can compare prose to output), and the `.bib` entries it cites. Chunk id = md5 of file path + text, so an edit elsewhere in the file does not invalidate it.

3. **One prompt, one schema, for both models.** `inst/review/accuracy-prompt.md`, `inst/review/accuracy-verify-prompt.md`, `inst/review/accuracy-schema.json`, `inst/review/accuracy-verify-schema.json`. A finding:
   ```json
   {"category": "number", "quote": "the mean wait was 4.2 minutes",
    "problem": "chunk output prints 4.31", "correction": "4.3",
    "evidence": "rendered output of chunk wait-summary", "evidence_url": null,
    "confidence": "high"}
   ```
   `quote` must be copied exactly from the chunk. `evidence` is required; an external fact claim needs `evidence_url` or is downgraded to `confidence: low`. The prompt tells each model it is one of two independent reviewers, that a missed error is worse than no finding but an invented one is worse than both, and that "I could not verify" is a valid answer.

4. **Pass 1, blind.** For every chunk, the skill dispatches a Fable subagent (Agent tool, `model: "fable"`, read-only, with web access for citations) and runs `codex exec -s read-only --output-schema accuracy-schema.json -o <reply>.json` with the same prompt, no `-m` (Codex's default model), and web search enabled. [VERIFY: the flag or `-c` key that enables web search in codex-cli 0.153.4; `codex exec --help` lists none, so find it in Task 3 before relying on it.] Neither sees the other's reply. Replies land in `<work>/replies/<model>/<chunk_id>.json`.

5. **Validation (R, `accuracy_collect()`).** A reply that fails the schema is a failed chunk for that model, not an empty one. A finding whose `quote` does not occur in the chunk text (exact characters, whitespace-normalised) is dropped and counted as `unverifiable_quote`, the same rule the privacy sweep uses for text findings. Counts per model are kept for the report.

6. **Pass 2, cross-verify.** For every surviving finding, `accuracy_collect()` writes a verify task for the OTHER model: the chunk, the quote, the claimed problem, and the evidence. The verifier answers `confirm`, `reject`, or `cannot_tell`, with its own evidence. A finding both models raised independently (same file, overlapping line span, same category, quotes overlapping) is matched before Pass 2 and needs no verification.

7. **Status (R, `accuracy_report()`).**
   - `agreed`: both models found it blind. Highest confidence.
   - `confirmed`: one found it, the other confirmed it.
   - `disputed`: one found it, the other rejected it. Shown with both arguments side by side; Logan decides.
   - `unverified`: the verifier answered `cannot_tell` or failed.
   No status means "correct" or "wrong" by itself; every finding goes to Logan.

8. **Never auto-fixed.** The audit writes no source file. Every finding is a proposal with a `correction` for Logan to accept or reject. This matches the a11y rule for alt text and colour: content under his name is drafted, never authored.

9. **Decision record.** `accuracy_review.csv` (id, file, line, category, status, quote, problem, correction, decision, note). `decision` is Logan's: `fix`, `not_an_error`, `defer`. On the next run a finding marked `not_an_error` is suppressed (by id) and counted, so the same false positive is not argued twice.

10. **Stable ids.** id = hash of file + category + normalised quote. Not line numbers, not the model's wording (same lesson as the a11y finding id). A re-run diffs against the last `accuracy-findings.json`: new, fixed, unchanged.

11. **Coverage is measured, not declared.** The report states: chunks in scope, chunks reviewed by Fable, chunks reviewed by Codex, chunks one or both failed. Fewer reviewed than declared prints `COVERAGE SHORTFALL` naming both numbers. A chunk only one model reviewed is listed as single-checked; that is not a dual check and the report says so.

12. **Cache.** Replies cached by md5 of (model id, prompt version, chunk text). A re-run after editing one chapter only re-sends changed chunks. Changing the prompt invalidates everything, on purpose.

13. **Answer-key containment.** Findings from `assessments/` and banks quote answer-key material, so they are written to a gitignored `audit/accuracy-private/` and only counts appear in the committed report. Mirrors the a11y `assessments/` containment rule.

14. **Cost and time guard.** `accuracy_prepare()` prints chunk count and an estimate of model calls (2 x chunks + verify calls) before anything runs. On a full-course run (no `scope` argument) the skill always shows that estimate and waits for Logan's go. A narrowed run goes without asking.

15. **Crossref check (R, no model), `accuracy_citations()`.** For every `.bib` entry cited in scope: an entry with a DOI is resolved against the Crossref API and its title, first author, year, and container are compared to the `.bib` (normalised case and punctuation); an entry without a DOI is searched by title, and a confident single match is compared the same way. Results: `ok`, `mismatch` (names the fields), `doi_not_found`, `no_match`, `not_checked` (no network or no curl, reported, never a pass). A `mismatch` or `doi_not_found` is a `citation` finding with source `crossref`; it joins the merge as a third voice and can turn a model's `citation` finding into `agreed`. Also reports in-text keys with no `.bib` entry and `.bib` entries never cited, without any lookup. Responses cached by DOI/title. Whether a source supports the claim it is attached to stays with the models; Crossref only checks that the reference is real and correctly described.

## Global Constraints

- R sources pure ASCII. testthat 3. Invented course text only in fixtures. No em-dashes in code, comments, docs, NEWS, commit messages, or any text the report shows.
- No model calls inside R. Tests use recorded fake replies in `tests/testthat/fixtures/accuracy/`.
- The audit never writes to a source file and never writes outside the course project (external_repos are read-only).
- Never touch `inst/skills/uwrf-syllabus/`.
- Every new exported function takes the course project root as its first argument, like every other entry point.

## Review Focus

1. A model invents an error by paraphrasing text that is not there. Expected: dropped by the exact-quote rule, counted as `unverifiable_quote`. Test in Task 4.
2. Both models share a blind spot and both miss a planted error. Expected: the pilot's planted-error set measures recall per model and jointly; the report never claims "no errors", only "no findings". Pilot, Task 9.
3. One model fails on a chunk (timeout, bad JSON). Expected: chunk listed as single-checked or unchecked, coverage shortfall printed. Test in Task 6.
4. A finding Logan marked `not_an_error` comes back after an unrelated edit. Expected: id is stable across line shifts; suppressed. Test in Task 4.
5. Answer-key text leaks into a committed file. Expected: only counts outside `audit/accuracy-private/`. Test in Task 6.
6. Student work reaches a model. Expected: hard excludes cannot be overridden by `accuracy.yml`. Test in Task 1.

---

## File Structure

| File | Responsibility |
|---|---|
| `R/accuracy-scope.R` (create) | read `accuracy.yml`, resolve globs, hard excludes |
| `R/accuracy-chunks.R` (create) | split sources into chunks, attach rendered output and cited `.bib` entries |
| `R/accuracy-model.R` (create) | finding record, ids, reply validation, quote check, cache keys |
| `R/accuracy.R` (create) | exported `accuracy_prepare()`, `accuracy_collect()`, `accuracy_report()` |
| `R/accuracy-report.R` (create) | merge, status, coverage, diff, markdown report, review CSV |
| `R/accuracy-citations.R` (create) | Crossref/DOI check, missing and uncited keys, response cache |
| `inst/review/accuracy-*.md`, `*.json` (create) | prompts and schemas |
| `inst/skills/course-accuracy-review/SKILL.md` (create) | orchestration: Fable subagents, `codex exec`, confirmations, human review |
| `inst/templates/course/Makefile` (modify) | `make accuracy-prepare`, `make accuracy-report` |
| `tests/testthat/test-accuracy-*.R` (create) | one per R file |

## Tasks

### Task 1: Scope
- [ ] Failing tests: yml include/exclude, `scope` narrowing, missing config stops, hard excludes win over includes, external repo read-only resolution.
- [ ] Implement `accuracy_scope()`; reuse the a11y glob matcher rather than a second one.
- [ ] Tests pass.

### Task 2: Chunker
- [ ] Failing tests: split at `##`, line spans exact, bank split per question, cited keys extracted (`[@key]`, `@key`), rendered output attached when a frozen copy exists and marked absent otherwise.
- [ ] Implement `accuracy_chunks()`.
- [ ] Tests pass.

### Task 3: Prompts and schemas
- [ ] Write the review and verify prompts and both JSON schemas.
- [ ] Check by hand with one real `codex exec --output-schema` call and one Fable subagent call on a fixture chunk that both return schema-valid JSON. (Live check; not part of the test suite.)

### Task 4: Finding model and validation
- [ ] Failing tests: schema-invalid reply = failed chunk; quote not in chunk = dropped and counted; id stable when lines shift; id changes when quote changes; cache key changes with prompt version.
- [ ] Implement.
- [ ] Tests pass.

### Task 5: Cross-verify tasks and matching
- [ ] Failing tests: blind-match rule (file, overlapping span, category, quote overlap); matched pairs get no verify task; every unmatched finding gets exactly one task for the other model.
- [ ] Implement inside `accuracy_collect()`.
- [ ] Tests pass.

### Task 6: Report
- [ ] Failing tests: status assignment for all four states; coverage shortfall; single-checked chunks listed; diff new/fixed/unchanged; `not_an_error` suppressed; answer-key findings only as counts in the committed report.
- [ ] Implement `accuracy_report()` and the markdown/CSV writers.
- [ ] Tests pass.

### Task 6b: Crossref citation check
- [ ] Failing tests (recorded responses, no network): DOI resolves and matches = `ok`; wrong year or author = `mismatch` naming the field; unknown DOI = `doi_not_found`; title search with no confident match = `no_match`; no curl or no network = `not_checked`, never a pass; missing and uncited keys found without lookup; a Crossref finding plus a model finding on the same entry merges to `agreed`.
- [ ] Implement `accuracy_citations()`; `curl` in Suggests; polite-pool `mailto` header per Crossref's guidance [VERIFY: current Crossref etiquette and rate limits].
- [ ] Tests pass. One live smoke test, run only when `COURSEPACK_LIVE_CROSSREF=1`.

### Task 7: Skill
- [ ] Write `course-accuracy-review/SKILL.md`: read-first list, scope confirmation, cost confirmation, Pass 1 dispatch (Fable subagents in parallel batches; `codex exec` per chunk), Pass 2 dispatch, never edit sources, walk Logan through `disputed` first, then `agreed`/`confirmed`.
- [ ] Add to `skill_index()` so `install_skills()` ships it; `test-skills-content.R` passes.

### Task 8: Makefile, docs, release
- [ ] Makefile targets, README/SETUP section, NEWS entry, version 1.4.0 (DESCRIPTION, `R/coursepack-package.R` status line, `SETUP.md` install tag, as earlier releases did).

### Task 9: Pilot (Logan runs it in the course project)
- [ ] One chapter Logan picks, plus a copy with planted errors he writes (one per category). Measure: planted errors found by Fable, by Codex, by both, by the pair after Pass 2; false findings per model; time and call count.
- [ ] Tune chunk size and prompt from the pilot; record results in this file.

## Open items

- [VERIFY] The codex-cli 0.153.4 setting that turns on web search (Task 3).
- [VERIFY] Current Crossref API etiquette and rate limits (Task 6b).
- Starting the build needs Logan's go; this plan does not authorize it.
