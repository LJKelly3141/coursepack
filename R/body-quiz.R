# Shared quiz body extraction. Sourced, never executed.
#
# WHY THIS IS SHARED RATHER THAN DUPLICATED. build_cartridge() inlines a quiz's
# questions into its Canvas assignment description, and build_preview() shows
# the same questions in the mockup so they can be reviewed before an import.
# Those two MUST produce identical text. A preview that shows something other
# than what ships is lying about its only job, and here the divergence would be
# invisible: the preview would look fine while the cartridge shipped the answer
# key, or the reverse. One function, two callers, no drift.
#
# THE SAFETY PROPERTY. A quiz source file holds the questions AND the answer key
# AND the rubric. Only the student-facing part may ever leave this function.
# An assignment description is shown to students exactly as written, which is
# the opposite of quiz QTI, where an answer key may legitimately travel in the
# cartridge because Canvas withholds it for grading.
#
# Three independent things must fail before an answer key could ship:
#   1. truncation at the ANSWER KEY heading, here,
#   2. the canary stop below, here,
#   3. build_cartridge()'s pre-zip scan across the whole staging tree.
# Do not delete any one of them on the grounds that the others cover it. That
# reasoning is how a safeguard becomes circular, which has happened in this
# repo before.

# The answer-key convention a course must follow today: the heading that ends
# the student-facing part matches ANSWER_KEY_HEADING_RE, and LEAK_CANARY is the
# string a course plants inside its keys so a leak is detectable as bytes.
# Making both configurable per course is recorded in NEWS as not yet done.
LEAK_CANARY <- "CANARY_ANSWER_KEY_MUST_NEVER_BE_PUBLIC"
ANSWER_KEY_HEADING_RE <- "^#+\\s*3\\.\\s*ANSWER\\s*KEY"

# Read a quiz source file and return ONLY the student-facing markdown:
# section 1 (instructions) and section 2 (the questions). Everything from the
# ANSWER KEY heading down is dropped.
#' Extract student-facing quiz markdown
#'
#' @param path Path to a quiz source file.
#' @param id Quiz identifier used in error messages.
#' @return The student-facing markdown lines before the answer key.
#' @examples
#' quiz <- tempfile("quiz-", fileext = ".md")
#' writeLines(c("# 1. Instructions", "Answer every question.", "",
#'              "# 2. Questions", "1. What is 2 + 2?", "",
#'              "# 3. ANSWER KEY", "1. 4"), quiz)
#'
#' # Everything from the answer key heading down is dropped.
#' quiz_student_md(quiz)
#'
#' unlink(quiz)
#' @export
quiz_student_md <- function(path, id = basename(path)) {
  if (!file.exists(path))
    stop("quiz '", id, "' points at a file that does not exist: ", path)
  lines <- readLines(path, warn = FALSE)

  # Heading level and capitalisation vary across the seven files, so match on
  # the words rather than on an exact heading string.
  cut <- grep(ANSWER_KEY_HEADING_RE, lines, ignore.case = TRUE)
  if (!length(cut))
    stop("quiz '", id, "' has no ANSWER KEY heading, so the student-facing ",
         "part cannot be separated from the answers. Refusing to continue.")

  kept <- lines[seq_len(cut[1] - 1L)]

  if (any(grepl(LEAK_CANARY, kept, fixed = TRUE)))
    stop("quiz '", id, "': leak canary survived truncation. The answer key ",
         "would have been shown to students. Refusing to continue.")

  kept
}

# Same content, converted to HTML. Used for the Canvas assignment description
# and for the preview pane.
#' Convert student-facing quiz markdown to HTML
#'
#' @inheritParams quiz_student_md
#' @param site_base Base URL used to make relative asset paths absolute.
#' @return The student-facing quiz HTML.
#' @examples
#' quiz <- tempfile("quiz-", fileext = ".md")
#' writeLines(c("# 1. Instructions", "Answer every question.", "",
#'              "# 2. Questions",
#'              "1. What is 2 + 2?",
#'              "", "![A plot](../../assets/quiz/plot.png)", "",
#'              "# 3. ANSWER KEY", "1. 4"), quiz)
#'
#' \dontrun{
#' # Needs pandoc, so this one is not run here. site_base is what turns the
#' # relative asset path above into an absolute URL Canvas can resolve.
#' quiz_student_html(quiz, site_base = "https://example.org/demo")
#' }
#'
#' unlink(quiz)
#' @export
quiz_student_html <- function(path, id = basename(path), site_base = NULL) {
  kept <- quiz_student_md(path, id)
  md <- tempfile(fileext = ".md")
  on.exit(unlink(md), add = TRUE)
  writeLines(kept, md)
  html <- tryCatch(
    system2("pandoc", c("--from=markdown", "--to=html", shQuote(md)), stdout = TRUE),
    error = function(e) stop("pandoc failed converting quiz '", id, "': ",
                             conditionMessage(e)))
  if (!length(html))
    stop("quiz '", id, "' converted to empty HTML. Refusing to continue.")
  out <- paste(html, collapse = "\n")

  # RELATIVE ASSET PATHS MUST BECOME ABSOLUTE, or every quiz image is broken in
  # Canvas. The quiz markdown references its artifacts as ../../assets/quiz/...
  # which is correct relative to the source file and meaningless once the HTML
  # is sitting inside a Canvas assignment description: Canvas resolves it
  # against its own domain and returns 404. This is the package rule, that
  # asset references are absolute Pages URLs and never cartridge-internal paths.
  #
  # Caught on the first real check of a built cartridge, not by reading. The
  # markdown looked right, the HTML looked right, and the images would all have
  # failed on import.
  if (!is.null(site_base) && nzchar(site_base)) {
    base <- sub("/+$", "", site_base)
    out <- gsub('(<(?:img|a|source)[^>]*\\s(?:src|href)=")(?:\\.\\./)+(assets/)',
                paste0("\\1", base, "/\\2"), out, perl = TRUE)
  }

  # Refuse to hand back a body that still carries a relative asset path. Silent
  # breakage on import is the failure mode this whole file exists to prevent.
  if (grepl('(?:src|href)="(?:\\.\\./|assets/)', out, perl = TRUE))
    stop("quiz '", id, "': a relative asset path survived rewriting, so its ",
         "images would 404 in Canvas. Refusing to continue.")

  out
}
