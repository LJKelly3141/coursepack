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
