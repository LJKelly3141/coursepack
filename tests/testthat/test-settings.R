base <- list(title = "T", canvas = list(course_code = "ABCD 101-01", is_public = FALSE, default_view = "modules"))
test_that("keys are emitted in canonical order, logicals lowercased, unknown keys refused", {
  x <- course_settings_xml(base, list(has_tile = FALSE), has_grading_standard = FALSE)
  expect_match(x, "<course_code>ABCD 101-01</course_code>\\s*<is_public>false</is_public>\\s*<default_view>modules</default_view>")
  expect_no_match(x, "grading_standard_identifier_ref")
  bad <- base; bad$canvas$foo <- 1
  expect_error(course_settings_xml(bad, list(has_tile = FALSE), FALSE), "unknown canvas: key: foo")
  nocode <- base; nocode$canvas$course_code <- NULL
  expect_error(course_settings_xml(nocode, list(has_tile = FALSE), FALSE), "canvas: course_code")
})
