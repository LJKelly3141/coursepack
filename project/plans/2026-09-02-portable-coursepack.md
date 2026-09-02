# Portable coursepack: the widened scope, planned

Written 2026-09-02 against the three repositories as they were on disk that
day. Status: proposed. No task here starts without Logan's approval for that
task, and nothing is committed without his permission for that specific
commit.

This plan supersedes nothing. `migration-spec.md` (2026-08-31) remains the
execution plan for every move it describes, and this document refers to it by
section number rather than restating it. Where the two disagree, it is because
something measured today differs from what the spec measured on 08-31, and
section 1 says exactly what. `inventory.md` remains the file-by-file record;
section 1g lists its corrections.

Reading order for whoever executes this: the ECON 730 `CLAUDE.md` (the house
conventions and the arrival rule), then `migration-spec.md` in full, then
`inventory.md`, then this document.

---

## 0. What Logan decided on 2026-09-02, and the one rule

Five things changed the scope of the extraction:

1. **Everything moves, the accessibility subsystem included.** The spec's
   Task 11 already planned this, overruling the design's decision 11. What is
   new is that it is no longer a later pass. It is in this pass, in parallel
   with the cartridge chain. Section 12 says what that costs.
2. **`init_course()` is in scope.** Decision 010 said it would be "planned in
   a separate session, after the function API exists." That session is this
   one. Section 5 is the design.
3. **The package repository goes public on GitHub.** Section 10 is the
   checklist. Section 9 explains why this changes the acceptance gate's
   fixture, which the spec's Task 3 designed for a private repo.
4. **The Claude Code skills ship with the package.** Section 6 answers where
   they live, how a user gets them, and which stay behind.
5. **Announcements.** `build_cartridge.R` is gaining announcement generation in
   a separate session today. This plan does not write that code. Section 7
   carries the verified contract into the package.

The one rule, from the ECON 730 `CLAUDE.md`, restated because five directories
are now writable and the boundary is enforced by judgment: **the two courses
share the toolchain and nothing else.** Nothing in this plan writes to the
ECON 202 repository. Nothing copies a value from one course's YAML into the
other's, into a template, or into a test fixture. The ECON 730 checkout is
shared with other sessions; never switch branches in it. Task T30 is the only
ECON 202 item and it produces a memo, not a file in that repo.

---

## 1. Measured today, and what it changes

Every number below is `wc -l`, `grep -c`, `ls`, or `unzip` output from
2026-09-02. Where a number differs from the spec or the inventory, the newer
number is the one to plan against, and the reason for the difference is
stated.

### 1a. ECON 730

**Working tree.** `HEAD` is `5515ece` on `main`. Uncommitted modifications:
`modules.yml`, `content/pages/syllabus.qmd`, `content/pages/welcome.qmd`, and
five files under `docs/`. Untracked: `skill/course-schedule-review/`. No
worktrees, no stash, one local branch. The announcement work in progress
today is therefore not on disk yet: `grep -n -i announce scripts/*.R
scripts/lib/*.R` finds only comment text about iframe titles. Any task that
freezes `build_cartridge.R` has to wait for that work to land (T05).

**`scripts/` is 12,882 lines** across every `.R` and `.sh` file. Of that:

| Set | Files | Lines |
|---|---|---:|
| Cartridge chain, moving | `build_cartridge.R` 927, `build_preview.R` 296, `build_qti.R` 68, `check_manifests.R` 149, `diff_against_reference.R` 204, `lib/resolve.R` 71, `lib/homework_body.R` 192, `lib/quiz_body.R` 89, `test_preview.R` 74, `test_resolve.R` 82 | 2,152 |
| Accessibility, moving | `audit_a11y.R` 388, `lib/a11y_cartridge.R` 668, `lib/a11y_checks.R` 631, `lib/a11y_model.R` 734, `lib/a11y_report.R` 810, `lib/a11y_serve.R` 186, `lib/a11y_targets.R` 514, `test_a11y.R` 3,106 | 7,037 |
| Mockup templates, moving | `templates/mockup/` (3 files) | 493 |
| **Total moving** | | **9,682** |
| Already migrated, delete the copy | `make_course_tile.R` 131 (is `R/tile.R`) | 131 |
| Staying, course-specific | `build_canvas_pages.R` 428, `build_outlines.R` 213, `build_media_players.R` 104, `migrate_data.R` 172, `quiz-artifacts/module-0[1-7].R` 2,503, `measure_page_heights.sh` 77, `transcribe_media.sh` 65 | 3,562 |

Three of the "moving" files are new since the inventory and change the
migration:

- **`build_cartridge.R` is 927 lines, not 769.** It now `source()`s
  `scripts/lib/quiz_body.R` and `scripts/lib/homework_body.R` (lines 429 and
  430). `body_for()` (line 453) inlines the case-study directions, read out of
  the rendered textbook by anchor, into every assignment description, and for
  the seven assignments carrying a `quiz_file:` key it inlines the
  student-facing half of a Markdown quiz source. `build_preview.R` (296 lines,
  not 243) sources the same two files so the mockup shows what ships.
- **`lib/quiz_body.R` truncates at an answer-key heading and hard-stops if
  the leak canary survives.** Its header names three independent guards
  (truncation, canary stop, the builder's pre-zip scan) and says not to remove
  any one because the others cover it. The package keeps all three.
- **`lib/homework_body.R` reads rendered HTML, not `.qmd`,** so the cartridge
  build depends on the textbook having been rendered. Its header states that
  cost. This matters for fixtures: a synthetic textbook has to look like
  Quarto output (section elements with ids), not like source.

**`modules.yml` is 775 lines.** 11 modules; items by form: 8 header, 44 page,
5 link, 17 assignment, 0 quiz, total 74 (the spec measured 69 on 08-31:
pages went 46 to 44, assignments 10 to 17). 17 `due:` fields, 38 `body: true`
pages, 7 `quiz_file:` keys, no top-level `quizzes:` block. The seven module
quizzes are Canvas assignments with inlined questions, not QTI; `build/qti/`
is empty and `assessments/exercises/` is empty. The R/exams path is idle, as
the spec says, and the spec's Task 9 stands.

**`course.yml` now declares two assignment groups** (Case Studies 80.0,
Quizzes 20.0, added 2026-09-01) while `assignment_defaults.group: Homework`
names a group that no longer exists and `build_cartridge.R` line 228 reads
`course$assignment_groups[[1]]` only. See 1b for what that produced.

**Due dates are converted with a fixed offset.** Lines 501 to 525: a bare
date means 11:59 PM Central, emitted as the next day `T04:59:00`, with a
`stop()` on any date on or after 2026-11-01 because the offset would be wrong
after daylight time ends. The comment says a course crossing that boundary
"needs real timezone handling rather than this arithmetic." Section 8 is that
handling, and announcements make it unavoidable now rather than later.

**Other facts unchanged from the inventory** and still to be removed in the
move: `PROJ` default at line 60 (absolute path), the textbook sibling-layout
fallback at line 437, `TEXTBOOK_DOCS` from the environment at line 438, the
output filename `econ-730-<date>.imscc` at line 905, `utils::zip` at line 918
(needs a `zip` binary on the PATH), and the build date in `lomimscc:dateTime`
at line 732.

**Announcement bodies exist and are not in version control.**
`semester/fall-2026/announcements/` holds seven HTML files,
`01-2026-09-02-welcome.html` through `07-2026-10-12-module-07.html`, and
`.gitignore` ignores `semester/*` with a single `!semester/README.md`
negation, deliberately, so that nothing tied to enrolled students is ever
committed. If `announcements.yml` names that directory, a fresh clone or a git
worktree cannot build the cartridge. Decision D5 in section 13.

**Skills.** `skill/` holds four `SKILL.md` files: `make-coursepack` 378
lines, `course-accessibility-review` 395, `preview-course` 134,
`course-schedule-review` 239 (untracked, written today). `.claude/skills/`
holds two others, `session-startup` and `strip-ai-characters`, and those two
are the ones that appear in this session's available-skills list; the four in
`skill/` do not. So today the four are documents that describe skills, not
active skills. References to `scripts/` paths that the migration invalidates:
accessibility 10, make-coursepack 3, preview 1, schedule 0.

**Other measurements used below.** `content/canvas/` holds 38 files;
`media/` holds 93; `project/accessibility/2026-09-01-findings.json` holds
41,902 findings and is the latest script-version audit, so it is the baseline
for T20; `reference/` holds the Fall 2025 export, `test-upload-export.imscc`
(its round trip), `policy/`, `literature/`, and a README; `reference.yml` is
absent; `.claude/settings.json` declares four `additionalDirectories`;
`NEW_COURSE_BOOTSTRAP_SPEC.md` is 2,160 lines, from before the package
existed, and its Configuration Variables block is the best existing list of
what a new course has to be asked (section 5 uses it).

### 1b. The 2026-09-02 build and its round trip

`build/coursepack/` holds `econ-730-2026-09-02-published.imscc` (built by
the current script), `managerial-statistics-export.imscc` (229,191 bytes,
13:10 today, the Canvas export of the course after import and hand edits),
and `staging/`. Comparing the two:

| | Built today | Round-trip export |
|---|---|---|
| `assignment_groups.xml` groups | 1 (Case Studies 80.0) | 2 (Case Studies 80.0, "Module Quizes" 20.0, typo as Canvas has it) |
| `imsdt_xmlv1p1` topic resources | 0 | 7 |
| `due_at` on the first assignment | `2026-09-26T04:59:00` | `2026-10-03T04:59:59` |
| `time_zone_edited` | | `Central Time (US &amp; Canada)` |

Three consequences:

1. **Spec Task 12a (multiple assignment groups) is now an ECON 730 need, not
   only an ECON 202 one.** The second group was made by hand in Canvas; the
   next cartridge built from source carries one group, and the reference
   diff against this export will report the missing one. T11 pulls it forward.
2. **The seconds differ.** The builder writes `T04:59:00`; Canvas, after the
   hand corrections recorded in `course-schedule-review`, holds `T04:59:59`.
   Whether the builder should emit `:59` to match what Canvas itself writes
   for an end-of-day deadline is decision D6. Until decided, the diff will
   show 17 divergences that are not bugs; declare them, do not "fix" them.
3. **Announcements are not module items.** `module_meta.xml` references no
   topic. They are resources plus Canvas-namespace metadata, and section 7
   records the fields verbatim from this export.

### 1c. ECON 202 built its own cartridge toolchain, in Python, and the spec does not know

The spec's section 1 and `econ202-onboarding.md` describe ECON 202 as having
"no `course.yml` or `modules.yml`" and needing five additive files. Measured
today:

- `course.yml` exists. Schema: `title`, `course_code`, `urls.site`, a
  `term:` block (`name`, `first_day`, `last_day`, `timezone:
  "America/Chicago"`, `meets`, `room`, `breaks:` list, `finals`,
  `final_exam`, `enrolled`), `due_time`, a `due_dates:` map keyed by item
  title, `exam_pools`, `canvas`, and `assignment_groups` carrying their
  original Canvas ids.
- `modules.yml` exists, 2,037 lines. Items carry `title`, `type: WikiPage`,
  `position`, `indent`, `published`, `item_id`, `resource_id`, `page`, `url`,
  `height`, and `height_measured` (a timestamp).
- `scripts/build_cartridge.py` (761 lines) builds from those two files plus
  a source export whose Canvas-native resources are carried through byte for
  byte. Its docstring reads "Destined for the coursepack R package. Nothing
  here is specific to any course." Functions: `gid`, `load_yaml`,
  `wiki_html`, `source_resources`, `apply_due_dates`, `fix_accessibility`,
  `apply_exam_pools`, `check_stale_measurements`, `sync_carried_titles`,
  `build`.
- `scripts/extract_cartridge_manifest.py` (219 lines) writes both YAML files
  from any Canvas export. Same docstring claim. `measure_iframe_heights.R`
  (127) and `apply_iframe_heights.py` (74) stamp heights with a date.
- `specs/CARTRIDGE_MECHANICS.md` sections 4, 5b, 10 and 11 are written for
  the package: the two courses use opposite item strategies (ECON 730 is
  `ExternalUrl` and generated bodies; ECON 202 is 149 `WikiPage` iframes and
  36 carried-through quizzes); an export specifies structure and never
  measurements; the bootstrap for a stranger is "export your Canvas course,
  extract, edit, rebuild," not "write a manifest"; and every resource has one
  of three fates, generate, carry through, or drop.
- `build/econ202-fall2026-v8.imscc` and a round trip
  `build/principles-of-macroeconomics-export.imscc` exist. Recent commits:
  "Fix the cartridge import: pages were arriving as file attachments,"
  "Measure every iframe height, and make stale measurements fail the build."
- Still true from the spec: no `Makefile`; the root-level
  `econ202-export.imscc` is where the audit's cartridge discovery cannot see
  it; `CLAUDE.md` is the API-era document and mentions none of the above.

So two schemas and two builders exist. ECON 202's is the one with a working
"start from an export" path and dated measurements; ECON 730's is the one with
generated bodies, quiz inlining, containment guards, and a verified round
trip. **This plan does not reconcile them and does not decide which survives.
It records that the spec's Task 13 and the onboarding document are stale and
that any ECON 202 work is now a schema decision first (T30).** What this plan
does take from ECON 202 is design, not values: the `term:` block with a
timezone (section 8), the measured-with-a-date idea, and the extractor as the
second entry point for `init_course()` (section 5, deferred half).

### 1d. The coursepack repository

Three commits: skeleton, MIT licence plus spec, `course_tile()`. Files:
`DESCRIPTION` (version 0.0.0.9000; Imports `digest`, `grDevices`, `grid`,
`jsonlite`, `magick`, `stats`, `stringr`, `tools`, `utils`, `xml2`, `yaml`;
Suggests `exams`, `testthat`; `SystemRequirements` naming Node, npx, and
Chrome for the audit only; author email at uwrf.edu), `LICENSE` (year 2026,
holder Logan Kelly), `LICENSE.md`, `NAMESPACE`, `README.md`,
`R/coursepack-package.R`, `R/tile.R` (139 lines, defines its own `%||%` at
line 139), `man/`, `tests/testthat.R`, `tests/testthat/test-tile.R` (68
lines; fixtures are written into `tempdir()` from R lists, which is the
pattern section 9 generalizes), `.Rbuildignore` (excludes `project/`,
`.claude/`, `.github/`, `LICENSE.md`, the Rproj), `.gitignore`, and
`project/` with the three documents. No `inst/`, `tools/`, `vignettes/`, or
`.github/`. The README says "Status: skeleton" and names both course repos by
their `Teaching/` paths.

### 1e. Sensitive-content audit, as of today

- ECON 730, excluding `docs/` and `build/`: the only files matching
  `api/v1`, `Bearer`, a Canvas token name, or the literal token shape
  `[0-9]{4,5}~[A-Za-z0-9]{40,}` are `CLAUDE.md` and
  `NEW_COURSE_BOOTSTRAP_SPEC.md`, both prose about the token having been
  removed. Nothing in `scripts/` matches.
- ECON 202: zero files match the literal token shape; 18 scripts read
  `Sys.getenv("CANVAS_...")`. Nothing from ECON 202 ships in the package, so
  this is a report, not a task.
- coursepack: nothing matches in the tree or in `git log -p` across the
  three commits.
- The token matter is closed per the ECON 730 memory and TODO. It appears
  here only because the task asked for confirmation that nothing of that kind
  is in what would ship. Confirmed: nothing is.

### 1f. Corrections to `inventory.md`

| Inventory says | Measured today | Effect |
|---|---|---|
| `build_cartridge.R` 769 lines | 927 | quiz and homework body inlining; two new `source()` calls |
| `build_preview.R` 243 | 296 | sources the same two body files |
| no `lib/homework_body.R`, `lib/quiz_body.R` | 192 and 89 lines | two more files move (T07) |
| no `build_media_players.R` | 104 lines, writes `assets/players/<stem>.html` | stays; course-specific media pipeline |
| no `scripts/quiz-artifacts/` | 7 files, 2,503 lines | stays; course content generators |
| live course 11 / 69 / 8 / 46 / 5 / 10 / 0 | 11 / 74 / 8 / 44 / 5 / 17 / 0 | `reference.yml` counts (T08) |
| one assignment group | two declared; builder still writes one | T11 pulled forward |
| ECON 202 has no `course.yml` or `modules.yml` | both exist, different schema, own builder | Task 13 and `econ202-onboarding.md` stale (T30) |
| `make_course_tile.R` duplicate to delete at repoint | still present, 131 lines | T14 |

---

## 2. The five scope changes and what each costs

**2a. The accessibility subsystem moves in this pass.** 7,037 lines, of
which 3,106 are tests written as plain assertions with a terminal verdict,
to be re-expressed as testthat blocks without losing any. The package
acquires a hard runtime dependency on Node.js, `npx`, and a Chrome for
Testing download for anyone who runs the audit, and a `python3` dependency
for serving pages (the mockup already had that one). `R CMD check` cannot run
the pa11y path on a machine without Chrome, so the integration test skips
there, which means the subsystem's most important path is verified only on
machines that have the browser. Section 12 says this plainly. The spec's
section 3 answers the design's three exclusion reasons and still stands.

**2b. `init_course()` is designed and built.** A scaffolder that writes an
empty course which builds, checks, and contains answer keys correctly. Its
verification bottoms out in a human importing an empty course into a
throwaway Canvas shell, which only Logan can do. Section 5.

**2c. The repository goes public.** Every ECON 730 fact leaves package code,
tests, documentation, and fixtures. The spec's pinned fixture of the real
`course.yml`, `modules.yml`, and 38 `content/canvas/` bodies cannot ship in a
public repository under the "course content never enters the package" rule,
so the acceptance gate splits into a synthetic gate that ships and a
real-course gate that lives in the private ECON 730 repo. Section 9.

**2d. The skills ship.** Canonical copies in `inst/skills/`, copied into a
course's `.claude/skills/` by `init_course()` and `install_skills()`.
Section 6.

**2e. Announcements.** A new item form in the cartridge, a new manifest
(`announcements.yml`), and the first place where the fixed UTC offset stops
being good enough. Sections 7 and 8.

---

## 3. Lanes and the dependency graph

Four lanes. After T01 and T02, the lanes proceed independently and Logan can
run one agent per lane. Cross-lane edges are listed explicitly; everything
else within a lane is serial in the order given.

```
T01 ─ T02 ─┬─ A: T03 ─ T05* ─ T06 ─ T07 ─ T08 ─ T09 ─ T10 ─ T11 ─ T12 ─ T13 ─ T14
           │        (T05 also needs T04, the announcement landing, and an import)
           ├─ B: T15 ─ T16 ─ T17 ─ T18 ─ T19 ─ T20 ─ T21
           ├─ D: T04 ─ T22 ─ T23 ─ T24 ─ T25 ─ T26 ─ T27 ─ T28 ─ T29
           └─ E: T30 (memo only)
```

Cross-lane edges:

| Edge | Why |
|---|---|
| T04 before T05, T13, T19, T25 | the synthetic fixtures are the input to the shipped gate, the preview test, the pa11y integration test, and the scaffold test |
| T03 before T10 | the cartridge move routes every date through the timezone helper |
| T07 before T13 | the preview sources the body helpers |
| T08 and T10 before T25's verification step | `init_course()` is verified by running `check_manifests()` and `build_cartridge()` on its output |
| T14 after T13 and T20 (or T14 leaves the a11y scripts in place and T20 deletes them) | deleting `scripts/` copies before every Makefile recipe is repointed breaks the shared checkout |
| T22 before T25 | the scaffold copies the skills |
| T26 rerun immediately before T29 | the scrub is only true of the tree it was run on |
| T27 after T14, T20, T25 | the README describes what exists, not what is planned |
| T29 last | flipping visibility is irreversible in practice |

What blocks what, stated for scheduling:

- **Nothing blocks T02, T04, T15, T22, T24, T26, T30 once T01 is done.** Those
  are the seven things that can start in parallel on day one.
- **T05 is blocked on events outside this plan**: the announcement session's
  commit to ECON 730, and a Canvas import of a cartridge that carries
  announcements, verified by round trip. Freezing the baseline before that
  produces a gate that fails the moment announcements are added, and
  regenerating it then would be exactly the "regenerate to pass" this
  design forbids.
- **T10 is the highest-risk task and is blocked on the most things**: T03,
  T05, T06, T07, T08, T09, decision D1, and the freeze.
- **T11 changes cartridge output** and lands only after T10's gate is green,
  as its own deliberate baseline regeneration, followed by an import.
- **T29 is blocked on every other task and on decisions D8 to D11.**

---

## 4. Tasks

Each task is one sitting and one commit per repository touched. "Done when"
is the evidence, not the feeling. Spec task numbers are given where a task is
the spec's task with amendments; the spec's own steps apply unless amended.

### Lane A: the cartridge chain

**T01. Confirm state.** Spec Task 1, plus: record the 1a to 1e measurements
in `log/sessions/` of the ECON 730 repo (no session log exists yet for
2026-09-01 or 09-02). Touches: one session log. Done when: `git status` in all
three repos is read and the files each lane will touch are known to be
clean. Must not break: nothing; writes one log file.

**T02. Config readers and the version stamp.** Spec Task 2, plus
`read_announcements(proj)` returning the parsed `announcements.yml` or `NULL`
when absent, and one internal `%||%` in `R/utils.R` replacing the copy in
`R/tile.R`. Add `install-toolchain` to the ECON 730 Makefile (spec section 4
recipe). Touches: `R/config.R`, `R/utils.R`, `R/tile.R` (one deletion),
`tests/testthat/test-config.R`, ECON 730 `Makefile`. Done when: `make -C
<econ730> install-toolchain` then `coursepack::coursepack_version()` prints
the bumped version; `read_announcements()` on a directory without the file
returns `NULL` and on a malformed file stops with the file name. Must not
break: nothing consumes these yet.

**T03. The timezone helper.** Section 8. `local_to_utc(date, time, tz)` and
`read_timezone(course)`; tests at both 2026 daylight-time boundaries and at
the seven announcement times from 1b. Touches: `R/time.R`,
`tests/testthat/test-time.R`. Done when: for every one of the 17 live due
dates (all before 2026-11-01), the helper with `America/Chicago` produces
the identical `T04:59:00` string the fixed offset produces, asserted in a
test over a synthetic list of those dates, not read from `modules.yml`; and
2026-09-08 00:00 Central produces `2026-09-08T05:00:00`. Must not break:
nothing calls it until T10.

**T05. The acceptance gate, in two halves.** Spec Task 3 amended by section
9. Package half: `tests/testthat/test-cartridge-gate.R` against the synthetic
fixture from T04, expected tree generated by `tools/baseline.R` running the
frozen ECON 730 script against that fixture. Course half:
`coursepack::gate_check(proj, expected)` plus the ECON 730 repo's own
`project/coursepack-gate/expected-tree.txt` generated from the real course
by the same tool. Both normalize the one `lomimscc:dateTime` line (spec 2f).
Precondition: the announcement work has landed in ECON 730 and a cartridge
carrying announcements has been imported and round-tripped. Touches:
`tools/baseline.R`, the gate test, `R/gate.R`, ECON 730
`project/coursepack-gate/`. Done when: both expected trees exist, each line
reads `<32 hex> <path>`, and the package test shows one skip with the reason
"build_cartridge has not moved into the package yet". Must not break: the
tool reads the ECON 730 repo and writes only under `build/` and
`project/coursepack-gate/` there. Never regenerate an expected tree to make
a failing gate pass.

**T06. Move the resolution helpers.** Spec Task 4 as written. Done when:
`make -C <econ730> checkyml` output is unchanged before and after.

**T07. Move the body helpers.** New. `homework_section_html()` and the quiz
functions from `lib/homework_body.R` and `lib/quiz_body.R` move verbatim to
`R/body-homework.R` and `R/body-quiz.R`, exported, with their header comments
intact (the three-guards comment in particular). The answer-key heading
pattern and the canary string become named package constants in one place,
documented as the convention a course must follow, not yet configurable
(generalizing it is a later item, recorded in T27's NEWS). Shims replace the
two `lib/` files, marked TRANSITIONAL. Tests: extraction of a section by
anchor from a synthetic rendered chapter; a synthetic quiz file whose
answer-key section must not appear in the returned HTML; a synthetic quiz
file carrying the canary string must stop. Touches: two `R/` files, two
tests, two shims. Done when: `make -C <econ730> coursepack` (the old script,
now sourcing the shims) builds a cartridge whose unpacked tree matches the
T05 course-half expected tree. Must not break: both the cartridge script and
the preview script source these; a shim missing one name breaks both.

**T08. Move the manifest checker; introduce `reference.yml`.** Spec Task 6.
Amendment: the live counts are now 11 / 74 / 8 / 44 / 5 / 17 / 0 and must be
re-measured at execution. The two-groups fact from 1b means the checker
should also validate that every `group:` named by an assignment or by
`assignment_defaults` exists in `assignment_groups`; today
`assignment_defaults.group: Homework` would fail that check, which is
correct and is a finding for Logan, not something to silently fix in the
YAML. Done when: spec Task 6's verification, and the group check fires on
the current `course.yml`.

**T09. Move the reference diff.** Spec Task 7 as written, plus: transcribe
whatever the current `EXPECTED` vector holds (count it on disk; the spec says
ten). `reference.yml`'s `export:` for ECON 730 points at
`reference/managerial-statistics-fall-2025-export.imscc` per decision D2;
if D2 retires the structure gate, the diff still runs as a format check and
the counts block is omitted.

**T10. Move the cartridge builder, with announcements and the timezone
helper.** Spec Task 8 with these amendments:

- One more destination file: `R/cartridge-announcements.R`, carrying the
  announcement code as landed in ECON 730, mechanically, per section 7.
- Every `due_at` and every `delayed_post_at` routes through `local_to_utc()`
  with the course's declared timezone. The `stop()` at 2026-11-01 is
  removed, because the helper handles the boundary; a test asserts the
  string equality from T03 so the gate cannot move.
- The filename comes from `course$slug %||% slugify(course$canvas$course_code)`
  per decision D1.
- `body_for()`'s ECON 730 submission prose stays in R for this task (spec
  Task 8 step 5; moving it is spec 12d). It is the one remaining piece of
  course prose in package code after this task, and T27's NEWS says so.
- Do not touch the single-group read. That is T11.

Done when: both halves of the T05 gate pass; the spec's Task 8 tests plus
the announcement tests from section 7 pass; and **Logan imports the next real
cartridge into a throwaway shell and round-trips it.** Not fully verified
until that has happened.

**T11. Multiple assignment groups.** Spec 12a, pulled forward because 1b
shows ECON 730 needs it. Emit every declared group; route each assignment by
its `group:` or `assignment_defaults$group`; stop on a name that matches no
group. Regenerate both T05 expected trees deliberately, in their own commit
whose message says the cartridge was supposed to change. Done when: the
generated `assignment_groups.xml` carries two groups with the weights in
`course.yml`, the reference diff against the 09-02 round trip no longer
reports the group as a divergence, and Logan imports and confirms the
Quizzes group arrives with weight 20. Must not break: with one group declared
(the synthetic fixture), output is byte-identical to before.

**T12. Move the QTI builder.** Spec Task 9 as written.

**T13. Move the preview builder.** Spec Task 5, plus: the preview calls the
package body helpers (T07); `inst/templates/mockup/` is where the three
templates land; and the Makefile's `open` call gets a fallback to
`xdg-open` so the scaffolded Makefile (T24) is not macOS-only. Done when:
spec Task 5's verification, run both ways with a stubbed opener.

**T14. Delete the old copies, repoint, update ECON 730 docs and skills.**
Spec Task 10, plus deletions: `scripts/make_course_tile.R`,
`scripts/lib/homework_body.R`, `scripts/lib/quiz_body.R` (the shims). Plus
header comments marking `build_canvas_pages.R`, `build_outlines.R`,
`build_media_players.R`, `migrate_data.R`, and `scripts/quiz-artifacts/` as
course-specific per the arrival rule, and bringing the two
`normalizePath(".")` scripts up to it. The `test` target runs the package
suite; the a11y scripts stay until T20 unless T20 has already landed. The
`skill/` directory: its four files become pointers to the package copies
(section 6), not deletions, so the ECON 730 record of where they came from
survives. Done when: spec Task 10 step 6, and `grep -rn 'scripts/lib'
Makefile skill/ CLAUDE.md` finds only the a11y recipe if T20 is pending.

### Lane B: accessibility

The spec's Task 11 is the specification for all of T15 to T20; each of its
nine handling notes lands in the task that moves the file it names. Every
task ports the corresponding slice of `test_a11y.R` in the same commit,
keeping every assertion and every negative control.

**T15. `a11y_serve.R` and `a11y_model.R`.** `R/a11y-serve.R` gains the
`npx`-on-PATH check and a `python3`-on-PATH check with a message naming what
to install; `PA11Y_VERSION` stays pinned here. `R/a11y-model.R` moves
verbatim; `AXE_CRITERION` (74) and `AXE_NO_WCAG_TAG` (30) sizes asserted; the
warn-once cache becomes a package environment. Done when: the ported tests
pass and `port_is_free()` is exercised against a real socket.

**T16. `a11y_targets.R` and `a11y_checks.R`.** Byte-level copy for
`glob_to_regex()`'s three control-byte sentinels; the `assets/**` tripwire
test is ported first. `SOURCE_EXCLUDE_RE` keeps `assessments` (spec note 6).
The `exclude` argument stays required. Done when: the tripwire passes and
the "two repos with the same basename halt" test passes.

**T17. `a11y_cartridge.R` and `a11y_report.R`.** `CART_GENERATOR` reworded;
`CARTRIDGE_SEARCH_DIRS` becomes an argument; `audit_cartridge()` keeps its
required surface argument. Done when: the two-byte-identical-cartridges
under-two-surfaces test passes and a synthetic wiki page with an untitled
iframe produces one finding.

**T18. `audit_course()` driver and the Makefile recipe.** Spec note 1's
signature. The ECON 730 `a11y` recipe becomes `Rscript -e
'coursepack::audit_course(c(".", "$(TEXTBOOK_REPO)"))'`. Done when: the
driver's coverage cross-check still reports measured against declared and
shouts `COVERAGE SHORTFALL` when a loop is commented out (verify by doing
it, then restore).

**T19. The pa11y integration test.** New. Against the T04 synthetic course,
served and audited for real; `skip_if(!nzchar(Sys.which("npx")))` and the
same for `python3`. Asserts both runners appear in returned issues and that
a deliberately failing fixture page (a filename-as-alt image, a missing
`lang`) produces the expected findings. Done when: it passes on Logan's
machine and skips cleanly on a machine without Node.

**T20. Real-run diff and deletion.** `audit_course()` against the real ECON
730 and textbook checkouts, from the primary checkout path (surface identity
is the basename; a worktree path re-bases every id and the diff becomes
meaningless). Findings JSON diffed against
`project/accessibility/2026-09-01-findings.json`: 0 fixed, 0 new, allowing
the known axe-core contrast non-determinism. Then delete `scripts/audit_a11y.R`,
`scripts/lib/a11y_*.R`, `scripts/test_a11y.R` with Logan's approval and
repoint the `test` target. Done when: the diff is clean and the deletion
list was shown and approved.

**T21. Announcement bodies as an audit surface.** New coverage, not a move,
so it lands after T20 and changes finding counts in its own commit. The
cartridge check reads `wiki_content/` only; the seven `imsdt_xmlv1p1` topic
bodies are HTML the same students read and are audited by nothing. Extend
the static cartridge checks to topic `<text>` bodies with the same untitled
iframe and link-text rules. Done when: a synthetic cartridge with one topic
carrying a bare-URL link produces one 2.4.4 finding, and the real re-audit's
new findings are all under topic bodies.

### Lane D: portability

**T04. Synthetic fixture courses.** Section 9 specifies them. Three:
`minimal-course` (one module, one header, one iframe page, one `body: true`
page with a tiny body, one homework assignment, one `quiz_file` assignment,
one announcement), `fake-textbook/docs` (two rendered-looking chapter pages
with the anchors the fixture references, written as Quarto emits them:
`<section id="..." class="level2">`), and `pair/` (two courses whose repos
share a basename, for the a11y halt test, and two that do not). All values
invented: course code `ABCD 101`, site `https://example.invalid/course`.
Touches: `tests/testthat/fixtures/`. Done when: `grep -rniE 'econ|uwrf|
kelly|ljkelly|managerial|macro' tests/testthat/fixtures/` returns nothing,
and a test asserts the fixture parses with `read_manifest()`.

**T22. Skills into `inst/skills/`.** Section 6. Four directories, each a
generalized `SKILL.md`; a fifth, `new-course`, wrapping `init_course()`.
Course-specific residue stays in the ECON 730 `skill/` copies. Touches:
`inst/skills/*/SKILL.md`. Done when: `grep -rniE 'econ ?730|managerial|
ljkelly3141|uwrf|reference/managerial' inst/skills/` returns only lines
inside a block explicitly labelled as one course's historical verification
record (decision D9 says whether even those stay), and every command in
every skill names a package function or a Makefile target that exists.

**T23. `install_skills()`.** `install_skills(proj, which = NULL, overwrite =
FALSE)` copies `inst/skills/<name>/` to `<proj>/.claude/skills/<name>/`,
refusing to overwrite unless told, printing what it wrote and the package
version. Each copied `SKILL.md` gets a trailing comment line naming the
package version it came from so drift is visible. Done when: a test copies
into a tempdir, asserts the files, asserts the refusal, asserts the
overwrite. Must not break: never writes outside `proj`.

**T24. `init_course()` templates.** `inst/templates/course/` holding every
file in section 5's table, with `{{key}}` placeholders and a tiny internal
`render_template()` (gsub, no new dependency). Done when: every template
renders with the section 5 example values and the rendered `_quarto.yml`
parses with `yaml::read_yaml()`.

**T25. `init_course()`.** Section 5's signature and behaviour, with tests
that run it into a tempdir and assert every file, the allowlist shape, the
canary, the refusal on a non-empty directory, the timezone validation, and
that `read_manifest()` parses the result. Verification step, after T08 and
T10 exist: `check_manifests()` passes on the scaffold, `build_cartridge()`
builds it, the built cartridge contains one module, one page, no
`assessments/` content and no `$IMS-CC-FILEBASE$`, and **Logan imports the
scaffold cartridge into a throwaway shell.** Done when: all of that, and the
import.

**T26. Scrub audit.** The section 10 greps, run and their output recorded in
the commit message or a `project/` note. Anything found is fixed in the
file that owns it. Done when: every grep in section 10 returns the allowed
set only. Rerun before T29.

**T27. README, CONTRIBUTING, NEWS.** For a stranger: what it is, the
architecture in five sentences (Canvas holds structure, Pages holds content,
containment by allowlist and canary, a zip proves nothing, import and
round-trip), system requirements split into "to build a cartridge" (R,
`zip`) and "to preview or audit" (`python3`; Node, `npx`, Chrome for the
audit), the quick start (`init_course()`, edit, `make coursepack`, import),
and an honest status table: which entry points have been verified by a real
Canvas import and which have not. CONTRIBUTING carries the arrival rule, the
gate rule (never regenerate to pass), the no-course-content rule, and how to
run the tests with and without Chrome. NEWS records what moved and what is
still ECON 730 prose in R (`body_for()`). Done when: a reader who has never
seen the ECON 730 repo can follow the quick start; Logan reads it as that
reader.

**T28. CI.** `.github/workflows/check.yml` running `R CMD check` on Ubuntu
with the pa11y tests skipping; a second, optional job that installs Node and
lets pa11y fetch Chrome and runs T19 for real. Decision D12 says whether the
second job exists at all. Done when: the first job is green on the public
repo; the second is either green or deliberately absent.

**T29. Go public.** Section 10 signed off line by line; T26 rerun on the
final tree; `git log -p | grep` for the token shape and for `/Users/`
outside `project/`; repository description and topics set; then the
visibility flip, by Logan, by hand. Done when: the repository is public and
`remotes::install_github("LJKelly3141/coursepack")` works without a PAT on
a machine that has never seen the repo.

### Lane E: ECON 202

**T30. Decision memo, no code.** Written into
`project/econ202-decision.md`. Lays out, with the 1c measurements: the two
schemas side by side; the three options (port `build_cartridge.py` and the
extractor into the package as a second item strategy with carry-through;
leave ECON 202 on its Python builder and out of the package; converge the
schemas, which touches ECON 730's `modules.yml`); what each does to the
UPDATE ONLY rule; and a recommendation, marked as one. Supersedes
`econ202-onboarding.md` sections 2 and 3 when Logan accepts it. Done when:
Logan has read it. Must not break: writes nothing in `macro_principles`.

---

## 5. `init_course()`

The piece that makes the system usable by a stranger with no course. It
scaffolds a repository that builds, checks, previews, and contains answer
keys, and stops there.

### Signature

```r
init_course(path,
            code,                       # "ABCD 101"
            title,                      # "Introduction to Something"
            site_url,                   # "https://<user>.github.io/<repo>"
            timezone,                   # IANA name; validated against OlsonNames()
            institution   = NULL,
            textbook_url  = NULL,       # sets urls$textbook when given
            textbook_docs = "none",     # local rendered textbook, or "none"
            skills        = TRUE,       # copy inst/skills into .claude/skills
            claude_md     = TRUE,       # write a CLAUDE.md for the course
            git           = TRUE,       # git init only; never commits
            ask           = interactive())
```

Returns `path` invisibly. Prints the file list it wrote, the package version,
and the next steps (below).

`timezone` has no default on purpose. `Sys.timezone()` is shown as the
suggestion when prompting and is never used silently: a wrong timezone moves
every due date and every announcement by hours and looks fine in the XML.
`path` must not exist or must be empty; the function refuses otherwise and
never overwrites. `code`, `title`, and `site_url` are required; `site_url`
must start with `https://`.

### What it asks

Only when `ask` is `TRUE` and the argument is missing. Non-interactive calls
with a missing required argument stop, which is what makes the function
testable and scriptable. The prompt order and wording come from the
Configuration Variables block of `NEW_COURSE_BOOTSTRAP_SPEC.md`, trimmed to
what the package reads: course code, title, institution (optional), the
Pages site URL, the timezone, and the textbook URL (optional). It does not
ask for a term, dates, module count, instructor name, YouTube or NotebookLM
ids, or a GitHub username; none of those is read by any package function,
and the dates in particular are exactly what `course-schedule-review` says
must never be invented.

### What it writes

Every file comes from `inst/templates/course/`. Nothing is copied from either
real course; the templates are written fresh and the T26 grep proves it.

| File | Content |
|---|---|
| `course.yml` | `code`, `title`, `institution`, `slug` (slugified code, decision D1), `term:` block with `name: TBD`, `first_day`, `last_day`, `timezone`, and an empty `breaks:` list (the ECON 202 shape, chosen because the schedule skill's open item wants exactly it, decision D4), `urls: {site, textbook?}`, `textbook_docs`, `canvas:` with the settings every ECON 730 and ECON 202 export agreed on (`default_view: modules`, `is_public: false`, `group_weighting_scheme: percent`), one assignment group `Assignments` at 100.0, `assignment_defaults` (`points: 100`, `submission_types: online_upload`, `group: Assignments`), no `grading_standard`, no `late_policy` (spec 12b makes their absence mean "not emitted"; until 12b lands, the template carries a commented block and the builder's unconditional emission is a known limitation stated in NEWS) |
| `modules.yml` | the item-form legend as a comment block; one module "Start here" with a header item, the welcome page, and one assignment with `todo: "replace me"` and `published: false`, which exercises the todo/published refusal the moment someone flips it |
| `announcements.yml` | `dir: content/announcements`; one entry, the welcome, with no `post_at` (posts at import); the section 7 schema as landed |
| `reference.yml` | not written. A new course has no export. `reference/README.md` explains how to get one and what to do with it |
| `content/pages/welcome.qmd`, `content/pages/syllabus.qmd` | stubs with a title and one paragraph |
| `content/canvas/.gitkeep`, `content/announcements/welcome.html` | the body contract directory and one body |
| `assessments/README.md`, `assessments/leak-canary.qmd`, `assessments/quizzes/.gitkeep` | the containment README (rewritten, generic) and the canary carrying the package's canary constant |
| `assets/data/.gitkeep`, `assets/images/.gitkeep`, `assets/files/.gitkeep` | with a README line: everything here is public |
| `_quarto.yml` | `type: default`, `output-dir: docs`, `render:` allowlist of `index.qmd` and `content/**/*.qmd`, `resources: ["assets/**"]`, `embed-resources: true`; a comment on the allowlist saying why it must never become a blocklist |
| `index.qmd`, `style.css` | minimal |
| `Makefile` | `COURSEPACK ?=` (documented as optional; the default path is the installed package), `install-toolchain`, `site` (with `leakcheck`), `leakcheck` calling `coursepack::leak_check(".")`, `checkyml`, `coursepack`, `refdiff`, `mockup`, `qti`, `a11y`, `tile`, `skills`, `test`, `clean` (which does NOT remove `docs/`, because on a Pages course that directory is the published site; ECON 730's `clean` removes it and that is recorded as a hazard in section 11) |
| `.gitignore` | `build/`, `.quarto/`, `*_files/`, `.Rproj.user/`, `.DS_Store` |
| `README.md` | ten lines: what the repo is, the three commands, where content goes |
| `CLAUDE.md` (optional) | the layout, the four hard rules (docs is public, assessments is never rendered, nothing is embedded in the cartridge, a zip proves nothing), and a pointer to `.claude/skills/` |
| `.claude/skills/*` (optional) | via `install_skills()` |
| `reference/README.md` | how to export a Canvas course and where to put it |

Next steps it prints: render the site, push, enable Pages from `main`
`/docs`, run `make coursepack`, import into a throwaway shell, look, export
back, compare. In that order, with the sentence "a zip that builds proves
nothing."

### What it deliberately does not do

- Create a GitHub repository, push, or enable Pages.
- Run `quarto render`, install Quarto, Node, or Chrome.
- Write any date. `term.first_day` and `last_day` are `null` with a comment.
- Write a reference export or `reference.yml`.
- Commit. With `git = TRUE` it runs `git init` and nothing else.
- Overwrite anything, ever.
- Copy any file from ECON 730 or ECON 202.
- Import into Canvas, or claim the scaffold is valid until someone has.
- Start from an existing Canvas export. That is the second entry point
  (`extract_manifest(imscc)`, the R port of ECON 202's extractor) and it
  belongs to T30's decision, not this pass. The scaffold README says both
  entry points exist and which one is built.

### Verification

Package tests (T25) prove the files. `check_manifests()` and
`build_cartridge()` on the scaffold prove it is a course the package can
build. A render of the scaffold with a fake file dropped into
`assessments/` followed by `leak_check()` proves the allowlist is closed.
Only a Canvas import of the scaffold cartridge, done by Logan, proves the
empty course is a course. `init_course()` is marked verified after that and
not before.

---

## 6. The skills

### The question

Where do Claude Code skills live in an installed R package, how does a user
get them into their own project, and which are course-specific?

### What was measured

The two skills ECON 730 has in `.claude/skills/` are active in this session;
the four in `skill/` are not. That is the only evidence available inside the
three readable repositories about how skills are discovered, and it is
consistent: a project's `.claude/skills/<name>/SKILL.md` is loaded, a
directory named `skill/` is not. Whether Claude Code also loads skills from
an installed plugin, and what that plugin's manifest looks like today, could
not be verified without reading outside the allowed paths, so this plan does
not build on it (section 14).

### Recommendation

1. **Canonical copies live in `inst/skills/<name>/SKILL.md`.** They install
   with the package, `system.file("skills", package = "coursepack")` finds
   them, they version with the code they describe, and `R CMD check` ships
   them without a second distribution channel.
2. **A user gets them by copying into the project.** `init_course()` does it
   for a new course; `install_skills(proj)` does it for an existing one; the
   scaffolded Makefile has a `skills` target that calls it. The copy is
   committed with the course, so a collaborator cloning the course gets the
   skills without installing anything, and the skills a course was built
   with stay with that course even after the package moves on. The cost is
   drift, which is why each copy carries the package version it came from
   and `install_skills(overwrite = TRUE)` is one command.
3. **Not a plugin, in this pass.** A plugin would remove the copy step, but
   its manifest format is unverified here and it would put the skills in a
   second place (the plugin root, not `inst/`). Revisit after T29 with the
   plugin documentation in front of whoever does it.

### Which skills ship, and what is scrubbed from each

| Skill | Ships? | What changes |
|---|---|---|
| `make-coursepack` | yes | commands become package functions and Makefile targets; the reference-export filename and the "9 modules, 72 items, 6 wiki pages" line become "your course's export"; the round-trip verification table stays only as a labelled record of the first course's verification, or goes, per decision D9 |
| `preview-course` | yes | one path update; already generic |
| `course-accessibility-review` | yes | ten path updates; "Read this before every run" stops naming ECON 730's `CLAUDE.md`, `TODO.md`, and decision 011 and instead says to read the course's own `CLAUDE.md` and decision record if it has them; the counts given "as a concrete illustration" go |
| `course-schedule-review` | yes, generalized | the ten-step procedure is generic; the registrar PDF path, the UWRF calendar facts, the seventeen-assignment table, and the Fall 2026 worked schedule are ECON 730's and stay in the ECON 730 copy. The incident narrative is the reason the skill exists; decision D9 says whether it ships with the course named or anonymized as "a course" |
| `new-course` (new) | yes | wraps `init_course()`: what it asks, what it writes, the next-steps list, the sentence that the scaffold is unverified until imported |
| `session-startup` | no | Logan's own opener; names his repos and memory |
| `strip-ai-characters` | no | not a course skill; lives where it lives |

The ECON 730 `skill/` directory keeps its four files as the record of where
the package skills came from, each gaining a one-line header pointing at
`inst/skills/`. They are not deleted (T14).

---

## 7. Announcements: what the package carries

The code is being written in ECON 730 today by a separate session. This plan
does not write it; T10 moves it. The contract below is what was verified
from `build/coursepack/managerial-statistics-export.imscc` and is the bar
the moved code is held to. If the file the other session lands differs from
the sketch, the file wins and this section is corrected, not the file.

**The cartridge shape.** One announcement is two resources: an
`imsdt_xmlv1p1` topic (`<topic>` with `<title>` and `<text
texttype="text/html">`) and a dependent
`associatedcontent/imscc_xmlv1p1/learning-application-resource` file
holding a Canvas-namespace `<topicMeta>` with `topic_id`, `title`,
`delayed_post_at`, `position`, `type` (`announcement`), `discussion_type`
(`threaded`), `has_group_category`, `workflow_state`, `module_locked`,
`allow_rating`, `only_graders_can_rate`, `sort_by_rating`, `sort_order`,
`sort_order_locked`, `expanded`, `expanded_locked`, and an empty
`todo_date`. Announcements appear in no module; `module_meta.xml` references
none.

**Two states, both observed.** The welcome announcement has `workflow_state
active`, `position 1`, and no `delayed_post_at`: posted at import. The other
six have `workflow_state post_delayed` and a `delayed_post_at`.

**All times are UTC with no timezone marker.** The six delayed posts read
`2026-09-08T05:00:00`, `09-14`, `09-21`, `09-28`, `10-05`, `10-12`, each at
`05:00:00`, which is midnight Central on those dates while daylight time is
in force. A builder that writes the local time moves every post to the
previous evening. The package routes `delayed_post_at` through the section 8
helper, never through a fixed offset.

**The source shape.** `announcements.yml` names a directory and lists
announcements; each has a title, an optional local post time, and a body
file in that directory. Bodies are HTML. Missing body file: hard stop,
naming the file. Empty body: hard stop. A `post_at` in the past: the builder
does not decide; it emits what it is given and prints the date, because
Canvas treats a past `delayed_post_at` as posted and that may be intended.

**Tests the moved code must pass (T10):** a fixture with one immediate and
one delayed announcement produces two topic resources, two meta resources,
the manifest dependency edges, `active` and `post_delayed` states, and the
UTC string from the fixture's declared timezone; the same fixture with the
timezone changed to `Europe/London` produces a different string; a missing
body stops; the a11y cartridge check (T21) sees the bodies.

**The bodies' location is a decision, D5.** Today they are under
`semester/`, which is gitignored by design. The scaffold (section 5) puts
them under `content/announcements/`, which is committed and inside the
render allowlist's parent but not a `.qmd`, so Quarto ignores it. ECON 730
can keep them where they are and accept that a clone cannot build until the
directory is restored, or move them. Not this plan's call.

---

## 8. Timezones: one helper, one declared zone

Every date the cartridge carries is stored by Canvas in UTC, written without
a marker, and displayed in the course's zone. Two kinds exist now
(`due_at`, `delayed_post_at`), a third is plausible (`unlock_at`,
`lock_at`), and the fixed `UTC-5` arithmetic in `build_cartridge.R` is
correct for every date currently in the course and wrong for any date after
2026-11-01, which the script itself refuses to emit.

`local_to_utc(date, time = "23:59:00", tz)` builds the local instant with
`as.POSIXct(paste(date, time), tz = tz)` and formats it in `UTC` as
`%Y-%m-%dT%H:%M:%S`. `tz` comes from `read_timezone(course)`, which reads
`course$term$timezone` (the ECON 202 shape, decision D4) and stops if it is
absent or not in `OlsonNames()`. No default zone anywhere in package code:
a default is a fact about one instructor.

The gate protects the move: for every date before the boundary, the helper
must produce the string the arithmetic produced, character for character,
and T03 asserts that before T10 wires it in. The boundary tests assert
2026-10-31 23:59 Central is `2026-11-01T04:59:00` and 2026-11-01 23:59
Central is `2026-11-02T05:59:00`.

ECON 730's `course.yml` has `term: TBD` as a scalar. Making it a block is a
one-key edit that no current code reads (its own comment says "nothing reads
it until dates exist"), so the cartridge is unchanged, but it is an edit to
Logan's file and waits for D4.

---

## 9. The acceptance gate when the package repository is public

The spec's Task 3 freezes the real `course.yml`, `modules.yml`, and 38
`content/canvas/` bodies into `tests/testthat/fixtures/econ730-pinned/`.
Today that would also have to freeze the seven `assessments/quizzes/*.md`
files, because the builder inlines their student-facing halves, and those
files carry answer keys. In a public repository that is not a fixture, it is
a leak. And even without the quiz files, 38 pages of ECON 730 prose and a
`modules.yml` that is forty percent notes about that course would be
"course content entering the package," which the package's own README rule
forbids.

So the gate splits:

**The shipped gate is synthetic.** T04's `minimal-course` exercises every
item form (header, iframe page, `body: true` page, `link` with chapter and
anchor, homework assignment, `quiz_file` assignment, announcement, one
group). `tools/baseline.R` runs the frozen 927-line script against that
fixture and writes `expected-tree.txt`; the package builds the same fixture
and must match. This proves "the move changed nothing" for every code path
the fixture reaches, and it ships.

**The course gate is real and private.** The same tool, pointed at the ECON
730 checkout, writes `project/coursepack-gate/expected-tree.txt` inside the
ECON 730 repository, which is private and already holds the course. `make
gate` there runs `coursepack::gate_check(".", "project/coursepack-gate/expected-tree.txt")`.
This is the gate that protects the live course through T10 and T11, and it
never leaves that repo.

What is lost: the package's own CI cannot prove the real course still
builds identically. What is gained: the package can go public at all. The
synthetic fixture has to be good enough that a regression on a real path is
also a regression on a fixture path, which is why T04 lists every form.

The same rule governs every other fixture: invented values, `example.invalid`
hosts, `ABCD 101`, and a grep that fails on any course name.

---

## 10. Public-readiness checklist

Each line is a command or a yes/no that someone else can rerun. T26 runs
them; T29 signs them.

**Content**

- [ ] `grep -rniE 'econ ?730|econ ?202|managerial|macro_principles|ljkelly3141|logankelly|/Users/|uwrf|river falls|real-world-statistics|kellyecon|My_Books|Teaching/' R/ inst/ tests/ man/ NAMESPACE README.md NEWS.md CONTRIBUTING.md` returns nothing except the lines decision D9 allows.
- [ ] `DESCRIPTION` `Authors@R` carries the name and the email Logan chooses (D8); nothing else in `DESCRIPTION` names a course or a path.
- [ ] `LICENSE` and `LICENSE.md` agree: MIT, 2026, Logan Kelly.
- [ ] `grep -rn 'Sys.getenv' R/` returns nothing. `grep -rnE '~/|/Users/|/home/' R/` returns nothing.
- [ ] `tests/testthat/fixtures/` contains no file copied from either course; the T04 grep passes.
- [ ] `inst/skills/` passes the T22 grep.
- [ ] `inst/templates/` passes the same grep.
- [ ] `project/` decision D10 applied: either the design record stays public as-is (it names Logan's directory layout and course facts; no secrets, verified by 1e) with one README line saying what it is, or it moves.

**Secrets and history**

- [ ] `git log -p --all | grep -cE '[0-9]{4,5}~[A-Za-z0-9]{40,}|Bearer |CANVAS_API_TOKEN'` is 0.
- [ ] `git log -p --all | grep -c '/Users/logankelly'` is 0 outside `project/` (the spec documents carry absolute paths by design; D10).
- [ ] No `.Renviron`, `.httr-oauth`, or credential file in any commit: `git log --all --name-only | grep -iE 'renviron|oauth|token|secret'` is empty.
- [ ] Three commits examined by hand before the flip; none rewritten.

**Package**

- [ ] `R CMD check --as-cran` on a machine without Node or Chrome: 0 errors, 0 warnings; pa11y tests report as skipped, not passed.
- [ ] `devtools::test()` on Logan's machine: T19 runs for real and passes.
- [ ] Every exported function has a roxygen page with an example that runs in `tempdir()`.
- [ ] `SystemRequirements` and the README's requirements table say the same thing.
- [ ] `.Rbuildignore` excludes `project/`, `.claude/`, `.github/`, `tools/`.

**Documentation for a stranger**

- [ ] README quick start followed on a clean machine by someone who is not Logan, or by Logan pretending, from `remotes::install_github()` to an imported scaffold.
- [ ] README status table marks each entry point verified or unverified by a real Canvas import, with the date.
- [ ] CONTRIBUTING states the arrival rule, the gate rule, the no-course-content rule, and the two courses rule in the package's own words.
- [ ] NEWS lists `body_for()`'s remaining course prose and the answer-key heading convention as known limitations.
- [ ] Repository description, topics, and default branch set; issues enabled or not (Logan).

**Skills**

- [ ] Every command in every `inst/skills/*/SKILL.md` names a function or target that exists in this version.
- [ ] `install_skills()` into an empty tempdir and diff against `inst/skills/`: identical apart from the version line.

---

## 11. Risks to the live courses

### ECON 730, live to students as of today

| Risk | Where it comes from | Guard |
|---|---|---|
| A half-repointed Makefile breaks `make coursepack` or `make mockup` for another session sharing the checkout | T13, T14 | each recipe changes in the same sitting as its function lands; the deletion list is shown and approved before anything is removed |
| The gate baseline is frozen before announcements land, then fails when they are added, and someone regenerates it | T05 | T05's precondition; the expected tree is regenerated only in T11 and only in a commit that says the cartridge was supposed to change |
| The timezone helper differs from the fixed offset by one hour on some date | T03, T10 | equality asserted for every live date before wiring; DST boundary tests |
| The next cartridge from source carries one assignment group while Canvas has two; an import into the live course would not remove the second, but the reference diff will complain | 1b | T11; until then the divergence is declared, not fixed by editing Canvas |
| `due_at` seconds differ from what Canvas holds after hand edits; a round-trip diff reports 17 false divergences | 1b | D6; declare, do not "fix" |
| Announcement bodies are gitignored; a build in a worktree or fresh clone stops on missing bodies | 1a | D5; the builder's hard stop names the file, so the failure is loud |
| `make clean` in ECON 730 removes `docs/`, the published site | Makefile | no task runs it; the scaffold's `clean` does not touch `docs/` |
| A test or tool writes into `docs/` | any | no package function takes `docs/` as an output; T13 keeps the preview under `build/` |
| The a11y real-run diff is run from a worktree path and reports everything fixed and new | T20 | run from the primary checkout only; stated in T20 |
| A leaked `python3 -m http.server` on 8766 blocks the next audit | T18, T20 | `port_is_free()` refuses; `lsof -i :8766` is the recovery |
| Stale package install builds with old code | every task after T02 | every entry point prints its version; bump on every behaviour change |
| Uncommitted edits to `modules.yml` (the date corrections) are on disk now; a fixture freeze or a gate baseline taken today captures them uncommitted | T05 | T05 waits; the baseline commit records the ECON 730 `HEAD` it was taken at |

### ECON 202, live, UPDATE ONLY

Nothing in this plan writes to `macro_principles`. The spec's Task 13 is
withdrawn pending T30. Specific risks:

| Risk | Guard |
|---|---|
| A package function is "tried" against ECON 202 and writes under `build/` or `project/` there | no task names that repo as a `proj`; T30 is a memo |
| Values from ECON 202's `course.yml` (its dates, its group ids, its site URL) reach a template or fixture | T04 and T26 greps include `macro_principles`, `econ ?202`; the scaffold's `term:` block is the shape, empty of values |
| The Python builder and the R package diverge further while T30 waits | recorded as a cost in section 12; not a package task |
| `audit_course()` pointed at ECON 202 cannot see the root-level export | `CARTRIDGE_SEARCH_DIRS` becomes an argument (T17), so the caller says where; no default is added for that repo |

---

## 12. Honest costs

**The accessibility subsystem makes the package heavier in every dimension
and the plan does not pretend otherwise.** Node.js, `npx`, and a Chrome for
Testing download become requirements for one entry point out of six;
`python3` is a requirement for two. `R CMD check` on a clean machine cannot
exercise the serve-and-audit path, so the package's largest test file has
its most important test skipping in the environment most people check
packages in, and CI proves the audit works only if a second job installs a
browser. Porting 3,106 lines of assertions is the single largest piece of
work in the plan and produces no user-visible change. Two subsystems that
share nothing but a namespace now share a version number, a `DESCRIPTION`,
and a release cadence. The surface-identity problem (a course's audit
history is keyed to its directory basename, spec 1i) becomes every user's
problem on day one, because every user's first clone path is their identity.
None of this is a reason not to do it; it is the price, and it is paid
whether or not anyone runs the audit.

**`init_course()` is easy to build and hard to make honest.** A scaffold that
produces an importable empty course is a day's work. A scaffold whose README,
`CLAUDE.md`, and skill copies teach the containment rules well enough that a
stranger does not put an answer key under `assets/` is documentation, and
documentation is where this project's own record shows claims drift from
what the code does. The plan compensates with greps and a human import, not
with confidence.

**Going public costs evidence.** The four skills are credible because they
name the incidents that shaped them: the seventeen wrong Fridays, the
collapsed quiz idents, the day pa11y ran one engine. Scrubbing course names
from those narratives makes the skills less specific, and specificity is
what the house style says makes a skill useful. Decision D9 is where Logan
chooses how much to keep. The design record in `project/` names his
directory layout and will be readable by anyone.

**Copied skills drift.** A version line and an overwrite flag are the whole
mitigation. Someone will edit a project copy and lose the edit on the next
`install_skills(overwrite = TRUE)`.

**Two builders exist and this plan leaves both standing.** ECON 202's Python
toolchain has a working "start from an export" path, dated measurements, and
a verified import; the R package has generated bodies, quiz inlining, and a
verified round trip. Until T30 is decided, "the package builds both courses"
is not true and the README must not say it. The extraction path a stranger
would most want (export first, edit second) is the one this pass does not
build.

**The byte gate that ships is weaker than the one the spec designed.** A
synthetic course cannot reach a path only the real course's 38 bodies, 17
assignments, and 7 quizzes reach. The real gate exists but is private, so a
public contributor cannot run it and a green CI on the public repo does not
mean ECON 730 still builds. That is stated in CONTRIBUTING rather than
hidden.

---

## 13. Decisions collected, all Logan's

Spec decisions 1a to 1i still stand where not superseded here.

| # | Decision | Blocks | Recommendation, marked as such |
|---|---|---|---|
| D1 | The cartridge filename: `slug:` in `course.yml`, defaulting to the slugified `canvas.course_code` (spec 1a) | T10, T24 | add `slug: econ-730` to ECON 730's `course.yml` so the current filename is preserved exactly |
| D2 | Whether the Fall 2025 export stays a structure gate (spec 1b, 1c) | T08, T09 | retire it as a structure gate, keep it as the format gate; the course was redesigned on purpose and the diff has reported that for two weeks |
| D3 | `textbook_docs: none` (spec 1h) | T08, T13, T24 | accept the spec's recommendation; the scaffold writes `none` |
| D4 | Where the timezone lives: `term.timezone` (ECON 202's shape) or top-level | T03, T08, T24 | `term:` as a block, because the schedule skill's open item and ECON 202 both want `first_day`, `last_day`, `breaks` in one place; ECON 730's scalar `term: TBD` becomes a block |
| D5 | Where announcement bodies live for ECON 730: stay under gitignored `semester/`, or move to `content/announcements/` | T10, T24 | move, so a clone builds; if they stay, the README of `semester/` says a clone cannot build the cartridge |
| D6 | `due_at` seconds: keep `T04:59:00` or emit `:59` to match what Canvas writes for 11:59 PM | T10, T11 | emit what Canvas writes; declare the change and regenerate the gate in T11's commit |
| D7 | Whether the real-course gate baseline is committed in ECON 730 `project/coursepack-gate/` or kept under gitignored `build/` | T05 | commit it; a baseline that vanishes with `make clean` protects nothing |
| D8 | Which email in `DESCRIPTION`, and whether the package name stays `coursepack` on public GitHub | T29 | not mine to recommend |
| D9 | How much course-specific narrative stays in the shipped skills: named, anonymized, or removed | T22, T26 | anonymize ("a seven-week course", "seventeen dates") and keep the incidents; the lesson survives, the name does not |
| D10 | Whether `project/` stays public as the design record | T29 | keep it; it is the most honest documentation the package has, and it holds no secrets |
| D11 | Whether CONTRIBUTING accepts outside contributions at all, or the repo is public for reading and installing only | T27, T29 | not mine to recommend |
| D12 | Whether CI runs the browser job | T28 | yes, as an optional job that may fail without blocking, because a red optional job is more information than no job |
| D13 | The ECON 202 direction | T30 and everything after it | the memo's job, not this table's |
| D14 | Whether a `new-course` skill ships alongside `init_course()` | T22 | yes; it is the entry point a Claude Code user will actually type |

---

## 14. Things this plan could not verify

Stated so nobody treats them as checked.

- **How Claude Code discovers skills** beyond what section 6 measured. The
  plugin manifest format, whether `~/.claude/skills/` is read, and whether a
  package could register skills without a copy step were not verified,
  because verifying them means reading outside the three permitted paths.
- **The announcement code's actual schema.** It is being written now and is
  not on disk. Section 7 is the contract from the export; the YAML shape is
  a sketch.
- **What the ECON 202 round trip proved.** `build/principles-of-macroeconomics-export.imscc`
  exists; whether its field-by-field comparison was clean was not read.
- **Whether `assignment_defaults.group: Homework` is reached by any code
  path today.** Line 228 reads `[[1]]`; the `group:` key may be dead. T08's
  check will say.
- **The a11y findings count's jump** from 9,864 (08-13) to 41,902 (09-01).
  Not investigated; the number is recorded as the baseline for T20 and the
  jump is a question for whoever runs it.
- **`python3` availability on a stranger's machine**, and whether an R-only
  server (`servr`, `httpuv`) should replace it. Not decided; adding a
  dependency to remove another is the kind of thing the house rule against
  over-engineering says to ask about first.
