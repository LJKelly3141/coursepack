# ---- reading a Canvas export back into the package schema -----------------
#
# The export is the specification. Hand-writing a manifest of a few hundred
# items and hoping it matches what Canvas does is how the first course was
# nearly built; reading the structure back out of a real export and writing it
# as declarative YAML is how it was actually built.
#
# Three things this reader does that the Python it ports did not:
#
#   1. A page is treated as a GENERATED wrapper only when its body is exactly
#      the builder's iframe template and nothing else (review 9). The Python
#      searched for an <iframe> anywhere in the page and rebuilt the page from
#      that one frame, so a page holding a frame plus a paragraph of the
#      instructor's own writing came back as a bare frame and the paragraph was
#      gone. Everything that is not a pure wrapper carries its bytes forward
#      with `source_ref:` instead, because the export is the only copy of it.
#   2. The site URL is cut at the last "/" (review 10). The Python shortened the
#      common prefix one CHARACTER at a time, so two pages under /ch01/ and
#      /ch02/ yielded ".../pages/ch0", a URL that is not a directory and that
#      nothing serves.
#   3. The `canvas:` keys are CANVAS_SETTINGS_KEYS, the same list the builder
#      emits from (review 12). A setting this writes is a setting the builder
#      writes back out, and a key on neither list is not silently invented here.
#
# What the export does not carry is not written: no `due:`, no `due_time:`, no
# term calendar, and no `height_measured:`. An extracted height is exactly the
# undated, possibly ancient measurement the stale check exists to flag, so the
# first build after an extraction reports every one of them as unchecked.

# One element of a list by name, or NULL when there is none. `[[` on a name a
# list does not carry is an error, not NULL, and every lookup below is asking
# whether something has been seen yet.
pick <- function(l, k) if (k %in% names(l)) l[[k]] else NULL

# One child element's text, trimmed, or `default` when the element is absent.
child_text <- function(node, name, default = "") {
  v <- xml2::xml_find_first(node, paste0("./", name))
  if (inherits(v, "xml_missing")) return(default)
  t <- xml2::xml_text(v)
  if (is.na(t)) default else trimws(t)
}

# An attribute, or NULL when it is absent, so an absent identifier leaves the
# key out of the YAML and the builder derives its own rather than reading "".
node_attr <- function(node, name) {
  v <- xml2::xml_attr(node, name)
  if (is.na(v) || !nzchar(v)) NULL else v
}

# Parse one file out of the export, namespaces stripped so the XPath below is
# readable. Absent is a stop naming the file: an export missing either of these
# is not an export this can read, and guessing at the structure it describes
# would produce a manifest that looks complete and is not.
export_xml <- function(src, name) {
  if (!name %in% src$names)
    stop("the export has no ", name, ", so there is nothing to extract from it: ",
         src$zip, call. = FALSE)
  doc <- xml2::read_xml(charToRaw(enc2utf8(read_zip_text(src$zip, name))))
  xml2::xml_ns_strip(doc)
  doc
}

# One attribute of the first <iframe> in a page body.
frame_attr <- function(body, name) {
  m <- regexpr(paste0("<iframe[^>]*\\s", name, '="[^"]*"'), body, perl = TRUE, ignore.case = TRUE)
  if (m < 0) return(NULL)
  hit <- substr(body, m, m + attr(m, "match.length") - 1L)
  xunesc(sub('^.*"([^"]*)"$', "\\1", hit))
}

# What one exported wiki page is: its slug, its title, and, when its body is the
# builder's wrapper and nothing else, the frame that wrapper holds.
#
# The comparison is against `iframe_wrapper()`, the builder's own template,
# rebuilt from this page's own attributes and compared with whitespace
# normalized. Rebuilding rather than pattern matching is what makes the test
# exact: a page carrying one extra sentence, or an attribute in another order,
# fails to match and is carried instead of being regenerated from a guess.
page_from_html <- function(html, slug) {
  title <- ""
  m <- regexpr("<title>[^<]*</title>", html)
  if (m > 0) title <- xunesc(trimws(substr(html, m + 7L, m + attr(m, "match.length") - 9L)))
  body <- ""
  b <- regexpr("(?is)<body[^>]*>.*</body>", html, perl = TRUE)
  if (b > 0) {
    body <- substr(html, b, b + attr(b, "match.length") - 1L)
    body <- sub("(?is)^<body[^>]*>", "", body, perl = TRUE)
    body <- sub("(?is)</body>$", "", body, perl = TRUE)
  }
  p <- list(slug = slug, title = title, wrapper = FALSE)
  src <- frame_attr(body, "src")
  if (is.null(src)) return(p)
  ftitle <- frame_attr(body, "title") %||% ""
  width  <- frame_attr(body, "width") %||% ""
  height <- frame_attr(body, "height") %||% ""
  video  <- grepl("<iframe[^>]*\\sallow=", body, perl = TRUE, ignore.case = TRUE)
  want <- iframe_wrapper(ftitle, src, width, height, if (video) IFRAME_ALLOW else "")
  if (!identical(oneline(body), oneline(want))) return(p)
  p$wrapper <- TRUE; p$iframe <- src; p$frame_title <- ftitle
  p$width <- width; p$height <- height; p$video <- video
  p
}

# The site URL: the longest common prefix of every iframe target, cut back to
# the last "/" so what comes out is a directory (review 10). "" when no page is
# a wrapper, because a course whose pages point nowhere has no site.
site_prefix <- function(srcs) {
  srcs <- unique(srcs[nzchar(srcs)])
  if (!length(srcs)) return("")
  p <- srcs[[1]]
  for (s in srcs) {
    n <- 0L; stop_at <- min(nchar(p), nchar(s))
    while (n < stop_at && identical(substr(p, n + 1L, n + 1L), substr(s, n + 1L, n + 1L)))
      n <- n + 1L
    p <- substr(p, 1L, n)
  }
  at <- regexpr("/[^/]*$", p)
  if (at < 0) return("")
  sub("/+$", "", substr(p, 1L, at - 1L))
}

# YAML the package's own readers read back. Booleans are written true and false
# rather than the yes and no this library writes by default, because every
# manifest a course hand-edits beside these is written the first way.
extract_yaml <- function(x) {
  yaml::as.yaml(x, handlers = list(logical = yaml::verbatim_logical),
                indent.mapping.sequence = TRUE)
}

write_extracted <- function(path, header, x) {
  body <- sub("\n$", "", extract_yaml(x))
  writef(path, if (length(header)) paste0(paste(header, collapse = "\n"), "\n", body) else body)
}

#' Extract a course manifest from a Canvas export
#'
#' Read a Canvas Common Cartridge export and write `course.yml`, `modules.yml`
#' and `reference.yml` under `out_dir` in this package's schema, together with a
#' copy of the export under `<out_dir>/reference/`. The result is a course
#' `build_cartridge()` can rebuild from, whose structure is the exported
#' course's own rather than a template's.
#'
#' @section What comes back:
#' The course title and code; the `canvas:` settings on `CANVAS_SETTINGS_KEYS`,
#' which is the same list the builder emits from; the assignment groups with
#' their identifiers, positions and weights, the identifiers because a carried
#' quiz or assignment references its group by identifier and a fresh one would
#' dangle every reference; the module tree with every module and item
#' identifier, title, indent and published state; and, for a page whose body is
#' the builder's iframe wrapper and nothing else, that frame's target, width,
#' height and title.
#'
#' @section What does not:
#' Everything else about a page, an assignment or a quiz becomes a `source_ref:`
#' definition, which carries the exported bytes forward unchanged, because the
#' export is the only copy of them there is. Announcements, grading standards,
#' the late policy and LTI links are counted in the closing summary and are not
#' written. Neither is the link from a resource back to the plain text it was
#' generated from: a course that authored its own pages and then extracts its
#' own export gets a manifest that is structurally exact and source blind, and
#' nothing here can tell that case from a course that has no sources at all.
#' `due:` and `height_measured:` are not written either. An extracted height is
#' the undated measurement the stale check exists to flag, so the first build
#' after an extraction classifies every height as undated, or as unmappable
#' where the site has no local mirror under `docs/` to compare against.
#'
#' @section Why it refuses to overwrite:
#' The extractor this ports wrote `course.extracted.yml` beside an existing
#' `course.yml` because, as its own comment recorded, re-running it "has already
#' destroyed those edits twice". Extraction is a one-time bootstrap; the files
#' are hand-edited afterward, with the term dates, the due dates and the grade
#' weights the export does not carry. So all three files are refused together
#' rather than one being written and another skipped, which would leave a
#' `modules.yml` describing a course its `course.yml` no longer does.
#'
#' @param imscc Path to a Canvas `.imscc` export.
#' @param out_dir Directory the manifests are written into. Created if absent.
#' @param overwrite Replace `course.yml`, `modules.yml` and `reference.yml` when
#'   they are already there. `FALSE`, the default, stops instead.
#' @return `out_dir`, invisibly.
#' @export
extract_manifest <- function(imscc, out_dir, overwrite = FALSE) {
  imscc <- normalizePath(imscc, mustWork = FALSE)
  src <- read_source_cartridge(imscc)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_dir <- normalizePath(out_dir, mustWork = TRUE)

  written <- c("course.yml", "modules.yml", "reference.yml")
  present <- written[file.exists(file.path(out_dir, written))]
  if (length(present) && !overwrite)
    stop(paste(present, collapse = ", "),
         if (length(present) == 1L) " already exists in " else " already exist in ",
         out_dir, ". Extraction is a one-time bootstrap: these files are ",
         "hand-edited afterward with the term dates, due dates and weights the ",
         "export does not carry, and re-running an extractor over them has ",
         "destroyed those edits twice. Pass overwrite = TRUE to replace them.",
         call. = FALSE)

  settings <- export_xml(src, "course_settings/course_settings.xml")
  modmeta  <- export_xml(src, "course_settings/module_meta.xml")
  groups_file <- "course_settings/assignment_groups.xml"
  groups <- if (groups_file %in% src$names) {
    lapply(xml2::xml_find_all(export_xml(src, groups_file), "//assignmentGroup"), function(g) {
      row <- list(name = child_text(g, "title"))
      row$id <- node_attr(g, "identifier")
      row$position <- as.integer(child_text(g, "position", "1"))
      row$weight <- as.numeric(child_text(g, "group_weight", "0"))
      row
    })
  } else list()

  # Every wiki page the export declares, keyed by resource id. A page nothing
  # points at is read and then never written: the module tree is what says which
  # pages this course has.
  pages <- list()
  for (id in names(src$resources)) {
    href <- src$resources[[id]]$href %||% ""
    if (!startsWith(href, "wiki_content/") || !href %in% src$names) next
    pages[[id]] <- page_from_html(read_zip_text(src$zip, href),
                                  tools::file_path_sans_ext(basename(href)))
  }

  # Two definitions may not land on the same key. Nothing downstream can tell
  # them apart afterward: the readers key every definition by its slug or id,
  # and the second one would replace the first silently (review 16).
  claimed <- list(page = list(), assignment = list(), quiz = list())
  claim <- function(kind, key, ref, title) {
    prev <- pick(claimed[[kind]], key)
    if (!is.null(prev) && !identical(prev$ref, ref))
      stop("two ", kind, "s in this export become '", key, "': '", prev$title,
           "' and '", title, "'. They are different resources with the same ",
           "name, and the manifest can hold only one of them under that key. ",
           "Rename one in Canvas and export again.", call. = FALSE)
    claimed[[kind]][[key]] <<- list(ref = ref, title = title)
    invisible(NULL)
  }

  defs <- list(page = list(), assignment = list(), quiz = list())
  mods <- list(); ctypes <- character()
  for (mod in xml2::xml_find_all(modmeta, "//module")) {
    row <- list(title = child_text(mod, "title"))
    row$module_id <- node_attr(mod, "identifier")
    row$published <- identical(child_text(mod, "workflow_state"), "active")
    row$sequential <- identical(child_text(mod, "require_sequential_progress"), "true")
    row$items <- list()
    for (it in xml2::xml_find_all(mod, "./items/item")) {
      ctype <- child_text(it, "content_type"); title <- child_text(it, "title")
      ref <- child_text(it, "identifierref")
      ctypes <- c(ctypes, ctype)
      published <- identical(child_text(it, "workflow_state"), "active")
      form <- if (identical(ctype, "ContextModuleSubHeader")) {
        list(header = title)

      } else if (identical(ctype, "ExternalUrl")) {
        url <- child_text(it, "url")
        if (!nzchar(url))
          stop("module item '", title, "' is an ExternalUrl carrying no <url>. ",
               "A link with no target is not a link.", call. = FALSE)
        list(link = title, url = url)

      } else if (identical(ctype, "WikiPage")) {
        p <- pick(pages, ref)
        if (is.null(p))
          stop("module item '", title, "' points at wiki page ", ref,
               ", which the export declares no wiki_content file for.", call. = FALSE)
        claim("page", p$slug, ref, title)
        if (is.null(pick(defs$page, p$slug))) {
          d <- list(slug = p$slug, title = if (nzchar(p$title)) p$title else title)
          if (isTRUE(p$wrapper)) {
            d$iframe <- p$iframe; d$width <- p$width; d$height <- p$height
            # The frame's name is the page's own unless the export says
            # otherwise, which is the one case `iframe_title:` exists for.
            if (!identical(p$frame_title, d$title)) d$iframe_title <- p$frame_title
            if (isTRUE(p$video)) d$video <- TRUE
          } else {
            d$source_ref <- ref
          }
          defs$page[[p$slug]] <- d
        }
        list(page = p$slug)

      } else if (ctype %in% c("Assignment", "Quizzes::Quiz")) {
        kind <- if (identical(ctype, "Assignment")) "assignment" else "quiz"
        if (!nzchar(ref))
          stop("module item '", title, "' is a ", ctype, " pointing at no ",
               "resource, so there is nothing to carry forward for it.", call. = FALSE)
        key <- slugify(title)
        if (!nzchar(key))
          stop("module item '", title, "' has a title that slugifies to nothing, ",
               "so it cannot be given a key in modules.yml.", call. = FALSE)
        claim(kind, key, ref, title)
        if (is.null(pick(defs[[kind]], key)))
          defs[[kind]][[key]] <- list(id = key, title = title,
                                      published = published, source_ref = ref)
        stats::setNames(list(key), kind)

      } else {
        stop("module item '", title, "' has content_type ", ctype,
             ", which this extractor does not write. Extraction stops rather ",
             "than dropping an item, because a manifest missing one item looks ",
             "exactly like a course that never had it.", call. = FALSE)
      }
      form$item_id <- node_attr(it, "identifier")
      form$indent <- as.integer(child_text(it, "indent", "0"))
      form$published <- published
      row$items[[length(row$items) + 1L]] <- form
    }
    mods[[length(mods) + 1L]] <- row
  }

  wrappers <- Filter(function(d) !is.null(d$iframe), defs$page)
  site <- site_prefix(vapply(wrappers, function(d) as.character(d$iframe), ""))

  cs <- list()
  for (key in CANVAS_SETTINGS_KEYS) {
    v <- xml2::xml_find_first(settings, paste0("./", key))
    if (inherits(v, "xml_missing")) next
    t <- trimws(xml2::xml_text(v))
    cs[[key]] <- if (t %in% c("true", "false")) identical(t, "true") else t
  }

  course <- list(code = child_text(settings, "course_code"),
                 title = child_text(settings, "title"),
                 urls = list(site = site),
                 textbook_docs = "none",
                 term = list(timezone = NULL),
                 canvas = cs,
                 assignment_groups = groups)
  modules_out <- list(modules = mods)
  sections <- c(page = "pages", assignment = "assignments", quiz = "quizzes")
  for (kind in names(sections))
    if (length(defs[[kind]]))
      modules_out[[sections[[kind]]]] <- unname(defs[[kind]])

  base <- basename(imscc)
  ref_rel <- file.path("reference", base)
  dir.create(file.path(out_dir, "reference"), recursive = TRUE, showWarnings = FALSE)
  dest <- file.path(out_dir, ref_rel)
  if (!identical(normalizePath(dest, mustWork = FALSE), imscc))
    file.copy(imscc, dest, overwrite = TRUE)

  write_extracted(file.path(out_dir, "course.yml"), c(
    "# Course metadata, read out of a Canvas export.",
    paste0("# Source: ", base),
    "# Every value here was read from that export, not invented. What the export",
    "# does not carry is not here: the term calendar, the due dates, and the",
    "# link from a page back to the source it was generated from."), course)
  # The one line a course must fill in before it can build anything dated. It is
  # written as a comment beside the key rather than as a plausible default,
  # because a wrong zone moves every due date by hours while looking fine.
  ct <- readLines(file.path(out_dir, "course.yml"))
  at <- grep("^  timezone: ~$", ct)
  if (length(at)) {
    ct <- append(ct, "  # set this; every due: and announcement is read in it",
                 after = at[[1]] - 1L)
    writef(file.path(out_dir, "course.yml"), paste(ct, collapse = "\n"))
  }

  write_extracted(file.path(out_dir, "modules.yml"), c(
    "# Module structure and item ordering, read out of a Canvas export.",
    paste0("# Source: ", base),
    "#",
    "# indent is real information: it drives Canvas's visual nesting, and",
    "# dropping it flattens every module. The item order is the exported order.",
    "# Every page that is not a plain iframe wrapper, and every assignment and",
    "# quiz, carries its exported bytes forward with source_ref: rather than",
    "# being regenerated, because the export is the only copy of them."),
    modules_out)
  write_extracted(file.path(out_dir, "reference.yml"), character(),
                  list(export = ref_rel, source = ref_rel))

  types <- vapply(src$resources, function(r) r$type %||% "", "")
  cat("=== extracted ===\n")
  cat(sprintf("  from %s\n", base))
  cat(sprintf("  modules: %d\n  items:   %d\n", length(mods), length(ctypes)))
  for (k in unique(ctypes)) cat(sprintf("    %s: %d\n", k, sum(ctypes == k)))
  cat(sprintf("  wiki pages: %d wrapper, %d carried\n",
              length(wrappers), length(defs$page) - length(wrappers)))
  cat(sprintf("  assignment groups: %d, weights sum to %s\n", length(groups),
              format(sum(vapply(groups, function(g) as.numeric(g$weight), 0)))))
  cat("  not extracted:\n")
  cat(sprintf("    announcements:     %d\n", sum(grepl("imsdt", types, fixed = TRUE))))
  cat(sprintf("    grading standards: %d\n",
              sum(grepl("^course_settings/grading_standards", src$names))))
  cat(sprintf("    late policy:       %d\n",
              sum(grepl("^course_settings/late_policy", src$names))))
  cat(sprintf("    LTI links:         %d\n", sum(grepl("imsbasiclti", types, fixed = TRUE))))
  cat(sprintf("  wrote course.yml, modules.yml, reference.yml and %s under %s\n",
              ref_rel, out_dir))
  cat("  no height_measured: is written, so the first build classifies every\n")
  cat("  iframe height as undated, or as unmappable where the site is not\n")
  cat("  mirrored under docs/. Both say the same thing: nobody has measured it.\n")
  version_line("extract_manifest")
  invisible(out_dir)
}
