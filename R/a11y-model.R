# The finding record and the JSON contract.
#
# The id is the load-bearing piece. A re-audit has to tell "this is the same
# problem I saw last time" from "this is new", and it must survive edits that
# shift line numbers. So the id hashes surface + file + criterion + selector
# + the pa11y technique code, and deliberately does NOT include the line
# number, the HTML context, or the message text.
#
# Withdrawn 2026-08-13, second code review: an earlier version of this file
# disambiguated same-key issues with a positional `occurrence` ordinal.
# That made ids distinct but not stable: the ordinal is assigned by an
# issue's position within its colliding group, and that position shifts
# whenever a sibling earlier in the group is added or removed by an ordinary,
# unrelated edit. A real fix in the middle of a group and an unrelated new
# issue added above it can renumber the whole group so every id changes,
# which reads to a re-audit as "0 fixed, 0 new, all unchanged", so both the
# real fix and the real regression go invisible. See from_pa11y() below for
# what replaced it: aggregation instead of enumeration.
#
# Amended 2026-08-13, third code review, finding 5: even with aggregation,
# two different pa11y checks landing on the same element under the same
# criterion (e.g. H37 "missing alt" and G73/G74 "needs a long description",
# both criterion 1.1.1, same <img>) still shared an id, because the key had
# no way to tell the two checks apart. `code` is pa11y's own identifier for
# which check fired and is template-stable across runs, so it closes that
# gap. Deliberately NOT `message`: pa11y interpolates real content into
# messages (a contrast message embeds the actual ratio and colors), so
# keying on it would make every value change read as one problem
# disappearing and an unrelated one appearing, which is worse noise than the
# collision it would fix.

# `count` added 2026-08-13, second code review, finding 1: distinguishes a
# single instance from an aggregate of instances pa11y could not tell apart
# (see from_pa11y()). Integer, not hashed into the id.
FINDING_COLS <- c("id", "surface", "file", "source_file", "line", "criterion",
                  "level", "issue", "selector", "severity", "count",
                  "fix_class", "fix_target", "leverage", "detail", "source")

# `code` defaults to NA so every pre-existing caller that has no notion of a
# pa11y technique code (a manually-constructed finding, and any direct call
# with just the original four arguments) keeps producing the exact id it
# always did. Only from_pa11y() ever supplies a real code.
finding_id <- function(surface, file, criterion, selector, code = NA_character_) {
  key <- paste(surface, file, criterion, selector %||% "", code, sep = "|")
  substr(digest::digest(key, algo = "sha1"), 1, 12)
}

#' One accessibility finding
#'
#' The record every check and every engine produces, and the row the JSON
#' report is written from. The id hashes surface, file, criterion, selector,
#' and the tool's own check code, and deliberately not the line number, the
#' HTML context, or the message text, so a re-audit can tell "the same
#' problem, still here" from "a new problem" across edits that move lines.
#'
#' @param surface The audited surface's name, e.g. a repository or cartridge.
#' @param file The file the finding is in, relative to that surface.
#' @param criterion The WCAG success criterion number, or `NA` when the
#'   producing engine gives none.
#' @param level The criterion's conformance level, or `NA` when it cannot be
#'   derived from what the tool reported.
#' @param issue The message a person reads.
#' @param selector A CSS selector for the element, or `NA`.
#' @param severity `"serious"`, `"moderate"`, `"minor"`, or `"review"`.
#' @param detail Supporting context, e.g. the HTML snippet.
#' @param source_file The authored source file, when a rendered finding can
#'   be traced back to one.
#' @param line The line in that source file.
#' @param source Which producer this came from, e.g. `"pa11y"` or
#'   `"custom"`.
#' @param count How many instances the tool could not tell apart collapsed
#'   into this row. Never hashed into the id.
#' @param code The producing check's own identifier, hashed into the id so
#'   two different checks on one element stay two findings.
#' @return A one-row data frame with the `FINDING_COLS` columns.
#' @examples
#' f <- finding(surface = "demo", file = "chapter1.html", criterion = "1.1.1",
#'              level = "A", issue = "image has no alt text",
#'              selector = "img[src='fig/a.png']", severity = "serious")
#' f[, c("id", "surface", "criterion", "severity", "count")]
#'
#' # The same element under a different check is a different finding, because
#' # the check's own code is part of the id.
#' g <- finding("demo", "chapter1.html", "1.1.1", "A",
#'              "image needs a long description", "img[src='fig/a.png']",
#'              "moderate", code = "G73")
#' identical(f$id, g$id)
#' @export
finding <- function(surface, file, criterion, level, issue, selector, severity,
                    detail = "", source_file = NA_character_,
                    line = NA_integer_, source = "pa11y", count = 1L,
                    code = NA_character_) {
  data.frame(
    id          = finding_id(surface, file, criterion, selector, code),
    surface     = surface,
    file        = file,
    source_file = source_file,
    line        = line,
    criterion   = criterion,
    level       = level,
    issue       = issue,
    selector    = selector %||% NA_character_,
    severity    = severity,
    count       = count,
    fix_class   = NA_character_,   # assigned by the report layer
    fix_target  = NA_character_,
    leverage    = NA_integer_,
    detail      = detail,
    source      = source,
    stringsAsFactors = FALSE)
}

# Maps a pa11y issue to a WCAG criterion number. pa11y reports a technique code
# such as "WCAG2AA.Principle1.Guideline1_1.1_1_1.H37"; the criterion is the
# fourth dotted segment with underscores turned into dots.
#
# The segment is matched by prefix, not by exact match, and only the leading
# digit_digit_digit run is kept. Verified against a real 699-issue audit:
# 50 of 51 distinct real codes fit "1_1_1" exactly, but one,
# "...Guideline1_3.1_3_1_A.G141", carries a trailing "_A" sub-technique
# marker on the criterion segment itself. An exact-match regex left that one
# code's criterion as NA; two real issues then shared a criterion of literal
# string "NA", which is exactly the collision the id hash is meant to avoid.
pa11y_criterion <- function(code) {
  if (is.null(code) || is.na(code)) return(NA_character_)
  parts <- strsplit(code, ".", fixed = TRUE)[[1]]
  crit  <- parts[grepl("^[0-9]+_[0-9]+_[0-9]+", parts)]
  if (!length(crit)) return(NA_character_)
  m <- regmatches(crit[1], regexpr("^[0-9]+_[0-9]+_[0-9]+", crit[1]))
  gsub("_", ".", m, fixed = TRUE)
}

pa11y_severity <- function(type) {
  switch(type %||% "error",
         error = "serious", warning = "moderate", notice = "minor", "moderate")
}

# ---- axe-core rule to WCAG criterion, verified from axe-core's own source -
#
# Added 2026-08-13, coordinator review, Finding 3 (critical, the
# coordinator's own error: the decision record chose pa11y believing it ran
# both engines by default, and it never had). Once `--runner axe` was
# actually passed (see the serving file), every axe-sourced issue's `code`
# (e.g. "color-contrast", "image-alt") turned out to be a rule NAME, not a
# WCAG technique code: it carries no embedded criterion number the way
# htmlcs's dotted codes do (pa11y_criterion(), above). Confirmed by
# inspecting a full raw axe issue from a real invocation: the object has
# `code`, `type`, `typeCode`, `message`, `context`, `selector`, `runner`, and
# `runnerExtras` (description/impact/needsFurtherReview/help/helpUrl) and
# nothing else. pa11y's JSON reporter does not surface axe-core's real `tags`
# array (which DOES carry the WCAG mapping) anywhere in what it returns.
# Left unhandled, every axe-sourced finding got criterion NA, and NA never
# matches the report layer's CLASS_A_CRITERIA or its 2.4.4 branch, so a real,
# leverage-eligible defect like color-contrast (1.4.3, the exact criterion
# the stylesheet-first class (a) leverage count is built around) fell
# through to class (b), one row per element, instead of joining the shared
# stylesheet fix. Verified against a real dual-runner run before this table
# existed: all 3,530 new axe-sourced classified findings landed in class
# (b), none in (a) or (c), even though several of them (every color-contrast
# and link-name issue among them) are exactly the kind of finding those two
# classes exist for.
#
# Amended 2026-08-13, coordinator re-review, Finding 5 (important): the
# table originally covered only the 7 axe codes the two real repos of the
# day happened to trigger. Confirmed live by the re-reviewer that a real
# WCAG-tagged rule that course simply never exercises, `html-has-lang`,
# was absent, meaning a language-attribute failure on a DIFFERENT course
# would carry no criterion and could never join a shared-edit group even
# though it belongs in one. The stated goal of this project is a system
# that works for any course, so "covers what one course happened to
# trigger" was the wrong bar. Every entry below is now read directly from
# EVERY rule axe-core v4.11.0 defines, not just the ones observed: fetched
# 2026-08-13 from the real directory listing at
# api.github.com/repos/dequelabs/axe-core/contents/lib/rules?ref=v4.11.0
# (104 real `.json` rule definitions, matchers-only `.js` files excluded),
# then each file's own `tags` array fetched from
# raw.githubusercontent.com/dequelabs/axe-core/v4.11.0/lib/rules/<rule>.json
# and read as-is, not memory or a summarizing model. v4.11.0 matches this
# project's real pa11y output, which links
# dequeuniversity.com/rules/axe/4.11/<rule> in every axe issue's own
# message. Of the 104 real rules, 74 carry at least one genuine WCAG
# success-criterion tag (axe-core's own convention: a tag of the exact form
# `wcag` + 3 or more digits, e.g. `wcag143` for 1.4.3 or `wcag1410` for
# 1.4.10, NOT `wcag2aa`/`wcag21a`/etc, which are conformance-LEVEL tags,
# not criterion tags, and are excluded by requiring every character after
# `wcag` to be a digit). The other 30 carry only `best-practice` or a
# non-WCAG tag and are listed in AXE_NO_WCAG_TAG below, not silently
# omitted, so they can be told apart from a rule this project has simply
# never verified at all (see axe_criterion()'s third state, below).
#
# 6 of the 74 carry more than one real WCAG tag at once. Each pick is
# whichever tag actually decides how the report layer should treat the
# finding, not an arbitrary first-listed one, when that differs; otherwise
# the first tag axe-core's own array lists, for a deterministic, checkable
# rule rather than a per-case judgement call:
# - area-alt: wcag244 (2.4.4) and wcag412 (4.1.2). An <area> hotspot with no
#   accessible text is the same shape of problem as link-name below,
#   descriptive text a human has to write, so 2.4.4 is picked for the same
#   reason.
# - aria-hidden-body: wcag131 (1.3.1) and wcag412 (4.1.2). Neither is in
#   CLASS_A_CRITERIA nor gets special treatment when fixes are classified, so
#   there is no classification consequence either way; 1.3.1, the
#   first-listed tag, is kept rather than picked by any other rule.
# - input-image-alt: wcag111 (1.1.1) and wcag412 (4.1.2). Same shape as
#   image-alt (an image needs alt text); 1.1.1 is picked to match its
#   single-tag sibling, which is also the first-listed tag here.
# - link-name: wcag244 (2.4.4) and wcag412 (4.1.2). 2.4.4 is picked because
#   the report layer specifically routes 2.4.4 to class (c) ("link text is
#   a sentence a person writes"), the correct treatment for "link has no
#   discernible text": a stylesheet cannot supply link text.
# - meta-refresh-no-exceptions: wcag224 (2.2.4) and wcag325 (3.2.5). Both
#   are Level AAA, outside this project's WCAG2AA invocation and outside
#   CLASS_A_CRITERIA either way; 2.2.4, the first-listed tag, is kept.
# - scrollable-region-focusable: wcag211 (2.1.1, Level A) and wcag213 (2.1.3,
#   Level AAA). 2.1.1 is picked as the criterion the standard actually being
#   audited against covers.
AXE_CRITERION <- c(
  "area-alt"                       = "2.4.4",
  "aria-allowed-attr"               = "4.1.2",
  "aria-braille-equivalent"         = "4.1.2",
  "aria-command-name"               = "4.1.2",
  "aria-conditional-attr"           = "4.1.2",
  "aria-deprecated-role"            = "4.1.2",
  "aria-hidden-body"                = "1.3.1",
  "aria-hidden-focus"               = "4.1.2",
  "aria-input-field-name"           = "4.1.2",
  "aria-meter-name"                 = "1.1.1",
  "aria-progressbar-name"           = "1.1.1",
  "aria-prohibited-attr"            = "4.1.2",
  "aria-required-attr"              = "4.1.2",
  "aria-required-children"          = "1.3.1",
  "aria-required-parent"            = "1.3.1",
  "aria-roledescription"            = "4.1.2",
  "aria-roles"                      = "4.1.2",
  "aria-toggle-field-name"          = "4.1.2",
  "aria-tooltip-name"               = "4.1.2",
  "aria-valid-attr-value"           = "4.1.2",
  "aria-valid-attr"                 = "4.1.2",
  "audio-caption"                   = "1.2.1",
  "autocomplete-valid"              = "1.3.5",
  "avoid-inline-spacing"            = "1.4.12",
  "blink"                           = "2.2.2",
  "button-name"                     = "4.1.2",
  "bypass"                          = "2.4.1",
  "color-contrast-enhanced"         = "1.4.6",
  "color-contrast"                  = "1.4.3",
  "css-orientation-lock"            = "1.3.4",
  "definition-list"                 = "1.3.1",
  "dlitem"                          = "1.3.1",
  "document-title"                  = "2.4.2",
  "duplicate-id-active"             = "4.1.1",
  "duplicate-id-aria"               = "4.1.2",
  "duplicate-id"                    = "4.1.1",
  "form-field-multiple-labels"      = "3.3.2",
  "frame-focusable-content"         = "2.1.1",
  "frame-title-unique"              = "4.1.2",
  "frame-title"                     = "4.1.2",
  "html-has-lang"                   = "3.1.1",
  "html-lang-valid"                 = "3.1.1",
  "html-xml-lang-mismatch"          = "3.1.1",
  "identical-links-same-purpose"    = "2.4.9",
  "image-alt"                       = "1.1.1",
  "input-button-name"               = "4.1.2",
  "input-image-alt"                 = "1.1.1",
  "label-content-name-mismatch"     = "2.5.3",
  "label"                           = "4.1.2",
  "link-in-text-block"              = "1.4.1",
  "link-name"                       = "2.4.4",
  "list"                            = "1.3.1",
  "listitem"                        = "1.3.1",
  "marquee"                         = "2.2.2",
  "meta-refresh-no-exceptions"      = "2.2.4",
  "meta-refresh"                    = "2.2.1",
  "meta-viewport"                   = "1.4.4",
  "nested-interactive"              = "4.1.2",
  "no-autoplay-audio"               = "1.4.2",
  "object-alt"                      = "1.1.1",
  "p-as-heading"                    = "1.3.1",
  "role-img-alt"                    = "1.1.1",
  "scrollable-region-focusable"     = "2.1.1",
  "select-name"                     = "4.1.2",
  "server-side-image-map"           = "2.1.1",
  "summary-name"                    = "4.1.2",
  "svg-img-alt"                     = "1.1.1",
  "table-fake-caption"              = "1.3.1",
  # 2.5.8 (Target Size Minimum) is a real WCAG 2.2 criterion, not WCAG 2.1.
  # axe-core tags this rule with it regardless of which WCAG version this
  # project's own level table covers; the level lookup already handles an
  # unlisted criterion by printing the number alone with no level, exactly
  # the honest behavior wanted here too, so it is kept rather than dropped
  # for being outside WCAG 2.1's 78 criteria.
  "target-size"                     = "2.5.8",
  "td-has-header"                   = "1.3.1",
  "td-headers-attr"                 = "1.3.1",
  "th-has-data-cells"               = "1.3.1",
  "valid-lang"                      = "3.1.2",
  "video-caption"                   = "1.2.2")

# The 30 real axe-core v4.11.0 rules confirmed, from the same fetch, to
# carry NO WCAG success-criterion tag at all (only `best-practice` or a
# non-WCAG tag such as `cat.semantics`). Listed explicitly, not silently
# omitted, so axe_criterion() can tell "verified, genuinely has no WCAG
# number" apart from "not yet verified against real axe-core metadata at
# all", the third state below.
AXE_NO_WCAG_TAG <- c(
  "accesskeys", "aria-allowed-role", "aria-dialog-name", "aria-text",
  "aria-treeitem-name", "empty-heading", "empty-table-header",
  "focus-order-semantics", "frame-tested", "heading-order", "hidden-content",
  "img-redundant-alt", "label-title-only", "landmark-banner-is-top-level",
  "landmark-complementary-is-top-level", "landmark-contentinfo-is-top-level",
  "landmark-main-is-top-level", "landmark-no-duplicate-banner",
  "landmark-no-duplicate-contentinfo", "landmark-no-duplicate-main",
  "landmark-one-main", "landmark-unique", "meta-viewport-large",
  "page-has-heading-one", "presentation-role-conflict", "region",
  "scope-attr-valid", "skip-link", "tabindex", "table-duplicate-name")

# Tracks which UNRECOGNIZED (surface, code) pairs have already triggered the
# warning below in this R session, so a real run with hundreds of instances
# of the same unrecognized rule ON THE SAME SURFACE warns once, not hundreds
# of times.
#
# Fixed 2026-08-13, coordinator re-review, Finding 6 (moderate). Keyed on
# `code` alone until this fix, which is correct for one course but not for
# the exact multi-course case Findings 4 and 5 were about: the audit driver
# loops over every repo named on its command line WITHIN ONE R process, i.e.
# one R session. If the same unrecognized axe code fired in repo A and again
# in repo B during that one invocation, only A's occurrence ever warned; B's
# identical, and equally real, occurrence was silently suppressed by the very
# cache built to make sure THIS class of thing never went quiet. No finding
# was lost either way (the row still lands with criterion NA regardless), but
# the STATED PURPOSE of this warning is that an unmapped code is new
# information a human should see for the run it happened in, and on a
# two-course run it is new information twice, once per course, not once
# total.
#
# Two fixes were considered: reset the cache once per repo (the driver
# already loops over repos explicitly, so it could clear the cache at the
# top of each iteration), or key the cache by (surface, code) instead of
# `code` alone. Keying by surface was chosen. A per-repo reset works only
# because the driver happens to structure its loop the way it does today;
# it is a contract between the driver and this file that nothing enforces,
# and the exact kind of caller-discipline dependency this project has
# repeatedly moved away from in favor of a guarantee the function itself
# holds (report_and_dedup()/halt_on_collision() being extracted for the
# identical reason). Keying by surface makes the correctness a property of
# axe_criterion() itself: it warns once per real reporting unit, no matter
# how a future caller structures its loops, and needs no cooperation from
# the driver to stay correct.
.axe_unrecognized_warned <- new.env(parent = emptyenv())

# `%||%` only substitutes on NULL, not NA, and a caller that omits `surface`
# passes the DEFAULT `NA_character_`, not NULL, so an explicit is.na()
# check is used here rather than `%||%`, which would silently let a real
# NA surface travel into the key unresolved. U+0001 separates the two
# halves so a surface name and a code can never concatenate into an
# accidental collision, the same reasoning the report layer's own two-part
# class key already uses.
axe_unrecognized_cache_key <- function(surface, code) {
  s <- if (is.null(surface) || is.na(surface)) "(unknown surface)" else surface
  paste(s, code, sep = "")
}

# Three states, not two, and only one of them is silent by design.
# Considered whether an unmapped axe rule firing should be visible rather
# than silent, given everything this build's other findings turned up about
# silence being the actual failure mode every time: decided yes, for
# exactly one of the two ways a code can be "unmapped". A code IN
# AXE_NO_WCAG_TAG is a verified, permanent fact (axe-core itself does not
# tie that rule to a WCAG number) and stays quiet, matching how the level
# table's own unlisted-criterion fallback already behaves. A code in
# NEITHER table is different in kind: it means axe fired a rule this
# project has never verified against real axe-core metadata at all, most
# likely because pa11y's bundled axe-core version has drifted from v4.11.0
# (the exact condition the decision record's "Revisit if" section already
# named). That is new information a person should see, not a fact already on
# record, so it warns once per (surface, code) pair per run rather than
# returning NA the same quiet way as a confirmed best-practice rule.
#
# `surface` defaults to NA so every existing direct caller (a test calling
# axe_criterion("some-code") with no surface argument) keeps working; a
# missing surface still gets its own cache slot rather than colliding with a
# real one, via the "(unknown surface)" label in
# axe_unrecognized_cache_key() above, so an anonymous caller and a named
# surface can never be mistaken for each other's cache entry either.
axe_criterion <- function(code, surface = NA_character_) {
  if (is.null(code) || is.na(code)) return(NA_character_)
  hit <- unname(AXE_CRITERION[code])
  if (!is.na(hit)) return(hit)
  if (code %in% AXE_NO_WCAG_TAG) return(NA_character_)
  key <- axe_unrecognized_cache_key(surface, code)
  if (!exists(key, envir = .axe_unrecognized_warned, inherits = FALSE)) {
    assign(key, TRUE, envir = .axe_unrecognized_warned)
    surface_label <- if (is.null(surface) || is.na(surface)) "(unknown)" else surface
    warning("axe_criterion: axe code '", code, "' on surface '",
            surface_label, "' is not in AXE_CRITERION or ",
            "AXE_NO_WCAG_TAG. This project's axe-core mapping was verified ",
            "against v4.11.0's real, complete rule set; this code was not ",
            "among them. Either axe-core has changed since, or pa11y's ",
            "bundled version differs from v4.11.0. Reporting with NO ",
            "criterion rather than a guess, but this needs a human to check ",
            "axe-core's current real rule metadata and update AXE_CRITERION ",
            "or AXE_NO_WCAG_TAG; do not treat this the same as a confirmed ",
            "best-practice rule.", call. = FALSE)
  }
  NA_character_
}

# pa11y represents "no value" for an optional field inconsistently: usually an
# absent key, which fromJSON turns into NULL, but sometimes an empty JSON
# object `{}`, which simplifyVector = FALSE turns into a zero-length named
# list. `%||%` only catches NULL. Verified against a real 699-issue audit of
# one rendered chapter: 53 issues had `context` as `list()` rather than a
# string or NULL, always on issues with no HTML snippet to show. Left
# unguarded that zero-length list reaches data.frame() as a zero-length
# column and errors "arguments imply differing number of rows".
#
# Applied to every optional string field pa11y emits, including `code` and
# `type` as of 2026-08-13, second code review, finding 4: those two were left
# unguarded in the first pass, so one malformed issue with an empty-list
# `code` or `type` would abort from_pa11y() for the entire page rather than
# just that one issue.
pa11y_chr <- function(x, default = "") {
  if (is.null(x) || !is.character(x) || length(x) != 1) default else x
}

# pa11y's `code` names the ruleset the audit ran under (this project always
# runs `--standard WCAG2AA`), not the individual success criterion's actual
# WCAG level. Fixed 2026-08-13 code review, finding 2: the previous
# heuristic, "WCAG2AA" in the code implies level AA, was checked against the
# real 699-issue probe and was wrong on every single row: level came back
# "AA" 699 times out of 699, including on criteria that are genuinely Level
# A, such as 1.1.1 and 4.1.2. There is no way to derive the true level from
# this project's fixed-standard invocation, so say that rather than assert a
# guess. A verified criterion-to-level lookup, sourced from the published W3C
# list, lives in the reporting stage, not here.
pa11y_level <- function(code) NA_character_

# Turns one raw pa11y issue into the plain fields from_pa11y() needs, with
# every optional field guarded through pa11y_chr(). Kept separate from
# from_pa11y() so the grouping logic below reads as grouping, not parsing.
#
# Amended 2026-08-13, coordinator review, Finding 3: routes criterion
# derivation on `runner`, not just `code`, now that both runners actually
# execute. htmlcs's dotted technique codes and axe's bare rule names are two
# different vocabularies; pa11y_criterion() only ever understood the former.
# An axe issue with no `runner` field at all (should not happen against a
# real pa11y invocation, but pa11y_chr() already defends every other
# optional field the same way) falls back to pa11y_criterion(), which will
# safely return NA for a non-htmlcs-shaped code rather than mis-parse it.
#
# `surface` amended 2026-08-13, coordinator re-review, Finding 6: passed
# through to axe_criterion() so its once-per-run unrecognized-code warning
# is keyed per surface, not globally across every repo one R process
# happens to audit. See axe_criterion()'s own comment for why.
pa11y_parse_issue <- function(i, surface = NA_character_) {
  code   <- pa11y_chr(i$code, NA_character_)
  runner <- pa11y_chr(i$runner, NA_character_)
  list(
    code      = code,
    type      = pa11y_chr(i$type, "error"),
    runner    = runner,
    criterion = if (identical(runner, "axe")) axe_criterion(code, surface)
                else pa11y_criterion(code),
    message   = pa11y_chr(i$message),
    selector  = pa11y_chr(i$selector, ""),
    context   = pa11y_chr(i$context))
}

# Builds a finding() row from one parsed issue, with a caller-supplied
# selector and count. Shared by the single-instance and aggregate paths in
# from_pa11y() below so both go through the exact same field mapping,
# including the full pa11y `code` in the id key (finding 5, third code
# review).
pa11y_finding_from <- function(p, surface, file, selector, count) {
  finding(
    surface   = surface,
    file      = file,
    criterion = p$criterion,
    level     = pa11y_level(p$code),
    issue     = p$message,
    selector  = selector,
    severity  = pa11y_severity(p$type),
    detail    = p$context,
    source    = "pa11y",
    count     = count,
    code      = p$code)
}

# Withdrawn ordinal, replaced with aggregation. Fixed 2026-08-13, second code
# review, finding 1: pa11y sometimes reports no selector for a whole class of
# check (verified: 28 of 29 real WCAG 1.4.10 reflow issues on one rendered
# chapter), and this tool has no way to tell those 28 instances apart from
# one another; pa11y itself cannot either. Pretending otherwise with a
# positional ordinal made ids distinct but not stable (see the file-level
# comment above). The honest representation is one finding per
# (surface, file, criterion, code) among the selector-less issues, carrying
# a `count` of how many instances collapsed into it. An aggregate's id is
# therefore identical to what finding_id() would have produced before the
# ordinal ever existed: finding_id(surface, file, criterion, "", code). Its
# count can move from 29 to 12 across audits and the id does not change,
# which is what lets diff_findings() recognize it as the same,
# partially-fixed problem rather than reporting noise. Grouping by code as
# well as criterion (finding 5, third code review) means two different
# checks that both happen to land on the same criterion with no selector are
# still treated as genuinely different problems, not merged.
#
# Issues that carry a real selector are grouped by (criterion, code,
# selector) the same way the selector-less issues below are grouped by
# (criterion, code), rather than emitted one row per issue unconditionally.
# Two different pa11y checks landing on the same element under the same
# criterion (e.g. "missing alt" plus "needs a long description" on the same
# <img>) still get distinct ids, since each check has its own `code`; that
# part of this comment's original claim, "each becomes its own row with
# count = 1", held until a real 21-chapter acceptance run proved it wrong
# the other direction.
#
# Amended 2026-08-13, after that acceptance run: a real selector does
# NOT guarantee pa11y only ever reports one issue against it. HTML_CodeSniffer's
# own G141 check ("heading structure is not logically nested") reports TWO
# distinct, template-fixed messages against the identical element under the
# identical code on every one of that course's 21 real chapter pages,
# verified live: selector "#toc-title", code
# "...Guideline1_3.1_3_1_A.G141", one message saying the h2 appears to be
# the primary heading and should be h1, the other saying the same h2 should
# be logically nested under a heading one level up. Two real, distinct
# complaints, not the same one restated. Before this fix both issues hashed
# to the identical id (same criterion, code, and selector), so this
# project's own dedup step collapsed them the moment two full repos were
# audited together, caught by report_and_dedup() (below in this file)
# reporting it as a genuine collision, on the very run meant to prove the
# fig-alt collision fix had closed every instance of this bug class.
#
# The fix mirrors the pattern already established for the selector-less
# path exactly, rather than inventing a second mechanism: group, then
# aggregate with a `count`. It deliberately does NOT hash the raw `message`
# text into the id. This file's own header comment already explains why not
# in general (message can embed an interpolated, run-to-run-varying value,
# e.g. a contrast finding's exact ratio, and keying on that would make an
# unchanged real problem look like a different one on every run); grouping
# by (criterion, code, selector) and letting `count` carry however many
# distinct messages collapsed into a row gets the same honesty the
# selector-less path already has, without ever touching message text at all.
from_pa11y <- function(raw, surface, file) {
  if (!length(raw)) return(finding("x","x","x","x","x","x","x")[0, ])

  parsed <- lapply(raw, pa11y_parse_issue, surface = surface)
  has_selector <- vapply(parsed, function(p) nzchar(p$selector), logical(1))

  sel_parsed <- parsed[has_selector]
  single_rows <- list()
  if (length(sel_parsed)) {
    sel_keys <- vapply(sel_parsed, function(p) {
      paste(p$criterion %||% "NA", p$code %||% "NA", p$selector, sep = "|")
    }, character(1))
    sel_groups <- split(sel_parsed, sel_keys)
    single_rows <- lapply(sel_groups, function(members) {
      pa11y_finding_from(members[[1]], surface, file, members[[1]]$selector,
                          count = length(members))
    })
  }

  grouped <- parsed[!has_selector]
  agg_rows <- list()
  if (length(grouped)) {
    keys <- vapply(grouped, function(p) {
      paste(p$criterion %||% "NA", p$code %||% "NA", sep = "|")
    }, character(1))
    groups <- split(grouped, keys)
    agg_rows <- lapply(groups, function(members) {
      pa11y_finding_from(members[[1]], surface, file, "", count = length(members))
    })
  }

  do.call(rbind, c(single_rows, agg_rows))
}

#' Write and read a findings file
#'
#' The JSON contract between one audit run and the next. `write_findings()`
#' writes the run's metadata and its findings; `read_findings()` reads them
#' back with every `FINDING_COLS` column present and typed, including on a
#' zero-row file, which is the state a course is trying to reach and not an
#' edge case to crash on.
#'
#' jsonlite cannot infer a type from an all-null JSON array, so a column that
#' is NA on every row comes back logical rather than character or integer.
#' `read_findings()` restores the types rather than letting a silent flip
#' reach a later stage that writes into those columns.
#'
#' @param df A data frame of [finding()] rows.
#' @param meta The run's metadata list, written under `audit`.
#' @param path The JSON file to write or read.
#' @return `write_findings()` returns `path` invisibly; `read_findings()`
#'   returns a data frame with the `FINDING_COLS` columns.
#' @examples
#' two <- rbind(
#'   finding("demo", "chapter1.html", "1.1.1", "A", "image has no alt text",
#'           "img[src='fig/a.png']", "serious"),
#'   finding("demo", "chapter2.html", "2.4.4", "A",
#'           "link text does not describe its destination", "a[href='/next']",
#'           "moderate"))
#'
#' path <- tempfile(fileext = ".json")
#' write_findings(two, meta = list(date = "2026-09-05"), path)
#' back <- read_findings(path)
#' nrow(back)
#' identical(back$id, two$id)   # every id survives the round trip
#' vapply(back[, c("line", "fix_class")], class, character(1))
#'
#' unlink(path)
#' @name findings_file
NULL

#' @rdname findings_file
#' @export
write_findings <- function(df, meta, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(list(audit = meta, findings = df), path,
             auto_unbox = TRUE, pretty = TRUE, na = "null")
  invisible(path)
}

# Columns that must survive a round trip as integer. Every other FINDING_COLS
# column must survive as character. Needed because jsonlite cannot infer a
# type from an all-null JSON array: fromJSON() returns logical for a column
# that is NA on every row, not the column's real type. Fixed 2026-08-13,
# second code review, finding 3: from_pa11y() output has source_file, line,
# fix_class, fix_target, and leverage NA on every row, so five of sixteen
# columns silently came back logical instead of character or integer.
# fix_class, fix_target, and leverage get written into by the report stage and
# read back from this file; a silent type flip there is exactly the kind of
# bug that looks fine until something calls as.integer() on a logical NA
# column and gets a different kind of NA than it expected.
FINDING_INT_COLS <- c("line", "leverage", "count")

#' @rdname findings_file
#' @export
read_findings <- function(path) {
  x  <- jsonlite::fromJSON(path, simplifyVector = TRUE)
  df <- x$findings
  # A zero-row write produces "findings": [], which fromJSON parses as
  # list(), not NULL. Fixed 2026-08-13, second code review, finding 2: the
  # old guard was `is.null(df) || !nrow(df)`, and nrow() on a plain list()
  # (not a data.frame) returns NULL, so !nrow(df) was `!NULL`, a zero-length
  # logical, and if() on that errors rather than returning the empty frame.
  # A page or a whole criterion with zero remaining issues is a normal,
  # desirable state this project is actively trying to reach, not an edge
  # case to crash on.
  if (is.null(df) || length(df) == 0 || nrow(df) == 0) {
    return(finding("x","x","x","x","x","x","x")[0, ])
  }
  for (col in FINDING_COLS) if (is.null(df[[col]])) df[[col]] <- NA
  for (col in FINDING_INT_COLS) df[[col]] <- as.integer(df[[col]])
  for (col in setdiff(FINDING_COLS, FINDING_INT_COLS)) df[[col]] <- as.character(df[[col]])
  df[, FINDING_COLS, drop = FALSE]
}

#' What changed between two audits
#'
#' Compares two findings frames by id, so a problem that is still present
#' reads as unchanged even after edits that moved it down the page.
#'
#' @param old_df,new_df Findings frames, older and newer.
#' @return A list of `fixed`, `new`, and `unchanged` frames.
#' @examples
#' old <- rbind(
#'   finding("demo", "a.html", "1.1.1", "A", "image has no alt text",
#'           "img", "serious"),
#'   finding("demo", "b.html", "2.4.4", "A", "link text says nothing",
#'           "a[href='/next']", "moderate"))
#' new <- rbind(
#'   old[2, ],
#'   finding("demo", "c.html", "1.4.3", "AA", "text contrast is too low",
#'           "p.note", "serious"))
#'
#' changed <- diff_findings(old, new)
#' vapply(changed, nrow, integer(1))   # one fixed, one new, one still here
#' changed$fixed$file
#' @export
diff_findings <- function(old_df, new_df) {
  list(
    fixed     = old_df[!old_df$id %in% new_df$id, , drop = FALSE],
    new       = new_df[!new_df$id %in% old_df$id, , drop = FALSE],
    unchanged = new_df[ new_df$id %in% old_df$id, , drop = FALSE])
}

# ---- id-based dedup, reporting itself rather than acting silently ---------
#
# Added 2026-08-13, coordinator review, finding 2, after an acceptance
# run. Every caller in this project that combines findings from more than one
# source (the driver, combining every page and check across every
# repo and cartridge in one run) needs to collapse rows that share an id, and
# up to this point that collapse was a bare `df[!duplicated(df$id), ]` with
# no report of what it did. That is exactly how 30 real missing-fig-alt
# findings were silently discarded during the acceptance run: the mechanism
# was doing real, consequential work, removing 30 of 40 real findings, and
# said nothing about it anywhere. It was caught only because four independent
# ground-truth facts happened to be checked by hand against the shipped
# report afterward. A dedup step in a document meant to support a
# compliance claim must never be silent about what it removed.
#
# Two rows sharing an id are not necessarily the same event. This function
# tells them apart:
#   - EXPECTED (same finding, seen twice): every row in the group agrees on
#     issue, detail, severity, criterion, file, and surface, so collapsing
#     them to one loses no information; the two rows really were reports
#     of the identical real-world problem. Two structurally-identical
#     `.imscc` files audited from one course's reference exports are the
#     real example: the same 3 untitled iframes are genuinely present in
#     both files, and reporting that finding twice would double-count one
#     real defect, not reveal two.
#   - COLLISION (a defect): the rows disagree on one of those fields despite
#     sharing an id, which means the id failed to distinguish two genuinely
#     different findings. This is reported loudly and separately, because it
#     means real findings are about to be silently discarded, exactly as the
#     missing-fig-alt ones were. Seeing this in a future run means a
#     check somewhere is missing a real discriminator; fix the check, not
#     this function.
#
# `quiet = TRUE` suppresses the console report (used by tests and by a caller
# that wants to inspect the outcome before deciding whether to print
# anything itself) without changing what gets removed.
#
# ALWAYS returns the deduplicated data.frame, whether or not anything was
# removed, so a caller can write `df <- report_and_dedup(df)` unconditionally
# exactly like the bare `df[!duplicated(df$id), ]` it replaces. The removal
# accounting rides along as attributes, `n_removed`, `dup_ids`,
# `collided_ids`, the same pattern the fig-alt check already uses for its own
# mode reporting, rather than wrapping the frame in a list and breaking every
# existing call site's assumption that this returns something `nrow()`- and
# `$`-indexable directly.
DEDUP_AGREE_COLS <- c("issue", "detail", "severity", "criterion", "file", "surface")

report_and_dedup <- function(df, quiet = FALSE) {
  if (!nrow(df)) {
    attr(df, "n_removed")    <- 0L
    attr(df, "dup_ids")      <- character()
    attr(df, "collided_ids") <- character()
    return(df)
  }

  is_dup  <- duplicated(df$id)
  dup_ids <- unique(df$id[is_dup])

  if (!length(dup_ids)) {
    if (!quiet) cat("\ndedup: 0 duplicate ids, 0 rows removed\n")
    attr(df, "n_removed")    <- 0L
    attr(df, "dup_ids")      <- character()
    attr(df, "collided_ids") <- character()
    return(df)
  }

  n_removed <- sum(is_dup)
  collided  <- character()
  groups    <- split(df, df$id)

  if (!quiet) {
    cat("\ndedup: ", length(dup_ids), " duplicate id(s), ", n_removed,
        " row(s) removed\n", sep = "")
  }
  for (id in dup_ids) {
    grp  <- groups[[id]]
    same <- all(vapply(DEDUP_AGREE_COLS, function(f) {
      length(unique(grp[[f]])) == 1L
    }, logical(1)))
    if (!same) collided <- c(collided, id)
    if (!quiet) {
      cat("  ", id, ": ", nrow(grp), " row(s) -> 1 kept (", grp$surface[1],
          "/", grp$file[1], ", ", grp$criterion[1], ")",
          if (!same) "  *** COLLISION, see below ***" else "", "\n", sep = "")
    }
  }

  if (length(collided) && !quiet) {
    cat("\n*** COLLISION: ", length(collided), " id(s) above absorbed rows ",
        "that do NOT agree on issue/detail/severity/criterion/file/surface. ",
        "These are NOT the same finding seen twice; the id failed to tell ",
        "two different findings apart, and real findings were just ",
        "discarded. Fix the discriminator in the check that produced them; ",
        "do not widen this report instead. Colliding ids: ",
        paste(collided, collapse = ", "), "\n", sep = "")
  }

  out <- df[!is_dup, , drop = FALSE]
  attr(out, "n_removed")    <- n_removed
  attr(out, "dup_ids")      <- dup_ids
  attr(out, "collided_ids") <- collided
  out
}

# report_and_dedup() deliberately never stop()s on a collision. It always
# returns a deduplicated frame, quietly for a real duplicate and loudly (via
# the console report and the collided_ids attribute) for a collision, so a
# caller can use it unconditionally: "the mechanism, not the diagnosis."
# Something still has to actually HALT the run when a collision is found, or
# a check meant to be silently-dropped-real-findings insurance is just
# insurance that never pays out. This is that something.
#
# Task 8 code review, finding 1: this used to be four lines duplicated
# between the driver (the real production guard) and a copy of
# the same if/stop reimplemented inside the test script's negative
# control. Both passed every check because the guard was genuinely present
# and reachable in both places, but a test that exercises a COPY of the
# guard cannot catch a regression that leaves the real guard's text intact
# while making it unreachable, e.g. wrapping the real
# report_and_dedup()/halt call in a conditional that skips it on the
# default path. Extracted so the driver and the tests call the exact
# same function; there is now exactly one guard, not two that can drift out
# of sync with each other.
halt_on_collision <- function(df, quiet = FALSE) {
  df <- report_and_dedup(df, quiet = quiet)
  if (length(attr(df, "collided_ids"))) {
    stop("id collision(s) detected during dedup (see above). ",
         "This means real, distinct findings would be silently discarded. ",
         "Fix the discriminator in the check that produced them before ",
         "trusting this run's output.")
  }
  df
}
