# Protected phrases (anon_keep.txt). Every name here is invented.

test_that("protected phrases survive; the same name alone does not", {
  terms <- data.frame(term = c("Avery", "Quill"), code = c("S04", "S04"),
                      loose = FALSE, stringsAsFactors = FALSE)
  keep <- c("Avery J. Thorn")
  x <- c("Professor Dr. Avery J. Thorn", "Thanks, Avery", "avery  j.\nthorn wrote")
  m <- mask_keep(x, keep)
  r <- redact_text(m$text, terms)
  out <- unmask_keep(r$text, m)
  expect_equal(out[1], "Professor Dr. Avery J. Thorn")
  expect_equal(out[2], "Thanks, [name]")
  expect_equal(out[3], "avery  j.\nthorn wrote")
  expect_equal(m$n, 2L)
})

test_that("the mask holds no ASCII letter or digit, so no key term can match it", {
  keep <- "Avery J. Thorn"
  x <- paste(rep("Avery J. Thorn", 12), collapse = " and ")
  m <- mask_keep(x, keep)
  expect_equal(m$n, 12L)
  expect_false(grepl("[A-Za-z0-9]", gsub(" and ", "", m$text)))
  terms <- data.frame(term = c("1", "11", "S01"), code = "S01", loose = FALSE,
                      stringsAsFactors = FALSE)
  r <- redact_text(m$text, terms)
  expect_equal(r$n, 0L)
  expect_identical(unmask_keep(r$text, m), x)
})

test_that("a phrase inside a longer word is not protected", {
  m <- mask_keep("Avery J. Thornton", "Avery J. Thorn")
  expect_equal(m$n, 0L)
  expect_identical(m$text, "Avery J. Thornton")
})

test_that("drop_keep blanks protected occurrences only", {
  expect_identical(drop_keep(c("Dr. Avery J. Thorn said", "Avery"), "Avery J. Thorn"),
                   c("Dr.   said", "Avery"))
  expect_identical(drop_keep("Avery", character()), "Avery")
})

test_that("a one-word line in anon_keep.txt stops with its line number only", {
  d <- withr::local_tempdir()
  writeLines(c("# instructor", "Avery J. Thorn", "", "Avery"), file.path(d, "anon_keep.txt"))
  expect_error(read_keep_phrases(d), "line 4")
  expect_error(read_keep_phrases(d), regexp = "^((?!Avery).)*$", perl = TRUE)
})

test_that("comments and blank lines are skipped and phrases are trimmed", {
  d <- withr::local_tempdir()
  writeLines(c("# instructor", "  Avery J. Thorn  ", "", "Dr. Thorn"),
             file.path(d, "anon_keep.txt"))
  k <- read_keep_phrases(d)
  expect_identical(as.vector(k), c("Avery J. Thorn", "Dr. Thorn"))
  expect_identical(attr(k, "line"), c(2L, 4L))
})

test_that("no file means no protected phrases", {
  expect_identical(read_keep_phrases(withr::local_tempdir()), character())
})

test_that("a protected phrase is not a leftover and does not flag an image", {
  d <- withr::local_tempdir()
  f <- file.path(d, "file1.md")
  writeLines("Dr. Avery J. Thorn", f)
  terms <- data.frame(term = "Avery", code = "S01", loose = FALSE, stringsAsFactors = FALSE)
  keep <- "Avery J. Thorn"
  expect_equal(nrow(find_leftovers(f, terms, keep = keep)), 0L)
  expect_equal(nrow(find_leftovers(f, terms)), 1L)
  loose <- loose_terms(terms)
  expect_true(is.na(text_reason("Dr. Avery J. Thorn", terms, loose, keep = keep)))
  expect_identical(text_reason("Dr. Avery J. Thorn", terms, loose), "name")
  # The same name alone, beside the phrase, still flags.
  expect_identical(text_reason("Avery J. Thorn and Avery", terms, loose, keep = keep), "name")
  # Patterns are still checked on the full text.
  expect_identical(text_reason("Avery J. Thorn 715-555-0142", terms, loose, keep = keep),
                   "pattern")
})

test_that("an anon_keep.txt saved with a byte-order mark reads correctly", {
  d <- withr::local_tempdir(); p <- file.path(d, "anon_keep.txt")
  con <- file(p, "wb")
  writeBin(c(as.raw(c(0xEF, 0xBB, 0xBF)),
             charToRaw("Avery J. Thorn\r\nDr. Thorn\r\n")), con)
  close(con)
  expect_identical(as.vector(read_keep_phrases(d)), c("Avery J. Thorn", "Dr. Thorn"))
})

test_that("redact_lines masks a phrase split across two lines and keeps the lines", {
  terms <- data.frame(term = "Avery", code = "S01", loose = FALSE, stringsAsFactors = FALSE)
  x <- c("as Dr. Avery J.", "Thorn noted.", "", "Thanks Avery", "")
  r <- redact_lines(x, terms, "Avery J. Thorn")
  expect_identical(r$text, c("as Dr. Avery J.", "Thorn noted.", "", "Thanks [name]", ""))
  expect_equal(r$n, 1L); expect_equal(r$kept, 1L)
  r0 <- redact_lines(x, terms, character())
  expect_identical(r0$text, c("as Dr. [name] J.", "Thorn noted.", "", "Thanks [name]", ""))
  expect_equal(r0$n, redact_text(x, terms)$n)
  expect_identical(redact_lines(character(), terms, "Avery J. Thorn")$text, character())
})

test_that("a phrase holding a student's full name, login or id is refused by line number", {
  d <- withr::local_tempdir()
  key <- data.frame(name_forms = "Morgan Rivera; Rivera, Morgan; Rivera; Morgan",
                    nicknames = "", login = "XQ1002", canvas_id = "1002",
                    stringsAsFactors = FALSE)
  chk <- function(lines) {
    writeLines(lines, file.path(d, "anon_keep.txt"))
    errors_with(check_keep_phrases(read_keep_phrases(d), key))
  }
  for (bad in c("TA Morgan Rivera", "rivera,  morgan helps", "login XQ1002 here",
                "Course 1002 TA")) {
    msg <- chk(c("# x", "Morgan J. Ellery", bad))
    expect_match(msg, "anon_keep.txt line 3 contains a student's name or id")
    expect_false(grepl("Morgan|Rivera|XQ1002|1002", msg))
  }
  expect_true(is.na(chk(c("Morgan J. Ellery", "Dr. Rivera Hall"))))
})
