# Images extracted from submissions. Each is stripped of metadata and read
# with OCR; the OCR text gets the same checks as the document text. Anything
# that hits, and anything OCR cannot read, waits for an instructor decision in
# <assignment>/anon_images.csv (image,decision with keep|remove).
IMAGE_EXTS <- c("png","jpg","jpeg","gif","bmp","tif","tiff","webp","emf","wmf","svg")
OCR_EXTS <- c("png","jpg","jpeg","gif","bmp","tif","tiff","webp")

# Image files anywhere under dir, plus EVERY file inside a <file>_media folder
# (any depth): pandoc puts embedded objects there under any extension (.wdp,
# .jfif, .heic, .bin, .pdf), and none of them may bypass the gate.
image_files <- function(dir) {
  f <- list.files(dir, recursive = TRUE, full.names = FALSE)
  in_media <- vapply(strsplit(dirname(f), "/", fixed = TRUE),
                     function(parts) any(grepl("_media$", parts)), TRUE)
  keep <- tolower(tools::file_ext(f)) %in% IMAGE_EXTS | in_media
  file.path(dir, f[keep])
}

# A kept emf/wmf is released unaltered: no tool here can strip them.
strip_image_metadata <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext == "svg") return(strip_svg(path))
  if (!ext %in% OCR_EXTS) return(FALSE)
  fmt <- magick::image_info(magick::image_read(path))$format[1]
  # Orient first: once EXIF is gone a phone photo would stay rotated.
  img <- magick::image_strip(magick::image_orient(magick::image_read(path)))
  magick::image_write(img, path, format = tolower(fmt))
  TRUE
}

# SVG is text: drop <metadata> blocks and editor attributes.
strip_svg <- function(path) {
  txt <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  txt <- gsub("(?is)<metadata\\b.*?</metadata>", "", txt, perl = TRUE)
  txt <- gsub("(?i)\\s+(sodipodi|inkscape):[A-Za-z0-9_-]+\\s*=\\s*(\"[^\"]*\"|'[^']*')", "",
              txt, perl = TRUE)
  writeLines(txt, path, useBytes = TRUE)
  TRUE
}

tesseract_path <- function() Sys.which("tesseract")[[1]]

require_tesseract <- function() {
  if (!nzchar(tesseract_path())) {
    stop("tesseract is not installed; image text cannot be checked. ",
         "Install it (brew install tesseract) and re-run.", call. = FALSE)
  }
  invisible(TRUE)
}

ocr_image <- function(path) {
  require_tesseract()
  # stdout only: tesseract prints diagnostics ("Estimating resolution...") to
  # stderr, which must not end up in the OCR text.
  res <- suppressWarnings(system2("tesseract", c(shQuote(path), "stdout", "--psm", "11"),
                                  stdout = TRUE, stderr = FALSE))
  st <- attr(res, "status")
  if (!is.null(st) && st != 0) stop("tesseract failed (status ", st, ")", call. = FALSE)
  paste(res, collapse = "\n")
}

# "name", "pattern" or NA for text read from an image. The name check runs on
# the RAW text: redacting paths first would erase a login before it is seen.
text_reason <- function(txt, terms, loose) {
  low <- tolower(txt)
  name_hit <- any(vapply(terms$term, function(t) grepl(word_rx(t), txt, perl = TRUE,
                                                       ignore.case = TRUE), TRUE)) ||
    any(vapply(loose$term, function(t) grepl(t, low, fixed = TRUE), TRUE))
  if (name_hit) return("name")
  pat_hit <- sum(redact_paths(txt, counts = TRUE)$counts) > 0 ||
    sum(redact_patterns(txt)$counts) > 0
  if (pat_hit) "pattern" else NA_character_
}

scan_images <- function(anon_dir, terms) {
  imgs <- image_files(anon_dir)
  # Fail here, not per image: the per-image tryCatch would otherwise turn a
  # missing tesseract into "unscannable" for every raster image.
  if (any(tolower(tools::file_ext(imgs)) %in% OCR_EXTS)) require_tesseract()
  loose <- loose_terms(terms)
  out <- data.frame(image = character(), code = character(), reason = character(),
                    stringsAsFactors = FALSE)
  stripped <- 0L
  for (p in imgs) {
    rel <- sub(paste0("^", rx_escape(normalizePath(anon_dir)), "/?"), "", normalizePath(p))
    code <- strsplit(rel, "/", fixed = TRUE)[[1]][1]
    ext <- tolower(tools::file_ext(p))
    # Any failure (corrupt file, tesseract error) leaves the image for a
    # decision; the error text is dropped so no file content is echoed.
    reason <- tryCatch({
      if (ext == "svg") {
        if (strip_image_metadata(p)) stripped <- stripped + 1L
        r <- text_reason(paste(readLines(p, warn = FALSE, encoding = "UTF-8"),
                               collapse = "\n"), terms, loose)
        if (is.na(r)) "unscannable" else r
      } else if (ext %in% OCR_EXTS) {
        if (strip_image_metadata(p)) stripped <- stripped + 1L
        text_reason(ocr_image(p), terms, loose)
      } else {
        "unscannable"
      }
    }, error = function(e) "unscannable")
    if (!is.na(reason)) {
      out <- rbind(out, data.frame(image = rel, code = code, reason = reason,
                                   stringsAsFactors = FALSE))
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
