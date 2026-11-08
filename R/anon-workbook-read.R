# A submitted workbook (or .csv) as markdown for the grader. The .xlsx is read
# as a zip of XML (tidyxl for cells, xml2 for the rest); nothing in it is run.
# Sections, in this order: Charts, each sheet, Pivot tables, Comments, Text
# boxes, Hyperlinks and defined names, Headers and footers, Embedded
# documents, Other content. Names stay in the text: redaction runs later on
# these lines. docProps, persons, vbaProject.bin, externalLinks and
# connections.xml are never extracted; their presence is counted only.

WB_NEVER_READ <- "^(docProps/|xl/persons/|xl/vbaProject\\.bin$|xl/externalLinks/|xl/connections\\.xml$)"
# A sheet or .csv whose used range (first to last non-empty cell) is over this
# many cells is raw data: it is not read, and one "Not read" line says so.
RAW_CELL_CAP <- 4000L

# Parts this reader handles or deliberately leaves alone. Anything else is
# counted under Other content as an unrecognised part.
WB_KNOWN_PARTS <- paste0(
  "^(\\[Content_Types\\]\\.xml$|_rels/|docProps/|customXml/|xl/(workbook\\.xml$|_rels/|",
  "worksheets/|chartsheets/|macrosheets/|dialogsheets/|sharedStrings\\.xml$|styles\\.xml$|",
  "theme/|calcChain\\.xml$|metadata\\.xml$|drawings/|charts/|media/|comments[^/]*\\.xml$|",
  "threadedComments/|persons/|pivotTables/|pivotCache/|tables/|printerSettings/|ctrlProps/|",
  "embeddings/|vbaProject\\.bin$|vbaProjectSignature[^/]*\\.bin$|externalLinks/|",
  "connections\\.xml$|activeX/|slicers/|slicerCaches/|timelines/|timelineCaches/|model/|",
  "queryTables/|webextensions/|richData/))")

# Always present in `other`, so a caller can index them.
WB_OTHER_KINDS <- c("macros", "external_links", "connections", "form_controls",
                    "sparklines", "embedded_objects")

WB_OTHER_LABELS <- c(
  macros = "macro code (VBA project or macro sheets; not read)",
  external_links = "links to other workbooks (targets not read)",
  connections = "data connections (not read)",
  form_controls = "form controls",
  sparklines = "sparklines",
  embedded_objects = "embedded objects not converted",
  activex = "ActiveX controls",
  slicers = "slicers",
  timelines = "timeline filters",
  data_model = "data model parts",
  query_tables = "query tables",
  custom_xml = "custom XML parts",
  web_extensions = "add-in (web extension) parts",
  other_pictures = "pictures not placed by a drawing (not copied)",
  header_footer_pictures = "header or footer pictures",
  drawing_objects = "other drawing objects",
  sheet_extensions = "sheet extensions not described",
  other_sheets = "sheets of another type (not read)",
  other_parts = "unrecognised parts",
  raw_hyperlinks = "hyperlinks on sheets not read as raw data (not listed)",
  data_tables = "what-if data tables (cells marked in the sheet)",
  scenarios = "what-if scenarios (not described)",
  csv_read_problems = "csv read problems")

wb_state <- function() {
  st <- new.env()
  st$other <- stats::setNames(as.list(rep(0L, length(WB_OTHER_KINDS))), WB_OTHER_KINDS)
  st$detail <- list(); st$media <- list(); st$n_image <- 0L
  st
}

other_counts <- function(st) unlist(st$other)

# ---- cells ----------------------------------------------------------------

compress_runs <- function(x, label = as.character) {
  x <- sort(unique(x))
  if (!length(x)) return(character())
  br <- c(0, which(diff(x) != 1), length(x))
  vapply(seq_len(length(br) - 1), function(i) {
    a <- x[br[i] + 1]; b <- x[br[i + 1]]
    if (a == b) label(a) else sprintf("%s to %s", label(a), label(b))
  }, "")
}

cell_values <- function(d, marks = list(spill = character(), data_table = character())) {
  v <- rep("", nrow(d))
  dt <- d$data_type
  i <- dt == "character"; v[i] <- d$character[i]
  i <- dt == "numeric"; v[i] <- as.character(d$numeric[i])
  i <- dt == "logical"; v[i] <- ifelse(d$logical[i], "TRUE", "FALSE")
  i <- dt == "error"; v[i] <- d$error[i]
  i <- dt == "date"
  if (any(i)) {
    dd <- d$date[i]
    v[i] <- ifelse(format(dd, "%H:%M:%S", tz = "UTC") == "00:00:00",
                   format(dd, "%Y-%m-%d", tz = "UTC"), format(dd, "%Y-%m-%d %H:%M:%S", tz = "UTC"))
  }
  v[is.na(v)] <- ""
  # Newer-function prefixes Excel writes to the file but never shows.
  fm <- gsub("_xl(fn|ws|pm)\\.", "", d$formula)
  # A what-if data table's cells hold results Excel computed, not typed values.
  dt_ref <- unname(marks$data_table[d$address])
  in_dt <- !is.na(dt_ref)
  f <- !is.na(fm) & nzchar(fm) & !in_dt
  spill <- unname(marks$spill[d$address])
  sp <- f & d$is_array & !is.na(spill)
  arr <- f & d$is_array & !sp
  v[f] <- trimws(paste0(v[f], " `", ifelse(arr[f], "{=", "="), fm[f], ifelse(arr[f], "}", ""), "`",
                        ifelse(sp[f], paste0(" (spills into ", spill[f], ")"), "")))
  v[in_dt] <- paste0(v[in_dt], " (data table ", dt_ref[in_dt], ")")
  v
}

# Every address in a range such as "B3:C4".
ref_cells <- function(ref) {
  ends <- strsplit(ref, ":", fixed = TRUE)[[1]]
  if (length(ends) == 1) ends <- c(ends, ends)
  cc <- vapply(ends, tidyxl_col, 0); rr <- as.integer(gsub("[^0-9]", "", ends))
  g <- expand.grid(c = seq(cc[1], cc[2]), r = seq(rr[1], rr[2]))
  paste0(vapply(g$c, col_letters, ""), g$r)
}

# Spilling (dynamic-array) formulas and what-if data tables, read from the
# sheet XML: tidyxl shows neither. Also counts data tables and scenarios.
formula_marks <- function(sdoc, st) {
  sp <- xml2::xml_find_all(sdoc, "//m:sheetData/m:row/m:c[@cm][m:f[@t='array']]", CHART_NS)
  spill <- stats::setNames(xml2::xml_attr(xml2::xml_find_first(sp, "m:f", CHART_NS), "ref"),
                           xml2::xml_attr(sp, "r"))
  dts <- xml2::xml_attr(xml2::xml_find_all(sdoc, "//m:sheetData/m:row/m:c/m:f[@t='dataTable']", CHART_NS), "ref")
  dts <- dts[!is.na(dts)]
  data_table <- unlist(lapply(dts, function(r) stats::setNames(rep(r, length(ref_cells(r))), ref_cells(r))))
  add_other(st, "data_tables", length(dts))
  add_other(st, "scenarios", length(xml2::xml_find_all(sdoc, "/m:worksheet/m:scenarios/m:scenario", CHART_NS)))
  list(spill = spill, data_table = if (is.null(data_table)) character() else data_table)
}

md_cell <- function(x) gsub("\r?\n", "<br>", gsub("|", "\\|", x, fixed = TRUE))

# A markdown table with a row-number column and column letters.
cell_table <- function(r, c, v, hidden_rows = integer(), hidden_cols = integer()) {
  rows <- sort(unique(r)); cols <- seq(min(c), max(c))
  m <- matrix("", length(rows), length(cols))
  m[cbind(match(r, rows), match(c, cols))] <- md_cell(v)
  rl <- ifelse(rows %in% hidden_rows, paste0(rows, " (hidden)"), as.character(rows))
  cl <- vapply(cols, col_letters, "")
  cl <- ifelse(cols %in% hidden_cols, paste0(cl, " (hidden)"), cl)
  c(paste0("| Row | ", paste(cl, collapse = " | "), " |"),
    paste0("|", paste(rep("---", length(cols) + 1), collapse = "|"), "|"),
    paste0("| ", rl, " | ", apply(m, 1, paste, collapse = " | "), " |"))
}

# ---- sheet structure lines ------------------------------------------------

filter_lines <- function(af) {
  if (inherits(af, "xml_missing")) return(character())
  ref <- xml2::xml_attr(af, "ref")
  out <- paste0("Autofilter: ", ref)
  c0 <- tidyxl_col(sub(":.*", "", ref))
  for (fc in xml2::xml_find_all(af, "m:filterColumn", CHART_NS)) {
    col <- col_letters(c0 + as.integer(xml2::xml_attr(fc, "colId")))
    for (k in xml2::xml_children(fc)) {
      kind <- xml2::xml_name(k)
      desc <- switch(kind,
        filters = {
          v <- xml2::xml_attr(xml2::xml_find_all(k, "m:filter", CHART_NS), "val")
          paste0("shows ", paste(v, collapse = ", "),
                 if (xml2::xml_attr(k, "blank") %in% c("1", "true")) ", (blanks)" else "")
        },
        customFilters = {
          cf <- xml2::xml_find_all(k, "m:customFilter", CHART_NS)
          op <- xml2::xml_attr(cf, "operator"); op[is.na(op)] <- "equal"
          paste(paste(op, xml2::xml_attr(cf, "val")),
                collapse = if (xml2::xml_attr(k, "and") %in% c("1", "true")) " and " else " or ")
        },
        top10 = sprintf("%s %s%s", if (xml2::xml_attr(k, "top") %in% c("0", "false")) "bottom" else "top",
                        xml2::xml_attr(k, "val"), if (xml2::xml_attr(k, "percent") %in% c("1", "true")) " percent" else ""),
        dynamicFilter = paste("dynamic:", xml2::xml_attr(k, "type")),
        colorFilter = "by color",
        iconFilter = "by icon",
        paste("not described:", kind))
      out <- c(out, sprintf("  - column %s: %s", col, desc))
    }
  }
  out
}

tidyxl_col <- function(ref) {
  l <- strsplit(gsub("[^A-Z]", "", toupper(ref)), "")[[1]]
  n <- 0
  for (ch in l) n <- n * 26 + match(ch, LETTERS)
  n
}

sort_lines <- function(ss) {
  if (inherits(ss, "xml_missing")) return(character())
  sc <- xml2::xml_find_all(ss, "m:sortCondition", CHART_NS)
  d <- ifelse(xml2::xml_attr(sc, "descending") %in% c("1", "true"), "descending", "ascending")
  by <- xml2::xml_attr(sc, "sortBy")
  sprintf("Sort state on %s: %s", xml2::xml_attr(ss, "ref"),
          paste(sprintf("%s %s%s", xml2::xml_attr(sc, "ref"), d,
                        ifelse(is.na(by) | by == "value", "", paste0(" by ", by))), collapse = ", then "))
}

hidden_rows_cols <- function(sdoc) {
  hr <- as.integer(xml2::xml_attr(xml2::xml_find_all(sdoc, "//m:sheetData/m:row[@hidden='1' or @hidden='true']", CHART_NS), "r"))
  hc <- xml2::xml_find_all(sdoc, "//m:cols/m:col[@hidden='1' or @hidden='true']", CHART_NS)
  list(rows = hr, cols = unlist(Map(seq, as.integer(xml2::xml_attr(hc, "min")), as.integer(xml2::xml_attr(hc, "max")))))
}

structure_lines <- function(root, rt, sdoc, hid) {
  out <- character()
  hr <- hid$rows; hc <- hid$cols
  if (length(hr)) out <- c(out, paste0("Hidden rows: ", paste(compress_runs(hr), collapse = ", ")))
  if (length(hc)) out <- c(out, paste0("Hidden columns: ", paste(compress_runs(hc, col_letters), collapse = ", ")))
  mc <- xml2::xml_attr(xml2::xml_find_all(sdoc, "//m:mergeCells/m:mergeCell", CHART_NS), "ref")
  if (length(mc)) out <- c(out, paste0("Merged cells: ", paste(mc, collapse = ", ")))
  af <- xml2::xml_find_first(sdoc, "/m:worksheet/m:autoFilter", CHART_NS)
  out <- c(out, filter_lines(af), sort_lines(xml2::xml_find_first(af, "m:sortState", CHART_NS)),
           sort_lines(xml2::xml_find_first(sdoc, "/m:worksheet/m:sortState", CHART_NS)))
  for (tp in rel_of(rt, "table")) {
    if (!file.exists(file.path(root, tp))) next
    td <- xml2::read_xml(file.path(root, tp))
    out <- c(out, sprintf("Table %s: %s", xml2::xml_attr(td, "displayName"), xml2::xml_attr(td, "ref")),
             paste0("  ", c(filter_lines(xml2::xml_find_first(td, "m:autoFilter", CHART_NS)),
                            sort_lines(xml2::xml_find_first(td, "m:sortState", CHART_NS)))))
    out <- out[out != "  "]
  }
  for (dv in xml2::xml_find_all(sdoc, "//m:dataValidations/m:dataValidation", CHART_NS)) {
    f <- xml2::xml_text(xml2::xml_find_all(dv, "m:formula1 | m:formula2", CHART_NS))
    ty <- xml2::xml_attr(dv, "type")
    out <- c(out, sprintf("Data validation on %s: %s%s", xml2::xml_attr(dv, "sqref"),
                          if (is.na(ty)) "any value" else ty,
                          if (length(f)) paste0(" ", paste(sprintf("`%s`", f), collapse = " and ")) else ""))
  }
  for (cf in xml2::xml_find_all(sdoc, "/m:worksheet/m:conditionalFormatting", CHART_NS)) {
    for (rl in xml2::xml_find_all(cf, "m:cfRule", CHART_NS)) {
      f <- xml2::xml_text(xml2::xml_find_all(rl, "m:formula", CHART_NS))
      op <- xml2::xml_attr(rl, "operator")
      out <- c(out, sprintf("Conditional formatting on %s: %s%s%s", xml2::xml_attr(cf, "sqref"),
                            xml2::xml_attr(rl, "type"), if (is.na(op)) "" else paste0(" ", op),
                            if (length(f)) paste0(" ", paste(sprintf("`%s`", f), collapse = " and ")) else ""))
    }
  }
  out
}

# Sparklines and sheet extensions; header/footer pictures.
# Never search a whole sheet with "//*": on a big data sheet the node set
# passes libxml2's 10-million-node cap and xml2 segfaults. Sparklines live
# only under the sheet's extLst, so the search starts there.
sheet_extras <- function(sdoc, st) {
  add_other(st, "sparklines", length(xml2::xml_find_all(sdoc, "/*/m:extLst//*[local-name()='sparkline']", CHART_NS)))
  for (e in xml2::xml_find_all(sdoc, "/*/m:extLst/m:ext", CHART_NS)) {
    k <- xml2::xml_name(xml2::xml_children(e))
    k <- setdiff(k, "sparklineGroups")
    if (length(k)) add_other(st, "sheet_extensions", length(k), k)
  }
  add_other(st, "header_footer_pictures",
            length(xml2::xml_find_all(sdoc, "/*/m:legacyDrawingHF", CHART_NS)))
}

# ---- raw-data cap -------------------------------------------------------------

not_read_line <- function(rows, cols) {
  f <- function(x) format(x, big.mark = ",", scientific = FALSE, trim = TRUE)
  sprintf("Not read: %s rows x %s columns is over the %s-cell limit for raw data.",
          f(rows), f(cols), f(RAW_CELL_CAP))
}

# Rows and columns from the first to the last non-empty cell; c(0, 0) if none.
used_extent <- function(r, c) {
  if (!length(r)) return(c(0, 0))
  c(max(r) - min(r) + 1, max(c) - min(c) + 1)
}

# ---- one sheet --------------------------------------------------------------

read_sheet <- function(wb, i, cells, st, media_dir, media_rel, used = c(0, 0)) {
  s <- wb$sheets[i, ]
  mark <- switch(if (is.na(s$state)) "visible" else s$state,
                 hidden = " (hidden)", veryHidden = " (very hidden)", "")
  res <- list(ignored = NULL, lines = character(), pivots = character(), comments = character(),
              text = character(), links = character(), headers = character())
  head <- sprintf("## Sheet: %s%s", s$name, mark)
  if (is.na(s$part) || !file.exists(file.path(wb$root, s$part))) {
    res$lines <- c(head, "", "Sheet part missing from the file.", "")
    return(res)
  }
  if (!grepl("^xl/(worksheets|chartsheets)/", s$part)) {
    add_other(st, if (grepl("^xl/macrosheets/", s$part)) "macros" else "other_sheets", detail = s$name)
    res$lines <- c(head, "", "A macro or dialog sheet: not read; counted under Other content.", "")
    return(res)
  }
  sdoc <- xml2::read_xml(file.path(wb$root, s$part))
  rt <- rels_table(wb$root, s$part)
  chartsheet <- grepl("^xl/chartsheets/", s$part)
  dr <- drawing_lines(wb$root, rt, sdoc, s$name, chartsheet, st, media_dir, media_rel)
  vml_controls(wb$root, rt, st)
  sheet_extras(sdoc, st)
  res$text <- dr$text
  res$comments <- comment_lines(wb$root, rt, s$name)
  res$headers <- header_lines(sdoc, s$name)
  if (chartsheet) {
    res$lines <- c(head, "", "A chart sheet: its chart is described under Charts.", dr$pictures, "")
    return(res)
  }
  res$links <- hyperlink_lines(rt, sdoc, s$name, cells)
  res$pivots <- unlist(lapply(rel_of(rt, "pivotTable"), function(pp)
    if (file.exists(file.path(wb$root, pp))) pivot_lines(wb$root, pp, s$name)))
  if (used[1] * used[2] > RAW_CELL_CAP) {
    # Raw data: no cells, formulas, filters, sort state or hyperlink lines
    # (hyperlinks are only counted). Charts, pivots, comments and text boxes
    # are still read.
    add_other(st, "raw_hyperlinks", length(xml2::xml_find_all(sdoc, "/m:worksheet/m:hyperlinks/m:hyperlink", CHART_NS)))
    res$links <- character()
    res$ignored <- data.frame(sheet_pos = i, rows = used[1], cols = used[2])
    res$lines <- c(head, "", not_read_line(used[1], used[2]), "",
                   if (length(dr$pictures)) c(dr$pictures, ""))
    return(res)
  }
  d <- cells[cells$sheet == s$name & (!cells$is_blank | !is.na(cells$formula)), ]
  hid <- hidden_rows_cols(sdoc)
  info <- structure_lines(wb$root, rt, sdoc, hid)
  marks <- formula_marks(sdoc, st)
  tab <- if (nrow(d)) cell_table(d$row, d$col, cell_values(d, marks), hid$rows, hid$cols) else "No cell content."
  res$lines <- c(head, "", if (length(info)) c(info, ""), tab, "",
                 if (length(dr$pictures)) c(dr$pictures, ""))
  res
}

# ---- whole workbook ---------------------------------------------------------

workbook_open <- function(xlsx) {
  nm <- utils::unzip(xlsx, list = TRUE)$Name
  if (any(unsafe_part_name(nm))) {
    wb_stop("workbook contains a part whose path climbs out of the file (\"..\" or a leading slash); refused")
  }
  root <- tempfile("wbread_")
  dir.create(root)
  utils::unzip(xlsx, files = nm[!grepl(WB_NEVER_READ, nm) & !grepl("/$", nm)], exdir = root)
  wbx <- xml2::read_xml(file.path(root, "xl/workbook.xml"))
  wrel <- part_rels(root, "xl/workbook.xml")
  sh <- xml2::xml_find_all(wbx, "//m:sheets/m:sheet", CHART_NS)
  sheets <- data.frame(name = xml2::xml_attr(sh, "name"), state = xml2::xml_attr(sh, "state"),
                       part = unname(wrel[xml2::xml_attr(sh, "r:id", CHART_NS)]), stringsAsFactors = FALSE)
  list(root = root, nm = nm, wbx = wbx, sheets = sheets)
}

# Counts taken from the part list alone (never opened).
count_parts <- function(nm, st) {
  n <- function(re) sum(grepl(re, nm))
  add_other(st, "macros", n("^xl/vbaProject\\.bin$"))
  add_other(st, "external_links", n("^xl/externalLinks/[^/]+\\.xml$"))
  add_other(st, "connections", n("^xl/connections\\.xml$"))
  add_other(st, "activex", n("^xl/activeX/[^/]+\\.xml$"))
  add_other(st, "slicers", n("^xl/slicers/[^/]+\\.xml$"))
  add_other(st, "timelines", n("^xl/timelines/[^/]+\\.xml$"))
  add_other(st, "data_model", n("^xl/model/[^/]+$"))
  add_other(st, "query_tables", n("^xl/queryTables/[^/]+\\.xml$"))
  add_other(st, "custom_xml", n("^customXml/item[0-9]*\\.xml$"))
  add_other(st, "web_extensions", n("^xl/webextensions/webextension[0-9]*\\.xml$"))
  unk <- nm[!grepl(WB_KNOWN_PARTS, nm) & !grepl("/$", nm)]
  add_other(st, "other_parts", length(unk), unique(dirname(unk)))
}

other_lines <- function(st) {
  o <- other_counts(st)
  o <- o[o > 0]
  if (!length(o)) return("None.")
  vapply(names(o), function(k) {
    lab <- if (is.na(WB_OTHER_LABELS[k])) k else WB_OTHER_LABELS[[k]]
    det <- unique(st$detail[[k]])
    sprintf("- %s: %d%s", lab, o[[k]], if (length(det)) sprintf(" (%s)", paste(det, collapse = ", ")) else "")
  }, "", USE.NAMES = FALSE)
}

section_md <- function(heading, x) c(heading, "", if (length(x)) x else "None.", "")

# Markdown lines for a workbook, the counts for Other content, and the sheets
# ignored as raw data (over RAW_CELL_CAP cells): sheet_pos, rows, cols.
workbook_to_md <- function(xlsx, media_dir, media_rel) {
  charts <- workbook_charts(xlsx)
  wb <- workbook_open(xlsx)
  on.exit(unlink(wb$root, recursive = TRUE), add = TRUE)
  # Every worksheet's cells are loaded and its used range measured from the
  # non-blank (or formula) cells; the <dimension> is not trusted, since styled
  # empty cells inflate it. Cells of sheets over the cap are then dropped, so
  # nothing downstream (charts included) can read them.
  is_ws <- !is.na(wb$sheets$part) & grepl("^xl/worksheets/", wb$sheets$part)
  cells <- if (any(is_ws)) tidyxl::xlsx_cells(xlsx, sheets = wb$sheets$name[is_ws]) else NULL
  used <- matrix(0, nrow(wb$sheets), 2)
  if (!is.null(cells)) {
    live <- cells[!cells$is_blank | !is.na(cells$formula), ]
    for (i in which(is_ws)) {
      d0 <- live[live$sheet == wb$sheets$name[i], ]
      used[i, ] <- used_extent(d0$row, d0$col)
    }
    over <- wb$sheets$name[is_ws & used[, 1] * used[, 2] > RAW_CELL_CAP]
    cells <- cells[!cells$sheet %in% over, ]
  }
  st <- wb_state()
  out <- c("## Charts", "", if (length(charts)) unlist(lapply(charts, function(ch)
    c(describe_chart(ch, cells), ""))) else c("None.", ""))
  ignored <- data.frame(sheet_pos = integer(), rows = numeric(), cols = numeric())
  acc <- list(pivots = character(), comments = character(), text = character(),
              links = character(), headers = character())
  for (i in seq_len(nrow(wb$sheets))) {
    s <- read_sheet(wb, i, cells, st, media_dir, media_rel, used = used[i, ])
    out <- c(out, s$lines)
    if (!is.null(s$ignored)) ignored <- rbind(ignored, s$ignored)
    for (k in names(acc)) acc[[k]] <- c(acc[[k]], s[[k]])
  }
  # Media files no drawing placed (a cell picture, a background) are counted.
  media <- grep("^xl/media/[^/]+$", wb$nm, value = TRUE)
  add_other(st, "other_pictures", length(setdiff(media, names(st$media))))
  dn <- defined_name_lines(wb$wbx, wb$sheets$name, attr(charts, "xlchart_used"))
  emb <- embedded_lines(wb$root, wb$nm, st, media_dir, media_rel)
  count_parts(wb$nm, st)
  out <- c(out,
           section_md("## Pivot tables", acc$pivots),
           section_md("## Comments", acc$comments),
           section_md("## Text boxes", acc$text),
           "## Hyperlinks and defined names", "",
           section_md("### Hyperlinks", acc$links),
           section_md("### Defined names", dn),
           section_md("## Headers and footers", acc$headers),
           emb,
           section_md("## Other content", other_lines(st)))
  list(lines = out, other = other_counts(st), ignored = ignored)
}

# A .csv file's text as UTF-8: as is when valid, else read as Windows-1252
# (what Excel on Windows writes), else Latin-1. A byte-order mark is dropped.
csv_text <- function(path) {
  raw <- readBin(path, "raw", file.size(path))
  if (length(raw) >= 3 && identical(raw[1:3], as.raw(c(0xef, 0xbb, 0xbf)))) raw <- raw[-(1:3)]
  if (any(raw == as.raw(0))) wb_stop("the file holds NUL bytes")
  s <- rawToChar(raw)
  if (validUTF8(s)) { Encoding(s) <- "UTF-8"; return(s) }
  out <- iconv(s, "CP1252", "UTF-8")
  if (is.na(out)) out <- iconv(s, "latin1", "UTF-8")
  out
}

# The last line's terminator ends that line; it does not start a blank row.
csv_trim_end <- function(s) sub("\r?\n$", "", s)

# A .csv as one sheet, in the same layout. Every value is kept as written;
# blank lines keep their row numbers and a long row stays one row. A read
# problem is counted under Other content, never hidden.
csv_to_md <- function(path) {
  st <- wb_state()
  ignored <- data.frame(sheet_pos = integer(), rows = numeric(), cols = numeric())
  head <- "## Sheet: (the .csv file)"
  # Quoted text in a message could be cell content; it is left out.
  problem <- function(m) add_other(st, "csv_read_problems", detail = gsub("'[^']*'", "'...'", m))
  d <- withCallingHandlers(tryCatch({
    s <- csv_trim_end(csv_text(path))
    n <- suppressWarnings(utils::count.fields(textConnection(s), sep = ",", quote = "\"",
                                              blank.lines.skip = FALSE, comment.char = ""))
    n <- if (all(is.na(n))) 0L else max(n, na.rm = TRUE)
    if (!nzchar(s) || n == 0L) data.frame() else
      utils::read.csv(text = s, header = FALSE, colClasses = "character", na.strings = character(),
                      check.names = FALSE, strip.white = FALSE, fill = TRUE, blank.lines.skip = FALSE,
                      col.names = paste0("V", seq_len(n)), comment.char = "", encoding = "UTF-8")
  }, error = function(e) { problem(conditionMessage(e)); NULL }),
  warning = function(w) { problem(conditionMessage(w)); invokeRestart("muffleWarning") })
  oc <- function() if (sum(other_counts(st))) section_md("## Other content", other_lines(st))
  if (is.null(d)) {
    return(list(lines = c(head, "", "The .csv file could not be read; see Other content.", "", oc()),
                other = other_counts(st), ignored = ignored))
  }
  if (!nrow(d) || !ncol(d)) {
    return(list(lines = c(head, "", "No cell content.", "", oc()), other = other_counts(st), ignored = ignored))
  }
  r <- rep(seq_len(nrow(d)), ncol(d)); c <- rep(seq_len(ncol(d)), each = nrow(d))
  v <- unlist(d, use.names = FALSE)
  ne <- nzchar(v)
  used <- if (any(ne)) used_extent(r[ne], c[ne]) else c(nrow(d), ncol(d))
  if (used[1] * used[2] > RAW_CELL_CAP) {
    ignored <- data.frame(sheet_pos = 1L, rows = used[1], cols = used[2])
    return(list(lines = c(head, "", not_read_line(used[1], used[2]), "", oc()),
                other = other_counts(st), ignored = ignored))
  }
  list(lines = c(head, "", cell_table(r, c, v), "", oc()), other = other_counts(st), ignored = ignored)
}
