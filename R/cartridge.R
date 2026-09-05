#' Build a Canvas-importable Common Cartridge from course.yml and modules.yml
#'
#' Build a Canvas-importable Common Cartridge 1.1.0 from course.yml + modules.yml.
#'
#'   build_cartridge(proj)
#'   -> build/coursepack/<slug>-<date>.imscc
#'
#' Shaped against a real Canvas export of the first course built with it.
#' Divergence from that export is a generator bug unless it is one of the
#' deliberate ones a course declares in its reference.yml.
#'
#' A third input, announcements.yml, is OPTIONAL. Absent, nothing below changes.
#' Present, it adds scheduled announcements, shaped against a second real
#' export (the first course's round trip), because its original reference
#' export carried none. See the announcements section.
#'
#' @section The identifier model:
#' Read this before changing anything.
#'
#' Canvas identifiers are "g" + 32 hex. Three kinds, and they are NOT interchangeable:
#'
#'   item id      one per module item. Appears as `identifier` in BOTH
#'                course_settings/module_meta.xml AND the manifest <organizations>.
#'   resource id  one per resource. Names the file or directory on disk.
#'   idref        how an item points at its resource. THIS IS WHERE IT GETS WEIRD.
#'
#' Verified against the reference export, all 72 items:
#'
#'   ContextModuleSubHeader   no idref anywhere (24/24)
#'   WikiPage                 module_meta idref == manifest idref == resource id (6/6)
#'   Assignment               module_meta idref == manifest idref == resource id (10/10)
#'   ExternalUrl              module_meta idref == THE ITEM'S OWN ID (32/32),
#'                            manifest idref == the weblink resource id (32/32),
#'                            and those two are DIFFERENT values (0/32 equal).
#'
#' So an ExternalUrl carries two distinct ids and module_meta self-references.
#' Emitting the resource id in module_meta, or the item id in the manifest, is
#' exactly the kind of malformed cartridge Canvas accepts and then silently drops.
#'
#' IDs are deterministic md5 of a stable key, so rebuilds are byte-reproducible
#' and a diff between two builds shows real change rather than fresh randomness.
#'
#' @section What this does not do, on purpose:
#'   * No files embedded in the cartridge, and no $IMS-CC-FILEBASE$ tokens. All
#'     asset references are absolute URLs. See the package README.
#'   * Nothing from assessments/ is read, ever. Quizzes ship as separate QTI zips.
#'   * No New Quizzes content.
#'   * No context.xml. The reference's copy carries the SOURCE course's Canvas ids
#'     and account uuid; those describe a course we are not importing from.
#'   * No web_resources/ EXCEPT the course card image. Revised 2026-09-02. The
#'     blanket exclusion was written when the only candidate was the reference's
#'     1.95 MB course image, which was 93% of that cartridge. Our card is 18 KB,
#'     built at Canvas's documented 262x146, so the size argument does not reach
#'     it. The package README rule against embedding files is about $IMS-CC-FILEBASE$
#'     tokens; the course image uses <image_identifier_ref> instead and needs no
#'     token, which is why this one file is admissible and page assets are not.
#'     udoit.json stays excluded: it is an accessibility-scanner artifact.
#'   * No LTI resources. imsbasiclti links do not round-trip through import.
#'
#' A zip that builds proves nothing. Canvas discards malformed cartridges without
#' reporting an error. This script says so at the end; do not delete that.
#'
#' @section Staging part of a course:
#' `modules =` names the modules to stage, by the `title:` they carry in
#' modules.yml. Only those modules are written, and with them only the pages,
#' assignments and quizzes their items point at; a title the manifest does not
#' declare stops the build rather than being skipped. Announcements are a
#' property of the course rather than of a module and are staged either way.
#'
#' The whole course, `modules = NULL`, is the form the byte gate stands behind
#' and the only one to import when the course is being replaced. A staged
#' cartridge is a partial course: importing it into a shell that already holds
#' the rest is the case it is for.
#'
#' @param proj Course project root.
#' @param modules Module titles to stage, or `NULL` for every module.
#' @return invisible(list(imscc, stage)).
#' @export
build_cartridge <- function(proj = ".", modules = NULL) {
  proj <- normalizePath(proj, mustWork = TRUE)
  out_root <- file.path(proj, "build", "coursepack"); stage <- file.path(out_root, "staging")
  # Purge staging every run. Nothing recreates it wholesale -- writef() makes
  # directories on demand -- so files written by a previous build survive, and the
  # pre-zip check then reports them as on-disk-but-undeclared. Found when quiz01
  # was removed: its three files were still staged and failed the next build.
  # Without the purge a removed item could also ship inside the zip unnoticed.
  unlink(stage, recursive = TRUE)
  m <- read_manifest(proj); course <- m$course; mods <- m$mods
  # The walk runs FIRST, before anything is read off disk for it, because it is
  # what `modules =` selects on: an unknown module title stops here rather than
  # after a stale-height report and a source cartridge have been read for
  # modules that were never going to be staged.
  r <- resolve_items(m, modules)                         # items, modmeta, ids, used
  # `sel` is the manifest narrowed to the definitions the staged items point
  # at. Every writer below reads it instead of `m`, and for a whole course the
  # two are the same manifest. See selected_defs() in R/cartridge-items.R.
  sel <- selected_defs(m, r$used)
  # Warning-level, and printed on every build: a hand-measured iframe height is
  # an observation with an expiry date, and one that has expired shows students
  # a scrollbar or dead space. The build proceeds; see R/stale.R. Only the pages
  # being staged are reported: a height that is not shipping is not this
  # build's problem to report on.
  check_stale_heights(proj, course, sel$pages)
  ann <- read_announcements(proj, course)
  # The zone is read only when something needs it: a due: on any definition,
  # or announcements. An extracted course (Phase 4) has neither and must build
  # without a term: block.
  tz <- if (needs_timezone(sel, ann)) read_timezone(course) else NULL
  tb_docs <- textbook_docs_path(course, proj)
  # reference.yml's source: names a cartridge a course can carry resources out
  # of. Nothing carries one yet, so a declared source with no definition naming
  # a source_ref is REPORTED rather than passed over: a source that is declared
  # and does nothing looks exactly like a source that was read and found empty.
  ref <- read_reference(proj)
  if (!is.null(ref$source) && !any_source_ref(sel))
    cat("  source declared, 0 resources carried\n")

  tile <- stage_course_card(proj, stage)
  write_course_settings(stage, course, tile)
  groups <- assignment_group_ids(course)
  write_assignment_groups(stage, course, groups)
  write_course_settings_files(stage, course)
  write_module_meta(stage, r$modmeta)
  write_weblinks(stage, r$items)
  write_wiki_pages(stage, proj, sel$pages, r$ids$page_res, course$urls)
  write_assignments(stage, sel$assignments, r$ids, course, tb_docs, groups, proj, tz)
  # Three ways a quiz reaches the cartridge, and a definition declares exactly
  # one of them (check_definition_shape()): `source_ref:` carries it out of the
  # source cartridge, `bank:` generates it from a JSON question bank, `qti:`
  # embeds an R/exams zip. A generated one hands back the <resource> blocks it
  # needs, figures included, because only it knows how many there are.
  generated <- list()
  for (k in names(sel$quizzes)) {
    q <- sel$quizzes[[k]]
    if (!is.null(q$source_ref)) next                   # carried, not generated
    ag_id <- group_id_for(q$group %||% course$assignment_defaults$group,
                          groups, paste0("quiz '", k, "'"))
    if (!is.null(q$bank)) generated[[k]] <- write_generated_quiz(k, q, r, course, proj, stage, groups)
    else embed_quiz(k, q, r$ids, ag_id, stage, proj)
  }
  # Carrying runs after every generated writer and before the manifest, which
  # needs the carried <resource> blocks. It writes nothing at all unless every
  # path the source declares is safe; see R/cartridge-carry.R.
  carried <- no_carry()
  if (any_source_ref(sel)) {
    cdefs <- carried_defs(sel)
    src <- read_source_cartridge(source_path(ref, proj, cdefs[[1]]$name))
    carried <- carry_resources(cdefs, src, stage)
    cat(sprintf("  carried %d resources, %d files out of %s\n",
                length(carried$carried), length(carried$files), basename(src$zip)))
    # Two fields inside the carried bytes belong to THIS course rather than to
    # the one they came out of. Titles first, then dates, so a definition whose
    # due: has nothing to write stops before any date is computed and the
    # titles it did sync are visible in the tree that gets inspected.
    n_titles <- sync_carried_titles(carried, cdefs, stage)
    dates <- apply_carried_dates(carried, cdefs, stage, course, tz)
    cat(sprintf("  carried titles synced=%d  dates written=%d  blanked=%d\n",
                n_titles, dates$dated, dates$blanked))
    # Last of the three rewrites, and the only optional one: two accessibility
    # defects in Canvas-authored HTML, repaired on the way in. Carried files
    # only; a generated page is fixed at its source, never here.
    if (repair_html_on(course)) {
      rep <- repair_carried_html(carried, stage)
      cat(sprintf("  carried html repaired: %d th scoped, %d headings\n",
                  rep$th, rep$headings))
    } else {
      cat("  carried html repair off (carry: repair_html: false)\n")
    }
  }
  ann_ids <- if (is.null(ann)) list(ann_res = character(), ann_meta = character(), ann_past = character())
             else stage_announcements(ann, stage)
  settings_res <- write_manifest(stage, course, r$modmeta, r$items, r$ids, tile,
                                 ann_ids, sel, carried, generated)

  cat("=== pre-zip validation ===\n")
  problems <- character(); p_fail <- function(...) problems <<- c(problems, paste0(...))
  prezip_checks(stage, settings_res, ann_ids$ann_res, p_fail, carried$carried)
  check_announcements(stage, ann, ann_ids$ann_res, p_fail)
  check_carried(stage, carried, groups, p_fail)
  if (length(problems)) {
    cat("\nBUILD FAILED:\n"); for (p in problems) cat("  ! ", p, "\n", sep = "")
    # The problems are repeated in the condition message, not only on the
    # console: a caller that catches the error, a test included, otherwise sees
    # a count and has to go looking for the output that says what broke.
    stop("BUILD FAILED: ", length(problems), " problem(s):\n  ",
         paste(problems, collapse = "\n  "), call. = FALSE)
  }
  outfile <- file.path(out_root, sprintf("%s-%s.imscc", course_slug(course), format(Sys.Date())))
  zip_cartridge(stage, outfile)                          # mtime pin, zip -q -X
  cat("\n=== built ===\n")
  cat(sprintf("  %s  (%s KB, %d entries)\n", outfile, format(round(file.size(outfile) / 1024, 1), nsmall = 1),
              length(list.files(stage, recursive = TRUE))))
  version_line("build_cartridge")
  cat("\nA zip that builds proves NOTHING. Canvas discards malformed cartridges\n")
  cat("without reporting an error. Import into a throwaway shell and look.\n")
  invisible(list(imscc = outfile, stage = stage))
}

# One quiz generated from a question bank. Everything it writes is in
# R/generate-quiz.R; what this adds is the one fact that comes from the walk
# rather than from the definition, the title of the module the quiz is first
# used in, which the default description names. A quiz no module item
# references falls back to its own title and is caught a few lines later by the
# orphan check, which is where an unused resource belongs.
write_generated_quiz <- function(k, q, r, course, proj, stage, groups) {
  mt <- unname(r$quiz_module[k])
  if (is.na(mt)) mt <- as.character(q$title)
  q$id <- q$id %||% k
  generate_quiz_files(q, mt, course, proj, stage, r$ids, groups)
}

# Does any page, assignment or quiz definition ask for something out of the
# source cartridge?
any_source_ref <- function(m) {
  defs <- c(m$pages, m$assignments, m$quizzes)
  any(vapply(defs, function(d) !is.null(d$source_ref), TRUE))
}

needs_timezone <- function(m, ann) {
  !is.null(ann) || any(vapply(c(m$assignments, m$quizzes), function(d) !is.null(d$due), TRUE))
}

# ---- zip -----------------------------------------------------------------
zip_cartridge <- function(stage, outfile) {
if (!nzchar(Sys.which("zip"))) stop("zip binary not found on the PATH; install zip", call. = FALSE)
if (file.exists(outfile)) unlink(outfile)

# Byte-reproducibility. zip stores each entry's mtime, so two builds of identical
# content still differ byte-for-byte unless the timestamps are pinned. Pin every
# staged file and directory to midnight of the build date. Cross-day builds still
# differ, which is correct: the manifest embeds the build date too.
stamp <- as.POSIXct(paste(format(Sys.Date()), "00:00:00"), tz = "UTC")
for (p in list.files(stage, recursive = TRUE, include.dirs = TRUE, full.names = TRUE))
  Sys.setFileTime(p, stamp)
Sys.setFileTime(stage, stamp)

old <- setwd(stage)
zres <- utils::zip(outfile, list.files(".", recursive = TRUE, all.files = FALSE), flags = "-q -X")
setwd(old)
if (zres != 0) stop("zip failed with status ", zres, call. = FALSE)

invisible(outfile)
}
