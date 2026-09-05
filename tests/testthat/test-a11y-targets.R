# Ported from the snapshot's own self-checking audit test script: the
# target-discovery sections. Each printed banner there is a test_that() block
# here and each check() is an expectation carrying the original label.
#
# Two departures from a straight transcription, both required by the plan:
#
# 1. The section that ran discovery against whatever real repository an
#    environment variable pointed at is replaced by the `pair/alpha` fixture
#    with a `_quarto.yml` written into a copy of it. The replacement is
#    recorded in NEWS.
# 2. The declared-surfaces negative control drives `intended_surfaces()`,
#    which reaches into the cartridge library. Its three cartridge-bearing
#    fixtures live in test-a11y-cartridge.R, beside that library; the
#    page-surface half is asserted here.

test_that("discover_target, synthetic", {
  # output-dir is "build", not "docs". "docs" is also the first name
  # find_output_dir() tries by convention when config reading is broken, so a
  # fixture that used it could not tell "read the config" apart from "got
  # lucky guessing the convention". "build" is not one of the fallback
  # candidates, so this passes only if the config value was really read.
  #
  # The fixture also carries a resources: key with a real .html file beneath
  # it, so the resources exclusion is asserted by direct membership rather
  # than by a count that could be right for the wrong reason.
  tt <- file.path(tempdir(), "fakequarto"); unlink(tt, recursive = TRUE)
  dir.create(file.path(tt, "build"), recursive = TRUE)
  writeLines(c("project:", "  type: book", "  output-dir: build",
               "  resources:", "    - old_stuff",
               "format:", "  html:", "    theme: cosmo"),
             file.path(tt, "_quarto.yml"))
  writeLines("<html lang='en'></html>", file.path(tt, "build", "01_intro.html"))
  writeLines("<html lang='en'></html>", file.path(tt, "build", "02_next.html"))
  dir.create(file.path(tt, "build", "01_intro_files"))
  writeLines("<html></html>", file.path(tt, "build", "01_intro_files", "widget.html"))
  dir.create(file.path(tt, "build", "old_stuff"))
  writeLines("<html lang='en'></html>", file.path(tt, "build", "old_stuff", "legacy.html"))

  tgt <- discover_target(tt)
  expect_identical(tgt$framework, "quarto", info = "detects quarto")
  expect_identical(basename(tgt$output_dir), "build",
    info = "reads output-dir from config, not the docs/ convention fallback")
  expect_identical(length(tgt$pages), 2L, info = "finds 2 pages")
  expect_identical(any(grepl("_files", tgt$pages)), FALSE, info = "excludes _files")
  expect_identical("old_stuff/legacy.html" %in% tgt$pages, FALSE,
    info = "excludes a resources: directory's html by direct membership")
  expect_identical(is.na(tgt$stylesheet), TRUE, info = "no stylesheet")
})

test_that("find_stylesheet, positive case", {
  # Every earlier fixture resolved to NA, so a find_stylesheet() hardcoded to
  # always return NA would have passed all of them. This one has a real
  # authored stylesheet declared through theme: [cosmo, custom.scss], the
  # documented way to layer a custom scss file on a built-in base, so there is
  # an assertion that can actually fail if discovery stops finding it.
  ts <- file.path(tempdir(), "fakequarto_styled"); unlink(ts, recursive = TRUE)
  dir.create(file.path(ts, "docs"), recursive = TRUE)
  writeLines(c("project:", "  type: book", "  output-dir: docs",
               "format:", "  html:", "    theme: [cosmo, custom.scss]"),
             file.path(ts, "_quarto.yml"))
  writeLines("/* authored theme overrides */", file.path(ts, "custom.scss"))
  writeLines("<html lang='en'></html>", file.path(ts, "docs", "index.html"))

  tgt_styled <- discover_target(ts)
  expect_identical(is.na(tgt_styled$stylesheet), FALSE,
    info = "finds the authored theme scss, not NA")
  expect_identical(basename(tgt_styled$stylesheet %||% ""), "custom.scss",
    info = "stylesheet path is the real custom.scss file, not a guess")
})

test_that("find_stylesheet, three reproduced wrong-non-NA cases (critical)", {
  # An earlier find_stylesheet() fell back to scanning the whole repo for the
  # first .css/.scss file once config reading found nothing, filtered by an
  # exclusion regex that hardcoded the literal string "/docs/" and had no
  # entries for common vendor or build-output directories. All three fixtures
  # below reproduce a real reported failure of that design and would have
  # returned a confident wrong path under it. The fix removes the fallback
  # scan: find_stylesheet() trusts only what config explicitly points at, so
  # all three correctly return NA.

  # Case 1: nothing but vendored CSS under node_modules/, and no config
  # pointing anywhere. The old exclusion regex had no node_modules entry.
  r1 <- file.path(tempdir(), "vendor_only_nodemodules"); unlink(r1, recursive = TRUE)
  dir.create(file.path(r1, "node_modules", "bootstrap", "dist", "css"), recursive = TRUE)
  writeLines("/* vendored */",
             file.path(r1, "node_modules", "bootstrap", "dist", "css", "bootstrap.min.css"))
  expect_identical(is.na(find_stylesheet(r1, "static")), TRUE,
    info = "vendored-only CSS under node_modules/ is not mistaken for authored")

  # Case 2: nothing but a webpack-style build bundle under dist/assets/. The
  # old exclusion regex had no dist entry either.
  r2 <- file.path(tempdir(), "build_output_only"); unlink(r2, recursive = TRUE)
  dir.create(file.path(r2, "dist", "assets"), recursive = TRUE)
  writeLines("/* bundler output, not authored */",
             file.path(r2, "dist", "assets", "main.a1b2c3.css"))
  expect_identical(is.na(find_stylesheet(r2, "static")), TRUE,
    info = "bundled build-output CSS under dist/ is not mistaken for authored")

  # Case 3: a Quarto project whose output-dir is not "docs" (the literal the
  # old regex hardcoded), holding a generated theme-compiled.css that nothing
  # in config references (theme: cosmo is a bare built-in name, not a file).
  r3 <- file.path(tempdir(), "quarto_nondocs_outputdir"); unlink(r3, recursive = TRUE)
  dir.create(file.path(r3, "_output"), recursive = TRUE)
  writeLines(c("project:", "  type: book", "  output-dir: _output",
               "format:", "  html:", "    theme: cosmo"),
             file.path(r3, "_quarto.yml"))
  writeLines("/* quarto-generated bootswatch compile, not authored */",
             file.path(r3, "_output", "theme-compiled.css"))
  expect_identical(is.na(find_stylesheet(r3, "quarto")), TRUE,
    info = "generated theme CSS in a non-docs output-dir is not mistaken for authored")
})

test_that("find_output_dir, bookdown config read symmetrically with quarto", {
  # _bookdown.yml's own output_dir: key was previously never read, so a
  # bookdown project using a name other than one of the convention fallbacks
  # (docs, _site, _book, public, .) silently produced output_dir = NA and 0
  # pages even though the config said exactly where to look.
  tbk <- file.path(tempdir(), "fakebookdown"); unlink(tbk, recursive = TRUE)
  dir.create(file.path(tbk, "public_html"), recursive = TRUE)
  writeLines('output_dir: "public_html"', file.path(tbk, "_bookdown.yml"))
  writeLines("<html lang='en'></html>", file.path(tbk, "public_html", "ch1.html"))

  tgt_bd <- discover_target(tbk)
  expect_identical(tgt_bd$framework, "bookdown", info = "detects bookdown")
  expect_identical(basename(tgt_bd$output_dir), "public_html",
    info = "reads bookdown output_dir from config, not a convention guess")
  expect_identical(length(tgt_bd$pages), 1L,
    info = "finds the bookdown page under its configured output_dir")
})

test_that("find_stylesheet, bookdown", {
  # find_stylesheet() had exactly one framework branch (quarto). Bookdown's
  # output_dir is read symmetrically in find_output_dir(), but nothing read
  # bookdown's stylesheet config, so a bookdown course was always told "create
  # a stylesheet first" even when it plainly had one: an undisclosed asymmetry
  # between what the two functions trust for the same framework. Bookdown's
  # css: setting lives per output format in _output.yml, not in _bookdown.yml.
  tbks <- file.path(tempdir(), "fakebookdown_styled"); unlink(tbks, recursive = TRUE)
  dir.create(file.path(tbks, "public_html"), recursive = TRUE)
  writeLines('output_dir: "public_html"', file.path(tbks, "_bookdown.yml"))
  writeLines(c("bookdown::gitbook:", "  css: style.css"),
             file.path(tbks, "_output.yml"))
  writeLines("/* authored bookdown theme */", file.path(tbks, "style.css"))
  writeLines("<html lang='en'></html>", file.path(tbks, "public_html", "ch1.html"))

  tgt_bks <- discover_target(tbks)
  expect_identical(is.na(tgt_bks$stylesheet), FALSE,
    info = "bookdown stylesheet resolves the real declared file, not NA")
  expect_identical(basename(tgt_bks$stylesheet %||% ""), "style.css",
    info = "bookdown stylesheet path is the real style.css")

  # A declared but absent bookdown stylesheet must return NA, not a path to a
  # file that does not exist, the same discipline the quarto branch has.
  tbkm <- file.path(tempdir(), "fakebookdown_missing_css"); unlink(tbkm, recursive = TRUE)
  dir.create(file.path(tbkm, "public_html"), recursive = TRUE)
  writeLines('output_dir: "public_html"', file.path(tbkm, "_bookdown.yml"))
  writeLines(c("bookdown::gitbook:", "  css: missing.css"),
             file.path(tbkm, "_output.yml"))
  writeLines("<html lang='en'></html>", file.path(tbkm, "public_html", "ch1.html"))

  tgt_bkm <- discover_target(tbkm)
  expect_identical(is.na(tgt_bkm$stylesheet), TRUE,
    info = "bookdown stylesheet declared but absent from disk returns NA")
})

test_that("find_output_dir, nested-only HTML fails loudly, not silently", {
  # A repo whose only HTML lives nested under a name no convention or config
  # recognizes used to return output_dir = NA with no signal distinguishing
  # "genuinely no HTML here yet" from "HTML exists but could not be placed".
  # find_output_dir() now warns in the second case; both the NA and the
  # warning are asserted, since an NA alone would look identical to the
  # pre-fix silent behaviour.
  tn <- file.path(tempdir(), "nested_static_only"); unlink(tn, recursive = TRUE)
  dir.create(file.path(tn, "content", "blog"), recursive = TRUE)
  writeLines("<html lang='en'></html>", file.path(tn, "content", "blog", "post.html"))

  warned <- FALSE
  od_nested <- withCallingHandlers(
    find_output_dir(tn, detect_framework(tn)),
    warning = function(w) { warned <<- TRUE; invokeRestart("muffleWarning") })
  expect_identical(is.na(od_nested), TRUE,
    info = "nested-only HTML with no recognizable output dir: honestly NA")
  expect_identical(warned, TRUE,
    info = "that NA is accompanied by a loud warning, not a silent guess")
})

test_that("find_output_dir, HTML found only under an excluded path (round 3)", {
  # An earlier fix filtered node_modules/, dist/, build/ and friends out of the
  # loud-warning scan so they would not falsely trigger it. dist/ and build/
  # are also ordinary real output directory names for a Vite or webpack style
  # static site, so a genuine site whose only HTML lives in dist/ then
  # resolved to a completely silent NA, indistinguishable from a repo with no
  # HTML at all. find_output_dir() now tells three states apart: real
  # non-vendor HTML found but unplaceable (the original warning, the section
  # above), HTML found only under an excluded path (a distinctly worded
  # warning, this section), and no HTML anywhere (silence, still correct).

  # Both whether a warning fired and its text, since state 2 and state 3 must
  # be told apart by what they say, not merely by whether some warning
  # happened.
  capture_with_warning <- function(expr) {
    msg <- NA_character_
    val <- withCallingHandlers(expr, warning = function(w) {
      msg <<- conditionMessage(w)
      invokeRestart("muffleWarning")
    })
    list(value = val, message = msg)
  }

  # The motivating case: a Vite or webpack style build whose real output lives
  # in dist/, with nothing else anywhere in the repo. Before the fix: a silent
  # NA, indistinguishable from an empty repo. After: a warning naming dist.
  td <- file.path(tempdir(), "state3_dist_only"); unlink(td, recursive = TRUE)
  dir.create(file.path(td, "dist"), recursive = TRUE)
  writeLines("<html lang='en'><body>a real page, just in an excluded-by-name dir</body></html>",
             file.path(td, "dist", "index.html"))
  res_dist <- capture_with_warning(find_output_dir(td, detect_framework(td)))
  expect_identical(is.na(res_dist$value), TRUE,
    info = "HTML found only under dist/: still resolves to NA")
  expect_identical(!is.na(res_dist$message), TRUE,
    info = "HTML found only under dist/: a warning fires (not silent)")
  expect_identical(grepl("dist", res_dist$message %||% "", fixed = TRUE), TRUE,
    info = "HTML found only under dist/: the warning names the dist directory")
  # The state-2 warning reads "...no output directory could be confidently
  # identified...". This message must not be that same text with the repo path
  # swapped in: it needs its own wording so a reader, or a script grepping
  # logs, can tell the two states apart.
  expect_identical(
    grepl("could be confidently identified", res_dist$message %||% "", fixed = TRUE),
    FALSE,
    info = "HTML found only under dist/: worded differently from the state-2 warning, not just a path swap")
  expect_identical(
    grepl("excluded vendor/build directory", res_dist$message %||% "", fixed = TRUE),
    TRUE,
    info = "HTML found only under dist/: mentions the excluded-path reasoning explicitly")

  # node_modules-only lands in state 3 too, not a silent state-2-adjacent
  # pass. State 3 is defined structurally ("HTML exists, all of it under an
  # excluded path"), not by which excluded name matched, so node_modules and
  # dist go through the identical code path and the identical discipline.
  # Special-casing node_modules back to silence would reintroduce a bespoke
  # rule for one directory name.
  tv <- file.path(tempdir(), "vendor_html_only"); unlink(tv, recursive = TRUE)
  dir.create(file.path(tv, "node_modules", "somejspkg", "docs"), recursive = TRUE)
  writeLines("<html><body>vendored package docs, not a real page</body></html>",
             file.path(tv, "node_modules", "somejspkg", "docs", "index.html"))
  res_vendor <- capture_with_warning(find_output_dir(tv, detect_framework(tv)))
  expect_identical(is.na(res_vendor$value), TRUE,
    info = "node_modules-only HTML: still resolves to NA")
  expect_identical(!is.na(res_vendor$message), TRUE,
    info = "node_modules-only HTML: now lands in state 3, a warning fires")
  expect_identical(grepl("node_modules", res_vendor$message %||% "", fixed = TRUE), TRUE,
    info = "node_modules-only HTML: the warning names node_modules specifically")

  # State 1 is exercised throughout this file already: every fixture whose
  # output_dir resolves to a real directory returns long before reaching this
  # code, so no warning ever fires for them.
})

test_that("discover_target, a fixture repo given a _quarto.yml", {
  # REPLACEMENT for the snapshot section that ran discovery against whatever
  # real repository an environment variable pointed at, and skipped when it
  # was unset. A live repository someone else is writing cannot be an input to
  # this package's suite, so the same properties are asserted against the
  # `pair/alpha` fixture with a `_quarto.yml` written into a copy of it: the
  # framework is read from that config, discovery finds real pages rather than
  # zero, every page sits at the output root, and nothing under a declared
  # pass-through copy is counted as a page.
  dest <- file.path(tempdir(), "targets-pair"); unlink(dest, recursive = TRUE)
  dir.create(dest, recursive = TRUE)
  stopifnot(file.copy(fixture_path("pair", "alpha"), dest, recursive = TRUE))
  repo <- normalizePath(file.path(dest, "alpha"), mustWork = TRUE)
  writeLines(c("project:", "  type: book", "  output-dir: site",
               "  resources:", "    - handouts"),
             file.path(repo, "_quarto.yml"))
  dir.create(file.path(repo, "site", "handouts"), recursive = TRUE)
  writeLines("<html lang='en'></html>",
             file.path(repo, "site", "handouts", "copied.html"))

  rt <- discover_target(repo)
  expect_identical(rt$framework, "quarto", info = "fixture framework")
  expect_identical(length(rt$pages) > 0L, TRUE,
    info = "fixture pages: discovery finds real pages, not zero")
  expect_identical(all(dirname(rt$pages) == "."), TRUE,
    info = "fixture pages: every page is a rendered page at the output root")
  expect_identical(
    any(vapply(rt$resource_dirs,
               function(d) any(exclusion_matches(rt$pages, d)),
               logical(1))),
    FALSE,
    info = "fixture pages: nothing under a declared resources/ copy is treated as a page")
  expect_identical(is.na(rt$stylesheet), TRUE,
    info = "the fixture has no authored stylesheet")
})

test_that("negative control: the driver's declared surfaces, against hand-authored expectations, through the real shared function", {
  # The first version of this section was circular: the function under test
  # was defined as an inline vapply() over discover_target(), and the section
  # computed that identical expression a second time and compared the two. A
  # function checked against a hand-copied restatement of its own definition
  # cannot fail under any real regression. Every expectation below is instead
  # a literal, hand-typed value chosen when the fixture was built.
  #
  # The page-surface half of the declaration, and the cartridge naming formula
  # in isolation, are asserted here. The three cartridge-bearing fixtures of
  # this section (3 pages plus a 2-wiki-page cartridge; 2 pages and no
  # cartridge directory at all, which must not produce a phantom cartridge
  # surface; 1 page and two real cartridges whose wiki pages must be summed
  # rather than overwritten) live in test-a11y-cartridge.R, with the library
  # whose functions intended_surfaces() reaches for them.
  nc_decl1 <- file.path(tempdir(), "nc-decl-full"); unlink(nc_decl1, recursive = TRUE)
  dir.create(file.path(nc_decl1, "docs"), recursive = TRUE)
  writeLines("project:\n  type: default\n", file.path(nc_decl1, "_quarto.yml"))
  for (nm in c("a", "b", "c")) {
    writeLines(sprintf("<html lang='en'><title>%s</title><body>%s</body></html>", nm, nm),
               file.path(nc_decl1, "docs", paste0(nm, ".html")))
  }

  expect_identical(page_surface_name(discover_target(nc_decl1)), "nc-decl-full",
    info = "negative control: the page surface name is the repo's own directory name, hand-typed")
  expect_identical(length(discover_target(nc_decl1)$pages), 3L,
    info = "negative control: the page surface is valued at the hand-built page count")

  # cartridge_surface_name() in isolation, against a literal, so a naming
  # regression there and a counting regression in intended_surfaces() cannot
  # mask each other.
  expect_identical(cartridge_surface_name(nc_decl1), "nc-decl-full-cartridge",
    info = "negative control: cartridge_surface_name() suffixes exactly '-cartridge', hand-typed")
})

test_that("intended_surfaces() searches the cartridge directories it is given", {
  skip_if_no("zip")
  # The declaration and the audit loop must read the SAME set of files, or the
  # report's coverage cross-check compares a measurement taken over one set of
  # cartridges against a declaration built from another. intended_surfaces()
  # called cartridges_in() with the package default while audit_course() passed
  # its own `cartridge_dirs` to the audit loop, so at any non-default value the
  # two silently looked in different places.
  cd <- file.path(tempdir(), "cart-dirs-repo"); unlink(cd, recursive = TRUE)
  dir.create(file.path(cd, "docs"), recursive = TRUE)
  writeLines("project:\n  type: default\n", file.path(cd, "_quarto.yml"))
  writeLines("<html lang='en'><title>a</title><body>a</body></html>",
             file.path(cd, "docs", "a.html"))
  dir.create(file.path(cd, "reference"), recursive = TRUE)
  write_a11y_cartridge(file.path(cd, "reference", "one.imscc"))

  expect_identical("cart-dirs-repo-cartridge" %in% names(intended_surfaces(cd)), TRUE,
    info = "the fixture really does hold a cartridge under the default directories")
  expect_identical(
    "cart-dirs-repo-cartridge" %in%
      names(intended_surfaces(cd, cartridge_dirs = "nowhere")),
    FALSE,
    info = "pointed somewhere with no cartridge, the declaration names no cartridge surface")
})

test_that("I5 addendum: declared pass-through directories are excluded from the source scan", {
  # Working files that are not distributed to students must not be scanned.
  # The exclusion is not a directory name written into the package: it is
  # whatever the project's own config declares it copies rather than renders
  # (project: resources:), read by discovery and passed to the checks as a
  # required argument, the same discipline `surface` follows.
  #
  # One fixture, two figure chunks: one inside a declared resource directory,
  # one outside. A check that ignored `exclude` would report both; a check
  # that excluded everything would report neither.
  i5x_root <- file.path(tempdir(), "i5x-resources"); unlink(i5x_root, recursive = TRUE)
  dir.create(file.path(i5x_root, "working_notes"), recursive = TRUE)
  dir.create(file.path(i5x_root, "docs"), recursive = TRUE)
  writeLines(c("project:", "  type: book", "  output-dir: docs",
               "  resources:", "    - working_notes"),
             file.path(i5x_root, "_quarto.yml"))
  writeLines(c("```{r published-fig}", "ggplot(d, aes(x, y)) + geom_point()", "```"),
             file.path(i5x_root, "ch1.qmd"))
  writeLines(c("```{r working-file-fig}", "ggplot(d, aes(x, y)) + geom_point()", "```"),
             file.path(i5x_root, "working_notes", "notes.qmd"))
  writeLines("<html lang='en'><title>c</title><body>c</body></html>",
             file.path(i5x_root, "docs", "ch1.html"))

  # A repo that declares nothing, for the other direction. The nested-course
  # fixture the snapshot reused here lives in test-a11y-checks.R now, so an
  # equivalent one is built locally rather than reached across files.
  i5x_bare <- file.path(tempdir(), "i5x-declares-nothing"); unlink(i5x_bare, recursive = TRUE)
  dir.create(file.path(i5x_bare, "chapters"), recursive = TRUE)
  writeLines(c("```{r nested-r-fig}", "ggplot(d, aes(x, y)) + geom_point()", "```"),
             file.path(i5x_bare, "chapters", "ch1.qmd"))

  # The exclusion list comes from real config through real discovery, not from
  # a literal typed into this test.
  i5x_tgt <- discover_target(i5x_root)
  expect_identical(i5x_tgt$resource_dirs, "working_notes",
    info = "I5x: discovery reads the declared pass-through directories from config")
  expect_identical(discover_target(i5x_bare)$resource_dirs, character(),
    info = "I5x: a repo declaring no resources excludes nothing")

  i5x_scanned <- source_files_for_checks(i5x_root, exclude = i5x_tgt$resource_dirs)
  expect_identical(any(grepl("ch1\\.qmd$", i5x_scanned)), TRUE,
    info = "I5x: the source outside the declared directory is scanned")
  expect_identical(any(grepl("working_notes", i5x_scanned)), FALSE,
    info = "I5x: the source inside it is not")

  i5x_fig <- check_missing_fig_alt(i5x_root, "i5x", exclude = i5x_tgt$resource_dirs)
  expect_identical(i5x_fig$selector, "chunk:published-fig",
    info = "I5x: exactly the published chunk is reported")
  i5x_all <- check_missing_fig_alt(i5x_root, "i5x", exclude = character())
  expect_identical(nrow(i5x_all), 2L,
    info = "I5x: and scanning everything WOULD have reported both, so the exclusion is doing real work")

  # The argument is required, in both checks and in the shared helper. A
  # default of character() would let a caller silently scan a course's working
  # files and still look correct.
  i5x_missing_fig <- try(check_missing_fig_alt(i5x_root, "i5x"), silent = TRUE)
  i5x_missing_col <- try(check_colour_only(i5x_root, "i5x"), silent = TRUE)
  i5x_missing_src <- try(source_files_for_checks(i5x_root), silent = TRUE)
  expect_identical(inherits(i5x_missing_fig, "try-error"), TRUE,
    info = "I5x: check_missing_fig_alt() without `exclude` fails loudly, it does not scan everything")
  expect_identical(
    grepl("check_missing_fig_alt\\(\\): `exclude` is required",
          conditionMessage(attr(i5x_missing_fig, "condition"))),
    TRUE,
    info = "I5x: and the error names the argument and who wanted it")
  expect_identical(inherits(i5x_missing_col, "try-error"), TRUE,
    info = "I5x: check_colour_only() without `exclude` fails loudly too")
  expect_identical(inherits(i5x_missing_src, "try-error"), TRUE,
    info = "I5x: so does the shared helper")
  expect_identical(
    inherits(try(source_files_for_checks(i5x_root, exclude = 42), silent = TRUE),
             "try-error"),
    TRUE,
    info = "I5x: a non-character exclusion is rejected rather than silently coerced")

  # Four assertions of this section read the audit driver's own source and
  # require that it builds the exclusion from discovery's resource_dirs and
  # unproduced_sources and passes the union, and that no course directory name
  # appears in its executable lines. They live in test-a11y-driver.R, with the
  # driver whose source they read.
  #
  # The fifth, that no course directory name reaches an executable line of the
  # checks, is asserted here against the deparsed function bodies and the
  # module-level constants. Deparsing gives exactly what the snapshot's
  # comment-stripping grep gave, the code that runs and not the comments,
  # which cite real directories as evidence by convention.
  ns <- asNamespace("coursepack")
  check_code <- c(
    unlist(lapply(c("check_missing_fig_alt", "check_colour_only",
                    "source_files_for_checks", "exclusion_matches",
                    "glob_to_regex", "warn_dead_exclusions", "require_exclude",
                    "zero_source_finding", "parse_qmd_chunks",
                    "find_rendered_figure_dir"),
                  function(f) deparse(get(f, envir = ns)))),
    SOURCE_EXCLUDE_RE, PLOT_CALL_RE)
  expect_identical(any(grepl("lecture_notes|_outlines", check_code)), FALSE,
    info = "I5x: no course's directory name appears in any executable line of the checks")
})

test_that("exclusion entries are globs, and a literal-only match is a silent no-op", {
  # The tripwire. Exclusion entries were matched only as literal directory
  # paths, so `assets/**`, the most common Quarto idiom there is, could never
  # equal or prefix a real path: the entry did nothing and said nothing.
  #
  # These also protect the three sentinel control characters glob_to_regex()
  # relies on (U+0001 to U+0003, real bytes in the checks file that most
  # editors render as nothing). If an editor ever strips them, every
  # assertion below fails rather than glob matching quietly switching itself
  # off.
  expect_true(exclusion_matches("assets/a/b.qmd", "assets/**"))
  expect_false(exclusion_matches("assetsfoo.qmd", "assets/**"))
  expect_true(exclusion_matches("a.qmd", "*.qmd"))
  expect_false(exclusion_matches("sub/a.qmd", "*.qmd"))
  expect_true(exclusion_matches("lecture_notes/x/y.qmd", "lecture_notes"))

  gx <- function(paths, entry) paths[exclusion_matches(paths, entry)]
  expect_identical(
    gx(c("assets/a.qmd", "assets/deep/b.qmd", "src/c.qmd"), "assets/**"),
    c("assets/a.qmd", "assets/deep/b.qmd"),
    info = "glob: ** crosses path separators")
  expect_identical(gx(c("assets/a.qmd", "assetsfoo/a.qmd"), "assets/**"), "assets/a.qmd",
    info = "glob: ** does not match a sibling whose name merely starts the same")
  expect_identical(gx(c("notes/a.qmd", "notes/deep/b.qmd"), "notes/*"), "notes/a.qmd",
    info = "glob: a single * stays inside one path segment")
  expect_identical(gx(c("draft-1.qmd", "final.qmd"), "draft-*.qmd"), "draft-1.qmd",
    info = "glob: * matches within a filename")
  expect_identical(gx(c("ch1.qmd", "ch12.qmd"), "ch?.qmd"), "ch1.qmd",
    info = "glob: ? matches exactly one character")
  expect_identical(gx(c("a.qmd", "axqmd"), "a.qmd"), "a.qmd",
    info = "glob: a dot in the entry is a literal dot, not regex 'any character'")
  expect_identical(
    gx(c("lecture_notes/a.qmd", "lecture_notes", "other/a.qmd"), "lecture_notes"),
    c("lecture_notes/a.qmd", "lecture_notes"),
    info = "glob: a wildcard-free entry keeps plain directory semantics")
  expect_identical(gx(c("notes/a.qmd", "other.qmd"), "notes/"), "notes/a.qmd",
    info = "glob: a trailing slash is tolerated")

  # End to end, against a real repo whose config uses the glob form: before
  # the fix the entry matched nothing and the file was scanned.
  gx_root <- file.path(tempdir(), "glob-resources"); unlink(gx_root, recursive = TRUE)
  dir.create(file.path(gx_root, "assets", "deep"), recursive = TRUE)
  writeLines(c("project:", "  type: default", "  resources:", "    - \"assets/**\""),
             file.path(gx_root, "_quarto.yml"))
  writeLines(c("```{r kept-fig}", "ggplot(d, aes(x, y)) + geom_point()", "```"),
             file.path(gx_root, "ch1.qmd"))
  writeLines(c("```{r asset-fig}", "ggplot(d, aes(x, y)) + geom_point()", "```"),
             file.path(gx_root, "assets", "deep", "copied.qmd"))
  gx_tgt <- discover_target(gx_root)
  expect_identical(gx_tgt$resource_dirs, "assets/**",
    info = "glob: the declared entry is read from config in its glob form")
  gx_fig <- check_missing_fig_alt(gx_root, "gx", exclude = gx_tgt$resource_dirs)
  expect_identical(gx_fig$selector, "chunk:kept-fig",
    info = "glob: a source file under a glob-declared directory is excluded end to end")

  # An entry naming a path that does not exist is a different thing from an
  # entry that legitimately matches no source file, and only the first is
  # worth saying out loud: `assets/**` matching zero .qmd files is normal.
  gx_warns <- function(expr) {
    w <- character()
    withCallingHandlers(expr,
      warning = function(cnd) { w <<- c(w, conditionMessage(cnd)); invokeRestart("muffleWarning") })
    w
  }
  expect_identical(
    any(grepl("names a path that does not exist",
              gx_warns(source_files_for_checks(gx_root, exclude = "no_such_dir/**")))),
    TRUE,
    info = "glob: a stale or misspelled exclusion entry warns that it is not in force")
  expect_identical(
    length(gx_warns(source_files_for_checks(gx_root, exclude = "assets/**"))), 0L,
    info = "glob: a real entry that simply matches no source file stays quiet")
})

test_that("I8: two repos that resolve to the same surface name halt the run", {
  # A surface identity is a path basename, so two repos ending in the same
  # directory name silently collapse into one surface: one course's findings
  # would classify against the other's stylesheet and one page count would
  # vanish from the declaration.
  i8_a <- file.path(tempdir(), "i8-parent-a", "shared-name")
  i8_b <- file.path(tempdir(), "i8-parent-b", "shared-name")
  i8_c <- file.path(tempdir(), "i8-parent-b", "distinct-name")
  for (d in c(i8_a, i8_b, i8_c)) { unlink(d, recursive = TRUE); dir.create(d, recursive = TRUE) }

  i8_hit <- try(halt_on_surface_collision(c(i8_a, i8_b)), silent = TRUE)
  expect_identical(inherits(i8_hit, "try-error"), TRUE,
    info = "I8: two repos sharing a basename halt rather than silently merging")
  expect_identical(
    grepl("shared-name", conditionMessage(attr(i8_hit, "condition")), fixed = TRUE),
    TRUE,
    info = "I8: and the error names the colliding surface")
  expect_identical(
    inherits(try(halt_on_surface_collision(c(i8_a, i8_c)), silent = TRUE), "try-error"),
    FALSE,
    info = "I8: two genuinely distinct repos do not halt")
  expect_identical(
    inherits(try(intended_surfaces(c(i8_a, i8_b)), silent = TRUE), "try-error"), TRUE,
    info = "I8: the guarantee lives inside intended_surfaces() too, not only in the driver")
})

test_that("unproduced sources: material counts only if it is produced", {
  # Derived from whether a page exists, never from a directory name, so this
  # fixture uses names that mean nothing to the code: one source that renders,
  # two that do not, for the two different reasons a real book exhibits (a
  # leading-underscore path Quarto never treats as an input, and a directory
  # simply absent from a book's chapter list).
  up <- file.path(tempdir(), "unprod"); unlink(up, recursive = TRUE)
  dir.create(file.path(up, "_hidden"), recursive = TRUE)
  dir.create(file.path(up, "aside"),   recursive = TRUE)
  dir.create(file.path(up, "out"),     recursive = TRUE)
  writeLines("---\ntitle: t\n---\n", file.path(up, "shipped.qmd"))
  writeLines("---\ntitle: t\n---\n", file.path(up, "_hidden", "draft.qmd"))
  writeLines("---\ntitle: t\n---\n", file.path(up, "aside", "scratch.Rmd"))
  writeLines("<html lang='en'><title>t</title></html>",
             file.path(up, "out", "shipped.html"))

  unprod <- unproduced_sources(up, file.path(up, "out"))
  expect_identical("shipped.qmd" %in% unprod, FALSE,
    info = "the produced source is not excluded")
  expect_identical("_hidden/draft.qmd" %in% unprod, TRUE,
    info = "an underscore-path source that renders nothing is excluded")
  expect_identical("aside/scratch.Rmd" %in% unprod, TRUE,
    info = "a plain directory that renders nothing is excluded")
  expect_identical(length(unprod), 2L,
    info = "exactly the two unproduced sources are named")

  # Would still pass if the function returned everything, so pin the inverse:
  # adding the missing page must remove that file from the excluded set.
  dir.create(file.path(up, "out", "aside"), showWarnings = FALSE)
  writeLines("<html lang='en'><title>t</title></html>",
             file.path(up, "out", "aside", "scratch.html"))
  expect_identical(
    "aside/scratch.Rmd" %in% unproduced_sources(up, file.path(up, "out")), FALSE,
    info = "rendering a source removes it from the excluded set")

  # No output at all: no evidence either way, so exclude nothing and let the
  # fig-alt check report fallback mode rather than silently scanning zero
  # files.
  expect_identical(length(unproduced_sources(up, NA_character_)), 0L,
    info = "an unrendered repo excludes nothing, rather than everything")
})
