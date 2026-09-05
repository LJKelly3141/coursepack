defn <- function(dir, body) { f <- file.path(dir, "quizzes", "q.R"); dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE); writeLines(body, f); f }

test_that("a missing definition file and missing required fields stop with the field names", {
  d <- withr::local_tempdir()
  expect_error(build_qti(file.path(d, "nope.R"), d), "does not exist")
  f <- defn(d, 'quiz <- list(name = "q")')
  expect_error(build_qti(f, d), "missing: exercises, n")
})

test_that("absent exercise files are listed", {
  d <- withr::local_tempdir()
  f <- defn(d, 'quiz <- list(name = "q", exercises = c("a.Rmd", "b.Rmd"), n = 1)')
  expect_error(build_qti(f, d), "exercise files not found:.*a.Rmd.*b.Rmd")
})

test_that("with exams installed, a one-exercise quiz writes build/qti/<name>.zip under proj", {
  skip_if_no_exams(); skip_if_no("pandoc"); skip_if_no("zip")
  d <- withr::local_tempdir(); dir.create(file.path(d, "exercises"))
  writeLines(c("Question", "========", "What is 1 + 1?", "", "Solution", "========", "2", "",
               "Meta-information", "================", "extype: num", "exsolution: 2", "exname: onePlusOne"),
             file.path(d, "exercises", "one.Rmd"))
  f <- defn(d, 'quiz <- list(name = "tiny", exercises = "one.Rmd", n = 1)')
  z <- build_qti(f, d)
  expect_equal(normalizePath(z), normalizePath(file.path(d, "build", "qti", "tiny.zip")))
})
