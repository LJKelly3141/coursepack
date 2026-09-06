# coursepack

coursepack builds a Canvas course out of plain text: a course's declarative
manifests become a Common Cartridge, a QTI 1.2 quiz package, a browsable local
preview and a paper form of any assessment, and the rendered course site is
audited against WCAG 2.1 AA. One installed copy serves any number of courses,
because every entry point takes that course's project root as its first argument
and reads nothing outside it.

## How a course is built

Canvas holds the structure and the course's own web site holds the content: the
cartridge carries modules, items, deadlines and settings, while everything a
student reads lives on the published site and is linked absolutely rather than
embedded, so the only files inside a cartridge are the dashboard card and quiz
figures. Containment is enforced twice over, by an allowlist and by a canary:
the render allowlist keeps the private assessment sources out of the site, and a
canary string planted in those sources is scanned for byte by byte in everything
the site is about to publish, so a leak is a refusal rather than a warning.
Every identifier the builder writes is derived from the manifests rather than
generated fresh, so a second import updates the Canvas objects the first one
created instead of standing up a second copy of the course beside them. A zip
that builds proves nothing: Canvas discards malformed content silently and still
reports a successful import, which is why every builder here says so in its
closing lines. The proof is an import and a round trip: import into a throwaway
Canvas shell, look at it, export it back out, and compare that export against
what was built.

## What you need

| To do this | You need |
|---|---|
| build a cartridge | R, `zip`, `pandoc` |
| preview or audit | `python3`; Node, `npx` and a Chrome or Chromium binary for the audit; `quarto` for paper forms |

The audit drives pa11y, which npx fetches at run time and which needs a browser.
That is the only reason Node appears anywhere here, and none of it is needed to
build a cartridge, a quiz package or a preview. `SETUP.md` is the full
walk-through: what to install on each platform, the install itself, starting a
course from nothing or from a Canvas export, and every `make` target a course
gets.

## Quick start

```r
remotes::install_github("LJKelly3141/coursepack")

coursepack::init_course(
  "abcd-101",
  code     = "ABCD 101",
  title    = "Introduction to Something",
  site_url = "https://example.invalid/abcd-101/",
  timezone = "America/Chicago"
)
```

Then, in the new course directory, the steps `init_course()` prints:

1. Fill in `term: first_day:` and `last_day:` from the registrar's calendar,
   and write the pages and the module tree in `course.yml` and `modules.yml`.
2. Render the site and check it for leaks: `quarto render`, then
   `make leakcheck`.
3. Commit, push, and enable Pages from `main /docs`. The site has to answer
   before a cartridge built from it is imported, because every page in the
   cartridge is a link to it.
4. Build.

```
make coursepack
```

That checks the manifests, stages the cartridge, zips it, and diffs it against
the reference export if the course declares one. What comes out is a `.imscc`,
and a `.imscc` that builds is not a course. Import it into a throwaway Canvas
shell, look at every page, export the shell back out, and compare the export
against what you built. That last step is the only evidence that any of this
worked.

## Two ways in

A course that does not exist yet starts from the scaffold. `init_course()`
writes about two dozen files, installs the authoring skills under
`.claude/skills/`, and prints the file list and the next steps. Nothing is ever
overwritten: the target directory has to be missing or empty. `code`, `title`,
`site_url` and `timezone` have no defaults, and the machine's own zone is
printed beside the timezone prompt as a suggestion rather than accepted by
pressing return, because a wrong zone moves every deadline by hours while the
generated XML still reads perfectly.

A course that is already in Canvas starts from an export of itself. Export it,
then hand the `.imscc` to the same function:

```r
coursepack::init_course("abcd-101", code = "ABCD 101", title = "Introduction to Something",
                        site_url = "https://example.invalid/abcd-101/", timezone = "UTC",
                        from_export = "abcd-101-export.imscc")
```

The scaffold is written first, then `extract_manifest()` replaces `course.yml`,
`modules.yml` and `reference.yml` with the export's own structure and copies the
export under `reference/`. A page whose body is the builder's own iframe wrapper
is regenerated as a definition; everything else is carried forward byte for byte
through `source_ref:`, so the first rebuild reproduces what Canvas already has
before anything is changed on purpose. The zone is the thing to be careful with:
every carried deadline is written as the UTC instant Canvas stored, with
`term: timezone: UTC` above it, so those two lines belong to each other and
naming a local zone means rewriting the dates to match.

## What has been verified

Nothing here has been imported into Canvas from this package yet. The table is
the honest state of that.

| Entry point | Verified by a real Canvas import | Date |
|---|---|---|
| `build_cartridge()` (generated items, announcements, embedded R/exams quiz) | the toolchain this package descends from, before the move | 2026-08-12, 2026-09-02 |
| `build_cartridge()` from this package | not yet | |
| carried resources, bank quizzes, `description:` assignments | not yet | |
| `extract_manifest()` | synthetic round trip only | |
| `init_course()` scaffold | not yet | |
| `audit_course()` | ran end to end on two real courses before the move | 2026-09-01 |

The package's own test suite is a different question and a much easier one. It
holds a synthetic course to a byte-for-byte expected staging tree, so an
unintended change to a single generated file fails the suite. That gate says the
output did not change. It cannot say the output is right.

## The separation rule

**Courses are separate and stay separate.** They share build tools and nothing
else.

Every entry point takes the course project root, `proj`, as its first argument.
Package code contains no absolute paths, no default pointing at any one course,
and no course-specific literals. Course-specific facts belong in that course's
own YAML.

A function that reads or writes outside the `proj` it was handed has broken the
separation. That is a defect on its own terms, whatever it was trying to do.

Course content never travels the other way either. Nothing in this repository is
taken from a real course: the test fixtures are an invented course, `ABCD 101`,
with hosts under `example.invalid`.

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

## Contributing

See `CONTRIBUTING.md`. Issues are open for bug reports, questions, and
requests. For a pull request, open an issue first.
