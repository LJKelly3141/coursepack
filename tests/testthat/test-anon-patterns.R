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
            "Route 66 Road Trip is a phrase.",
            "obs 105 230 1450 rows",
            "[1] 512 384 2048",
            "  625 480 1200",
            "Residuals 100 120 1300",
            "breaks 500 750 1000",
            "See @fig-scatter and @tbl-summary, as [@smith2020; @lee2019] show.",
            "In @sec-intro and @eq-ols we cite [@smith2020].",
            "#' @param x a vector",
            "#' @return the fit",
            "  #' @export")
  expect_identical(redact_patterns(keep)$text, keep)
})

test_that("phone forms with a parenthesis, one repeated separator or +1 are redacted", {
  x <- c("(715) 555-0142", "(715)555-0142", "715-555-0142", "715.555.0142",
         "+1 715-555-0142", "+1 (715) 555-0142", "715-555.0142", "715 555 0142")
  r <- redact_patterns(x)
  expect_identical(r$text, c(rep("[PHONE]", 6), "715-555.0142", "715 555 0142"))
  expect_identical(r$counts[["PHONE"]], 6L)
})

test_that("a handle is still a handle outside roxygen lines", {
  r <- redact_patterns(c("Follow @patq_22 for updates.", "#' @param x", "ping @patq_22, thanks"))
  expect_identical(r$text, c("Follow [HANDLE] for updates.", "#' @param x", "ping [HANDLE], thanks"))
  expect_identical(r$counts[["HANDLE"]], 2L)
})

test_that("redact_paths counts only when asked and keeps its replacements", {
  x <- "See /Users/pat/work and pat@example.edu"
  expect_equal(redact_paths(x), "See /Users/USER/work and EMAIL")
  r <- redact_paths(x, counts = TRUE)
  expect_equal(r$text, "See /Users/USER/work and EMAIL")
  expect_equal(r$counts, c(PATH = 1L, EMAIL = 1L))
})

test_that("profile pattern does not match inside other domains", {
  keep <- c("Get it at dropbox.com/abc today.",
            "Try linux.com/x for docs.",
            "Visit mytwitter.com/foo now.")
  expect_identical(redact_patterns(keep)$text, keep)
})

test_that("NA input yields non-NA integer counts", {
  r <- redact_patterns(c("a", NA))
  expect_false(anyNA(r$counts))
  expect_type(r$counts, "integer")
  expect_false(anyNA(redact_paths(c("a", NA), counts = TRUE)$counts))
})
