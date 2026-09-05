# ---- carrying resources out of a source cartridge -------------------------
#
# A course that already exists in Canvas holds pages, assignments and quizzes
# that were written IN Canvas. Regenerating those from YAML would mean
# re-authoring them, and every regeneration would be a chance to change bytes
# nobody asked to change. So a definition may instead name a resource in a
# source cartridge with `source_ref:`, and this file copies that resource's
# declared files into the staging tree UNCHANGED and copies its <resource>
# block into the generated manifest verbatim.
#
# Three properties this is built to hold:
#
#   1. Bytes in equal bytes out. The files are read out of the archive and
#      written back as raw bytes, never parsed and re-serialised, so a carried
#      file's md5 matches the source's. A round trip through an XML writer
#      would reformat attributes and entities and silently change what ships.
#   2. Only what is reachable travels. The walk starts at each `source_ref:`
#      and follows <dependency> edges. A question bank nothing points at stays
#      behind rather than riding along as dead weight Canvas will not read.
#   3. NOTHING is written until EVERY path has been checked. See
#      safe_stage_path() below; this is the review-19 finding and the reason
#      the walk is completed before the first byte is staged.

# The keys a definition uses to generate a body of its own. A carried
# definition brings its body out of the source cartridge, so it declares none
# of them: a definition holding both says two different things about where its
# content comes from, and whichever one the builder happened to prefer would be
# invisible in the output.
BODY_KEYS <- c("iframe", "body", "homework", "quiz_file", "todo",
               "qti", "bank", "description")

# Checked in read_manifest(), so check_manifests() sees a malformed definition
# at check time rather than at build time.
check_carried_shape <- function(defs, what) {
  for (k in names(defs)) {
    d <- defs[[k]]
    if (is.null(d$source_ref)) next
    clash <- intersect(BODY_KEYS, names(d))
    if (length(clash))
      stop(what, " '", k, "' declares source_ref and ", clash[[1]],
           ". A carried definition brings its bytes out of the source ",
           "cartridge unchanged and generates no body of its own.",
           call. = FALSE)
    if (is.null(d$title) || !nzchar(trimws(as.character(d$title))))
      stop(what, " '", k, "' carries source_ref ", d$source_ref,
           " but declares no title:. The module item is named from the ",
           "course's own manifest, never from the carried resource.",
           call. = FALSE)
  }
  invisible(NULL)
}

# Every definition carrying a source_ref, in the order the manifest declares
# them: pages, then assignments, then quizzes. That order is the walk order,
# and the walk order is the order the carried <resource> blocks are appended
# to the generated manifest, so a rebuild is byte-reproducible.
carried_defs <- function(m) {
  out <- list()
  for (kind in c("page", "assignment", "quiz")) {
    defs <- switch(kind, page = m$pages, assignment = m$assignments, quiz = m$quizzes)
    for (k in names(defs)) if (!is.null(defs[[k]]$source_ref))
      out[[length(out) + 1L]] <- list(name = k, kind = kind,
                                      ref = as.character(defs[[k]]$source_ref))
  }
  stats::setNames(out, vapply(out, `[[`, "", "name"))
}

# The cartridge a course carries out of. `source:` names it; `export:` is the
# fallback, because a course that diffs against its own export usually carries
# out of that same file and should not have to name it twice.
source_path <- function(ref, proj, who) {
  p <- ref$source %||% ref$export
  if (is.null(p) || !nzchar(as.character(p)[1]))
    stop("definition '", who, "' carries a source_ref, so this course ",
         "needs reference.yml with source: or export: naming the cartridge ",
         "those bytes come out of", call. = FALSE)
  proj_path(proj, as.character(p)[1])
}

# ---- reading the source cartridge ----------------------------------------

read_zip_text <- function(zipf, name) {
  con <- unz(zipf, name, open = "rb")
  on.exit(close(con), add = TRUE)
  paste(readLines(con, warn = FALSE), collapse = "\n")
}

read_zip_bytes <- function(zipf, name, size) {
  con <- unz(zipf, name, open = "rb")
  on.exit(close(con), add = TRUE)
  readBin(con, "raw", n = as.integer(size))
}

# The raw text of one <resource> block, exactly as the source manifest wrote
# it. Located by identifier with FIXED matching, because an identifier read as
# a pattern is a bug waiting for the first id containing a metacharacter.
#
# The block ends at its own </resource>, or at the end of the opening tag when
# the resource is self-closing. A self-closing <resource .../> is legal and
# Canvas emits one for a webcontent resource with no <file> children; a reader
# that assumed </resource> silently swallowed everything up to the NEXT
# resource's close and carried the wrong block.
resource_span <- function(mtext, id) {
  at <- regexpr(paste0('<resource identifier="', id, '"'), mtext, fixed = TRUE)
  if (at < 0)
    stop("the source manifest declares resource ", id,
         ", which this reader cannot locate as text. It writes the ",
         "identifier attribute first on every <resource>; this one does not.",
         call. = FALSE)
  rest <- substring(mtext, at)
  open_end <- regexpr(">", rest, fixed = TRUE)
  if (open_end < 0) stop("the source manifest never closes the opening tag of resource ", id, call. = FALSE)
  if (identical(substr(rest, open_end - 1L, open_end - 1L), "/"))
    return(list(raw = substr(rest, 1L, open_end), self_closing = TRUE))
  close_at <- regexpr("</resource>", rest, fixed = TRUE)
  if (close_at < 0) stop("the source manifest never closes resource ", id, call. = FALSE)
  list(raw = substr(rest, 1L, close_at + nchar("</resource>") - 1L), self_closing = FALSE)
}

# Parse a source cartridge's manifest into a resource table. The attributes and
# the child elements are read with xml2, because a regex over XML gets the easy
# cases right and the nested ones wrong; the RAW SPAN is taken from the text,
# because that is what gets copied into the generated manifest and a
# re-serialised node is not the same bytes.
read_source_cartridge <- function(path) {
  if (!file.exists(path))
    stop("the source cartridge does not exist: ", path, call. = FALSE)
  listing <- utils::unzip(path, list = TRUE)
  sizes <- stats::setNames(as.numeric(listing$Length), listing$Name)
  if (!"imsmanifest.xml" %in% names(sizes))
    stop("the source cartridge has no imsmanifest.xml: ", path, call. = FALSE)
  mtext <- read_zip_text(path, "imsmanifest.xml")
  doc <- xml2::read_xml(charToRaw(enc2utf8(mtext)))
  xml2::xml_ns_strip(doc)
  resources <- list()
  for (nd in xml2::xml_find_all(doc, "//resources/resource")) {
    id <- xml2::xml_attr(nd, "identifier")
    if (is.na(id) || !nzchar(id)) next
    files <- xml2::xml_attr(xml2::xml_find_all(nd, "./file"), "href")
    deps  <- xml2::xml_attr(xml2::xml_find_all(nd, "./dependency"), "identifierref")
    href  <- xml2::xml_attr(nd, "href")
    span  <- resource_span(mtext, id)
    resources[[id]] <- list(raw = span$raw,
                            type = xml2::xml_attr(nd, "type"),
                            href = if (is.na(href)) NULL else href,
                            files = files[!is.na(files)],
                            deps = deps[!is.na(deps)],
                            self_closing = span$self_closing)
  }
  list(zip = path, names = names(sizes), sizes = sizes,
       manifest = mtext, resources = resources)
}

# ---- where a declared href is allowed to land ----------------------------

# Lexical normalisation. normalizePath() cannot be used here: the destination
# does not exist yet, and for a path that does not exist it returns the input
# unchanged, so a comparison against a resolved staging root would reject every
# safe path on a machine where the temp directory is a symlink.
lexical_path <- function(p) {
  out <- character()
  for (x in strsplit(p, "/", fixed = TRUE)[[1]]) {
    if (!nzchar(x) || identical(x, ".")) next
    if (identical(x, "..")) {
      if (length(out)) out <- out[-length(out)] else out <- c(out, "..")
    } else out <- c(out, x)
  }
  paste0(if (startsWith(p, "/")) "/" else "", paste(out, collapse = "/"))
}

# THE ARCHIVE NAMES ARE UNTRUSTED INPUT. The Python this ports joined a
# declared href straight onto the staging root, so a cartridge declaring
# ../../x wrote outside the build directory and a cartridge declaring /etc/x
# wrote wherever the process could. A cartridge is a zip somebody else made.
#
# Returns the destination path. Callers write to the RETURNED path and never to
# the raw href, or the check is decorative.
safe_stage_path <- function(stage, href) {
  bad <- function() stop("source cartridge declares an unsafe path: ", href, call. = FALSE)
  if (!is.character(href) || length(href) != 1L || is.na(href) || !nzchar(href)) bad()
  if (grepl("\\", href, fixed = TRUE)) bad()          # a backslash is a separator on Windows
  if (startsWith(href, "/") || grepl("^[A-Za-z]:", href)) bad()
  if (any(strsplit(href, "/", fixed = TRUE)[[1]] == "..")) bad()
  dest <- file.path(stage, href)
  if (!startsWith(lexical_path(dest), paste0(lexical_path(stage), "/"))) bad()
  dest
}

# ---- the walk ------------------------------------------------------------

# Walk every source_ref and its dependencies, validate every declared path,
# and only then write. The order matters and is the whole point of the
# function: per-write validation would stage the page and the assignment
# before it reached a bad href behind the last definition's dependency edge,
# and the build would fail with a staging tree half full of another course's
# files. Nothing is written unless everything can be.
carry_resources <- function(defs, src, stage) {
  r <- src$resources
  order <- character()
  visit <- function(id, missing_msg) {
    if (id %in% order) return(invisible(NULL))
    if (is.null(r[[id]])) stop(missing_msg, call. = FALSE)
    order <<- c(order, id)
    for (d in r[[id]]$deps)
      visit(d, paste0("source cartridge resource ", id, " depends on ", d,
                      ", which the cartridge does not declare"))
    invisible(NULL)
  }
  for (d in defs)
    visit(d$ref, paste0("definition '", d$name, "' carries source_ref ", d$ref,
                        ", which is not in ", src$zip))

  hrefs <- character()
  for (id in order) hrefs <- c(hrefs, r[[id]]$href, r[[id]]$files)
  hrefs <- unique(hrefs[nzchar(hrefs)])

  dest <- vapply(hrefs, function(h) safe_stage_path(stage, h), "", USE.NAMES = FALSE)
  for (h in hrefs) if (!h %in% src$names)
    stop("source cartridge declares a file it does not contain: ", h,
         ". The manifest and the archive disagree; the export is damaged.",
         call. = FALSE)

  for (i in seq_along(hrefs)) {
    dir.create(dirname(dest[[i]]), recursive = TRUE, showWarnings = FALSE)
    writeBin(read_zip_bytes(src$zip, hrefs[[i]], src$sizes[[hrefs[[i]]]]), dest[[i]])
  }
  list(raw = vapply(order, function(id) r[[id]]$raw, "", USE.NAMES = FALSE),
       carried = order, files = hrefs)
}

# What build_cartridge() holds when nothing is carried, so every consumer reads
# the same shape whether or not a source cartridge is in play.
no_carry <- function() list(raw = character(), carried = character(), files = character())
