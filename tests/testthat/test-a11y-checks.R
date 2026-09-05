# Ported from the snapshot's own self-checking audit test script: the
# custom-check sections. Each printed banner there is a test_that() block here
# and each check() is an expectation carrying the original label. Two sections
# rebuild a fixture the snapshot had built in an earlier section and reused,
# since a test_that() block owns its own fixtures; nothing about the
# assertions changed.

test_that("contrast", {
  expect_identical(round(contrast_ratio("#ffffff", "#ffffff"), 2), 1,
    info = "white on white is 1")
  expect_identical(round(contrast_ratio("#000000", "#ffffff"), 2), 21,
    info = "black on white is 21")
  expect_identical(round(contrast_ratio("#999999", "#ffffff"), 2), 2.85,
    info = "#999 on white fails")

  sug <- suggest_passing_colour("#999999", "#ffffff", 4.5)
  expect_identical(contrast_ratio(sug, "#ffffff") >= 4.5, TRUE,
    info = "suggestion passes")
  expect_identical(grepl("^#[0-9a-f]{6}$", sug), TRUE,
    info = "suggestion is a hex")

  # The walk used to commit to one direction from a heuristic that could pick
  # "toward black" even when the background was itself dark, so a passing
  # colour on the other side went undiscovered. Demonstrated case: #1a1a1a on
  # #4d4d4d. Toward black tops out at about 2.48, short of 4.5; toward white
  # reaches about 8.45. The old code never tried white.
  sug_dark <- suggest_passing_colour("#1a1a1a", "#4d4d4d", 4.5)
  expect_identical(is.na(sug_dark), FALSE,
    info = "dark-on-dark: a passing colour is found, not NA")
  expect_identical(contrast_ratio(sug_dark, "#4d4d4d") >= 4.5, TRUE,
    info = "dark-on-dark: the suggestion actually clears the target")

  # The early-return branch used to hand back the caller's original string
  # verbatim (any case, 3 or 6 digits) while the walking branch always
  # normalized. Both branches must agree.
  expect_identical(suggest_passing_colour("#fff", "#000000", 4.5), "#ffffff",
    info = "early-return normalizes a 3-digit hex that already passes")
  expect_identical(suggest_passing_colour("#ABCDEF", "#000000", 4.5), "#abcdef",
    info = "early-return normalizes an uppercase hex that already passes")
})

test_that("filename-as-alt", {
  h <- file.path(tempdir(), "alt.html")
  writeLines(paste0(
    "<html lang='en'><body>",
    "<img src='a.png' alt='chart1.png'>",
    "<img src='b.png' alt='A scatterplot of price against mileage'>",
    "<img src='c.png' alt='IMG_2841.JPG'>",
    "</body></html>"), h)
  fa <- check_filename_alt(h, "textbook", "alt.html")
  expect_identical(nrow(fa), 2L, info = "flags two filename alts")
  expect_identical(unique(fa$criterion), "1.1.1", info = "criterion is 1.1.1")

  # Discrimination: a corpus with no filename-style alt text must produce zero
  # findings. Without this, a check that always returns a finding would still
  # pass the block above, and only a clean-input case can catch that.
  h_clean <- file.path(tempdir(), "alt-clean.html")
  writeLines(paste0(
    "<html lang='en'><body>",
    "<img src='a.png' alt='A scatterplot of price against mileage'>",
    "<img src='b.png' alt='Distribution of residuals by group'>",
    "</body></html>"), h_clean)
  fa_clean <- check_filename_alt(h_clean, "textbook", "alt-clean.html")
  expect_identical(nrow(fa_clean), 0L, info = "clean alt text produces zero findings")
})

test_that("missing fig-alt", {
  qr <- file.path(tempdir(), "qmdrepo"); unlink(qr, recursive = TRUE); dir.create(qr)
  writeLines(c(
    "---", "title: t", "---",
    "```{r}",
    "#| label: fig-good",
    "#| fig-cap: Good",
    "#| fig-alt: A described figure",
    "plot(1:10)",
    "```",
    "",
    "```{r}",
    "#| label: fig-bare",
    "#| fig-cap: Bare",
    "plot(1:10)",
    "```"), file.path(qr, "ch1.qmd"))
  mf <- check_missing_fig_alt(qr, "textbook", exclude = character())
  expect_identical(nrow(mf), 1L, info = "one chunk missing fig-alt")
  expect_identical(grepl("fig-bare", mf$detail[1]), TRUE, info = "names the bare chunk")

  # Discrimination: a repo where every figure chunk carries fig-alt must
  # produce zero findings, ruling out a check that flags every
  # figure-producing chunk regardless of whether fig-alt is present.
  qr_clean <- file.path(tempdir(), "qmdrepo_clean"); unlink(qr_clean, recursive = TRUE)
  dir.create(qr_clean)
  writeLines(c(
    "---", "title: t", "---",
    "```{r}",
    "#| label: fig-one",
    "#| fig-cap: One",
    "#| fig-alt: A fully described figure",
    "plot(1:10)",
    "```"), file.path(qr_clean, "ch1.qmd"))
  mf_clean <- check_missing_fig_alt(qr_clean, "textbook", exclude = character())
  expect_identical(nrow(mf_clean), 0L,
    info = "every chunk described produces zero findings")
})

test_that("missing fig-alt: rendered mode vs source-heuristic fallback", {
  # The pre-fix heuristic identified a "figure chunk" only by fig-cap or a
  # "fig-" label prefix, so a chunk that renders a real image under any other
  # name, the review's own motivating case of a chunk named
  # resid-vs-fitted-illustration, was invisible to it. Both fixtures below
  # share one source file: a chunk labelled like the motivating case (no
  # fig-cap, no "fig-" prefix), a bare unlabelled chunk, and an
  # already-described chunk that must never be flagged either way.
  fig_alt_source <- c(
    "---", "title: t", "---",
    "```{r}",
    "#| label: resid-vs-fitted-illustration",
    "plot(1:10)",
    "```",
    "",
    "```{r}",
    "plot(1:5)",
    "```",
    "",
    "```{r}",
    "#| label: fig-described",
    "#| fig-cap: Described",
    "#| fig-alt: A fully described figure",
    "plot(1:3)",
    "```")

  # Rendered mode: a real _files/figure-html directory exists, so detection is
  # keyed on actual PNGs rather than guessed from the label's spelling.
  qr_rendered <- file.path(tempdir(), "qmdrepo_rendered"); unlink(qr_rendered, recursive = TRUE)
  dir.create(qr_rendered)
  writeLines(fig_alt_source, file.path(qr_rendered, "ch1.qmd"))
  render_dir <- file.path(qr_rendered, "ch1_files", "figure-html")
  dir.create(render_dir, recursive = TRUE)
  writeLines("png", file.path(render_dir, "resid-vs-fitted-illustration-1.png"))
  # Verified live against `quarto render`: the bare chunk above is the first
  # unlabelled chunk in the document, so knitr names it unnamed-chunk-1 even
  # though it is the second chunk overall. The labelled chunk ahead of it does
  # not consume a slot in the counter.
  writeLines("png", file.path(render_dir, "unnamed-chunk-1-1.png"))
  writeLines("png", file.path(render_dir, "fig-described-1.png"))

  mf_rendered <- check_missing_fig_alt(qr_rendered, "textbook", exclude = character())
  expect_identical(any(grepl("resid-vs-fitted-illustration", mf_rendered$detail)), TRUE,
    info = "rendered mode: catches a labelled chunk with no fig-cap and no fig- prefix")
  expect_identical(any(grepl("unnamed-chunk-1\\b", mf_rendered$detail)), TRUE,
    info = "rendered mode: catches the unlabelled chunk via unnamed-chunk numbering")
  expect_identical(any(grepl("fig-described", mf_rendered$detail)), FALSE,
    info = "rendered mode: the already-described chunk is not flagged")
  expect_identical(nrow(mf_rendered), 2L,
    info = "rendered mode: exactly the two undescribed rendered chunks")
  expect_identical(attr(mf_rendered, "mode"), "rendered",
    info = "rendered mode is reported on the result")

  # Same source, no render step taken: nothing to cross-reference, so
  # detection falls back to a plotting-call scan. It must still catch what the
  # rendered check catches. The point is that neither mode goes silent.
  qr_heuristic <- file.path(tempdir(), "qmdrepo_heuristic"); unlink(qr_heuristic, recursive = TRUE)
  dir.create(qr_heuristic)
  writeLines(fig_alt_source, file.path(qr_heuristic, "ch1.qmd"))

  mf_heuristic <- check_missing_fig_alt(qr_heuristic, "textbook", exclude = character())
  expect_identical(any(grepl("resid-vs-fitted-illustration", mf_heuristic$detail)), TRUE,
    info = "fallback mode: still catches a plot() call regardless of label spelling")
  expect_identical(any(grepl("unnamed-chunk-1\\b", mf_heuristic$detail)), TRUE,
    info = "fallback mode: also catches the unlabelled plot() chunk")
  expect_identical(any(grepl("fig-described", mf_heuristic$detail)), FALSE,
    info = "fallback mode: the already-described chunk is not flagged")
  expect_identical(nrow(mf_heuristic), 2L,
    info = "fallback mode: exactly the two undescribed chunks with a plot call")
  expect_identical(attr(mf_heuristic, "mode"), "source-heuristic",
    info = "fallback mode is reported on the result")
})

test_that("colour-only", {
  # The snapshot wrote ch2.qmd into the two repos the missing fig-alt section
  # had already built. Those repos are rebuilt here, identically, because a
  # test block owns its own fixtures.
  qr <- file.path(tempdir(), "qmdrepo_colour"); unlink(qr, recursive = TRUE); dir.create(qr)
  writeLines(c(
    "---", "title: t", "---",
    "```{r}",
    "#| label: fig-good",
    "#| fig-cap: Good",
    "#| fig-alt: A described figure",
    "plot(1:10)",
    "```",
    "",
    "```{r}",
    "#| label: fig-bare",
    "#| fig-cap: Bare",
    "plot(1:10)",
    "```"), file.path(qr, "ch1.qmd"))
  writeLines(c(
    "```{r}",
    "ggplot(d, aes(x, y, colour = grp)) + geom_line()",
    "```",
    "```{r}",
    "ggplot(d, aes(x, y, colour = grp, linetype = grp)) + geom_line()",
    "```"), file.path(qr, "ch2.qmd"))
  co <- check_colour_only(qr, "textbook", exclude = character())
  expect_identical(nrow(co), 1L, info = "flags colour-only once")
  expect_identical(co$criterion[1], "1.4.1", info = "criterion is 1.4.1")
  expect_identical(co$severity[1], "review", info = "routed to human")

  # Discrimination: every series in this file carries a second channel (shape,
  # linetype), so a check that flags any colour= or fill= aesthetic while
  # ignoring whether a second channel is present must be ruled out by a
  # zero-finding result here.
  qr_clean <- file.path(tempdir(), "qmdrepo_colour_clean"); unlink(qr_clean, recursive = TRUE)
  dir.create(qr_clean)
  writeLines(c(
    "---", "title: t", "---",
    "```{r}",
    "#| label: fig-one",
    "#| fig-cap: One",
    "#| fig-alt: A fully described figure",
    "plot(1:10)",
    "```"), file.path(qr_clean, "ch1.qmd"))
  writeLines(c(
    "```{r}",
    "ggplot(d, aes(x, y, colour = grp, shape = grp)) + geom_point()",
    "```",
    "```{r}",
    "ggplot(d, aes(x, y, fill = grp, linetype = grp)) + geom_area()",
    "```"), file.path(qr_clean, "ch2.qmd"))
  co_clean <- check_colour_only(qr_clean, "textbook", exclude = character())
  expect_identical(nrow(co_clean), 0L,
    info = "every series has a second channel produces zero findings")
})

test_that("I5: the source checks are not blind on a course shaped differently", {
  # Both source-layer checks globbed a non-recursive, .qmd-only file list. A
  # Quarto book with chapters in a subdirectory, or any bookdown or .Rmd
  # course, yielded zero fig-alt and zero colour-only findings with no warning
  # at all, while discovery next door explicitly supports bookdown.
  i5_root <- file.path(tempdir(), "i5-nested-course"); unlink(i5_root, recursive = TRUE)
  dir.create(file.path(i5_root, "chapters"), recursive = TRUE)
  writeLines(c("```{r nested-r-fig}", "ggplot(d, aes(x, y)) + geom_point()", "```"),
             file.path(i5_root, "chapters", "ch1.qmd"))
  writeLines(c("```{r bookdown-fig}", "plot(x, y)", "```"),
             file.path(i5_root, "chapters", "ch2.Rmd"))
  writeLines(c("```{python py-fig}", "plt.scatter(x, y)", "```"),
             file.path(i5_root, "chapters", "ch3.qmd"))
  writeLines(c("```{python sns-fig}", "sns.boxplot(data=df)", "```"),
             file.path(i5_root, "chapters", "ch4.qmd"))
  writeLines(c("```{python pandas-fig}", "df.plot(kind='bar')", "```"),
             file.path(i5_root, "chapters", "ch5.qmd"))
  writeLines(c("```{r no-figure-here}", "summary(model)", "```"),
             file.path(i5_root, "chapters", "ch6.qmd"))
  # Build output, which must not be scanned as if it were source.
  dir.create(file.path(i5_root, "docs"), recursive = TRUE)
  writeLines(c("```{r rendered-copy}", "ggplot(d, aes(x, y)) + geom_point()", "```"),
             file.path(i5_root, "docs", "ch1.qmd"))

  i5_files <- source_files_for_checks(i5_root, exclude = character())
  expect_identical(length(i5_files) >= 6L, TRUE,
    info = "I5: nested sources are found at all")
  expect_identical(any(grepl("ch2\\.Rmd$", i5_files)), TRUE,
    info = "I5: .Rmd counts as source, not just .qmd")
  expect_identical(any(grepl("/docs/", i5_files)), FALSE,
    info = "I5: a copy under docs/ is not scanned as source")

  i5_fig <- check_missing_fig_alt(i5_root, "i5", exclude = character())
  expect_identical(any(grepl("nested-r-fig", i5_fig$selector)), TRUE,
    info = "I5: the R figure chunk in a subdirectory is found")
  expect_identical(any(grepl("bookdown-fig", i5_fig$selector)), TRUE,
    info = "I5: the bookdown .Rmd figure chunk is found")
  expect_identical(any(grepl("py-fig", i5_fig$selector)), TRUE,
    info = "I5: a matplotlib figure chunk is found (Python is first-class in this project)")
  expect_identical(any(grepl("sns-fig", i5_fig$selector)), TRUE,
    info = "I5: a seaborn figure chunk is found")
  expect_identical(any(grepl("pandas-fig", i5_fig$selector)), TRUE,
    info = "I5: a pandas .plot() figure chunk is found")
  expect_identical(any(grepl("no-figure-here", i5_fig$selector)), FALSE,
    info = "I5: a chunk that renders no figure is still not flagged")
  expect_identical(nrow(i5_fig), 5L,
    info = "I5: five figure chunks, five findings, no double count from the docs/ copy")

  # A repo with no .qmd or .Rmd at all must say so. A check that scanned
  # nothing and a check that found nothing must never read the same.
  i5_bare <- file.path(tempdir(), "i5-no-sources"); unlink(i5_bare, recursive = TRUE)
  dir.create(i5_bare, recursive = TRUE)
  writeLines("<html><body>a hand-written page</body></html>",
             file.path(i5_bare, "index.html"))
  i5_zero_fig <- check_missing_fig_alt(i5_bare, "i5-bare", exclude = character())
  i5_zero_col <- check_colour_only(i5_bare, "i5-bare", exclude = character())
  expect_identical(nrow(i5_zero_fig), 1L,
    info = "I5: a repo with no source files yields a LOUD row from the fig-alt check")
  expect_identical(grepl("examined NOTHING", i5_zero_fig$issue[1], fixed = TRUE), TRUE,
    info = "I5: which says nothing was examined, in those words")
  expect_identical(nrow(i5_zero_col), 1L,
    info = "I5: the colour-only check says the same, separately")
  expect_identical(length(unique(c(i5_zero_fig$id, i5_zero_col$id))), 2L,
    info = "I5: and the two rows do not collide into one id")
  expect_identical(any(grepl("examined NOTHING", i5_fig$issue, fixed = TRUE)), FALSE,
    info = "I5: a repo that DOES have sources emits no such row")
})

test_that("containment: assessment sources are never scanned", {
  # Making the scan recursive pulled assessment sources into scope, and
  # check_colour_only() copies raw source lines into `detail` and `code`,
  # which land in the committed findings JSON and markdown. Nothing leaked,
  # but answer-key material must not accumulate in artifacts by accident. It
  # costs nothing: assessment sources are never rendered to HTML by design, so
  # they have no accessibility surface and a finding against one could never
  # be acted on.
  ct_root <- file.path(tempdir(), "containment-repo"); unlink(ct_root, recursive = TRUE)
  dir.create(file.path(ct_root, "assessments"), recursive = TRUE)
  writeLines(c("```{r public-fig}", "ggplot(d, aes(colour = grp)) + geom_line()", "```"),
             file.path(ct_root, "ch1.qmd"))
  writeLines(c("```{r answer-key-fig}",
               "ggplot(secret, aes(colour = correct_answer)) + geom_line()", "```"),
             file.path(ct_root, "assessments", "quiz01.qmd"))

  ct_scanned <- source_files_for_checks(ct_root, exclude = character())
  expect_identical(any(grepl("assessments", ct_scanned)), FALSE,
    info = "containment: assessments/ is excluded even when the caller excludes nothing")
  ct_fig <- check_missing_fig_alt(ct_root, "ct", exclude = character())
  ct_col <- check_colour_only(ct_root, "ct", exclude = character())
  expect_identical(any(grepl("quiz01", ct_fig$file)), FALSE,
    info = "containment: no fig-alt finding names an assessment source")
  expect_identical(any(grepl("quiz01", ct_col$file)), FALSE,
    info = "containment: no colour-only finding does either")
  expect_identical(
    any(grepl("correct_answer", c(ct_col$detail, ct_col$code, ct_fig$detail))), FALSE,
    info = "containment: and no answer-key source line is copied into any finding column")
  expect_identical(
    c(any(grepl("public-fig", ct_fig$selector)), nrow(ct_col)), c(TRUE, 1L),
    info = "containment: the published chunk is still reported, so this is not a blanket skip")
})
