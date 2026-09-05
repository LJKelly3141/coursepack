# The stale-height check.
#
# THE GENERAL RULE, and the reason this file exists:
#
#   An export is the specification for STRUCTURE, and only structure. Anything
#   in it that was MEASURED, an iframe height, a due date, a chapter coverage
#   list, is a stale observation with an expiry date, not a spec. Structure may
#   be copied forever. Measurements must be re-taken, and a build must not
#   silently pretend otherwise.
#
# The course this was written for shipped every one of its 135 pages with a
# height copied out of an eight-month-old export. Content had been added to
# those pages since, so 25 of the first 31 checked were too short and showed
# students an inner scrollbar for the whole term. Nothing complained, because
# nothing knew the number had an age.
#
# So an iframe height carries `height_measured:`, and this compares it against
# the mtime of the page it describes. A page edited after its measurement means
# the height is a guess again.
#
# WHY `unmappable` IS A CLASS AND NOT A SKIP. The Python original did
# `if not local.exists(): continue`, which exempted from the check exactly the
# pages it could not verify. A height it cannot map is the height most likely to
# be wrong: the URL moved, or docs/ was never rendered. The count is printed, so
# a course that reports four unmappable heights knows it is checking nothing.

# Iframe heights measured against the page they describe.
#
# For every page declaring `iframe:` whose resolved src starts with
# `course$urls$site`, the tail of the URL under that site is the path under
# `<proj>/docs`, which is the local mirror of the published site (the same
# mapping `build_preview()` serves as /site). Each such page is classified:
#
#   undated      no `height_measured:`, or one that does not parse. An undated
#                height is indistinguishable from one copied out of an old
#                export.
#   stale        the local file's mtime is after `height_measured:`, so the
#                page was edited after the height was taken.
#   fresh        measured at or after the last edit.
#   unmappable   no local file under docs/ answers the URL, so nothing can be
#                compared. Counted, never silently exempt.
#
# A page with `iframe:` and no `height:` is already a hard stop in
# write_wiki_pages(); this is warning-level and the build proceeds. A course
# with no `urls: site:` has no site-hosted frame to check, and every iframe it
# declares points somewhere this cannot reason about, so nothing is classified.
#
# Returns list(undated, stale, fresh, unmappable), each a character vector of
# slugs, and prints the counts with the slugs of every non-empty class.
check_stale_heights <- function(proj, course, pages) {
  classes <- c("undated", "stale", "fresh", "unmappable")
  out <- stats::setNames(rep(list(character()), length(classes)), classes)
  urls <- course$urls
  site <- sub("/+$", "", as.character(urls$site %||% ""))
  docs <- file.path(proj, "docs")
  if (nzchar(site)) for (k in names(pages)) {
    p <- pages[[k]]
    if (is.null(p$iframe)) next
    src <- interp_urls(as.character(p$iframe), urls)
    if (!startsWith(src, site)) next
    local <- docs_path_for(docs, substring(src, nchar(site) + 1L))
    cls <- if (!file.exists(local)) {
      "unmappable"
    } else {
      when <- parse_measured(p$height_measured)
      if (is.na(when)) "undated"
      else if (file.info(local)$mtime > when) "stale"
      else "fresh"
    }
    out[[cls]] <- c(out[[cls]], k)
  }
  part <- function(nm) paste0(length(out[[nm]]), " ", nm,
                              if (length(out[[nm]]))
                                paste0(" (", paste(out[[nm]], collapse = ", "), ")") else "")
  cat("  heights: ", paste(vapply(classes, part, ""), collapse = ", "), "\n", sep = "")
  invisible(out)
}

# The path under docs/ a site URL tail names. A query or a fragment is not part
# of the file name, and a directory URL is served by its index.html.
docs_path_for <- function(docs, tail) {
  tail <- sub("[?#].*$", "", sub("^/+", "", tail))
  if (!nzchar(tail) || endsWith(tail, "/")) tail <- paste0(tail, "index.html")
  p <- file.path(docs, tail)
  if (dir.exists(p)) file.path(p, "index.html") else p
}

# `height_measured:` as a time. A YAML reader may hand this back as a string or
# as a parsed timestamp, so both are accepted. Anything unreadable is NA, which
# the caller reports as undated: a date it cannot read is a date it does not
# have, and reading it as "now" would call every stale height fresh.
parse_measured <- function(when) {
  if (is.null(when) || !length(when)) return(as.POSIXct(NA))
  if (inherits(when, "POSIXt")) return(as.POSIXct(when)[1])
  if (inherits(when, "Date")) return(as.POSIXct(when[1]))
  s <- trimws(as.character(when)[1])
  if (!nzchar(s)) return(as.POSIXct(NA))
  s <- sub("Z$", "", s)
  for (f in c("%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M", "%Y-%m-%d")) {
    t <- as.POSIXct(s, format = f)
    if (!is.na(t)) return(t)
  }
  as.POSIXct(NA)
}
