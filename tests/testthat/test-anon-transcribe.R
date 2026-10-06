# A student whose only upload is an image: anonymize(transcribe_images = TRUE)
# has the local model transcribe it, and relink() answers with an image of the
# same name. Model calls are mocked: these tests never need LM Studio.

photo_course <- function(env = parent.frame()) {
  skip_if_no("tesseract")
  cc <- anon_course(env = env); a <- a1_assignment(cc)
  img <- magick::image_annotate(magick::image_blank(400, 120, "white"), "my reflection",
                                size = 30, location = "+10+30", color = "black")
  magick::image_write(img, file.path(a, "quillpat_1001_5001_reflection.jpg"), format = "jpeg")
  list(cc = cc, a = a, an = file.path(a, "anon"))
}
transcriber_up <- function(text = "Reflection by Pat Quill\nThe multiplier is 2.", env = parent.frame()) {
  local_mocked_bindings(review_models = function(url) "gemma-4-31b-it-mlx",
                        transcribe_call = function(body, url) list(content = text),
                        .env = env)
}

test_that("an image-only student stops without transcribe_images, naming the option", {
  s <- photo_course()
  e <- errors_with(quiet(anonymize(s$cc$proj, "semester/A1", dict = NULL)))
  expect_match(e, "transcribe_images = TRUE", fixed = TRUE)
  expect_false(grepl("quill|1001", e, ignore.case = TRUE))
  expect_false(dir.exists(s$an))
})

test_that("the transcription becomes the coded document, redacted, and the photo stays out of anon/", {
  s <- photo_course(); transcriber_up()
  out <- capture.output(res <- anonymize(s$cc$proj, "semester/A1", dict = NULL,
                                         transcribe_images = TRUE))
  expect_identical(res$images$scanned, 0L)          # the photo was never swept
  md <- readLines(file.path(s$an, "S01", "file1.md"))
  expect_true(any(grepl("The multiplier is 2.", md, fixed = TRUE)))
  expect_false(any(grepl("Quill", md)))
  expect_true(any(grepl("[name]", md, fixed = TRUE)))
  expect_true(any(grepl("Transcribed from an image", md, fixed = TRUE)))
  # Only the transcript goes into anon/: no photo, no media folder, no image link.
  expect_false(dir.exists(file.path(s$an, "S01", "file1_media")))
  expect_equal(length(list.files(s$an, "\\.(png|jpe?g)$", recursive = TRUE, ignore.case = TRUE)), 0L)
  expect_false(any(grepl("![](", md, fixed = TRUE)))
  expect_identical(res$transcribed, "S01")
  expect_true(any(grepl("TRANSCRIBED from images.*S01", out)))
  log <- readLines(file.path(s$a, "deidentification_log.md"))
  expect_true(any(grepl("transcribed from images by the local model.*: S01", log)))
  expect_false(any(grepl("Quill|1001|5001|reflection", log, ignore.case = TRUE)))
  man <- utils::read.csv(file.path(s$an, "manifest.csv"), colClasses = "character")
  expect_identical(man$target, "TRUE")
  expect_identical(man$ext, "jpg")
})

test_that("a transcription failure stops naming the code only, and no anon/ is released", {
  s <- photo_course()
  local_mocked_bindings(review_models = function(url) "gemma-4-31b-it-mlx",
                        transcribe_call = function(body, url) list(fail = "HTTP 500"))
  e <- errors_with(quiet(anonymize(s$cc$proj, "semester/A1", dict = NULL, transcribe_images = TRUE)))
  expect_match(e, "transcription failed for S01", fixed = TRUE)
  expect_false(dir.exists(s$an))
})

test_that("relink() answers an image submission with an image of the same name", {
  skip_if_no("pandoc"); skip_if_no("xelatex"); skip_if_no("pdftoppm"); skip_if_no("zip")
  s <- photo_course(); transcriber_up()
  quiet(anonymize(s$cc$proj, "semester/A1", dict = NULL, transcribe_images = TRUE))
  dir.create(file.path(s$an, "feedback"))
  writeLines(c("# Feedback: S01", "", "Good reflection, S01."), file.path(s$an, "feedback", "S01.md"))
  utils::write.csv(data.frame(code = "S01", total = "9"), file.path(s$an, "scores.csv"), row.names = FALSE)
  quiet(relink(s$cc$proj, "semester/A1", dict = NULL))
  fb <- file.path(s$a, "feedback", "quillpat_1001_5001_reflection.jpg")
  expect_true(file.exists(fb))
  expect_identical(magick::image_info(magick::image_read(fb))$format, "JPEG")
})
