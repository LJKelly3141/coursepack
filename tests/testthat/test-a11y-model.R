# Ported from the snapshot's own self-checking audit test script: the
# finding-model sections. Each printed banner there is a test_that() block
# here and each check() is an expectation carrying the original label. Real
# chapter file names from the course the snapshot audited are replaced with
# neutral ones; nothing else about the assertions changed.
#
# Two sections of the map could not be ported here, because the libraries
# they drive have not moved into the package yet. Both are named where they
# would have gone, so the task that moves those libraries can pick them up:
# the fixture-driven "distinct ids in one file" section (it calls the custom
# checks) and the M11 "no WCAG criterion says so" section (it renders a
# report).

test_that("finding_id", {
  a <- finding_id("textbook", "chapter-03.qmd", "1.1.1", "#fig-1 > img")
  b <- finding_id("textbook", "chapter-03.qmd", "1.1.1", "#fig-1 > img")
  c2 <- finding_id("textbook", "chapter-03.qmd", "1.1.1", "#fig-2 > img")
  expect_identical(identical(a, b), TRUE, info = "id is stable")
  expect_identical(identical(a, c2), FALSE, info = "id varies by selector")
  expect_identical(nchar(a), 12L, info = "id is a short hash")

  # pa11y's `code` joined the id key so two different checks landing on the
  # same element under the same criterion (H37 "missing alt" vs G73/G74
  # "needs a long description", both criterion 1.1.1, both real codes) no
  # longer collide.
  code_h37 <- "WCAG2AA.Principle1.Guideline1_1.1_1_1.H37"
  code_g73 <- "WCAG2AA.Principle1.Guideline1_1.1_1_1.G73,G74"
  d1 <- finding_id("textbook", "chapter-03.qmd", "1.1.1", "#fig-1 > img", code_h37)
  d2 <- finding_id("textbook", "chapter-03.qmd", "1.1.1", "#fig-1 > img", code_g73)
  d1_again <- finding_id("textbook", "chapter-03.qmd", "1.1.1", "#fig-1 > img", code_h37)
  expect_identical(identical(d1, d2), FALSE,
    info = "id varies by code when everything else matches")
  expect_identical(identical(d1, d1_again), TRUE,
    info = "id with an explicit code is still stable across two calls")
})

test_that("from_pa11y aggregation for selector-less issues", {
  # An earlier fix disambiguated same-key issues with a positional occurrence
  # ordinal. That made ids distinct but not stable: the ordinal shifts
  # whenever a sibling earlier in the colliding group is added or removed by
  # an unrelated edit, so a real fix and a real regression both go invisible
  # to diff_findings(). Replaced with aggregation: when pa11y gives no
  # selector, every instance sharing (surface, file, criterion) collapses
  # into ONE finding carrying a `count`, rather than enumerating
  # pseudo-instances this tool cannot actually tell apart. This block builds
  # a synthetic pa11y payload matching the real shape that motivated the fix
  # (28 of 29 real WCAG 1.4.10 reflow issues on one rendered chapter had an
  # empty selector) and also exercises the context-as-empty-list guard, since
  # real pa11y output mixes both.
  code_h37 <- "WCAG2AA.Principle1.Guideline1_1.1_1_1.H37"
  code_g73 <- "WCAG2AA.Principle1.Guideline1_1.1_1_1.G73,G74"

  mk_reflow_issue <- function(msg) list(
    code = "WCAG2AA.Principle1.Guideline1_4.1_4_10.G000", type = "warning",
    typeCode = 2L, message = msg, context = list(), selector = "",
    runner = "htmlcs", runnerExtras = list())

  raw_two  <- list(mk_reflow_issue("reflow A"), mk_reflow_issue("reflow B"))
  raw_five <- list(mk_reflow_issue("reflow A"), mk_reflow_issue("reflow B"),
                    mk_reflow_issue("reflow C"), mk_reflow_issue("reflow D"),
                    mk_reflow_issue("reflow E"))
  df_two  <- from_pa11y(raw_two,  "textbook", "chapter-03.html")
  df_five <- from_pa11y(raw_five, "textbook", "chapter-03.html")

  expect_identical(nrow(df_two), 1L,
    info = "selector-less issues collapse to one aggregate row")
  expect_identical(df_two$count, 2L,
    info = "aggregate count reflects the real instance count (2)")
  expect_identical(df_five$count, 5L,
    info = "aggregate count reflects the real instance count (5)")
  expect_identical(identical(df_two$id, df_five$id), TRUE,
    info = "an aggregate's id does not change when its count changes")
  expect_identical(
    identical(df_two$id, from_pa11y(raw_two, "textbook", "chapter-03.html")$id),
    TRUE, info = "calling from_pa11y twice on identical input gives identical ids")

  raw_other_criterion <- list(
    list(code = "WCAG2AA.Principle1.Guideline1_1.1_1_1.H37", type = "error",
         typeCode = 1L, message = "alt A", context = list(), selector = "",
         runner = "htmlcs", runnerExtras = list()),
    list(code = "WCAG2AA.Principle1.Guideline1_1.1_1_1.H37", type = "error",
         typeCode = 1L, message = "alt B", context = list(), selector = "",
         runner = "htmlcs", runnerExtras = list()))
  df_other <- from_pa11y(raw_other_criterion, "textbook", "chapter-03.html")
  expect_identical(identical(df_two$id, df_other$id), FALSE,
    info = "two different criteria on the same page get different aggregate ids")

  expect_identical(all(is.na(df_two$level)), TRUE,
    info = "from_pa11y does not assert a level it cannot derive")

  # A real selector is not aggregated: still its own row, count 1, id
  # computed the same way finding_id() computes it directly, code included.
  raw_with_selector <- list(list(
    code = code_h37, type = "error",
    typeCode = 1L, message = "Img element missing an alt attribute.",
    context = list(), selector = "#fig-1 > img", runner = "htmlcs",
    runnerExtras = list()))
  df_sel <- from_pa11y(raw_with_selector, "textbook", "chapter-03.html")
  expect_identical(df_sel$count, 1L, info = "a real selector still gets count 1")
  expect_identical(
    identical(df_sel$id,
              finding_id("textbook", "chapter-03.html", "1.1.1",
                         "#fig-1 > img", code_h37)),
    TRUE, info = "a real-selector id matches finding_id on the same 5 fields")

  # The real motivating case: two different pa11y checks (different `code`)
  # landing on the SAME element under the SAME criterion. Before the fix
  # these collapsed to one id (verified: 8 such pairs in a real 699-issue
  # probe, e.g. H37 "missing alt" plus G73/G74 "needs a long description" on
  # the same <img>). They must now be told apart.
  raw_same_element_two_checks <- list(
    list(code = code_h37, type = "error", typeCode = 1L,
         message = "Img element missing an alt attribute.", context = list(),
         selector = "#fig-1 > img", runner = "htmlcs", runnerExtras = list()),
    list(code = code_g73, type = "error", typeCode = 1L,
         message = "If this image cannot be fully described...",
         context = list(), selector = "#fig-1 > img", runner = "htmlcs",
         runnerExtras = list()))
  df_two_checks <- from_pa11y(raw_same_element_two_checks, "textbook",
                               "chapter-03.html")
  expect_identical(length(unique(df_two_checks$id)), 2L,
    info = "two different checks on the same element get distinct ids")

  # The SAME check (same code) CAN legitimately report two distinct,
  # template-fixed messages against the identical selector. Real motivating
  # case, verified live on every one of 21 real chapter pages:
  # HTML_CodeSniffer's G141 check reports both "this h2 appears to be the
  # primary heading" and "this h2 should be an h1" against the same
  # "#toc-title" element. Before the fix the two rows shared one id (same
  # criterion, code, AND selector) and report_and_dedup() collapsed them the
  # moment two repos were audited together, discarding one silently, exactly
  # the fig-alt bug class one level over. The fix mirrors the selector-less
  # aggregation path: they collapse to ONE row with count = 2, honestly
  # representing "two complaints, one location", rather than either losing
  # one silently (the bug) or fabricating a second, unstable id out of
  # message text (the alternative the model file's own header already
  # rejects for contrast messages).
  raw_same_selector_two_messages <- list(
    list(code = "WCAG2AA.Principle1.Guideline1_3.1_3_1_A.G141", type = "error",
         typeCode = 1L,
         message = "This h2 element appears to be the primary document heading, and should be an h1 element.",
         context = list(), selector = "#toc-title", runner = "htmlcs",
         runnerExtras = list()),
    list(code = "WCAG2AA.Principle1.Guideline1_3.1_3_1_A.G141", type = "error",
         typeCode = 1L,
         message = "This h2 element should be an h1 to be the primary document heading.",
         context = list(), selector = "#toc-title", runner = "htmlcs",
         runnerExtras = list()))
  df_same_sel_two_msg <- from_pa11y(raw_same_selector_two_messages, "textbook",
                                     "chapter-01.html")
  expect_identical(nrow(df_same_sel_two_msg), 1L,
    info = "same code + same selector + different message: one aggregate row, not two")
  expect_identical(df_same_sel_two_msg$count, 2L,
    info = "same code + same selector + different message: count reflects both")
  expect_identical(df_same_sel_two_msg$selector, "#toc-title",
    info = "same code + same selector + different message: the real selector is kept")
  expect_identical(
    identical(df_same_sel_two_msg$id,
              from_pa11y(raw_same_selector_two_messages, "textbook",
                         "chapter-01.html")$id),
    TRUE, info = "calling from_pa11y twice on this identical input gives the identical id")
})

test_that("axe_criterion, verified against axe-core's own source", {
  # axe's `code` is a bare rule name ("color-contrast"), not a dotted
  # technique code, so pa11y_criterion() (built for htmlcs) cannot read a
  # WCAG number out of it and always returned NA for an axe-sourced issue
  # before this fix. Every entry in the table was fetched from axe-core's own
  # v4.11.0 rule metadata (the version this project's real pa11y output
  # actually links to), not written from memory.
  expect_identical(axe_criterion("color-contrast"), "1.4.3",
    info = "color-contrast maps to 1.4.3 (axe-core tag wcag143)")
  expect_identical(axe_criterion("image-alt"), "1.1.1",
    info = "image-alt maps to 1.1.1 (axe-core tag wcag111)")
  expect_identical(axe_criterion("link-name"), "2.4.4",
    info = "link-name maps to 2.4.4, not 4.1.2, so fix classification routes it to class c")
  expect_identical(axe_criterion("scrollable-region-focusable"), "2.1.1",
    info = "scrollable-region-focusable maps to 2.1.1, the AA-relevant tag")
  expect_identical(is.na(axe_criterion("landmark-unique")), TRUE,
    info = "landmark-unique (best-practice only, no WCAG tag) is honestly NA, not guessed")
  expect_identical(is.na(axe_criterion("heading-order")), TRUE,
    info = "heading-order (best-practice only) is honestly NA")
  expect_identical(is.na(axe_criterion("empty-table-header")), TRUE,
    info = "empty-table-header (best-practice only) is honestly NA")

  # An unrecognized code warns (the third state), so this consumes that
  # warning explicitly rather than letting it escape into the run's output.
  # withCallingHandlers + muffleWarning is used throughout this block instead
  # of suppressWarnings() specifically because the point of several
  # expectations below is COUNTING whether a warning fired, not just hiding
  # it; suppressWarnings() would make that uncountable.
  unseen_warned <- 0L
  withCallingHandlers(
    expect_identical(is.na(axe_criterion("some-future-axe-rule")), TRUE,
      info = "an axe code never seen before returns NA, not a guess"),
    warning = function(w) { unseen_warned <<- unseen_warned + 1L; invokeRestart("muffleWarning") })
  expect_identical(unseen_warned, 1L, info = "...and warns exactly once when it does")
  expect_identical(is.na(axe_criterion(NA_character_)), TRUE,
    info = "axe_criterion(NA) is NA, not an error")

  # The table's coverage is verified by its SIZE as well as by spot-checking
  # individual entries, because a size check is what catches a future fetch
  # that fails partway (e.g. a network error mid-loop silently leaving the
  # table with 40 entries instead of 74) that a handful of
  # present-and-correct spot checks would not notice on their own. 74 rules
  # with a real WCAG tag, 30 confirmed to carry none, both counted directly
  # against axe-core v4.11.0's real, complete rule set (104 total .json rule
  # files under lib/rules).
  expect_identical(length(AXE_CRITERION), 74L,
    info = "AXE_CRITERION covers all 74 verified axe-core v4.11.0 rules with a real WCAG tag")
  expect_identical(length(AXE_NO_WCAG_TAG), 30L,
    info = "AXE_NO_WCAG_TAG covers all 30 verified rules confirmed to carry none")
  expect_identical(length(intersect(names(AXE_CRITERION), AXE_NO_WCAG_TAG)), 0L,
    info = "the two tables never share a rule name (each rule is in exactly one)")

  # The live-confirmed motivating case for widening the table beyond the 7
  # codes one course happens to trigger: html-has-lang carries a real WCAG
  # tag (wcag311 to 3.1.1) and was absent from the 7-code table.
  expect_identical(axe_criterion("html-has-lang"), "3.1.1",
    info = "html-has-lang maps to 3.1.1 (axe-core tag wcag311), absent from the earlier 7-code table")

  # The warn-once cache used to be keyed on `code` alone, but the audit
  # driver loops over every repo named on its command line WITHIN ONE R
  # process, one session, one cache, for the whole multi-course run. The same
  # unrecognized code firing in course A and again in course B during that
  # one invocation is new information twice, once per course, not once total;
  # keying by code alone would have suppressed B's occurrence entirely,
  # silently, the moment A's had already warned. Verified directly here
  # rather than trusted from the fix's own description: a made-up code warns
  # on its first appearance for a given surface, does NOT warn again for that
  # SAME surface, and DOES warn again the first time it appears under a
  # DIFFERENT surface.
  made_up_axe_code <- "totally-unmapped-rule-for-testing-warn-once"
  count_course_a_first  <- 0L
  count_course_a_second <- 0L
  count_course_b_first  <- 0L
  invisible(withCallingHandlers(
    axe_criterion(made_up_axe_code, surface = "warn-once-course-a"),
    warning = function(w) { count_course_a_first <<- count_course_a_first + 1L; invokeRestart("muffleWarning") }))
  invisible(withCallingHandlers(
    axe_criterion(made_up_axe_code, surface = "warn-once-course-a"),
    warning = function(w) { count_course_a_second <<- count_course_a_second + 1L; invokeRestart("muffleWarning") }))
  invisible(withCallingHandlers(
    axe_criterion(made_up_axe_code, surface = "warn-once-course-b"),
    warning = function(w) { count_course_b_first <<- count_course_b_first + 1L; invokeRestart("muffleWarning") }))
  expect_identical(count_course_a_first, 1L,
    info = "an unrecognized code warns on its first appearance for course A")
  expect_identical(count_course_a_second, 0L,
    info = "the SAME code on the SAME surface (course A again) does not warn again")
  expect_identical(count_course_b_first, 1L,
    info = "the SAME code on a DIFFERENT surface (course B) warns again")

  # A confirmed best-practice code must never warn, on any surface, no
  # matter how many different courses audit it: it is a settled fact, not new
  # information, and the point of the per-surface key is precision (warn
  # exactly when something is genuinely new), not just "warn more often".
  best_practice_warn_count <- 0L
  invisible(withCallingHandlers({
    axe_criterion("landmark-unique", surface = "warn-once-course-a")
    axe_criterion("landmark-unique", surface = "warn-once-course-b")
  }, warning = function(w) { best_practice_warn_count <<- best_practice_warn_count + 1L; invokeRestart("muffleWarning") }))
  expect_identical(best_practice_warn_count, 0L,
    info = "a confirmed best-practice code never warns, on any surface")

  # from_pa11y() must route on `runner`, not assume every issue is
  # htmlcs-shaped. A real color-contrast issue as pa11y's own JSON reporter
  # actually emits it: no WCAG technique code, a `runner` field of "axe", and
  # a `runnerExtras` object pa11y_chr() never touches.
  raw_axe_contrast <- list(list(
    code = "color-contrast", type = "error", typeCode = 1L,
    message = "Elements must meet minimum color contrast ratio thresholds",
    context = "<a>...", selector = "#toc-chapter-goals", runner = "axe",
    runnerExtras = list(description = "...", impact = "serious")))
  df_axe <- from_pa11y(raw_axe_contrast, "textbook", "chapter-01.html")
  expect_identical(df_axe$criterion, "1.4.3",
    info = "a real-shaped axe issue gets criterion 1.4.3, not NA")
  expect_identical(df_axe$selector, "#toc-chapter-goals",
    info = "an axe issue's real selector is kept, exactly like an htmlcs one")

  # The same bare code ("color-contrast") would collide with a DIFFERENT
  # meaning if the wrong runner's parser were applied to it: htmlcs's own
  # pa11y_criterion() would find no digit-dot-digit segment in
  # "color-contrast" either, but only by accident (it happens to also return
  # NA), which would mask a routing bug rather than prove the routing works.
  # This asserts the routing itself, not just the coincidental shared NA
  # fallback.
  expect_identical(is.na(pa11y_criterion("color-contrast")), TRUE,
    info = "routing is by runner, not a coincidence: htmlcs-style parsing of the same axe code also gives NA (both must be checked, not just axe's path)")
})

test_that("diff_findings", {
  old <- rbind(
    finding("textbook", "a.qmd", "1.1.1", "A", "no alt", "#i1", "serious"),
    finding("textbook", "b.qmd", "1.4.3", "AA", "contrast", "#p1", "serious"))
  new <- rbind(
    finding("textbook", "b.qmd", "1.4.3", "AA", "contrast", "#p1", "serious"),
    finding("textbook", "c.qmd", "2.4.4", "A", "link text", "#a1", "moderate"))
  d <- diff_findings(old, new)
  expect_identical(nrow(d$fixed), 1L, info = "one fixed")
  expect_identical(d$fixed$file, "a.qmd", info = "fixed is a.qmd")
  expect_identical(nrow(d$new), 1L, info = "one new")
  expect_identical(d$new$file, "c.qmd", info = "new is c.qmd")
  expect_identical(nrow(d$unchanged), 1L, info = "one unchanged")
})

test_that("round trip", {
  new <- rbind(
    finding("textbook", "b.qmd", "1.4.3", "AA", "contrast", "#p1", "serious"),
    finding("textbook", "c.qmd", "2.4.4", "A", "link text", "#a1", "moderate"))
  p <- file.path(tempdir(), "findings.json")
  write_findings(new, list(date = "2026-08-12", tool = "pa11y@9.1.1"), p)
  rt <- read_findings(p)
  expect_identical(nrow(rt), nrow(new), info = "round trips row count")
  expect_identical(sort(rt$id), sort(new$id), info = "round trips ids")

  # write_findings() on a 0-row frame writes "findings": [], which fromJSON()
  # parses as list(), not NULL. The old guard, is.null(df) || !nrow(df),
  # called nrow() on that list(), got NULL back, and `if (!NULL)` is a
  # zero-length logical that errors rather than returning the empty frame. A
  # page, or a criterion, with zero remaining issues is a normal and
  # desirable state this project is actively trying to reach, not a crash.
  p0 <- file.path(tempdir(), "findings-empty.json")
  write_findings(new[0, ], list(date = "2026-08-12", tool = "pa11y@9.1.1"), p0)
  rt0 <- tryCatch(read_findings(p0), error = function(e) e)
  expect_identical(inherits(rt0, "error"), FALSE,
    info = "a 0-row frame round trips without erroring")
  if (!inherits(rt0, "error")) {
    expect_identical(nrow(rt0), 0L, info = "a 0-row round trip has 0 rows")
    expect_identical(identical(names(rt0), FINDING_COLS), TRUE,
      info = "a 0-row round trip still has every FINDING_COLS column")
  }

  # jsonlite cannot infer a type from an all-null JSON array, so a column
  # that is NA on every row (source_file, line, fix_class, fix_target,
  # leverage on every from_pa11y() row) comes back as R's `logical` instead
  # of its real type. The report stage writes into fix_class, fix_target and
  # leverage and reads this file back in, so a silent type flip there is a
  # real landmine, not a cosmetic one.
  all_na <- finding("textbook", "d.qmd", "1.1.1", "A", "all-NA row", "#x1",
                     "serious")
  p_na <- file.path(tempdir(), "findings-allna.json")
  write_findings(all_na, list(date = "2026-08-12", tool = "pa11y@9.1.1"), p_na)
  rt_na <- read_findings(p_na)
  expect_identical(is.integer(rt_na$line), TRUE,
    info = "line survives an all-NA round trip as integer")
  expect_identical(is.integer(rt_na$leverage), TRUE,
    info = "leverage survives an all-NA round trip as integer")
  expect_identical(is.integer(rt_na$count), TRUE,
    info = "count survives an all-NA round trip as integer")
  expect_identical(is.character(rt_na$source_file), TRUE,
    info = "source_file survives an all-NA round trip as character")
  expect_identical(is.character(rt_na$fix_class), TRUE,
    info = "fix_class survives an all-NA round trip as character")
  expect_identical(is.character(rt_na$fix_target), TRUE,
    info = "fix_target survives an all-NA round trip as character")
})

test_that("distinct rows in one file get distinct ids", {
  # HAND-OFF. The source section drove this through the three custom checks
  # (missing fig-alt, filename-as-alt, colour-only), building a fixture with
  # two real, distinct violations in ONE file and requiring both nrow() and
  # the number of DISTINCT ids to equal 2. Those checks arrive with the
  # checks library in a later task; the fixture-driven form belongs with them
  # in that file. What can be asserted here is the property they depend on,
  # in the layer that provides it: the id key's discriminators. 30 of 40 real
  # findings once vanished silently because every row a check produced for
  # one file shared a single id (no selector, no code), and a bare nrow()
  # check on the pre-dedup list would still have passed, because rbind() does
  # not care whether two rows share an id.
  two_selectors <- rbind(
    finding("textbook", "ch1.qmd", "1.1.1", NA_character_, "no alt",
            "#fig-first > img", "serious", source = "custom"),
    finding("textbook", "ch1.qmd", "1.1.1", NA_character_, "no alt",
            "#fig-second > img", "serious", source = "custom"))
  expect_identical(nrow(two_selectors), 2L,
    info = "two violations in one file both survive rbind")
  expect_identical(length(unique(two_selectors$id)), 2L,
    info = "a per-row selector gives two DISTINCT ids, not one shared id")

  # The filename-as-alt shape: two different images sharing the SAME bad alt
  # text. The alt value alone collides, so the selector is what has to
  # discriminate.
  same_alt <- rbind(
    finding("textbook", "alt2.html", "1.1.1", NA_character_,
            "alt text is a file name", "img[src='chart-a.png']", "serious",
            source = "custom"),
    finding("textbook", "alt2.html", "1.1.1", NA_character_,
            "alt text is a file name", "img[src='chart-b.png']", "serious",
            source = "custom"))
  expect_identical(nrow(same_alt), 2L,
    info = "two images sharing the same bad alt text both survive rbind")
  expect_identical(length(unique(same_alt$id)), 2L,
    info = "two DISTINCT ids even though the alt value alone collides")

  # The selector-less shape: a check that can report twice for one file with
  # no element to point at has to carry its own discriminator in `code`, or
  # the two rows share an id and one is discarded silently downstream.
  no_selector <- rbind(
    finding("textbook", "ch1.qmd", "1.1.1", NA_character_, "colour only",
            NA_character_, "serious", source = "custom", code = "colour-only-1"),
    finding("textbook", "ch1.qmd", "1.1.1", NA_character_, "colour only",
            NA_character_, "serious", source = "custom", code = "colour-only-2"))
  expect_identical(nrow(no_selector), 2L,
    info = "two selector-less violations in one file both survive rbind")
  expect_identical(length(unique(no_selector$id)), 2L,
    info = "a per-row code gives two DISTINCT ids with no selector to key on")
})

test_that("report_and_dedup", {
  # The id-based dedup used to be a bare `df[!duplicated(df$id), ]` with no
  # report of what it removed, which is how a 30-row loss went unnoticed
  # until four ground-truth facts were checked by hand against the shipped
  # report. report_and_dedup() must (a) leave a frame of genuinely distinct
  # findings completely intact, (b) collapse a real duplicate (same finding,
  # same content, seen twice) and say so via its returned attributes, and (c)
  # tell that apart from rows that share an id despite NOT agreeing on their
  # own content, a collision, which means a check is missing a discriminator
  # and is reported as such rather than quietly collapsed like an ordinary
  # duplicate.

  # (a) Genuinely distinct findings: two rows with two different ids.
  # report_and_dedup() must not touch either row.
  distinct_df <- rbind(
    finding("textbook", "ch1.qmd", "1.1.1", NA_character_, "no alt",
            "#fig-first > img", "serious", source = "custom"),
    finding("textbook", "ch1.qmd", "1.1.1", NA_character_, "no alt",
            "#fig-second > img", "serious", source = "custom"))
  dd_distinct <- report_and_dedup(distinct_df, quiet = TRUE)
  expect_identical(nrow(dd_distinct), 2L,
    info = "dedup: a frame of genuinely distinct findings survives with 0 removed")
  expect_identical(attr(dd_distinct, "n_removed"), 0L,
    info = "dedup: n_removed is 0 for a frame with no duplicate ids")
  expect_identical(length(attr(dd_distinct, "collided_ids")), 0L,
    info = "dedup: no collision reported for genuinely distinct findings")

  # (b) A real duplicate: the same finding, byte-for-byte, seen twice, the
  # actual shape of the two-cartridge case the driver hits in production,
  # where the same untitled iframe is genuinely present in both files.
  dup_a <- finding(surface = "cartridge", file = "welcome-to-class.html",
                    criterion = "4.1.2", level = NA_character_,
                    issue = "iframe has no title, so it is announced only as 'frame'",
                    selector = "iframe[src='welcome.html']", severity = "serious",
                    detail = "src=welcome.html", source = "custom")
  dup_b <- dup_a  # identical row: the same real finding, seen in a second file
  dup_df <- rbind(dup_a, dup_b)
  expect_identical(length(unique(dup_df$id)), 1L,
    info = "dedup fixture: the duplicate pair really does share one id")
  dd_dup <- report_and_dedup(dup_df, quiet = TRUE)
  expect_identical(nrow(dd_dup), 1L,
    info = "dedup: a real duplicate is collapsed to one row")
  expect_identical(attr(dd_dup, "n_removed"), 1L,
    info = "dedup: n_removed reports the 1 row it removed")
  expect_identical(length(attr(dd_dup, "collided_ids")), 0L,
    info = "dedup: a real duplicate is NOT reported as a collision")

  # (c) A collision: two rows engineered to share an id (same surface, file,
  # criterion, no selector, no code, exactly the pre-fix fig-alt shape) but
  # disagreeing on issue/detail, i.e. two genuinely different findings. This
  # must be reported loudly and distinctly from case (b), never just
  # collapsed.
  col_a <- finding(surface = "textbook", file = "ch1.qmd", criterion = "1.1.1",
                    level = NA_character_, issue = "issue A, chunk one",
                    selector = NA_character_, severity = "serious",
                    detail = "chunk one", source = "custom")
  col_b <- finding(surface = "textbook", file = "ch1.qmd", criterion = "1.1.1",
                    level = NA_character_, issue = "issue B, chunk two",
                    selector = NA_character_, severity = "serious",
                    detail = "chunk two", source = "custom")
  col_df <- rbind(col_a, col_b)
  expect_identical(length(unique(col_df$id)), 1L,
    info = "collision fixture: the two different findings really do share one id")
  dd_col <- report_and_dedup(col_df, quiet = TRUE)
  expect_identical(nrow(dd_col), 1L,
    info = "dedup: a collision still collapses to one row (the mechanism, not the diagnosis)")
  expect_identical(length(attr(dd_col, "collided_ids")), 1L,
    info = "dedup: a collision IS reported, distinct from an ordinary duplicate")
  expect_identical(attr(dd_col, "collided_ids")[1], col_a$id[1],
    info = "dedup: the reported collided id matches the actual shared id")

  # The console report itself (not quiet = TRUE): confirms the loud path
  # prints something a person would actually notice, not just that the
  # attribute is set.
  dedup_out <- paste(capture.output(report_and_dedup(col_df)), collapse = "\n")
  expect_identical(grepl("COLLISION", dedup_out, fixed = TRUE), TRUE,
    info = "dedup: the printed report names the collision explicitly")
})

test_that("negative control: a dedup collision halts, an ordinary duplicate does not", {
  # report_and_dedup() itself does not stop() on a collision, "the mechanism,
  # not the diagnosis": it still collapses the colliding rows to one and only
  # REPORTS the collision via attr(., "collided_ids"). The halt is
  # halt_on_collision().
  #
  # The first version of this section reimplemented the guard as a LOCAL
  # closure, a copy of the real if/stop that used to live inline in the
  # driver. Both passed every check because the real guard was genuinely
  # present and reachable, but a test exercising a COPY of the guard cannot
  # catch a regression that leaves the real one's text physically present
  # while making it UNREACHABLE, e.g. the driver wrapping its call in a
  # conditional that skips it on the default path. halt_on_collision() is the
  # ONE function both the driver and this test call; there is no longer a
  # second copy to drift out of sync with it. A genuine collision and a
  # genuine, non-colliding duplicate must produce OPPOSITE outcomes through
  # that one real function.
  #
  # HAND-OFF: the source section's third assertion is static coupling to the
  # driver, that it really calls halt_on_collision() on its findings frame
  # rather than retaining an inert reference to it. The driver moves into the
  # package in a later task, so that assertion belongs in the driver's own
  # test file, where the source it reads exists.
  col_df <- rbind(
    finding(surface = "textbook", file = "ch1.qmd", criterion = "1.1.1",
            level = NA_character_, issue = "issue A, chunk one",
            selector = NA_character_, severity = "serious",
            detail = "chunk one", source = "custom"),
    finding(surface = "textbook", file = "ch1.qmd", criterion = "1.1.1",
            level = NA_character_, issue = "issue B, chunk two",
            selector = NA_character_, severity = "serious",
            detail = "chunk two", source = "custom"))
  dup_row <- finding(surface = "cartridge", file = "welcome-to-class.html",
                      criterion = "4.1.2", level = NA_character_,
                      issue = "iframe has no title, so it is announced only as 'frame'",
                      selector = "iframe[src='welcome.html']", severity = "serious",
                      detail = "src=welcome.html", source = "custom")
  dup_df <- rbind(dup_row, dup_row)

  nc_halt_collision <- tryCatch({ halt_on_collision(col_df, quiet = TRUE); "did not halt" },
                                 error = function(e) "halted")
  expect_identical(nc_halt_collision, "halted",
    info = "negative control: a genuine collision halts the real halt_on_collision()")
  nc_halt_duplicate <- tryCatch({ halt_on_collision(dup_df, quiet = TRUE); "did not halt" },
                                 error = function(e) "halted")
  expect_identical(nc_halt_duplicate, "did not halt",
    info = "negative control: an ordinary duplicate never trips halt_on_collision()")
})

test_that("M12: the JSON keeps each page count attached to its surface name", {
  # A named integer VECTOR is written by write_json() as a bare positional
  # array ([2,12]), so the JSON loses the names and a reader has to align
  # counts against the declared surfaces by position. as.list() makes it a
  # JSON object instead. The source section reached write_findings() through
  # the driver's own metadata builder, which arrives in a later task; the
  # contract that section was protecting is this file's, so it is asserted
  # against write_findings() directly, in both directions.
  d <- withr::local_tempdir()
  empty <- finding("alpha", "x.html", "1.1.1", NA_character_, "x", NA, "serious")[0, ]
  measured <- c(alpha = 2L, `alpha-cartridge` = 12L)

  as_object <- file.path(d, "m12-object.json")
  write_findings(empty, list(date = "2026-08-13", tool = "pa11y@9.1.1",
                             pages_examined = as.list(measured),
                             surfaces = names(measured)), as_object)
  object_txt <- paste(readLines(as_object, warn = FALSE), collapse = "\n")
  expect_identical(grepl('"pages_examined"\\s*:\\s*\\{', object_txt), TRUE,
    info = "M12: pages_examined is a JSON object, not a positional array")
  expect_identical(grepl('"alpha-cartridge"', object_txt, fixed = TRUE), TRUE,
    info = "M12: and each surface name is present as a key")

  # The bug shape, asserted rather than described: the same counts passed as
  # the named vector they start life as write out as a positional array with
  # the surface names gone, which is why the caller converts. The declared
  # surfaces are deliberately left out of this second file, so that a surface
  # name found anywhere in it can only have come from the counts.
  as_vector <- file.path(d, "m12-vector.json")
  write_findings(empty, list(date = "2026-08-13", tool = "pa11y@9.1.1",
                             pages_examined = measured), as_vector)
  vector_txt <- paste(readLines(as_vector, warn = FALSE), collapse = "\n")
  expect_identical(grepl('"pages_examined"\\s*:\\s*\\[', vector_txt), TRUE,
    info = "M12: a bare named vector writes as a positional array")
  expect_identical(grepl('"alpha-cartridge"', vector_txt, fixed = TRUE), FALSE,
    info = "M12: and loses every surface name, which is the loss as.list() prevents")
})
