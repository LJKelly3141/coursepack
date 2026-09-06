# Setting up coursepack

How to install the package, start a course with it, and bring it into a course
that already exists. The README says what the package is; this page is the
walk-through.

## What you need

| To do this | You need |
|---|---|
| install the package | R 4.1 or later, and the `remotes` package |
| build a cartridge (`make coursepack`) | `zip`, `pandoc` |
| draw the dashboard card (`make tile`) | ImageMagick, which the `magick` package binds to |
| render the site and paper forms (`make site`, `make paper`) | `quarto` |
| preview the module tree (`make mockup`) | `python3`, for the local server |
| audit for accessibility (`make a11y`) | `python3`, Node with `npx`, and a Chrome or Chromium binary |
| the scaffold's `git init` | `git` |

The audit is the only reason Node appears anywhere. It drives pa11y, which
`npx` fetches at run time and which needs a browser. None of that is needed to
build a cartridge, a quiz package, or a preview.

By platform:

- **macOS**, with Homebrew: `brew install pandoc imagemagick quarto node`.
  `zip`, `python3`, `git` and `make` are already there.
- **Ubuntu or Debian**: `sudo apt-get install zip pandoc libmagick++-dev python3
  make`, then Quarto and Node from their own installers.
- **Windows**: install Rtools, which provides `zip` and `make`, then Pandoc,
  Quarto, and Node from their installers. ImageMagick comes bundled with the
  `magick` package's CRAN binary.

## Install the package

```r
install.packages("remotes")
remotes::install_github("LJKelly3141/coursepack")
coursepack::coursepack_version()
```

The last line prints the installed version. For a specific release, name its
tag: `remotes::install_github("LJKelly3141/coursepack@v1.0.0")`.

To check the installation without touching any course, scaffold a throwaway
course into a temporary directory and build it:

```r
root <- coursepack::init_course(tempfile("course-"), code = "ABCD 101",
                                title = "Demo Course",
                                site_url = "https://example.org/demo",
                                timezone = "America/Chicago",
                                git = FALSE, skills = FALSE)
coursepack::build_cartridge(root)
unlink(root, recursive = TRUE)
```

A cartridge lands under `build/coursepack/` in that directory, and the closing
lines remind you that a zip that builds proves nothing.

## Start a course

### A course that does not exist yet

```r
coursepack::init_course(
  "abcd-101",
  code     = "ABCD 101",
  title    = "Introduction to Something",
  site_url = "https://example.invalid/abcd-101/",
  timezone = "America/Chicago"
)
```

`code`, `title`, `site_url` and `timezone` have no defaults, and the function
stops rather than guess; in an interactive session it prompts for a missing one.
`site_url` is where the rendered site will be published and must start with
`https://`. `timezone` is an IANA name, checked against `OlsonNames()`, because a
wrong zone moves every deadline by hours while the generated XML still reads
perfectly. The directory must be missing or empty; nothing is ever overwritten.

It writes about two dozen files: the two manifests `course.yml` and
`modules.yml`, `announcements.yml`, a Quarto site with a render allowlist, the
containment scaffold that keeps `assessments/` and `questions/` out of the site,
a `Makefile` whose every target calls this package, the authoring skills under
`.claude/skills/`, and a `README.md`. It runs `git init` and commits nothing.
Then it prints the next steps, which are the working loop below.

### A course that is already in Canvas

Export the course from Canvas as a Common Cartridge, then hand the `.imscc` to
the same function:

```r
coursepack::init_course("abcd-101", code = "ABCD 101",
                        title = "Introduction to Something",
                        site_url = "https://example.invalid/abcd-101/",
                        timezone = "UTC",
                        from_export = "abcd-101-export.imscc")
```

The scaffold is written first, then `extract_manifest()` replaces the two
manifests and `reference.yml` with the export's own structure and copies the
export under `reference/`. Every carried deadline is written as the UTC instant
Canvas stored, with `term: timezone: UTC` above it. Those two lines belong to
each other: naming a local zone here means rewriting the carried `due:` dates to
match, and the closing summary says so when it applies. The first
`make coursepack` after this reproduces what Canvas already has, and
`make refdiff` reports no divergence, before anything is changed on purpose.

## Bring the toolchain into a course

A course repository carries no build script. The package is a dependency, and
the scaffold's `Makefile` is the only thing in the course that names it:

```
make install-toolchain
```

installs or updates the package from GitHub. A session that is working on the
package itself points the target at a checkout instead:

```
make install-toolchain COURSEPACK=/path/to/coursepack
```

The authoring skills ship inside the package and are copied into the course,
so a clone carries them whether or not the package is installed on that
machine. `make skills` refreshes the shipped copies and leaves anything the
course added beside them.

Every target in the scaffold's `Makefile`:

| Target | What it does |
|---|---|
| `make site` | `quarto render` into `docs/`, then the leak check |
| `make leakcheck` | refuses if anything from `assessments/` reached `docs/` |
| `make checkyml` | validates `course.yml` and `modules.yml` |
| `make coursepack` | `checkyml`, builds the cartridge, then `refdiff` |
| `make refdiff` | structural diff against the export named in `reference.yml` |
| `make mockup` | builds the local preview and serves it in a browser |
| `make qti QUIZ=assessments/quizzes/<name>.R` | a QTI 1.2 package for one quiz definition |
| `make paper ID=<id> SEED=<n>` | one fixed paper form of a quiz or assignment, with its key |
| `make a11y` | the accessibility audit of the rendered site |
| `make tile` | the Canvas dashboard card, to `assets/images/course-tile.png` |
| `make skills` | refreshes the shipped skills under `.claude/skills/` |
| `make test` | `checkyml` and `leakcheck` |
| `make clean` | removes `build/` and `.quarto/`, never `docs/` |
| `make install-toolchain` | installs or updates this package |

## The working loop

1. Fill in `term: first_day:` and `last_day:` from the registrar's calendar, and
   write the pages and the module tree in `course.yml` and `modules.yml`.
2. `make site`. That renders and runs the leak check in one step.
3. Commit, push, and enable GitHub Pages from `main` and the `docs` folder. The
   site has to answer before a cartridge built from it is imported, because
   every page in the cartridge is a link to it.
4. `make coursepack`.
5. `make mockup` and read the module tree before anyone imports it.
6. Import the `.imscc` into a throwaway Canvas shell and look at every page.
   Export the shell back out, name the export in `reference.yml`, and
   `make refdiff`. That comparison is the only evidence that any of this worked.

## What is never public

`assessments/` and `questions/` are never rendered and never enter the site or
the cartridge. `docs/` and `assets/` are always public. The line between them
is enforced twice: the render allowlist in `_quarto.yml`, and a canary string
planted in the assessment sources that `make leakcheck` scans for byte by byte
in everything about to be published. A hit is a refusal, not a warning.
