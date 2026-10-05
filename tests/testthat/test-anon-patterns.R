test_that("fixed patterns are redacted by type, with counts", {
  x <- c("Call me at (715) 555-0142 or 715.555.0199.",
         "SSN 123-45-6789 on file.",
         "I was born on March 4, 2003 and my DOB: 03/04/2003.",
         "I live at 1410 N Main Street in town.",
         "See github.com/patquill and https://www.linkedin.com/in/pat-quill-12",
         "Follow @patq_22 for updates.")
  r <- redact_patterns(x)
  expect_equal(r$text[1], "Call me at [PHONE] or [PHONE].")
  expect_equal(r$text[2], "SSN [SSN] on file.")
  expect_equal(r$text[3], "I was born on [DOB] and my DOB: [DOB].")
  expect_equal(r$text[4], "I live at [ADDRESS] in town.")
  expect_equal(r$text[5], "See [PROFILE] and [PROFILE]")
  expect_equal(r$text[6], "Follow [HANDLE] for updates.")
  expect_equal(unname(r$counts[c("PHONE","SSN","DOB","ADDRESS","PROFILE","HANDLE")]),
               c(2L, 1L, 2L, 1L, 2L, 1L))
})

test_that("statistical output and code are left alone", {
  keep <- c("Years 2019-2023, range 12.5-13.5, R^2 0.912, tol 1e-8.",
            "summary(fit)@coef and obj@slot are R slots.",
            "Canvas id 10970338 and 114224481 in a table.",
            "Estimate -63.2274 SE 107.0997 t -0.590 p 0.5581",
            "Dates 2026-09-30 and 09/30/2026 with no birth context.",
            "Route 66 Road Trip is a phrase.")
  expect_identical(redact_patterns(keep)$text, keep)
})

test_that("redact_paths counts only when asked and keeps its replacements", {
  x <- "See /Users/pat/work and pat@example.edu"
  expect_equal(redact_paths(x), "See /Users/USER/work and EMAIL")
  r <- redact_paths(x, counts = TRUE)
  expect_equal(r$text, "See /Users/USER/work and EMAIL")
  expect_equal(r$counts, c(PATH = 1L, EMAIL = 1L))
})
