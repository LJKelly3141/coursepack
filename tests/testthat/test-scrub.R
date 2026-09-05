# The public-readiness scrub is a repository audit rather than package code: it
# greps the checkout for course residue, the repository address outside the files
# allowed to carry it, Sys.getenv() in R/, absolute paths, em-dashes in shipped
# text, and token shapes in the git history. tools/ is in .Rbuildignore, so the
# script is absent from the built tarball and this skips there instead of failing.
#
# The script's greps name R/, inst/ and tests/ relative to the package root, and
# its history grep needs to be inside the working tree, so it runs with the root
# as the working directory rather than tests/testthat/.
test_that("the public-readiness scrub finds nothing outside its allowed set", {
  script <- testthat::test_path("..", "..", "tools", "scrub.sh")
  skip_if(!file.exists(script), "tools/scrub.sh is not in this tree (R CMD check tarball)")
  # Both paths are resolved before with_dir() changes directory: system2() is the
  # lazily evaluated argument, so a relative path would be read from the new root.
  script <- normalizePath(script)
  root <- normalizePath(testthat::test_path("..", ".."))
  out <- withr::with_dir(root, system2(script, stdout = TRUE, stderr = TRUE))
  status <- attr(out, "status")
  if (is.null(status)) status <- 0L
  expect_equal(as.integer(status), 0L, info = paste(c("scrub output:", out), collapse = "\n"))
  expect_true("scrub: clean" %in% out)
})
