# A list-valued override REPLACES the default outright. modifyList() merges one
# list into the other, so spec(draws = list(2L, 1L)) would come back as the
# three-entry default and every refusal below would go untested.
spec <- function(...) {
  base <- list(dir = "bank", chapters = list(1L, 2L), draws = list(2L, 1L, 2L), points = 5,
               group_by = "section", allowed_attempts = -1L)
  over <- list(...)
  for (n in names(over)) base[n] <- list(over[[n]])
  base
}
with_bank <- function() {
  to <- withr::local_tempdir(.local_envir = parent.frame())
  p <- copy_course(to = to); file.copy(fixture_path("bank"), p, recursive = TRUE); p
}

test_that("bank_groups orders chapter then section and enforces every refusal", {
  p <- with_bank()
  g <- bank_groups(spec(), p, "T")
  expect_equal(vapply(g$groups, `[[`, "", "name"), c("1.1 First Ideas", "1.2 Second Ideas", "Sample Chapter Two"))
  expect_equal(g$draws, c(2L, 1L, 2L))
  expect_error(bank_groups(spec(chapters = list()), p, "T"), "T: bank.chapters is empty")
  expect_error(bank_groups(spec(points = NULL), p, "T"), "bank.points is required")
  expect_error(bank_groups(spec(group_by = "topic"), p, "T"), "group_by must be section or chapter")
  expect_error(bank_groups(spec(draws = list(2L, 1L)), p, "T"), "2 draws given for 3 bank sections")
  expect_error(bank_groups(spec(points = 4), p, "T"), "draws sum to 5 but points is 4")
  expect_error(bank_groups(spec(draws = list(2L, 9L, 2L), points = 13), p, "T"), "has 3 questions, cannot draw 9")
  gc <- bank_groups(spec(group_by = "chapter", draws = list(3L, 2L)), p, "T")
  expect_equal(vapply(gc$groups, `[[`, "", "name"), c("Sample Chapter One", "Sample Chapter Two"))
  expect_length(gc$groups[[1]]$qs, 6L)
})

test_that("splits expand a section into parts and refuse gaps, overlaps and unused entries", {
  p <- with_bank()
  sp <- spec(draws = list(list(1L, 1L), 1L, 2L), splits = list(`1.1 First Ideas` = list(list(1L, 2L), list(3L))))
  g <- bank_groups(sp, p, "T")
  expect_equal(g$groups[[1]]$name, "1.1 First Ideas (part 1)"); expect_equal(g$groups[[2]]$name, "1.1 First Ideas (part 2)")
  expect_equal(g$draws, c(1L, 1L, 1L, 2L))
  bad <- sp; bad$splits[[1]] <- list(list(1L, 2L), list(2L, 3L)); expect_error(bank_groups(bad, p, "T"), "lists ids in two parts")
  bad$splits[[1]] <- list(list(1L), list(3L)); expect_error(bank_groups(bad, p, "T"), "splits leave ids out")
  bad$splits <- list(`1.2 Second Ideas` = list(list(4L, 5L, 6L))); bad$draws <- list(2L, 1L, 2L)
  expect_error(bank_groups(bad, p, "T"), "splits names sections whose draw is not a list")
})

test_that("answer ids are unique within an item and stable; a forced collision is salted", {
  ids <- answer_ids("gabc", c("A", "B", "C", "D"))
  expect_length(unique(unlist(ids)), 4L); expect_identical(ids, answer_ids("gabc", c("A", "B", "C", "D")))
  expect_true(all(unlist(ids) >= 1000 & unlist(ids) <= 9999))
})

test_that("normalize_tables adds a caption, scope and thead, and leaves an already-normal table alone", {
  t <- "<table><tr><th>x</th><th>y</th></tr><tr><td>1</td><td>2</td></tr></table>"
  n <- normalize_tables(t)
  expect_match(n, "<caption>Data for this question</caption>", fixed = TRUE)
  expect_match(n, '<thead><tr><th scope="col">x</th><th scope="col">y</th></tr></thead><tbody>', fixed = TRUE)
  expect_identical(normalize_tables(n), n)
})

test_that("window_utc converts a course-zone stamp and refuses a bad format", {
  expect_equal(window_utc("2026-10-25 09:00:00", "America/Chicago", "T", "unlock_at"), "2026-10-25T14:00:00")
  expect_equal(window_utc(NULL, "America/Chicago", "T", "unlock_at"), "")
  expect_error(window_utc("2026-10-25", "America/Chicago", "T", "unlock_at"), "unlock_at must be 'YYYY-MM-DD HH:MM:SS'")
})

test_that("the generated files match the Python generator after id normalisation", {
  skip_if_no("python3")
  snap <- testthat::test_path("..", "..", "project", "econ202-toolchain", "scripts")
  skip_if(!file.exists(file.path(snap, "generate_resources.py")), "the Python snapshot is not present (R CMD check tarball)")
  p <- with_bank(); stage_r <- withr::local_tempdir(); stage_py <- withr::local_tempdir()
  q <- list(id = "q-bank", title = "Module 1 Bank Quiz", group = "Quizzes", published = TRUE, bank = spec())
  ids <- list(quiz_res = c(`q-bank` = "g00000000000000000000000000000d01"), quiz_meta = c(`q-bank` = "g00000000000000000000000000000d02"),
              quiz_aid = c(`q-bank` = "g00000000000000000000000000000d03"))
  course <- read_course(p); groups <- assignment_group_ids(course)
  generate_quiz_files(q, "Module 1: Start Here", course, p, stage_r, ids, groups)
  sj <- tempfile(fileext = ".json")
  jsonlite::write_json(list(title = q$title, module_title = "Module 1: Start Here", group = "Quizzes", group_id = unname(groups["Quizzes"]),
                            tz = "America/Chicago", quiz_id = "g00000000000000000000000000000d01", published = TRUE,
                            bank = list(chapters = c(1, 2), draws = c(2, 1, 2), points = 5, group = "Quizzes")), sj, auto_unbox = TRUE)
  system2("python3", c(testthat::test_path("oracle", "generate_quiz.py"), snap, file.path(p, "bank"), sj, stage_py))
  norm <- function(f) { x <- paste(readLines(f, warn = FALSE), collapse = "\n")
    x <- gsub("g[0-9a-f]{32}", "GID", x); x <- gsub('ident="[0-9]{4}"', 'ident="AID"', x)
    x <- gsub("(<varequal respident=\"response1\">)[0-9]{4}", "\\1AID", x)
    x <- gsub("(<fieldentry>)[0-9]{4}(,[0-9]{4})*", "\\1AIDS", x); x }
  for (f in c("non_cc_assessments/g00000000000000000000000000000d01.xml.qti",
              "g00000000000000000000000000000d01/assessment_qti.xml",
              "g00000000000000000000000000000d01/assessment_meta.xml"))
    expect_identical(norm(file.path(stage_r, f)), norm(file.path(stage_py, f)), info = f)
  expect_true(file.exists(file.path(stage_r, "web_resources", "quiz_images", "CH01_Q002.png")))
})
