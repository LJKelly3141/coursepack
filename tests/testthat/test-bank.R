test_that("read_bank loads a chapter and refuses a missing one", {
  b <- read_bank(fixture_path("bank"), 1)
  expect_equal(b$chapter, 1L); expect_length(b$sections, 2L)
  expect_error(read_bank(fixture_path("bank"), 9), "does not exist")
})

test_that("check_question refuses the three malformed shapes with the location in the message", {
  ok <- list(type = "multiple_choice", options = list(A = "a", B = "b"), answer = "A")
  expect_no_error(check_question(ok, "Q1"))
  expect_error(check_question(modifyList(ok, list(type = "essay")), "Q1"), "Q1: question type 'essay' is not supported")
  expect_error(check_question(list(options = list(A = "a"), answer = "A"), "Q1"), "needs at least two options")
  expect_error(check_question(modifyList(ok, list(answer = "C")), "Q1"), "answer 'C' is not one of")
})

test_that("check_bank enforces unique ids and existing images, and warns on a figure without alt", {
  b <- read_bank(fixture_path("bank"), 1)
  expect_length(check_bank(b, fixture_path("bank", "images"))$warnings, 0L)
  b2 <- b; b2$sections[[1]]$questions[[2]]$figure$alt <- NULL
  expect_match(check_bank(b2, fixture_path("bank", "images"))$warnings, "id 2.*no alt")
  b3 <- b; b3$sections[[2]]$questions[[1]]$id <- 1L
  expect_error(check_bank(b3, fixture_path("bank", "images")), "duplicate question id")
  b4 <- b; b4$sections[[1]]$questions[[2]]$image <- "missing.png"
  expect_error(check_bank(b4, fixture_path("bank", "images")), "image .*missing.png does not exist")
})
