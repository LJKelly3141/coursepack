---
name: question-bank-authoring
description: >
  Author and review a chapter of a JSON multiple-choice question bank that a
  Canvas quiz draws from, with a separate reviewer agent reading the source
  text back against every key. Use when the user says "write the question
  bank", "author chapter N questions", "review the bank", "generate quiz
  questions for chapter", or asks for new items for a bank quiz. Also use when
  an existing chapter needs remeasuring after fixes.
---

# Authoring a question bank

A `bank:` quiz in `modules.yml` names a directory of chapter files, and Canvas
draws each student's quiz out of the pools built from them. The bank is the
only copy of those questions, so an item that is wrong is wrong for every
student who ever draws it, and nobody sees it happen. That is what the loop
below is for.

One chapter is one unit of work. Two agents do it: an author who reads the
source and writes, and a reviewer who reads the source again and rules on what
the author wrote. Neither is the instructor, who admits the chapter at the end.

## 1. The schema

One JSON file per chapter, `chapter_<NN>.json`, in the bank directory:

```
{chapter, title, source, sections: [{section, questions: [{id, type,
  difficulty, objective, question, options {A, B, C, D}, answer, explanation,
  image, figure {file, script, alt}}]}]}
```

`question` is HTML, so `<br>`, `<i>` and `<table>` in it are content rather
than markup errors. `id` is an integer, unique within the chapter, because the
cartridge builder derives a stable Canvas item identifier from the chapter, the
section and the id: two questions sharing an id collapse into one item.

The conventions that make a chapter admissible:

| Convention | Value |
|---|---|
| Items per section | 12 |
| Difficulty mix per section | 5 recall, 5 application, 2 analysis |
| Key letters per section | exactly 3 A, 3 B, 3 C, 3 D |
| Explanation | complete sentences, ends with the section number |
| Figures | a script under `figures/`, writing a PNG under `images/` |
| Figure naming | named by the item that uses it, `CH<NN>_Qnnn.py` and `.png` |
| Alt text | enough to answer the question from the alt text alone |

Section names in the bank must match the item titles in `modules.yml`
character for character. A title that reads right and does not match is the
defect this catches.

## 2. The loop

**Author.** Reads every section of the chapter through
`scripts/fetch_openstax.py`, which writes the page body to a text file and
exits non-zero under 300 words, so a failed fetch cannot pass as a read. Writes
the chapter file, draws the figures, runs `scripts/measure_bank.py` and
`coursepack::check_bank()`, and reports the measurement output in full rather
than a summary of it.

**Reviewer.** A different agent, which did not write the bank. Fetches the
same pages again rather than reading the author's text files, then checks every
item against eight criteria:

1. Key correct, with the establishing sentence quoted from the text.
2. A single defensible answer; no distractor arguably right.
3. Agreement with the text, including a misprint in the source reported.
4. Arithmetic recomputed from the givens, with the computation recorded.
5. Figure integrity: PNG against script, alt text against the data.
6. Stands alone: no reference to the book, no "all of the above".
7. The option-length rule, computed rather than judged.
8. Leakage, scanned and then read by eye.

It writes `review_chapter_<NN>.json`: a verdict per item, and for every fix the
exact replacement wording, the full new stem or option or explanation, so the
author applies it without judgment.

**Author again.** Applies the required changes and nothing else. A reviewer's
wording is the ruling; a fix that turns into a rewrite is a new item and needs
a new review.

**Reviewer again.** Confirms, and adds a recheck block to the review file
saying which fixes it verified.

**Orchestrator.** Re-measures the chapter and presents eight sampled items in
full, with `--sample 8`, so the instructor reads real items rather than counts.

**Instructor.** Admits the chapter, or sends it back.

Across eleven chapters authored this way: 612 items, 50 first-pass fixes, zero
rejects, no key wrong as keyed. The phrase scans caught almost none of the real
leaks; the reviewer reading each key against its neighbours did.

## 3. The briefs

`briefs/author.md` and `briefs/reviewer.md` are the two agent briefs, as
templates. Fill four placeholders and hand the result to the agent:
`{{chapter}}` is the chapter number, `{{sections}}` is the list of section
titles with the source URL for each one, `{{bank_dir}}` is the bank directory
as `modules.yml` names it (`questions`, conventionally), and `{{source_name}}`
is the book and edition the sections come from. Where a file name needs the
chapter padded to two digits the briefs write `<NN>`; fill that too. The author
brief also carries one bracketed paragraph of chapter guidance, which is the
one thing per chapter that has to be written rather than substituted: the ideas
the items must cover and the figures the chapter calls for.

Fill them per chapter and keep the filled copies. A brief is the record of what
the agent was actually asked for, which is the first thing to read when an item
comes back wrong.

## 4. Rules

- **No em-dashes** in a stem, an option, an explanation, alt text, or a figure
  label. Use a comma or a second sentence. `scripts/bank_checks.py` finds them.
- **No attribution to AI tools** in the bank, the report, or the review file.
- **Measure, never recall.** A count in a report comes from running the
  measurement script over the file on disk. A chapter reported as balanced and
  never measured is a chapter nobody has checked.
- **A figure is reproducible or it is broken.** `bank_checks.py` regenerates
  every figure and compares the PNG hash before and after. A figure that
  changes was drawn by hand somewhere, and the script is not the source of it.
- **Constructed data, never real-world figures presented as current.** A number
  that was true when the chapter was written becomes a wrong answer later.
- **The reviewer reads the source, not the author's notes.** The whole value of
  the second pass is that it is independent. A reviewer that reads the author's
  text files is checking the author's transcription, not the bank.

## 5. The scripts

All four are read-only except where noted, and all take plain arguments.

| Script | What it does |
|---|---|
| `scripts/fetch_openstax.py <url> <out.txt>` | Page body to a text file, with figures, captions and tables marked. Prints the word count and exits non-zero under 300 words. |
| `scripts/measure_bank.py <bank-dir> <chapter>` | The measurement table: per-section counts and difficulty, key balance, the option-length cue, figure presence, and a problem list. `--sample N --seed S` prints N items in full; `--modules <modules.yml>` cross-checks the section titles. |
| `scripts/bank_checks.py <bank-dir> <chapter>` | Em-dash, book-reference, forbidden-option, alt-length and figure-file checks, then regenerates every figure and compares hashes. The regeneration overwrites the PNGs; nothing else is written. |
| `scripts/dump_imscc.py <cartridge.imscc> <out.txt>` | Structural dump of a built cartridge or a Canvas export: modules, items, quizzes with their item, group and draw counts. Two pairs of arguments compares two cartridges. |

The package's own checks run beside them, and they are the ones the build
runs, so a bank that passes the scripts and fails these still fails:

```r
b <- coursepack::read_bank("questions", 4)
coursepack::check_bank(b, file.path("questions", "images"))
# draws has one entry per section, in chapter then section order
coursepack::bank_groups(list(dir = "questions", chapters = 4, draws = c(4, 4, 4), points = 12), ".", "Chapter 4 Quiz")
```

`check_bank()` refuses a duplicate id, an answer naming no option, and an image
that is not on disk, and returns a figure with no alt text as a warning rather
than a stop, because the item still renders. `bank_groups()` shows what a
`bank:` block would pool and draw without building anything, which is the fast
way to find a `draws:` list that does not match the sections.

## Reading the bank back out of a cartridge

The bank is the source, but the cartridge is what students meet. After a build,
`dump_imscc.py` prints each quiz's item count, group count and draw count. Read
those against the plan: a quiz that draws 20 from 20 groups of 1 is not the
quiz that was intended, and it imports without an error.

A quiz that builds proves nothing. Import it into a throwaway shell, export the
course back out, and dump both.
