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
| install the package | R 4.1 or later; on Linux, ImageMagick's `libmagick++-dev`, which the `magick` dependency builds against |
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
overwritten: the target directory has to be missing or empty, unless
`existing = TRUE`, which adds the course beside files already there and stops,
writing nothing, if any file it would create is already present. `code`, `title`,
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

## Slide style

Decks are Quarto reveal.js documents. The package carries one slide style, UWRF:
a format extension under `inst/templates/slides/` that gives a deck the
university brand when it declares `format: uwrf-revealjs`. `use_uwrf_slides()`
copies the extension into a course's deck directory; the course's `_quarto.yml`
is left alone, and the closing summary says what to add to it. UWRF is the only
style so far. Another institution's or department's style would be a second
extension beside it, installed the same way: a directory under
`inst/templates/slides/_extensions/`, whose name the public-readiness scrub
allows the moment it exists, and a `use_<id>_slides()` of its own.

## Grading without student identity

Five functions let a grader, a person or an agent, score submissions without
ever seeing a name, a Canvas id or a login. Identity is handled only on the
instructor's machine, and the upload back to Canvas works as it always has.

```r
coursepack::anon_key(".", "semester/fall2026/gradebook_export/<export>.csv",  # this run's key
                     "semester/fall2026/CaseStudy03",                         # codes shuffled
                     nicknames = "semester/fall2026/nicknames.csv")
coursepack::anonymize(".", "semester/fall2026/CaseStudy03")  # coded text into its anon/
coursepack::relink(".", "semester/fall2026/CaseStudy03")     # feedback, scores and feedback.zip
coursepack::canvas_grades(".", "semester/fall2026/gradebook_export/<export>.csv",  # narrow import
                          folder = "semester/fall2026/CaseStudy03",  # into semester/fall2026/
                          column = "Case Study 3")                   # gradebook_import/
coursepack::anon_forget(".", "semester/fall2026/CaseStudy03")  # delete the key once Canvas has it all
```

The workflow runs in that order:

1. `anon_key()` reads the latest Canvas gradebook export and builds the key for
   one assignment's grading run at `<assignment>/anon_key.csv`, beside the
   downloads and never inside `anon/`. Codes `S01`, `S02` and so on are handed
   out in a random order every run, so a key that leaks de-anonymizes one
   assignment and no other. The key records its run, the assignment folder
   relative to the project, and every function that reads it refuses a key of
   another run. A re-run for the same assignment keeps every row and adds only
   new students. Nicknames live in a term nicknames file the instructor keeps,
   `canvas_id,nicknames` with nicknames separated by `;`; it holds no codes,
   and `nicknames =` copies its entries into the key.
2. `anonymize()` converts one assignment's Canvas downloads to plain text,
   replaces every name form, nickname, file prefix, login and Canvas id of every
   student with the neutral token `[name]`, whichever student it belongs to, so
   no code appears in the text and the grader never learns whose name was
   redacted, and then checks its own output for anything left. Whole phrases of
   two or more words listed in `anon_keep.txt` at the course root, such as an
   instructor's name in a heading ("Dr. Avery Thorn"), are kept; a one-word
   line is refused, and so is a phrase holding a student's name or id. List
   exact phrases, because "Dr. Thorn" counts as two words and is kept
   wherever it is written. The same name standing alone is still redacted. The
   log counts the protected phrases kept, never the phrase. It refuses to release the folder until nothing is: `anon/NOT_READY`
   stays until the check passes. It also replaces phone numbers, Social
   Security numbers, birth dates, street addresses, profile URLs and @handles,
   and reads the text in every image with tesseract, which must be installed;
   without it the run stops before writing anything. A raster image (PNG,
   JPEG, GIF, BMP, TIFF, WebP) is stripped of its metadata, and an SVG loses its
   `<metadata>` block and editor attributes; an EMF, a WMF and any file that
   cannot be read keep theirs. An image whose text holds a name, id, login,
   path, email or fixed pattern, every SVG, and a file that cannot be read, such
   as an EMF or WMF, is held for you: open each one yourself, then list it in
   `anon_images.csv` beside the key as `image,decision` with `keep` or
   `remove`, and run again. A `remove` row also takes out an image that was not
   held, such as a photo with no text, and one image given both decisions stops
   the run. A kept EMF or WMF is released unaltered, metadata included. The coded folder shows no
   lateness or submission times. Each run adds counts to
   `deidentification_log.md` beside the key, the record that submissions were
   de-identified; keep it with the course records, because `anon_forget()` does
   not delete it.
3. The grader is given only `anon/` and the rubric, and writes
   `anon/feedback/<code>.md` and `anon/scores.csv`, keyed by code.
4. `relink()` puts the names back, refuses feedback that mentions another
   student, and writes each feedback file under a name identical to the
   submission it answers, as a valid file of that type: a PDF for a `.pdf`, a
   Word file for a `.docx`, OpenDocument text for an `.odt`, and the text
   itself for `.md`, `.qmd`, `.Rmd` and `.txt`. Then it writes the scores file
   and `feedback.zip`. When a student uploads several files, feedback goes to
   the latest document of those types whose name does not start a word with
   "spec", or to the latest document when every one is a spec. A script such
   as `.R` is converted for the grader but never answered, and a student with
   no document at all stops the run.
5. `canvas_grades()` writes a narrow gradebook import: the identity columns and
   the scored assignments' columns only, every row of the export kept, and
   every kept cell the export's own bytes except the filled scores. Canvas
   writes back every cell an import carries and reads a blank as a deletion,
   but leaves alone an assignment column the import does not carry, so other
   assignments' grades cannot be rolled back. Exports go in
   `semester/<term>/gradebook_export/` and imports go in the sibling
   `semester/<term>/gradebook_import/`: the function reads exports and writes
   only imports, by default to
   `semester/<term>/gradebook_import/<YYYY-MM-DD>_<folder>_import.csv`, or
   `<YYYY-MM-DD>_<N>-assignments_import.csv` for several assignments. Only the
   term is read from the input paths, never a folder to write in: it is the
   folder name right after `semester/` in the export's path, and every
   assignment folder must be in the same term. An export outside
   `semester/<term>/`, or an assignment folder in another term or in none,
   stops the call with a list of each path and its term, unless `import_dir` or
   `out` names where to write; there is no fallback to a folder without a term.
   It stops
   rather than write into the export's own folder, any folder below it, or
   over the export, and it
   never overwrites an import unless given `overwrite = TRUE`, for a re-run
   after a ruling. Several assignments go through a map, a CSV with columns `folder`
   and `column` and an optional third column `scores` naming a scores file for
   a folder that holds more than one. Coded scores are placed through the
   folder's own key.
6. `anon_forget()` deletes the assignment's key once the feedback upload and
   the grade import are confirmed. It refuses until `relink()` has written
   `feedback/` and the scores file into the assignment folder.

Every key and every output lives in the course's `semester/` folder, which the
course's `.gitignore` must exclude. A key is the only file that joins a code to
a name. None of these functions prints a student's name, id or original file
name; their messages name codes, positions, counts and folder paths. Converting
`.docx` or `.odt` needs `pandoc`, `.pdf` needs `pdftotext` and `pdfimages`,
Word and OpenDocument feedback need `pandoc`, PDF feedback needs `pandoc` and
`xelatex`, and `relink()` needs `zip`.

## What has been verified

Two courses have been built with this package, each started from its own Canvas
export, and taken through the full round trip: imported into a shell, exported
back out, and compared against what was built. The table is the honest state of
what that covers.

| Entry point | Verified by a real Canvas import | Date |
|---|---|---|
| `build_cartridge()` (generated items, announcements, embedded R/exams quiz) | the toolchain this package descends from, before the move | 2026-08-12, 2026-09-02 |
| `build_cartridge()` from this package | two courses, full round trip | September 2026 |
| carried resources, bank quizzes, `description:` assignments | not yet | |
| `extract_manifest()` | two courses started from their Canvas exports, full round trip | September 2026 |
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
