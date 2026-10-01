# canvas_grades() fills scores into a Canvas gradebook export for re-import.
# Canvas only accepts an import that is exactly its own export, so the core
# assertion is byte-level: the output equals the input except for the target
# assignments' cells on scored rows. Fixtures are invented.

# An export in Canvas's shape: quoted "Last, First", a Points Possible row with
# leading spaces, two-decimal scores, read-only totals, letter grades.
export_lines <- c(
  'Student,ID,SIS User ID,SIS Login ID,Root Account,Section,Module 2 Quiz: Data (201),Case Study 3: Engine Efficiency and MSRP (111),Case Study 4: New Technology (112),Current Score,Final Grade',
  '    Points Possible,,,,,,100.00,50.00,50.00,(read only),(read only)',
  '"Quill, Pat",1001,U1,XQ1001,x.edu,90-01,88.00,,,88.00,B',
  '"Rivera, Morgan",1002,U2,XQ1002,x.edu,90-01,91.00,40.00,,91.00,A',
  '"Stone, Pat",1003,U3,XQ1003,x.edu,90-01,,,,0.00,F',
  '"Student, Test",9999,,,x.edu,90-01,,,,,')

write_export <- function(path, eol = "\n") {
  writeBin(charToRaw(paste0(paste(export_lines, collapse = eol), eol)), path)
  path
}

# A course root with the export and two scored assignment folders.
grades_course <- function(env = parent.frame()) {
  td <- normalizePath(withr::local_tempdir("canvas_", .local_envir = env))
  gb <- write_export(file.path(td, "export.csv"))
  ad <- file.path(td, "CaseStudy03"); dir.create(ad)
  utils::write.csv(data.frame(student = c("x", "y"), canvas_user_id = c("1001", "1002"),
                              total = c("45", "38.5")),
                   file.path(ad, "case03_scores.csv"), row.names = FALSE)
  a4 <- file.path(td, "CaseStudy04"); dir.create(a4)
  utils::write.csv(data.frame(canvas_user_id = c("1003"), total = c("30")),
                   file.path(a4, "case04_scores.csv"), row.names = FALSE)
  list(proj = td, td = td, gb = gb, ad = ad, a4 = a4,
       out_default = file.path(td, "canvas_import.csv"))
}

# Several assignments go through a map, the way a course runs them.
write_map <- function(dir, folders, columns) {
  mp <- file.path(dir, "canvas_columns.csv")
  utils::write.csv(data.frame(folder = folders, column = columns), mp, row.names = FALSE)
  mp
}

tgt <- function(folder, column, scores = "") {
  data.frame(folder = folder, column = column, scores = scores, stringsAsFactors = FALSE)
}

one_expected <- function() {
  e <- export_lines
  e[3] <- '"Quill, Pat",1001,U1,XQ1001,x.edu,90-01,88.00,45.00,,88.00,B'
  e[4] <- '"Rivera, Morgan",1002,U2,XQ1002,x.edu,90-01,91.00,38.50,,91.00,A'
  e
}

test_that("one assignment: the export byte for byte except the target cells on scored rows", {
  g <- grades_course()
  out <- quiet(canvas_grades(g$proj, g$gb, folder = g$ad, column = "Case Study 3"))
  expect_identical(out, g$out_default)   # written next to the export
  expected <- one_expected()
  expect_identical(raw_text(out), paste0(paste(expected, collapse = "\n"), "\n"))
  unlink(out)

  gb_crlf <- write_export(file.path(g$td, "export_crlf.csv"), eol = "\r\n")
  out <- quiet(canvas_grades(g$proj, gb_crlf, folder = g$ad, column = "Case Study 3"))
  expect_identical(raw_text(out), paste0(paste(expected, collapse = "\r\n"), "\r\n"))
  unlink(out)

  bom <- file.path(g$td, "export_bom.csv")
  writeBin(c(as.raw(c(0xEF, 0xBB, 0xBF)), readBin(g$gb, "raw", file.info(g$gb)$size)), bom)
  out <- quiet(canvas_grades(g$proj, bom, folder = g$ad, column = "Case Study 3"))
  expect_identical(readBin(out, "raw", 3), as.raw(c(0xEF, 0xBB, 0xBF)))
  unlink(out)

  nofinal <- file.path(g$td, "export_nofinal.csv")
  writeBin(charToRaw(paste(export_lines, collapse = "\n")), nofinal)
  out <- quiet(canvas_grades(g$proj, nofinal, folder = g$ad, column = "Case Study 3"))
  expect_identical(substring(raw_text(out), nchar(raw_text(out))), ",")  # no final newline added
  unlink(out)

  expect_identical(raw_text(g$gb), paste0(paste(export_lines, collapse = "\n"), "\n"))
})

test_that("several assignments fill one file; overlaps, misses and overwrites stop", {
  g <- grades_course()
  mp <- write_map(g$td, c(g$ad, g$a4), c("Case Study 3", "Case Study 4"))
  out <- quiet(canvas_grades(g$proj, g$gb, map = mp))
  exp2 <- one_expected()
  exp2[5] <- '"Stone, Pat",1003,U3,XQ1003,x.edu,90-01,,,30.00,0.00,F'
  expect_identical(raw_text(out), paste0(paste(exp2, collapse = "\n"), "\n"))

  expect_true(grepl("already exists", errors_with(
    canvas_grades(g$proj, g$gb, folder = g$ad, column = "Case Study 3"))))
  unlink(out)

  mp2 <- write_map(g$td, c(g$ad, g$a4), c("Case Study 3", "Engine Efficiency"))
  expect_true(grepl("same column", errors_with(canvas_grades(g$proj, g$gb, map = mp2))))
  mp3 <- write_map(g$td, c(g$ad, g$a4), c("Case Study 3", "Quiz 9"))
  errors_with(canvas_grades(g$proj, g$gb, map = mp3))
  expect_false(file.exists(g$out_default))   # nothing written when any assignment fails

  expect_true(grepl("no gradebook column", errors_with(
    canvas_grades(g$proj, g$gb, folder = g$ad, column = "Quiz 9"))))
  expect_true(grepl("more than one", errors_with(
    canvas_grades(g$proj, g$gb, folder = g$ad, column = "Case Study"))))
  expect_true(grepl("no gradebook column", errors_with(
    canvas_grades(g$proj, g$gb, folder = g$ad, column = "Current Score"))))
})

test_that("bad scores stop without printing an id, and nothing is written", {
  g <- grades_course()
  bad <- file.path(g$td, "Bad"); dir.create(bad)
  utils::write.csv(data.frame(canvas_user_id = "4242", total = "10"),
                   file.path(bad, "bad_scores.csv"), row.names = FALSE)
  msg <- errors_with(canvas_grades(g$proj, g$gb, folder = bad, column = "Case Study 3"))
  expect_true(grepl("not in the gradebook", msg))
  expect_false(grepl("4242", msg))
  expect_false(file.exists(g$out_default))

  nn <- file.path(g$td, "NotNum"); dir.create(nn)
  utils::write.csv(data.frame(canvas_user_id = "1001", total = "ten"),
                   file.path(nn, "nn_scores.csv"), row.names = FALSE)
  expect_true(grepl("not a number", errors_with(
    canvas_grades(g$proj, g$gb, folder = nn, column = "Case Study 3"))))

  ml <- file.path(g$td, "export_multiline.csv")
  writeLines(c(export_lines[1:2], '"Quill,\nPat",1001,U1,XQ1001,x.edu,90-01,,,,,'), ml)
  expect_true(grepl("spans lines|unbalanced", errors_with(
    canvas_grades(g$proj, ml, folder = g$ad, column = "Case Study 3"))))
})

test_that("the map file reads its folders and defaults the scores column", {
  g <- grades_course()
  mp <- file.path(g$td, "canvas_columns.csv")
  writeLines(c("folder,column", paste0(g$ad, ",Case Study 3"), paste0(g$a4, ",Case Study 4")), mp)
  m <- read_map(mp)
  expect_identical(m$folder, c(g$ad, g$a4))
  expect_identical(m$scores, c("", ""))
})

test_that("coded scores map through the key into the right cell, and need the key", {
  g <- grades_course()
  kg <- file.path(g$td, "keygb.csv")
  writeLines(c('Student,ID,SIS User ID,SIS Login ID,Root Account,Section',
               '    Points Possible,,,,,',
               '"Quill, Pat",1001,U1,XQ1001,x,90',
               '"Rivera, Morgan",1002,U2,XQ1002,x,90',
               '"Stone, Pat",1003,U3,XQ1003,x,90'), kg)
  kp <- file.path(g$td, "anon_key.csv")
  quiet(build_key(kg, kp))
  cd <- file.path(g$td, "Coded"); dir.create(file.path(cd, "anon"), recursive = TRUE)
  utils::write.csv(data.frame(code = "S02", total = "41"), file.path(cd, "anon", "scores.csv"),
                   row.names = FALSE)
  out2 <- quiet(canvas_grades(g$proj, g$gb, folder = cd, column = "Case Study 4", key = kp))
  exp3 <- export_lines
  exp3[4] <- '"Rivera, Morgan",1002,U2,XQ1002,x.edu,90-01,91.00,40.00,41.00,91.00,A'
  expect_identical(raw_text(out2), paste0(paste(exp3, collapse = "\n"), "\n"))
  unlink(out2)
  expect_true(grepl("key", errors_with(
    canvas_grades(g$proj, g$gb, folder = cd, column = "Case Study 4"))))
})

test_that("canvas_grades() resolves paths against proj and refuses an ambiguous call", {
  g <- grades_course()
  mp <- write_map(g$td, c("CaseStudy03", "CaseStudy04"), c("Case Study 3", "Case Study 4"))
  out <- capture.output(res <- canvas_grades(g$proj, "export.csv", map = "canvas_columns.csv",
                                             out = "import.csv"))
  expect_identical(res, file.path(g$proj, "import.csv"))
  expect_true(any(grepl("coursepack", out)))
  expect_false(any(grepl("Quill|Rivera|Stone|100[123]", out)))
  expect_error(canvas_grades(g$proj, "export.csv", map = mp, folder = "CaseStudy03",
                             column = "Case Study 3"), "not both")
  expect_error(canvas_grades(g$proj, "export.csv", folder = "CaseStudy03"), "folder with column")
  # The internal filler takes a targets frame directly, the shape a map becomes.
  expect_identical(quiet(fill_gradebook(g$gb, tgt(g$ad, "Case Study 3"))), g$out_default)
})
