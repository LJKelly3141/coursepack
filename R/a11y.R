# Entry point for the course accessibility audit.
#
# Serves each repo's rendered output, runs pa11y over every page, layers the
# custom source checks, audits any cartridge found, classifies, and writes
# three files into the audit's output directory.
#
# No repo path is defaulted. This runs against any course.

#' Audit a course's rendered output against WCAG 2.1 AA
#'
#' Serves each repository's rendered output over a local HTTP server, runs
#' pa11y across every page, layers the custom source checks on top, audits any
#' Common Cartridge found under the repository, classifies each finding by the
#' kind of fix it needs, and writes a JSON record, a findings document and a
#' remediation plan.
#'
#' The measured page count and the declared scope are accumulated on two
#' separate code paths on purpose, so the report's coverage comparison is a
#' real cross-check rather than a value compared against itself. The comments
#' in this file say why.
#'
#' @param repos Character vector of repository paths to audit. Required; no
#'   repository is assumed and an empty vector stops.
#' @param proj The course project root. Used only to place `out_dir`.
#' @param out_dir Where the three files are written.
#' @param port The port the local server binds while pa11y reads a page.
#' @param cartridge_dirs Directories under each repository to search for
#'   cartridges, passed to [cartridges_in()].
#' @param video_fetch The watch-page fetcher passed to [audit_cartridge()].
#'   Defaults to the real network fetcher.
#' @return Invisibly, a list with `findings` (the full frame, classified rows
#'   plus the notice rows), `meta` (the run's metadata) and `files` (the three
#'   paths written).
#' @export
audit_course <- function(repos, proj = ".",
                         out_dir = file.path(proj, "project", "accessibility"),
                         port = 8766L,
                         cartridge_dirs = c("build/coursepack", "reference"),
                         video_fetch = default_youtube_fetch) {
  if (!length(repos)) {
    stop("usage: audit_course(<repo> [, <repo> ...])\n",
         "  no repo is assumed; this audit is not tied to one course")
  }

  today   <- format(Sys.Date(), "%Y-%m-%d")
  all     <- list()
  targets <- list()

  # Two repos whose paths end in the same directory name resolve to the same
  # surface (a surface name IS a path basename), which would silently merge two
  # courses into one: the second overwrites targets[[surface]], so one course's
  # findings would classify against the other's stylesheet, and one page count
  # would vanish. Halt instead. Checked here, before any work, and again inside
  # intended_surfaces() so the guarantee does not depend on this driver
  # remembering to ask (R/a11y-targets.R, finding I8).
  halt_on_surface_collision(repos)

  # zero_page_targets carries zero_page_note() TEXT, not bare surface names.
  # It is folded into the report as supplementary detail once
  # meta$pages_examined has already said a surface examined 0 pages.
  zero_page_targets <- character()

  # THE EMPIRICAL PAGE COUNTER. Restored 2026-08-13, final whole-branch review,
  # finding C1 (critical).
  #
  # This is incremented per page ACTUALLY audited and per wiki page ACTUALLY
  # read, inside the loops below that do the work. It is deliberately NOT
  # intended_surfaces(), which is the DECLARATION and is read exactly once, far
  # below, for meta$surfaces and meta$declared. For one round this file built
  # both from the same intended_surfaces() call, and the effect was that the
  # renderer's coverage cross-check compared a value against itself: commenting
  # out the entire cartridge loop still printed the full page count, still
  # declared the cartridge surface, fired no banner, and read as a clean audit.
  # Two signals from one function call cannot check each other. Keep these two
  # on separate code paths.
  pages_examined <- integer(0)

  # Every surface gets an entry the moment its target is discovered, so a
  # surface that examined nothing reports an honest, explicit 0 rather than
  # disappearing from the count entirely (ruling R27). A surface that is never
  # reached at all still has NO entry, which is what the renderer's
  # missing-surface banner is for.
  media_inventory <- list()

  # Per cartridge surface, how many .imscc files its page count is spread
  # across. See the cartridge loop below.
  cartridge_files <- integer(0)

  # Pages pa11y itself could not audit (pa11y_raw() threw). A failed page is
  # NOT counted as examined: this counter answers "how many pages does this
  # report actually cover", and a page the tool could not read is a page it
  # covers nothing of. Folded into meta and rendered beside the page count, not
  # merely cat() to a console that scrolls away: a run where pa11y failed on 20
  # of 21 pages must not print a full page count anywhere.
  failed_pages <- character()

  for (repo in repos) {
    tgt <- discover_target(repo)
    surface <- page_surface_name(tgt)  # R/a11y-targets.R: the one shared rule,
                                       # also what intended_surfaces() (below)
                                       # calls to build the real declaration,
                                       # so a test calling intended_surfaces()
                                       # directly exercises this exact rule
    targets[[surface]] <- tgt   # keyed by surface, because classification is
                                # per surface: see the classify block below
    cat("== ", surface, ": ", tgt$framework, ", ", length(tgt$pages),
        " pages\n", sep = "")

    # An honest, explicit 0 for a surface that was reached but examined
    # nothing, distinct from a surface with no entry at all (never reached).
    pages_examined <- bump_examined(pages_examined, surface, 0L)

    # Non-HTML media: listed, never judged. inventory_media()
    # (R/a11y-cartridge.R) was written, tested, and called by nothing until
    # 2026-08-13 (finding I4), while the audit's own documentation claimed
    # media was inventoried "so nothing goes missing by silent omission".
    #
    # inventory_media() returns NULL for a repo with no images and no PDFs, and
    # `lst[[name]] <- NULL` DELETES the element in R rather than storing an
    # empty one, caught on the first real run after wiring this up, where a
    # whole repo vanished from the inventory entirely instead of reporting an
    # honest zero. That is the same silent omission this whole finding is
    # about, so the empty case is materialized as a real 0-row frame.
    inv <- inventory_media(tgt$repo)
    if (is.null(inv)) {
      inv <- data.frame(kind = character(), ref = character(),
                        note = character(), stringsAsFactors = FALSE)
    }
    media_inventory[[surface]] <- inv

    # A zero-page target is recorded as a FINDING, not just a console line.
    # Console output scrolls away; the report persists and is what someone
    # relies on. An audit that examined nothing and an audit that found nothing
    # must never read the same. See ruling R27.
    if (is.na(tgt$output_dir) || !length(tgt$pages)) {
      cat("   no rendered output found; render it before auditing\n")
      zero_page_targets <- c(zero_page_targets, zero_page_note(surface, tgt))
      all[[length(all) + 1]] <- finding(
        surface = surface, file = "(whole target)", criterion = NA_character_,
        level = NA_character_, selector = NA_character_, severity = "serious",
        issue = "no rendered HTML was found for this target, so NOTHING here was audited",
        detail = sprintf("output_dir=%s. Render the site, then re-run. A clean result for this target would be meaningless.",
                         tgt$output_dir %||% "(none resolved)"),
        source = "custom")
      next
    }

    srv <- serve_dir(tgt$output_dir, port = port)
    # finally, not the file-level on.exit() the draft used: on.exit() has no
    # effect at top level (there is no enclosing function frame for it to
    # attach to in a plain Rscript), so it was silently doing nothing. A
    # tryCatch(..., finally=) around the actual work is the version of "clean
    # up even on an early error" that is real at top level. serve_dir()'s own
    # port_is_free() check turns any leak this still misses into a loud
    # failure on the next run rather than a silent one, so this is belt, not
    # suspenders alone.
    tryCatch({
      for (p in tgt$pages) {
        cat("   pa11y ", p, "\n", sep = "")
        raw <- try(pa11y_raw(paste0(srv$url, "/", p)), silent = TRUE)
        if (inherits(raw, "try-error")) {
          cat("   FAILED on ", p, ": ", conditionMessage(attr(raw, "condition")),
              "\n", sep = "")
          failed_pages <- c(failed_pages, paste0(surface, "/", p))
          next
        }
        # Counted HERE, after pa11y actually returned parsed output for this
        # page, and never anywhere else. This one line is the empirical half of
        # the coverage cross-check (finding C1): if this loop does not run, or
        # runs and fails, the count does not move, and the report says so.
        pages_examined <- bump_examined(pages_examined, surface, 1L)
        all[[length(all) + 1]] <- from_pa11y(raw, surface, p)
        all[[length(all) + 1]] <- check_filename_alt(
          file.path(tgt$output_dir, p), surface, p)
      }
    }, finally = srv$stop())

    # `exclude` is required by both checks and comes from THIS repo's own
    # config, via discover_target(): the directories the project declares as
    # pass-through resources, which it copies rather than renders. A `.qmd`
    # under one of those was never a page this build produced, so a fig-alt
    # finding against it names a figure the course does not publish. The
    # checks cannot work this out themselves (reading config is
    # R/a11y-targets.R's job and R/a11y-checks.R must not depend on it), so the
    # driver supplies it, exactly as it supplies `surface`.
    #
    # Two separate reasons a source is out of scope, unioned here because the
    # checks take one list. resource_dirs: copied verbatim, never rendered.
    # unproduced_sources: renders to no page at all, so it was never produced
    # to students, which is the rule set 2026-08-13. A file can be out
    # of scope for either reason independently, so neither filter subsumes the
    # other and both are required.
    src_exclude <- unique(c(tgt$resource_dirs, tgt$unproduced_sources))
    all[[length(all) + 1]] <- check_missing_fig_alt(tgt$repo, surface,
                                                    exclude = src_exclude)
    all[[length(all) + 1]] <- check_colour_only(tgt$repo, surface,
                                                exclude = src_exclude)
  }

  # Any cartridge in a repo's build or reference directories.
  #
  # cart_surface is derived from the repo a cartridge was found under, not a
  # constant. Coordinator review, Finding 4: auditing more than one course in
  # one invocation is an explicitly supported use case (this loop is already
  # over every repo in `repos`), and a bare "cartridge" surface let two
  # different courses' cartridge findings collapse into each other the moment
  # they shared a (file, criterion, selector), two conventionally-named
  # "syllabus.html" wiki pages with the same iframe src, for instance. One
  # course's finding would then silently vanish into the other's via
  # report_and_dedup()'s "expected duplicate" path, a false negative and the
  # silent opposite of the collision-halt built earlier the same day.
  # cartridge_surface_name() (R/a11y-targets.R) suffixes "-cartridge" onto that
  # repo's own page surface base name so a cartridge finding and a
  # rendered-page finding for the same course still land in two different
  # report buckets, exactly as they always have for a single course.
  #
  # cartridges_in() (R/a11y-cartridge.R) is the same glob intended_surfaces()
  # uses below to declare this surface's honest wiki-page count, so this loop
  # can never silently audit a different set of files than the declaration
  # says it did.
  for (repo in repos) {
    cart_surface <- cartridge_surface_name(repo)
    for (z in cartridges_in(repo, cartridge_dirs)) {
      cat("== cartridge: ", basename(z), " (", cart_surface, ")\n", sep = "")
      res <- audit_cartridge(z, surface = cart_surface, video_fetch = video_fetch)
      # The cartridge half of the empirical counter (finding C1). The number
      # comes back from audit_cartridge() as an attribute recording how many
      # wiki pages that call ACTUALLY read, not from re-globbing the zip here
      # and not from the declaration: make audit_cartridge() return zero rows
      # and this still counts what it read, but delete this loop and the
      # cartridge surface has no count at all, which is exactly the state the
      # renderer's missing-surface banner exists to shout about.
      pages_examined <- bump_examined(pages_examined, cart_surface,
                                      attr(res, "wiki_pages_read") %||% 0L)
      all[[length(all) + 1]] <- res
      # How many .imscc files a cartridge surface's page count is spread
      # across. The count itself cannot say this, and it changes what the
      # number MEANS: two cartridges under one repo (an export and its own
      # round-trip copy, which is exactly what a reference/ directory holds)
      # read the same wiki page twice. The report states it next to the number
      # rather than leaving a reader to find it in another document.
      cartridge_files <- bump_examined(cartridge_files, cart_surface, 1L)
    }
  }

  # THE DECLARATION, and nothing else. Read exactly once, here, well after
  # pages_examined has been accumulated empirically above.
  #
  # intended_surfaces() (R/a11y-targets.R) is the one function BOTH this driver
  # and the audit's own test suite call to build a declaration, so a test
  # against it exercises the exact code path a real run takes rather than a
  # hand-copied restatement of the same formula (coordinator review, Task 8
  # finding 4, round 2). It declares a page surface even when the target has
  # zero pages, and a cartridge surface only when at least one `.imscc` was
  # actually found, valued at its total wiki-page count, never a raw `.imscc`
  # FILE count, which would mix units with every page-surface entry next to it
  # (coordinator review, finding 5).
  #
  # Fixed 2026-08-13, final whole-branch review, finding C1 (critical): this
  # call briefly fed pages_examined as well. That made the declaration and the
  # measurement the same number, and the renderer's coverage cross-check
  # compared it against itself. It is meta$surfaces and meta$declared only.
  declared <- intended_surfaces(repos)

  full_df <- do.call(rbind, Filter(function(x) !is.null(x) && nrow(x), all))
  if (is.null(full_df)) full_df <- finding("x","x","x","x","x","x","x")[0, ]

  # report_and_dedup() (R/a11y-model.R) replaces a bare
  # `full_df[!duplicated(full_df$id), ]`. That silent version is exactly how
  # 30 real check_missing_fig_alt() findings vanished during this feature's own
  # acceptance run: the dedup was doing real, consequential work and reporting
  # none of it. It now prints every collapsed id, how many rows each absorbed,
  # and separates the expected case (the same real finding seen in more than
  # one place, e.g. both `.imscc` files under `reference/` genuinely sharing an
  # untitled iframe) from a COLLISION, rows sharing an id despite disagreeing
  # on their own content, which means a check somewhere is missing a real
  # discriminator and real findings are about to be silently dropped again.
  #
  # halt_on_collision() (R/a11y-model.R) does the dedup AND stops the run on a
  # collision. Task 8 code review, finding 1: this used to be report_and_dedup()
  # plus an inline if/stop written here, with a copy of the same if/stop
  # reimplemented inside the audit's test script so it could be
  # tested at all. Extracted so this line and the test call the identical
  # function, closing the gap where a regression could leave the guard's text
  # present but unreachable and still pass a test that only exercised a copy
  # of it.
  full_df <- halt_on_collision(full_df)

  # Notices are pulled out ONCE, upstream of classification, on the FULL frame,
  # and never reach classify_fixes() or the plan. They are summarized by
  # count instead. One real full run produces 3,725 of them (the
  # measured number; three comments in this codebase cited "roughly 16,000" as
  # fact when it was an unchecked estimate, corrected 2026-08-13, finding M16);
  # letting even one reach classify_fixes() risks it picking up a real
  # fix_class (including class (a)) and inflating a leverage count. See
  # R/a11y-report.R's notices section and the coordinator review it documents.
  notices <- notice_table(full_df)
  work_df <- strip_notices(full_df)

  # Classify PER SURFACE, not once for the whole set. The stylesheet question is
  # a property of a repo: a textbook may have none while a course shell has
  # style.css, so classifying the shell's findings against the textbook's target
  # would tell someone to create a stylesheet that already exists. See ruling R3
  # in the SDD ledger.
  # The cartridge has no repo of its own; its findings arrive with fix_target
  # already set by audit_cartridge, so an empty target is correct for it.
  NO_TARGET <- list(stylesheet = NA_character_, framework = NA_character_,
                    repo = NA_character_)
  work_df <- do.call(rbind, lapply(split(work_df, work_df$surface), function(part) {
    classify_fixes(part, targets[[part$surface[1]]] %||% NO_TARGET)
  }))
  if (is.null(work_df)) work_df <- finding("x","x","x","x","x","x","x")[0, ]
  rownames(work_df) <- NULL

  # The JSON is the full, unfiltered record: classified findings plus the
  # notice rows exactly as strip_notices() pulled them out, untouched by
  # classify_fixes() (fix_class stays NA on every one). The two human documents
  # below are built from work_df alone, never from this recombined frame, so
  # notices can never leak into the report or the plan even indirectly.
  notice_rows <- full_df[full_df$severity == "minor", , drop = FALSE]
  df <- rbind(work_df, notice_rows)
  rownames(df) <- NULL

  # pages_examined is counted independently of findings and is NOT optional.
  # Without it, "0 findings across 0 files" reads identically whether the audit
  # examined 21 pages and found nothing or examined nothing at all. The report
  # states it unconditionally. See ruling R33.
  #
  # THE THREE COVERAGE FIELDS COME FROM THREE DIFFERENT PLACES ON PURPOSE, and
  # that is the whole point of finding C1:
  #
  #   pages_examined  MEASURED, accumulated inside the audit loops above
  #   surfaces/declared  DECLARED, from intended_surfaces() and target discovery
  #   failed_pages    MEASURED, the pages the tool could not read at all
  #
  # meta$surfaces is REQUIRED by render_report() (the coordinator's finding 8):
  # a page count cannot be judged complete without a declared scope to be
  # complete against. It is names(declared), NOT names(pages_examined). Built
  # from the measurement, it would agree with the measurement by construction
  # and could never catch a surface the run failed to reach.
  #
  # as.list() on the two named counts (finding M12): write_json() turns a named
  # integer VECTOR into a bare positional array ([2,21,12]), so the JSON lost
  # the surface names entirely and a reader had to align the counts against
  # meta$surfaces by position. A named list becomes a JSON object and keeps
  # each count attached to its own surface. render_report() unlist()s both, so
  # one meta serves the JSON and the two documents.
  meta <- list(date = today, standard = "WCAG 2.1 AA",
               tool = paste0("pa11y@", PA11Y_VERSION),
               repos = repos,
               pages_examined    = as.list(pages_examined),
               declared          = as.list(declared),
               surfaces          = unique(names(declared)),
               failed_pages      = failed_pages,
               cartridge_files   = as.list(cartridge_files),
               zero_page_targets = zero_page_targets,
               media_inventory   = media_inventory,
               notices           = notices)

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  jsonp <- file.path(out_dir, paste0(today, "-findings.json"))

  prior <- sort(list.files(out_dir, pattern = "-findings\\.json$",
                           full.names = TRUE), decreasing = TRUE)
  prior <- setdiff(prior, jsonp)
  if (length(prior)) {
    d <- diff_findings(read_findings(prior[1]), df)
    cat("\nvs ", basename(prior[1]), ": ", nrow(d$fixed), " fixed, ",
        nrow(d$new), " new, ", nrow(d$unchanged), " unchanged\n", sep = "")
  }

  mdp   <- file.path(out_dir, paste0(today, "-findings.md"))
  planp <- file.path(out_dir, paste0(today, "-plan.md"))
  write_findings(df, meta, jsonp)
  render_report(work_df, meta, mdp)
  render_plan(work_df, meta, planp)

  cat("\n", nrow(work_df), " findings (", nrow(notice_rows),
      " notices summarized separately, not counted here)\n", sep = "")
  print(table(work_df$fix_class))

  # The two coverage numbers, side by side, on the console as well as in the
  # report: measured against declared. They come from different code paths on
  # purpose (finding C1), so printing only one of them hides exactly the case
  # this counter exists to catch.
  cat("\npages examined (measured) vs declared:\n")
  for (s in unique(c(names(pages_examined), names(declared)))) {
    got  <- if (s %in% names(pages_examined)) pages_examined[[s]] else 0L
    want <- if (s %in% names(declared)) declared[[s]] else NA_integer_
    cat("  ", s, ": ", got, " examined / ",
        if (is.na(want)) "not declared" else want, " declared",
        if (!is.na(want) && got < want) "   *** SHORTFALL ***" else "", "\n",
        sep = "")
  }
  if (length(failed_pages)) {
    cat("\npa11y FAILED on ", length(failed_pages), " page(s), NOT counted as ",
        "examined: ", paste(failed_pages, collapse = ", "), "\n", sep = "")
  } else {
    cat("\npa11y failed on 0 pages\n")
  }
  cat("\nwrote:\n  ", jsonp, "\n  ", mdp, "\n  ", planp, "\n", sep = "")
  version_line("audit_course")

  invisible(list(findings = df, meta = meta, files = c(jsonp, mdp, planp)))
}
