---
name: make-coursepack
description: >
  Builds a Canvas-importable Common Cartridge (.imscc) from a plain-text
  course source tree. Use when the user says "build the coursepack", "make
  the cartridge", "generate the imscc", "package the course for Canvas",
  "export for Canvas", or asks to get course content into Canvas without
  API access. Also use when a module, page, or assignment has changed and
  the user wants an updated import file.
---

# make-coursepack

**Status: verified by a real Canvas round trip** of the first course built with
this toolchain (9 modules, 74 items sent, 74 returned, 0 lost). Round-tripping
is the technique that makes this verifiable.

## The first verification, as a record

A generated cartridge was imported into a real Canvas shell, inspected by the
author, and then **exported back out**. The round-trip export was compared field
by field against what went in:

| Checked | Result |
|---|---|
| modules | 9 sent, 9 returned |
| module items | 74 sent, 74 returned, **0 lost, 0 gained** |
| `indent`, `new_tab`, `url`, `workflow_state`, `position` | 0 mismatches across all 74 |
| URL anchors (`#homework-assignment-...`) | 6 sent, 6 returned intact |
| weblink resources | 33 sent, 33 returned |
| assignments | 10, with state, points, submission type, allowed extensions and position all identical |
| wiki page iframes | 6 sent, 6 returned with `src` unchanged |
| grading standard | returned byte-identical |
| embedded quiz | 20 questions, 20 distinct idents, 20 distinct answer ranges, points and group preserved |
| files dropped by Canvas | none |

Canvas discards malformed content silently, so "it imported without an error"
means nothing. Export the course back out and diff it against what you sent.
Anything Canvas quietly dropped is missing from the re-export.

| Entry point | Role |
|---|---|
| `coursepack::check_manifests(".")` | validates `course.yml` and `modules.yml` |
| `coursepack::build_cartridge(".")` | emits the `.imscc`; `modules = c("Module 5", ...)` stages a partial build |
| `coursepack::diff_against_reference(".")` | fails on any divergence not declared in `reference.yml` |
| `make coursepack` | chains all three |

Still unverified, and marked UNVERIFIED where it appears below: anything about
content types this course does not use. Discussions, files embedded in the
cartridge, New Quizzes, and LTI all remain untested here.

## When to use

Building a `.imscc` from source for manual import into Canvas. This exists
where the author has no Canvas API access, so the cartridge is the only
delivery mechanism.

Includes Classic quizzes: they are embedded, so there is one file to upload.

Not for: anything requiring the Canvas API, or New Quizzes content.

## Inputs

| Path | Role |
|---|---|
| `course.yml` | Course metadata |
| `modules.yml` | Module structure and item ordering |
| `content/pages/` | Page source |
| `build/qti/*.zip` | R/exams QTI packages, referenced from `quizzes:` in modules.yml |
| `announcements.yml` | Optional. Declares the announcement bodies the cartridge carries. |
| `questions/` | JSON question banks, drawn from by `bank:` quizzes |
| `reference.yml` `source:` | The cartridge carried resources come from |
| `reference.yml` `export:` | **Your course's own Canvas export, the specification** |

Output: `build/coursepack/<slug>-<date>.imscc`

## The reference export is the spec

`reference.yml`'s `export:` names a real Canvas export of **your own course**.
Read its `imsmanifest.xml` and match its structure. Do not work from IMS
standards documents when the reference answers the question. It reflects what
Canvas actually produces and accepts, which is not always what the spec says.

Unpack it read-only. Never modify or regenerate it.

Because it is a real export rather than a hand-built file, **divergence between
generated output and this cartridge is a bug in the generator**, not a
difference of opinion about the spec. That is what makes it usable as an
acceptance test.

The corollary, learned the hard way: **a real export also contains the course's
own mistakes.** One real export had a title with a trailing space, two
assignment items writing `<new_tab/>` empty where eight write `false`, four
duplicated homework dropboxes, and two due dates out of order. Match the
export's *structure*, not its typos. Normalize, and declare each normalization
so the diff still fails on anything undeclared.

## The identifier model, which is the trap

Canvas uses three kinds of identifier and they are not interchangeable:

- **item id**, one per module item
- **resource id**, which names the file or directory on disk
- **idref**, how an item points at its resource

For most item types the idref holds the same value in both files it appears in.
`ExternalUrl` is the exception. Verified across all 72 items of one real export:

| Item type | `module_meta.xml` idref | `imsmanifest.xml` idref |
|---|---|---|
| ContextModuleSubHeader | none (24/24) | none |
| WikiPage | resource id (6/6) | same |
| Assignment | resource id (10/10) | same |
| **ExternalUrl** | **the item's own id** (32/32) | **the weblink resource id** (0/32 equal) |

So for a weblink, `module_meta.xml` **self-references** while `imsmanifest.xml`
points at the actual `<idref>.xml`. One item, two distinct identifiers.

The obvious guess, that an idref means the same thing everywhere, produces a
cartridge Canvas accepts and then silently drops items from. Check this first if
modules import but their links do not.

Identifiers should be **deterministic**, a hash of a stable key rather than
random, so two builds of unchanged source are comparable and a diff shows real
change.

Read first:

| Path | What it gives you |
|---|---|
| `imsmanifest.xml` | resource declarations, identifier conventions, nesting |
| `course_settings/module_meta.xml` | the modules and items, in order |
| `course_settings/assignment_groups.xml` | assignment group structure |
| `wiki_content/` | how Canvas stores page HTML |

A course whose export has no quizzes is not evidence that cartridges cannot
carry them; a real export of a second course carried 36 Classic quizzes. That
inference was made here once and was wrong: a single negative sample is not
evidence of impossibility. See "Embedding quizzes" below.

Note the version distinction: the cartridge is CC **1.1.0** while quizzes are
QTI **1.2**. Different standards, different version numbers, one zip.

## Embedding quizzes

Classic quizzes ride in the cartridge, so there is one file to upload. Confirmed
against a real export containing 36 of them.

A quiz is **three files and two resources**:

```
<qid>/assessment_qti.xml          CC-profile stub, EMPTY <section>, ~1 KB
<qid>/assessment_meta.xml         Canvas quiz settings
non_cc_assessments/<qid>.xml.qti  the real QTI, all the questions
```

```xml
<resource identifier="<qid>" type="imsqti_xmlv1p2/imscc_xmlv1p1/assessment">
  <file href="<qid>/assessment_qti.xml"/>
  <dependency identifierref="<metaid>"/>
</resource>
<resource identifier="<metaid>" type="associatedcontent/..." href="<qid>/assessment_meta.xml">
  <file href="<qid>/assessment_meta.xml"/>
  <file href="non_cc_assessments/<qid>.xml.qti"/>
</resource>
```

Two things that look like bugs and are not: **the stub is genuinely empty**, and
the **meta** resource, not the assessment resource, declares the
`non_cc_assessments` file.

Module item: `content_type` `Quizzes::Quiz`, `identifierref` pointing at the
assessment resource, `<new_tab/>` empty rather than `false`.

The meta's `<quiz identifier>` must equal the assessment resource id. Also set
`assignment_group_identifierref`, or the quiz lands in Canvas's default group.

### The identifier rewrite, which is where this goes wrong

A generator like R/exams stamps fresh random ids into every build, so they must
be rewritten to something deterministic. Two traps, both hit here:

**1. Rewrite the PREFIX, not the whole token.** Question idents extend the base:

```
quiz01-interval-estimation_400877615_section_1_item_01_num
```

Matching `[A-Za-z0-9._-]+_[0-9]+` swallows `_section_1_item_01` too, collapsing
all 20 idents to one value. **Canvas then keeps 1 question and discards 19,
silently.** The quiz still imports, still appears in the right module with the
right title, and looks perfect in the UI. Only a round-trip diff reveals it.

Always assert that question count equals distinct-ident count, and fail the
build if not.

**2. There is more than one random id.** R/exams uses two independent suffixes on
the same base name, and the meta references both. Rewriting one leaves the other
dangling.

Locate prefixes by **literal** search. Building a regex from a course slug means
escaping metacharacters by hand, which is its own bug.

### Reproducibility

The cartridge is byte-reproducible **for a given QTI zip**. It is not
reproducible across quiz regenerations, and should not be: that randomization is
the point of R/exams. Regenerate the quiz when you want new numbers, not on
every cartridge build.

### Three ways a quiz reaches the cartridge

A quiz definition in `modules.yml` declares exactly one of three keys, and the
key decides where its questions come from.

`qti:` names an R/exams zip. The zip is embedded, with the prefix rewrite above
applied to every ident so two builds of the same zip are comparable:

```yaml
- id: q-sample
  title: Sample R/exams Quiz
  qti: build/qti/quiz-sample.zip
  group: Quizzes
```

`bank:` generates the quiz from a JSON question bank under `questions/`. The
draw becomes Canvas question pools, one per section or one per chapter, and
`splits` divides a single section's draw into more than one pool. `unlock_at`
and `lock_at` set the quiz window and are read in the course's own zone:

```yaml
- id: q-bank
  title: Module 1 Bank Quiz
  due: 2026-09-25
  bank: {dir: questions, chapters: [1, 2], draws: [2, 1, 2], points: 5}
```

`source_ref:` carries the quiz out of the cartridge named by `reference.yml`'s
`source:`, byte for byte, because that export is the only copy of it:

```yaml
- id: carried-quiz
  title: Carried Quiz
  due: 2026-10-02
  source_ref: i1a2b3c4d5e6f7890abcdef1234567890
```

### Carried resources

A `source_ref:` page, assignment or quiz is copied byte for byte out of the
source cartridge and then transformed in a fixed order. Titles and `due:` are
rewritten from the YAML, and carried HTML is repaired unless `course.yml` says
`carry: {repair_html: false}`. Everything else in a carried file is exactly what
the source held. The package cannot judge whether a carried body is current or
right; it only guarantees that it is unchanged.

### Quiz figures

A question bank may reference figures, and those figures are the one admitted
use of `$IMS-CC-FILEBASE$`. They are staged under `web_resources/quiz_images/`,
referenced only as `$IMS-CC-FILEBASE$/quiz_images/<file>`, and every token is
checked against the staged file, file by file, before anything is zipped. Exam
figures cannot be hosted publicly the way the rest of the assets are, which is
why this exception exists at all.

### Starting from an export

A course that already lives in Canvas does not start from a blank manifest. It
starts from its own export:

```r
coursepack::extract_manifest("export.imscc", "path/to/new-course")
```

That writes `course.yml`, `modules.yml`, `reference.yml` and a copy of the
export under `reference/`. It never overwrites an existing one of those files
unless `overwrite = TRUE`, because re-running an extractor over hand-edited
manifests has destroyed those edits before.

It also writes `carry: repair_html: false`, `term: timezone: UTC`, and the
export's own `course_id:` and `manifest_id:`, with every exported deadline as a
`due:` value in UTC, so that the first rebuild reproduces the export byte for
byte. Set your real zone and rewrite those dates in the same pass, since the
values only mean what they say together, and turn `repair_html` back on once
the export's own HTML has been checked.

What is not recovered: announcements, grading standards, the late policy, LTI
links, and the link from any resource back to its plain-text source. A course
that authored its pages and then extracts its own export therefore gets a
manifest that is structurally exact and source blind. The first build after an
extraction also reports every iframe height as undated, because an extracted
height is a measurement with no date on it.

## Workflow

1. **Read the reference manifest.** Structure, resource types, identifier
   conventions, organization nesting.
2. **Parse `course.yml` and `modules.yml` with `check_manifests()`.** Fail
   loudly on missing or malformed fields; a partial cartridge that imports
   incorrectly is worse than one that doesn't build.
3. **Render pages to cartridge HTML.**
4. **Rewrite asset references to absolute Pages URLs.** See below.
5. **Build `imsmanifest.xml`** matching reference structure.
6. **Assemble the zip.**
7. **Diff against the reference with `diff_against_reference()`.** Report
   structural divergence before writing.
8. **Report what needs manual work after import**: dates, the course name, and
   deleting the destination shell's default empty assignment group.
9. **Stop.** Do not claim success. Only a Canvas import proves the cartridge is
   valid.

## Hard rules

**Never embed files in the cartridge.** Assets live on GitHub Pages; the
cartridge contains absolute URLs to them. Cartridge-internal file references
use `$IMS-CC-FILEBASE$` tokens rewritten at import, and getting that wrong is
the most common cartridge failure mode. Hosting on Pages removes the problem
rather than solving it.

The only exceptions are the course card and quiz figures, both checked file by
file.

If any other asset reference in generated output is a relative path or an
`$IMS-CC-FILEBASE$` token, that's a bug.

**Never include assessment SOURCE files.** No `.Rmd`, `.qmd`, `.R` or `.Rnw`
from `assessments/`, and never the leak canary.

Do not implement this as a filename check. Matching `assessment` or `quiz` in a
filename fires on Canvas's own `assessment_meta.xml`. Check for source
extensions and the canary string instead.

Note what IS allowed: **quiz QTI contains answer keys**, deliberately, because
Canvas needs them to grade. That is safe because the cartridge is imported into
Canvas and is never rendered into `docs/`. The containment rule is about the
public site, not the cartridge.

**Never generate New Quizzes content.** New Quizzes are LTI-backed and do not
round-trip through import. Classic Quizzes only.

**Never report success on a successful zip build.** The build succeeding says
nothing about whether Canvas will accept it.

**Refuse to build rather than emit a known-bad artifact.** Where a course
manifest can express something that must never ship, make it a hard `stop()`,
not a warning. Here, an assignment carrying a `todo:` marker can never be
emitted as `published: true`. That single rule is what makes placeholder
assignments safe to include at all; without it they are a liability waiting to
go live by accident.

**Omit what does not belong to the destination course.** The reference carries
things a generated cartridge should not reproduce:

| Omit | Why |
|---|---|
| `context.xml` | holds the SOURCE course's Canvas id, root account id and account uuid |
| `web_resources/` except the course card and quiz figures | the course card is 18 KB and uses image_identifier_ref; quiz figures are exam content and must not be public |
| `imsbasiclti_xmlv1p0` | LTI links do not round-trip through import |
| due dates | stale dates look authoritative in Canvas, which is worse than none |

## Gotchas

Seeded from prior work. Add to this as you learn; it is the most valuable part
of the skill.

- **Canvas fails silently on invalid content.** With malformed QTI it creates
  no quiz and reports no error. Assume cartridge imports fail the same way.
  Never trust the import log; inspect the result, and prefer a round-trip export
  over eyeballing the course.
- **Import into a throwaway shell, never a live course.** Imports add content;
  they don't replace it. Repeated test imports into a real course leave debris.
- **Older cartridge into newer Canvas is the safe direction.** The reference
  export predates the current institutional Canvas version, which is the
  correct direction of travel.

Found while building, 2026-08-12:

- **A manifest never declares itself.** A check comparing files on disk against
  `<file href=...>` entries will flag `imsmanifest.xml` unless exempted. The
  reference declares it 0 times. The first run of that check failed the build on
  a non-problem: suspect a new validator before suspecting the artifact.
- **zip stores mtimes, so identical content is not a byte-identical archive.**
  `zip -X` strips extra fields but not timestamps. Pin every staged file's mtime
  before zipping if reproducibility is claimed. It was claimed here before it was
  tested, and the first test disproved it.
- **Number formatting is a real divergence.** Canvas writes
  `<points_possible>50.0</points_possible>`. In R, `format(50L, nsmall = 1)`
  returns `"50"`, because `nsmall` is ignored on integers and YAML parses `50` as
  one. Caught by the reference diff, not by reading the code. This is the
  argument for the diff existing.
- **Link by anchor, never by printed section number.** Section numbers in a
  Quarto book are positional and renumber when anything is inserted earlier. A
  Canvas assignment citing "6.11" was pointing at a heading the book now numbers
  6.12, while every anchor across the same edits still resolved.
- **Verify link targets exist before shipping.** A dead link inside a cartridge
  is invisible until a student clicks it. Resolve every chapter file and every
  anchor against the actual rendered HTML at build time.

## Verification

### Test the validators, not just the artifact

A validator that always passes is worse than none, because it manufactures
confidence. Before trusting any check, **break something on purpose and confirm
it fails**, then restore and confirm the file is byte-identical again.

Both checks here were proved this way: a deliberately broken anchor was caught in
both places it appeared, and setting a placeholder assignment to `published:
true` aborted the build with a named error.

### Local checks worth running before the expensive one

Cheap, and they protect the manual import from being spent on mechanical faults:

- every file declared in the manifest exists, and every file on disk is declared
- every idref resolves to a declared resource; no dangling refs, no orphans
- every generated XML file parses
- no `$IMS-CC-FILEBASE$` anywhere but the quiz figures under `quiz_images/`
- nothing from `assessments/` present
- two consecutive builds are byte-identical

### The only real test: round-trip it

1. Build the cartridge.
2. Import into a throwaway Canvas course shell.
3. Open it. Check module structure, page rendering, and that every asset link
   resolves to a live Pages URL.
4. **Export the course back out of Canvas and diff the export against what you
   sent.** This is the step that catches silent failures. Eyeballing a course
   will not tell you that one item of 73 is missing; a field-by-field comparison
   will.

Compare structurally, never by identifier. Canvas regenerates every id on
import, so ids will always differ and that is not a finding. Match items on
title plus content type, then compare `indent`, `new_tab`, `url`,
`workflow_state` and `position`.

For an embedded quiz, check specifically:

- `non_cc_assessments/` is **non-empty**. An empty directory means the quiz never
  imported. That is what it looks like when Canvas rejects it.
- question count and **distinct ident count** both match what you sent. Equal
  totals with collapsed idents is the silent failure above.
- distinct answer values match. Canvas re-encodes a numerical tolerance from an
  `<or>` of exact plus range into a pure `vargte`/`varlte` range, so count
  bounds, not `<varequal>`. It also drops `<order order_type="Random"/>`.
  Neither is a loss.

Two things that are expected in a round trip and are not failures:

- Canvas **adds** `course_settings/context.xml`, describing the destination
  course.
- The destination shell's own empty **Assignments** group survives alongside the
  imported group. Delete it by hand; it does not affect grades but it clutters
  the gradebook.

And one thing the cartridge does **not** control: the course name. The
destination shell keeps its own title. Set it in Canvas after import.

Log the outcome in the course's own log if it keeps one, with symptom, cause,
and fix for anything that broke.

## Reference

- `reference.yml` `export:`, the known-good target
- the package `NEWS.md`, for what changed at which version
- the course's own decision record, if it keeps one
