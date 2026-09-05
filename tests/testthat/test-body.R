tb <- function() fixture_path("fake-textbook", "docs")

test_that("homework_section_html keeps the instruction subsections and drops the walkthrough", {
  h <- homework_section_html("ch01", "homework-assignment", tb(), "https://example.invalid/book", "hw-1")
  expect_match(h, "Objective"); expect_match(h, "Instructions")
  expect_no_match(h, "The Data"); expect_no_match(h, "Step 1")
})

test_that("heading levels normalise to h2, a bold-only paragraph becomes h3, links and images go absolute", {
  h <- homework_section_html("ch01", "homework-assignment", tb(), "https://example.invalid/book/", "hw-1")
  expect_match(h, "<h2[ >]"); expect_no_match(h, "<h3 class=\"anchored\">Objective")
  expect_match(h, "<h3>1\\. Write your specification first</h3>")
  expect_match(h, 'href="https://example.invalid/book/data/example.csv"[^>]*>example.csv</a>')
  expect_match(h, 'src="https://example.invalid/book/img/plot.png"')
  expect_no_match(h, "anchorjs-link")
})

test_that("homework_section_html refuses a missing chapter, a missing anchor, and an anchor with no instruction subsections", {
  expect_error(homework_section_html("nope", "x", tb(), "https://b", "a"), "not rendered")
  expect_error(homework_section_html("ch01", "no-such-anchor", tb(), "https://b", "a"), "not found")
  expect_error(homework_section_html("ch02", "sec-two", tb(), "https://b", "a"), "Refusing to build")
})

test_that("quiz_student_md truncates at the answer key and never returns the canary", {
  q <- fixture_path("minimal-course", "assessments", "quizzes", "quiz01.md")
  kept <- quiz_student_md(q, "quiz-1")
  expect_true(any(grepl("^# 2\\. Questions", kept)))
  expect_false(any(grepl("ANSWER KEY", kept)))
  expect_false(any(grepl(LEAK_CANARY, kept, fixed = TRUE)))
})

test_that("a quiz without an answer-key heading, or with the canary above it, stops", {
  d <- withr::local_tempdir()
  writeLines(c("# 1. Instructions", "text"), file.path(d, "nokey.md"))
  expect_error(quiz_student_md(file.path(d, "nokey.md"), "a"), "no ANSWER KEY heading")
  writeLines(c("# 1. Instructions", LEAK_CANARY, "# 3. ANSWER KEY"), file.path(d, "leak.md"))
  expect_error(quiz_student_md(file.path(d, "leak.md"), "a"), "leak canary survived")
  expect_error(quiz_student_md(file.path(d, "absent.md"), "a"), "does not exist")
})

test_that("quiz_student_html rewrites relative asset paths to the site and refuses one that survives", {
  skip_if_no("pandoc")
  q <- fixture_path("minimal-course", "assessments", "quizzes", "quiz01.md")
  h <- quiz_student_html(q, "quiz-1", "https://example.invalid/course")
  expect_match(h, 'src="https://example.invalid/course/assets/quiz/fig.png"')
  expect_error(quiz_student_html(q, "quiz-1", NULL), "relative asset path survived")
})
