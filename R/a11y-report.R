# Classification and rendering.
#
# The classification is the point of the whole exercise. A list of 400
# accessibility failures is not actionable. The same list, with the six that
# are one stylesheet edit at the top and their leverage counted, is a
# morning's work. Class (a) first is not a stylistic preference, it is what
# makes the remediation finishable. That means the leverage number has to be
# trustworthy: it is the one number the whole plan is built on, and every fix
# below (coordinator review, 2026-08-13) exists because some path made that
# number wrong, either too high (findings 1 and 5) or pointed at a target
# where the promised fix cannot actually happen (finding 2).
#
# No em-dashes in anything this file EMITS (the markdown it writes to disk).
# It is read by other people. Comments in this file follow the project's own
# convention of "--" as a dash substitute, which is fine, since a reader of
# the source is a colleague, not the report's audience.
#
# NOTHING here defaults to any one course's path. classify_fixes(), the
# zero_page_note() helper, and every render_* function take a target/meta
# argument for exactly that reason.

# NA-safe scalar string coercion. Used everywhere this file reads a
# free-text column (detail, selector) that may be NA rather than "". The
# task brief's own draft used `nzchar(df$detail[i] %||% "")`, and %||% only
# substitutes on NULL, not NA. nzchar(NA_character_) returns NA, and
# `if (NA)` throws "missing value where TRUE/FALSE needed". Every finding()
# call in this project defaults detail to "", so the bug never fires against
# current callers, but a column read back through read_findings() or built
# by some future caller has no such guarantee.
chr0 <- function(x) if (is.null(x) || is.na(x)) "" else x

# ---- WCAG 2.1 A vs AA vs AAA, transcribed from the published source -------
#
# Fetched from https://www.w3.org/TR/WCAG21/ on 2026-08-13 (curl, not
# WebFetch's summarizing model, and not memory) and parsed programmatically
# from the page's own markup: each success criterion heading is followed by
# `<p class="conformance-level">(Level X)</p>`. That extraction produced
# exactly 78 success criteria (30 A, 20 AA, 28 AAA), which matches the
# published total for WCAG 2.1 and is itself a check that the parse found
# the right elements rather than some unrelated "(Level ...)" string
# elsewhere on the page.
#
# Every entry below is checkable by searching the criterion number at that
# URL. If a code ever reports a criterion not in this table, level_for()
# below returns NA and the report prints the criterion number alone. The
# project's decision record settled this: a confidently wrong level in a
# compliance document is worse than an absent one, so nothing here is a guess
# or filled in from memory.
WCAG_LEVEL <- c(
  # 1.x Perceivable
  "1.1.1" = "A", "1.2.1" = "A", "1.2.2" = "A", "1.2.3" = "A", "1.2.4" = "AA",
  "1.2.5" = "AA", "1.2.6" = "AAA", "1.2.7" = "AAA", "1.2.8" = "AAA", "1.2.9" = "AAA",
  "1.3.1" = "A", "1.3.2" = "A", "1.3.3" = "A", "1.3.4" = "AA", "1.3.5" = "AA",
  "1.3.6" = "AAA", "1.4.1" = "A", "1.4.2" = "A", "1.4.3" = "AA", "1.4.4" = "AA",
  "1.4.5" = "AA", "1.4.6" = "AAA", "1.4.7" = "AAA", "1.4.8" = "AAA", "1.4.9" = "AAA",
  "1.4.10" = "AA", "1.4.11" = "AA", "1.4.12" = "AA", "1.4.13" = "AA",
  # 2.x Operable
  "2.1.1" = "A", "2.1.2" = "A", "2.1.3" = "AAA", "2.1.4" = "A", "2.2.1" = "A",
  "2.2.2" = "A", "2.2.3" = "AAA", "2.2.4" = "AAA", "2.2.5" = "AAA", "2.2.6" = "AAA",
  "2.3.1" = "A", "2.3.2" = "AAA", "2.3.3" = "AAA", "2.4.1" = "A", "2.4.2" = "A",
  "2.4.3" = "A", "2.4.4" = "A", "2.4.5" = "AA", "2.4.6" = "AA", "2.4.7" = "AA",
  "2.4.8" = "AAA", "2.4.9" = "AAA", "2.4.10" = "AAA", "2.5.1" = "A", "2.5.2" = "A",
  "2.5.3" = "A", "2.5.4" = "A", "2.5.5" = "AAA", "2.5.6" = "AAA",
  # 3.x Understandable
  "3.1.1" = "A", "3.1.2" = "AA", "3.1.3" = "AAA", "3.1.4" = "AAA", "3.1.5" = "AAA",
  "3.1.6" = "AAA", "3.2.1" = "A", "3.2.2" = "A", "3.2.3" = "AA", "3.2.4" = "AA",
  "3.2.5" = "AAA", "3.3.1" = "A", "3.3.2" = "A", "3.3.3" = "AA", "3.3.4" = "AA",
  "3.3.5" = "AAA", "3.3.6" = "AAA",
  # 4.x Robust
  "4.1.1" = "A", "4.1.2" = "A", "4.1.3" = "AA")

#' The conformance level of one WCAG success criterion
#'
#' Looks the criterion up in the table transcribed from the published standard.
#' Returns `NA` for anything not in it, including a criterion that is not a
#' WCAG success criterion at all, so the report prints the number alone rather
#' than a guessed level.
#'
#' @param criterion The criterion number, e.g. `"1.4.3"`, or `NA`.
#' @return `"A"`, `"AA"`, `"AAA"`, or `NA_character_`.
#' @export
level_for <- function(criterion) {
  if (is.null(criterion) || is.na(criterion)) return(NA_character_)
  unname(WCAG_LEVEL[criterion]) %||% NA_character_
}

# ---- notices: filtered out ONCE, upstream of classification ---------------
#
# Fixed 2026-08-13, coordinator review, finding 1 (critical). classify_fixes()
# used to special-case severity "review" but never "minor", so a pa11y
# notice could receive a real fix_class, including class (a), and its
# leverage joined whatever real serious/moderate findings shared its
# criterion. At 3,725 notices in this project's own real full run (the
# measured number; "roughly 16,000" appeared in three comments in this
# codebase as if it were one, and was an estimate nobody had checked --
# corrected 2026-08-13, final whole-branch review, finding M16), that is not
# a corner case: a single demoted contrast notice landing on a
# CLASS_A_CRITERIA criterion could inflate a leverage count by hundreds.
# render_report() then
# made it worse: it built its surface x fix_class summary table from the
# FULL frame, notices included, and only stripped them out AFTER, right
# before the detail section, so the table and the list below it counted two
# different sets of rows and could never reconcile.
#
# The fix is a single filtering point, upstream of classify_fixes(), not a
# filter repeated (and able to drift) inside classify_fixes() or inside
# either renderer. A caller (the audit driver, and this file's own tests)
# calls notice_table() on the FULL findings frame first, to capture the
# summary before anything is removed, then strip_notices() to get the frame
# that classify_fixes(), render_report(), and render_plan() all consume from
# that point on. Notices are never lost: write_findings(), in the finding
# model, still writes the full, unfiltered frame to the JSON. Only the two
# human documents ever see the split, and both see the SAME split.
strip_notices <- function(df) {
  if (!nrow(df)) return(df)
  df[df$severity != "minor", , drop = FALSE]
}

# Fixed 2026-08-13, final whole-branch review, finding I7 (important).
# table() DROPS NA by default, so every notice whose criterion is NA (an axe
# rule carrying no WCAG success-criterion tag, e.g. heading-order) vanished
# from both the table and, because the report's own sentence computes the
# total as sum(nt$n), from the total as well. Measured on this project's own
# run: the report asserted "3722 notices are recorded in the JSON findings
# file" while the JSON held 3,725. A sentence that explicitly claims to
# reconcile with another artifact, and does not, is worse than no sentence.
# useNA = "ifany" keeps them, under an explicit "(no criterion)" label rather
# than a bare NA that reads as a rendering bug.
NO_CRITERION_LABEL <- "(no criterion)"

notice_table <- function(df) {
  empty <- data.frame(criterion = character(), level = character(),
                       n = integer(), stringsAsFactors = FALSE)
  if (!nrow(df)) return(empty)
  notices <- df[df$severity == "minor", , drop = FALSE]
  if (!nrow(notices)) return(empty)
  nt <- as.data.frame(table(notices$criterion, useNA = "ifany"),
                      stringsAsFactors = FALSE)
  names(nt) <- c("criterion", "n")
  nt$criterion <- as.character(nt$criterion)
  nt$criterion[is.na(nt$criterion)] <- NO_CRITERION_LABEL
  nt$level <- vapply(nt$criterion, level_for, character(1))
  nt[order(-nt$n), c("criterion", "level", "n")]
}

# ---- one grouping key, used identically everywhere leverage is counted ----
#
# Fixed 2026-08-13, coordinator review, finding 3 (important). classify_fixes()
# used to build this key with paste(criterion, fix_target, sep = ""), no
# delimiter at all; render_plan() built a DIFFERENT key with
# paste(criterion, fix_target), a plain space. Two different join functions
# that happened to agree often enough to pass the existing tests, while a
# comment in classify_fixes() asserted the two could never drift apart. They
# already had. There is now exactly one join to get right: both call
# class_a_key() below, through leverage_key(). U+0001 is not a character
# either criterion strings or fix_target paths contain, so a criterion and a
# fix_target can never concatenate into an accidental collision the way
# "1.4" + "3foo.css" and "1.4.3" + "foo.css" would under plain concatenation
# or even a space-joined key if a path itself ever contained a space.
CLASS_A_KEY_SEP <- "\u0001"
class_a_key <- function(...) paste(..., sep = CLASS_A_KEY_SEP)

# Which class (a) criteria genuinely close per ITEM rather than per shared
# edit. Fixed 2026-08-13, coordinator review, finding 5 (important). A
# broken-embed finding's fix_target is always CART_GENERATOR, the cartridge
# layer's one generator string, the same for every dead video, because that is
# simply where every video URL
# happens to be authored. That is NOT the same shape as an iframe title or a
# contrast rule, where one generator or stylesheet change really does fix
# every instance at once: fixing dead video A's URL does not fix dead video
# B's URL. Grouping broken embeds by (criterion, fix_target) the way a
# genuine shared-edit criterion is grouped reported N dead videos as ONE
# fix and credited only 1 of them as closed once someone did the one edit
# that actually exists to do.
#
# Add a criterion here only when its "already targeted" fix_target names a
# generator or template but each instance still needs its own, independent
# edit within it. Every other class (a) criterion keeps grouping by
# (criterion, fix_target), which is the correct, leverage-preserving
# behaviour for a fix that really is shared.
PER_ITEM_CRITERIA <- c("broken-embed")

# `surface` added 2026-08-13, final whole-branch review, finding I6
# (important). The key omitted it, so render_plan(), which runs over EVERY
# surface at once, merged class (a) rows from two different courses whenever
# they shared a criterion and a fix_target. Two courses that both lack a
# stylesheet is not hypothetical: sheet_label is then the identical literal
# "create a stylesheet first, then this edit lands there once" for both, so
# every contrast finding in both courses collapsed onto ONE bullet carrying
# ONE course's leverage number, and the other course's rows were absent from
# the plan entirely. classify_fixes() was accidentally safe here (the driver
# already calls it per surface, so surface is constant within one call), which
# is exactly why this stayed invisible: the two callers of a deliberately
# shared key disagreed only in the caller that spans surfaces.
leverage_key <- function(criterion, fix_target, id, surface) {
  if (criterion %in% PER_ITEM_CRITERIA) class_a_key(surface, criterion, id)
  else class_a_key(surface, criterion, fix_target)
}

# ---- fix-leverage classification -------------------------------------------
#
# "Class (a)" below is this project's own three-tier leverage label, not the
# WCAG conformance Level A defined above. The two use the same letter by
# coincidence of vocabulary, not by design; a class (a) fix can target a
# Level AA criterion (contrast is the whole reason this tier exists) and a
# class (c) fix can target a Level A criterion (2.4.4 link text, below).
# Read "class (a)" as "one shared edit" and "Level A" as "WCAG conformance
# tier", and do not conflate them when editing this file.
#
# Criteria whose fix is normally a single stylesheet or template edit.
#
# 2.4.1 (Bypass Blocks) was REMOVED 2026-08-13, coordinator review, finding
# 2 (critical, the coordinator's own error, not this file's). The other five
# are genuinely one stylesheet edit. 2.4.1 is not: it is fixed by adding a
# skip link or a landmark region to the shared page TEMPLATE, and this file
# has no notion of a template target, only a stylesheet (sheet_label,
# below). Every 2.4.1 finding was naming a stylesheet edit that cannot
# actually close it; someone follows that instruction, edits the stylesheet,
# and closes nothing. Do NOT add 2.4.1 back without also building a real
# template-target mechanism, which is scope this project has not designed.
# Left off this list, it falls through classify_fixes()'s ordinary branches
# to class (b) or (c) like any criterion this file has no special grouping
# rule for, which is an honest "per page" answer rather than a wrong "one
# shared edit" promise.
CLASS_A_CRITERIA <- c("1.4.3", "1.4.11", "2.4.7", "1.4.4", "1.4.12")

# Criteria whose fix is content a human has to write or commission, one
# instance at a time, no matter what file the instance is authored in. These
# are forced to class (c) BEFORE the "already targeted" branch below, so a
# producer that presets a real fix_target (the cartridge checks all do) can
# never push one of these into class (a) and have its leverage counted as
# though one edit closed all of them.
#
# 1.2.2 added 2026-08-13, final whole-branch review, finding C2, when caption
# findings started being emitted at all. A caption finding arrives with
# fix_target already set to the cartridge generator, because that is where
# the video URL is authored, and without this it would have landed in class
# (a) alongside untitled iframes: one generator edit really does title every
# iframe, and no generator edit has ever captioned a video. Captioning is the
# same shape of work as writing alt text (1.1.1) or link text (2.4.4), which
# is why all three share one list rather than three parallel branches.
HUMAN_CONTENT_CRITERIA <- c("2.4.4", "1.1.1", "1.2.2")

#' Sort findings into fix classes and count their leverage
#'
#' Class (a) is one shared edit that closes many findings, class (b) is per
#' page and automatable, class (c) needs human judgement. The class letters are
#' this project's own leverage labels, not WCAG conformance levels: a class (a)
#' fix can target a Level AA criterion and a class (c) fix a Level A one.
#'
#' @param df A findings data frame.
#' @param target The surface's discovery result. Only `$stylesheet` is read,
#'   for the name a shared edit lands in.
#' @return `df` with `fix_class`, `fix_target`, and `leverage` filled in.
#' @export
classify_fixes <- function(df, target) {
  if (!nrow(df)) return(df)
  sheet <- target$stylesheet
  sheet_label <- if (is.null(sheet) || is.na(sheet)) {
    "create a stylesheet first, then this edit lands there once"
  } else {
    basename(sheet)
  }

  for (i in seq_len(nrow(df))) {
    if (identical(df$severity[i], "review")) {
      df$fix_class[i]  <- "c"
      # A preset fix_target is kept. Fixed 2026-08-13, re-review finding 5:
      # this branch overwrote it unconditionally, so an undetermined-caption
      # row arrived naming the cartridge generator, where the embed is
      # actually authored, and left carrying the generic
      # placeholder instead. The class already says a human decides; the
      # target says WHERE, and throwing it away made a routable finding
      # unroutable. Only a row whose producer set no target gets the
      # placeholder.
      if (is.na(df$fix_target[i])) {
        df$fix_target[i] <- "human judgement, do not automate"
      }
    } else if (df$criterion[i] %in% HUMAN_CONTENT_CRITERIA) {
      # Link text, alt text, and captions are all content a person writes or
      # commissions, and all get the SAME protection for the SAME reason (see
      # HUMAN_CONTENT_CRITERIA above): this branch runs
      # BEFORE the "already targeted" branch below on purpose, for both
      # criteria. Fixed 2026-08-13, coordinator review, finding 9 (minor but
      # free, spotted alongside finding 7). The 1.1.1 half of this
      # condition used to sit AFTER "already targeted", so a hypothetical
      # 1.1.1 finding arriving with a preset fix_target would have been
      # pushed to class (a) despite needing a human-authored sentence per
      # instance -- exactly the asymmetry this branch was already written to
      # avoid for 2.4.4 link text. No producer presets fix_target on a 1.1.1
      # finding today (verified across all five: from_pa11y(),
      # check_filename_alt(), check_missing_fig_alt(), which never do, and
      # check_untitled_iframes(), check_weak_link_text(), which set 4.1.2
      # and 2.4.4 and never 1.1.1), so this was latent, not active. Moved
      # here to match 2.4.4's position, so a future producer cannot silently
      # reintroduce the exact inconsistency finding 7 just closed for
      # message-text routing, this time through a preset fix_target instead.
      #
      # One generator change cannot supply good link text for N links, or a
      # correct alt string for an image it has never seen, so calling either
      # class (a) and counting leverage would promise a fix that does not
      # exist. The project's decision record settled 2.4.4 this way. A cartridge
      # weak-link finding arrives with fix_target already set to modules.yml
      # (where the weblink title is authored), and that target is still
      # correct even though the class stays (c), because writing each
      # sentence is still human work; a hypothetical future 1.1.1 producer
      # with a real preset target gets the identical treatment.
      #
      # This branch also matches on the CRITERION alone, never on message
      # text (finding 7, same review round): HTML_CodeSniffer's H37 wording
      # and axe-core's image-alt wording describe the identical 1.1.1 defect
      # in different words, and matching a message substring is inherently
      # engine-specific, breaking again the moment a tool reworks its
      # phrasing, which is exactly what surfaced this bug in the first
      # place. The criterion is stable across engines; the message is not.
      df$fix_class[i]  <- "c"      # every alt or link-text string is a human sentence
      if (is.na(df$fix_target[i])) df$fix_target[i] <- df$file[i]
    } else if (df$criterion[i] %in% CLASS_A_CRITERIA) {
      df$fix_class[i]  <- "a"
      df$fix_target[i] <- sheet_label
    } else if (!is.na(df$fix_target[i])) {
      # Already targeted by its producer. Genuinely (a): whether this is a
      # true shared-edit fix (an iframe title the cartridge generator can
      # emit for every frame from one change) or a per-item fix that merely
      # shares a generator file (broken embeds) is NOT decided here -- it is
      # decided once, at leverage time, by leverage_key() and
      # PER_ITEM_CRITERIA above, so both classify_fixes() and render_plan()
      # agree on which rows a single edit actually closes.
      df$fix_class[i]  <- "a"
    } else {
      df$fix_class[i]  <- "b"
      df$fix_target[i] <- df$file[i]
    }
  }

  # Leverage: how many findings one class (a) edit closes. Grouped by
  # leverage_key(), shared with render_plan() below (finding 3), which is
  # (criterion, fix_target) for a genuine shared-edit criterion and
  # (criterion, id) -- unique per row -- for anything listed in
  # PER_ITEM_CRITERIA (finding 5), so a per-item fix can never be credited
  # as closing more than the one finding it actually closes.
  a_idx <- which(df$fix_class == "a")
  if (length(a_idx)) {
    keys <- vapply(a_idx, function(i)
      leverage_key(df$criterion[i], df$fix_target[i], df$id[i],
                   df$surface[i]), character(1))
    for (k in unique(keys)) {
      grp <- a_idx[keys == k]
      df$leverage[grp] <- length(grp)
    }
  }
  df$leverage[df$fix_class != "a"] <- 1L
  df
}

# ---- a note for a target discover_target() could not find any pages under -
#
# Not a finding. discover_target() (Task 3) returns pages = character(0)
# when nothing could be identified as a real page; an audit driver calling
# it knows that BEFORE it ever runs pa11y. zero_page_note() formats that
# into a human-readable line naming the surface, the path, and the
# framework, for a caller to fold into meta$zero_page_targets as
# SUPPLEMENTARY detail. It is no longer the thing that triggers the "nothing
# was examined" warning in render_report() below (see meta$pages_examined
# and finding 4): this note explains WHY a surface had zero pages once the
# unconditional pages_examined count has already said THAT it did.
zero_page_note <- function(surface, target) {
  where <- target$output_dir
  if (is.null(where) || is.na(where)) where <- target$repo %||% "(unknown path)"
  sprintf(
    "%s: discover_target() found 0 pages under %s (framework: %s). Nothing was examined here. Do not read this as a clean audit; check target discovery before trusting an empty result for this surface.",
    surface, where, target$framework %||% "unknown")
}

sev_order <- function(s) match(s, c("serious", "moderate", "review", "minor"))

# A finding's detail carries "[mode: rendered]" or "[mode: source-heuristic]"
# when check_missing_fig_alt(), in the source checks, produced it, recording
# whether the finding was confirmed against a real rendered image or only
# guessed from source code patterns because nothing was rendered yet. Fixed
# strings, not a loose "fallback" synonym match, so this only fires on the
# literal marker the check actually writes.
MODE_RENDERED_MARK   <- "[mode: rendered]"
MODE_HEURISTIC_MARK  <- "[mode: source-heuristic]"

# How a finding with no WCAG criterion is named in the report.
#
# Fixed 2026-08-13, final whole-branch review, finding M11 (minor). 22
# findings rendered their heading as "### NA" and their criterion line as
# "- **WCAG:** NA", which reads as a rendering bug rather than as the real,
# deliberate state it is: the rule that fired carries no WCAG success
# criterion at all. That state is reached two ways, and the wording covers
# both without claiming which: an axe-core rule confirmed to carry no WCAG
# tag (AXE_NO_WCAG_TAG, in the finding model), or any code this project's own
# mapping does not recognize, which warns separately at parse time. The
# report cannot tell them apart, because `code` is deliberately not a
# findings column, so it says the true thing both share rather than naming an
# engine it would sometimes be wrong about.
NO_CRITERION_TEXT <- "no WCAG criterion (the rule that fired carries no success criterion)"

criterion_label <- function(criterion) {
  if (is.null(criterion) || is.na(criterion)) NO_CRITERION_TEXT else criterion
}

confidence_line_for <- function(detail) {
  d <- chr0(detail)
  if (grepl(MODE_HEURISTIC_MARK, d, fixed = TRUE)) {
    paste("- **Confidence:** not verified. This was matched from source code",
          "patterns because nothing was rendered for this file yet, not",
          "confirmed against a real image. Render the file and re-audit",
          "before treating it as certain.")
  } else if (grepl(MODE_RENDERED_MARK, d, fixed = TRUE)) {
    "- **Confidence:** verified against a rendered image."
  } else {
    NULL
  }
}

#' Render the findings report
#'
#' Writes the human-readable markdown document: the coverage banners, the
#' summary, the media inventory, the notice counts, and one section per
#' finding. `meta$pages_examined` and `meta$surfaces` are both required, and
#' their absence is stated loudly rather than left to read as a clean audit.
#'
#' @param df A classified findings data frame, already notice-free.
#' @param meta The run's metadata: `date`, `tool`, `standard`,
#'   `pages_examined`, `surfaces`, `declared`, `failed_pages`,
#'   `cartridge_files`, `media_inventory`, `notices`, `zero_page_targets`.
#' @param path Where to write the markdown.
#' @return `path`, invisibly.
#' @export
render_report <- function(df, meta, path) {
  # Fixed 2026-08-13, coordinator review, finding 4 (important). A 0-row
  # findings frame cannot tell "21 pages audited, nothing wrong" from "0
  # pages audited, nothing examined" apart on its own; both print "0
  # findings across 0 files and 0 surfaces" below with nothing to
  # distinguish them. meta$pages_examined is counted independently of df, by
  # whoever ran the audit, and is checked UNCONDITIONALLY
  # here, not only when a caller also remembers to pass
  # meta$zero_page_targets. A safeguard that only works when a caller
  # remembers to invoke it is not a safeguard: this one fires from the
  # absence of the field itself.
  # unlist(), not a bare read: meta$pages_examined is written to the JSON as
  # a named LIST (as.list(), so the JSON is an object and each count stays
  # attached to its surface name rather than becoming a bare positional
  # array -- finding M12), and a caller that hands this function the same
  # meta it hands write_findings() therefore passes a list here. unlist()
  # accepts both shapes and returns the named integer vector this function
  # has always worked with; unlist(NULL) is NULL, so an absent field still
  # reads as absent below.
  pe <- unlist(meta$pages_examined)
  sf <- meta$surfaces
  # Fixed 2026-08-13, coordinator review, finding 6 (moderate), then finding
  # 8 (moderate, the tenth instance of one failure shape in this build).
  # Finding 6: the earlier version validated pe's VALUES (present, no NA, no
  # zero) but never its NAMES. c(textbook = 21L), where a second real
  # surface was simply never included, passed every check, fired neither
  # banner, and quietly undercounted sum(pe). A missing NAME was checked
  # against known_surfaces, built from df's own rows plus meta$surfaces, an
  # authoritative list a driver could OPTIONALLY supply -- the only way to
  # catch a surface with ZERO findings, which never appears in df at all.
  #
  # Finding 8: meta$surfaces being optional was itself the next floor in the
  # same chain. A driver that omitted a surface from pages_examined AND
  # never supplied meta$surfaces at all left known_surfaces silently equal
  # to unique(df$surface), so the very case meta$surfaces exists to catch
  # (a surface with zero findings, invisible to df) went uncaught again, one
  # level down, with no banner. Ruling: meta$surfaces is now REQUIRED, and
  # its own absence is exactly as loud as an absent pages_examined, folded
  # into the same pe_ok gate and the same NOT REPORTED banner below, because
  # a page count cannot be judged complete without a declared scope to be
  # complete AGAINST. This is treated as a terminating point, not one more
  # floor: past requiring a driver to state both what it found (pages_examined)
  # and what it intended to audit (surfaces), any further gap is a defect in
  # how the driver BUILT that declaration against the project's real
  # structure (e.g. a stale, hardcoded surface list that never learned about
  # a newly added surface type), which is a driver-code-correctness question
  # for Task 7/8's own tests against discover_target(), not something a pure
  # rendering function fed only (df, meta) can independently verify without
  # importing course discovery into the renderer, a boundary this file does
  # not cross. See the addendum in the Task 6 report for the fuller argument.
  pe_named <- !is.null(pe) && length(pe) > 0 &&
    !is.null(names(pe)) && all(nzchar(names(pe)))
  pe_values_ok <- pe_named && !anyNA(pe)
  sf_declared  <- !is.null(sf) && length(sf) > 0 && is.character(sf) && all(nzchar(sf))
  pe_ok <- pe_values_ok && sf_declared

  known_surfaces <- if (pe_ok) {
    unique(c(if (nrow(df)) as.character(df$surface) else character(), sf))
  } else {
    character()
  }
  pe_missing_surfaces <- if (pe_ok) setdiff(known_surfaces, names(pe)) else character()
  pe_zero_surfaces    <- if (pe_ok) names(pe)[pe == 0L] else character()

  L <- c(
    sprintf("# Accessibility findings, %s", meta$date),
    "",
    sprintf("Standard: %s. Tool: %s.", meta$standard %||% "WCAG 2.1 AA",
            meta$tool %||% "pa11y"),
    "")

  if (!pe_ok) {
    reasons <- c(
      if (!pe_values_ok)
        "pages_examined is missing, unnamed, or contains NA",
      if (!sf_declared)
        "meta$surfaces (the driver's declared list of surfaces it intended to audit) is missing or empty")
    L <- c(L,
      "## PAGES EXAMINED: NOT REPORTED",
      "",
      sprintf("This report cannot verify complete audit coverage: %s.",
              paste(reasons, collapse = "; and ")),
      paste("An audit of zero pages and a clean audit of many pages produce",
            "the identical findings table below unless both a verified page",
            "count and a verified declaration of intended scope are",
            "present. Do not read a low or zero finding count as evidence",
            "of a clean course until both are supplied."),
      "")
  } else if (length(pe_zero_surfaces) || length(pe_missing_surfaces)) {
    detail <- meta$zero_page_targets %||% character()
    L <- c(L,
      "## Nothing was examined here",
      "",
      paste("The surfaces below are not accounted for in pages_examined.",
            "This is not the same thing as an audit that ran and found no",
            "problems: here, nothing was examined at all, or this report",
            "cannot tell whether it was, so none of this must be read as",
            "a clean result."),
      "",
      if (length(pe_zero_surfaces))
        sprintf("- %s: 0 pages examined.", pe_zero_surfaces),
      if (length(pe_missing_surfaces))
        sprintf("- %s: no pages_examined entry at all. Do not assume this surface is clean; its count was never reported.",
                pe_missing_surfaces),
      if (length(detail)) sprintf("- %s", detail),
      "")
  }

  pages_line <- if (!pe_ok) {
    "Pages examined: NOT REPORTED."
  } else if (length(pe_missing_surfaces)) {
    # The total itself must not read as clean when it is known to be
    # incomplete: sum(pe) silently undercounts exactly when a surface is
    # missing, which is the core of finding 6. Say so at the point where the
    # number is shown, not only in the banner above.
    sprintf("Pages examined: %d (INCOMPLETE: no entry for %s).",
            sum(pe), paste(pe_missing_surfaces, collapse = ", "))
  } else {
    sprintf("Pages examined: %d.", sum(pe))
  }
  # ---- coverage: the DECLARED scope, and the pages that could not be read -
  #
  # Added 2026-08-13, final whole-branch review, finding C1 (critical).
  # meta$pages_examined is an EMPIRICAL count accumulated inside the audit
  # loops; meta$declared is what the run's own target discovery said it
  # intended to audit, from a different function on a different code path.
  # Printing only one of them is what let a neutered audit loop read as a
  # clean run: the two numbers have to be shown together, and their
  # disagreement stated, or the comparison exists only in principle.
  #
  # meta$failed_pages is the third distinct question, and it is NOT the same
  # as either: a page pa11y could not audit at all is a page this report
  # says nothing about. Reported unconditionally, including when it is zero
  # and when the driver did not report it, because silence here is
  # indistinguishable from success.
  declared    <- unlist(meta$declared)
  declared_ok <- !is.null(declared) && length(declared) > 0 &&
    !is.null(names(declared)) && all(nzchar(names(declared))) && !anyNA(declared)
  shortfall <- character()
  if (pe_ok && declared_ok) {
    for (s in names(declared)) {
      got  <- if (s %in% names(pe)) as.integer(pe[[s]]) else 0L
      want <- as.integer(declared[[s]])
      if (got < want) {
        shortfall <- c(shortfall, sprintf(
          "%s: %d of %d declared page(s) actually examined.", s, got, want))
      }
    }
  }

  coverage <- if (!pe_ok) {
    character()
  } else if (declared_ok) {
    c(sprintf("Coverage: %d page(s) examined against %d page(s) this run declared in scope.",
              sum(pe), sum(declared)),
      if (length(shortfall)) c(
        paste("**COVERAGE SHORTFALL.** A surface examined fewer pages than",
              "target discovery said it intended to audit. The findings",
              "below do not cover this course completely, and a low count",
              "for these surfaces is not evidence that they are clean:"),
        sprintf("- %s", shortfall)))
  } else {
    paste("Coverage: this run declared no intended page counts, so the",
          "examined count above cannot be checked against an intended",
          "scope. An audit loop that never ran would look identical to one",
          "that ran and found nothing.")
  }

  # What the page count MEANS, stated where the number is.
  #
  # Added 2026-08-13: the qualifier lived only in the audit's own
  # documentation, and a reader of
  # this report should not have to open another document to learn that a
  # cartridge surface's figure counts wiki pages READ across every `.imscc`
  # under that repo, not distinct pages. When a surface's count is spread
  # across more than one cartridge (an export plus its own round-trip copy,
  # which is a normal thing for a repo to hold), the same page is counted
  # once per file. Driven by meta$cartridge_files, which the driver measures
  # in the same loop that does the reading, so this says nothing the run did
  # not observe.
  cfl <- unlist(meta$cartridge_files)
  cart_note <- if (is.null(cfl) || !length(cfl)) {
    character()
  } else {
    c(sprintf("Cartridge surfaces count wiki pages READ, not distinct pages: %s.",
              paste(sprintf("%s spans %d .imscc file(s)", names(cfl), cfl),
                    collapse = "; ")),
      if (any(cfl > 1L))
        paste("At least one cartridge surface above spans more than one",
              "`.imscc`. If those files are the same course (an export and",
              "its round-trip copy), every wiki page in both is counted",
              "once per file, so the figure overstates distinct pages",
              "covered while remaining exact about files read."))
  }

  fp <- meta$failed_pages
  fail_line <- if (is.null(fp)) {
    paste("Pages the audit tool could not read: not reported by this run.",
          "A page the tool failed on is a page this report says nothing",
          "about, so an unreported failure count leaves the totals above",
          "unverifiable.")
  } else if (!length(fp)) {
    "Pages the audit tool could not read: 0."
  } else {
    sprintf(paste("Pages the audit tool could not read: %d (%s). These are",
                  "NOT included in the examined count above, and nothing in",
                  "this report covers them; do not read their absence from",
                  "the findings as a clean result."),
            length(fp), paste(fp, collapse = ", "))
  }

  L <- c(L,
    "## Summary",
    "",
    sprintf("%d findings across %d files and %d surfaces. %s",
            nrow(df), length(unique(df$file)), length(unique(df$surface)),
            pages_line),
    "",
    coverage,
    "",
    cart_note,
    if (length(cart_note)) "",
    fail_line,
    "")

  # ---- non-HTML media, inventoried rather than audited ---------------------
  #
  # Added 2026-08-13, final whole-branch review, finding I4 (important).
  # inventory_media(), in the cartridge layer, existed, was tested, and was
  # called by nothing, while the audit's own documentation said non-HTML media
  # "is inventoried, not audited ... so nothing goes missing by silent
  # omission". The inventory
  # was itself the thing going missing by silent omission. Counts by surface
  # and kind here; the full file list rides in the JSON, because a
  # thousand-row table in a document meant to be read would bury the
  # findings the plan is built around.
  media_lines <- character()
  mi <- meta$media_inventory
  if (!is.null(mi) && length(mi)) {
    rows <- character()
    for (s in names(mi)) {
      inv <- mi[[s]]
      # inventory_media() returns NULL, not a 0-row frame, when a repo has
      # neither images nor PDFs. A surface with nothing to inventory still
      # gets a row: "no media found" and "never looked" must not print the
      # same way, which is the same rule pages_examined follows.
      if (is.null(inv) || !nrow(inv)) {
        rows <- c(rows, sprintf("| %s | (nothing found) | 0 | inventory ran and found no non-HTML media |", s))
        next
      }
      for (k in unique(inv$kind)) {
        sub <- inv[inv$kind == k, , drop = FALSE]
        rows <- c(rows, sprintf("| %s | %s | %d | %s |", s, k, nrow(sub),
                                sub$note[1]))
      }
    }
    media_lines <- c("## Non-HTML media, inventoried not audited", "",
      paste("pa11y and the HTML-layer checks structurally cannot see these",
            "files, so they are listed rather than judged. Every path is in",
            "the JSON findings file. Deciding whether a listed file is in",
            "scope, a working file, or published but out of scope is an",
            "editorial call, not one this inventory makes."),
      "", "| Surface | Kind | Files | Note |", "|---|---|---:|---|", rows, "")
  }
  if (nrow(df)) {
    tb <- as.data.frame(table(df$surface, df$fix_class))
    names(tb) <- c("surface", "class", "n")
    tb <- tb[tb$n > 0, ]
    L <- c(L, "| Surface | Fix class | Findings |", "|---|---|---:|",
           sprintf("| %s | %s | %d |", tb$surface, tb$class, tb$n), "")
  }
  # The inventory follows the summary's own tables rather than splitting
  # them: it is a list of what was NOT audited, and it has to survive a
  # zero-finding run, so it sits outside the nrow(df) branch on both sides.
  L <- c(L, media_lines)
  if (nrow(df)) {

    # Notices are counted, not listed, and are never in df at this point:
    # the caller filtered them out with strip_notices() before df ever
    # reached classify_fixes() (see the notices section above; finding 1).
    # That is what makes this table and the detail section below it
    # reconcile: both are built from the exact same, already notice-free
    # df, with no filtering happening in between them anymore. meta$notices
    # -- built by the SAME caller, from the full frame, via notice_table()
    # -- is the only place notice counts appear in this document. The
    # project's decision record settled why notices are summarized rather than
    # listed at all: 3,725 of them in one real full run (the
    # measured figure; the "roughly 16,000" this comment used to cite was an
    # estimate nobody had checked, corrected 2026-08-13, finding M16) would
    # bury the class (a) items the plan is built around, and the JSON keeps
    # every one.
    nt <- meta$notices
    if (!is.null(nt) && nrow(nt)) {
      L <- c(L, "## Notices, summarized", "",
        sprintf("%d notices are recorded in the JSON findings file and counted here rather than listed. They are advisory: each marks something a tool cannot decide, so they need a human read rather than a fix.",
                sum(nt$n)),
        "", "| Criterion | Level | Count |", "|---|---|---:|",
        sprintf("| %s | %s | %d |", nt$criterion,
                ifelse(is.na(nt$level), "", nt$level), nt$n), "")
    }

    L <- c(L, "## Findings", "")
    ord <- order(df$fix_class, sev_order(df$severity), df$file)
    for (i in ord) {
      lvl <- level_for(df$criterion[i])
      # R16: never print a level this project did not look up. Print the
      # criterion number alone when level_for() has no entry for it, rather
      # than a heuristic or a default.
      crit_label <- criterion_label(df$criterion[i])
      wcag_line <- if (!is.na(lvl)) {
        sprintf("- **WCAG:** %s Level %s", crit_label, lvl)
      } else {
        sprintf("- **WCAG:** %s", crit_label)
      }
      detail_i <- chr0(df$detail[i])
      L <- c(L,
        sprintf("### %s  `%s`", crit_label, df$file[i]),
        "",
        sprintf("- **Issue:** %s", df$issue[i]),
        # count > 1 means pa11y could not distinguish the instances, so this
        # row is an aggregate rather than one location. Saying so matters:
        # a reader who thinks it is one occurrence will fix one and move on.
        if (!is.na(df$count[i]) && df$count[i] > 1L)
          sprintf("- **Occurrences:** %d on this page. pa11y reports no selector for this check, so the instances cannot be located individually. Progress shows as this number falling.",
                  df$count[i]),
        wcag_line,
        sprintf("- **Severity:** %s", df$severity[i]),
        sprintf("- **Fix class:** (%s), target: %s",
                df$fix_class[i], df$fix_target[i]),
        if (!is.na(df$selector[i])) sprintf("- **Selector:** `%s`", df$selector[i]),
        if (nzchar(detail_i)) sprintf("- **Detail:** %s", detail_i),
        # D: a finding produced by guessing from source patterns must never
        # read the same as one confirmed against a rendered image.
        confidence_line_for(df$detail[i]),
        "")
    }
  }
  writeLines(L[!vapply(L, is.null, logical(1))], path)
  invisible(path)
}

# No deadline parameter, and no deadline line in the output. Settled
# 2026-08-13: these courses are built compliant, not built toward a date.
# Earlier versions printed "compliance deadline: not verified", which framed
# an absent date as a gap someone ought to close. It is not a gap. The plan
# is ordered by leverage and student impact, which is the right ordering
# whether or not a deadline exists. Do not add the parameter back.

#' Render the remediation plan
#'
#' A checklist ordered by leverage, then by student impact: class (a) items
#' first, because each one closes many findings at once. Class (a) bullets are
#' deduplicated by the same key [classify_fixes()] counts leverage with, so a
#' per-item fix prints one bullet per item rather than collapsing into one.
#'
#' @param df A classified findings data frame.
#' @param meta The run's metadata. Only `date` is read.
#' @param path Where to write the markdown.
#' @return `path`, invisibly.
#' @export
render_plan <- function(df, meta, path) {
  head <- c(
    sprintf("# Accessibility remediation plan, %s", meta$date),
    "",
    paste("Ordered by leverage, then by student impact. Work top to bottom.",
          "This plan carries no dates by design."),
    "",
    "Work top to bottom. Class (a) items come first because each one closes",
    "many findings at once, so the count falls fastest there. A \"closes N",
    "findings\" count is how many finding ROWS one edit closes, not how many",
    "occurrences on the page: a row with a count above 1 (see the report)",
    "still contributes only 1 to this number, so the real impact of a class",
    "(a) edit can be larger than what is printed here.",
    "")

  body <- character()
  for (cls in c("a", "b", "c")) {
    sub <- df[df$fix_class == cls, , drop = FALSE]
    if (!nrow(sub)) next
    label <- switch(cls,
      a = "Class (a): one shared edit, closes many pages",
      b = "Class (b): per page, automatable",
      c = "Class (c): needs human judgement")
    body <- c(body, sprintf("## %s", label), "")
    sub <- sub[order(sev_order(sub$severity), -sub$leverage), , drop = FALSE]
    seen <- character()
    for (i in seq_len(nrow(sub))) {
      # Same key as classify_fixes()'s leverage grouping (finding 3): a
      # genuine shared-edit criterion dedupes by (criterion, fix_target); a
      # PER_ITEM_CRITERIA criterion (finding 5, e.g. broken-embed) dedupes by
      # (criterion, id), which is unique per row, so N independent items
      # print N independent bullets instead of collapsing into one.
      key <- leverage_key(sub$criterion[i], sub$fix_target[i], sub$id[i],
                          sub$surface[i])
      if (cls == "a" && key %in% seen) next
      seen <- c(seen, key)
      lev <- if (cls == "a")
        sprintf(" Closes %d findings (a finding can itself represent more than one occurrence).",
                sub$leverage[i]) else ""
      # The surface is named in the bullet because it is now part of the
      # leverage key (finding I6): two courses that both lack a stylesheet
      # produce two bullets whose criterion and fix_target text are
      # word-for-word identical, and without the surface a reader cannot tell
      # which course each one is for.
      body <- c(body, sprintf("- [ ] **%s** in `%s` (%s). %s%s",
        sub$criterion[i], sub$fix_target[i], sub$surface[i], sub$issue[i],
        lev), "")
    }
  }

  tail <- c(
    "## Re-audit",
    "",
    "- [ ] Rebuild the affected sites so the fixes reach the rendered output.",
    "- [ ] Run the audit again.",
    "- [ ] Compare against the previous findings JSON. Every item above should",
    "      appear under `fixed`, and `new` should be empty. A nonempty `new`",
    "      means a fix introduced a regression.",
    "")

  writeLines(c(head, body, tail), path)
  invisible(path)
}
