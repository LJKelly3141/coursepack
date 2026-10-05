# Images extracted from submissions. Each is stripped of metadata and read
# with OCR; the OCR text gets the same checks as the document text. Anything
# that hits, and anything OCR cannot read, waits for an instructor decision in
# <assignment>/anon_images.csv (image,decision with keep|remove).
IMAGE_EXTS <- c("png","jpg","jpeg","gif","bmp","tif","tiff","webp","emf","wmf","svg")
OCR_EXTS <- c("png","jpg","jpeg","gif","bmp","tif","tiff","webp")

image_files <- function(dir) {
  f <- list.files(dir, recursive = TRUE, full.names = TRUE)
  f[tolower(tools::file_ext(f)) %in% IMAGE_EXTS]
}

strip_image_metadata <- function(path) {
  if (!tolower(tools::file_ext(path)) %in% OCR_EXTS) return(FALSE)
  fmt <- magick::image_info(magick::image_read(path))$format[1]
  img <- magick::image_strip(magick::image_read(path))
  magick::image_write(img, path, format = tolower(fmt))
  TRUE
}

tesseract_path <- function() Sys.which("tesseract")[[1]]

ocr_image <- function(path) {
  if (!nzchar(tesseract_path())) {
    stop("tesseract is not installed; image text cannot be checked. ",
         "Install it (brew install tesseract) and re-run.", call. = FALSE)
  }
  # stdout only: tesseract prints diagnostics ("Estimating resolution...") to
  # stderr, which must not end up in the OCR text.
  res <- suppressWarnings(system2("tesseract", c(shQuote(path), "stdout", "--psm", "11"),
                                  stdout = TRUE, stderr = FALSE))
  st <- attr(res, "status")
  if (!is.null(st) && st != 0) stop("tesseract failed (status ", st, ")", call. = FALSE)
  paste(res, collapse = "\n")
}

scan_images <- function(anon_dir, terms) {
  imgs <- image_files(anon_dir)
  loose <- loose_terms(terms)
  out <- data.frame(image = character(), code = character(), reason = character(),
                    stringsAsFactors = FALSE)
  stripped <- 0L
  for (p in imgs) {
    rel <- sub(paste0("^", rx_escape(normalizePath(anon_dir)), "/?"), "", normalizePath(p))
    code <- strsplit(rel, "/", fixed = TRUE)[[1]][1]
    if (!tolower(tools::file_ext(p)) %in% OCR_EXTS) {
      out <- rbind(out, data.frame(image = rel, code = code, reason = "unscannable"))
      next
    }
    if (strip_image_metadata(p)) stripped <- stripped + 1L
    txt <- redact_paths(ocr_image(p))
    low <- tolower(txt)
    name_hit <- any(vapply(terms$term, function(t) grepl(word_rx(t), txt, perl = TRUE,
                                                         ignore.case = TRUE), TRUE)) ||
      any(vapply(loose$term, function(t) grepl(t, low, fixed = TRUE), TRUE))
    pat_hit <- sum(redact_patterns(txt)$counts) > 0
    if (name_hit || pat_hit) {
      out <- rbind(out, data.frame(image = rel, code = code,
                                   reason = if (name_hit) "name" else "pattern"))
    }
  }
  attr(out, "scanned") <- length(imgs)
  attr(out, "stripped") <- stripped
  out
}

read_image_decisions <- function(assignment_dir) {
  p <- file.path(assignment_dir, "anon_images.csv")
  if (!file.exists(p)) return(data.frame(image = character(), decision = character()))
  d <- utils::read.csv(p, colClasses = "character", na.strings = character(),
                       strip.white = TRUE)
  if (!all(c("image", "decision") %in% names(d))) {
    stop("anon_images.csv needs the columns image,decision", call. = FALSE)
  }
  bad <- !tolower(d$decision) %in% c("keep", "remove")
  if (any(bad)) stop("anon_images.csv: decision must be keep or remove", call. = FALSE)
  d$decision <- tolower(d$decision)
  d
}

apply_image_decisions <- function(anon_dir, flagged, decisions) {
  m <- match(flagged$image, decisions$image)
  undecided <- flagged[is.na(m), , drop = FALSE]
  dec <- decisions$decision[m]
  removed <- 0L; kept <- 0L
  for (i in which(!is.na(m))) {
    if (dec[i] == "keep") { kept <- kept + 1L; next }
    rel <- flagged$image[i]
    unlink(file.path(anon_dir, rel))
    code <- flagged$code[i]
    inside <- sub(paste0("^", rx_escape(code), "/"), "", rel)
    link <- paste0("!\\[[^\\]]*\\]\\(", rx_escape(inside), "\\)(\\{[^}]*\\})?")
    for (md in list.files(file.path(anon_dir, code), "\\.md$", full.names = TRUE)) {
      txt <- readLines(md, warn = FALSE, encoding = "UTF-8")
      writeLines(gsub(link, "[image removed]", txt, perl = TRUE), md, useBytes = TRUE)
    }
    removed <- removed + 1L
  }
  list(removed = removed, kept = kept, undecided = undecided)
}
