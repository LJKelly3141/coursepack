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
#' @param proj Course project root.
#' @return invisible(list(imscc, stage)).
#' @export
build_cartridge <- function(proj = ".") {
  proj <- normalizePath(proj, mustWork = TRUE)
  out_root <- file.path(proj, "build", "coursepack"); stage <- file.path(out_root, "staging")
  # Purge staging every run. Nothing recreates it wholesale -- writef() makes
  # directories on demand -- so files written by a previous build survive, and the
  # pre-zip check then reports them as on-disk-but-undeclared. Found when quiz01
  # was removed: its three files were still staged and failed the next build.
  # Without the purge a removed item could also ship inside the zip unnoticed.
  unlink(stage, recursive = TRUE)
  m <- read_manifest(proj); course <- m$course; mods <- m$mods
  ann <- read_announcements(proj)
  # The zone is read only when something needs it: a due: on any definition,
  # or announcements. An extracted course (Phase 4) has neither and must build
  # without a term: block.
  tz <- if (needs_timezone(m, ann)) read_timezone(course) else NULL
  tb_docs <- textbook_docs_path(course, proj)
  # reference.yml's source: names a cartridge a course can carry resources out
  # of. Nothing carries one yet, so a declared source with no definition naming
  # a source_ref is REPORTED rather than passed over: a source that is declared
  # and does nothing looks exactly like a source that was read and found empty.
  ref <- read_reference(proj)
  if (!is.null(ref$source) && !any_source_ref(m))
    cat("  source declared, 0 resources carried\n")

  r <- resolve_items(m)                                  # items, modmeta, ids
  tile <- stage_course_card(proj, stage)
  write_course_settings(stage, course, tile)
  groups <- assignment_group_ids(course)
  write_assignment_groups(stage, course, groups)
  write_course_settings_files(stage, course)
  write_module_meta(stage, r$modmeta)
  write_weblinks(stage, r$items)
  write_wiki_pages(stage, proj, m$pages, r$ids$page_res, course$urls)
  write_assignments(stage, m$assignments, r$ids, course, tb_docs, groups, proj, tz)
  for (k in names(m$quizzes)) {
    q <- m$quizzes[[k]]
    ag_id <- group_id_for(q$group %||% course$assignment_defaults$group,
                          groups, paste0("quiz '", k, "'"))
    embed_quiz(k, q, r$ids, ag_id, stage, proj)
  }
  ann_ids <- if (is.null(ann)) list(ann_res = character(), ann_meta = character(), ann_past = character())
             else stage_announcements(ann, stage)
  settings_res <- write_manifest(stage, course, r$modmeta, r$items, r$ids, tile, ann_ids, m)

  cat("=== pre-zip validation ===\n")
  problems <- character(); p_fail <- function(...) problems <<- c(problems, paste0(...))
  prezip_checks(stage, settings_res, ann_ids$ann_res, p_fail)
  check_announcements(stage, ann, ann_ids$ann_res, p_fail)
  if (length(problems)) {
    cat("\nBUILD FAILED:\n"); for (p in problems) cat("  ! ", p, "\n", sep = "")
    stop("BUILD FAILED: ", length(problems), " problem(s); see above", call. = FALSE)
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

# Does any page, assignment or quiz definition ask for something out of the
# source cartridge? False for every course today; the key is read here so the
# reporting line above is written once and stays correct when carrying lands.
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
