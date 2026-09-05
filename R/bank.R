# Question banks: one JSON file per chapter, read and checked before anything
# draws from them.
#
# The schema is the one the snapshot's generator reads:
#
#   {chapter, title, source, sections: [{section, questions: [{id, type,
#     difficulty, objective, question, options {A..D}, answer, explanation,
#     image, figure {file, script, alt}}]}]}
#
# A question stem is HTML, so `<br>`, `<i>` and `<table>` in it are content and
# not markup errors. Ids are integers and unique within the chapter, because the
# generator derives a stable item identifier from the chapter, the section and
# the id; two questions sharing an id would collapse into one Canvas item.
#
# The checks refuse rather than warn. A quiz that silently under-draws, or a
# question whose figure is missing, is a defect students meet and nobody else
# sees. The one exception is a figure without alt text, which is reported as a
# warning: the image is there and the item works, so the build carries on while
# the author is told what to write.

#' Read one chapter of a question bank
#'
#' Parse `chapter_<NN>.json` out of a bank directory. Question ids and the
#' chapter number are coerced to integer; everything else is returned as it was
#' written, with no vector simplification, so a one-option question stays a list
#' rather than becoming a bare string.
#'
#' @param dir Directory holding the bank's `chapter_<NN>.json` files.
#' @param chapter Chapter number. Padded to two digits to make the file name.
#' @return The parsed bank: a list with `chapter`, `title`, `source` and
#'   `sections`, each section a list with `section` and `questions`.
#' @export
read_bank <- function(dir, chapter) {
  path <- file.path(dir, sprintf("chapter_%02d.json", as.integer(chapter)))
  if (!file.exists(path)) {
    stop("question bank ", path, " does not exist", call. = FALSE)
  }
  bank <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  bank$chapter <- as.integer(bank$chapter %||% chapter)
  bank$sections <- lapply(bank$sections %||% list(), function(s) {
    s$questions <- lapply(s$questions %||% list(), function(q) {
      q$id <- as.integer(q$id)
      q
    })
    s
  })
  bank
}

#' Check one question
#'
#' Refuse the three shapes the generator cannot render: a type it does not
#' support, fewer than two options, and an answer key naming no option. Every
#' message is prefixed with `where`, so the author is told which item in which
#' section of which chapter to open.
#'
#' @param q One question, as `read_bank()` returns it.
#' @param where Location prefix for the error message.
#' @return `TRUE`, invisibly, when the question is well formed. Otherwise it
#'   stops.
#' @export
check_question <- function(q, where) {
  type <- as.character(q$type %||% "multiple_choice")
  if (!identical(type, "multiple_choice")) {
    stop(where, ": question type '", type, "' is not supported", call. = FALSE)
  }
  opts <- q$options %||% list()
  if (!is.list(opts) || length(opts) < 2L) {
    stop(where, ": needs at least two options", call. = FALSE)
  }
  answer <- as.character(q$answer %||% "")
  if (!answer %in% names(opts)) {
    stop(where, ": answer '", answer, "' is not one of ",
         paste(names(opts), collapse = ", "), call. = FALSE)
  }
  invisible(TRUE)
}

#' Check a whole question bank
#'
#' Every question is checked, ids are required to be unique within the chapter,
#' and every question naming an `image` must have that file under `images_dir`.
#' A figure carrying no `alt` text is returned as a warning rather than stopping
#' the run, because the item still renders.
#'
#' Exported so a bank-authoring session can check its own work without building
#' anything.
#'
#' @param bank A bank, as `read_bank()` returns it.
#' @param images_dir Directory holding the bank's figure PNGs.
#' @return `list(warnings = <character>)`, one entry per figure with no alt
#'   text, each naming the chapter, the section and the question id.
#' @export
check_bank <- function(bank, images_dir) {
  warns <- character()
  seen <- integer()
  for (s in bank$sections %||% list()) {
    for (q in s$questions %||% list()) {
      where <- paste0("chapter ", bank$chapter, ": ", s$section %||% "",
                      " question id ", q$id)
      check_question(q, where)

      id <- as.integer(q$id)
      if (id %in% seen) {
        stop("chapter ", bank$chapter, ": duplicate question id ", id, call. = FALSE)
      }
      seen <- c(seen, id)

      image <- as.character(q$image %||% "")
      if (nzchar(image)) {
        p <- file.path(images_dir, image)
        if (!file.exists(p)) {
          stop(where, ": image ", p, " does not exist", call. = FALSE)
        }
        if (!nzchar(as.character(q$figure$alt %||% ""))) {
          warns <- c(warns, paste0(where, ": figure has no alt text"))
        }
      }
    }
  }
  list(warnings = warns)
}
