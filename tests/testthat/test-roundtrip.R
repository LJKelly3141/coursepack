test_that("build, extract, build reproduces the staging tree", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  # Announcements, the grading standard and the late policy are not extracted
  # (decision E8), so they are removed from the source before the first build.
  unlink(file.path(p, "announcements.yml"))
  y <- readLines(file.path(p, "course.yml"))
  cut <- function(y, start) { i <- grep(start, y); j <- i; while (j < length(y) && grepl("^  ", y[j + 1])) j <- j + 1; y[-(i:j)] }
  y <- cut(y, "^grading_standard:"); y <- cut(y, "^late_policy:")
  writeLines(sub("grading_standard_enabled: true", "grading_standard_enabled: false", y), file.path(p, "course.yml"))
  one <- build_cartridge(p)
  h1 <- tree_hashes(one$stage)
  out <- withr::local_tempdir()
  extract_manifest(one$imscc, out)
  two <- build_cartridge(out)
  h2 <- tree_hashes(two$stage)
  expect_identical(h2, h1)
})
