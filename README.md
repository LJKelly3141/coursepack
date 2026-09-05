# coursepack

Build tools for plain-text course authoring. One installed copy serves any
number of courses.

**Status: the builder has converged (0.2.0).** `check_manifests()`, `build_cartridge()`,
`diff_against_reference()`, `build_qti()`, `build_preview()`, and `course_tile()` are
in the package. Since the byte-identical move, every output change has been made on
purpose and recorded in the gate: assignment groups routed by name, optional grading
standard and late policy, one known-key list for `canvas:`, one titled iframe template,
id overrides, course prose in `course.yml`, `textbook_docs: none`, two pre-zip guards,
and a stale-height report. Nothing has been imported into Canvas from this package yet.

## What it is for

Two courses at UW-River Falls are authored as plain text and delivered through
Canvas, which has no API available to them, so every build ends in a manual
import. Each course had grown its own copy of the same build scripts. This
package is the one copy.

| Course | Repository |
|---|---|
| ECON 730, Managerial Statistics | `Teaching/managerial_statistics` |
| ECON 202, Macroeconomic Principles | `Teaching/macro_principles` |

## What moves in here, and what never does

Build tools move in. Course content does not.

```
coursepack (this repo)                  each course repo (separate, always)
  build the Common Cartridge              course.yml, modules.yml
  build the QTI 1.2 quiz package          content, pages, data, images
  build the local preview mockup          docs/ and the published site
  check the manifests                     the writing itself
  diff against a Canvas export            reference.yml
  audit against WCAG 2.1 AA               log/, project/
```

## The separation rule

**The courses are separate and stay separate.** They share build tools and
nothing else.

Every entry point takes the course project root, `proj`, as its first argument.
Package code contains no absolute paths, no default pointing at any one course,
and no course-specific literals. Course-specific facts belong in that course's
own YAML.

A function that reads or writes outside the `proj` it was handed has broken the
separation. That is a defect on its own terms, whatever it was trying to do.

## Installing

Not yet installable in any useful sense. When there is something to install:

```r
remotes::install_github("LJKelly3141/coursepack")
```

## Accessibility

The WCAG audit is part of this package rather than a second one. It needs
Node.js, `npx`, and a Chrome or Chromium binary, because it drives pa11y. Those
are declared in `SystemRequirements` and are needed only for the audit. Building
a cartridge, a quiz package, or a preview needs none of them.

## Licence

MIT. See `LICENSE.md`.

One dependency, `digest`, is GPL (>= 2) and sits in `Imports`. The strict reading
of the GPL says a package importing GPL code must itself be GPL; R practice does
not follow that reading, and MIT packages importing `digest` are common on CRAN.
This package declares the dependency rather than redistributing it. If that ever
needs to be airtight, R 4.6 added a `bytes` argument to `tools::md5sum()`, so the
hashing could move to base R and `digest` could be dropped. Be aware that this
changes output: `digest()` as called today serializes its argument first, so its
md5 differs from a raw-string md5, and swapping would change every generated
cartridge identifier. That is a deliberate decision with a re-import cost, not a
tidy-up.

`exams` is GPL-2 | GPL-3 but sits in `Suggests`, which raises no question.

Licensing this package does not license any course content. That lives in the
course repositories and is not covered here.

## The migration

Specified in `project/`. The plan it grew out of lives in the ECON 730 repo at
`project/plans/2026-08-15-coursepack-extraction.md` and
`project/coursepack-extraction-design.md`, which remain the record of why the
design is shaped the way it is.
