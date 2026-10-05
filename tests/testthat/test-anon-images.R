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
  expect_message(r <- apply_image_decisions(a, flagged, dec), "^1 row\\(s\\)")
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

test_that("a login or email seen only in an image is flagged, not erased", {
  skip_if_no("tesseract")
  a <- withr::local_tempdir(); m <- file.path(a, "S01", "file1_media"); dir.create(m, recursive = TRUE)
  make_png(file.path(m, "path.png"), "/Users/pquill/Documents/hw3.R")
  make_png(file.path(m, "mail.png"), "write to pquill@my.uwrf.edu")
  terms <- data.frame(term = "pquill", code = "S01", loose = TRUE, stringsAsFactors = FALSE)
  f <- scan_images(a, terms)
  expect_setequal(f$image, c("S01/file1_media/path.png", "S01/file1_media/mail.png"))
  f2 <- scan_images(a, data.frame(term = "zzzzz", code = "S01", loose = TRUE))
  expect_true(all(f2$reason == "pattern"))
  expect_equal(nrow(f2), 2L)
})

test_that("a corrupt image is flagged unscannable and the run continues", {
  skip_if_no("tesseract")
  a <- withr::local_tempdir(); m <- file.path(a, "S01", "file1_media"); dir.create(m, recursive = TRUE)
  writeBin(as.raw(1:10), file.path(m, "bad.png"))
  make_png(file.path(m, "ok.png"), "MSRP vs MPG")
  f <- scan_images(a, fake_terms())
  expect_equal(f$image, "S01/file1_media/bad.png"); expect_equal(f$reason, "unscannable")
  expect_equal(attr(f, "scanned"), 2L)
})

test_that("svg metadata is removed and svg text is checked", {
  a <- withr::local_tempdir(); m <- file.path(a, "S01", "file1_media"); dir.create(m, recursive = TRUE)
  writeLines(c("<svg xmlns=\"http://www.w3.org/2000/svg\" inkscape:version=\"1.0\">",
               "<metadata><dc:creator>Pat Quill</dc:creator></metadata>",
               "<text>MSRP</text></svg>"), file.path(m, "meta.svg"))
  writeLines("<svg><text>Pat Quill</text></svg>", file.path(m, "name.svg"))
  f <- scan_images(a, fake_terms())
  expect_false(grepl("Pat Quill|inkscape", paste(readLines(file.path(m, "meta.svg")), collapse = "")))
  expect_equal(f$image[f$reason == "name"], "S01/file1_media/name.svg")
  expect_equal(f$reason[f$image == "S01/file1_media/meta.svg"], "unscannable")
  expect_equal(attr(f, "stripped"), 2L)
})

test_that("any file inside a _media folder is gated, whatever its extension", {
  a <- withr::local_tempdir(); m <- file.path(a, "S01", "file1_media", "media"); dir.create(m, recursive = TRUE)
  file.create(file.path(m, "x.wdp")); file.create(file.path(a, "S01", "notes.wdp"))
  f <- scan_images(a, fake_terms())
  expect_equal(f$image, "S01/file1_media/media/x.wdp"); expect_equal(f$reason, "unscannable")
})

test_that("scan_images stops with the install hint when tesseract is missing", {
  local_mocked_bindings(tesseract_path = function() "")
  a <- withr::local_tempdir(); m <- file.path(a, "S01", "file1_media"); dir.create(m, recursive = TRUE)
  make_png(file.path(m, "a.png"), "MSRP vs MPG")
  expect_error(scan_images(a, fake_terms()), "brew install tesseract")
})

test_that("a remove row deletes an unflagged image and counts it; keep for one is a no-op", {
  a <- withr::local_tempdir(); m <- file.path(a, "S01", "file1_media"); dir.create(m, recursive = TRUE)
  file.create(file.path(m, c("face.png", "plot.png")))
  writeLines("Me: ![](file1_media/face.png) and ![](file1_media/plot.png)",
             file.path(a, "S01", "file1.md"))
  writeLines("x", file.path(a, "manifest.csv"))
  flagged <- data.frame(image = character(), code = character(), reason = character())
  dec <- data.frame(image = c("S01/file1_media/face.png", "S01/file1_media/plot.png",
                              "S02/gone.png", "manifest.csv", "../escape.png"),
                    decision = c("remove", "keep", "remove", "remove", "remove"))
  expect_message(r <- apply_image_decisions(a, flagged, dec), "^3 row\\(s\\) in anon_images.csv")
  expect_identical(c(r$removed, r$kept), c(1L, 0L))
  expect_false(file.exists(file.path(m, "face.png")))
  expect_true(file.exists(file.path(m, "plot.png")))
  expect_true(file.exists(file.path(a, "manifest.csv")))   # only gated images can be removed
  expect_identical(readLines(file.path(a, "S01", "file1.md")),
                   "Me: [image removed] and ![](file1_media/plot.png)")
})

test_that("conflicting decisions for one image stop; identical duplicates do not", {
  d <- withr::local_tempdir()
  writeLines(c("image,decision", "S01/file1_media/a.png,keep", "S01/file1_media/a.png,remove"),
             file.path(d, "anon_images.csv"))
  err <- errors_with(read_image_decisions(d))
  expect_true(grepl("conflicting decisions for S01/file1_media/a.png", err, fixed = TRUE))
  writeLines(c("image,decision", "S01/file1_media/a.png,remove", "S01/file1_media/a.png,REMOVE"),
             file.path(d, "anon_images.csv"))
  r <- read_image_decisions(d)
  expect_identical(r$image, "S01/file1_media/a.png"); expect_identical(r$decision, "remove")
})

test_that("anon_images.csv saved by Excel with a byte-order mark is read", {
  d <- withr::local_tempdir(); p <- file.path(d, "anon_images.csv")
  con <- file(p, "wb")
  writeBin(c(as.raw(c(0xEF, 0xBB, 0xBF)),
             charToRaw("image,decision\r\nS01/file1_media/a.png,keep\r\n")), con)
  close(con)
  r <- read_image_decisions(d)
  expect_identical(r$image, "S01/file1_media/a.png"); expect_identical(r$decision, "keep")
  writeLines(c("image,decision", "S01/file1_media/b.png,remove"), p)
  expect_identical(read_image_decisions(d)$image, "S01/file1_media/b.png")
})

test_that("a home-folder login in a non-rendering svg attribute is redacted on strip", {
  a <- withr::local_tempdir(); p <- file.path(a, "fig.svg")
  writeLines(c("<svg xmlns:xlink=\"http://www.w3.org/1999/xlink\">",
               "<image xlink:href=\"/Users/pquill/Desktop/plot.png\"/></svg>"), p)
  expect_true(strip_svg(p))
  txt <- paste(readLines(p), collapse = "\n")
  expect_false(grepl("pquill", txt, fixed = TRUE))
  expect_true(grepl("/Users/USER/Desktop/plot.png", txt, fixed = TRUE))
})

test_that("an image showing only a protected phrase is not flagged; a name beside it is", {
  skip_if_no("tesseract")
  a <- withr::local_tempdir(); dir.create(file.path(a, "S01", "file1_media"), recursive = TRUE)
  make_png(file.path(a, "S01", "file1_media", "title.png"), "Prof. Avery J. Thorn")
  make_png(file.path(a, "S01", "file1_media", "note.png"), "Thanks Avery")
  terms <- data.frame(term = "Avery", code = "S01", loose = FALSE, stringsAsFactors = FALSE)
  f <- scan_images(a, terms, keep = "Avery J. Thorn")
  expect_equal(f$image, "S01/file1_media/note.png")
  expect_equal(f$reason, "name")
  f0 <- scan_images(a, terms)
  expect_setequal(f0$image, c("S01/file1_media/title.png", "S01/file1_media/note.png"))
})
