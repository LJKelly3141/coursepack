make_png <- function(path, label) {
  img <- magick::image_blank(600, 120, "white")
  img <- magick::image_annotate(img, label, size = 40, location = "+10+30", color = "black")
  magick::image_write(img, path, format = "png", comment = "author Pat Quill")
}
fake_terms <- function() data.frame(term = c("Pat Quill", "Quill"), code = "S01",
                                    loose = c(TRUE, FALSE), stringsAsFactors = FALSE)

test_that("metadata is stripped from extracted images", {
  d <- withr::local_tempdir(); p <- file.path(d, "a.png"); make_png(p, "y = 3x")
  expect_true(strip_image_metadata(p))
  expect_identical(magick::image_comment(magick::image_read(p)), "")
})

test_that("an image showing a name is flagged; a plot label is not", {
  skip_if_no("tesseract")
  a <- withr::local_tempdir(); dir.create(file.path(a, "S01", "file1_media"), recursive = TRUE)
  make_png(file.path(a, "S01", "file1_media", "name.png"), "Written by Pat Quill")
  make_png(file.path(a, "S01", "file1_media", "plot.png"), "MSRP vs MPG")
  f <- scan_images(a, fake_terms())
  expect_equal(f$image, "S01/file1_media/name.png")
  expect_equal(f$code, "S01"); expect_equal(f$reason, "name")
  expect_equal(attr(f, "scanned"), 2L)
})

test_that("an unscannable image is flagged for a decision", {
  skip_if_no("tesseract")
  a <- withr::local_tempdir(); dir.create(file.path(a, "S02", "file1_media"), recursive = TRUE)
  writeBin(as.raw(1:10), file.path(a, "S02", "file1_media", "chart.emf"))
  f <- scan_images(a, fake_terms())
  expect_equal(f$reason, "unscannable")
})

test_that("decisions remove an image and its link, keep another, and ignore stale rows", {
  a <- withr::local_tempdir(); m <- file.path(a, "S01", "file1_media"); dir.create(m, recursive = TRUE)
  file.create(file.path(m, c("x.png", "y.png")))
  writeLines(c("See ![](file1_media/x.png){width=\"3in\"} here.",
               "And ![plot](file1_media/y.png)."), file.path(a, "S01", "file1.md"))
  flagged <- data.frame(image = c("S01/file1_media/x.png", "S01/file1_media/y.png"),
                        code = "S01", reason = "name")
  dec <- data.frame(image = c("S01/file1_media/x.png", "S01/file1_media/y.png", "S09/gone.png"),
                    decision = c("remove", "keep", "remove"))
  r <- apply_image_decisions(a, flagged, dec)
  expect_equal(c(r$removed, r$kept), c(1L, 1L)); expect_equal(nrow(r$undecided), 0L)
  expect_false(file.exists(file.path(m, "x.png")))
  md <- readLines(file.path(a, "S01", "file1.md"))
  expect_equal(md[1], "See [image removed] here.")
  expect_equal(md[2], "And ![plot](file1_media/y.png).")
})

test_that("ocr_image stops with an install hint when tesseract is missing", {
  local_mocked_bindings(tesseract_path = function() "")
  expect_error(ocr_image("x.png"), "brew install tesseract")
})
