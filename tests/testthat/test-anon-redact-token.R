test_that("a match becomes [name] and carries no code", {
  terms <- data.frame(term = c("Pat Quill", "Quill", "Robin"), code = c("S01", "S01", "S02"),
                      loose = c(TRUE, FALSE, FALSE), stringsAsFactors = FALSE)
  r <- redact_text(c("By Pat Quill.", "Robin helped me."), terms)
  expect_equal(r$text, c("By [name].", "[name] helped me."))
  expect_equal(r$n, 2L)
  expect_false(any(grepl("S0[0-9]|SXX", r$text)))
})

test_that("the token is never re-matched", {
  terms <- data.frame(term = c("name", "Pat"), code = c("S01", "S02"),
                      loose = FALSE, stringsAsFactors = FALSE)
  r <- redact_text("Pat wrote my name here.", terms)
  expect_equal(r$text, "[name] wrote my [name] here.")
  expect_equal(r$n, 2L)
})

test_that("the leftover check does not read the token as a student named name", {
  d <- withr::local_tempdir(); f <- file.path(d, "file1.md")
  terms <- data.frame(term = c("name", "Pat"), code = c("S01", "S02"),
                      loose = c(TRUE, FALSE), stringsAsFactors = FALSE)
  writeLines(c("[name] wrote [name]", "[NAME]?"), f)
  # "[NAME]" is not the token: it is a leftover.
  expect_equal(nrow(find_leftovers(f, terms)), 1L)
  writeLines("[name] wrote [name][name]", f)
  expect_equal(nrow(find_leftovers(f, terms)), 0L)
  writeLines("[name] wrote, my name is", f)
  expect_identical(find_leftovers(f, terms)$code, "S01")
})
