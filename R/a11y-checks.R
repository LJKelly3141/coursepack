# The four things pa11y cannot do, plus the contrast maths it stops short of.
#
# axe reports "2.85:1, fails" and leaves you to find a colour that works.
# Computing the replacement is the difference between a finding a TA can act
# on and one they have to research.
#
# NOTHING here defaults to any one course's path. Every check takes a repo
# or a file path as an argument, exactly like target discovery.
#
# level is deliberately left NA on every finding() call below, not "A" or
# "AA". The finding model's pa11y_level() explains why: this project cannot
# derive a verified WCAG level from its own invocation, and a criterion-to-
# level lookup is planned for the reporting stage, not here. Inventing a
# level at check-authoring time would be exactly the guess that comment
# warns against, just moved one file over.

# ---- contrast ------------------------------------------------------------
# WCAG relative luminance. The 0.03928 branch is in the spec; do not simplify
# it to a plain 2.2 gamma, the results differ near black.
rel_luminance <- function(hex) {
  hex <- gsub("^#", "", tolower(hex))
  if (nchar(hex) == 3) hex <- paste0(rep(strsplit(hex, "")[[1]], each = 2), collapse = "")
  rgb <- strtoi(substring(hex, c(1, 3, 5), c(2, 4, 6)), 16L) / 255
  f <- function(c) if (c <= 0.03928) c / 12.92 else ((c + 0.055) / 1.055)^2.4
  s <- vapply(rgb, f, numeric(1))
  0.2126 * s[1] + 0.7152 * s[2] + 0.0722 * s[3]
}

#' WCAG contrast ratio between two colours
#'
#' The ratio WCAG 2.1 defines for success criterion 1.4.3, computed from
#' relative luminance. Black on white is 21, white on white is 1.
#'
#' @param hex_fg,hex_bg Hex colours, with or without the leading `#`, in
#'   3-digit or 6-digit form, any case.
#' @return The contrast ratio, a number between 1 and 21.
#' @examples
#' contrast_ratio("#000000", "#ffffff")   # 21, the maximum
#' contrast_ratio("#999", "#fff")         # 2.85, under the 4.5 AA threshold
#' contrast_ratio("#767676", "#FFF")      # short form and case do not matter
#' @export
contrast_ratio <- function(hex_fg, hex_bg) {
  l1 <- rel_luminance(hex_fg); l2 <- rel_luminance(hex_bg)
  (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
}

# 6-digit lowercase, "#" prefixed. Used so every hex this file hands back to a
# caller, whether it already passed or was walked to a new value, looks
# the same, rather than the early-return branch echoing back whatever case or
# length the caller happened to pass in.
normalize_hex <- function(hex) {
  hex <- gsub("^#", "", tolower(hex))
  if (nchar(hex) == 3) hex <- paste0(rep(strsplit(hex, "")[[1]], each = 2), collapse = "")
  paste0("#", hex)
}

# NOT WIRED INTO THE AUDIT, and that is a measured conclusion rather than an
# oversight. Recorded 2026-08-13, final whole-branch review, finding I3.
#
# The claim this function was written to support ("a finding reads as an
# action: #999 on white = 2.85:1, use #767676 = 4.54:1") needs a
# (foreground, background) PAIR. Neither engine gives one through pa11y's
# JSON reporter. Verified against a real dual-runner invocation of a real
# chapter page on 2026-08-13, not assumed:
#
# - axe-core's color-contrast issue arrives as message "Elements must meet
#   minimum color contrast ratio thresholds (<helpUrl>)" with fields code,
#   type, typeCode, message, context, selector, runner, runnerExtras
#   (description/impact/needsFurtherReview/help/helpUrl). No colours, and no
#   ratio either. axe-core computes both internally, in its own
#   `any[].data`/failureSummary, and pa11y's reporter does not surface them.
# - HTML_CodeSniffer's own contrast message DOES carry the measured ratio and
#   its own recommended replacement ("...has a contrast ratio of 4.31:1.
#   Recommendation: change text colour to #4455a8."), but still no
#   foreground/background pair, and its recommendation is already computed,
#   so there is nothing here left to compute.
#
# Wiring it anyway would mean inventing a background colour, which is the
# exact class of confident-wrong-answer this project keeps removing. The
# claim was therefore withdrawn from the audit's own documentation instead. The
# function stays, tested, because it is correct and the moment a runner that
# exposes the real colour pair is added (axe-core invoked directly rather
# than through pa11y's reporter) it is what turns that pair into an action.
# It is not called from any audit path today; do not describe it as one of
# the custom checks.
#
# Walks the foreground toward black AND toward white and returns whichever
# reaches the target in fewer steps (i.e. is nearer the original colour).
#
# Fixed 2026-08-13, quality review: the previous version picked ONE direction
# up front from a heuristic (rel_luminance(bg) > rel_luminance(fg) OR
# rel_luminance(bg) > 0.5) and only ever walked that way. Demonstrated bug:
# suggest_passing_colour("#1a1a1a", "#4d4d4d", 4.5) returned NA. #4d4d4d is
# itself fairly dark (luminance ~0.074), so the first clause of the OR fired
# and picked "toward black" even though walking toward black from #1a1a1a
# tops out at #000000 vs #4d4d4d, a ratio of ~2.48, short of 4.5. Walking
# toward white instead reaches ~8.45 easily. The heuristic never got a chance
# to try that direction. Telling a caller no fix exists when one does is
# worse than staying silent, since the entire point of this function is
# turning a finding into an action; the fix is to just try both directions
# and take whichever actually works, preferring the nearer one when both do.
#' A nearby foreground colour that clears a contrast target
#'
#' Walks the foreground toward black and toward white and returns whichever
#' reaches the target in fewer steps, so the answer is the passing colour
#' nearest the original. Returns the normalized original when it already
#' passes, and `NA` when neither direction reaches the target.
#'
#' Not wired into the audit, and that is a measured conclusion rather than an
#' oversight: turning a contrast finding into an action needs a foreground and
#' background PAIR, and neither engine surfaces one through pa11y's JSON
#' reporter. Wiring it anyway would mean inventing a background colour. The
#' function stays because it is correct and because the moment a runner that
#' exposes the real pair is added, this is what turns that pair into an
#' action.
#'
#' @param hex_fg,hex_bg Hex colours, with or without the leading `#`.
#' @param target Contrast ratio to reach. 4.5 is WCAG AA for body text.
#' @return A 6-digit lowercase hex string, or `NA_character_`.
#' @examples
#' # A grey that fails on white, and the nearest grey that does not.
#' contrast_ratio("#999999", "#ffffff")
#' fixed <- suggest_passing_colour("#999999", "#ffffff")
#' fixed
#' contrast_ratio(fixed, "#ffffff")
#'
#' # A colour that already clears the target comes back normalized, unchanged.
#' suggest_passing_colour("#000", "#fff")
#'
#' # Walking toward white is tried too, so a dark foreground on a mid grey
#' # still gets an answer.
#' suggest_passing_colour("#1a1a1a", "#4d4d4d")
#' @export
suggest_passing_colour <- function(hex_fg, hex_bg, target = 4.5) {
  hex_fg <- normalize_hex(hex_fg)
  if (contrast_ratio(hex_fg, hex_bg) >= target) return(hex_fg)
  rgb <- strtoi(substring(gsub("^#", "", hex_fg), c(1, 3, 5), c(2, 4, 6)), 16L)

  walk <- function(toward_black) {
    for (step in 1:255) {
      rgb2 <- if (toward_black) pmax(rgb - step, 0) else pmin(rgb + step, 255)
      cand <- sprintf("#%02x%02x%02x", rgb2[1], rgb2[2], rgb2[3])
      if (contrast_ratio(cand, hex_bg) >= target) return(list(hex = cand, step = step))
    }
    NULL
  }

  candidates <- Filter(Negate(is.null), list(walk(TRUE), walk(FALSE)))
  if (!length(candidates)) return(NA_character_)
  steps <- vapply(candidates, function(c) c$step, numeric(1))
  candidates[[which.min(steps)]]$hex
}

# ---- filename-as-alt -----------------------------------------------------
# axe reports a MISSING alt. It does not report alt="chart1.png", which is
# present, useless, and read aloud to a screen reader user verbatim.
FILENAME_ALT <- "^[^ ]+\\.(png|jpe?g|gif|svg|webp|bmp|tiff?)$"

# Amended 2026-08-13, coordinator review after Task 7's acceptance run: every
# finding() call in this file is a candidate for the SAME id-collision class
# that silently dropped 30 of 40 real check_missing_fig_alt() findings (see
# that function below). This one was audited too: `selector` is built from
# the matched `alt` VALUE alone (`sprintf("img[alt='%s']", a)`), so two
# DIFFERENT <img> elements on the same page that happen to carry the
# identical bad alt text (two different screenshots both literally saved and
# referenced as "image1.png", not a hypothetical) would still collide on id
# even though they are two real, distinct elements needing two independent
# fixes. `code` now carries the full matched `<img ...>` tag text, which
# almost always differs even when the alt value alone does not (the tag also
# contains `src=`, and two different images essentially never share a `src`
# on the same page), closing the gap the same way `check_missing_fig_alt()`
# below closes it: with real content that identifies THIS element, not a
# position that could shift.
#' Flag alt text that is really a filename
#'
#' axe reports a MISSING alt. It does not report `alt="chart1.png"`, which is
#' present, useless, and read aloud to a screen reader user verbatim.
#'
#' @param html_path Path to one rendered HTML page.
#' @param surface Surface this page belongs to. Required, so two courses'
#'   findings can never merge.
#' @param rel The page's path relative to its output directory, as it should
#'   appear in the report.
#' @return A findings data frame, empty when the page is clean.
#' @examples
#' page <- tempfile(fileext = ".html")
#' writeLines(c(
#'   "<p>Two figures on one page.</p>",
#'   "<img src='fig/a.png' alt='chart1.png'>",
#'   "<img src='fig/b.png' alt='Enrolment by term, rising since 2019'>"), page)
#'
#' found <- check_filename_alt(page, surface = "demo", rel = "chapter1.html")
#' nrow(found)          # only the filename alt is reported
#' found$detail
#'
#' unlink(page)
#' @export
check_filename_alt <- function(html_path, surface, rel) {
  txt  <- paste(readLines(html_path, warn = FALSE), collapse = "\n")
  alts <- stringr::str_match_all(txt, "<img[^>]*\\salt=[\"']([^\"']*)[\"']")[[1]]
  if (!nrow(alts)) return(finding("x","x","x","x","x","x","x")[0, ])
  keep <- grepl(FILENAME_ALT, alts[, 2], ignore.case = TRUE)
  if (!any(keep)) return(finding("x","x","x","x","x","x","x")[0, ])
  bad_tag <- alts[keep, 1, drop = TRUE]  # full matched "<img ...>" text
  bad_alt <- alts[keep, 2, drop = TRUE]  # just the alt value
  do.call(rbind, Map(function(tag, a) finding(
    surface = surface, file = rel, criterion = "1.1.1", level = NA_character_,
    issue = "alt text is a filename, which is announced verbatim and conveys nothing",
    selector = sprintf("img[alt='%s']", a), severity = "serious",
    detail = sprintf("alt=\"%s\"", a), source = "custom", code = tag),
    bad_tag, bad_alt))
}

# ---- fig-alt missing at source -------------------------------------------
#
# Rewritten 2026-08-13, quality review, finding 1 (critical). The original
# version identified a "figure-producing chunk" by whether it carried a
# fig-cap or a label starting with "fig-". That conflates "the author gave
# this a caption or a cross-reference" with "this chunk renders an image".
# They are different, and most of a real book's rendered, alt-less figures
# are the second without being the first. Quantified against one real book
# repo: its output directory held 65 rendered figure-html PNGs (49 once the
# 16 under the project's own `resources:` copy of a working-notes directory
# are excluded, since those were never rendered by its 21 chapters and target
# discovery already excludes their HTML pages for the same reason), and the
# old heuristic covered only 13 of them. Two real chunks in one chapter
# rendered confirmed alt-less PNGs but were invisible to it, because neither
# set fig-cap and neither label started with "fig-".
#
# The fix keys detection on whether a chunk ACTUALLY RENDERS AN IMAGE,
# checked two ways, and the return value says which way ran (see `mode`
# below). A caller must never be unable to tell "cross-referenced real
# figures" from "guessed from source patterns because nothing was rendered",
# which is the silent-ambiguity failure this project keeps hitting.
#
# 1. RENDERED (preferred): Quarto/knitr name a chunk's figure output
#    predictably, verified against a live `quarto render` probe on 2026-08-13:
#    "<qmd-stem>_files/figure-html/<label-or-unnamed-chunk-N>-<n>.png". When
#    that directory exists for a given .qmd, its PNGs are enumerated and
#    mapped back to source chunks by name, and only THOSE chunks are checked
#    for fig-alt. This verifies a real image exists rather than inferring one,
#    and it does not care whether the chunk has a caption or a "fig-" label,
#    since a real PNG is real evidence regardless of what the author called it.
# 2. SOURCE-HEURISTIC (fallback, unrendered repos): a chunk counts as
#    figure-producing if it calls one of ggplot(, plot(, autoplot(, qplot(,
#    hist(, boxplot(, barplot(, curve(, image(, OR still carries a fig-cap /
#    fig- label (kept as an extra signal, not a replacement, so an unusual
#    plotting call that isn't in the list but does carry a caption is still
#    caught).
#
# Both modes share one chunk parser so a chunk's identity (its "ident": an
# explicit label, or an auto-assigned "unnamed-chunk-N") is computed the same
# way regardless of which mode is checking it. A label can arrive two ways,
# verified against real chunks in a real chapter: Quarto's own
# `#| label: xyz` chunk option, and the classic R Markdown inline
# `{r xyz}` / `{r xyz, opt=val}` form. A parser that only read `#| label:`
# would miss every inline-labelled chunk, a different gap from the one this
# rewrite closes but caught by the same fix. For a chunk with no label of
# either kind, the "unnamed-chunk-N" auto-name is assigned by counting
# unlabelled chunks in document order. Verified live: `quarto render` on a
# 5-chunk probe with 3 unlabelled chunks interleaved with 2 labelled ones
# produced unnamed-chunk-1, -2, -3 in that document order, confirming the
# counter increments only for unlabelled chunks and skips labelled ones
# entirely, which is what makes the PNG-filename map reliable.
#
# Amended 2026-08-13, final whole-branch review, finding I5 (important). This
# pattern was R-only while this project declares R and Python both
# first-class and shows code to students in both, so a Python chunk that
# renders a real figure was invisible to the source-heuristic mode
# entirely, a silent zero, the failure shape this build kept producing.
# matplotlib and seaborn calls are added: any `plt.`/`pyplot.`/`sns.`/
# `seaborn.` method call, plus a bare `.plot(` (pandas' own
# `df.plot(...)`/`series.plot.bar(...)` accessor, which is how most
# pandas-first course code draws). `.plot(` is deliberately narrow enough to
# need the dot: it does not match R's `plot(`, which the R alternation above
# already covers on its own.
PLOT_CALL_RE     <- paste0(
  "\\b(ggplot|plot|autoplot|qplot|hist|boxplot|barplot|curve|image)\\s*\\(",
  "|\\b(plt|pyplot|sns|seaborn)\\.[A-Za-z_][A-Za-z0-9_.]*\\s*\\(",
  "|\\.plot\\s*\\(")
CHUNK_HEADER_RE  <- "^```\\{[a-zA-Z]+([^}]*)\\}"

# ---- which source files the two source-layer checks scan -------------------
#
# Fixed 2026-08-13, final whole-branch review, finding I5 (important).
# check_missing_fig_alt() and check_colour_only() both used
# `list.files(repo, pattern = "\\.qmd$", full.names = TRUE)`: NOT recursive,
# and `.qmd` only. Consequences, both silent:
#
# - A Quarto book whose chapters live in a subdirectory (chapters/, parts/,
#   the default for several book templates) yielded ZERO source files and
#   therefore zero fig-alt and zero colour-only findings, with no warning.
#   A course with every figure missing alt text and a course with perfect alt
#   text produced the identical output: nothing.
# - Any bookdown or R Markdown course yielded the same zero, because none of
#   its sources are named `.qmd`. Target discovery explicitly detects and
#   supports bookdown (detect_framework(), find_output_dir(),
#   bookdown_stylesheet_candidates()), so the source layer being
#   Quarto-only contradicted the discovery layer sitting next to it.
#
# Now recursive, and `.qmd` or `.Rmd`. Recursion needs an exclusion list, or
# a rendered/vendored copy of a source file gets scanned as if it were the
# source: the paths below are build output, dependency caches, and editor or
# backup working directories by convention across Quarto, bookdown, R, and
# node projects, not this course's own paths. This mirrors the exclusion
# inventory_media() (below) already applies for the same reason rather than
# inventing a second convention.
#
# `zero_source_finding()` exists because "no source files found" must be a
# ROW in the report, not a console line and not silence: this is the same
# ruling (R27) that made a zero-page target a finding. A check that scanned
# nothing and a check that found nothing must never read the same.
# `assessments` is on this list as a CONTAINMENT rule, not a convenience, and
# it is the one directory name here that is this project's own convention
# rather than a framework or toolchain convention.
#
# Added 2026-08-13 by ruling, after the re-review. Making the source scan
# recursive pulled `assessments/` into scope, including the leak canary.
# check_colour_only() copies the offending raw source LINE into both `detail`
# and `code`, and those columns land in the audit's committed JSON and
# markdown. Nothing leaked (that directory is outside `_quarto.yml`'s
# render allowlist, so it never reaches the output tree and is never
# published), but a
# future quiz source carrying a `ggplot(aes(colour = ...))` line would have
# that line copied verbatim into a committed artifact. Answer-key material
# must not accumulate in artifacts by accident, and the containment model is
# this project's hardest constraint.
#
# What makes the exclusion free rather than a trade-off: assessment sources
# are never rendered to HTML by design (the answer-key containment rule), so
# they have no rendered accessibility surface at
# all, and a finding against one could never be acted on. Scanning them can
# only produce risk, never a fix.
#
# The cost, recorded rather than hidden: a course that keeps its answer keys
# under some other directory name gets no such protection from this line. The
# generalization is recorded as open work.
SOURCE_EXCLUDE_RE <- paste0(
  "(^|/)(docs|_site|_book|\\.quarto|\\.git|\\.Rproj\\.user|node_modules|",
  "renv|packrat|bower_components|vendor|bak|assessments)/|_files/|site_libs")

# ---- glob-aware exclusion matching -----------------------------------------
#
# Added 2026-08-13, re-review finding 1 (moderate). Exclusion entries were
# matched only as literal directory paths (`f == d || startsWith(f, d "/")`),
# which is correct for a plain directory name and a silent no-op for the most
# common Quarto idiom there is. A real repo declares `resources: ["assets/**"]`,
# and the literal string `assets/**` can never equal or prefix any real path,
# so the entry did nothing and said nothing. It happened not to matter here
# (no source files live under `assets/`), but a required argument that
# silently degrades to doing nothing is the exact shape this whole build has
# been removing.
#
# Glob semantics are Quarto's (which are the ordinary shell/gitignore ones),
# NOT regex:
#   **  matches across path separators  ("assets/**" covers "assets/a/b.qmd")
#   *   matches within one segment only ("*.qmd" does not cover "sub/a.qmd")
#   ?   matches exactly one character, not a separator
# Everything else in the entry is a literal, including `.`, which regex would
# otherwise read as "any character".
#
# An entry containing no wildcard keeps the original directory semantics
# (equal to, or under, that path), so a bare `working_notes` still means the
# whole tree without anyone having to write `working_notes/**`.
glob_to_regex <- function(g) {
  # READ THIS BEFORE EDITING THE SIX gsub() LINES BELOW.
  #
  # The wildcards are swapped for SENTINELS before the quotemeta pass, so
  # that pass cannot escape them, then restored as real regex afterwards.
  # The three sentinels are the literal control characters U+0001, U+0002
  # and U+0003, which no real path contains. They are REAL BYTES IN THIS
  # FILE and most editors render them as nothing, so the three lines below
  # look like they replace a wildcard with an empty string. They do not.
  #
  #   line 1: "**" -> U+0001      line 4: "\" + U+0001 -> ".*"
  #   line 2: "*"  -> U+0002      line 5: "\" + U+0002 -> "[^/]*"
  #   line 3: "?"  -> U+0003      line 6: "\" + U+0003 -> "[^/]"
  #
  # The backslash on the restore side is there because a sentinel is itself
  # a non-word character, so the quotemeta pass escapes it too.
  #
  # If an editor or a copy-paste ever strips those bytes, this function
  # silently stops handling wildcards. That is not left to trust:
  # the suite asserts the real mapping ("assets/**" must match
  # "assets/a/b.qmd" and must NOT match "assetsfoo.qmd"), so losing them
  # fails the suite loudly rather than quietly disabling every glob
  # exclusion.
  g <- gsub("**", "", g, fixed = TRUE)
  g <- gsub("*",  "", g, fixed = TRUE)
  g <- gsub("?",  "", g, fixed = TRUE)
  g <- gsub("(\\W)", "\\\\\\1", g, perl = TRUE)   # quotemeta: escape every
                                                   # non-word character
  g <- gsub("\\", ".*",    g, fixed = TRUE)
  g <- gsub("\\", "[^/]*", g, fixed = TRUE)
  g <- gsub("\\", "[^/]",  g, fixed = TRUE)
  paste0("^", g, "$")
}

exclusion_matches <- function(paths, entry) {
  d <- sub("/+$", "", entry)
  if (!nzchar(d) || !length(paths)) return(rep(FALSE, length(paths)))
  if (!grepl("[*?]", d)) return(paths == d | startsWith(paths, paste0(d, "/")))
  grepl(glob_to_regex(d), paths)
}

# An entry that matches nothing is usually fine and occasionally a typo, and
# those two must not look the same.
#
# Matching zero SOURCE files is normal: `assets/**` correctly excludes a
# directory that holds no `.qmd`. Warning on that would fire on every clean
# run. What is worth saying out loud is an entry whose literal part does not
# exist in the repo at all, which means the config names a path that is gone
# or misspelled, and the exclusion someone believes is in force is not.
warn_dead_exclusions <- function(repo, exclude) {
  for (d in exclude) {
    d <- sub("/+$", "", d)
    if (!nzchar(d)) next
    stem <- sub("[*?].*$", "", d)          # literal prefix before any wildcard
    stem <- sub("/[^/]*$", "", stem)       # back up to the last whole segment
    probe <- if (nzchar(stem)) file.path(repo, stem) else repo
    if (!file.exists(probe)) {
      warning("a11y_checks: exclusion entry '", d, "' names a path that does ",
              "not exist under ", repo, " (looked for '", stem, "'). The ",
              "exclusion it is meant to apply is NOT in force. Check the ",
              "project's resources declaration for a stale or misspelled ",
              "entry.", call. = FALSE)
    }
  }
  invisible(NULL)
}

# `exclude` is REQUIRED and has no default.
#
# Added 2026-08-13, after the first recursive run reached directories this
# course declares as pass-through resources and reported figures it does not
# publish. The exclusion cannot be computed here: which directories a project
# only COPIES is a fact in that project's own config, and reading config is
# target discovery's job, which this file must not depend on (each library
# file has to stand on its own).
#
# So this follows the pattern the cartridge checks already settled on for
# `surface`: the check takes what it cannot know as a required argument, and
# the driver, which already owns discovery, supplies it. No default, for the
# same reason `surface` has none. A default of character() would let a caller
# silently scan everything and look correct, which is this build's defining
# failure mode; a default computed from any hardcoded directory name would
# tie the checks to one course's layout. Missing means stop, immediately,
# with a message naming what to pass.
#
# Entries are repo-relative paths (a directory name like "working_notes", or
# a nested path like "vendor/theme"). A file is excluded when its path equals
# an entry or sits under it, the same matching rule list_pages() in target
# discovery already uses for the same declared directories.
require_exclude <- function(exclude, who) {
  if (missing(exclude) || is.null(exclude)) {
    stop(who, "(): `exclude` is required and was not supplied. Pass the ",
         "repo-relative directories this project only copies rather than ",
         "authors; the audit driver passes discover_target()'s ",
         "`resource_dirs`. Pass character(0) to scan everything, but pass ",
         "it deliberately: defaulting this argument would let a caller scan ",
         "a course's working files and report figures it does not publish, ",
         "with nothing anywhere saying so.", call. = FALSE)
  }
  if (!is.character(exclude)) {
    stop(who, "(): `exclude` must be a character vector of repo-relative ",
         "paths, got ", class(exclude)[1], call. = FALSE)
  }
  invisible(exclude)
}

source_files_for_checks <- function(repo, exclude) {
  require_exclude(exclude, "source_files_for_checks")
  warn_dead_exclusions(repo, exclude)
  f <- list.files(repo, pattern = "\\.(qmd|Rmd)$", recursive = TRUE,
                  full.names = FALSE)
  f <- f[!grepl(SOURCE_EXCLUDE_RE, f)]
  for (d in exclude) {
    f <- f[!exclusion_matches(f, d)]
  }
  file.path(repo, f)
}

zero_source_finding <- function(repo, surface, check_label) {
  finding(
    surface = surface, file = "(whole repo)", criterion = NA_character_,
    level = NA_character_, selector = sprintf("check:%s", check_label),
    severity = "serious",
    issue = sprintf("no .qmd or .Rmd source files were found in this repo, so the %s check examined NOTHING here",
                    check_label),
    detail = sprintf("repo=%s. This is not a clean result: the check ran against an empty file list. Either this course's sources are not .qmd/.Rmd, or they live under a path this check excludes as build output or a dependency cache (see SOURCE_EXCLUDE_RE in the source checks).",
                     repo),
    source = "custom")
}

# One chunk parse, shared by both modes. Returns a list of
# list(start=, ident=, has_alt=, body=) in document order.
parse_qmd_chunks <- function(lines) {
  starts <- grep("^```\\{", lines)
  ends   <- grep("^```\\s*$", lines)
  chunks <- list()
  unnamed_n <- 0L
  for (s in starts) {
    e <- ends[ends > s][1]
    if (is.na(e)) next
    body   <- lines[s:e]
    header <- lines[s]

    m <- regmatches(header, regexec(CHUNK_HEADER_RE, header))[[1]]
    inline_rest <- if (length(m) >= 2) trimws(m[2]) else ""
    label <- NA_character_
    if (nzchar(inline_rest) && !startsWith(inline_rest, ",")) {
      label <- trimws(strsplit(inline_rest, ",", fixed = TRUE)[[1]][1])
    }
    if (is.na(label)) {
      lm <- stringr::str_match(paste(body, collapse = "\n"),
                               "#\\|\\s*label:\\s*([^\n]+)")[, 2]
      if (!is.na(lm)) label <- trimws(lm)
    }

    if (is.na(label)) {
      unnamed_n <- unnamed_n + 1L
      ident <- sprintf("unnamed-chunk-%d", unnamed_n)
    } else {
      ident <- label
    }

    chunks[[length(chunks) + 1]] <- list(
      start   = s,
      ident   = ident,
      has_alt = any(grepl("^#\\|\\s*fig-alt:", body)),
      body    = body)
  }
  chunks
}

# Recursively finds "<stem>_files/figure-html" under repo, if it exists
# anywhere (typically under the project's configured output-dir, e.g.
# docs/). Repo-wide rather than reading _quarto.yml's output-dir itself:
# target discovery already owns config-driven output-dir discovery, and this
# file stands on its own (see the file-level comment above), so it must not
# depend on that one having run first. A repo-wide search by the
# stem-specific directory name carries negligible false-positive risk, since
# it can only match a directory Quarto itself generated for this exact source
# file, and, unlike a name guessed from convention, it naturally excludes an
# unrelated `resources:` copy elsewhere in the repo (verified against a real
# book repo, whose pass-through copy of a working-notes directory has its own
# figure-html directories, which never match any of the 21 chapter stems this
# searches for).
find_rendered_figure_dir <- function(repo, stem, all_dirs) {
  want <- file.path(paste0(stem, "_files"), "figure-html")
  hit  <- all_dirs[endsWith(all_dirs, want)]
  if (length(hit)) hit[1] else NA_character_
}

#' Flag figure-producing chunks that carry no fig-alt
#'
#' Detection keys on whether a chunk ACTUALLY RENDERS AN IMAGE, checked two
#' ways. In `rendered` mode the chunk's real PNGs are enumerated from the
#' `_files/figure-html` directory Quarto wrote and mapped back to source
#' chunks by name. In `source-heuristic` mode, used when nothing was rendered,
#' a plotting-call scan stands in. The result's `mode` attribute says which
#' ran, per file in `modes` and overall in `mode`, so a caller can always tell
#' verified figures from guessed ones.
#'
#' @param repo Repository to scan.
#' @param surface Surface these findings belong to.
#' @param exclude Repo-relative paths this project only copies rather than
#'   authors, from `discover_target()`'s `resource_dirs` and
#'   `unproduced_sources`. Required and has no default: a default would let a
#'   caller silently scan a course's working files and still look correct.
#'   Pass `character(0)` to scan everything, deliberately.
#' @return A findings data frame, with `modes` and `mode` attributes. A repo
#'   with no `.qmd` or `.Rmd` sources at all yields one loud row saying the
#'   check examined nothing, never an empty frame.
#' @examples
#' # A source-only repo, so the source-heuristic mode is what runs.
#' repo <- tempfile("repo-")
#' dir.create(repo)
#' writeLines(c(
#'   "```{r fig-trend}", "plot(1:10)", "```", "",
#'   "```{r fig-captioned}", "#| fig-alt: A line rising from left to right",
#'   "plot(1:10)", "```"), file.path(repo, "chapter1.qmd"))
#'
#' found <- check_missing_fig_alt(repo, surface = "demo",
#'                                exclude = character(0))
#' nrow(found)              # the captioned chunk is left alone
#' found$selector
#' attr(found, "mode")      # say which way detection ran, never guess silently
#'
#' unlink(repo, recursive = TRUE)
#' @export
check_missing_fig_alt <- function(repo, surface, exclude) {
  require_exclude(exclude, "check_missing_fig_alt")
  qmds <- source_files_for_checks(repo, exclude)
  if (!length(qmds)) return(zero_source_finding(repo, surface, "fig-alt"))
  all_dirs <- list.dirs(repo, recursive = TRUE, full.names = TRUE)
  all_dirs <- all_dirs[!grepl("(^|/)\\.git(/|$)", all_dirs)]

  out   <- list()
  modes <- character()

  # Fixed 2026-08-13, coordinator review after Task 7's acceptance run
  # (critical, real data loss). `selector` used to be NA_character_ on every
  # row this function produces. finding_id() hashes surface + file +
  # criterion + selector + code, and every argument here besides `selector`
  # is IDENTICAL for every chunk in one file (same surface, same file, same
  # "1.1.1", and this function never sets `code`), so every chunk in a file
  # collapsed to one shared id and the driver's own dedup step silently
  # dropped every chunk after the first. Verified against a real book repo:
  # 40 real findings across 10 chapters, 10 unique ids, 30 rows dropped
  # with no error and no warning anywhere. The chunk's own ident (an
  # explicit `#| label:`/inline label, or Quarto's own document-order
  # "unnamed-chunk-N" fallback; see parse_qmd_chunks() above) already
  # exists at construction time and is exactly what distinguishes one
  # figure-producing chunk from another within the same file, so it is used
  # here rather than inventing a new key. It is also unaffected by an edit
  # anywhere else in the file that would only move a LINE number, which is
  # why `line` was never a candidate for this (see the finding model's own
  # header comment on why a raw position was rejected for a different
  # check). The "unnamed-chunk-N" fallback name is not immune to every kind
  # of instability, since inserting or deleting an EARLIER unlabelled chunk
  # in the same file renumbers every unlabelled chunk after it, same as it
  # would for Quarto's own real PNG filenames in `rendered` mode. But that
  # is a property of how Quarto itself names unlabelled chunk output, not
  # something this check introduces, and a real content edit is exactly the
  # kind of change a re-audit is supposed to be sensitive to.
  mk_finding <- function(q, ch, mode) finding(
    surface = surface, file = basename(q), criterion = "1.1.1",
    level = NA_character_,
    issue = "figure-producing chunk has no fig-alt, so the rendered img gets no alt",
    selector = sprintf("chunk:%s", ch$ident), severity = "serious",
    detail = sprintf("chunk %s at line %d [mode: %s]", ch$ident, ch$start, mode),
    source_file = basename(q), line = ch$start, source = "custom")

  for (q in qmds) {
    stem   <- tools::file_path_sans_ext(basename(q))
    lines  <- readLines(q, warn = FALSE)
    chunks <- parse_qmd_chunks(lines)
    render_dir <- find_rendered_figure_dir(repo, stem, all_dirs)

    if (!is.na(render_dir)) {
      modes[stem] <- "rendered"
      pngs   <- list.files(render_dir, pattern = "\\.png$")
      idents <- unique(sub("-[0-9]+\\.png$", "", pngs))
      by_ident <- stats::setNames(chunks, vapply(chunks, `[[`, "", "ident"))
      for (id in idents) {
        ch <- by_ident[[id]]
        # A PNG whose name doesn't map to any parsed chunk is left alone
        # rather than guessed at, e.g. a stale render artifact from a
        # chunk since deleted. Real evidence with no chunk to attach it to
        # is not the same claim as a chunk confirmed to lack fig-alt.
        if (is.null(ch) || ch$has_alt) next
        out[[length(out) + 1]] <- mk_finding(q, ch, "rendered")
      }
    } else {
      modes[stem] <- "source-heuristic"
      for (ch in chunks) {
        body_txt <- paste(ch$body, collapse = "\n")
        is_fig <- grepl(PLOT_CALL_RE, body_txt) ||
                  any(grepl("^#\\|\\s*fig-cap:", ch$body)) ||
                  grepl("^fig-", ch$ident)
        if (is_fig && !ch$has_alt) {
          out[[length(out) + 1]] <- mk_finding(q, ch, "source-heuristic")
        }
      }
    }
  }

  result <- if (!length(out)) finding("x","x","x","x","x","x","x")[0, ] else do.call(rbind, out)
  # Per-file mode, plus a single summary: the uniform value if every scanned
  # file agreed, "mixed" if some files had rendered output and others didn't
  # (one real book repo is exactly this case, with 12 of 21 chapters holding
  # a rendered figure-html directory and 9 not), NA if there was nothing to
  # scan. Attributes don't survive a plain rbind() with other findings or a
  # write_findings()/read_findings() round trip (read_findings selects only
  # FINDING_COLS), so this is for a caller inspecting THIS return value
  # directly, which is also why the mode is repeated inside each finding's
  # own `detail` text above, as a copy that does survive.
  attr(result, "modes") <- modes
  attr(result, "mode") <- if (!length(modes)) NA_character_
                          else if (length(unique(modes)) == 1) unique(modes)
                          else "mixed"
  result
}

# ---- colour as the only channel ------------------------------------------
# Never auto-fixed. A chart that separates series by colour alone fails 1.4.1
# for a colourblind reader, but whether a given chart does is a judgement about
# what the chart is for. severity "review" routes it to a human by design.
COLOUR_AES  <- "aes\\([^)]*\\b(colou?r|fill)\\s*="
SECOND_CHAN <- "\\b(shape|linetype|lty|pch|alpha|size|label)\\s*="

#' Flag charts that may separate series by colour alone
#'
#' A chart that distinguishes its series by colour alone fails 1.4.1 for a
#' colourblind reader, but whether a given chart does is a judgement about
#' what the chart is for. Severity `review` routes it to a human by design;
#' this is never auto-fixed.
#'
#' @param repo Repository to scan.
#' @param surface Surface these findings belong to.
#' @param exclude Repo-relative paths this project only copies rather than
#'   authors. Required and has no default, for the reason
#'   `check_missing_fig_alt()` documents.
#' @return A findings data frame. A repo with no `.qmd` or `.Rmd` sources at
#'   all yields one loud row saying the check examined nothing.
#' @examples
#' repo <- tempfile("repo-")
#' dir.create(repo)
#' writeLines(c(
#'   "```{r}", "ggplot(d, aes(x, y, colour = grp)) + geom_line()", "```", "",
#'   "```{r}", "ggplot(d, aes(x, y, colour = grp, linetype = grp)) +",
#'   "  geom_line()", "```"), file.path(repo, "chapter1.qmd"))
#'
#' found <- check_colour_only(repo, surface = "demo", exclude = character(0))
#' nrow(found)          # the line carrying a second channel is not flagged
#' found$severity       # "review": a person decides, this is never auto-fixed
#'
#' unlink(repo, recursive = TRUE)
#' @export
check_colour_only <- function(repo, surface, exclude) {
  require_exclude(exclude, "check_colour_only")
  qmds <- source_files_for_checks(repo, exclude)
  if (!length(qmds)) return(zero_source_finding(repo, surface, "colour-only"))
  out <- list()
  for (q in qmds) {
    lines <- readLines(q, warn = FALSE)
    for (i in seq_along(lines)) {
      if (grepl(COLOUR_AES, lines[i]) && !grepl(SECOND_CHAN, lines[i])) {
        out[[length(out) + 1]] <- finding(
          surface = surface, file = basename(q), criterion = "1.4.1",
          level = NA_character_,
          issue = "series may be distinguished by colour alone; needs a second channel",
          # Audited 2026-08-13, coordinator review after Task 7's acceptance
          # run, alongside check_missing_fig_alt() below. `selector` stays
          # NA (there is no DOM to point at; this scans source, not rendered
          # HTML), but a second colour-only violation in the SAME file would
          # otherwise share the identical (surface, file, "1.4.1", NA, NA)
          # id with the first, and the second would be silently dropped by
          # the driver's dedup exactly like the fig-alt findings were. Not
          # observed in the real run (the real repos have exactly one
          # colour-only hit total), but the check can legitimately produce
          # more than one per file, so it needs the same discipline the
          # fig-alt fix applies. The offending line's own trimmed text is
          # the natural discriminator here: two genuinely different
          # violations almost never read as identical source text, and
          # unlike the line NUMBER, the TEXT does not shift just because an
          # unrelated edit happens earlier in the same file.
          selector = NA_character_, severity = "review",
          detail = trimws(lines[i]),
          source_file = basename(q), line = i, source = "custom",
          code = trimws(lines[i]))
      }
    }
  }
  if (!length(out)) return(finding("x","x","x","x","x","x","x")[0, ])
  do.call(rbind, out)
}
