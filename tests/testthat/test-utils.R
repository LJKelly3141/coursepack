test_that("%||% returns the default only for NULL", {
  expect_equal(NULL %||% 2, 2)
  expect_equal(1 %||% 2, 1)
  expect_equal(NA %||% 2, NA)
  expect_equal(list() %||% 2, list())
})

test_that("coursepack_version() matches DESCRIPTION", {
  expect_equal(coursepack_version(), as.character(utils::packageVersion("coursepack")))
})

test_that("version_line prints the version after a label", {
  expect_output(version_line("built"), "built: coursepack [0-9.]+")
})
