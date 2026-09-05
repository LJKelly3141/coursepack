test_that("the fixture course parses and reaches every item form", {
  p <- copy_course()
  m <- read_manifest(p)
  forms <- unlist(lapply(m$mods$modules, function(mod) vapply(mod$items, function(it)
    intersect(c("header", "page", "link", "assignment", "quiz"), names(it))[1], "")))
  expect_setequal(unique(forms), c("header", "page", "link", "assignment", "quiz"))
  expect_true(isTRUE(m$pages[["chapter-one"]]$body))
  expect_true(!is.null(m$assignments[["quiz-1"]]$quiz_file))
  expect_true(!is.null(m$assignments[["todo-1"]]$todo))
  expect_equal(read_timezone(m$course), "America/Chicago")
  expect_true(dir.exists(textbook_docs_path(m$course, p)))
})

test_that("no course fact leaked into the fixtures", {
  hits <- suppressWarnings(system2("grep", c("-rniE", shQuote("econ ?[0-9]|uwrf|kelly|ljkelly|managerial|macro_principles"),
                            shQuote(fixture_path())), stdout = TRUE, stderr = FALSE))
  expect_length(hits, 0)
})

test_that("the sample QTI zips and holds exactly two distinct item idents sharing the base", {
  skip_if_no("zip")
  p <- copy_course()
  z <- zip_fixture_qti(p)
  expect_true(file.exists(z))
  files <- utils::unzip(z, list = TRUE)$Name
  expect_true(any(grepl("assessment_meta\\.xml$", files)))
  d <- withr::local_tempdir(); utils::unzip(z, exdir = d)
  ass <- setdiff(list.files(d, "\\.xml$", recursive = TRUE, full.names = TRUE),
                 list.files(d, "assessment_meta\\.xml$", recursive = TRUE, full.names = TRUE))
  expect_length(ass, 1L)
  x <- paste(readLines(ass), collapse = "\n")
  idents <- regmatches(x, gregexpr('<item ident="[^"]*"', x))[[1]]
  expect_length(idents, 2L); expect_length(unique(idents), 2L)
  expect_true(all(grepl('ident="quiz-sample_[0-9]+_section_1_item_0[12]_num"', idents)))
  expect_match(x, "<!DOCTYPE")
})
