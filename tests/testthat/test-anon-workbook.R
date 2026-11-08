test_that("fake_workbook builds a readable xlsx", {
  td <- withr::local_tempdir()
  p <- fake_workbook(td)
  expect_true(file.exists(p))
  expect_equal(tidyxl::xlsx_sheet_names(p),
               c("Summary", "Pat Quill data", "Hidden calc"))
  nm <- utils::unzip(p, list = TRUE)$Name
  expect_equal(nm[1], "[Content_Types].xml")
  expect_true("xl/charts/chart1.xml" %in% nm)
  expect_true("xl/charts/chart2.xml" %in% nm)
  expect_false("xl/vbaProject.bin" %in% nm)
})

test_that("fake_workbook(macro = TRUE) keeps the macro project", {
  td <- withr::local_tempdir()
  p <- fake_workbook(td, name = "quillpat_1001_5001_partb.xlsm", macro = TRUE)
  expect_true("xl/vbaProject.bin" %in% utils::unzip(p, list = TRUE)$Name)
  expect_no_error(tidyxl::xlsx_sheet_names(p))
})

test_that("fake_hcahps points at the source csv", {
  expect_true(file.exists(fake_hcahps()))
})

# Task 3: types, .xls refusal, skip_types.
touch_files <- function(a, names) {
  for (n in names) writeLines("x", file.path(a, n))
}

test_that("xls stops with re-save advice", {
  skip_if_no("tesseract")
  cc <- anon_course(); a <- a1_assignment(cc)
  mk_docx(file.path(a, "quillpat_1001_5002_a.docx"), "Hello")
  touch_files(a, "quillpat_1001_5001_b.xls")
  mk_docx(file.path(a, "riveramorgan_1002_5003_a.docx"), "Hello")
  msg <- errors_with(quiet(anonymize(cc$proj, "semester/A1", dict = NULL)))
  expect_match(msg, "S0[0-9] \\(file1\\).*re-save as .xlsx.*skip_types")
  expect_false(grepl("quill", msg, ignore.case = TRUE))
})

test_that("skip_types drops a type and counts it", {
  td <- withr::local_tempdir()
  touch_files(td, c("quillpat_1001_5001_a.docx", "quillpat_1001_5002_b.xls"))
  for (st in c("xls", ".XLS")) {
    s <- list_submissions(td, skip_types = st)
    expect_false(any(tolower(tools::file_ext(s$original)) == "xls"))
    expect_equal(nrow(s), 1)
    expect_equal(attr(s, "skipped")[["xls"]], 1L)
  }
  expect_length(attr(list_submissions(td), "skipped"), 0)
})

test_that("workbook-only student targets the workbook", {
  cc <- anon_course(); a <- a1_assignment(cc)
  touch_files(a, c("quillpat_1001_5001_a.xlsx", "riveramorgan_1002_5002_a.xlsx",
                   "riveramorgan_1002_5003_a.docx"))
  key <- read_key(file.path(a, "anon_key.csv"))
  s <- assign_files(list_submissions(a), key)
  q <- s[s$canvas_id == "1001", ]
  expect_true(q$target)
  r <- s[s$canvas_id == "1002", ]
  expect_equal(tools::file_ext(r$original[r$target]), "docx")
  expect_equal(sum(r$target), 1)
})

test_that("all files skipped still stops", {
  cc <- anon_course(); a <- a1_assignment(cc)
  touch_files(a, c("quillpat_1001_5001_a.xls", "riveramorgan_1002_5002_a.docx"))
  key <- read_key(file.path(a, "anon_key.csv"))
  msg <- errors_with(assign_files(list_submissions(a, "xls"), key))
  expect_match(msg, "no document")
  expect_false(grepl("quill", msg, ignore.case = TRUE))
})

test_that("a not-in-key student with only a skipped file still stops", {
  cc <- anon_course(); a <- a1_assignment(cc)
  touch_files(a, c("quillpat_1001_5001_a.docx", "stranger_7777_5002_a.xls"))
  key <- read_key(file.path(a, "anon_key.csv"))
  expect_match(errors_with(assign_files(list_submissions(a, "xls"), key)), "not in the key")
})

test_that("an empty skip_types entry drops nothing", {
  td <- withr::local_tempdir()
  touch_files(td, c("quillpat_1001_5001_a.docx", "quillpat_1001_5002_noext"))
  s <- list_submissions(td, skip_types = c("", "."))
  expect_equal(nrow(s), 2)
  expect_length(attr(s, "skipped"), 0)
})

test_that("convert_to_text refuses .xls with advice", {
  td <- withr::local_tempdir()
  p <- file.path(td, "old.xls"); writeLines("x", p)
  msg <- errors_with(convert_to_text(p, file.path(td, "o", "file1.md"), file.path(td, "o", "file1_media")))
  expect_match(msg, "re-save as .xlsx.*skip_types")
})
