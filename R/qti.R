# Build a Canvas-importable QTI 1.2 zip from an R/exams quiz definition.
#
# The generator is swappable. The contract other generators must honor is just
# "write a QTI 1.2 zip into build/qti/". Nothing downstream depends on R/exams
# specifically, so text2qti or a hand-rolled generator can sit alongside this
# without either one being rewritten.
#
# This function does NOT prove the quiz works. Only a Canvas import does.

#' Build a QTI quiz package
#'
#' Read an R quiz definition and render its exercises as a Canvas-importable
#' QTI 1.2 zip file under `build/qti` in the project directory.
#'
#' @param quiz_file Path to an R file that assigns a `quiz` list containing
#'   `name`, `exercises`, and `n`, with optional `points` and `quiztype`.
#' @param proj Project root under which the output is written.
#' @return The path to the generated zip file, invisibly.
#' @examples
#' # A quiz definition names exercise files, which sit in an exercises/
#' # directory beside the directory the definition is in.
#' proj <- tempfile("qti-")
#' dir.create(file.path(proj, "quizzes"), recursive = TRUE)
#' dir.create(file.path(proj, "exercises"))
#' writeLines(c("Question", "========", "What is 1 + 1?", "",
#'              "Solution", "========", "2", "",
#'              "Meta-information", "================",
#'              "extype: num", "exsolution: 2", "exname: onePlusOne"),
#'            file.path(proj, "exercises", "one.Rmd"))
#' quiz_file <- file.path(proj, "quizzes", "tiny.R")
#' writeLines('quiz <- list(name = "tiny", exercises = "one.Rmd", n = 1)', quiz_file)
#'
#' \dontrun{
#' # Needs the exams package and pandoc, so this one is not run here.
#' build_qti(quiz_file, proj)
#' }
#'
#' unlink(proj, recursive = TRUE)
#' @export
build_qti <- function(quiz_file, proj = ".") {
  quiz_file <- normalizePath(quiz_file, mustWork = FALSE)
  if (!file.exists(quiz_file)) {
    stop("quiz definition does not exist: ", quiz_file, call. = FALSE)
  }

  quiz <- NULL
  source(quiz_file, local = TRUE)

  required <- c("name", "exercises", "n")
  missing <- setdiff(required, names(quiz))
  if (!is.null(missing) && length(missing) > 0L) {
    stop("quiz definition is missing: ", paste(missing, collapse = ", "), call. = FALSE)
  }

  exercise_dir <- file.path(dirname(dirname(quiz_file)), "exercises")
  paths <- file.path(exercise_dir, quiz$exercises)
  absent <- paths[!file.exists(paths)]
  if (length(absent) > 0L) {
    stop("exercise files not found:\n  ", paste(absent, collapse = "\n  "), call. = FALSE)
  }

  out_dir <- file.path(proj, "build", "qti")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  cat("Building:", quiz$name, "\n")
  cat("  exercises:", paste(quiz$exercises, collapse = ", "), "\n")
  cat("  versions: ", quiz$n, "\n")

  if (!requireNamespace("exams", quietly = TRUE)) {
    stop('install.packages("exams") to build QTI packages', call. = FALSE)
  }
  exams::exams2canvas(
    file = paths,
    n = quiz$n,
    dir = out_dir,
    name = quiz$name,
    points = if (!is.null(quiz$points)) quiz$points else 1,
    quiztype = if (!is.null(quiz$quiztype)) quiz$quiztype else "assignment",
    # pandoc-mathjax is the package default and the safer choice. Canvas needs
    # math MathJax can render. pandoc-mathml also works but the package docs warn
    # it can misbehave when a quiz is imported into the item bank.
    converter = "pandoc-mathjax"
  )

  zip_path <- file.path(out_dir, paste0(quiz$name, ".zip"))
  if (!file.exists(zip_path)) {
    stop("expected zip was not produced: ", zip_path, call. = FALSE)
  }

  cat("\nWrote: ", zip_path, "\n", sep = "")
  cat("       ", round(file.size(zip_path) / 1024, 1), " KB\n", sep = "")
  cat("\nNOT VERIFIED. A zip that builds says nothing about whether Canvas\n")
  cat("accepts it. Import into a throwaway course shell and preview the quiz.\n")
  cat("Canvas fails silently on invalid QTI: the quiz simply never appears.\n")
  version_line("build_qti")
  invisible(zip_path)
}
