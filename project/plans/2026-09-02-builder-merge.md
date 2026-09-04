# Builder merge: one cartridge builder, three tools

Written 2026-09-02 against the three repositories as they were on disk that
afternoon. Status: proposed. Documents only. No code was written, moved, or
deleted while producing this; no build was run; nothing was committed. No task
below starts without Logan's approval for that task, and nothing is committed
without his permission for that specific commit.

This plan is a dependency of the cartridge lane of
`project/plans/2026-09-02-portable-coursepack.md` (the sibling plan). It refers
to that plan's tasks by number (T01 to T30) and its decisions by letter (D1 to
D14) rather than restating them. Where the two disagree, section 11 says so.
It also reconciles `macro_principles/specs/TOOLCHAIN-REVIEW-2026-09-02.md`
(the review), an independent read-only review of the Python toolchain dated
today, whose findings are unfixed by design; section 5 gives each one a
disposition here.

Reading order for whoever executes this: the ECON 730 `CLAUDE.md`, then
`migration-spec.md`, then the sibling plan, then
`macro_principles/specs/CARTRIDGE_MECHANICS.md` sections 3, 4, 5b, 10 and 11,
then the review, then this document.

Two boundaries that this plan was written under and that any execution of it
inherits. The review opens by recording that Logan asked for a review and his
course was edited instead; that is the failure mode every task here is shaped
to avoid. Nothing in this plan writes to `macro_principles` except the tasks
in section 6 explicitly labelled as ECON 202 sessions, each of which is a
proposal for Logan to run or refuse, not something a package task does on its
way past. And the two courses share the toolchain and nothing else: no value
from either course's YAML reaches package code, a template, or a fixture.

---

## 0. What changed while this was being written

The brief described two builders to reconcile, one per course, and framed the
merge as one builder with two source modes, `generate` for ECON 730 and
`carry-through` for ECON 202. Two corrections arrived mid-task and both are
right; the plan is built on the corrected picture.

**Carry-through is per item, not per course.** ECON 202 is authored as plain
text exactly as ECON 730 is: `course.yml`, a 2,007-line `modules.yml`,
`pages/`, `questions/`, `notes/`, `data/`, `semester.yml`, its own
`_quarto.yml`, all present on disk. What it carries through from a source
cartridge is three specific classes of item that have no regenerable source
today: 14 "End of Module N" wiki pages, its Classic quizzes, and its
assignments. Section 2 re-derives this from the code.

**There are three tools, not two.** `extract_cartridge_manifest.py` (219
lines) reads a real Canvas export and writes `course.yml` and `modules.yml`
from it. Logan has named it as a capability he values and wants kept. It is
the bootstrap for a stranger and the thing that makes a round trip testable
without Canvas. Section 3.7 designs its port; section 8 uses it.

The review was also unknown when the brief was written. It is the best
evidence available about the Python toolchain's current defects, and several
of its findings change what "port this faithfully" means: a faithful port of
`apply_exam_pools()` would reproduce a confirmed structural defect.

---

## 1. Measured today

Every number is `wc -l`, `grep -c`, `git`, `unzip`, or a `yaml` parse run on
2026-09-02. Where a number differs from the sibling plan or the brief, the
reason is given.

### 1a. The three tools

| Tool | File | Lines | Hard failures | Soft failures | Functions |
|---|---|---:|---:|---:|---|
| R builder, working tree | `managerial_statistics/scripts/build_cartridge.R` | 1,274 | 31 `stop()` lines, plus 2 `quit(status = 1)` | none: every problem the pre-zip scan finds fails the build | `gid`, `xesc`, `xtext`, `oneline`, `slugify`, `writef`, `url_for`, `quiz_body`, `body_for`, `ann_when`, `p_fail`, `xread`, `xt` |
| R builder, committed `HEAD` (`5515ece`) | same path | 927 | 16 | | |
| Python builder | `macro_principles/scripts/build_cartridge.py` | 761 | 2 `sys.exit` (missing PyYAML; usage), 0 `raise` | 14 `warnings.append` sites, all printed and none fatal | `gid`, `load_yaml`, `wiki_html`, `source_resources`, `apply_due_dates`, `fix_accessibility`, `apply_exam_pools`, `check_stale_measurements`, `sync_carried_titles`, `build` |
| Extractor | `macro_principles/scripts/extract_cartridge_manifest.py` | 219 | 1 `sys.exit` (usage) | prints counts | `text`, `yaml_str`, `load_manifest_resources`, `load_wiki_pages`, `extract` |

**The R builder on disk is 347 lines longer than its last commit.** `git
status` in ECON 730 shows `scripts/build_cartridge.R` modified (+351, minus 4
per `git diff --stat`), `modules.yml` modified, `announcements.yml`
untracked, plus `content/pages/syllabus.qmd`, `welcome.qmd`, and five files
under `docs/`. The uncommitted 347 lines are the announcement section, the
course card, and the pre-zip checks for both. The brief's "31 `stop()`
calls" describes the working tree; the sibling plan's "927 lines" describes
`HEAD`. Both are true. This plan treats the working tree as the builder,
because that is what will be committed, and it inherits the sibling plan's
T05 precondition that the announcement work land first.

**The Python builder is committed.** `git status` in `macro_principles` shows
only `specs/TOOLCHAIN-REVIEW-2026-09-02.md` untracked. Its last change was
`6d246ed` (2026-09-01, "make modules.yml own item titles"); `0e9d5e7`
(2026-09-02, "Thin the deadlines") touched only the two YAML files. The review
records that two edits to it were made and reverted today; the file
checksum-matches `HEAD`.

**Python imports.** `hashlib`, `re`, `shutil`, `sys`, `tempfile`, `zipfile`,
`pathlib`, `xml.sax.saxutils`, and inline `datetime` and `html`: all standard
library. `yaml` (PyYAML) is imported in a `try` and its absence is a
`sys.exit`. There is no other third-party dependency. The brief's claim is
verified.

### 1b. What each builder reads

The two builders read two different `modules.yml` schemas. This is the
largest fact in the merge and neither the brief nor the sibling plan's
section 1c puts a number on it.

**R schema** (ECON 730, 775 lines): a `modules:` tree whose items are one of
five keyed forms (`header:`, `page:`, `link:`, `assignment:`, `quiz:`) with
optional `indent:` and `new_tab:`; separate `pages:` (keyed by `slug`, body
form `iframe:` with `width`, `height`, `video`, optional `iframe_title`, or
`body: true`), `assignments:` (`id`, `title`, `published`, `due`, `group`,
`points`, one of `homework:`, `quiz_file:`, `todo:`), and `quizzes:` (`id`,
`title`, `qti`, `published`) blocks. Positions are implicit in order. Every
identifier is derived by `gid()`.

**Python schema** (ECON 202, 2,007 lines, down 30 from the sibling plan's
2,037 after today's `0e9d5e7`): a single `modules:` tree, 17 modules, each
with `title`, `module_id`, `position`, `published`,
`require_sequential_progress`; 189 items, each with `title`, `type`,
`position`, `indent`, `published`, `item_id`, `resource_id`, and for wiki
pages `page`, `url`, `height`, `height_measured`. Item types: 148
`WikiPage`, 34 `Quizzes::Quiz`, 7 `Assignment`. 134 items carry `url`,
`height` and `height_measured` (all three always together). 14 carry
`carry_through: true`, and those 14 are exactly the "End of Module 1"
through "End of Module 14" pages. 0 carry `source_ref`, although the
extractor writes that key for quizzes and assignments and the builder never
reads it (`grep -c source_ref build_cartridge.py` is 0). 2 items are
unpublished: the Midterm Exam and the Final Exam. 14 modules require
sequential progress. Every module's item positions are 1..n in file order.
The file's 12 comment lines are all in its header; 0 follow `modules:`.

**ECON 202's `course.yml`** carries `title`, `course_code`, `urls.site`
(which ends in `/pages`, derived by the extractor as the longest common
prefix of all iframe targets), a `term:` block with `timezone:
America/Chicago`, `due_time: "23:59:59"`, a `due_dates:` map of 41 entries
keyed by item title (34 quizzes and exams, 7 activity reflections; one, the
Final Exam, carries a clock time), an `exam_pools:` block for two exams, a
`canvas:` block of seven keys, and five `assignment_groups:` of which four
carry their original Canvas `id:` and one, Position Memos, does not.

### 1c. The exports and builds on disk

| File | Date | What it is | Modules / items / types |
|---|---|---|---|
| `managerial_statistics/reference/managerial-statistics-fall-2025-export.imscc` | 2026-08-12 | ECON 730's reference export, THE spec for the R builder | 9 / 72: 10 Assignment, 24 subheader, 32 ExternalUrl, 6 WikiPage; also 2 `imsbasiclti_xmlv1p0` resources, `context.xml`, `web_resources/` with the card and `udoit.json` |
| `managerial_statistics/build/coursepack/managerial-statistics-export.imscc` | 2026-09-02 13:10 | ECON 730's round-trip export after import and hand edits | 11 / 74: 17 Assignment, 8 subheader, 5 ExternalUrl, 44 WikiPage; 7 `imsdt_xmlv1p1` announcements, 3 `imsbasiclti`, 2 assignment groups |
| `macro_principles/econ202-export.imscc` | 2026-01-26 | ECON 202's source export: both the reference and the carry-through source | 17 / 193: 149 WikiPage, 36 Quizzes::Quiz, 8 Assignment; 330 files; 37 `non_cc_assessments` files (36 quizzes plus one `<objectbank>`); `files_meta.xml` declaring a hidden "Uploaded Media" folder; a 6.8 MB thumbnail |
| `macro_principles/build/econ202-fall2026-v8.imscc` | 2026-09-01 21:32 | Python build | 17 / 193, 280 files, 36 quizzes |
| `macro_principles/build/econ202-fall2026-v9.imscc`, `v10.imscc` | 2026-09-02 14:25, 14:31 | Python builds after today's YAML thinning | v10: 148 wiki pages; carries `files_meta.xml` and `media_tracks.xml` from the source |
| `macro_principles/build/principles-of-macroeconomics-export.imscc` | 2026-09-01 11:45 | the round trip of the FAILED first import (the missing-marker case in mechanics 5a) | 157 `Attachment`, 0 WikiPage, 36 quizzes |

There is no export on disk of a successful ECON 202 import. The commit "Fix
the cartridge import: pages were arriving as file attachments" (`58cd1d6`)
records the fix; whether v8, v9, or v10 was imported into a shell afterwards
and what came back is not on disk. Section 13.

### 1d. The `new_tab` and `identifierref` shapes, from both real exports

| Export | Content type | `new_tab` | `url` | `identifierref` |
|---|---|---|---|---|
| ECON 730 reference | ExternalUrl (32) | `false` (26), `true` (6) | present | present |
| | WikiPage (6), subheader (24) | `false` | absent | present / absent |
| | Assignment (10) | `false` (8), `<new_tab/>` (2) | absent | present |
| ECON 202 | WikiPage (149), Quizzes::Quiz (36), Assignment (8) | `<new_tab/>` | absent | present |

Canvas writes both `<new_tab>false</new_tab>` and `<new_tab/>` for the same
content types, so both are accepted. The R builder emits `false` (and empty
for quizzes, matching the ECON 202 export's quizzes); the Python builder
emits `<new_tab/>` for everything, including its untested ExternalUrl path.

### 1e. Identifier derivation differs

R: `gid(...)` is `md5` of the arguments pasted with no separator. Python:
`md5` of the arguments joined with `::`. For the same key the two produce
different ids. ECON 730's ids are all derived, so the R convention is pinned
by the byte gate. ECON 202's module, item, and resource ids are all carried
from its export in YAML, so derivation only reaches four ids there: the
manifest identifier, the course identifier, the course-settings resource id,
and the Position Memos assignment group, `g65ad0ae65cbfc6dd049ab3d136be2e0d`
under the Python convention. Only the last is load-bearing across an import,
because Canvas matches an assignment group on that identifier when a
cartridge is re-imported. Section 6, M15, pins it.

---

## 2. The framing, re-derived from the code

The brief's "one builder, two source modes" does not survive contact with
`build_cartridge.py`. Its `build()` loop dispatches per item:

- `ExternalUrl` with a `url`: generate a four-line weblink.
- `WikiPage` with a `url` and no `carry_through`: generate an iframe wrapper
  page from the template.
- everything else with a `resource_id`: carry through, by walking
  `<dependency>` edges from that resource in the source manifest, copying
  every declared file byte for byte and re-emitting the source's `<resource>`
  XML verbatim.

So the 14 marked pages are carried because they are marked, and the 34
quizzes and 7 assignments are carried because they are not weblinks or
iframe pages. The `carry_through` marker is explicit for one class and
implicit for two. One build, one staging tree, one manifest, generated and
carried resources side by side. There is no course-level switch anywhere.

The R builder has five generated item forms and no source cartridge. Nothing
in it is a "mode" either.

**What the code needs, then:** one builder; each item has one of three
fates, generate, carry, or drop; an optional source cartridge supplies the
bytes for carried items; and the fate is declared per item in `modules.yml`.
A course with no carried items never names a source. A course with carried
items names one, and the build stops if any carried item's resource is not in
it. ECON 730 has no carried item today; the mechanism would be the right one
the moment it does. Its own 09-02 round-trip export already carries three
`imsbasiclti` resources and a hand-made second assignment group that the
generator never emits. Whether either is wanted is Logan's call; the point is
only that "no regenerable source" is not a property of ECON 202.

"Drop" is what neither builder emits and the mechanics document lists:
`context.xml`, `web_resources/` (with the course card as the R builder's
deliberate, size-justified exception), the source's `files_meta.xml` and
`media_tracks.xml` (see E4), the `<objectbank>` no item references, and
anything under `assessments/`.

The rest of this document uses "generated" and "carried" as adjectives on
items and resources, never on courses.

---

## 3. The design

### 3.1 Signature

```r
build_cartridge(proj = ".")
```

The same signature the spec's Task 8 already fixes. No `source` argument, no
`mode` argument, no `date` argument (spec 2f rejected a date parameter for
the gate's sake). Everything else is read from the course's YAML under
`proj`, in keeping with the arrival rule: course facts live in YAML, defaults
are function arguments only where they are not one course's facts.

Reads: `course.yml`, `modules.yml`, `announcements.yml` (optional),
`reference.yml` (optional; see 3.4 for the `source:` key), `content/canvas/`
for `body: true` pages, the rendered textbook for `homework:` assignments,
`assets/images/course-tile.png` if present, QTI zips named by `quizzes:`
entries, and the source cartridge named by `reference.yml` if any item is
carried.

Writes: `build/coursepack/staging/` (purged every run) and
`build/coursepack/<slug>-<date>.imscc` (D1). Nothing else. Never `docs/`.

### 3.2 The one schema

The R schema is the package's schema. Reasons, in order of weight: the R
builder's output is the one with a recorded field-by-field Canvas round trip
(ECON 730 `log/verified.md`, 2026-08-12, 0 of 73 items lost); the R schema
already separates definitions (`pages:`, `assignments:`, `quizzes:`) from the
module tree, which is where a per-item fate belongs; and the byte gate that
protects the live ECON 730 course pins the R schema's output, so changing it
would mean regenerating the gate to pass. The Python schema is converted
(section 3.8), not supported alongside. Two dialects in one reader was
considered and rejected: it is the cheaper first step and the more expensive
permanent state, and the conversion is mechanical because the Python schema is
a strict subset in information content.

The schema gains these keys. Each is additive; a course that omits all of
them builds exactly as today, which is what keeps the ECON 730 gate green
through the schema change.

| Where | Key | Meaning | Origin |
|---|---|---|---|
| `reference.yml` | `source:` | path to the cartridge carried resources are read from; defaults to `export:` when absent | new; the Python builder's third positional argument |
| `pages:`, `assignments:`, `quizzes:` entries | `source_ref: g<hex>` | this definition is carried: its bytes are the named resource in `source:` plus that resource's dependency closure; no other body key may be present | the extractor's own key, which the Python builder never read; replaces `carry_through: true` |
| `pages:`, `assignments:`, `quizzes:` entries | `resource_id: g<hex>` | override the derived resource id, so an extracted course reproduces its export exactly; defaults to `source_ref` when that is present, else `gid()` | Python `resource_id` |
| module items | `item_id: g<hex>` | override the derived item id | Python `item_id` |
| modules | `module_id: g<hex>` | override the derived module id | Python `module_id` |
| module items (any form) | `published:` | item-level workflow state; defaults to `true` for header, page and link items and to the definition's `published` for assignments and quizzes, which is today's behaviour | Python per-item `published`; ECON 202's two unpublished exams need it |
| `pages:` entries with `iframe:` | `height_measured:` | ISO timestamp of when `height` was measured | Python; mechanics 5b |
| `assignments:` and `quizzes:` entries | `due:` | already exists for assignments as a date; extended to accept `YYYY-MM-DD HH:MM[:SS]`, the same three forms `announcements.yml` accepts for `post:`; on a carried definition it rewrites the carried `due_at`; absent on a carried definition, the carried `due_at` is blanked, never inherited | R `due`; Python `due_dates` map and the blank-never-inherit rule |
| `course.yml` | `due_time:` | the clock time a bare `due:` date means; no package default (see D6 and E1) | Python |
| `course.yml` `assignment_groups:` entries | `id:` | override the derived group id | Python; load-bearing for ECON 202's four existing groups |
| `course.yml` `canvas:` | `allow_student_wiki_edits`, `restrict_student_future_view`, `restrict_student_past_view` | added to the known-key list; an unknown key under `canvas:` is a hard stop naming it, never silently dropped (review 12) | Python and the extractor |
| `course.yml` | `exam_pools:` | see section 4, row "exam pools"; keyed by quiz definition id, not title | Python, reshaped |

Positions stay implicit. ECON 202's positions are 1..n in file order in
every module and 1..17 across modules, measured, so nothing is lost; the
converter asserts this before writing and stops if it ever fails.

### 3.3 What each fate reads and writes

**Generate**, unchanged from the R builder: header, weblink, iframe page,
`body: true` page, assignment with `homework:` or `quiz_file:` or `todo:`,
quiz from an R/exams QTI zip, announcement, course card, course settings,
groups, grading standard and late policy (optional after M04), manifest.

**Carry**, new, ported from `source_resources()` and the else branch of
`build()`: for each definition with `source_ref`, walk the source manifest
from that resource across `<dependency>` edges, copy each declared file's
bytes into staging unchanged, and collect the source's `<resource>` elements
verbatim for the manifest. Then apply, in this order and only to carried
files, the declared rewrites: title sync (M08), due dates (M08),
accessibility repair (M09), exam pools (M11). Each rewrite reports a count.
The module item for a carried definition is emitted by the same code path as
a generated one: `content_type` from the definition kind, `identifierref`
from `resource_id`, `new_tab` per the R rules.

**Drop**: never staged. The pre-zip scan's "file on disk not declared" and
"orphan resource" checks are what make an accidental carry visible.

### 3.4 The source cartridge

`reference.yml` (introduced by T08) gains `source:`. For ECON 202 today
`source:` and `export:` are the same file, and that is the common case: the
export you diff against is the export you carry from. They are separate keys
because they can legitimately differ (a newer export taken after hand edits
in Canvas as the source, the original as the structural reference) and
because conflating "what I compare to" with "where bytes come from" is how
measurements get copied forward as if they were structure (mechanics 5b).

If any definition has `source_ref` and `reference.yml` has neither `source:`
nor `export:`, the build stops naming the definition. If `source:` is
declared and no definition uses it, the build prints "source declared, 0
resources carried" rather than stopping; a course may declare it ahead of
need.

### 3.5 Identifiers

`gid()` keeps the R concatenation exactly, because ECON 730's byte gate pins
it. Every derived id remains derivable; every carried or extracted id is an
override. The identifier model in the R builder's header comment (an
`ExternalUrl` carries two distinct ids and `module_meta` self-references)
moves with the code and now covers carried items too: a carried quiz's
`module_meta` idref and manifest idref are both its `resource_id`, which is
what the ECON 202 export shows for all 36.

### 3.6 Time

Every `due_at` and every `delayed_post_at` goes through the sibling plan's
T03 helper with the course's declared IANA zone. `dst_in_effect()` is not
ported; it is a hand-written US rule that the review (item 7) notes ignores
the `term.timezone` the same file carries. The R builder's fixed `UTC-5` and
its hard stop at 2026-11-01 go at the same time (T10). ECON 202's Final Exam,
due at 09:45 local on 2026-12-22, after daylight time ends, is the first
real date in either course on the far side of a boundary and is a required
test case for T03 (the helper must produce `2026-12-22T15:45:00`).

### 3.7 The third tool: `extract_manifest()`

```r
extract_manifest(imscc, out_dir, overwrite = FALSE)
```

Reads a Canvas export and writes, into `out_dir`, `course.yml`,
`modules.yml`, and `reference.yml` in the package's schema (3.2), and copies
the export into `<out_dir>/reference/`. Never overwrites an existing file:
the Python extractor writes `course.extracted.yml` beside an existing
`course.yml` because, its comment records, re-running it "has already
destroyed those edits twice"; the port keeps that rule for all three files.

What it recovers, per the Python original: course title and code; the
`canvas:` settings on the known-key list; assignment groups with their ids,
positions and weights; the module tree with every module and item identifier,
type, title, position, indent and workflow state; for each wiki page its
slug, title, and if it is an iframe wrapper its target and height. Every
item whose page is not an iframe wrapper, and every quiz and assignment,
becomes a `source_ref` definition. `height_measured` is deliberately NOT
written: an extracted height is exactly the undated, possibly ancient
measurement the stale check exists to flag, and the first build after
extraction should say so for every page.

Three review findings are fixed in the port rather than carried across:
item 9 (a page containing an iframe among other content is classified
generated and its other content silently discarded; the port classifies a
page as generated only when its body matches the wrapper template with
nothing else, and carries it otherwise), item 10 (the site URL is truncated
at the last `/`, not at an arbitrary character), and item 12 (the extractor
and the builder share one list of `canvas:` keys, so a setting the extractor
writes is a setting the builder emits).

**Verifying "nothing here is ECON 202 specific."** Read in full: the
extractor reads nothing from the course repo, only from the export; its
settings key list is Canvas's schema, not ECON 202's; the iframe regexes are
generic. The claim holds, with the caveat that the wrapper-shape assumption
(item 9) is an ECON 202 fact about how its pages were made and is what the
port removes. The Python builder's identical docstring claim does not hold;
section 4 lists its four course facts.

**Relation to `init_course()`.** The sibling plan's section 5 lists "start
from an existing Canvas export" as the thing `init_course()` deliberately
does not do, deferred to T30. The coordinator's reading is that
`init_course()` should have two paths and the export path is the more
valuable one. Tested against both files: the extractor produces the two
manifests and nothing else, while `init_course()` produces the containment
scaffold (`_quarto.yml` allowlist, the canary, `assessments/`, the Makefile,
the skills) and manifests with placeholder content. Neither subsumes the
other. The right composition is `init_course(..., from_export = NULL)`: the
scaffold is written as designed, then, when `from_export` names an `.imscc`,
`extract_manifest()` writes the three manifests in place of the template ones
and copies the export into `reference/`. A stranger with a Canvas course
gets a containment-correct repository whose structure is their own course.
This amends T25's signature and its "deliberately does not do" list, and it
supersedes T30's deferral of the extractor; section 11 lists the amendments.
The scaffold path stays: a stranger with no course yet still needs it.

**The honest limit.** Extraction recovers what the export contains and no
more. From the two real exports and the round-trip records on hand, what
falls in the gap:

- Anything Canvas does not export: the course name (round-trip verified: the
  shell keeps its own), enrollments, term dates, grades, module unlock
  dates and prerequisites (none in either export's `module_meta.xml`; not
  verified whether Canvas would export them if set).
- Anything Canvas exports lossily: the `title` attribute on iframes is
  stripped on round trip (mechanics section 5; the ECON 730 audit found the
  three that came back untitled), and an unrelated `allow` clause was
  dropped from one iframe (ECON 730 `CLAUDE.md`).
- The link from a resource back to its plain-text source. A `body: true`
  page comes back as Canvas HTML with no pointer to `content/canvas/`; a
  `homework:` assignment comes back as HTML with no chapter and anchor; a
  `quiz_file:` assignment likewise. All three become `source_ref`
  definitions after extraction. A course that already has sources and
  extracts its own export gets a manifest that is structurally exact and
  source-blind, which is the right result for a stranger and the wrong one
  for a course that authored the sources, and the tool cannot tell the two
  apart. The README has to say this.
- Measurements. Due dates, heights and group weights come back as they were
  and are stale by construction (mechanics 5b). The extractor writes dates
  and heights as found and the builder's stale checks are what say so.
- Things the extractor does not read though the export has them:
  announcements (`imsdt_xmlv1p1`, 7 in ECON 730's round trip), grading
  standards, late policy, assignment settings beyond what carry-through
  copies, LTI links. All are carried as bytes or dropped; none becomes YAML
  in this pass. E8.
- Whether Canvas exports rubrics, outcomes, or a syllabus body in a shape
  the extractor would lose: not determinable from these two exports, neither
  of which has any. Section 13.

### 3.8 Converting the Python schema

A one-off converter, run once per course by a human in that course's own
session, writes the R schema from the Python one. It is not a package
function that stays. For each ECON 202 module it emits `module_id`,
`sequential` from `require_sequential_progress`, and its items in order; for
each item a `pages:` / `assignments:` / `quizzes:` definition plus the
keyed item with `indent`, `item_id`, and `published`. Wiki pages with `url`
become `iframe:` definitions with `width: "100%"`, `height`,
`height_measured`, `resource_id`; marked pages and every quiz and assignment
become `source_ref` definitions; `due_dates[title]` becomes that definition's
`due:`; `due_time` moves to `course.yml` unchanged; `exam_pools` is re-keyed
by definition id. It asserts, before writing, that positions are sequential,
that titles are unique within their kind (review 16), and that every
`due_dates` key matched a definition (review 13), and stops otherwise. The
converted file loses ECON 202's 12 header comment lines unless the converter
copies the header block verbatim, which it does.

Cost, stated now because it is the one thing a reader of the two files will
notice first: the R schema is longer for a course like ECON 202. Each of its
134 iframe pages appears twice, as a definition and as an item, where the
Python schema inlines them. Estimate, not measured: the converted
`modules.yml` is roughly 2,600 lines against 2,007 today. That is the price
of one schema and it is stated rather than hidden.

---

## 4. Capability disposition

For each capability: does it become part of the merged function, an option,
or is it left behind; and whether ECON 730 needs it, which is the test for
"general" against "ECON 202 quirk". "Merged" means always on, with no switch.

### 4a. Python has, R does not

| Capability | Disposition | Reasoning, and the ECON 730 test |
|---|---|---|
| Carry-through from a source cartridge (`source_resources()`, the dependency walk, verbatim `<resource>` re-emission) | **Merged**, per item via `source_ref` | The load-bearing reason is QTI: a Canvas quiz's pools live in `non_cc_assessments/<id>.xml.qti`, declared by the meta resource, and regenerating the resource without it "silently converts a pooled quiz into a fixed one" (the docstring, and mechanics 10). Nothing about that is ECON 202's. ECON 730 has no carried item today and a mechanism the moment it does (section 2). |
| `sync_carried_titles()` | **Merged**, as part of carry; not optional | A carried quiz has two titles, the module item's and the object's own, and letting them diverge is what made the gradebook disagree with the module list on ECON 202. Any carried item on any course has this property. Port fixes review 18: rewrite both `<title>` elements in a quiz meta (the outer and the nested `<assignment>`'s), and escape and unescape consistently (review 4). |
| `apply_due_dates()` | **Merged** via `due:` on the definition; the title-keyed `due_dates` map is not supported | Blank-never-inherit is a correctness rule for any carried date (mechanics 5b, mechanism 1). Title keying is the quirk: it is what ECON 202 had because its carried items had no other handle in YAML. With definitions, the handle is the definition. Port fixes review 5 (`<due_at/>` is a due date of none and must be rewritten, not skipped), 4 (unescape), and 13 (a `due:` on a definition that produces no rewrite is a stop, not silence). |
| `dst_in_effect()` | **Left behind**, superseded by T03 | Hand-written US daylight-time rule. The R builder already does zone-correct arithmetic for announcements with `OlsonNames()`; T03 makes that the one helper. Review 7. |
| `fix_accessibility()`: `<th>` scope and leading bold-paragraph-to-heading, on carried content | **Option**, `repair_carried: true` by default, scoped to carried files only | The defects are real and Canvas's own checker reports them, but they are defects in bytes that have no source, which is why they are fixed on the way into the cartridge. Generated content is fixed at its source (ECON 730 closed 114 findings that way on 09-01). Scoping to carried files is not a nicety: unscoped, the table fixer would touch ECON 730's 38 generated `body: true` pages and break the byte gate. It is a switch because it is the one transform that changes carried bytes for a reason not declared in YAML, and a course reproducing its export exactly (mechanics 10, "reproduce before you generate") needs to turn it off. |
| `apply_exam_pools()`: inject groups, move groups between exams, rescale `selection_number` per chapter, rewrite the description and check it against the pool | **Split.** The pool arithmetic is **merged** as a carry transform driven by `exam_pools:` in `course.yml`. Three things inside it are ECON 202 facts and become required YAML instead of code: the group-title-to-chapter pattern (today `Ch\.?\s*(\d+)`, coupled to `build_qti_groups.py`'s output format and, per review 8, documented nowhere), the description template (today the literal "40 questions, randomly selected for each student" and "ONE ATTEMPT ONLY", review 6), and the chapter-list parsing of the description (replaced by generating the description from the pool and asserting the count). | Any course carrying pooled Classic quizzes and wanting pool composition declared in YAML rather than inherited from an old export needs the arithmetic; that is mechanics 5b's third mechanism and it is general. ECON 730 does not need it today and its R/exams quizzes have one group. Review 1 (insert new groups inside `root_section`, found by depth, never after it; CONFIRMED against v10, where 12 of the midterm's 52 groups sit outside) is **inherited from the upstream Python fix Logan authorized 2026-09-02**, not made here; see the review table. Port fixes 14 (count real insertions), 15 (no-op on a missing description is a stop), and 16 (key by definition id). This is the least general thing in the package and the hardest to fixture; see section 10 and E3, which offers leaving it in ECON 202 instead. |
| `check_stale_measurements()` | **Merged**, warning-level, fail-closed in its reporting | Mechanics 5b's second mechanism; general to any iframe page. ECON 730 has 2 site iframe pages (welcome, syllabus) with heights and no `height_measured`, so it would report 2 undated heights on the first run, which is true. Port fixes review 11: a page whose URL does not map under `docs/` is counted and printed as "unmappable", not silently exempt; a `url` with no `height` is a stop, not a silent `1000px`. The mapping rule: `urls.site` is the Pages root of `docs/` and the URL's tail maps under `docs/`; the two-try fallback that knows ECON 202 lays `docs/` out under `pages/` is not ported (E5). |
| The iframe wiki-page template (wrapper `div`, titled iframe, `style="border: 0"`, `allowfullscreen=""`, "Open in new tab" link) | **Merged** as the one template, parameterized by `width`, `height`, `title`, and the `video` allow-list the R builder already emits | Spec 1g and 12c already recommended adopting this shape because the titled, escapable frame is the accessible one. One template, no option: ECON 730's 8 iframe pages change shape once, deliberately, with an import (M05). The silent `"1000px"` default height is not ported. |
| Assignment group `id:` override | **Merged** | Needed by any extracted course; carried quizzes and assignments name their group by id inside their bytes and a regenerated id dangles every reference (ECON 202 `course.yml`'s own comment). Extends T11. |
| `canvas_export.txt` presence check and the manifest-header token check against the reference | **Merged** into the pre-zip scan, as stops | Mechanics 5a: without the marker Canvas files every page as an attachment and reports nothing. The R builder writes the marker and has never lacked it, so it has no check; a check costs nothing and the failure it catches cost three import passes. |
| Carrying `files_meta.xml` and `media_tracks.xml` from the source | **Decision E4** | ECON 202's export declares a hidden "Uploaded Media" folder in `files_meta.xml`; v10 carries it; mechanics 6 lists both files under "drop". Whether that folder declaration matters on import is unknown. Default in this plan: write the empty files the R builder writes, declare the difference in the equivalence gate, and let the import say. |
| The extractor | **Merged** as `extract_manifest()`, section 3.7 | Third tool. |
| `measure_iframe_heights.R` and `apply_iframe_heights.py` | **Left behind** in ECON 202, unchanged | Course tooling that writes measurements into `modules.yml`; the package reads `height_measured`, it does not produce it. The ECON 730 docs already flag an `iframe-heights` package candidate; not this pass. Review 17 (the two scripts fight over the file) is theirs to fix. |
| `build_qti_groups.py` | **Left behind** in ECON 202 | Its output is the file `exam_pools.inject` names. It is a question-bank generator, not cartridge toolchain; review 2 (duplicate answer ids) is its defect. It is also a Python dependency that survives at the course level for ECON 202 after this merge, stated plainly in section 9. |

### 4b. R has, Python does not

| Capability | Disposition | Reasoning |
|---|---|---|
| Embedded R/exams quizzes (`imsqti_xmlv1p2`, the three-file layout, the prefix identifier rewrite, the leftover-token and distinct-idents guards) | **Merged**, as the `qti:` body form of a quiz definition; `source_ref` is the other | Round-trip verified 2026-08-12 (20 of 20 questions back). A quiz definition has exactly one of `qti:` or `source_ref:`; a generated quiz and a carried quiz emit the same manifest shape. |
| Scheduled announcements (`imsdt_xmlv1p1`, `announcements.yml`) | **Merged** | Any course; not a module item; the sibling plan's section 7 contract. ECON 202 has none today and loses nothing. |
| Grading standard and late policy | **Merged, made optional** (spec 12b): absent keys mean the files are neither written nor declared, and `grading_standard_identifier_ref` is omitted | ECON 202's export has neither file and `grading_standard_enabled` false; unconditional emission is the ECON 730 shape-fact spec 12b names. No output change for ECON 730. |
| Course card in `web_resources/` | **Merged**, optional by file presence, as today | Already general: any course with `assets/images/course-tile.png`. The size argument in mechanics 6 is about a 6.8 MB thumbnail, not an 18 KB card. |
| The pre-zip scan: declared-versus-on-disk both directions, no `$IMS-CC-FILEBASE$` anywhere, no assessment source file, the answer-key canary as bytes, dangling and orphan references, well-formed XML, the announcement read-back | **Merged**, extended to carried resources | Carried resources add: every file a carried `<resource>` declares must exist in the source and be staged; carried resource ids must be unique across the manifest (review 16); every `assignment_group_identifierref` inside a carried file must name a declared group; an item whose `source_ref` is not in the source is a stop, not a warning (Python's "no source resource for" warning, which lets a cartridge ship with a missing item and prints one line). The Python builder's other fourteen warnings each become a stop or a printed count per the table in 4a. |
| `body: true` pages from `content/canvas/`, `homework:` and `quiz_file:` assignment bodies with the three answer-key guards | **Merged** | Sibling T07 and T10. ECON 202 does not use them and is not made to. |
| `{site}` and other `urls:` token interpolation | **Merged** | Already general. ECON 202's URLs are absolute and interpolate to themselves. |
| The `todo:` and `published: true` refusal | **Merged** | Already general. |
| Pinned zip entry mtimes and deterministic ids | **Merged** | Byte-reproducibility is what makes the gates work. Python's zip is not pinned (review does not note it; measured: `zipfile.ZipFile(..., ZIP_DEFLATED)` with no mtime handling), so two Python builds of the same input differ, which is one reason an ECON 202 byte gate cannot be built against v10. |

---

## 5. Reconciling the review

Nineteen findings, each with what this plan does about it. "Port-time fix"
means the R port does not reproduce the defect and a test asserts the fixed
behaviour on a synthetic fixture. Nothing in `macro_principles` is edited by
any of these; the Python builder keeps its defects until it is retired (E7).

| # | Finding | Status in the review | Here |
|---|---|---|---|
| 1 | Injected and moved groups land outside `root_section` | CONFIRMED | **INHERITED, not a port-time fix.** Logan authorized the fix in ECON 202's `build_cartridge.py` on 2026-09-02, upstream of this plan, after the same defect was found independently by two sessions with the same count. M11 ports a builder that already inserts by depth. Two caveats: the fix is authorized and in progress, not yet verified, and it is believed only once a depth count shows **0** groups outside `root_section` against a real export and a Canvas import confirms the pooled quizzes still draw. Until that lands, treat M11 as still carrying the fix. The equivalence gate against v10 still shows the 12 relocated groups as a declared, intended divergence, because v10 predates the fix. |
| 2 | Duplicate answer ids in `build_qti_groups.py` | CONFIRMED | not this plan's: that script stays in ECON 202; reported to Logan as an ECON 202 item |
| 3 | Subheaders get a fabricated `identifierref` | CLAIMED | does not arise: the R item emitter, verified against 24 real subheaders, is the one kept |
| 4 | XML-escaped titles break title-keyed lookups | CLAIMED | does not arise: lookups are keyed by definition id; where carried text is compared it is unescaped first (M08) |
| 5 | `<due_at/>` is skipped, so fresh courses never get dates | CLAIMED | port-time fix in M08; a synthetic carried assignment with `<due_at/>` gets its date |
| 6 | Hardcoded "40 questions ... ONE ATTEMPT ONLY" | CLAIMED | the description becomes a required template in `exam_pools:`, generated from the pool with the count asserted (M11) |
| 7 | Hardcoded US Central time | CLAIMED | T03 helper with the declared zone; `dst_in_effect()` not ported |
| 8 | Pooling requires "Ch. N" titles | CLAIMED | the pattern becomes required YAML under `exam_pools:`; a group title matching nothing is a stop (M11) |
| 9 | Extractor guts any page that is not a pure wrapper | CLAIMED | port-time fix in M12: generated only if the body is the wrapper and nothing else |
| 10 | Site URL can truncate mid-segment | CLAIMED | port-time fix in M12 |
| 11 | Stale-height check fails open; silent `1000px` | CLAIMED | port-time fix in M10 |
| 12 | Extracted settings not round-tripped | CLAIMED | one shared key list; unknown key is a stop (M04, M12) |
| 13 | Unused `due_dates` entries never reported | | a `due:` that rewrites nothing is a stop (M08); the converter refuses an unmatched map entry (M15) |
| 14 | `inject` counts success it did not achieve | | port-time fix in M11 |
| 15 | Description rewrite no-ops silently; regex replacement of user text | | port-time fix in M11; `fixed = TRUE` substitution |
| 16 | No uniqueness checks | | definition ids and slugs are unique by construction of the R schema (they are YAML map keys after `setNames`, and `check_manifests` T08 asserts it); carried resource ids checked in the pre-zip scan (M07); the converter asserts title uniqueness (M15) |
| 17 | The two height scripts fight over `modules.yml` | | ECON 202's; left behind, reported |
| 18 | `sync_carried_titles` renames only the first `<title>` | | port-time fix in M08; whether Canvas's gradebook reads the nested title is unverified (section 13), so both are rewritten |
| 19 | `source_resources` alternation bug on self-closing `<resource/>` | | port-time fix in M07: parse the manifest with `xml2` to find resource boundaries, then take the raw text span; a synthetic source with one self-closing resource is a fixture |

The review's "what it found to be correct" (the ExternalUrl double-id trap,
the dependency walk, the run order retitle then dates then pools, the
weight and marker guards) is kept as found, and the run order is the order
in 3.3.

---

## 6. Tasks

Each task is one sitting and one commit per repository touched. "Done when"
is evidence. M-numbers are this plan's; T-numbers are the sibling plan's
and are not restated. Tasks marked **ECON 730 session** touch only that
repo's `scripts/build_cartridge.R` and YAML; tasks marked **ECON 202
session** are proposals for a session Logan opens in that repo and are the
only things in this plan that write there; everything else is package work
under `coursepack/`.

### Lane A0: converge in the live script, before the freeze (ECON 730 session)

These change the R script in place while it is still the builder, so that
the T05 baseline captures a shape the merged builder will not need to change
again, and so that one Canvas import verifies all of them at once. Section 11
says why this ordering differs from the sibling's. Each output-changing task
says so; the batch ends with one import.

**M01. The announcement and card work lands.** Not this plan's to do; the
sibling's T05 precondition, restated because M02 to M06 edit the same file.
Done when: `git status` in ECON 730 shows `scripts/build_cartridge.R` and
`announcements.yml` committed and `build_cartridge.R` is 1,274 lines or
whatever that commit makes it.

**M02. `due_at` seconds and `due_time`.** D6 as recommended: a bare `due:`
means `due_time`, read from `course.yml`, with ECON 730's `course.yml` gaining
`due_time: "23:59:59"` so the emitted string becomes `T04:59:59`, which is
what both real exports show Canvas itself writes. `due:` accepts the three
forms of 3.2. Output changes on 17 assignments. Done when: the 17 `due_at`
values in a fresh build equal the 17 in the 09-02 round-trip export, character
for character; `refdiff` against that export no longer reports them. Must not
break: a `due:` after 2026-11-01 still stops until T10 replaces the offset.

**M03. Multiple assignment groups.** Spec 12a and the sibling's T11, done
here instead of after T10 (section 11). Emit every declared group; route each
assignment and each generated quiz by its `group:` or
`assignment_defaults$group`; stop on a name that matches no group; accept an
optional `id:` per group. ECON 730's `assignment_defaults.group: Homework`
names no group, so the build stops until Logan changes it to `Case Studies`;
that is a finding, not something this task edits silently. Output changes:
`assignment_groups.xml` gains the Quizzes group; the seven quiz assignments
reference it. Done when: the built `assignment_groups.xml` carries both
groups with the `course.yml` weights, and `refdiff` against the 09-02 round
trip reports the group only as Canvas's typo ("Module Quizes"). Must not
break: with one group declared, output is byte-identical to before.

**M04. Optional grading standard and late policy; known `canvas:` keys.**
Spec 12b. Absent keys, absent files, absent declarations, no
`grading_standard_identifier_ref`. The `canvas:` block is emitted from one
known-key list in the reference's element order; an unknown key stops the
build naming it. No output change for ECON 730. Done when: the build is
byte-identical to M03's; a synthetic `course.yml` without the two blocks
builds and its manifest declares six settings files, not eight.

**M05. The one iframe page template.** Spec 12c. The wrapper `div`, `style="border: 0"`,
`allowfullscreen=""`, the "Open in new tab" link, with `width`, `height`,
`title`, `loading="lazy"` and the `video` allow-list as parameters. Output
changes on ECON 730's 8 iframe pages. Done when: the 2 site pages and 6 video
pages render inside Canvas after the M06 import with no inner scrollbar
regression, and the a11y cartridge check still finds 0 untitled iframes.
Must not break: `body: true` pages are untouched.

**M06. Schema additions with no output change, then the import.**
`published:` on items, `item_id:`, `module_id:`, `resource_id:` overrides,
`height_measured:` on iframe pages, `source:` in `reference.yml` read and
reported (0 carried) but not yet acted on. Done when: the build is
byte-identical to M05's; each override, set on a synthetic course, appears in
the output. **Then Logan imports the M06 cartridge into a throwaway shell,
exports it, and compares field by field** per `skill/make-coursepack`. Not
done until that has happened. This is the import that verifies M02 to M05
together.

Then the sibling's **T05** freezes the baseline against this script, and
**T10** moves it. Nothing in this plan touches the builder between M06 and
T10.

### Lane C: carry-through, in the package (after T10)

**M07. Carry core.** `R/cartridge-carry.R`: read `reference.yml`'s `source:`,
open the cartridge, parse its manifest with `xml2` to locate every
`<resource>` (review 19), walk dependencies from each `source_ref`, stage
declared files as bytes, collect the raw `<resource>` spans for the manifest;
extend the pre-zip scan per 4b. Fixture: a synthetic source cartridge under
`tests/testthat/fixtures/` holding one carried page, one carried assignment,
and one carried quiz with a two-group pooled `non_cc_assessments` file and
an unreferenced `<objectbank>`, all invented content. Done when: the fixture
builds; the carried quiz's three files are byte-identical to the fixture's;
the objectbank is absent; a `source_ref` naming a resource not in the source
stops; the ECON 730 byte gate is untouched (no `source_ref` there). Must not
break: the gate.

**M08. Carried titles and dates.** Title sync on both `<title>` elements;
`due:` rewrites `due_at` and `all_day_date` in carried files through the T03
helper; absent `due:` blanks; `<due_at/>` handled; unescape before compare;
a `due:` that rewrites nothing stops. Done when: each case has a test on the
M07 fixture. Depends on T03.

**M09. `repair_carried_html()`.** Table scope and leading bold to heading,
carried files only, `repair_carried` option, counts printed. Done when: a
carried page with a scope-less `<th>` gains `scope`; a generated page with
the same table is untouched; with the option off nothing changes.

**M10. Stale-height check.** As in 4a. Done when: undated, stale, fresh,
and unmappable each produce their line on a fixture whose `docs/` is written
by the test with controlled mtimes; a `url` without `height` stops.

**M11. Exam pools.** As in 4a, keyed by definition id, `group_title_pattern`
and `description_template` required, groups inserted inside `root_section`.
Done when: on the M07 fixture, a `take_from` moves a group and the file still
ends with the two closing `</section>` tags a real export ends with; a draw
larger than a group's size stops; the description count equals the pool.
Independent of M08 to M10.

### Lane X: extraction (from T02; parallel with everything above)

**M12. `extract_manifest()`.** Section 3.7. Writes the R schema. Done when:
run on the M07 synthetic cartridge it writes three files that
`read_manifest()` parses; the wrapper-shape test classifies a page with extra
content as carried; the site URL of a synthetic export with pages under
`.../pages/ch01.html` is the directory, not `.../pages/ch`; nothing is
overwritten. Must not break: nothing consumes it yet.

**M13. The synthetic round trip.** Build the T04 minimal course; extract the
result; build the extracted course; diff the two staging trees. Done when:
the diff is empty apart from the declared set: `lomimscc:dateTime`, and the
`source_ref` definitions the extraction produced for the fixture's `body:
true` page and `quiz_file` assignment (which come back as carried bytes,
byte-identical to what went in). Depends on M07 and M12.

**M14. `init_course(from_export =)`.** The T25 amendment from 3.7. Done
when: `init_course(path, from_export = <M07 fixture>)` writes the scaffold
with the extracted manifests and the export under `reference/`, and
`build_cartridge()` on it reproduces the fixture's carried resources. Owned by
whoever executes T25; listed here so the dependency is visible.

### Lane E: ECON 202 (two sessions Logan opens there, last)

**M15. Convert and pin (ECON 202 session).** Run the 3.8 converter to write
`modules.yml` in the R schema; move `due_dates` into definitions; add `id:
g65ad0ae65cbfc6dd049ab3d136be2e0d` to Position Memos (1e); change `urls.site`
to the Pages root and add nothing else (E5); write `reference.yml` with
`export:` and `source:` both naming `econ202-export.imscc` (copied into
`reference/` per the onboarding memo); write the minimal `Makefile` the
onboarding memo's item 4 specifies. The Python builder and its YAML inputs
are not deleted in this task. Done when: `check_manifests()` passes; the
converter's assertions all held; `git status` there shows only the intended
files. **Equivalence gate:** `diff_against_reference()` (T09) pointed at
`build/econ202-fall2026-v10.imscc` as the reference reports only declared
divergences, and the declared list is written down before the run: the
`new_tab` form on 189 items; the manifest, course and settings-resource
identifiers; the `course_settings.xml` element set; `files_meta.xml` per E4;
the 12 exam groups relocated inside `root_section`; the second `<title>` in
34 quiz metas; the zip mtimes. Every carried file outside that list must be
byte-identical to v10's and every generated wiki page byte-identical to v10's.
A divergence not on the list is a bug in the port or a finding about v10;
stop.

**M16. Verify ECON 202 (ECON 202 session).** Two round trips, then an import:
(1) `extract_manifest("econ202-export.imscc")` into a scratch directory,
build it, `refdiff` against the export itself: only the thumbnail, the
objectbank, `context.xml`, and the template-versus-export page differences
may appear. (2) Build the converted course and **Logan imports it into a
throwaway shell, never the live course**, exports it, and compares field by
field; the iframe pages must render their content, the two exams must arrive
with 40 questions each and their pools intact, Position Memos must arrive as
one group. Done when: both, and a human has looked. Then E7 is decidable.

**M17. ECON 730's own extraction round trip.** Not a gate; a report.
`extract_manifest()` on `build/coursepack/managerial-statistics-export.imscc`,
build the result, diff against the 09-02 build. Expected to show every
`body: true` page and every assignment as carried bytes, the 3 `imsbasiclti`
resources, the typo'd group, the stripped iframe titles. Done when: the diff
is written into the ECON 730 session log as the record of what Canvas does
to a cartridge on the way back out. Depends on M12 and T10.

**M18. Documentation.** `NEWS` and the README status table (T27) gain rows
for carry, extract, and the three-fates rule; `inst/skills/make-coursepack`
(T22) gains the carry and extract sections; the sibling plan's section 12
sentence "two builders exist and this plan leaves both standing" is
corrected once M16 has happened and not before.

**M19. Paper version of any assignment (requested by Logan, 2026-09-04).** A
routine in the package that turns any assessment the builder can generate,
a quiz, an exam, or a written assignment, into a printable form: one fixed
draw from the same question pools under a seed, rendered through Quarto to
a Word document (and PDF) with the stems, tables, figures, and answer
choices inline, plus a separate answer key that names the item ids and the
seed, so a paper form can be re-created and graded against the same bank.
For written assignments it prints the description and submission
instructions. The first user is ECON 202's final, taken in the room through
Canvas on 2026-12-22 with a paper version available on request; the ECON 202
repo's `TODO.md` carries the same item as deferred there. Reads the R schema
after M15; before that it can read the Python generate blocks directly. Done
when: `print_assessment(course, item, seed)` produces a document a student
could sit, the key matches the document item for item, and a re-run with
the same seed is byte-identical apart from the date.

---

## 7. What blocks what

```
M01 ─ M02 ─ M03 ─ M04 ─ M05 ─ M06 ─ [import] ─ T05 ─ T10 ─┬─ M07 ─┬─ M08 (needs T03)
                                                          │       ├─ M09
T02 ─ M12 ─────────────────────────────────────────────────┤       ├─ M10
                                                          │       └─ M11
                                                          └─ M13 (needs M07 + M12) ─ M14 (needs T25)
M15 (needs M07..M11, M12, T08, T09, D4, E1..E6) ─ M16 (needs a Canvas shell) ─ E7
M17 (needs M12 + T10)
M18 (last)
```

For an operator running agents in parallel:

- **Day one, in parallel:** M12 (package, needs only T02) and M01 to M06
  (ECON 730 session, serial, one file). Nothing else can start.
- **M02 to M06 are serial and single-session** because they edit one live
  file in a checkout other sessions share. Never two agents in
  `scripts/build_cartridge.R` at once.
- **The import after M06 is a hard gate on everything in lanes C and E.**
  Freezing before it captures unverified output; converging after it
  regenerates the gate.
- **M08, M09, M10, M11 are independent of each other** and can run as four
  agents once M07 has landed; M08 additionally needs T03.
- **M15 waits on all of lane C, M12, and decisions E1 to E6.** It is the
  first time the package builds ECON 202 and it happens in that repo's own
  session with the update-only rule enforced by `git status`.
- **M16 needs a Canvas shell and Logan.** Nothing in this plan is verified
  until it has happened.

---

## 8. Test strategy

Both courses are live to students today. The merged builder is trusted for a
course only after it has reproduced that course's current cartridge and,
separately, after a cartridge it built has been imported and round-tripped.
A zip that builds proves nothing; ECON 730's `CLAUDE.md` and both builders'
closing lines say so and the reason is specific: Canvas discards malformed
cartridges and items without reporting an error, so the only observable
failure is an item that is not there. Five layers, each with what it proves
and what it cannot.

**1. The ECON 730 byte gate (T05, unchanged).** Frozen script against the
package, dates normalized, tree hashes equal. Proves the move changed
nothing on every path the fixture reaches. After M02 to M06 the frozen shape
is the converged one, so no later task regenerates it except by a deliberate
change with its own import. Proves nothing about Canvas.

**2. The ECON 202 equivalence gate (M15).** A byte gate is not available:
Python's zip is not mtime-pinned, its `gid()` differs, and its
`course_settings.xml` element set differs, so v10 cannot be reproduced
byte for byte without porting three things the merge deliberately does not
port. The gate is therefore `diff_against_reference()` against v10 with a
pre-declared divergence list, plus byte-identity asserted on every carried
file and every generated wiki page. Proves the port reproduces what the
Python builder built where it was right and differs only where section 5
says it was wrong. Proves nothing about Canvas, and v10's own import status
is unverified (section 13).

**3. The synthetic round trip (M13), and the real ones (M16 step 1, M17).**
Build, extract, build, diff. This is the gate the extractor unlocks and it
needs no Canvas. The synthetic form ships with the package and runs in CI;
it proves the three tools agree with each other about the schema and the
cartridge shape. The real forms use Canvas's own exports as input and cannot
ship (course content), but they prove something the synthetic one cannot:
that the extractor reads what Canvas writes, and they record exactly what
Canvas alters on the way back out (titles stripped, LTI resources added,
seconds changed, a group renamed by hand). It belongs in this section and it
is the strongest correctness check available without an import, with one
limit stated plainly: it proves extract and generate are inverses of each
other, not that either matches Canvas.

**4. Review-finding tests.** Every port-time fix in section 5 has a test on
the M07 synthetic source, and each test is written to fail against the
Python behaviour first (a group inserted after `root_section`, a skipped
`<due_at/>`, a page with extra body content classified generated). These are
the tests that would have caught the review's findings before an import.

**5. Canvas imports.** Four, all by Logan, all into throwaway shells:
after M06 (verifies M02 to M05 for ECON 730); after T10 (the sibling already
requires it); after M16 (the first package-built ECON 202 cartridge, never
into the live course); and the scaffold import T25 already requires. Each
followed by an export and a field-by-field comparison matching on title plus
content type and never on identifiers. This is the only layer that proves
Canvas accepts the output, and each entry in the README's status table names
the date of the import that verified it or says "unverified".

What no layer covers: whether Canvas walks groups outside `root_section`
(the fix makes the question moot for package output but v10 already shipped
with them, section 13), and the live courses themselves, which are never
re-imported by any task here.

---

## 9. Base language: decision record

**Date** 2026-09-02 | **Phase** generalization, preceding the cartridge
lane's T10.

**Context.** Two builders in two languages must become one function in the
`coursepack` package. The decision was taken before this plan; the plan's job
was to verify its reasons against the repositories rather than accept them.

**Options.** R (port the 761-line Python builder's capabilities into the
1,274-line R builder inside the package). Python (port the R builder into
Python and make `coursepack` a Python package). A hybrid or a `reticulate`
bridge, considered and rejected before this plan: two runtimes and two
dependency systems for a package strangers install from GitHub.

**Decision.** R.

**Why, each reason checked.**

- *The Python builder has no library lock-in.* Verified: standard library plus
  an optional PyYAML import (1a). Nothing in it is hard to express in R; its
  transforms are regular expressions over XML text, which port one for one,
  and its one structural operation, the dependency walk, is a loop over a
  parsed manifest.
- *Quiz generation is R-locked.* Verified for ECON 730's path:
  `scripts/build_qti.R` line 46 calls `exams::exams2canvas()`, whose output
  the R builder's prefix-rewrite is shaped around, and that path is
  round-trip verified. Partly false for ECON 202: its groups file is written
  by `build_qti_groups.py` from a JSON bank, in Python. That script stays in
  ECON 202 as course tooling (4a), so the lock holds for the package and not
  for that course, and ECON 202 keeps a Python dependency of its own after
  the merge.
- *The accessibility subsystem is R.* Verified: 7,037 lines across
  `audit_a11y.R`, six `lib/a11y_*.R` files and `test_a11y.R`, all R, moving
  in the sibling's lane B.
- *`coursepack` is an R package.* Verified: `DESCRIPTION`, `NAMESPACE`,
  `R/tile.R` with tests.
- A reason the brief did not give and that weighs more than any of the
  above: the R builder is the one with a recorded, field-by-field Canvas
  round trip and thirty-one fail-closed checks grown from real failures. The
  Python builder's post-fix import is not evidenced on disk. Porting toward
  the verified artifact keeps the byte gate; porting away from it would mean
  regenerating the gate from unverified output.

**What R costs, accepted.** `utils::zip` needs a `zip` binary on the PATH
where Python has `zipfile` built in (the spec notes this; a `zip` package
dependency is the alternative if it bites). R's regular expressions over XML
are no safer than Python's; the port keeps the approach because parsing and
re-serializing carried XML with `xml2` would change bytes and break carried
byte-identity. The package grows to roughly 2,000 lines of cartridge code
plus fixtures, split across the spec's five files and the new
`cartridge-carry.R` and `extract.R`.

**Revisit if** the a11y subsystem is dropped from the package and the
R/exams path is retired in favour of a JSON-bank generator, at which point
nothing but inertia holds the language, or if `exams2canvas()` is ever
replaced by something with a Python implementation.

### If Logan overrules and chooses Python

The R builder's 1,274 lines, including the announcement section, the quiz
embed with its prefix rewrite, the course card, the body inlining with its
three answer-key guards, and the pre-zip scan, would be ported into Python,
and the byte gate would have to be regenerated from Python output. The gate's
rule is never to regenerate to pass, so the only honest path is to make the
Python port byte-exact against the R output first, on the ECON 730 fixture,
which means reproducing R's `gid()` concatenation, `writef()`'s byte
handling, the pinned zip mtimes, and every element order. That is the same
work as the R port in the other direction plus a language change.

Two R dependencies would not go away. `exams2canvas()` has no Python
equivalent, so quiz generation would be an R subprocess or would stay an R
package of its own, which is the two-runtime problem the hybrid rejection was
meant to avoid, relocated rather than removed. The accessibility subsystem,
7,037 lines with 3,106 lines of tests, would be rewritten or would stay R;
either way the sibling plan's lane B changes shape entirely. Distribution
moves from `remotes::install_github()` to `pip`, and the Makefiles, the
skills, and `init_course()` follow.

What would be gained: `zipfile` and `zoneinfo` in the standard library, and
a language some contributors prefer. Neither reaches the cost above.

---

## 10. Honest costs

**The merged builder is bigger and holds more than one person's model of
Canvas.** Roughly 2,000 lines of R across seven files, two item-body
vocabularies (generated and carried), five schema keys that exist only so
extracted courses can reproduce their ids, and a transform pipeline over
carried bytes with a fixed order that matters. The R builder today can be
read top to bottom; the merged one cannot.

**Carried bytes are opaque to every check that matters.** The pre-zip scan
can verify a carried resource is declared, referenced, well-formed, and
byte-identical to its source. It cannot verify the content is right, is
current, or is what the instructor meant. The answer-key canary is meaningful
only for generated content; carried QTI legitimately holds answers. A course
that carries most of its items has most of its cartridge outside the reach of
the containment design, and the README must say that carry-through is bytes
in, bytes out.

**Regular expressions over XML stay.** Every carried transform edits XML text
with regexes because parsing and re-serializing would change bytes. The
review found seven defects in that style of code (items 4, 5, 14, 15, 18,
19, and the `re.sub` replacement escaping). The port fixes those seven and
inherits the fragility that produced them. Each transform is tested on
synthetic carried files, which is the mitigation, and it is not a strong one.

**Exam pools are one course's feature in the package.** The arithmetic is
general and has one consumer. Its fixture is a hand-written pooled QTI file
because real pooled quizzes are course content. E3 offers leaving it behind
in ECON 202, and this plan's recommendation to port it is the least confident
one in the document.

**The schema conversion rewrites a live course's manifest.** ECON 202's
`modules.yml` is under active edit (three commits in two days) and the
converted file is longer and shaped differently. The converter preserves
every value and the header comments; it cannot preserve the file's feel, and
`git blame` on it restarts. It is a rewrite of the one file that course's
Python builder reads, so between M15 and E7 the Python builder cannot build
the course and the package is the only builder. That window is the risk, and
it closes only with M16's import.

**ECON 730's cartridge changes shape three times before the freeze** (M02,
M03, M05), on a live course, verified by one import. The alternative, the
sibling's ordering, changes it once after the move and then twice more, each
with an import. This plan trades import count for a bigger single change;
section 11 says so and E1 is the decision.

**`height_measured` against mtimes is weak.** `git` does not preserve
mtimes, so every fresh clone makes every page look edited after its
measurement and every height reports stale. The check will be noisy exactly
when a new contributor first runs it. A content hash beside the timestamp
would fix it and is deliberately not in this pass.

**Announcements stay ECON 730's only, in practice.** The mechanism is general
and the extractor does not read them, so a course extracted from an export
carries its announcements as nothing at all until E8 is decided. The seven in
ECON 730's round-trip export would be lost by M17's extraction and that is
recorded there as expected.

**Two builders exist for the duration.** Until M16, ECON 202 builds with
Python and every defect in section 5 stays live in what it ships; the plan
fixes them in the port and not in `macro_principles`. Review item 1 is
CONFIRMED and present in v10. Whether that is acceptable for the next ECON
202 import is Logan's call and not this plan's; the review's own "before the
next import" list is 1, 2, 3.

**The extractor makes a promise the README has to qualify.** "Export your
course, run one command, have a plain-text repo" is true for structure and
false for sources: an extracted course of `body: true` pages is a course of
carried bytes with no `content/canvas/`, and it stays that way until someone
writes the sources. The best first experience for a stranger is also the one
most likely to leave them with a repo they cannot edit as text.

---

## 11. Where this plan and the sibling plan disagree

Each is a proposed amendment to the sibling plan, for Logan to accept or
refuse. None is applied here.

1. **T11's placement.** The sibling lands multiple assignment groups after
   T10, as the one deliberate baseline regeneration. This plan does it in
   the live script before T05 (M03), together with D6 (M02) and the template
   (M05), so that one import verifies all three and T10 becomes a pure move
   of a converged script. If Logan prefers the sibling's order, M02, M03 and
   M05 become three post-T10 regenerations with three imports, and lane C
   waits on the last of them. E1.
2. **T30 is superseded.** The sibling's Lane E memo was to lay out three
   options for ECON 202. This plan is the first option, worked out: port the
   Python builder's capabilities into the package with per-item carry, and
   convert the schema. If accepted, T30 becomes "read this plan and decide",
   and `econ202-onboarding.md` sections 2, 4, and 5 are superseded by
   sections 3.8, 4, and 6 here (its section 1 measurements and section 6
   verification still stand and are used by M15 and M16).
3. **`init_course()` gains `from_export`.** The sibling's section 5 defers
   the export entry point to T30 and lists it under "deliberately does not
   do". Section 3.7 here puts it in scope as M14, amending T25's signature,
   its "does not do" list, and its verification (the scaffold-from-export is
   verified by building the M07 fixture, and by Logan's ECON 202 import in
   M16, not by a second scaffold import).
4. **Section 12's "two builders exist and this plan leaves both standing"**
   is corrected by M16 and M18, not before.
5. **Section 9's synthetic fixture** needs one more member: a synthetic
   source cartridge (M07) so the shipped gate reaches the carry path. T04's
   `minimal-course` gains one `source_ref` definition of each kind pointing
   into it.
6. **Spec 12b and 12c** move from "after the gate" to "before the freeze"
   (M04, M05). 12b changes no ECON 730 output; 12c does, and is in the M06
   import.
7. **Spec 1h / D3 (`textbook_docs: none`)** is needed by M15: ECON 202 has
   no textbook. The sibling already recommends it; this plan depends on it
   landing in T08.
8. **D4 (`term:` as a block with `timezone`)** is required, not optional,
   for M08: carried due dates on ECON 202 need the declared zone, and ECON
   730's announcements already carry theirs in `announcements.yml`. M15's
   ECON 202 `course.yml` already has the block.
9. **Section 14's unverified item "what the ECON 202 round trip proved"**
   is answered: the only round trip on disk is the failed one (1c).

---

## 12. Decisions for Logan

Beyond the sibling's D1 to D14, which stand.

| # | Decision | Blocks | Recommendation, marked as such |
|---|---|---|---|
| E1 | Converge before the freeze (M02 to M06, one import) or move first and regenerate three times (the sibling's order) | M02, T05 | converge first; the gate then guards the shape that ships, and a live course gets one import event |
| E2 | The R schema as the one schema, with ECON 202's `modules.yml` converted by a one-off tool in its own session | M15 | yes; the alternative is two dialects in the package forever |
| E3 | Exam pools: port the arithmetic with the three ECON 202 facts moved to YAML (M11); or leave the whole transform in ECON 202 as a post-build script; or re-baseline ECON 202's `source:` to a fresh export after the Fall 2026 import so the pools are already in the bytes and the transform is not needed until the next redesign | M11, M15 | port it, but this is the least confident recommendation here; the third option is cheapest and contradicts mechanics 5b by putting pool design back into bytes |
| E4 | `files_meta.xml` and `media_tracks.xml`: write empty (the R builder, mechanics 6) or carry from `source:` (the Python builder, v10) | M07, M15 | write empty and declare the divergence; if the M16 import shows the "Uploaded Media" folder matters, carry becomes an option |
| E5 | ECON 202's `urls.site` loses its `/pages` suffix so the stale check maps URLs under `docs/` without a course-layout heuristic | M10, M15 | make the one-line edit in M15; nothing else in ECON 202 reads `site` |
| E6 | Pin Position Memos' id to the Python-derived value in ECON 202's `course.yml` | M15 | yes, if any v8 to v10 cartridge was imported into a shell that will be reused; harmless otherwise |
| E7 | Retire `scripts/build_cartridge.py` and `extract_cartridge_manifest.py` from ECON 202 after M16 | after M16 | Logan's, in an ECON 202 session; not before a package-built cartridge has been imported and round-tripped |
| E8 | Whether `extract_manifest()` also writes `announcements.yml` from `imsdt_xmlv1p1` resources, and YAML for grading standards and late policy, in a later task | later | later; structure first |
| E9 | ~~Whether review item 1 (groups outside `root_section`, present in v10) is fixed in the Python builder before the next ECON 202 import, independently of this plan~~ | nothing here | **DECIDED 2026-09-02. Logan authorized the fix in ECON 202's `build_cartridge.py`, upstream and independent of this plan.** Rationale: `coursepack` still contains one function, so nothing about the fix waited on the migration, and fixing upstream means ECON 202 ships a correct cartridge for Fall 2026 while the port inherits a fix proven against a real export rather than reproducing a broken one. Authorization covers the script and this fix only, not committing, not the review's other findings, and not the generate-everything redesign. |

---

## 13. What this plan could not verify

Stated so nobody treats them as checked.

- **Whether any ECON 202 cartridge after the marker fix was imported into
  Canvas, and what its round trip showed.** The only round-trip export on
  disk is the failed first one. The commit message records the fix; the
  verification is not on disk.
- **Whether Canvas walks groups placed outside `root_section`.** The review
  confirmed v10 has 12 such groups in the midterm; Canvas's tolerance is
  unknown. M11 makes the question moot for package output.
- **Which `<title>` Canvas uses for a quiz's gradebook column** (review 18).
  M08 rewrites both, which is safe either way.
- **Whether the "Uploaded Media" folder declaration in `files_meta.xml`
  affects an import** (E4).
- **Whether module `unlock_at` or prerequisites are exported when set.**
  Neither export has any.
- **What Canvas exports for rubrics, outcomes, or a syllabus body.** Neither
  export has any.
- **The ECON 202 v9 and v10 builds' relation to `HEAD`.** Their mtimes
  (14:25, 14:31) postdate the review's reverted edits window; `git status`
  shows the builder clean, so they were built by the committed script, but
  which YAML state they reflect was not checked.
- **The converted `modules.yml` length.** The 2,600-line figure in 3.8 is an
  estimate, not a measurement; the converter does not exist.
- **Whether T03's helper produces `2026-12-22T15:45:00` for ECON 202's
  final.** Stated as the expected value from the zone rule; T03's test is
  where it is checked.
- **The extractor's behaviour on an export whose wiki pages are not iframe
  wrappers at all** (a hand-authored Canvas course). Both exports on hand are
  wrapper courses; M12's fixture is synthetic.
