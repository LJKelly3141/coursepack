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

built <- function() {
  skip_if_no("zip"); skip_if_no("pandoc")
  to <- withr::local_tempdir(.local_envir = parent.frame())   # bind the tempdir to the TEST, not to this helper
  p <- copy_course(to = to); zip_fixture_qti(p)
  res <- build_cartridge(p)
  list(p = p, stage = res$stage, imscc = res$imscc,
       man = paste(readLines(file.path(res$stage, "imsmanifest.xml")), collapse = "\n"),
       mm = paste(readLines(file.path(res$stage, "course_settings", "module_meta.xml")), collapse = "\n"))
}

# Replace one literal line fragment in a fixture YAML file. `from` is matched
# fixed, so regex metacharacters in YAML need no escaping.
edit_yaml <- function(p, file, from, to) {
  y <- paste(readLines(file.path(p, file)), collapse = "\n")
  stopifnot(grepl(from, y, fixed = TRUE))
  writeLines(sub(from, to, y, fixed = TRUE), file.path(p, file))
}
