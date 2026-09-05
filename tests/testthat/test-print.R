test_that("a bank quiz prints a deterministic form and a key that matches it item for item", {
  skip_if_no("pandoc")
  p <- copy_course()
  r1 <- print_assessment(p, "q-bank", seed = 7, render = FALSE)
  r2 <- print_assessment(p, "q-bank", seed = 7, render = FALSE, out_dir = file.path(p, "build", "paper2"))
  expect_identical(readLines(r1$qmd), readLines(r2$qmd))
  r3 <- print_assessment(p, "q-bank", seed = 8, render = FALSE, out_dir = file.path(p, "build", "paper3"))
  expect_false(identical(readLines(r1$qmd), readLines(r3$qmd)))
  key <- readLines(r1$key)
  rows <- key[grepl("^\\| *[0-9]+ *\\|", key)]
  expect_length(rows, 5L)                                   # sum(draws)
  expect_true(any(grepl("seed 7", key)))
  expect_true(file.exists(file.path(dirname(r1$qmd), "CH01_Q002.png")) || !any(grepl("CH01_Q002", readLines(r1$qmd))))
})

test_that("a description assignment prints its body; an R/exams or carried quiz is refused", {
  skip_if_no("pandoc")
  p <- copy_course()
  r <- print_assessment(p, "memo-1", seed = 1, render = FALSE)
  expect_match(paste(readLines(r$qmd), collapse = "\n"), "Upload your draft before class on Thursday.")
  expect_null(r$key)
  expect_error(print_assessment(p, "q-sample", seed = 1), "printable forms are bank quizzes")
})

test_that("with quarto available the form renders to docx", {
  skip_if_no("pandoc"); skip_if_no("quarto")
  p <- copy_course()
  r <- print_assessment(p, "q-bank", seed = 3, formats = "docx")
  expect_true(file.exists(r$rendered[["docx"]]))
})
