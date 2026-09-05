skip_if_no <- function(tool) {
  if (!nzchar(Sys.which(tool))) testthat::skip(paste(tool, "is not on the PATH"))
}
skip_if_no_exams <- function() {
  if (!requireNamespace("exams", quietly = TRUE)) testthat::skip("the exams package is not installed")
}
