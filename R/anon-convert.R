# One submission file to one plain-text file plus its images.
# Converting to text is what removes document metadata: pandoc without -s
# emits no title block, and pdftotext emits page text only.

TEXT_EXTS <- c("md", "qmd", "rmd", "r", "txt")

run_tool <- function(cmd, args) {
  res <- suppressWarnings(system2(cmd, args, stdout = TRUE, stderr = TRUE))
  st <- attr(res, "status")
  if (!is.null(st) && st != 0) stop(cmd, " failed (status ", st, ")", call. = FALSE)
  invisible(res)
}

convert_to_text <- function(path, out_md, media_dir) {
  ext <- tolower(tools::file_ext(path))
  dir.create(dirname(out_md), recursive = TRUE, showWarnings = FALSE)
  if (ext == "docx") {
    # pandoc writes image links using the --extract-media path as given, so
    # run it from the .md's own folder with a relative media folder: links
    # then read <file>_media/media/image1.png and resolve for the grader.
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
  } else {
    stop("unsupported submission type: .", ext, call. = FALSE)
  }
  invisible(out_md)
}
