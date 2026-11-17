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
#' numbers, linear navigation, a 1280 by 720 canvas and embedded resources.
#' [use_falcon_slides()] and [use_falcon_light_slides()] install the two
#' falcon styles the same way.
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
  install_slide_style(proj, dir, overwrite, "uwrf", "UWRF", "use_uwrf_slides")
}

#' Install the falcon slide styles into a course
#'
#' Copy the `falcon` (dark) or `falcon-light` Quarto format extension into
#' `dir` under the course root, so a deck there can declare
#' `format: falcon-revealjs` or `format: falcon-light-revealjs`. They carry the
#' look of the falcon lecture-video themes: headings in white condensed
#' capitals on a red band with a slanted end and a sky-blue stripe, Barlow
#' Condensed headings and Nunito Sans body text (both bundled, so every machine
#' shows the same face and a rendered deck needs no web access), slide numbers,
#' linear navigation, a 1280 by 720 canvas and embedded resources. Neither
#' shows a logo. Every text colour clears 4.5:1 on its background; where a
#' video colour did not, text uses a lighter or darker shade of the same hue.
#' The classes are the same as the UWRF style's (see the slides README).
#'
#' Nothing outside `proj` is touched, and the course's `_quarto.yml` is not
#' edited; the closing summary says what to add.
#'
#' @inheritParams use_uwrf_slides
#' @return The path of the installed extension,
#'   `<proj>/<dir>/_extensions/falcon` or `.../falcon-light`, invisibly.
#' @examples
#' p <- file.path(tempdir(), "falcon-example")
#' init_course(p, code = "ABCD 101", title = "A Course",
#'             site_url = "https://example.invalid/c", timezone = "UTC",
#'             ask = FALSE, git = FALSE)
#' use_falcon_slides(p)
#' use_falcon_light_slides(p)
#' list.files(file.path(p, "slides", "_extensions"))
#' unlink(p, recursive = TRUE)
#' @export
use_falcon_slides <- function(proj, dir = "slides", overwrite = FALSE) {
  install_slide_style(proj, dir, overwrite, "falcon", "Falcon", "use_falcon_slides")
}

#' @rdname use_falcon_slides
#' @export
use_falcon_light_slides <- function(proj, dir = "slides", overwrite = FALSE) {
  install_slide_style(proj, dir, overwrite, "falcon-light", "Falcon Light",
                      "use_falcon_light_slides")
}

# Copy the slide style `id` from inst/templates/slides/_extensions/ into
# <proj>/<dir>/_extensions/<id>. label names it in messages; fn is the
# exported function, for the version line.
install_slide_style <- function(proj, dir, overwrite, id, label, fn) {
  if (!is.character(proj) || length(proj) != 1L || !dir.exists(proj))
    stop("proj is not a directory: ", paste(proj, collapse = ""), call. = FALSE)
  proj <- normalizePath(proj, mustWork = TRUE)
  src <- system.file("templates", "slides", "_extensions", id,
                     package = "coursepack")
  if (!nzchar(src))
    stop("the coursepack slide templates are not installed", call. = FALSE)

  ext_dir <- file.path(proj, dir, "_extensions")
  dst <- file.path(ext_dir, id)
  rel <- file.path(dir, "_extensions", id)
  if (dir.exists(dst)) {
    if (!isTRUE(overwrite))
      stop("the ", label, " slide style is already installed at ", rel,
           "; pass overwrite = TRUE to replace it", call. = FALSE)
    unlink(dst, recursive = TRUE)
  }
  dir.create(ext_dir, recursive = TRUE, showWarnings = FALSE)
  # file.copy() of a directory places it under the destination by its own
  # name, so this lands at <ext_dir>/<id> with every file intact, a logo
  # included. Nothing here reads a file as text.
  if (!isTRUE(file.copy(src, ext_dir, recursive = TRUE)))
    stop("could not copy the ", label, " slide style into ", ext_dir, call. = FALSE)

  cat("=== ", label, " slide style installed ===\n", sep = "")
  cat("  ", rel, "\n", sep = "")
  for (f in sort(list.files(dst, recursive = TRUE))) cat("    ", f, "\n", sep = "")
  cat("\nA deck in ", dir, "/ opts in with:\n", sep = "")
  cat("  format:\n    ", id, "-revealjs:\n      footer: \"<course>, <term>\"\n", sep = "")
  cat("\nTo render the decks with the site, add \"", dir,
      "/**/*.qmd\" to the render list in _quarto.yml.\n", sep = "")
  # lecturecast is optional and not a declared dependency, so it is detected
  # by its installed files rather than by requireNamespace().
  if (nzchar(system.file(package = "lecturecast"))) {
    cat("\nlecturecast is installed: a rendered deck can also become a narrated\n")
    cat("video. See the course-slides skill.\n")
  } else {
    cat("\nNarrated videos from these decks need the lecturecast package, which is\n")
    cat("not installed. Slides for class work without it.\n")
  }
  version_line(fn)
  invisible(dst)
}
