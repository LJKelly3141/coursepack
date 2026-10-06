# One submission file to one plain-text file plus its images.
# Converting to text is what removes document metadata: pandoc without -s
# emits no title block, and pdftotext emits page text only.

TEXT_EXTS <- c("md", "qmd", "rmd", "r", "txt")

# Feedback can be written back as each of these, so only these can be a
# target. A script (.R) is read for grading but never answered in its own type.
FEEDBACK_TEXT_EXTS <- c("md", "qmd", "rmd", "txt")
DOCUMENT_EXTS <- c("docx", "odt", "pdf", FEEDBACK_TEXT_EXTS)
# A photo or screenshot submitted instead of a document. With
# anonymize(transcribe_images = TRUE) the local model transcribes it; relink()
# answers it with feedback rendered as an image of the same type and name.
SUBMISSION_IMAGE_EXTS <- c("jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tif", "tiff")

run_tool <- function(cmd, args) {
  res <- suppressWarnings(system2(cmd, args, stdout = TRUE, stderr = TRUE))
  st <- attr(res, "status")
  if (!is.null(st) && st != 0) stop(cmd, " failed (status ", st, ")", call. = FALSE)
  invisible(res)
}

convert_to_text <- function(path, out_md, media_dir, transcribe = NULL) {
  ext <- tolower(tools::file_ext(path))
  dir.create(dirname(out_md), recursive = TRUE, showWarnings = FALSE)
  if (ext %in% c("docx", "odt")) {
    # pandoc picks the reader from the extension. It writes image links using
    # the --extract-media path as given, so run it from the .md's own folder
    # with a relative media folder: links then read <file>_media/media/...
    # (Pictures/... for an .odt) and resolve for the grader.
    if (!identical(normalizePath(dirname(media_dir)), normalizePath(dirname(out_md)))) {
      stop("media_dir must sit beside out_md", call. = FALSE)
    }
    src <- normalizePath(path)
    old <- setwd(dirname(out_md)); on.exit(setwd(old), add = TRUE)
    run_tool("pandoc", c(shQuote(src), "-t", "markdown", "--wrap=none",
                         "--track-changes=accept",
                         paste0("--extract-media=", shQuote(basename(media_dir))),
                         "-o", shQuote(basename(out_md))))
  } else if (ext == "pdf") {
    run_tool("pdftotext", c("-layout", shQuote(path), shQuote(out_md)))
    dir.create(media_dir, recursive = TRUE, showWarnings = FALSE)
    run_tool("pdfimages", c("-png", shQuote(path), shQuote(file.path(media_dir, "img"))))
  } else if (ext %in% TEXT_EXTS) {
    writeLines(readLines(path, warn = FALSE, encoding = "UTF-8"), out_md, useBytes = TRUE)
  } else if (ext %in% SUBMISSION_IMAGE_EXTS) {
    if (is.null(transcribe)) {
      stop("image submission (.", ext, "); anonymize(..., transcribe_images = TRUE) has the ",
           "local model transcribe it", call. = FALSE)
    }
    # The image is transcribed from a temporary PNG copy (any format, HEIC
    # included) and is never written to the coded folder: the redacted
    # transcript is the student's only file, so the photo is never swept or
    # shown to a grader.
    png <- tempfile(fileext = ".png")
    on.exit(unlink(png), add = TRUE)
    magick::image_write(magick::image_read(path), png, format = "png")
    text <- transcribe(png)
    writeLines(c("*Transcribed from an image by the local model. Check it against the original submission.*",
                 "", text), out_md, useBytes = TRUE)
  } else {
    stop("unsupported submission type: .", ext, call. = FALSE)
  }
  invisible(out_md)
}
