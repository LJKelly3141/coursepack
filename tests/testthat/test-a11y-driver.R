# Ported from the snapshot's own self-checking audit test script: the
# driver-level sections. Each printed banner there is a test_that() block here
# and each check() is an expectation carrying the original label.
#
# Two departures from a straight transcription:
#
# 1. The three sections that read the driver's own source read it by deparsing
#    `audit_course()` instead of readLines()-ing a script. The driver is a
#    function in this package now, so its source is reachable, and deparsing
#    gives exactly what the snapshot's comment-stripping grep gave: the code
#    that runs and not the comments, which cite real evidence by convention.
#    The one anchored pattern loses its `^` anchor, because a function body is
#    indented where a script's top level was not.
# 2. The C1 coverage fixture is built by a helper called inside each block
#    rather than at file level, so the missing-`zip` skip can fire first.
#
# Three hand-offs land here, and after them none is left: the four assertions
# of the pass-through-exclusion section that read the driver's source (named in
# place in test-a11y-targets.R), and the static coupling to the driver in the
# dedup collision negative control (named in place in test-a11y-model.R).

# A cartridge directory zipped in place, the way a Canvas export is shaped.
# test-a11y-cartridge.R defines its own; a test file's functions are not
# visible to another test file, and one two-line zip helper in each is a
# smaller cost than a shared helper file for a shape that is not a fixture.
zip_a11y_dir <- function(root, zip_path) {
  unlink(zip_path)
  old <- setwd(root)
  on.exit(setwd(old), add = TRUE)
  utils::zip(zip_path, list.files(".", recursive = TRUE), flags = "-q")
  zip_path
}

# A real fixture repo: 2 rendered pages, one cartridge holding 2 wiki pages,
# plus the declaration and the metadata builder the two coverage sections
# share. Both sections drive the REAL intended_surfaces() for the declaration
# and hand-build the measurement, which is the whole point: the two numbers
# have to be able to disagree.
c1_fixture <- function() {
  root <- file.path(tempdir(), "c1-coverage-fixture"); unlink(root, recursive = TRUE)
  dir.create(file.path(root, "docs"), recursive = TRUE)
  writeLines("project:\n  type: default\n", file.path(root, "_quarto.yml"))
  for (nm in c("p1", "p2")) {
    writeLines(sprintf("<html lang='en'><title>%s</title><body>%s</body></html>", nm, nm),
               file.path(root, "docs", paste0(nm, ".html")))
  }
  cart_src <- file.path(tempdir(), "c1-coverage-cart-src")
  unlink(cart_src, recursive = TRUE)
  dir.create(file.path(cart_src, "wiki_content"), recursive = TRUE)
  for (nm in c("w1", "w2")) {
    writeLines(sprintf("<html><body>%s</body></html>", nm),
               file.path(cart_src, "wiki_content", paste0(nm, ".html")))
  }
  dir.create(file.path(root, "reference"), recursive = TRUE)
  zip_a11y_dir(cart_src, file.path(root, "reference", "c1.imscc"))

  declared <- intended_surfaces(root)          # the DECLARATION
  page_sf  <- "c1-coverage-fixture"
  cart_sf  <- "c1-coverage-fixture-cartridge"
  list(
    root     = root,
    declared = declared,
    page_sf  = page_sf,
    cart_sf  = cart_sf,
    empty_df = finding(page_sf, "x", "1.1.1", NA_character_, "x", NA, "serious")[0, ],
    meta     = function(measured) {
      list(date = "2026-08-13", tool = "pa11y@9.1.1",
           pages_examined = as.list(measured),
           declared       = as.list(declared),
           surfaces       = unique(names(declared)),
           failed_pages   = character())
    })
}

# The driver's own code, comment-free, the way the snapshot's structural checks
# read it. width.cutoff is raised so a wrapped call cannot hide a pattern
# across two lines.
driver_code <- function() deparse(audit_course, width.cutoff = 500L)

test_that("negative control: the audit must FAIL on broken input", {
  # Task 8. Every check in the other files proves the audit passes on clean
  # input. None of them proves it fails on broken input, and those two states
  # look identical from outside: both run, both print, both exit zero. This
  # project has hit that shape nine separate times while building this
  # feature. This section, and this section alone, is the check on that.

  # Deliberately broken page: no lang, no title, an unlabelled image, a
  # filename alt, and a contrast failure. A working audit must object to all
  # of it. If this block ever reports zero findings, the audit is not running.
  nc <- file.path(tempdir(), "negctl"); unlink(nc, recursive = TRUE)
  dir.create(nc)
  writeLines(paste0(
    "<html><head><style>.faint{color:#999;background:#fff}</style></head><body>",
    "<img src='a.png'>",
    "<img src='b.png' alt='chart1.png'>",
    "<p class='faint'>low contrast text</p>",
    "<h3>skipped heading level</h3>",
    "</body></html>"), file.path(nc, "broken.html"))

  nc_fa <- check_filename_alt(file.path(nc, "broken.html"), "test", "broken.html")
  expect_identical(nrow(nc_fa) >= 1L, TRUE,
    info = "negative control: filename alt is caught")

  # A clean page must NOT trip the same check. A checker that flags everything
  # is as useless as one that flags nothing, and both pass a "found issues" test.
  writeLines(paste0(
    "<html lang='en'><head><title>ok</title></head><body>",
    "<img src='a.png' alt='A scatterplot of price against mileage'>",
    "</body></html>"), file.path(nc, "clean.html"))
  nc_fc <- check_filename_alt(file.path(nc, "clean.html"), "test", "clean.html")
  expect_identical(nrow(nc_fc), 0L,
    info = "negative control: clean page is not flagged")

  # The source checks must also discriminate.
  ncq <- file.path(tempdir(), "negctlq"); unlink(ncq, recursive = TRUE)
  dir.create(ncq)
  writeLines(c("```{r}", "#| label: fig-x", "#| fig-cap: c", "plot(1)", "```"),
             file.path(ncq, "bad.qmd"))
  expect_identical(
    nrow(check_missing_fig_alt(ncq, "test", exclude = character())) >= 1L, TRUE,
    info = "negative control: missing fig-alt is caught")
  writeLines(c("```{r}", "#| label: fig-y", "#| fig-cap: c",
               "#| fig-alt: A described figure", "plot(1)", "```"),
             file.path(ncq, "bad.qmd"))
  expect_identical(
    nrow(check_missing_fig_alt(ncq, "test", exclude = character())), 0L,
    info = "negative control: described figure is not flagged")

  # Contrast must reject what fails and accept what passes.
  expect_identical(contrast_ratio("#999999", "#ffffff") < 4.5, TRUE,
    info = "negative control: #999 on white is rejected")
  expect_identical(contrast_ratio("#767676", "#ffffff") >= 4.5, TRUE,
    info = "negative control: #767676 on white is accepted")
})

test_that("audit_course refuses no repos and refuses two repos with one basename before serving anything", {
  expect_error(audit_course(character()), "no repo is assumed")
  a <- fixture_path("pair", "alpha"); b <- fixture_path("pair", "other", "alpha")
  expect_error(audit_course(c(a, b), out_dir = withr::local_tempdir()), "same surface")
})

test_that("negative control: pages_examined still catches a zero-finding surface (fresh fixture)", {
  # Repeats the discipline of the pages_examined safeguard proven in
  # test-a11y-report.R, with an independent fixture: a surface entirely missing
  # from pages_examined must be caught even though it produced zero findings
  # and therefore never appears in df at all. df alone cannot reveal this, only
  # meta$surfaces can.
  nc_empty_df <- finding("textbook", "x", "1.1.1", NA_character_, "x", NA, "serious")[0, ]
  nc_rp_missing <- file.path(tempdir(), "report_nc_missing_surface.md")
  render_report(nc_empty_df, list(date = "2026-08-13", tool = "pa11y@9.1.1",
                                  pages_examined = c(textbook = 5L),
                                  surfaces = c("textbook", "cartridge")), nc_rp_missing)
  nc_txt_missing <- paste(readLines(nc_rp_missing, warn = FALSE), collapse = "\n")
  expect_identical(
    grepl("cartridge: no pages_examined entry", nc_txt_missing, fixed = TRUE), TRUE,
    info = "negative control: a zero-finding surface absent from pages_examined is still caught")

  nc_rp_complete <- file.path(tempdir(), "report_nc_complete_surface.md")
  render_report(nc_empty_df, list(date = "2026-08-13", tool = "pa11y@9.1.1",
                                  pages_examined = c(textbook = 5L, cartridge = 3L),
                                  surfaces = c("textbook", "cartridge")), nc_rp_complete)
  nc_txt_complete <- paste(readLines(nc_rp_complete, warn = FALSE), collapse = "\n")
  expect_identical(
    grepl("cartridge: no pages_examined entry", nc_txt_complete, fixed = TRUE), FALSE,
    info = "negative control: a surface genuinely accounted for is not flagged missing")
})

test_that("C1: the coverage cross-check compares two signals from two code paths", {
  skip_if_no("zip")
  # Final whole-branch review, finding C1 (critical), and the twelfth instance
  # of one failure shape in this build: code that runs, prints, exits zero, and
  # verifies less than it appears to.
  #
  # The driver briefly built BOTH pages_examined and meta$surfaces from one
  # intended_surfaces() call. The renderer's coverage cross-check then compared
  # a value against itself and could not fire: comment out the entire cartridge
  # loop and the report still printed the full page count, still declared the
  # cartridge surface, and read as a clean audit.
  #
  # Three assertions, deliberately of three different kinds, because no one of
  # them alone catches a re-merge:
  #
  # 1. STRUCTURAL, against the real driver's own code. This is the only check
  #    that can fail when someone reintroduces `pages_examined <-
  #    intended_surfaces(repos)`, because that line is reachable from no
  #    behaviour a test can drive without a rendered course and a live browser.
  # 2. FUNCTIONAL, driving the real render_report() with the real
  #    intended_surfaces() as the declaration and a hand-built measurement
  #    standing in for a run whose cartridge loop did not execute.
  # 3. UNIT, on bump_examined(), the one increment both driver loops use.
  c1_code <- driver_code()
  expect_identical(
    any(grepl("pages_examined\\s*<-\\s*intended_surfaces", c1_code)), FALSE,
    info = "C1 structural: the driver never derives pages_examined from intended_surfaces()")
  expect_identical(sum(grepl("intended_surfaces\\(", c1_code)), 1L,
    info = "C1 structural: the driver reads intended_surfaces() exactly once, and only for the declaration")
  expect_identical(
    any(grepl("^\\s*declared\\s*<-\\s*intended_surfaces\\(", c1_code)), TRUE,
    info = "C1 structural: that one read is assigned to `declared`, not to the page counter")
  expect_identical(
    sum(grepl("pages_examined\\s*<-\\s*bump_examined\\(", c1_code)) >= 3L, TRUE,
    info = "C1 structural: the driver accumulates pages_examined inside its loops, in more than one place")

  # bump_examined(), the increment itself. `integer(0)[["new"]]` errors and
  # `integer(0)["new"]` is NA, and NA + 1L is NA, so a naive inline increment
  # poisons a surface's count the first time it is seen instead of starting it.
  expect_identical(bump_examined(integer(0), "s", 1L), c(s = 1L),
    info = "C1 unit: a surface seen for the first time starts at the increment, not NA")
  expect_identical(bump_examined(bump_examined(integer(0), "s", 1L), "s", 1L),
                   c(s = 2L),
    info = "C1 unit: repeated increments accumulate")
  expect_identical(bump_examined(integer(0), "s", 0L), c(s = 0L),
    info = "C1 unit: an explicit zero entry is a real, honest 0, not an absent entry")
  expect_identical(bump_examined(c(s = 2L), "s-cartridge", 12L),
                   c(s = 2L, `s-cartridge` = 12L),
    info = "C1 unit: a cartridge's whole page count lands in one increment")

  fx <- c1_fixture()

  # THE PROOF. A run whose cartridge loop never executed: the page loop
  # measured its 2 pages, and nothing ever incremented the cartridge surface.
  c1_neutered <- bump_examined(bump_examined(integer(0), fx$page_sf, 0L),
                               fx$page_sf, 2L)
  c1_rp_neutered <- file.path(tempdir(), "c1_report_neutered.md")
  render_report(fx$empty_df, fx$meta(c1_neutered), c1_rp_neutered)
  c1_txt_neutered <- paste(readLines(c1_rp_neutered, warn = FALSE), collapse = "\n")
  expect_identical(
    grepl(paste0(fx$cart_sf, ": no pages_examined entry"), c1_txt_neutered,
          fixed = TRUE), TRUE,
    info = "C1 proof: a run whose cartridge loop did not execute names the missing surface")
  expect_identical(grepl("INCOMPLETE", c1_txt_neutered, fixed = TRUE), TRUE,
    info = "C1 proof: and refuses to print its page total as if it were complete")
  expect_identical(
    grepl("2 page(s) examined against 4 page(s) this run declared in scope",
          c1_txt_neutered, fixed = TRUE), TRUE,
    info = "C1 proof: and states the measured total against the declared scope")

  # The confirming case: the same declaration, the same renderer, a complete
  # measurement. If the two banners above fired for any reason other than the
  # missing measurement, they would fire here too.
  c1_full <- bump_examined(c1_neutered, fx$cart_sf, 2L)
  c1_rp_full <- file.path(tempdir(), "c1_report_full.md")
  render_report(fx$empty_df, fx$meta(c1_full), c1_rp_full)
  c1_txt_full <- paste(readLines(c1_rp_full, warn = FALSE), collapse = "\n")
  expect_identical(
    grepl("no pages_examined entry", c1_txt_full, fixed = TRUE), FALSE,
    info = "C1 confirming: a complete measurement names no missing surface")
  expect_identical(grepl("INCOMPLETE", c1_txt_full, fixed = TRUE), FALSE,
    info = "C1 confirming: and prints no INCOMPLETE marker")
  expect_identical(
    grepl("4 page(s) examined against 4 page(s) this run declared in scope",
          c1_txt_full, fixed = TRUE), TRUE,
    info = "C1 confirming: and reconciles measured against declared")
  expect_identical(identical(c1_txt_neutered, c1_txt_full), FALSE,
    info = "C1 confirming: and the two reports are not the same document")

  # A partial page loop: every surface has an entry, so the missing-surface
  # banner cannot fire, but pa11y failed on half the pages. The value-level
  # comparison is the only thing that catches this.
  c1_partial <- bump_examined(bump_examined(bump_examined(integer(0), fx$page_sf, 0L),
                                            fx$page_sf, 1L), fx$cart_sf, 2L)
  c1_meta_partial <- fx$meta(c1_partial)
  c1_meta_partial$failed_pages <- paste0(fx$page_sf, "/p2.html")
  c1_rp_partial <- file.path(tempdir(), "c1_report_partial.md")
  render_report(fx$empty_df, c1_meta_partial, c1_rp_partial)
  c1_txt_partial <- paste(readLines(c1_rp_partial, warn = FALSE), collapse = "\n")
  expect_identical(
    grepl("COVERAGE SHORTFALL", c1_txt_partial, fixed = TRUE), TRUE,
    info = "C1: a surface that examined fewer pages than declared reports a shortfall")
  expect_identical(
    grepl(paste0(fx$page_sf, ": 1 of 2 declared page(s) actually examined"),
          c1_txt_partial, fixed = TRUE), TRUE,
    info = "C1: the shortfall names the surface and both numbers")
  expect_identical(
    grepl("Pages the audit tool could not read: 1", c1_txt_partial, fixed = TRUE), TRUE,
    info = "C1: failed pages are reported in the document, not only on a console that scrolls away")
  expect_identical(
    grepl("Pages the audit tool could not read: 0", c1_txt_full, fixed = TRUE), TRUE,
    info = "C1: a run with no failures says so explicitly rather than staying silent")
  c1_rp_nofp <- file.path(tempdir(), "c1_report_nofp.md")
  c1_meta_nofp <- fx$meta(c1_full); c1_meta_nofp$failed_pages <- NULL
  render_report(fx$empty_df, c1_meta_nofp, c1_rp_nofp)
  expect_identical(
    grepl("could not read: not reported by this run",
          paste(readLines(c1_rp_nofp, warn = FALSE), collapse = "\n"),
          fixed = TRUE), TRUE,
    info = "C1: a driver that never reports failures is called out, not assumed clean")
})

test_that("the page count says what it means, where the number is", {
  skip_if_no("zip")
  # A cartridge surface's count is wiki pages READ across every .imscc under
  # that repo. When a repo holds an export and its own round-trip copy, the
  # same page is counted twice. That qualifier used to live only in the audit's
  # own documentation; a reader of the report should not have to open another
  # document to learn what the number means.
  fx <- c1_fixture()
  c1_full <- bump_examined(bump_examined(bump_examined(integer(0), fx$page_sf, 0L),
                                         fx$page_sf, 2L), fx$cart_sf, 2L)
  c1_rp_full <- file.path(tempdir(), "c1_report_full_counts.md")
  render_report(fx$empty_df, fx$meta(c1_full), c1_rp_full)
  c1_txt_full <- paste(readLines(c1_rp_full, warn = FALSE), collapse = "\n")

  c1_meta_cart <- function(n) {
    m <- fx$meta(c1_full)
    m$cartridge_files <- as.list(stats::setNames(as.integer(n), fx$cart_sf))
    m
  }
  # A one-row classified frame, so the document has a "## Findings" section to
  # position the qualifier against: it has to sit with the number, not below
  # the findings where nobody reading the summary would meet it.
  c1_one_row <- classify_fixes(
    finding(fx$cart_sf, "w1.html", "4.1.2", NA_character_, "iframe has no title",
            "iframe[src='x']", "serious"),
    list(stylesheet = NA_character_, framework = NA_character_, repo = NA_character_))
  c1_rp_two <- file.path(tempdir(), "c1_report_two_carts.md")
  render_report(c1_one_row, c1_meta_cart(2L), c1_rp_two)
  c1_txt_two <- paste(readLines(c1_rp_two, warn = FALSE), collapse = "\n")
  expect_identical(
    grepl("count wiki pages READ, not distinct pages", c1_txt_two, fixed = TRUE), TRUE,
    info = "the report states that a cartridge count is pages read, not distinct pages")
  expect_identical(
    grepl(paste0(fx$cart_sf, " spans 2 .imscc file(s)"), c1_txt_two, fixed = TRUE), TRUE,
    info = "and names how many .imscc files the count spans")
  expect_identical(
    grepl("counted once per file", c1_txt_two, fixed = TRUE), TRUE,
    info = "and warns that the same page is counted once per file")
  expect_identical(
    regexpr("count wiki pages READ", c1_txt_two) < regexpr("## Findings", c1_txt_two),
    TRUE,
    info = "the qualifier sits with the number, ahead of the findings")
  c1_rp_one <- file.path(tempdir(), "c1_report_one_cart.md")
  render_report(fx$empty_df, c1_meta_cart(1L), c1_rp_one)
  c1_txt_one <- paste(readLines(c1_rp_one, warn = FALSE), collapse = "\n")
  expect_identical(
    grepl("spans 1 .imscc file(s)", c1_txt_one, fixed = TRUE), TRUE,
    info = "a single cartridge still states what the count is")
  expect_identical(
    grepl("counted once per file", c1_txt_one, fixed = TRUE), FALSE,
    info = "but claims no double count, because there is none")
  expect_identical(
    grepl("count wiki pages READ", c1_txt_full, fixed = TRUE), FALSE,
    info = "a run with no cartridge surface says nothing about cartridges")
})

test_that("the driver's exclusion and its collision halt are really wired up", {
  # The three hand-offs this file was named in. Every assertion here reads the
  # driver's own code, which is why they waited for the driver to move.
  #
  # From the pass-through-exclusion section (test-a11y-targets.R): the driver
  # passes a UNION of two discovery-derived lists, resource_dirs (copied
  # verbatim, never rendered) and unproduced_sources (renders to no page, so
  # never produced to students). Both must be present. These prove the
  # exclusion comes from discovery rather than from a course name written into
  # package code, so they assert both sources and that no course directory is
  # named.
  c1_code <- driver_code()
  expect_identical(any(grepl("tgt\\$resource_dirs", c1_code)), TRUE,
    info = "I5x: the driver builds the exclusion from discovery's resource_dirs")
  expect_identical(any(grepl("tgt\\$unproduced_sources", c1_code)), TRUE,
    info = "I5x: and from discovery's unproduced_sources")
  expect_identical(any(grepl("exclude = src_exclude", c1_code)), TRUE,
    info = "I5x: and passes that union, not one of them alone")
  # EXECUTABLE lines only, which is what deparsing gives. Comments in this
  # codebase cite real directories as evidence by convention, which is the
  # opposite of a problem. What must never happen is a course's directory name
  # reaching a line that RUNS.
  expect_identical(any(grepl("lecture_notes", c1_code)), FALSE,
    info = "I5x: nor in the driver's executable lines")

  # From the dedup collision negative control (test-a11y-model.R): static
  # coupling to the real driver, proving it actually CALLS the shared function
  # on its real findings frame, rather than, say, retaining an inert import of
  # it while some other code path builds the report. If a future edit made that
  # call unreachable (e.g. moved behind a flag that defaults off), this fails
  # independently of the behavioral proof in test-a11y-model.R, which only
  # exercises halt_on_collision() itself and could not detect that the driver
  # stopped calling it at all.
  expect_identical(
    grepl("full_df <- halt_on_collision(full_df)",
          paste(c1_code, collapse = "\n"), fixed = TRUE), TRUE,
    info = "negative control: the driver actually calls halt_on_collision() on its findings")
})
