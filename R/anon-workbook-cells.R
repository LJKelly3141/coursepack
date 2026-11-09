# tidyxl reads cells in C++ and does not check for every malformed structure:
# some crash R outright (a segfault no tryCatch can catch). So
#   1. workbook_faults() names the structures known to crash it, from the
#      unzipped parts, and the workbook is refused with fixed text;
#   2. xlsx_cells_isolated() runs tidyxl in a separate R process, so a crash
#      on a structure not yet known stops only that process, and anonymize()
#      gets an ordinary error (shown as the fixed "could not be read" text).
# Fault lines give a sheet's position, never its name or any content.

# Character vector of known faults; empty when none. root is the unzipped
# workbook; sheets has columns name and part (worksheets only).
workbook_faults <- function(root, sheets) {
  out <- character()
  n_xf <- NA_integer_
  sp <- file.path(root, "xl/styles.xml")
  if (file.exists(sp)) {
    xf <- xml2::xml_find_all(xml2::read_xml(sp), "/m:styleSheet/m:cellXfs/m:xf", CHART_NS)
    n_xf <- length(xf)
  }
  for (i in seq_len(nrow(sheets))) {
    part <- sheets$part[i]
    if (is.na(part) || !file.exists(file.path(root, part))) next
    at <- sprintf("sheet %d", i)
    d <- xml2::read_xml(file.path(root, part), options = "HUGE")
    q <- function(xp) xml2::xml_find_all(d, xp, CHART_NS)
    # Child steps only: a "//" or "//*" search over a big sheet can pass
    # libxml2's node-set cap and crash xml2 itself.
    if (!length(q("/m:worksheet/m:sheetData"))) out <- c(out, sprintf("%s has no cell data section", at))
    if (length(q("/m:worksheet/m:cols/m:col[not(@min) or not(@max)]"))) {
      out <- c(out, sprintf("%s has a column-width entry without its first or last column", at))
    }
    if (length(q("/m:worksheet/m:sheetData/m:row/*[not(self::m:c)]"))) {
      out <- c(out, sprintf("%s has a row holding something other than cells", at))
    }
    f <- q("/m:worksheet/m:sheetData/m:row/m:c/m:f[@t='shared']")
    if (length(f)) {
      si <- xml2::xml_attr(f, "si")
      master <- !is.na(xml2::xml_attr(f, "ref"))
      if (any(!si %in% si[master])) {
        out <- c(out, sprintf("%s has a shared formula without its first cell", at))
      }
    }
    s <- suppressWarnings(as.integer(xml2::xml_attr(q("/m:worksheet/m:sheetData/m:row/m:c[@s]"), "s")))
    if (!is.na(n_xf) && length(s) && (anyNA(s) || any(s < 0L | s >= n_xf))) {
      out <- c(out, sprintf("%s has a cell whose style number is not in the style list", at))
    }
    for (cp in rel_of(rels_table(root, part), "comments")) {
      if (!file.exists(file.path(root, cp))) next
      cd <- xml2::read_xml(file.path(root, cp))
      cl <- xml2::xml_find_all(cd, "/m:comments/m:commentList", CHART_NS)
      cm <- xml2::xml_find_all(cd, "/m:comments/m:commentList/m:comment", CHART_NS)
      if (!length(cl)) {
        out <- c(out, sprintf("%s has a comments part without a comment list", at))
      } else if (length(cm) && (any(is.na(xml2::xml_attr(cm, "ref"))) ||
                                any(xml2::xml_length(cm) == 0L))) {
        out <- c(out, sprintf("%s has a comment without a cell reference or text", at))
      }
    }
  }
  out
}

# tidyxl::xlsx_cells() in a child R process. Any failure there, a crash
# included, becomes a classed error with fixed text: the child's own message
# could quote the workbook.
xlsx_cells_isolated <- function(xlsx, sheets) {
  io <- tempfile("cells_")
  dir.create(io)
  on.exit(unlink(io, recursive = TRUE), add = TRUE)
  inp <- file.path(io, "in.rds"); res <- file.path(io, "out.rds")
  saveRDS(list(path = normalizePath(xlsx), sheets = sheets), inp)
  code <- sprintf("a <- readRDS(%s); saveRDS(tidyxl::xlsx_cells(a$path, sheets = a$sheets), %s)",
                  deparse(inp), deparse(res))
  rscript <- file.path(R.home("bin"), "Rscript")
  # The subshell's own redirect also silences the shell's "Bus error" or
  # "Segmentation fault" report, which would echo this command.
  cmd <- paste(shQuote(rscript), "--vanilla -e", shQuote(code))
  st <- suppressWarnings(system(paste0("(", cmd, ") >/dev/null 2>&1"),
                                ignore.stdout = TRUE, ignore.stderr = TRUE))
  # A plain error: convert_to_text() replaces it with its fixed "could not be
  # read" text, the same as for a tidyxl error before the read was isolated.
  if (!identical(as.integer(st), 0L) || !file.exists(res)) {
    stop("the cell reader failed (exit status ", st, ")", call. = FALSE)
  }
  readRDS(res)
}
