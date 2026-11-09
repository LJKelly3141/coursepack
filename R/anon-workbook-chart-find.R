# Finding the charts in a submitted workbook: walk sheets (worksheets and
# chart sheets) in workbook order, then each drawing in order, and record
# each chart's sheet and cell position. Any chart part not reached from a
# sheet is still listed, so no chart is dropped silently. Only the parts
# named in CHART_PARTS are extracted: docProps, persons, comments,
# vbaProject, externalLinks and connections are never read.

CHART_NS <- c(c = "http://schemas.openxmlformats.org/drawingml/2006/chart",
              a = "http://schemas.openxmlformats.org/drawingml/2006/main",
              r = "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
              xdr = "http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing",
              cx = "http://schemas.microsoft.com/office/drawing/2014/chartex",
              m = "http://schemas.openxmlformats.org/spreadsheetml/2006/main")

CHART_PARTS <- "^xl/(workbook\\.xml|_rels/workbook\\.xml\\.rels|(worksheets|chartsheets)/[^/]+\\.xml|(worksheets|chartsheets)/_rels/|drawings/[^/]+\\.xml$|drawings/_rels/|charts/)"
CHART_FILES <- "^xl/charts/(chart|chartEx)[0-9]*\\.xml$"

# Resolve a relationship target against the folder of the part that owns it.
part_path <- function(base_dir, target) {
  if (startsWith(target, "/")) return(sub("^/", "", target))
  parts <- strsplit(file.path(base_dir, target), "/", fixed = TRUE)[[1]]
  out <- character()
  for (p in parts) {
    if (p == "..") out <- utils::head(out, -1) else if (p != "." && p != "") out <- c(out, p)
  }
  paste(out, collapse = "/")
}

# Relationship id -> resolved part path, for the part at owner.
part_rels <- function(root, owner) {
  rp <- file.path(root, dirname(owner), "_rels", paste0(basename(owner), ".rels"))
  if (!file.exists(rp)) return(character())
  d <- xml2::xml_ns_strip(xml2::read_xml(rp))
  r <- xml2::xml_find_all(d, "//Relationship[not(@TargetMode='External')]")
  stats::setNames(vapply(xml2::xml_attr(r, "Target"), part_path, "",
                         base_dir = dirname(owner)),
                  xml2::xml_attr(r, "Id"))
}

col_letters <- function(n) {
  s <- ""
  while (n > 0) { s <- paste0(LETTERS[(n - 1) %% 26 + 1], s); n <- (n - 1) %/% 26 }
  s
}

# Walk sizes (px) from a 0-based start index and offset (EMU) through len
# EMU; return the 0-based end index and the EMU offset into it.
walk_cells <- function(start, off, len, size_px) {
  i <- start; left <- off + len
  repeat {
    w <- size_px(i) * 9525
    if (left < w) return(c(i, left))
    left <- left - w; i <- i + 1
  }
}

# "G3:L17": an end edge exactly on a cell boundary ends in the cell before.
anchor_ref <- function(fc, fr, tc, tco, tr, tro) {
  if (tco == 0 && tc > fc) tc <- tc - 1
  if (tro == 0 && tr > fr) tr <- tr - 1
  sprintf("%s%d:%s%d", col_letters(fc + 1), fr + 1, col_letters(tc + 1), tr + 1)
}

anchor_of <- function(an, sheet_doc) {
  num <- function(xp) as.numeric(xml2::xml_text(xml2::xml_find_first(an, xp, CHART_NS)))
  kind <- xml2::xml_name(an)
  if (kind == "twoCellAnchor") {
    return(anchor_ref(num("xdr:from/xdr:col"), num("xdr:from/xdr:row"),
                      num("xdr:to/xdr:col"), num("xdr:to/xdr:colOff"),
                      num("xdr:to/xdr:row"), num("xdr:to/xdr:rowOff")))
  }
  ext <- xml2::xml_find_first(an, "xdr:ext", CHART_NS)
  cx <- as.numeric(xml2::xml_attr(ext, "cx")); cy <- as.numeric(xml2::xml_attr(ext, "cy"))
  if (kind == "oneCellAnchor") {
    fc <- num("xdr:from/xdr:col"); fco <- num("xdr:from/xdr:colOff")
    fr <- num("xdr:from/xdr:row"); fro <- num("xdr:from/xdr:rowOff")
  } else {
    pos <- xml2::xml_find_first(an, "xdr:pos", CHART_NS)
    fc <- 0; fr <- 0
    fco <- as.numeric(xml2::xml_attr(pos, "x")); fro <- as.numeric(xml2::xml_attr(pos, "y"))
  }
  cols <- xml2::xml_find_all(sheet_doc, "//m:cols/m:col[@width]", CHART_NS)
  cmin <- as.numeric(xml2::xml_attr(cols, "min")); cmax <- as.numeric(xml2::xml_attr(cols, "max"))
  cw <- as.numeric(xml2::xml_attr(cols, "width"))
  rows <- xml2::xml_find_all(sheet_doc, "//m:sheetData/m:row[@ht]", CHART_NS)
  rr <- as.numeric(xml2::xml_attr(rows, "r")); rh <- as.numeric(xml2::xml_attr(rows, "ht"))
  col_px <- function(i) {
    k <- which(cmin <= i + 1 & cmax >= i + 1)
    if (length(k)) floor(cw[k[1]] * 7 + 5) else 64
  }
  row_px <- function(i) {
    k <- which(rr == i + 1)
    if (length(k)) rh[k[1]] * 96 / 72 else 20
  }
  ec <- walk_cells(fc, fco, cx, col_px); er <- walk_cells(fr, fro, cy, row_px)
  anchor_ref(fc, fr, ec[1], ec[2], er[1], er[2])
}

# Text of every paragraph in a c:userShapes part (text boxes on the chart).
shape_text <- function(root, path) {
  if (is.na(path) || !file.exists(file.path(root, path))) return(character())
  d <- xml2::read_xml(file.path(root, path))
  t <- vapply(xml2::xml_find_all(d, "//a:p", CHART_NS),
              function(p) paste(xml2::xml_text(xml2::xml_find_all(p, ".//a:t", CHART_NS)), collapse = ""), "")
  t[nzchar(trimws(t))]
}

# One chart entry; a part that is missing or unreached gets `problem`.
chart_entry <- function(root, cp, sheet, anchor, problem = NULL) {
  if (!is.null(problem) || !file.exists(file.path(root, cp))) {
    return(list(sheet = sheet, anchor = anchor, xml = NULL, shapes = character(),
                problem = if (is.null(problem)) sprintf("chart part %s (missing from the file)", cp) else problem))
  }
  cd <- xml2::read_xml(file.path(root, cp))
  us <- xml2::xml_find_first(cd, "/*/c:userShapes", CHART_NS)
  shapes <- if (inherits(us, "xml_missing")) character() else
    shape_text(root, part_rels(root, cp)[xml2::xml_attr(us, "r:id", CHART_NS)])
  # The part's own text, not a re-serialised (re-indented) copy.
  raw <- readBin(file.path(root, cp), "raw", file.size(file.path(root, cp)))
  xml <- rawToChar(raw)
  Encoding(xml) <- "UTF-8"
  list(sheet = sheet, anchor = anchor, xml = xml, shapes = shapes)
}

# Zip entry names that would climb out of the extraction folder.
unsafe_part_name <- function(nm) grepl("(^|[/\\\\])\\.\\.([/\\\\]|$)|^[/\\\\]|^[A-Za-z]:", nm)

# One entry per chart, in sheet order then drawing order, then any chart
# part no sheet reaches: list(n, sheet, anchor, xml, shapes[, problem]).
workbook_charts <- function(xlsx) {
  nm <- utils::unzip(xlsx, list = TRUE)$Name
  if (any(unsafe_part_name(nm))) {
    wb_stop("workbook contains a part whose path climbs out of the file (\"..\" or a leading slash); refused")
  }
  root <- tempfile("wbchart_")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  utils::unzip(xlsx, files = grep(CHART_PARTS, nm, value = TRUE), exdir = root)
  wb <- xml2::read_xml(file.path(root, "xl/workbook.xml"))
  if (any(grepl("^http://purl\\.oclc\\.org/ooxml/", xml2::xml_ns(wb)))) {
    # The advice names the file's own type (xlsx or xlsm), never the file.
    ext <- tolower(tools::file_ext(xlsx))
    wb_stop(sprintf("workbook saved in Strict Open XML format; re-save it as a normal .xlsx workbook, or pass %s in skip_types",
                    if (ext %in% WORKBOOK_EXTS) sprintf("\"%s\"", ext) else "the file's type"))
  }
  wrel <- part_rels(root, "xl/workbook.xml")
  out <- list(); seen <- character()
  for (s in xml2::xml_find_all(wb, "//m:sheets/m:sheet", CHART_NS)) {
    sp <- wrel[xml2::xml_attr(s, "r:id", CHART_NS)]
    if (is.na(sp) || !file.exists(file.path(root, sp))) next
    sd <- xml2::read_xml(file.path(root, sp))
    srel <- part_rels(root, sp)
    is_chartsheet <- grepl("^xl/chartsheets/", sp)
    for (dr in xml2::xml_find_all(sd, "//m:drawing", CHART_NS)) {
      dp <- srel[xml2::xml_attr(dr, "r:id", CHART_NS)]
      if (is.na(dp) || !file.exists(file.path(root, dp))) next
      dd <- xml2::read_xml(file.path(root, dp))
      drel <- part_rels(root, dp)
      for (top in xml2::xml_children(dd)) {
        # A group (xdr:grpSp) can hold several charts under one anchor: each
        # is its own entry, all at the group's position.
        refs <- xml2::xml_find_all(top, ".//c:chart | .//cx:chart", CHART_NS)
        if (!length(refs)) next
        an <- if (grepl("Anchor$", xml2::xml_name(top))) top else
          xml2::xml_find_first(top, ".//*[substring(local-name(), string-length(local-name()) - 5) = 'Anchor']")
        anchor <- if (is_chartsheet) "whole sheet" else
          if (inherits(an, "xml_missing")) "position unknown" else anchor_of(an, sd)
        for (ref in refs) {
          cp <- drel[xml2::xml_attr(ref, "r:id", CHART_NS)]
          cp <- if (is.na(cp)) "(no relationship)" else unname(cp)
          seen <- c(seen, cp)
          out[[length(out) + 1]] <- chart_entry(root, cp, xml2::xml_attr(s, "name"), anchor)
        }
      }
    }
  }
  for (cp in setdiff(sort(grep(CHART_FILES, nm, value = TRUE)), seen)) {
    out[[length(out) + 1]] <- chart_entry(root, cp, NA, NA,
                                          sprintf("chart part %s (not reached from any sheet)", cp))
  }
  # Excel writes a newer chart type's data formulas as hidden defined names
  # (_xlchart.v1.0 ...); each entry carries them so they resolve to ranges.
  dn <- xml2::xml_find_all(wb, "//m:definedNames/m:definedName[starts-with(@name, '_xlchart.')]", CHART_NS)
  xlnames <- stats::setNames(sub("^=", "", xml2::xml_text(dn)), xml2::xml_attr(dn, "name"))
  for (i in seq_along(out)) { out[[i]]$n <- i; out[[i]]$xlnames <- xlnames }
  # The _xlchart names some chart's cx:f refers to: only these are left out
  # of the defined names list (an unused one is listed like any other).
  # as.character(): with no charts unlist() gives NULL, which startsWith() rejects.
  used <- as.character(unlist(lapply(out, function(e) {
    if (is.null(e$xml)) return(character())
    trimws(xml2::xml_text(xml2::xml_find_all(xml2::read_xml(e$xml), "//cx:f", CHART_NS)))
  })))
  attr(out, "xlchart_used") <- intersect(unique(used[startsWith(used, "_xlchart.")]), names(xlnames))
  out
}
