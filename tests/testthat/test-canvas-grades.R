# canvas_grades() fills scores into a narrow Canvas gradebook import. Canvas
# writes back every cell an import carries, reads a blank cell as a deletion,
# and leaves alone any assignment column that is absent, so the import keeps
# the identity columns and the mapped assignment columns only. Every kept cell
# is the export's own bytes except the filled target cells on scored rows.
# Exports are read; imports are written to import_dir and nowhere else.
# Fixtures are invented.

# An export in Canvas's shape: quoted "Last, First", a quoted header carrying a
# comma, a Points Possible row with leading spaces, two-decimal scores,
# read-only totals, letter grades, and the Test Student row.
export_lines <- c(
  'Student,ID,SIS User ID,SIS Login ID,Root Account,Section,"Module 2 Quiz: Data, Part 1 (201)",Case Study 3: Engine Efficiency and MSRP (111),Case Study 4: New Technology (112),Current Score,Final Grade',
  '    Points Possible,,,,,,100.00,50.00,50.00,(read only),(read only)',
  '"Quill, Pat",1001,U1,XQ1001,x.edu,90-01,88.00,,,88.00,B',
  '"Rivera, Morgan",1002,U2,XQ1002,x.edu,90-01,91.00,40.00,,91.00,A',
  '"Stone, Pat",1003,U3,XQ1003,x.edu,90-01,,,,0.00,F',
  '"Student, Test",9999,,,x.edu,90-01,,,,,')

write_export <- function(path, eol = "\n") {
  writeBin(charToRaw(paste0(paste(export_lines, collapse = eol), eol)), path)
  path
}

# A course root with the export in gradebook_export/ and two scored
# assignment folders. With a term, all of it sits under semester/<term>/ in
# proj, g$td is that term folder, and the default import_dir is its sibling
# semester/<term>/gradebook_import. Without one it sits directly in proj, which
# has no term, so every call passes import_dir or out; g$imp is then only a
# folder for fill_gradebook() called directly.
grades_course <- function(term = NULL, env = parent.frame()) {
  proj <- normalizePath(withr::local_tempdir("canvas_", .local_envir = env))
  td <- if (is.null(term)) proj else file.path(proj, "semester", term)
  dir.create(file.path(td, "gradebook_export"), recursive = TRUE)
  gb <- write_export(file.path(td, "gradebook_export", "export.csv"))
  ad <- file.path(td, "CaseStudy03"); dir.create(ad)
  utils::write.csv(data.frame(student = c("x", "y"), canvas_user_id = c("1001", "1002"),
                              total = c("45", "38.5")),
                   file.path(ad, "case03_scores.csv"), row.names = FALSE)
  a4 <- file.path(td, "CaseStudy04"); dir.create(a4)
  utils::write.csv(data.frame(canvas_user_id = c("1003"), total = c("30")),
                   file.path(a4, "case04_scores.csv"), row.names = FALSE)
  imp <- if (is.null(term)) file.path(proj, "semester", "gradebook_import") else
    file.path(td, "gradebook_import")
  today <- format(Sys.Date(), "%Y-%m-%d")
  list(proj = proj, td = td, gb = gb, ad = ad, a4 = a4, imp = imp,
       out_one = file.path(imp, paste0(today, "_CaseStudy03_import.csv")),
       out_two = file.path(imp, paste0(today, "_2-assignments_import.csv")))
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

# The narrow import for Case Study 3 alone: identity columns and the one
# mapped column, every row kept, Rivera's 40.00 replaced and Stone untouched.
one_expected <- c(
  'Student,ID,SIS User ID,SIS Login ID,Root Account,Section,Case Study 3: Engine Efficiency and MSRP (111)',
  '    Points Possible,,,,,,50.00',
  '"Quill, Pat",1001,U1,XQ1001,x.edu,90-01,45.00',
  '"Rivera, Morgan",1002,U2,XQ1002,x.edu,90-01,38.50',
  '"Stone, Pat",1003,U3,XQ1003,x.edu,90-01,',
  '"Student, Test",9999,,,x.edu,90-01,')

two_expected <- c(
  'Student,ID,SIS User ID,SIS Login ID,Root Account,Section,Case Study 3: Engine Efficiency and MSRP (111),Case Study 4: New Technology (112)',
  '    Points Possible,,,,,,50.00,50.00',
  '"Quill, Pat",1001,U1,XQ1001,x.edu,90-01,45.00,',
  '"Rivera, Morgan",1002,U2,XQ1002,x.edu,90-01,38.50,',
  '"Stone, Pat",1003,U3,XQ1003,x.edu,90-01,,30.00',
  '"Student, Test",9999,,,x.edu,90-01,,')

test_that("one assignment: identity columns and the mapped column only, every row kept", {
  g <- grades_course("fall2026")
  out <- quiet(canvas_grades(g$proj, g$gb, folder = g$ad, column = "Case Study 3"))
  expect_identical(out, g$out_one)   # dated, named for the folder, under import_dir
  expect_identical(raw_text(out), paste0(paste(one_expected, collapse = "\n"), "\n"))

  gb_crlf <- write_export(file.path(g$td, "gradebook_export", "export_crlf.csv"), eol = "\r\n")
  out <- quiet(canvas_grades(g$proj, gb_crlf, folder = g$ad, column = "Case Study 3",
                             overwrite = TRUE))
  expect_identical(raw_text(out), paste0(paste(one_expected, collapse = "\r\n"), "\r\n"))

  bom <- file.path(g$td, "gradebook_export", "export_bom.csv")
  writeBin(c(as.raw(c(0xEF, 0xBB, 0xBF)), readBin(g$gb, "raw", file.info(g$gb)$size)), bom)
  out <- quiet(canvas_grades(g$proj, bom, folder = g$ad, column = "Case Study 3",
                             overwrite = TRUE))
  expect_identical(readBin(out, "raw", 3), as.raw(c(0xEF, 0xBB, 0xBF)))
  b <- readBin(out, "raw", file.info(out)$size)
  expect_identical(rawToChar(b[-(1:3)]), paste0(paste(one_expected, collapse = "\n"), "\n"))

  nofinal <- file.path(g$td, "gradebook_export", "export_nofinal.csv")
  writeBin(charToRaw(paste(export_lines, collapse = "\n")), nofinal)
  out <- quiet(canvas_grades(g$proj, nofinal, folder = g$ad, column = "Case Study 3",
                             overwrite = TRUE))
  expect_identical(raw_text(out), paste(one_expected, collapse = "\n"))  # no final newline added

  expect_identical(raw_text(g$gb), paste0(paste(export_lines, collapse = "\n"), "\n"))
})

test_that("the export's folder gains nothing; imports go only to import_dir", {
  g <- grades_course("fall2026")
  before <- sort(list.files(file.path(g$td, "gradebook_export"), all.files = TRUE, no.. = TRUE))
  out <- quiet(canvas_grades(g$proj, g$gb, folder = g$ad, column = "Case Study 3"))
  expect_identical(sort(list.files(file.path(g$td, "gradebook_export"), all.files = TRUE,
                                   no.. = TRUE)), before)
  expect_identical(list.files(g$imp), basename(g$out_one))

  out2 <- quiet(canvas_grades(g$proj, g$gb, folder = g$ad, column = "Case Study 3",
                              import_dir = "elsewhere/imports"))
  expect_identical(out2, file.path(g$proj, "elsewhere", "imports", basename(g$out_one)))
  expect_true(file.exists(out2))
  expect_identical(sort(list.files(file.path(g$td, "gradebook_export"), all.files = TRUE,
                                   no.. = TRUE)), before)
})

test_that("several assignments fill one narrow file; overlaps, misses and overwrites stop", {
  g <- grades_course("fall2026")
  mp <- write_map(g$td, c(g$ad, g$a4), c("Case Study 3", "Case Study 4"))
  out <- quiet(canvas_grades(g$proj, g$gb, map = mp))
  expect_identical(out, g$out_two)
  expect_identical(raw_text(out), paste0(paste(two_expected, collapse = "\n"), "\n"))

  msg <- errors_with(canvas_grades(g$proj, g$gb, map = mp))
  expect_true(grepl("already exists", msg) && grepl("overwrite = TRUE", msg, fixed = TRUE))
  expect_identical(raw_text(out), paste0(paste(two_expected, collapse = "\n"), "\n"))
  writeLines("stale", out)
  out <- quiet(canvas_grades(g$proj, g$gb, map = mp, overwrite = TRUE))
  expect_identical(raw_text(out), paste0(paste(two_expected, collapse = "\n"), "\n"))
  unlink(out)

  mp2 <- write_map(g$td, c(g$ad, g$a4), c("Case Study 3", "Engine Efficiency"))
  expect_true(grepl("same column", errors_with(canvas_grades(g$proj, g$gb, map = mp2))))
  mp3 <- write_map(g$td, c(g$ad, g$a4), c("Case Study 3", "Quiz 9"))
  errors_with(canvas_grades(g$proj, g$gb, map = mp3))
  expect_false(file.exists(g$out_two))   # nothing written when any assignment fails

  expect_true(grepl("no gradebook column", errors_with(
    canvas_grades(g$proj, g$gb, folder = g$ad, column = "Quiz 9"))))
  expect_true(grepl("more than one", errors_with(
    canvas_grades(g$proj, g$gb, folder = g$ad, column = "Case Study"))))
  expect_true(grepl("no gradebook column", errors_with(
    canvas_grades(g$proj, g$gb, folder = g$ad, column = "Current Score"))))
})

test_that("a mapped folder that does not exist stops, naming the folder path", {
  g <- grades_course("fall2026")
  msg <- errors_with(canvas_grades(g$proj, g$gb, folder = "semester/fall2026/CaseStudy09",
                                   column = "Case Study 3"))
  expect_identical(msg, paste0("no assignment folder at ", file.path(g$td, "CaseStudy09")))
  expect_false(dir.exists(g$imp))
})

test_that("bad scores stop without printing an id, and nothing is written", {
  g <- grades_course("fall2026")
  bad <- file.path(g$td, "Bad"); dir.create(bad)
  utils::write.csv(data.frame(canvas_user_id = "4242", total = "10"),
                   file.path(bad, "bad_scores.csv"), row.names = FALSE)
  msg <- errors_with(canvas_grades(g$proj, g$gb, folder = bad, column = "Case Study 3"))
  expect_true(grepl("not in the gradebook", msg))
  expect_false(grepl("4242", msg))
  expect_false(dir.exists(g$imp))

  nn <- file.path(g$td, "NotNum"); dir.create(nn)
  utils::write.csv(data.frame(canvas_user_id = "1001", total = "ten"),
                   file.path(nn, "nn_scores.csv"), row.names = FALSE)
  expect_true(grepl("not a number", errors_with(
    canvas_grades(g$proj, g$gb, folder = nn, column = "Case Study 3"))))

  ml <- file.path(g$td, "gradebook_export", "export_multiline.csv")
  writeLines(c(export_lines[1:2], '"Quill,\nPat",1001,U1,XQ1001,x.edu,90-01,,,,,'), ml)
  expect_true(grepl("spans lines|unbalanced", errors_with(
    canvas_grades(g$proj, ml, folder = g$ad, column = "Case Study 3"))))

  short <- file.path(g$td, "gradebook_export", "export_short.csv")
  writeLines(c(export_lines[1:2], '"Stone, Pat",1003,U3'), short)
  expect_true(grepl("wrong number of fields", errors_with(
    canvas_grades(g$proj, short, folder = g$ad, column = "Case Study 3"))))
  expect_false(dir.exists(g$imp))
})

test_that("the map file reads its folders and defaults the scores column", {
  g <- grades_course()
  mp <- file.path(g$td, "canvas_columns.csv")
  writeLines(c("folder,column", paste0(g$ad, ",Case Study 3"), paste0(g$a4, ",Case Study 4")), mp)
  m <- read_map(mp)
  expect_identical(m$folder, c(g$ad, g$a4))
  expect_identical(m$scores, c("", ""))
})

test_that("coded scores are placed through the folder's own key, and only a matching key", {
  g <- grades_course("fall2026")
  kg <- file.path(g$td, "keygb.csv")
  writeLines(c('Student,ID,SIS User ID,SIS Login ID,Root Account,Section',
               '    Points Possible,,,,,',
               '"Quill, Pat",1001,U1,XQ1001,x,90',
               '"Rivera, Morgan",1002,U2,XQ1002,x,90',
               '"Stone, Pat",1003,U3,XQ1003,x,90'), kg)
  cd <- file.path(g$td, "Coded"); dir.create(file.path(cd, "anon"), recursive = TRUE)
  k <- quiet(anon_key(g$proj, "semester/fall2026/keygb.csv", "semester/fall2026/Coded"))
  rivera <- k$code[k$canvas_id == "1002"]   # the code is shuffled; read it from the key
  utils::write.csv(data.frame(code = rivera, total = "41"), file.path(cd, "anon", "scores.csv"),
                   row.names = FALSE)
  out <- quiet(canvas_grades(g$proj, g$gb, folder = cd, column = "Case Study 4"))
  exp3 <- c(
    'Student,ID,SIS User ID,SIS Login ID,Root Account,Section,Case Study 4: New Technology (112)',
    '    Points Possible,,,,,,50.00',
    '"Quill, Pat",1001,U1,XQ1001,x.edu,90-01,',
    '"Rivera, Morgan",1002,U2,XQ1002,x.edu,90-01,41.00',
    '"Stone, Pat",1003,U3,XQ1003,x.edu,90-01,',
    '"Student, Test",9999,,,x.edu,90-01,')
  expect_identical(raw_text(out), paste0(paste(exp3, collapse = "\n"), "\n"))

  # An explicit key is accepted only when it is this folder's run.
  out <- quiet(canvas_grades(g$proj, g$gb, folder = cd, column = "Case Study 4",
                             key = "semester/fall2026/Coded/anon_key.csv", overwrite = TRUE))
  expect_identical(raw_text(out), paste0(paste(exp3, collapse = "\n"), "\n"))
  other <- file.path(g$td, "Other"); dir.create(other)
  quiet(anon_key(g$proj, "semester/fall2026/keygb.csv", "semester/fall2026/Other"))
  msg <- errors_with(canvas_grades(g$proj, g$gb, folder = cd, column = "Case Study 4",
                                   key = "semester/fall2026/Other/anon_key.csv", overwrite = TRUE))
  expect_true(grepl("Other", msg) && grepl("Coded", msg))

  unlink(file.path(cd, "anon_key.csv"))
  expect_true(grepl("key", errors_with(
    canvas_grades(g$proj, g$gb, folder = cd, column = "Case Study 4", overwrite = TRUE))))
})

test_that("canvas_grades() resolves paths against proj and refuses an ambiguous call", {
  g <- grades_course()
  mp <- write_map(g$td, c("CaseStudy03", "CaseStudy04"), c("Case Study 3", "Case Study 4"))
  out <- capture.output(res <- canvas_grades(g$proj, "gradebook_export/export.csv",
                                             map = "canvas_columns.csv", out = "import.csv"))
  expect_identical(res, file.path(g$proj, "import.csv"))
  expect_true(any(grepl("coursepack", out)))
  expect_false(any(grepl("Quill|Rivera|Stone|100[123]", out)))
  expect_error(canvas_grades(g$proj, "export.csv", map = mp, folder = "CaseStudy03",
                             column = "Case Study 3"), "not both")
  expect_error(canvas_grades(g$proj, "export.csv", folder = "CaseStudy03"), "folder with column")
  # The internal filler takes a targets frame directly, the shape a map becomes.
  expect_identical(quiet(fill_gradebook(g$gb, tgt(g$ad, "Case Study 3"), g$proj,
                                        import_dir = g$imp)),
                   g$out_one)
})

# ---- review fixes (1.2.2) ----------------------------------------------------------

test_that("a scores row with a blank id and a total stops", {
  g <- grades_course("fall2026")
  bl <- file.path(g$td, "BlankId"); dir.create(bl)
  utils::write.csv(data.frame(canvas_user_id = c("1001", ""), total = c("45", "10")),
                   file.path(bl, "bl_scores.csv"), row.names = FALSE)
  msg <- errors_with(canvas_grades(g$proj, g$gb, folder = bl, column = "Case Study 3"))
  expect_true(grepl("blank", msg))
  expect_false(dir.exists(g$imp))
})

test_that("rows without a numeric ID are never filled, whatever the scores say", {
  g <- grades_course("fall2026")
  mp_lines <- append(export_lines,
                     '    Manual Posting,,,,,,,Manual Posting,,,', after = 2)
  gb <- file.path(g$td, "gradebook_export", "export_mp.csv")
  writeLines(mp_lines, gb)
  out <- local({
    local_mocked_bindings(read_scores = function(...) {
      data.frame(canvas_id = c("1001", ""), total = c(45, 1), stringsAsFactors = FALSE)
    })
    quiet(canvas_grades(g$proj, gb, folder = g$ad, column = "Case Study 3"))
  })
  got <- readLines(out)
  expect_identical(got[2], '    Points Possible,,,,,,50.00')
  expect_identical(got[3], '    Manual Posting,,,,,,Manual Posting')
  expect_identical(got[4], '"Quill, Pat",1001,U1,XQ1001,x.edu,90-01,45.00')
})

test_that("an import is never written into the export's folder or over the export", {
  g <- grades_course()
  before <- raw_text(g$gb)
  msg <- errors_with(canvas_grades(g$proj, g$gb, folder = g$ad, column = "Case Study 3",
                                   import_dir = "gradebook_export"))
  expect_true(grepl("different folders", msg))
  msg <- errors_with(canvas_grades(g$proj, g$gb, folder = g$ad, column = "Case Study 3",
                                   out = "gradebook_export/export.csv", overwrite = TRUE))
  expect_true(grepl("different folders", msg))
  msg <- errors_with(canvas_grades(g$proj, g$gb, folder = g$ad, column = "Case Study 3",
                                   out = "gradebook_export/other.csv"))
  expect_true(grepl("different folders", msg))
  expect_identical(raw_text(g$gb), before)
  expect_identical(list.files(file.path(g$td, "gradebook_export")), "export.csv")
})

test_that("an Integration ID column is kept as an identity column", {
  g <- grades_course("fall2026")
  il <- sub("SIS Login ID,", "SIS Login ID,Integration ID,", export_lines[1], fixed = TRUE)
  il <- c(il, sub("^(([^,]*,){3})", "\\1,", export_lines[2]),
          sub("XQ1001,", "XQ1001,INT1,", export_lines[3], fixed = TRUE),
          sub("XQ1002,", "XQ1002,INT2,", export_lines[4], fixed = TRUE))
  gb <- file.path(g$td, "gradebook_export", "export_int.csv")
  writeLines(il, gb)
  out <- quiet(canvas_grades(g$proj, gb, folder = g$ad, column = "Case Study 3",
                             overwrite = TRUE))
  got <- readLines(out)
  expect_identical(got[1], paste0('Student,ID,SIS User ID,SIS Login ID,Integration ID,',
                                  'Root Account,Section,Case Study 3: Engine Efficiency and MSRP (111)'))
  expect_identical(got[3], '"Quill, Pat",1001,U1,XQ1001,INT1,x.edu,90-01,45.00')
})

test_that("an import is never written anywhere inside the export's folder tree", {
  g <- grades_course()
  ex <- file.path(g$td, "gradebook_export")
  msg <- errors_with(canvas_grades(g$proj, g$gb, folder = g$ad, column = "Case Study 3",
                                   import_dir = "gradebook_export/nested/deeper"))
  expect_true(grepl("different folders", msg))
  msg <- errors_with(canvas_grades(g$proj, g$gb, folder = g$ad, column = "Case Study 3",
                                   out = "gradebook_export/sub/x.csv"))
  expect_true(grepl("different folders", msg))
  expect_identical(list.files(ex, recursive = TRUE, include.dirs = TRUE, all.files = TRUE),
                   "export.csv")
  # A sibling whose name only starts like the export folder is not inside it.
  out <- quiet(canvas_grades(g$proj, g$gb, folder = g$ad, column = "Case Study 3",
                             import_dir = "gradebook_export_imports"))
  expect_true(file.exists(out))
})

# ---- the term-aware default (1.2.3) -------------------------------------------------
# Only the term is taken from the input paths, never a folder to write in: the
# default import_dir is semester/<term>/gradebook_import under proj.

test_that("the derived default is the sibling semester/<term>/gradebook_import", {
  g <- grades_course("fall2026")
  ex <- file.path(g$td, "gradebook_export")
  before <- list.files(ex, recursive = TRUE, include.dirs = TRUE, all.files = TRUE)
  out <- quiet(canvas_grades(g$proj, "semester/fall2026/gradebook_export/export.csv",
                             folder = "semester/fall2026/CaseStudy03", column = "Case Study 3"))
  expect_identical(out, file.path(g$proj, "semester", "fall2026", "gradebook_import",
                                  basename(g$out_one)))
  expect_identical(list.files(ex, recursive = TRUE, include.dirs = TRUE, all.files = TRUE),
                   before)
  expect_false(dir.exists(file.path(g$proj, "semester", "gradebook_import")))

  mp <- write_map(g$td, c("semester/fall2026/CaseStudy03", "semester/fall2026/CaseStudy04"),
                  c("Case Study 3", "Case Study 4"))
  out <- quiet(canvas_grades(g$proj, g$gb, map = mp))
  expect_identical(out, g$out_two)
  expect_identical(list.files(ex, recursive = TRUE, include.dirs = TRUE, all.files = TRUE),
                   before)
})

test_that("an export directly in semester/<term>/ takes that term; the guard still holds", {
  p <- normalizePath(withr::local_tempdir("canvas_"))
  td <- file.path(p, "semester", "fall-2026"); dir.create(td, recursive = TRUE)
  gb <- write_export(file.path(td, "export.csv"))
  ad <- file.path(td, "CaseStudy03"); dir.create(ad)
  utils::write.csv(data.frame(canvas_user_id = "1001", total = "45"),
                   file.path(ad, "case03_scores.csv"), row.names = FALSE)
  # The derived folder, semester/fall-2026/gradebook_import, is below the
  # export's own folder, so the guard stops it and nothing is created.
  msg <- errors_with(canvas_grades(p, "semester/fall-2026/export.csv",
                                   folder = "semester/fall-2026/CaseStudy03",
                                   column = "Case Study 3"))
  expect_true(grepl("different folders", msg))
  expect_true(grepl(file.path("semester", "fall-2026", "gradebook_import"), msg, fixed = TRUE))
  expect_false(dir.exists(file.path(td, "gradebook_import")))
  expect_identical(sort(list.files(td)), c("CaseStudy03", "export.csv"))
})

test_that("an export outside semester/<term>/ stops when the import_dir is derived", {
  g <- grades_course()
  msg <- errors_with(canvas_grades(g$proj, g$gb, folder = g$ad, column = "Case Study 3"))
  expect_true(grepl("term", msg))
  expect_true(grepl("gradebook_export/export.csv", msg, fixed = TRUE))
  expect_true(grepl("(none)", msg, fixed = TRUE))
  expect_false(grepl("Quill|Rivera|Stone|100[123]", msg))
  expect_false(dir.exists(file.path(g$proj, "semester")))

  # semester/ with no term folder below it is not a term either.
  dir.create(file.path(g$proj, "semester"))
  file.copy(g$gb, file.path(g$proj, "semester", "export.csv"))
  msg <- errors_with(canvas_grades(g$proj, "semester/export.csv", folder = g$ad,
                                   column = "Case Study 3"))
  expect_true(grepl("term", msg) && grepl("(none)", msg, fixed = TRUE))
  expect_identical(list.files(file.path(g$proj, "semester")), "export.csv")
})

test_that("an export and an assignment folder in different terms stop", {
  g <- grades_course("fall2026")
  sp <- file.path(g$proj, "semester", "spring2027", "CaseStudy03")
  dir.create(sp, recursive = TRUE)
  file.copy(file.path(g$ad, "case03_scores.csv"), sp)
  msg <- errors_with(canvas_grades(g$proj, g$gb, folder = "semester/spring2027/CaseStudy03",
                                   column = "Case Study 3"))
  expect_true(grepl("fall2026", msg) && grepl("spring2027", msg))
  expect_true(grepl("semester/spring2027/CaseStudy03", msg, fixed = TRUE))
  expect_false(dir.exists(g$imp))
  expect_false(dir.exists(file.path(g$proj, "semester", "spring2027", "gradebook_import")))

  # Through a map, one folder in another term is enough to stop it.
  mp <- write_map(g$td, c(g$ad, sp), c("Case Study 3", "Case Study 4"))
  msg <- errors_with(canvas_grades(g$proj, g$gb, map = mp))
  expect_true(grepl("spring2027", msg))
  # And an assignment folder outside semester/<term>/ has no term to agree.
  out_folder <- file.path(g$proj, "Loose"); dir.create(out_folder)
  msg <- errors_with(canvas_grades(g$proj, g$gb, folder = "Loose", column = "Case Study 3"))
  expect_true(grepl("Loose", msg) && grepl("(none)", msg, fixed = TRUE))
  expect_false(dir.exists(g$imp))
})

test_that("an explicit import_dir or out wins over the derived default", {
  g <- grades_course("fall2026")
  out <- quiet(canvas_grades(g$proj, g$gb, folder = g$ad, column = "Case Study 3",
                             import_dir = "elsewhere"))
  expect_identical(out, file.path(g$proj, "elsewhere", basename(g$out_one)))
  out <- quiet(canvas_grades(g$proj, g$gb, folder = g$ad, column = "Case Study 3",
                             out = "picked/here.csv"))
  expect_identical(out, file.path(g$proj, "picked", "here.csv"))
  expect_false(dir.exists(g$imp))
  # Nothing is derived when import_dir is given, so a folder in another term
  # does not stop it.
  sp <- file.path(g$proj, "semester", "spring2027", "CaseStudy03")
  dir.create(sp, recursive = TRUE)
  file.copy(file.path(g$ad, "case03_scores.csv"), sp)
  out <- quiet(canvas_grades(g$proj, g$gb, folder = sp, column = "Case Study 3",
                             import_dir = "elsewhere", overwrite = TRUE))
  expect_true(file.exists(out))
  # And the guard still applies to an explicit choice.
  msg <- errors_with(canvas_grades(g$proj, g$gb, folder = g$ad, column = "Case Study 3",
                                   import_dir = "semester/fall2026/gradebook_export/in"))
  expect_true(grepl("different folders", msg))
  expect_false(dir.exists(g$imp))
})
