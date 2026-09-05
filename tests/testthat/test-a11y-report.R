# Ported from the snapshot's own self-checking audit test script: the
# classification and rendering sections. Each printed banner there is a
# test_that() block here and each check() is an expectation carrying the
# original label.
#
# The M11 "a finding with no WCAG criterion says so" section is here rather
# than with the finding model, where its source section sat: it renders a
# report, so it belongs with the renderer. test-a11y-model.R named it in place
# while the renderer was still outside the package.

# Counts non-overlapping literal occurrences of a substring. Used below to
# prove a report has exactly the Confidence lines it should have, not merely
# "at least one", which a half-working confidence_line_for() could pass by
# accident.
count_substr <- function(txt, pattern) {
  if (!grepl(pattern, txt, fixed = TRUE)) return(0L)
  length(gregexpr(pattern, txt, fixed = TRUE)[[1]])
}

# The character the rendered documents must never contain, built from its code
# point so this file can assert the ban without carrying the character itself.
EM_DASH <- intToUtf8(8212L)

test_that("classify_fixes", {
  df <- rbind(
    finding("textbook", "a.html", "1.4.3", "AA", "contrast", "#p", "serious"),
    finding("textbook", "b.html", "1.4.3", "AA", "contrast", "#p", "serious"),
    finding("textbook", "c.html", "1.4.3", "AA", "contrast", "#p", "serious"),
    finding("textbook", "a.qmd",  "1.1.1", "A",  "no fig-alt", NA, "serious"),
    finding("textbook", "d.qmd",  "1.4.1", "A",  "colour only", NA, "review"))
  tgt <- list(stylesheet = NA_character_, framework = "quarto", repo = "/x")
  cl <- classify_fixes(df, tgt)
  expect_identical(unique(cl$fix_class[cl$criterion == "1.4.3"]), "a",
    info = "contrast is class a")
  expect_identical(unique(cl$leverage[cl$criterion == "1.4.3"]), 3L,
    info = "leverage counted")
  expect_identical(cl$fix_class[cl$severity == "review"], "c",
    info = "review is class c")
  expect_identical(grepl("create", cl$fix_target[cl$criterion == "1.4.3"][1]), TRUE,
    info = "no stylesheet names creation")

  # A real stylesheet must be used by name, not silently replaced by the
  # "create one first" fallback text. Without this, classify_fixes() could be
  # stubbed to always return the fallback message and the check above would
  # still pass, since it only ever exercises the no-stylesheet case.
  tgt_styled <- list(stylesheet = file.path(tempdir(), "theme.scss"),
                     framework = "quarto", repo = "/x")
  df_style <- finding("textbook", "a.html", "1.4.3", "AA", "contrast", "#p", "serious")
  cl_style <- classify_fixes(df_style, tgt_styled)
  expect_identical(cl_style$fix_target[1], "theme.scss",
    info = "a real stylesheet target is named by basename")
  expect_identical(grepl("create", cl_style$fix_target[1]), FALSE,
    info = "a real stylesheet target does not fall back to the create-one message")
})

test_that("classify_fixes: 2.4.1 no longer promises a stylesheet fix it cannot deliver", {
  # Bypass Blocks is fixed by adding a skip link or a landmark region to the
  # shared page TEMPLATE, not the stylesheet. The report library has no
  # template-target mechanism, so routing 2.4.1 to class (a) named an edit that
  # could not actually close it. It now falls through to the same per-page
  # handling any criterion with no special grouping rule gets.
  df_bypass <- finding("textbook", "a.html", "2.4.1", "A",
                       "no way to skip repeated navigation", NA, "serious")
  tgt_bypass <- list(stylesheet = file.path(tempdir(), "theme.scss"),
                     framework = "quarto", repo = "/x")
  cl_bypass <- classify_fixes(df_bypass, tgt_bypass)
  expect_identical(cl_bypass$fix_class[1], "b", info = "2.4.1 is not class a")
  expect_identical(cl_bypass$fix_target[1], "a.html",
    info = "2.4.1 does not name the stylesheet as its fix target")
  expect_identical("2.4.1" %in% CLASS_A_CRITERIA, FALSE,
    info = "2.4.1 is dropped from CLASS_A_CRITERIA entirely")
})

test_that("notices: filtered ONCE upstream of classify_fixes, not inside it or a renderer", {
  # classify_fixes() used to give a minor-severity notice a real fix_class, and
  # its leverage could merge with real findings sharing its criterion;
  # render_report() built its summary table from the FULL frame and only
  # stripped notices afterward, so the table and the detail section below it
  # counted two different sets of rows. strip_notices()/notice_table() are now
  # the single upstream filtering point: classify_fixes(), the summary table,
  # the detail section, and the plan all consume the exact same, already
  # notice-free frame.
  full_notice_df <- rbind(
    finding("textbook", "a.html", "1.4.3", "AA", "contrast", "#p", "serious"),
    finding("textbook", "b.html", "1.4.3", "AA", "contrast", "#p", "serious"),
    finding("textbook", "c.html", "1.4.3", "AA", "contrast", "#p", "serious"),
    finding("textbook", "n1.html", "2.4.6", NA_character_,
            "heading text could be clearer", NA, "minor"),
    finding("textbook", "n2.html", "2.4.6", NA_character_,
            "heading text could be clearer", NA, "minor"),
    finding("textbook", "n3.html", "3.1.2", NA_character_,
            "language of parts notice", NA, "minor"))
  notices_n  <- notice_table(full_notice_df)
  findings_n <- strip_notices(full_notice_df)
  expect_identical(nrow(findings_n), 3L,
    info = "strip_notices removes exactly the 3 minor rows")
  expect_identical(nrow(notices_n), 2L,
    info = "notice_table keeps the 3 minor rows, grouped into 2 criteria")
  expect_identical(notices_n$n[notices_n$criterion == "2.4.6"], 2L,
    info = "notice_table counts 2.4.6 correctly")

  tgt_n <- list(stylesheet = NA_character_, framework = "quarto", repo = "/x")
  cl_n  <- classify_fixes(findings_n, tgt_n)
  expect_identical(any(cl_n$severity == "minor"), FALSE,
    info = "no minor-severity row ever reaches classify_fixes' output")
  expect_identical(unique(cl_n$leverage[cl_n$criterion == "1.4.3"]), 3L,
    info = "leverage for the real contrast findings is exactly 3, not inflated by notices")

  rp_n <- file.path(tempdir(), "report_notices.md")
  render_report(cl_n, list(date = "2026-08-13", tool = "pa11y@9.1.1",
                           notices = notices_n), rp_n)
  txt_n <- paste(readLines(rp_n, warn = FALSE), collapse = "\n")
  expect_identical(count_substr(txt_n, "\n### "), 3L,
    info = "exactly 3 detail headings, matching the 3 real findings")
  expect_identical(grepl("| textbook | a | 3 |", txt_n, fixed = TRUE), TRUE,
    info = "the fix-class summary table shows exactly 3, matching the 3 detail headings")
  expect_identical(grepl("## Notices, summarized", txt_n, fixed = TRUE), TRUE,
    info = "notices are summarized, not listed, in their own section")
  expect_identical(grepl("### 2.4.6", txt_n, fixed = TRUE), FALSE,
    info = "a notice criterion never gets its own finding heading")
  expect_identical(grepl("| 2.4.6 |", txt_n, fixed = TRUE), TRUE,
    info = "the notices section still names 2.4.6 in its summary table")
})

test_that("classify_fixes/render_plan: broken embeds count per item, not per criterion", {
  # Every broken-embed finding shares one criterion ("broken-embed") and one
  # fix_target (CART_GENERATOR, from the cartridge library), because that is
  # simply where every video URL happens to be authored. Grouping leverage by
  # (criterion, fix_target) alone would credit fixing ONE dead video with
  # closing every dead video.
  df_embeds <- rbind(
    finding("cartridge", "welcome.html", "broken-embed", NA_character_,
            "embedded video is unavailable", "iframe[src*='AAAAAAAAAAA']",
            "serious", detail = "youtube video id AAAAAAAAAAA"),
    finding("cartridge", "syllabus.html", "broken-embed", NA_character_,
            "embedded video is unavailable", "iframe[src*='BBBBBBBBBBB']",
            "serious", detail = "youtube video id BBBBBBBBBBB"))
  df_embeds$fix_target <- CART_GENERATOR
  tgt_embeds <- list(stylesheet = NA_character_)
  cl_embeds  <- classify_fixes(df_embeds, tgt_embeds)
  expect_identical(unique(cl_embeds$fix_class), "a",
    info = "both broken-embed findings are class a: a generator file is where the fix lands")
  expect_identical(cl_embeds$leverage, c(1L, 1L),
    info = "each broken-embed finding has leverage exactly 1, never 2")

  pp_embeds <- file.path(tempdir(), "plan_embeds.md")
  render_plan(cl_embeds, list(date = "2026-08-13"), pp_embeds)
  ptxt_embeds <- paste(readLines(pp_embeds, warn = FALSE), collapse = "\n")
  expect_identical(count_substr(ptxt_embeds, "broken-embed"), 2L,
    info = "the plan prints two separate broken-embed bullets, not one deduped bullet")
  expect_identical(grepl("Closes 2 findings", ptxt_embeds, fixed = TRUE), FALSE,
    info = "neither bullet claims to close more than the 1 finding it actually closes")
})

test_that("render_report: pages_examined, the unconditional zero-page safeguard", {
  # A 0-row findings frame cannot tell "audited many pages, found nothing"
  # apart from "audited nothing" on its own: both print "0 findings across 0
  # files and 0 surfaces" with nothing to distinguish them.
  # meta$pages_examined is counted independently of df and is checked
  # UNCONDITIONALLY here, not only when a caller also remembers to pass
  # meta$zero_page_targets.
  empty_df <- finding("textbook", "x", "1.1.1", NA_character_, "x", NA, "serious")[0, ]

  rp_absent <- file.path(tempdir(), "report_pe_absent.md")
  render_report(empty_df, list(date = "2026-08-13", tool = "pa11y@9.1.1"), rp_absent)
  txt_absent <- paste(readLines(rp_absent, warn = FALSE), collapse = "\n")
  expect_identical(grepl("PAGES EXAMINED: NOT REPORTED", txt_absent, fixed = TRUE), TRUE,
    info = "pages_examined absent entirely is reported loudly, not silently")

  rp_zero <- file.path(tempdir(), "report_pe_zero.md")
  render_report(empty_df, list(date = "2026-08-13", tool = "pa11y@9.1.1",
                               pages_examined = c(textbook = 0L),
                               surfaces = c("textbook")), rp_zero)
  txt_zero <- paste(readLines(rp_zero, warn = FALSE), collapse = "\n")
  expect_identical(grepl("Nothing was examined here", txt_zero, fixed = TRUE), TRUE,
    info = "pages_examined = 0 triggers the Nothing-was-examined banner")
  expect_identical(regexpr("Nothing was examined here", txt_zero) <
                     regexpr("## Summary", txt_zero), TRUE,
    info = "the zero-page section leads, ahead of the Summary")

  rp_clean <- file.path(tempdir(), "report_pe_clean.md")
  render_report(empty_df, list(date = "2026-08-13", tool = "pa11y@9.1.1",
                               pages_examined = c(textbook = 21L),
                               surfaces = c("textbook")), rp_clean)
  txt_clean <- paste(readLines(rp_clean, warn = FALSE), collapse = "\n")
  expect_identical(grepl("Nothing was examined here", txt_clean, fixed = TRUE), FALSE,
    info = "a real, nonzero pages_examined never shows the Nothing-was-examined banner")
  expect_identical(grepl("PAGES EXAMINED: NOT REPORTED", txt_clean, fixed = TRUE), FALSE,
    info = "a real, nonzero pages_examined never shows the NOT REPORTED banner")

  # Both derived from the SAME empty df, so the only difference between the
  # two summary lines below is the pages_examined count.
  summary_line_zero  <- grep("^0 findings across", strsplit(txt_zero,  "\n")[[1]], value = TRUE)[1]
  summary_line_clean <- grep("^0 findings across", strsplit(txt_clean, "\n")[[1]], value = TRUE)[1]
  expect_identical(identical(summary_line_zero, summary_line_clean), FALSE,
    info = "the zero-page and the clean summary lines are never identical")
  expect_identical(grepl("Pages examined: 0.", summary_line_zero, fixed = TRUE), TRUE,
    info = "the zero-page summary line states Pages examined: 0")
  expect_identical(grepl("Pages examined: 21.", summary_line_clean, fixed = TRUE), TRUE,
    info = "the clean summary line states the real page count")

  # zero_page_note() still works, now as SUPPLEMENTARY detail alongside the
  # unconditional pages_examined trigger, not as the trigger itself.
  tgt_empty <- list(repo = "/x/empty-course", framework = "static",
                    output_dir = NA_character_, source_dir = "/x/empty-course",
                    pages = character(0), stylesheet = NA_character_)
  note <- zero_page_note("textbook", tgt_empty)
  expect_identical(grepl("^textbook:", note), TRUE,
    info = "zero_page_note names the surface")
  expect_identical(grepl("[Nn]othing was examined", note), TRUE,
    info = "zero_page_note says nothing was examined")
  rp_zero_note <- file.path(tempdir(), "report_pe_zero_note.md")
  render_report(empty_df, list(date = "2026-08-13", tool = "pa11y@9.1.1",
                               pages_examined = c(textbook = 0L),
                               surfaces = c("textbook"),
                               zero_page_targets = note), rp_zero_note)
  txt_zero_note <- paste(readLines(rp_zero_note, warn = FALSE), collapse = "\n")
  expect_identical(grepl(note, txt_zero_note, fixed = TRUE), TRUE,
    info = "supplementary zero_page_targets detail reaches the report alongside pages_examined")
})

test_that("render_report: pages_examined validates its NAMES, not just its values", {
  # The earlier round only checked that pages_examined had no zero or NA
  # VALUES. A vector like c(textbook = 21L), where a second real surface was
  # simply never included, passed every check cleanly, fired neither banner,
  # and silently undercounted sum(pe): the exact silent-failure shape this
  # safeguard exists to eliminate, one level down. Every earlier fixture used a
  # single surface, so this went untested.
  #
  # meta$surfaces is supplied in every render_report() call below. It is
  # REQUIRED (the next block), so a fixture omitting it entirely no longer
  # demonstrates "caught from df alone": it demonstrates the NOT REPORTED
  # banner instead, which is what that block tests.
  df_two_surfaces <- rbind(
    finding("textbook", "a.html", "1.4.3", "AA", "contrast", "#p", "serious"),
    finding("cartridge", "syllabus.html", "4.1.2", NA_character_,
            "iframe has no title", "iframe", "serious"))
  df_two_surfaces$fix_target[df_two_surfaces$surface == "cartridge"] <- CART_GENERATOR
  cl_two <- classify_fixes(df_two_surfaces, list(stylesheet = NA_character_))

  # Case A: cartridge has real findings in df, but pages_examined never
  # mentions it, even though the declared surfaces list does name it.
  rp_missing_name <- file.path(tempdir(), "report_pe_missing_name.md")
  render_report(cl_two, list(date = "2026-08-13", tool = "pa11y@9.1.1",
                             pages_examined = c(textbook = 21L),
                             surfaces = c("textbook", "cartridge")), rp_missing_name)
  txt_missing_name <- paste(readLines(rp_missing_name, warn = FALSE), collapse = "\n")
  expect_identical(grepl("Nothing was examined here", txt_missing_name, fixed = TRUE), TRUE,
    info = "a surface present in df but absent from pages_examined is caught")
  expect_identical(grepl("cartridge: no pages_examined entry", txt_missing_name, fixed = TRUE),
                   TRUE,
    info = "the missing surface is named explicitly")
  expect_identical(grepl("INCOMPLETE", txt_missing_name, fixed = TRUE), TRUE,
    info = "the incomplete total is flagged inline, not silently reported as clean")

  # Case B: the fully silent case. A surface with ZERO findings never appears
  # in df at all, so df's own rows cannot reveal it is missing. meta$surfaces
  # is the authoritative list a driver supplies for exactly this case.
  rp_missing_silent <- file.path(tempdir(), "report_pe_missing_silent.md")
  render_report(cl_two[cl_two$surface == "textbook", , drop = FALSE],
                list(date = "2026-08-13", tool = "pa11y@9.1.1",
                     pages_examined = c(textbook = 21L),
                     surfaces = c("textbook", "cartridge")), rp_missing_silent)
  txt_missing_silent <- paste(readLines(rp_missing_silent, warn = FALSE), collapse = "\n")
  expect_identical(
    grepl("cartridge: no pages_examined entry", txt_missing_silent, fixed = TRUE), TRUE,
    info = "a surface with zero findings, absent from both df and pages_examined, is still caught via meta$surfaces")

  # Stub check: a complete pages_examined covering every known surface must
  # never trip the missing-surface warning.
  rp_complete <- file.path(tempdir(), "report_pe_complete.md")
  render_report(cl_two, list(date = "2026-08-13", tool = "pa11y@9.1.1",
                             pages_examined = c(textbook = 21L, cartridge = 6L),
                             surfaces = c("textbook", "cartridge")),
                rp_complete)
  txt_complete <- paste(readLines(rp_complete, warn = FALSE), collapse = "\n")
  expect_identical(grepl("Nothing was examined here", txt_complete, fixed = TRUE), FALSE,
    info = "a complete pages_examined covering every surface never shows the missing-surface warning")
  expect_identical(grepl("INCOMPLETE", txt_complete, fixed = TRUE), FALSE,
    info = "a complete pages_examined never shows INCOMPLETE")
})

test_that("render_report: meta$surfaces is REQUIRED, exactly as loud as an absent pages_examined", {
  # The chain: pages could be absent (fixed by counting them), the count could
  # be absent (fixed by a loud banner), the count could be present but missing
  # an entry (fixed by checking entries against a surface list), and now the
  # surface list itself could be absent, silently collapsing known_surfaces
  # back to unique(df$surface) and losing exactly the zero-finding-surface case
  # meta$surfaces exists to catch. Ruling: meta$surfaces is REQUIRED. Its
  # absence gates pe_ok to FALSE exactly like an absent pages_examined does,
  # and the reasons are named explicitly so a reader can tell the two apart.
  empty_df <- finding("textbook", "x", "1.1.1", NA_character_, "x", NA, "serious")[0, ]
  rp_no_surfaces <- file.path(tempdir(), "report_pe_no_surfaces.md")
  render_report(empty_df, list(date = "2026-08-13", tool = "pa11y@9.1.1",
                               pages_examined = c(textbook = 21L, cartridge = 6L)),
                rp_no_surfaces)
  txt_no_surfaces <- paste(readLines(rp_no_surfaces, warn = FALSE), collapse = "\n")
  expect_identical(grepl("PAGES EXAMINED: NOT REPORTED", txt_no_surfaces, fixed = TRUE), TRUE,
    info = "a fully valid, complete pages_examined with NO meta$surfaces still triggers NOT REPORTED")
  expect_identical(grepl("meta$surfaces", txt_no_surfaces, fixed = TRUE), TRUE,
    info = "the banner names meta$surfaces specifically as the missing piece")
  expect_identical(grepl("Pages examined: 27.", txt_no_surfaces, fixed = TRUE), FALSE,
    info = "a report with no meta$surfaces never claims complete coverage via Pages examined: N.")

  # Confirming case: the SAME pages_examined, with a complete surfaces
  # declaration added, trips nothing.
  rp_with_surfaces <- file.path(tempdir(), "report_pe_with_surfaces.md")
  render_report(empty_df, list(date = "2026-08-13", tool = "pa11y@9.1.1",
                               pages_examined = c(textbook = 21L, cartridge = 6L),
                               surfaces = c("textbook", "cartridge")),
                rp_with_surfaces)
  txt_with_surfaces <- paste(readLines(rp_with_surfaces, warn = FALSE), collapse = "\n")
  expect_identical(
    grepl("PAGES EXAMINED: NOT REPORTED", txt_with_surfaces, fixed = TRUE) ||
      grepl("Nothing was examined here", txt_with_surfaces, fixed = TRUE), FALSE,
    info = "a complete declaration alongside a complete count trips neither banner")
  expect_identical(grepl("Pages examined: 27.", txt_with_surfaces, fixed = TRUE), TRUE,
    info = "a complete declaration lets the real total through cleanly")
})

test_that("classify_fixes: routes 1.1.1 by criterion, not by engine-specific message wording", {
  # axe-core's image-alt message ("Images must have alternate text") does not
  # contain any of the literal substrings ("fig-alt", "alt text", "alt
  # attribute") the old routing matched on, while HTML_CodeSniffer's H37
  # wording does, so the IDENTICAL defect landed in class (c) from one engine's
  # finding and class (b) from the other's. Both describe WCAG criterion 1.1.1,
  # and the fix is the same kind of human-authored sentence either way, so
  # routing now keys on the criterion alone.
  df_engines <- rbind(
    finding("textbook", "a.html", "1.1.1", NA_character_,
            "Img element missing an alt attribute. Use the alt attribute to specify a short text alternative.",
            "img", "serious"),
    finding("textbook", "b.html", "1.1.1", NA_character_,
            "Images must have alternate text",
            "img", "serious"))
  # Sanity check on the fixture itself: axe's wording must NOT contain any of
  # the old regex's substrings, or this test would not actually reproduce the
  # reported defect.
  expect_identical(grepl("fig-alt|alt text|alt attribute", df_engines$issue[2]), FALSE,
    info = "the axe-style fixture wording does not contain the old regex's substrings")

  tgt_engines <- list(stylesheet = NA_character_, framework = "quarto", repo = "/x")
  cl_engines  <- classify_fixes(df_engines, tgt_engines)
  expect_identical(length(unique(cl_engines$fix_class)), 1L,
    info = "an htmlcs-worded and an axe-worded finding for the same 1.1.1 defect classify identically")
  expect_identical(unique(cl_engines$fix_class), "c",
    info = "both are routed to class c, the human-authored-sentence class alt text needs")
})

test_that("classify_fixes: 1.1.1 is protected from a preset fix_target, matching 2.4.4 (finding 9)", {
  # The 1.1.1 branch used to sit AFTER "already targeted", so a hypothetical
  # producer presetting fix_target on a 1.1.1 finding would have been pushed to
  # class (a) despite needing a human-authored sentence per instance. No real
  # producer does this today (verified across all five: from_pa11y(),
  # check_filename_alt(), check_missing_fig_alt(), check_untitled_iframes(),
  # check_weak_link_text()), so this fixture is deliberately synthetic: it
  # proves the ordering fix directly rather than reproducing an observed bug,
  # the same way the 2.4.1 test does.
  df_1111_preset <- finding("textbook", "a.html", "1.1.1", NA_character_,
                            "Images must have alternate text", "img", "serious")
  df_1111_preset$fix_target <- "some/other/generator.R"
  cl_1111_preset <- classify_fixes(df_1111_preset, list(stylesheet = NA_character_))
  expect_identical(cl_1111_preset$fix_class[1], "c",
    info = "a 1.1.1 finding with a preset fix_target still classifies as c, not a")
  expect_identical(cl_1111_preset$fix_target[1], "some/other/generator.R",
    info = "its preset fix_target is preserved, matching 2.4.4's treatment of a preset target")
})

test_that("level_for: WCAG A vs AA, transcribed from the fetched W3C page", {
  # WCAG_LEVEL was parsed from https://www.w3.org/TR/WCAG21/ own
  # <p class="conformance-level">(Level X)</p> markup, not from memory. 1.1.1
  # and 4.1.2 are the two criteria the finding model and the cartridge checks
  # already call out by name as genuinely Level A despite pa11y prefixing their
  # code with "WCAG2AA."; the wrong heuristic this project replaced would have
  # returned "AA" for both.
  expect_identical(level_for("1.1.1"), "A",
    info = "1.1.1 is Level A, not the AA a pa11y-code heuristic would claim")
  expect_identical(level_for("4.1.2"), "A",
    info = "4.1.2 is Level A, not the AA a pa11y-code heuristic would claim")
  expect_identical(level_for("1.4.3"), "AA", info = "1.4.3 is Level AA")
  expect_identical(level_for("9.9.9"), NA_character_,
    info = "an unlisted criterion returns NA rather than a guessed default")
  expect_identical(level_for(NA_character_), NA_character_,
    info = "level_for(NA) returns NA rather than erroring")
})

test_that("render_report: the verified level reaches the rendered text", {
  df2 <- rbind(
    finding("textbook", "a.html", "1.1.1", NA_character_, "missing alt", "img", "serious"),
    finding("textbook", "e.html", "9.9.9", NA_character_, "not a real WCAG criterion", NA, "moderate"))
  tgt2 <- list(stylesheet = NA_character_, framework = "quarto", repo = "/x")
  cl2  <- classify_fixes(df2, tgt2)
  rp2  <- file.path(tempdir(), "report2.md")
  render_report(cl2, list(date = "2026-08-12", tool = "pa11y@9.1.1",
                          standard = "WCAG 2.1 AA"), rp2)
  txt2 <- paste(readLines(rp2, warn = FALSE), collapse = "\n")
  expect_identical(grepl("**WCAG:** 1.1.1 Level A", txt2, fixed = TRUE), TRUE,
    info = "a real Level A criterion prints its verified level")
  expect_identical(grepl("1.1.1 Level AA", txt2, fixed = TRUE), FALSE,
    info = "that same criterion never prints Level AA")
  expect_identical(grepl("**WCAG:** 9.9.9", txt2, fixed = TRUE), TRUE,
    info = "an unlisted criterion prints the number alone")
  expect_identical(grepl("9.9.9 Level", txt2, fixed = TRUE), FALSE,
    info = "an unlisted criterion never gets a Level word glued to it")
})

test_that("render_report: mode disclosure, guessed vs verified fig-alt findings", {
  # check_missing_fig_alt() writes "[mode: rendered]" when it confirmed a real
  # rendered PNG, and "[mode: source-heuristic]" when it only guessed from a
  # plotting call or a fig- label because nothing was rendered. A report that
  # shows both the same way presents a guess as a verified result.
  df3 <- rbind(
    finding("textbook", "a.qmd", "1.1.1", NA_character_,
            "figure-producing chunk has no fig-alt, so the rendered img gets no alt",
            NA, "serious",
            detail = "chunk fig1 at line 10 [mode: source-heuristic]"),
    finding("textbook", "b.qmd", "1.1.1", NA_character_,
            "figure-producing chunk has no fig-alt, so the rendered img gets no alt",
            NA, "serious",
            detail = "chunk fig2 at line 20 [mode: rendered]"),
    finding("textbook", "c.html", "1.4.3", NA_character_, "contrast", "#p", "serious",
            detail = "measured 2.1:1"))
  tgt3 <- list(stylesheet = NA_character_, framework = "quarto", repo = "/x")
  cl3  <- classify_fixes(df3, tgt3)
  rp3  <- file.path(tempdir(), "report3.md")
  render_report(cl3, list(date = "2026-08-12", tool = "pa11y@9.1.1"), rp3)
  txt3 <- paste(readLines(rp3, warn = FALSE), collapse = "\n")
  expect_identical(grepl("not verified", txt3, fixed = TRUE), TRUE,
    info = "a source-heuristic finding is disclosed as not verified")
  expect_identical(grepl("verified against a rendered image", txt3, fixed = TRUE), TRUE,
    info = "a rendered-mode finding is disclosed as verified")
  expect_identical(count_substr(txt3, "Confidence:"), 2L,
    info = "exactly two Confidence lines: one per mode-carrying finding, not the third")
})

test_that("render", {
  # The same fixture the classify_fixes section builds, rendered end to end.
  df <- rbind(
    finding("textbook", "a.html", "1.4.3", "AA", "contrast", "#p", "serious"),
    finding("textbook", "b.html", "1.4.3", "AA", "contrast", "#p", "serious"),
    finding("textbook", "c.html", "1.4.3", "AA", "contrast", "#p", "serious"),
    finding("textbook", "a.qmd",  "1.1.1", "A",  "no fig-alt", NA, "serious"),
    finding("textbook", "d.qmd",  "1.4.1", "A",  "colour only", NA, "review"))
  cl <- classify_fixes(df, list(stylesheet = NA_character_, framework = "quarto",
                                repo = "/x"))
  rp <- file.path(tempdir(), "report.md")
  render_report(cl, list(date = "2026-08-12", tool = "pa11y@9.1.1",
                         standard = "WCAG 2.1 AA"), rp)
  txt <- paste(readLines(rp, warn = FALSE), collapse = "\n")
  expect_identical(file.exists(rp), TRUE, info = "report exists")
  expect_identical(grepl(EM_DASH, txt, fixed = TRUE), FALSE,
    info = "report has no em-dash")
  expect_identical(grepl("pa11y@9.1.1", txt), TRUE, info = "report names the tool")

  pp <- file.path(tempdir(), "plan.md")
  render_plan(cl, list(date = "2026-08-12"), pp)
  ptxt <- paste(readLines(pp, warn = FALSE), collapse = "\n")
  # NOTE: these match what render_plan actually emits. It writes
  # "## Class (a): ..." and "## Re-audit", both capitalised. Matching them
  # case-sensitively in lower case would fail against correct code.
  expect_identical(regexpr("Class \\(a\\)", ptxt) < regexpr("Class \\(c\\)", ptxt), TRUE,
    info = "plan leads with class a")
  # The plan carries NO date and never asserts one. The old check demanded the
  # plan flag an unverified deadline, which framed an absent date as a gap. It
  # asserts the opposite: no date language at all.
  expect_identical(grepl("compliance deadline", ptxt, ignore.case = TRUE), FALSE,
    info = "plan asserts no compliance date")
  expect_identical(grepl("re-audit", ptxt, ignore.case = TRUE), TRUE,
    info = "plan ends with a re-audit step")
  expect_identical(grepl(EM_DASH, ptxt, fixed = TRUE), FALSE,
    info = "plan has no em-dash")
  # "Closes N findings" undercounts real impact whenever a finding is itself an
  # aggregate (count > 1), since such a row still contributes only 1 to
  # leverage. A wording fix, not a logic fix: an understatement, not a
  # double-count.
  expect_identical(grepl("more than one occurrence", ptxt, fixed = TRUE), TRUE,
    info = "the plan discloses that a finding can represent more than one occurrence")
})

test_that("negative control: cross-engine classification discriminates by criterion, not wording", {
  # A fresh fixture, distinct wording from the one used earlier in this file,
  # proving the same discipline again rather than resting on one instance:
  # an htmlcs-worded and an axe-worded finding for the identical 1.1.1 defect
  # must classify identically, AND a genuinely different criterion in the same
  # batch must NOT be folded into that same class just because it rode along.
  # A classifier that flags everything the same way passes the first half of
  # this test and fails the second.
  nc_df_cross <- rbind(
    finding("textbook", "p1.html", "1.1.1", NA_character_,
            "Img element missing an alt attribute. Use the alt attribute to specify a short text alternative.",
            "img#hero", "serious"),
    finding("textbook", "p2.html", "1.1.1", NA_character_,
            "Images must have alternate text",
            "img.banner", "serious"),
    finding("textbook", "p3.html", "1.4.3", "AA",
            "Element has insufficient color contrast", "p.faint", "serious"))
  nc_cl_cross <- classify_fixes(
    nc_df_cross, list(stylesheet = "style.css", framework = "quarto", repo = "/x"))
  expect_identical(
    length(unique(nc_cl_cross$fix_class[nc_cl_cross$criterion == "1.1.1"])), 1L,
    info = "negative control: htmlcs-worded and axe-worded 1.1.1 findings classify identically")
  expect_identical(
    nc_cl_cross$fix_class[nc_cl_cross$criterion == "1.4.3"] !=
      nc_cl_cross$fix_class[nc_cl_cross$criterion == "1.1.1"][1], TRUE,
    info = "negative control: a genuinely different criterion in the same batch is not folded into 1.1.1's class")
})

test_that("a review-severity finding keeps the target its producer set", {
  # The review branch overwrote fix_target unconditionally, so an undetermined
  # caption row lost the cartridge generator target and gained a generic
  # placeholder. The class already says a human decides; the target says where.
  ft_no_target <- classify_fixes(
    finding("s", "a.qmd", "1.4.1", NA_character_, "colour only", NA_character_, "review"),
    list(stylesheet = NA_character_, framework = NA_character_, repo = NA_character_))
  expect_identical(ft_no_target$fix_target, "human judgement, do not automate",
    info = "review: a producer that set no target still gets the human-judgement placeholder")

  # A real undetermined caption row, produced by the check that makes them
  # rather than typed out here, so the preset target under test is the one the
  # producer actually sets.
  und_state <- list(list(file = "und_page.html", vid = "GONEVIDEO01",
                         state = "undetermined"))
  und <- do.call(rbind,
                 check_video_captions(character(), "und-cartridge", states = und_state))
  ft_preset <- classify_fixes(und, list(stylesheet = NA_character_,
                                        framework = NA_character_,
                                        repo = NA_character_))
  expect_identical(ft_preset$fix_target, CART_GENERATOR,
    info = "review: a preset target survives classification")
  expect_identical(ft_preset$fix_class, "c",
    info = "review: and the class is still (c)")
})

test_that("I6: class (a) leverage never merges two courses into one bullet", {
  # leverage_key() omitted the surface, so render_plan(), which runs across
  # every surface at once, collapsed two courses' class (a) rows onto one
  # bullet carrying one course's leverage, with the other course's rows absent
  # from the plan entirely. Two stylesheet-less courses is the real case:
  # sheet_label is then the identical literal string for both.
  expect_identical(
    identical(leverage_key("1.4.3", "sheet.css", "id1", "course-a"),
              leverage_key("1.4.3", "sheet.css", "id1", "course-b")),
    FALSE,
    info = "I6: the leverage key is surface-aware")
  i6_no_sheet <- list(stylesheet = NA_character_, framework = "quarto",
                      repo = NA_character_)
  i6_mk <- function(surface, n) do.call(rbind, lapply(seq_len(n), function(i)
    finding(surface, sprintf("page%d.html", i), "1.4.3", NA_character_,
            "insufficient contrast", sprintf("#el%d", i), "serious")))
  i6_a <- classify_fixes(i6_mk("course-a", 3L), i6_no_sheet)
  i6_b <- classify_fixes(i6_mk("course-b", 2L), i6_no_sheet)
  expect_identical(unique(c(i6_a$fix_class, i6_b$fix_class)), "a",
    info = "I6: both courses classify as class (a) against a stylesheet neither has yet")
  expect_identical(identical(unique(i6_a$fix_target), unique(i6_b$fix_target)), TRUE,
    info = "I6: and both carry the identical fix_target text, which is what made them merge")
  i6_plan <- file.path(tempdir(), "i6_plan.md")
  render_plan(rbind(i6_a, i6_b), list(date = "2026-08-13"), i6_plan)
  i6_txt <- readLines(i6_plan, warn = FALSE)
  i6_bullets <- grep("^- \\[ \\] \\*\\*1\\.4\\.3\\*\\*", i6_txt, value = TRUE)
  expect_identical(length(i6_bullets), 2L,
    info = "I6: two courses produce two bullets, not one")
  expect_identical(c(any(grepl("(course-a)", i6_bullets, fixed = TRUE)),
                     any(grepl("(course-b)", i6_bullets, fixed = TRUE))),
                   c(TRUE, TRUE),
    info = "I6: and each bullet names its own course")
  expect_identical(sort(c(i6_a$leverage[1], i6_b$leverage[1])), c(2L, 3L),
    info = "I6: each carries its own leverage, not the other's")
})

test_that("I7: the notice total reconciles with the JSON it claims to reconcile with", {
  # notice_table() used table(), which drops NA, so notices whose criterion is
  # NA (an axe rule with no WCAG success-criterion tag) vanished from the table
  # AND from the total, in a sentence that explicitly asserts the JSON count.
  # Measured: the report said 3722, the JSON held 3725.
  i7_df <- rbind(
    finding("s", "a.html", "1.4.6", NA_character_, "notice one", "#a", "minor"),
    finding("s", "b.html", "1.4.6", NA_character_, "notice two", "#b", "minor"),
    finding("s", "c.html", NA_character_, NA_character_, "untagged rule", "#c", "minor"),
    finding("s", "d.html", NA_character_, NA_character_, "untagged rule two", "#d", "minor"),
    finding("s", "e.html", "1.1.1", NA_character_, "a real finding", "#e", "serious"))
  i7_nt <- notice_table(i7_df)
  expect_identical(sum(i7_nt$n), sum(i7_df$severity == "minor"),
    info = "I7: the notice total equals the number of notice rows, with none dropped")
  expect_identical(i7_nt$n[i7_nt$criterion == "(no criterion)"], 2L,
    info = "I7: the criterion-less notices get their own labelled row")
  expect_identical(any(is.na(i7_nt$criterion)), FALSE,
    info = "I7: and no row is named NA")
})

test_that("M11: a finding with no WCAG criterion says so, rather than printing NA", {
  # 22 findings rendered their heading as "### NA" and their criterion line as
  # "- **WCAG:** NA", which reads as a rendering bug rather than as the real,
  # deliberate state it is: the rule that fired carries no WCAG success
  # criterion at all.
  m11_df <- classify_fixes(
    finding("s", "x.html", NA_character_, NA_character_,
            "heading levels should only increase by one", "#h", "moderate"),
    list(stylesheet = NA_character_, framework = NA_character_, repo = NA_character_))
  m11_path <- file.path(tempdir(), "m11_report.md")
  render_report(m11_df, list(date = "2026-08-13", tool = "pa11y@9.1.1",
                             pages_examined = c(s = 1L), surfaces = "s",
                             failed_pages = character()), m11_path)
  m11_txt <- paste(readLines(m11_path, warn = FALSE), collapse = "\n")
  expect_identical(grepl("### NA", m11_txt, fixed = TRUE), FALSE,
    info = "M11: no heading reads '### NA'")
  expect_identical(grepl("WCAG:** NA", m11_txt, fixed = TRUE), FALSE,
    info = "M11: no criterion line reads 'WCAG:** NA'")
  expect_identical(grepl("no WCAG criterion", m11_txt, fixed = TRUE), TRUE,
    info = "M11: the real state is stated instead")
})
