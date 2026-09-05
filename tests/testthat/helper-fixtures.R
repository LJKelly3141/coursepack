fixture_path <- function(...) testthat::test_path("fixtures", ...)

copy_course <- function(name = "minimal-course", to = withr::local_tempdir(.local_envir = parent.frame())) {
  ok <- file.copy(fixture_path(name), to, recursive = TRUE)
  ok2 <- file.copy(fixture_path("fake-textbook"), to, recursive = TRUE)
  stopifnot(all(ok), all(ok2))
  normalizePath(file.path(to, name))
}

zip_fixture_qti <- function(course_dir) {
  src <- fixture_path("qti-sample", "quiz-sample")
  out_dir <- file.path(course_dir, "build", "qti")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  zipf <- normalizePath(file.path(out_dir, "quiz-sample.zip"), mustWork = FALSE)
  old <- setwd(dirname(src)); on.exit(setwd(old), add = TRUE)
  utils::zip(zipf, list.files(basename(src), recursive = TRUE, full.names = TRUE), flags = "-q -X")
  zipf
}
