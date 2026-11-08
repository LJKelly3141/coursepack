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
