# Shared resolution logic. Used by `check_manifests()`, `build_preview()` and
# `build_cartridge()`.
#
# This exists because the checker and the mockup ask the same question: does the
# chapter file exist, and does the anchor exist inside it? Two copies would
# drift, and the mockup would eventually reassure you about a link the checker
# rejects. One implementation, two callers.
#
# Pure functions plus one file read. No course-specific constants: everything
# comes in as an argument.

# Replace {textbook}, {site}, {legacy} with values from course.yml urls.
#' Interpolate named URL tokens
#'
#' @param s A character string containing named URL tokens, or `NULL`.
#' @param urls A named list of token replacements.
#' @return The interpolated character string, or `NULL` when `s` is `NULL`.
#' @examples
#' urls <- list(site = "https://example.org/demo",
#'              textbook = "https://example.org/book")
#' interp_urls("{site}/content/pages/welcome.html", urls)
#' interp_urls("{textbook}/ch01.html#sec-mean", urls)
#' # A token with no value in urls is left alone.
#' interp_urls("{legacy}/old.html", urls)
#' # NULL travels through untouched.
#' interp_urls(NULL, urls)
#' @export
interp_urls <- function(s, urls) {
  if (is.null(s)) return(NULL)
  for (k in names(urls)) s <- gsub(paste0("{", k, "}"), urls[[k]], s, fixed = TRUE)
  s
}

# Mirrors `url_for()` in `R/cartridge-items.R`.
#' Build a textbook chapter URL
#'
#' @param chapter A chapter slug, `NULL`, or an empty string.
#' @param anchor An optional anchor name.
#' @param base The textbook base URL.
#' @return The chapter URL, or the textbook root URL for an empty chapter.
#' @examples
#' chapter_url("ch01", NULL, "https://example.org/book")
#' chapter_url("ch01", "sec-mean", "https://example.org/book")
#' # An empty or absent chapter points at the textbook root.
#' chapter_url("", NULL, "https://example.org/book")
#' chapter_url(NULL, NULL, "https://example.org/book")
#' @export
chapter_url <- function(chapter, anchor, base) {
  if (is.null(chapter) || !nzchar(chapter)) return(paste0(base, "/"))
  paste0(base, "/", chapter, ".html",
         if (!is.null(anchor)) paste0("#", anchor) else "")
}

# Does the chapter file exist, and does the anchor exist inside it?
# Returns state: ok | missing-chapter | missing-anchor | unchecked
#' Resolve a textbook chapter and anchor
#'
#' Reports `ok` when the chapter and requested anchor exist,
#' `missing-chapter` when the chapter file is absent, `missing-anchor` when the
#' file lacks the requested anchor, and `unchecked` when resolution cannot be
#' performed. The two fail-open scars are an absent textbook directory and a
#' `NULL` or empty chapter; both return `unchecked`, even when the other input
#' would permit a check.
#' @param chapter A chapter slug, `NULL`, or an empty string.
#' @param anchor An optional anchor name.
#' @param tb_docs Path to the rendered textbook directory.
#' @return A list with `state` and `detail`. `state` is one of `ok`,
#'   `missing-chapter`, `missing-anchor`, or `unchecked`.
#' @examples
#' docs <- file.path(tempdir(), "book-docs")
#' dir.create(docs, showWarnings = FALSE)
#' writeLines('<h2 id="sec-mean">The mean</h2>', file.path(docs, "ch01.html"))
#' resolve_target("ch01", NULL, docs)$state
#' resolve_target("ch01", "sec-mean", docs)$state
#' resolve_target("ch01", "sec-nope", docs)
#' resolve_target("ch99", NULL, docs)$state
#' # The two fail-open scars: no chapter to check, and no textbook to check it in.
#' resolve_target(NULL, NULL, docs)$state
#' resolve_target("ch01", NULL, file.path(tempdir(), "no-such-book"))$state
#' unlink(docs, recursive = TRUE)
#' @export
resolve_target <- function(chapter, anchor, tb_docs) {
  if (is.null(chapter) || !nzchar(chapter))
    return(list(state = "unchecked", detail = "no chapter"))
  if (!dir.exists(tb_docs))
    return(list(state = "unchecked", detail = paste0("textbook not built at ", tb_docs)))

  f <- file.path(tb_docs, paste0(chapter, ".html"))
  if (!file.exists(f))
    return(list(state = "missing-chapter", detail = paste0(chapter, ".html not found")))
  if (is.null(anchor)) return(list(state = "ok", detail = ""))

  h <- paste(readLines(f, warn = FALSE), collapse = "\n")
  if (!grepl(paste0('id="', anchor, '"'), h, fixed = TRUE))
    return(list(state = "missing-anchor",
                detail = paste0("#", anchor, " not in ", chapter, ".html")))
  list(state = "ok", detail = "")
}

# Every chapter/anchor reference in the manifest: module items carrying
# chapter:, plus assignments carrying homework$chapter. Placeholder assignments
# have a chapter but no anchor; the chapter must still exist.
#' Collect textbook references from a manifest
#'
#' @param mods A parsed modules manifest.
#' @return A list of references, each containing `ch`, `anc`, and `what`.
#' @examples
#' mods <- list(
#'   modules = list(list(items = list(
#'     list(link = "Chapter 1", chapter = "ch01", anchor = "sec-mean")))),
#'   assignments = list(
#'     list(id = "hw-01", homework = list(chapter = "ch01", anchor = "sec-drills"))))
#' refs <- collect_refs(mods)
#' length(refs)
#' # A module item first, then the assignments that name a chapter.
#' refs[[1]]
#' refs[[2]]
#' @export
collect_refs <- function(mods) {
  refs <- list()
  for (m in mods$modules) for (it in m$items)
    if (!is.null(it$chapter) && nzchar(it$chapter))
      refs[[length(refs) + 1]] <- list(ch = it$chapter, anc = it$anchor, what = it$link)
  for (a in mods$assignments)
    if (!is.null(a$homework$chapter))
      refs[[length(refs) + 1]] <- list(ch = a$homework$chapter,
                                       anc = a$homework$anchor, what = a$id)
  refs
}
