---
name: paper-assessment
description: >
  Print one fixed paper form of a quiz or an assignment, as Word and PDF, with
  an answer key beside it. Use when the user says "paper version", "print the
  quiz", "paper exam", "printable final", or needs a form for a make-up
  sitting, a proctored room or an accommodation. Covers the seed, the key, and
  which definitions can be printed at all.
---

# The paper form of an assessment

A bank quiz in Canvas is a draw. Every student meets a different set of items,
and nobody, the instructor included, ever holds the whole thing in one hand. A
make-up sitting, a proctored room and an accommodation each need one fixed form
on paper, with a key that matches it item for item.

```r
coursepack::print_assessment(".", id = "final-exam", seed = 2026, formats = c("docx", "pdf"))
```

`id` is a quiz or assignment id from `modules.yml`. Quizzes are looked up
first. The documents land under `build/paper/` unless `out_dir` says otherwise,
and each is rendered with quarto when quarto is on the PATH.

## The seed is the form's name

The draw is `set.seed(seed)` and then one sample without replacement from each
question group, in group order. Seed 7 is one paper and seed 8 is another, and
asking for seed 7 again next term hands back the same paper. Nothing written
carries a timestamp for exactly that reason, so two runs of one seed are
byte-identical files and a diff of two forms shows the questions rather than
the clock.

**Keep the seed and the key with the sitting.** They are the record: with them
the form can be printed again from the bank and a student's answers graded
against it, and without them the paper in the folder is the only copy of what
was asked. The key is written as a separate document, never a section of the
form and never a page the form runs into, so the two are handed to a copier
separately or not at all. It names the number as printed, the chapter, the
section, the bank id and the answer letter, with the seed above the table.

## The same pools as Canvas

`bank_groups()` builds the groups, and it is the same function the cartridge
builder calls. The paper form and the Canvas quiz therefore draw from
identical pools, with the same splits and the same chapter pooling. A form that
prints is evidence about the quiz that ships.

## What is printable

| Definition | Printable |
|---|---|
| a quiz declaring `bank:` | yes, with a key |
| an assignment declaring `description:` | yes, no key |
| an assignment declaring `homework:` | yes, no key |
| a quiz declaring `qti:` | no |
| a quiz or assignment declaring `source_ref:` | no |
| an assignment declaring `quiz_file:` | no |

The three refusals are all the same refusal. An R/exams zip, a carried resource
and a linked quiz file each keep their student-facing text somewhere this
package does not read, so a form built out of the part it can see would be a
form with questions missing. It refuses and says which forms it does print,
rather than printing a shorter paper that looks complete.

## Details worth knowing before the copier

- Question stems are HTML in a bank and go through pandoc to Markdown. Tables
  become pipe tables, because a simple table indented under a numbered item and
  then edited by hand falls apart without anything looking wrong.
- Options print `A.` to `D.` in the order the bank wrote them, and the key
  records the letter **as printed**, which is the letter a student writes down.
- A figure is copied beside the document and referenced by its bare filename
  with the bank's alt text, so the form and its images travel as one folder.
- `formats` takes `docx` and `pdf`, which are the two the front matter
  declares. Anything else stops.
- With `render = FALSE`, or with no quarto on the PATH, the documents are
  written and where they are is printed.

## Before it is sat

A form that renders proves nothing about the draw. Read the rendered document
against the key, question by question, before it is copied. Check that every
figure is on the page it belongs to, that no table has lost its columns, and
that the key's answer letters match the options as they now stand on paper.

That reading is a person's job, and it is the only check there is.
