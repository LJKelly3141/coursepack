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

# A workbook submitted instead of a document. Never a feedback target while the
# student also submitted a document or an image.
WORKBOOK_EXTS <- c("xlsx", "xlsm")
SHEET_EXTS <- c(WORKBOOK_EXTS, "csv")

# The package's own workbook messages: fixed text, never workbook content.
# Classed so convert_to_text() can pass them through and replace any other
# reader error, whose text could quote the workbook.
wb_stop <- function(msg) {
  stop(structure(class = c("coursepack_wb_error", "error", "condition"),
                 list(message = msg, call = NULL)))
}

run_tool <- function(cmd, args) {
  res <- suppressWarnings(system2(cmd, args, stdout = TRUE, stderr = TRUE))
  st <- attr(res, "status")
  if (!is.null(st) && st != 0) stop(cmd, " failed (status ", st, ")", call. = FALSE)
  invisible(res)
}

# Returns out_md invisibly. For a workbook or .csv it carries attributes
# "other" (named integer counts of content not read, by kind) and "ignored"
# (data.frame of sheets over the raw-data cell cap: sheet_pos, rows, cols).
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
  } else if (ext %in% SHEET_EXTS) {
    # Read as XML (or plain text for a .csv); nothing in the workbook runs.
    # The markdown goes through anonymize()'s redaction like any document.
    # The readers get a copy under a neutral name: the Canvas filename carries
    # the student's name and id, and unzip() and tidyxl put the path they
    # were given into their error messages.
    tmp <- tempfile("submission_", fileext = paste0(".", ext))
    on.exit(unlink(tmp), add = TRUE)
    # file.copy() warnings can name the source path, the Canvas filename.
    if (!suppressWarnings(file.copy(path, tmp))) wb_stop("could not copy the workbook for reading")
    # Allow-list: only the package's own messages (wb_stop()) pass through. A
    # third-party error (tidyxl, xml2/libxml2, unzip) can quote sheet names or
    # cell text, so it is replaced by a fixed message.
    # Warnings and messages from the readers can quote the workbook too
    # (libxml2 names a bad namespace URI): muffled, and warnings only counted.
    n_warn <- 0L
    wb <- tryCatch(
      withCallingHandlers(
        if (ext == "csv") csv_to_md(tmp) else workbook_to_md(tmp, media_dir, basename(media_dir)),
        warning = function(w) { n_warn <<- n_warn + 1L; invokeRestart("muffleWarning") },
        message = function(m) invokeRestart("muffleMessage")),
      error = function(e) {
        if (inherits(e, "coursepack_wb_error")) stop(conditionMessage(e), call. = FALSE)
        stop(if (ext == "csv") "the csv could not be read; re-save it, or pass skip_types" else
          "the workbook could not be read; re-save it as .xlsx, or pass skip_types", call. = FALSE)
      })
    writeLines(wb$lines, out_md, useBytes = TRUE)
    attr(out_md, "other") <- c(wb$other, reader_warnings = n_warn)
    attr(out_md, "ignored") <- wb$ignored
  } else if (ext == "xls") {
    stop("legacy .xls workbook; re-save as .xlsx, or pass skip_types = \"xls\" to leave ",
         ".xls files out", call. = FALSE)
  } else {
    stop("unsupported submission type: .", ext, call. = FALSE)
  }
  invisible(out_md)
}
