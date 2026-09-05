test_that("a fresh scaffold passes check_manifests, builds a cartridge with one module and one page, and contains nothing it should not", {
  skip_if_no("zip"); skip_if_no("pandoc")
  d <- withr::local_tempdir(); p <- file.path(d, "c")
  init_course(p, code = "ABCD 101", title = "A Course", site_url = "https://example.invalid/c",
              timezone = "America/Chicago", ask = FALSE, git = FALSE)
  expect_no_error(check_manifests(p))
  res <- build_cartridge(p)
  mm <- paste(readLines(file.path(res$stage, "course_settings", "module_meta.xml")), collapse = "\n")
  expect_length(gregexpr("<module identifier=", mm)[[1]], 1L)
  expect_length(list.files(file.path(res$stage, "wiki_content")), 1L)
  expect_false(dir.exists(file.path(res$stage, "assessments")))
  files <- list.files(res$stage, recursive = TRUE, full.names = TRUE)
  expect_false(any(vapply(files, function(f) length(grepRaw("IMS-CC-FILEBASE", readBin(f, "raw", file.info(f)$size), fixed = TRUE)) > 0, TRUE)))
  # the containment gate: a fake render that leaks the canary is caught
  dir.create(file.path(p, "docs")); file.copy(file.path(p, "assessments", "leak-canary.qmd"), file.path(p, "docs", "leak.html"))
  expect_error(leak_check(p), "LEAK")
})
