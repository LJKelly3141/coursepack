# The UWRF slide style ships with the package as a Quarto format extension under
# inst/templates/slides/. It sits beside the course template rather than inside
# it because init_course() pushes every course-template file through
# render_template(), which reads text and would corrupt the logo PNG. A course
# picks the style up by having the extension directory beside its decks, and
# this is the function that puts it there.

#' Install the UWRF slide style into a course
#'
#' Copy the `uwrf` Quarto format extension into `dir` under the course root, so
#' a deck there can declare `format: uwrf-revealjs` and get the university
#' brand: Passion Red Impact headings, Arial body text, the UWRF logo, slide
#' numbers, linear navigation, a 1280 by 720 canvas and embedded resources. It
#' is the only slide style the package carries so far.
#'
#' Nothing outside `proj` is touched, and the course's `_quarto.yml` is not
#' edited: its render list is an explicit allowlist, and adding the deck
#' directory to it is the course's decision, so the closing summary says what
#' to add.
#'
#' @param proj Course project root. Written to under `dir`.
#' @param dir Directory under `proj` that holds the deck sources, created if it
#'   does not exist. Quarto looks for `_extensions/` beside a document, so the
#'   decks and the extension share a directory.
#' @param overwrite Replace an installed copy. The default refuses, so a local
#'   edit to the style is not lost by a re-run; pass `TRUE` to pick up a newer
#'   version of the style from a reinstalled package.
#' @return The path of the installed extension, `<proj>/<dir>/_extensions/uwrf`,
#'   invisibly.
#' @examples
#' p <- file.path(tempdir(), "uwrf-example")
#' init_course(p, code = "ABCD 101", title = "A Course",
#'             site_url = "https://example.invalid/c", timezone = "UTC",
#'             ask = FALSE, git = FALSE)
#' use_uwrf_slides(p)
#' list.files(file.path(p, "slides", "_extensions", "uwrf"))
#' unlink(p, recursive = TRUE)
#' @export
use_uwrf_slides <- function(proj, dir = "slides", overwrite = FALSE) {
  if (!is.character(proj) || length(proj) != 1L || !dir.exists(proj))
    stop("proj is not a directory: ", paste(proj, collapse = ""), call. = FALSE)
  proj <- normalizePath(proj, mustWork = TRUE)
  src <- system.file("templates", "slides", "_extensions", "uwrf",
                     package = "coursepack")
  if (!nzchar(src))
    stop("the coursepack slide templates are not installed", call. = FALSE)

  ext_dir <- file.path(proj, dir, "_extensions")
  dst <- file.path(ext_dir, "uwrf")
  rel <- file.path(dir, "_extensions", "uwrf")
  if (dir.exists(dst)) {
    if (!isTRUE(overwrite))
      stop("the UWRF slide style is already installed at ", rel,
           "; pass overwrite = TRUE to replace it", call. = FALSE)
    unlink(dst, recursive = TRUE)
  }
  dir.create(ext_dir, recursive = TRUE, showWarnings = FALSE)
  # file.copy() of a directory places it under the destination by its own
  # name, so this lands at <ext_dir>/uwrf with every file intact, the logo
  # included. Nothing here reads a file as text.
  if (!isTRUE(file.copy(src, ext_dir, recursive = TRUE)))
    stop("could not copy the UWRF slide style into ", ext_dir, call. = FALSE)

  cat("=== UWRF slide style installed ===\n")
  cat("  ", rel, "\n", sep = "")
  for (f in sort(list.files(dst, recursive = TRUE))) cat("    ", f, "\n", sep = "")
  cat("\nA deck in ", dir, "/ opts in with:\n", sep = "")
  cat("  format:\n    uwrf-revealjs:\n      footer: \"<course>, <term>\"\n")
  cat("\nTo render the decks with the site, add \"", dir,
      "/**/*.qmd\" to the render list in _quarto.yml.\n", sep = "")
  version_line("use_uwrf_slides")
  invisible(dst)
}
