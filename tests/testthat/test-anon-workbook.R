test_that("fake_workbook builds a readable xlsx", {
  td <- withr::local_tempdir()
  p <- fake_workbook(td)
  expect_true(file.exists(p))
  expect_equal(tidyxl::xlsx_sheet_names(p),
               c("Summary", "Pat Quill data", "Hidden calc"))
  nm <- utils::unzip(p, list = TRUE)$Name
  expect_equal(nm[1], "[Content_Types].xml")
  expect_true("xl/charts/chart1.xml" %in% nm)
  expect_true("xl/charts/chart2.xml" %in% nm)
  expect_false("xl/vbaProject.bin" %in% nm)
})

test_that("fake_workbook(macro = TRUE) keeps the macro project", {
  td <- withr::local_tempdir()
  p <- fake_workbook(td, name = "quillpat_1001_5001_partb.xlsm", macro = TRUE)
  expect_true("xl/vbaProject.bin" %in% utils::unzip(p, list = TRUE)$Name)
  expect_no_error(tidyxl::xlsx_sheet_names(p))
})

test_that("fake_hcahps points at the source csv", {
  expect_true(file.exists(fake_hcahps()))
})

# Task 3: types, .xls refusal, skip_types.
touch_files <- function(a, names) {
  for (n in names) writeLines("x", file.path(a, n))
}

test_that("xls stops with re-save advice", {
  skip_if_no("tesseract")
  cc <- anon_course(); a <- a1_assignment(cc)
  mk_docx(file.path(a, "quillpat_1001_5002_a.docx"), "Hello")
  touch_files(a, "quillpat_1001_5001_b.xls")
  mk_docx(file.path(a, "riveramorgan_1002_5003_a.docx"), "Hello")
  msg <- errors_with(quiet(anonymize(cc$proj, "semester/A1", dict = NULL)))
  expect_match(msg, "S0[0-9] \\(file1\\).*re-save as .xlsx.*skip_types")
  expect_false(grepl("quill", msg, ignore.case = TRUE))
})

test_that("skip_types drops a type and counts it", {
  td <- withr::local_tempdir()
  touch_files(td, c("quillpat_1001_5001_a.docx", "quillpat_1001_5002_b.xls"))
  for (st in c("xls", ".XLS")) {
    s <- list_submissions(td, skip_types = st)
    expect_false(any(tolower(tools::file_ext(s$original)) == "xls"))
    expect_equal(nrow(s), 1)
    expect_equal(attr(s, "skipped")[["xls"]], 1L)
  }
  expect_length(attr(list_submissions(td), "skipped"), 0)
})

test_that("workbook-only student targets the workbook", {
  cc <- anon_course(); a <- a1_assignment(cc)
  touch_files(a, c("quillpat_1001_5001_a.xlsx", "riveramorgan_1002_5002_a.xlsx",
                   "riveramorgan_1002_5003_a.docx"))
  key <- read_key(file.path(a, "anon_key.csv"))
  s <- assign_files(list_submissions(a), key)
  q <- s[s$canvas_id == "1001", ]
  expect_true(q$target)
  r <- s[s$canvas_id == "1002", ]
  expect_equal(tools::file_ext(r$original[r$target]), "docx")
  expect_equal(sum(r$target), 1)
})

test_that("all files skipped still stops", {
  cc <- anon_course(); a <- a1_assignment(cc)
  touch_files(a, c("quillpat_1001_5001_a.xls", "riveramorgan_1002_5002_a.docx"))
  key <- read_key(file.path(a, "anon_key.csv"))
  msg <- errors_with(assign_files(list_submissions(a, "xls"), key))
  expect_match(msg, "no document")
  expect_false(grepl("quill", msg, ignore.case = TRUE))
})

test_that("a not-in-key student with only a skipped file still stops", {
  cc <- anon_course(); a <- a1_assignment(cc)
  touch_files(a, c("quillpat_1001_5001_a.docx", "stranger_7777_5002_a.xls"))
  key <- read_key(file.path(a, "anon_key.csv"))
  expect_match(errors_with(assign_files(list_submissions(a, "xls"), key)), "not in the key")
})

test_that("an empty skip_types entry drops nothing", {
  td <- withr::local_tempdir()
  touch_files(td, c("quillpat_1001_5001_a.docx", "quillpat_1001_5002_noext"))
  s <- list_submissions(td, skip_types = c("", "."))
  expect_equal(nrow(s), 2)
  expect_length(attr(s, "skipped"), 0)
})

test_that("convert_to_text refuses .xls with advice", {
  td <- withr::local_tempdir()
  p <- file.path(td, "old.xls"); writeLines("x", p)
  msg <- errors_with(convert_to_text(p, file.path(td, "o", "file1.md"), file.path(td, "o", "file1_media")))
  expect_match(msg, "re-save as .xlsx.*skip_types")
})

# Task 4: charts described from the chart XML.
chart_fixture <- function() {
  td <- withr::local_tempdir(.local_envir = parent.frame())
  p <- fake_workbook(td)
  list(charts = workbook_charts(p), cells = tidyxl::xlsx_cells(p))
}

test_that("charts found in order with anchors", {
  f <- chart_fixture()
  expect_length(f$charts, 2)
  expect_equal(f$charts[[1]]$sheet, "Summary")
  for (ch in f$charts) expect_match(ch$anchor, "^[A-Z]+[0-9]+:[A-Z]+[0-9]+$")
  expect_equal(f$charts[[1]]$anchor, "G3:L17")
  expect_equal(f$charts[[2]]$anchor, "N3:S17")
})

test_that("column chart described", {
  f <- chart_fixture()
  md <- describe_chart(f$charts[[1]], f$cells)
  txt <- paste(md, collapse = "\n")
  expect_match(md[1], "^### Chart 1 \\(sheet Summary, G3:L17\\)$")
  expect_match(txt, "column", fixed = TRUE)
  expect_match(txt, "Chart by Pat Quill", fixed = TRUE)
  expect_match(txt, "Score (points)", fixed = TRUE)
  scale <- "  - scale: min automatic, max automatic, major unit automatic, minor unit automatic"
  expect_equal(sum(md == scale), 2L)
  expect_true("- Axis: value axis, primary, left" %in% md)
  expect_match(txt, "Categories (plotted order): Mo, Pat, Jordan", fixed = TRUE)
  expect_match(txt, "values: 10, 20, 30", fixed = TRUE)
  expect_false(grepl("—", txt))
  expect_false(grepl("not described", txt))
})

test_that("values from cells when no cache", {
  f <- chart_fixture()
  txt <- paste(describe_chart(f$charts[[2]], f$cells), collapse = "\n")
  expect_match(txt, "values: 10, 20, 30 (from cells)", fixed = TRUE)
  expect_match(txt, "values: 25, 25, 25 (from cells)", fixed = TRUE)
  ch <- f$charts[[2]]
  ch$xml <- gsub("Summary!$D$7:$D$9", "Missing!$D$7:$D$9", ch$xml, fixed = TRUE)
  txt <- paste(describe_chart(ch, f$cells), collapse = "\n")
  expect_match(txt, "Missing!$D$7:$D$9", fixed = TRUE)
  expect_match(txt, "values not available", fixed = TRUE)
})

test_that("combo and reference line", {
  f <- chart_fixture()
  txt <- paste(describe_chart(f$charts[[2]], f$cells), collapse = "\n")
  expect_match(txt, "Part 1: column chart, clustered", fixed = TRUE)
  expect_match(txt, "Part 2: line chart", fixed = TRUE)
  expect_match(txt, "Part 2: line chart, standard, on secondary axes", fixed = TRUE)
  expect_match(txt, "- Axis: value axis, secondary, right\n", fixed = TRUE)
  expect_false(grepl("Part 1: [^\n]*secondary", txt))
  expect_match(txt, "constant: likely reference line", fixed = TRUE)
  expect_equal(lengths(regmatches(txt, gregexpr("likely reference line", txt))), 1L)
})

test_that("source line text box", {
  f <- chart_fixture()
  txt <- paste(describe_chart(f$charts[[1]], f$cells), collapse = "\n")
  expect_match(txt, "Source: Pat Quill", fixed = TRUE)
})

test_that("unknown element named", {
  f <- chart_fixture()
  ch <- f$charts[[1]]
  ch$xml <- sub("<c:layout/>", "<c:layout/><c:foo/>", ch$xml, fixed = TRUE)
  ch$xml <- sub("<c:plotVisOnly", "<c:bar2/><c:plotVisOnly", ch$xml, fixed = TRUE)
  txt <- paste(describe_chart(ch, f$cells), collapse = "\n")
  expect_match(txt, "not described: foo", fixed = TRUE)
  expect_match(txt, "not described: bar2", fixed = TRUE)
})

# Task 4 fix round 1. wb_variant() unzips the fixture workbook, lets edit()
# change the parts in place, and zips it again.
wb_variant <- function(edit, env = parent.frame()) {
  td <- withr::local_tempdir(.local_envir = env)
  p <- fake_workbook(td)
  parts <- file.path(td, "parts"); dir.create(parts)
  utils::unzip(p, exdir = parts)
  edit(parts)
  unlink(p)
  old <- setwd(parts); on.exit(setwd(old))
  utils::zip(p, list.files(".", recursive = TRUE, all.files = TRUE), flags = "-X -q")
  p
}
put <- function(parts, rel, lines) {
  dir.create(dirname(file.path(parts, rel)), recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, file.path(parts, rel))
}
change <- function(parts, rel, f) {
  x <- readLines(file.path(parts, rel), warn = FALSE)
  writeLines(f(x), file.path(parts, rel))
}
md_of <- function(chart, cells = NULL) paste(describe_chart(chart, cells), collapse = "\n")

test_that("a chart moved to a chart sheet is described", {
  p <- wb_variant(function(parts) {
    change(parts, "xl/drawings/drawing1.xml", function(x) x[!grepl("name=\"Chart 2\"", x)])
    change(parts, "xl/workbook.xml", function(x) sub("</sheets>",
      "<sheet name=\"Chart1\" sheetId=\"4\" r:id=\"rId11\"/></sheets>", x, fixed = TRUE))
    change(parts, "xl/_rels/workbook.xml.rels", function(x) sub("</Relationships>",
      "<Relationship Id=\"rId11\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/chartsheet\" Target=\"chartsheets/sheet1.xml\"/></Relationships>", x, fixed = TRUE))
    put(parts, "xl/chartsheets/sheet1.xml", '<chartsheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheetViews><sheetView workbookViewId="0"/></sheetViews><drawing r:id="rId1"/></chartsheet>')
    put(parts, "xl/chartsheets/_rels/sheet1.xml.rels", '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing3.xml"/></Relationships>')
    put(parts, "xl/drawings/drawing3.xml", '<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"><xdr:absoluteAnchor><xdr:pos x="0" y="0"/><xdr:ext cx="8670000" cy="6300000"/><xdr:graphicFrame macro=""><xdr:nvGraphicFramePr><xdr:cNvPr id="2" name="Chart 1"/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr><xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></xdr:xfrm><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart r:id="rId1"/></a:graphicData></a:graphic></xdr:graphicFrame><xdr:clientData/></xdr:absoluteAnchor></xdr:wsDr>')
    put(parts, "xl/drawings/_rels/drawing3.xml.rels", '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="../charts/chart2.xml"/></Relationships>')
  })
  ch <- workbook_charts(p)
  expect_length(ch, 2)
  expect_equal(ch[[2]]$sheet, "Chart1")
  expect_equal(ch[[2]]$anchor, "whole sheet")
  txt <- md_of(ch[[2]], tidyxl::xlsx_cells(p))
  expect_match(txt, "### Chart 2 (sheet Chart1, whole sheet)", fixed = TRUE)
  expect_match(txt, "values: 25, 25, 25 (from cells)", fixed = TRUE)
})

test_that("an orphan chart part is reported", {
  p <- wb_variant(function(parts) {
    file.copy(file.path(parts, "xl/charts/chart1.xml"), file.path(parts, "xl/charts/chart9.xml"))
  })
  ch <- workbook_charts(p)
  expect_length(ch, 3)
  txt <- md_of(ch[[3]])
  expect_match(txt, "### Chart 3 (not on any sheet)", fixed = TRUE)
  expect_match(txt, "not described: chart part xl/charts/chart9.xml (not reached from any sheet)", fixed = TRUE)
})

test_that("strict workbook stops without naming the file", {
  p <- wb_variant(function(parts) {
    change(parts, "xl/workbook.xml", function(x) sub("http://schemas.openxmlformats.org/spreadsheetml/2006/main",
      "http://purl.oclc.org/ooxml/spreadsheetml/main", x, fixed = TRUE))
  })
  msg <- errors_with(workbook_charts(p))
  expect_equal(msg, "workbook saved in Strict Open XML format; re-save it as a normal .xlsx workbook, or pass \"xlsx\" in skip_types")
  expect_false(grepl("quill|/", msg, ignore.case = TRUE))
})

test_that("extLst contents are named unless cosmetic", {
  f <- chart_fixture()
  ch <- f$charts[[1]]
  c15 <- 'xmlns:c15="http://schemas.microsoft.com/office/drawing/2012/chart"'
  c16 <- 'xmlns:c16="http://schemas.microsoft.com/office/drawing/2014/chart"'
  ser_ext <- sprintf('<c:extLst><c:ext uri="{02D57815-91ED-43cb-92C2-25804820EDAC}" %s><c15:datalabelsRange><c15:f>Summary!$C$7:$C$9</c15:f></c15:datalabelsRange></c:ext><c:ext uri="{C3380CC4-5D6E-409C-BE32-E72D297353CC}" %s><c16:uniqueId val="{00000000-0001}"/></c:ext></c:extLst></c:ser>', c15, c16)
  grp_ext <- sprintf('<c:axId val="112"/><c:extLst><c:ext uri="{02D57815-91ED-43cb-92C2-25804820EDAC}" %s><c15:filteredBarSeries><c15:ser/></c15:filteredBarSeries></c:ext></c:extLst></c:barChart>', c15)
  ch$xml <- sub("</c:ser>", ser_ext, ch$xml, fixed = TRUE)
  ch$xml <- sub('<c:axId val="112"/></c:barChart>', grp_ext, ch$xml, fixed = TRUE)
  txt <- md_of(ch, f$cells)
  expect_match(txt, "not described: c15:datalabelsRange", fixed = TRUE)
  expect_match(txt, "not described: c15:filteredBarSeries", fixed = TRUE)
  expect_false(grepl("uniqueId", txt))
})

test_that("categories follow the plotted order", {
  f <- chart_fixture()
  ch <- f$charts[[1]]
  rev_cat <- function(x) sub('<c:axId val="111"/><c:scaling><c:orientation val="minMax"/>',
                             '<c:axId val="111"/><c:scaling><c:orientation val="maxMin"/>', x, fixed = TRUE)
  bar <- function(x) sub('<c:barDir val="col"/>', '<c:barDir val="bar"/>', x, fixed = TRUE)
  cats <- function(x) { ch$xml <- x; grep("^- Categories", describe_chart(ch, f$cells), value = TRUE) }
  expect_equal(cats(rev_cat(ch$xml)), "- Categories (plotted order): Jordan, Pat, Mo (left to right)")
  expect_equal(cats(bar(ch$xml)), "- Categories (plotted order): Jordan, Pat, Mo (top to bottom)")
  expect_equal(cats(bar(rev_cat(ch$xml))), "- Categories (plotted order): Mo, Pat, Jordan (top to bottom)")
})

test_that("missing categories and empty caches", {
  f <- chart_fixture()
  ch <- f$charts[[1]]
  ch$xml <- sub("<c:cat>.*</c:cat>", "", ch$xml)
  expect_match(md_of(ch, f$cells), "- Categories (plotted order): not available", fixed = TRUE)
  ch <- f$charts[[1]]
  ch$xml <- sub("<c:numCache>.*</c:numCache>", "<c:numCache><c:ptCount val=\"0\"/></c:numCache>", ch$xml)
  expect_match(md_of(ch, f$cells), "values: 10, 20, 30 (from cells)", fixed = TRUE)
  expect_match(md_of(ch, NULL), "values: values not available", fixed = TRUE)
})

test_that("data label details are described or named", {
  f <- chart_fixture()
  ch <- f$charts[[1]]
  dl <- '<c:dLbls><c:dLbl><c:idx val="1"/><c:tx><c:rich><a:bodyPr/><a:p><a:r><a:t>Best</a:t></a:r></a:p></c:rich></c:tx><c:showVal val="1"/></c:dLbl><c:numFmt formatCode="0.0" sourceLinked="0"/><c:showVal val="1"/><c:zap/></c:dLbls></c:ser>'
  ch$xml <- sub("</c:ser>", dl, ch$xml, fixed = TRUE)
  txt <- md_of(ch, f$cells)
  expect_match(txt, "  - data labels: on, showing value", fixed = TRUE)
  expect_match(txt, "    - label number format: 0.0", fixed = TRUE)
  expect_match(txt, "    - custom label on point 2: Best", fixed = TRUE)
  expect_match(txt, "    - not described: zap", fixed = TRUE)
})

test_that("zip entries that climb out are refused", {
  expect_equal(unsafe_part_name(c("xl/charts/chart1.xml", "../evil.xml", "xl/../../x",
                                  "/etc/x", "a\\..\\b", "C:/x", "xl/a..b.xml")),
               c(FALSE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE))
})

# Task 5: the rest of the workbook read into markdown.
wb_md <- function(macro = FALSE, p = NULL, env = parent.frame()) {
  td <- withr::local_tempdir(.local_envir = env)
  if (is.null(p)) {
    p <- fake_workbook(td, name = if (macro) "quillpat_1001_5001_partb.xlsm" else
      "quillpat_1001_5001_partb.xlsx", macro = macro)
  }
  media <- file.path(td, "file1_media")
  r <- workbook_to_md(p, media, "file1_media")
  r$media_dir <- media
  r
}
# Lines under a `## ` heading, up to the next one.
section <- function(lines, heading) {
  i <- which(lines == heading)
  if (!length(i)) return(character())
  rest <- lines[-seq_len(i[1])]
  j <- which(startsWith(rest, "## "))
  if (length(j)) rest[seq_len(j[1] - 1)] else rest
}

test_that("charts come first", {
  r <- wb_md()
  h <- grep("^## ", r$lines, value = TRUE)
  expect_equal(h[1], "## Charts")
  ch <- section(r$lines, "## Charts")
  expect_true(any(grepl("^### Chart 1 \\(sheet Summary, G3:L17\\)$", ch)))
  expect_true(any(grepl("^### Chart 2 \\(sheet Summary, N3:S17\\)$", ch)))
})

test_that("sheets in order with hidden marks", {
  r <- wb_md()
  h <- grep("^## Sheet: ", r$lines, value = TRUE)
  expect_equal(h, c("## Sheet: Summary", "## Sheet: Pat Quill data",
                    "## Sheet: Hidden calc (very hidden)"))
  s1 <- section(r$lines, "## Sheet: Summary")
  expect_true("Hidden rows: 4" %in% s1)
  expect_true("Hidden columns: D" %in% s1)
  expect_true(any(grepl("hidden row note", s1, fixed = TRUE)))
  expect_true("Autofilter: A6:B9" %in% s1)
  expect_true(any(grepl("secret calc", section(r$lines, "## Sheet: Hidden calc (very hidden)"))))
})

test_that("formulas beside values", {
  r <- wb_md()
  expect_true(any(grepl("268 `=SUM('Pat Quill data'!B2:B5)`", r$lines, fixed = TRUE)))
  # Shared formulas are written out for every cell they fill.
  expect_true(any(grepl("40 `=B8*2`", r$lines, fixed = TRUE)))
  expect_true(any(grepl("60 `=B9*2`", r$lines, fixed = TRUE)))
})

test_that("split run read whole", {
  r <- wb_md()
  expect_equal(sum(grepl("| Pat Quill |", r$lines, fixed = TRUE)), 1)
  expect_false(any(grepl("| Pat |  Quill", r$lines, fixed = TRUE)))
})

test_that("pivot, comment, text box, hyperlink, defined name, header present", {
  r <- wb_md()
  pv <- paste(section(r$lines, "## Pivot tables"), collapse = "\n")
  expect_match(pv, "PivotTable1", fixed = TRUE)
  expect_match(pv, "G1:H5", fixed = TRUE)
  expect_match(pv, "'Pat Quill data'!D1:E31", fixed = TRUE)
  expect_match(pv, "rows: state", fixed = TRUE)
  expect_match(pv, "Sum of surveys", fixed = TRUE)
  cm <- paste(section(r$lines, "## Comments"), collapse = "\n")
  expect_match(cm, "Summary!A1 (threaded comment): Check this total", fixed = TRUE)
  expect_match(cm, "Summary!A2 (note): [author removed]: Legacy note from the author", fixed = TRUE)
  expect_false(grepl("[Threaded comment]", cm, fixed = TRUE))
  expect_false(grepl("Pat Quill", cm, fixed = TRUE))
  tb <- paste(section(r$lines, "## Text boxes"), collapse = "\n")
  expect_match(tb, "prompt log: Pat Quill asked the assistant", fixed = TRUE)
  hl <- paste(section(r$lines, "## Hyperlinks and defined names"), collapse = "\n")
  expect_match(hl, "Contact the author", fixed = TRUE)
  expect_match(hl, "mailto:pat.quill@example.edu", fixed = TRUE)
  expect_match(hl, "PatQuillRange: 'Pat Quill data'!$B$2:$B$31", fixed = TRUE)
  hf <- paste(section(r$lines, "## Headers and footers"), collapse = "\n")
  expect_match(hf, "left: Pat Quill", fixed = TRUE)
  expect_match(hf, "center: Report", fixed = TRUE)
  # Fixed order of the sections after the sheets.
  h <- grep("^## ", r$lines, value = TRUE)
  rest <- h[!startsWith(h, "## Sheet: ")][-1]
  expect_equal(rest, c("## Pivot tables", "## Comments", "## Text boxes",
                       "## Hyperlinks and defined names", "## Headers and footers",
                       "## Other content"))
})

test_that("metadata never read", {
  for (m in c(FALSE, TRUE)) {
    r <- wb_md(macro = m)
    txt <- paste(r$lines, collapse = "\n")
    for (s in c("Rivera", "Quill LLC", "patquill/secret", "XQ1001", "SQLOLEDB",
                "Campus data", "7C3D1A10", "5A1F0C2E", "PLACEHOLDER")) {
      expect_false(grepl(s, txt, fixed = TRUE), info = s)
    }
    expect_equal(r$other[["macros"]], as.integer(m))
    expect_equal(r$other[["external_links"]], 1L)
    expect_equal(r$other[["connections"]], 1L)
  }
})

test_that("embedded picture lands in media", {
  r <- wb_md()
  expect_true(file.exists(file.path(r$media_dir, "image1.png")))
  s1 <- section(r$lines, "## Sheet: Summary")
  expect_true(any(grepl("](file1_media/image1.png)", s1, fixed = TRUE)))
  expect_true(any(grepl("signature image", s1, fixed = TRUE)))
})

test_that("nothing silently dropped", {
  r <- wb_md()
  oc <- paste(section(r$lines, "## Other content"), collapse = "\n")
  expect_match(oc, "form control", fixed = TRUE)
  expect_match(oc, "sparkline", fixed = TRUE)
  expect_match(oc, "embedded object", fixed = TRUE)
  expect_equal(r$other[["form_controls"]], 1L)
  expect_equal(r$other[["sparklines"]], 1L)
  expect_equal(r$other[["embedded_objects"]], 1L)
  expect_false(any(grepl("—", r$lines)))
})

test_that("an embedded Word document is converted", {
  skip_if_no("pandoc")
  src <- withr::local_tempdir()
  png <- mk_png(file.path(src, "pic.png"))
  doc <- file.path(src, "inner.docx")
  mk_docx(doc, c("# Memo", "", "Embedded essay text by Pat Quill.", "", sprintf("![](%s)", png)))
  p <- wb_variant(function(parts) {
    dir.create(file.path(parts, "xl", "embeddings"), showWarnings = FALSE)
    file.copy(doc, file.path(parts, "xl", "embeddings", "Microsoft_Word_Document.docx"))
  })
  r <- wb_md(p = p)
  ed <- section(r$lines, "## Embedded document 1")
  expect_true(any(grepl("Embedded essay text by Pat Quill.", ed, fixed = TRUE)))
  expect_true(any(grepl("](file1_media/embedded1/media/", ed, fixed = TRUE)))
  expect_length(list.files(file.path(r$media_dir, "embedded1"), recursive = TRUE, pattern = "\\.png$"), 1)
  expect_false(any(grepl("\\.md$", list.files(r$media_dir, recursive = TRUE))))
  # The placeholder OLE object is still only counted.
  expect_equal(r$other[["embedded_objects"]], 1L)
  h <- grep("^## ", r$lines, value = TRUE)
  expect_equal(h[length(h) - 1], "## Embedded document 1")
})

test_that("csv reads as one sheet", {
  r <- csv_to_md(fake_hcahps())
  expect_equal(sum(grepl("^## Sheet:", r$lines)), 1)
  rows <- grep("^\\| [0-9]+ \\|", r$lines, value = TRUE)
  expect_length(rows, 31)
  expect_match(rows[1], "facility_id", fixed = TRUE)
  expect_equal(nrow(r$ignored), 0)
})

# Raw-data cap: a sheet or csv over RAW_CELL_CAP (4,000) cells is not read.
# `rows` x `cols` of invented strings "zqRxC"; B2:B4 are 10, 20, 30.
big_variant <- function(rows, cols, chart_on_big = FALSE, drop_cache = FALSE, dim = NULL, link = FALSE, env = parent.frame()) {
  wb_variant(function(parts) {
    cell <- function(r, c) {
      a <- paste0(LETTERS[c], r)
      if (c == 2 && r >= 2 && r <= 4) return(sprintf('<c r="%s"><v>%d</v></c>', a, (r - 1) * 10))
      sprintf('<c r="%s" t="inlineStr"><is><t>zq%dx%d</t></is></c>', a, r, c)
    }
    body <- paste0(vapply(seq_len(rows), function(r) paste0('<row r="', r, '">',
      paste(vapply(seq_len(cols), function(c) cell(r, c), ""), collapse = ""), '</row>'), ""), collapse = "")
    change(parts, "xl/worksheets/sheet2.xml", function(x) {
      x <- paste(x, collapse = "\n")
      d <- if (is.null(dim)) sprintf('<dimension ref="A1:%s%d"/>', LETTERS[cols], rows) else if (nzchar(dim)) sprintf('<dimension ref="%s"/>', dim) else ""
      x <- sub('<dimension ref="[^"]*"/>', d, x)
      lk <- if (link) '<hyperlinks><hyperlink ref="A1" location="Summary!A1" display="zqlinktext"/></hyperlinks>' else ""
      sub("<sheetData>.*</sheetData>", paste0("<sheetData>", body, "</sheetData>", lk), x)
    })
    if (chart_on_big) change(parts, "xl/charts/chart1.xml", function(x) {
      x <- gsub("Summary!\\$A\\$7:\\$A\\$9", "'Pat Quill data'!$A$2:$A$4", x)
      x <- gsub("Summary!\\$B\\$7:\\$B\\$9", "'Pat Quill data'!$B$2:$B$4", x)
      if (drop_cache) x <- gsub("<c:numCache>.*?</c:numCache>", "", x)
      x
    })
  }, env = env)
}

test_that("sheet over the cap is ignored", {
  r <- wb_md(p = big_variant(201, 20))
  sh <- section(r$lines, "## Sheet: Pat Quill data")
  expect_true(any(grepl("Not read: 201 rows x 20 columns is over the 4,000-cell limit for raw data.", sh, fixed = TRUE)))
  expect_false(any(grepl("zq", r$lines, fixed = TRUE)))
  expect_false(any(grepl("^\\| [0-9]+ \\|", sh)))
  expect_equal(nrow(r$ignored), 1)
  expect_equal(r$ignored$rows, 201)
  expect_equal(r$ignored$cols, 20)
  expect_equal(r$ignored$sheet_pos, 2)
  expect_null(r$big_sheets)
  # The other sheets are still read.
  expect_true(any(grepl("^## Sheet: Summary", r$lines)))
})

test_that("sheet at the cap is read", {
  r <- wb_md(p = big_variant(200, 20))
  sh <- section(r$lines, "## Sheet: Pat Quill data")
  expect_false(any(grepl("Not read", sh)))
  expect_true(any(grepl("zq200x20", sh, fixed = TRUE)))
  expect_equal(nrow(r$ignored), 0)
})

test_that("csv over the cap is ignored", {
  p <- withr::local_tempfile(fileext = ".csv")
  writeLines(c("id", sprintf("zq%d", seq_len(4000))), p)
  r <- csv_to_md(p)
  expect_true(any(grepl("Not read: 4,001 rows x 1 columns is over the 4,000-cell limit for raw data.", r$lines, fixed = TRUE)))
  expect_false(any(grepl("zq", r$lines, fixed = TRUE)))
  expect_equal(r$ignored$rows, 4001)
  expect_equal(r$ignored$cols, 1)
  expect_equal(r$ignored$sheet_pos, 1)
  p2 <- withr::local_tempfile(fileext = ".csv")
  writeLines(c("id", sprintf("zq%d", seq_len(3999))), p2)
  r2 <- csv_to_md(p2)
  expect_equal(nrow(r2$ignored), 0)
  expect_true(any(grepl("zq3999", r2$lines, fixed = TRUE)))
})

test_that("charts on an ignored sheet still described", {
  chart1 <- function(r) {
    ch <- section(r$lines, "## Charts")
    i <- grep("^### Chart", ch)
    paste(ch[i[1]:(i[2] - 1)], collapse = "\n")
  }
  r <- wb_md(p = big_variant(201, 20, chart_on_big = TRUE))
  expect_match(chart1(r), "values: 10, 20, 30", fixed = TRUE)
  expect_false(grepl("from cells", chart1(r), fixed = TRUE))
  r2 <- wb_md(p = big_variant(201, 20, chart_on_big = TRUE, drop_cache = TRUE))
  expect_match(chart1(r2), "values not available", fixed = TRUE)
  expect_false(grepl("10, 20, 30", chart1(r2), fixed = TRUE))
  expect_false(any(grepl("zq", r2$lines, fixed = TRUE)))
})

test_that("a small sheet with an inflated dimension is read", {
  r <- wb_md(p = big_variant(10, 5, dim = "A1:J1000"))
  sh <- section(r$lines, "## Sheet: Pat Quill data")
  expect_false(any(grepl("Not read", sh)))
  expect_true(any(grepl("zq10x5", sh, fixed = TRUE)))
  expect_equal(nrow(r$ignored), 0)
})

test_that("a sheet with no dimension is measured from its cells", {
  r <- wb_md(p = big_variant(201, 20, dim = ""))
  expect_true(any(grepl("Not read: 201 rows x 20 columns", r$lines, fixed = TRUE)))
  expect_equal(nrow(r$ignored), 1)
})

test_that("a dimensionless over-cap sheet is not read by a chart", {
  r <- wb_md(p = big_variant(201, 20, chart_on_big = TRUE, drop_cache = TRUE, dim = ""))
  chs <- section(r$lines, "## Charts")
  ch <- paste(chs[seq_len(grep("^### Chart 2", chs)[1] - 1)], collapse = "\n")
  expect_match(ch, "values not available", fixed = TRUE)
  expect_false(grepl("from cells", ch, fixed = TRUE))
  expect_false(grepl("10, 20, 30", ch, fixed = TRUE))
})

test_that("an ignored sheet lists no hyperlinks", {
  r <- wb_md(p = big_variant(201, 20, link = TRUE))
  expect_false(any(grepl("zqlinktext", r$lines, fixed = TRUE)))
  expect_false(any(grepl("^- .*Pat Quill data.*!A1: ", r$lines)))
  expect_true(any(grepl("hyperlinks on sheets not read as raw data (not listed): 1", section(r$lines, "## Other content"), fixed = TRUE)))
})

test_that("anonymize has no source_data argument", {
  expect_false("source_data" %in% names(formals(anonymize)))
})

test_that("a chart sheet takes its place among the sheets", {
  p <- wb_variant(function(parts) {
    change(parts, "xl/workbook.xml", function(x) sub("</sheets>",
      "<sheet name=\"Chart1\" sheetId=\"4\" r:id=\"rId11\"/></sheets>", x, fixed = TRUE))
    change(parts, "xl/_rels/workbook.xml.rels", function(x) sub("</Relationships>",
      "<Relationship Id=\"rId11\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/chartsheet\" Target=\"chartsheets/sheet1.xml\"/></Relationships>", x, fixed = TRUE))
    put(parts, "xl/chartsheets/sheet1.xml", '<chartsheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheetViews><sheetView workbookViewId="0"/></sheetViews><headerFooter><oddFooter>&amp;CChart footer</oddFooter></headerFooter></chartsheet>')
  })
  r <- wb_md(p = p)
  h <- grep("^## Sheet: ", r$lines, value = TRUE)
  expect_equal(h[4], "## Sheet: Chart1")
  expect_true("A chart sheet: its chart is described under Charts." %in% section(r$lines, "## Sheet: Chart1"))
  expect_true("- Chart1, footer: center: Chart footer" %in% section(r$lines, "## Headers and footers"))
})

# Task 5 fix round 1.
csv_bytes <- function(raw) {
  p <- withr::local_tempfile(fileext = ".csv", .local_envir = parent.frame())
  writeBin(raw, p)
  p
}
csv_rows <- function(r) grep("^\\| [0-9]+ \\|", r$lines, value = TRUE)

test_that("a cp1252 csv keeps every row and its accents", {
  p <- csv_bytes(c(charToRaw("name,score\nAlpha,1\nCaf"), as.raw(0xe9),
                   charToRaw(",2\nBeta,3\nGamma,4\n")))
  r <- csv_to_md(p)
  rows <- csv_rows(r)
  expect_length(rows, 5)
  expect_true("| 3 | Café | 2 |" %in% rows)
  expect_true("| 5 | Gamma | 4 |" %in% rows)
})

test_that("a ragged csv row stays one row", {
  p <- csv_bytes(charToRaw("a,b\n1,2\n3,4\n5,6\n7,8\n9,10\n11,12,13,14\n"))
  r <- csv_to_md(p)
  rows <- csv_rows(r)
  expect_length(rows, 7)
  expect_true("| 7 | 11 | 12 | 13 | 14 |" %in% rows)
  expect_true("| 1 | a | b |  |  |" %in% rows)
})

test_that("a blank csv line keeps later row numbers", {
  r <- csv_to_md(csv_bytes(charToRaw("a,b\n\n1,2\n")))
  rows <- csv_rows(r)
  expect_true("| 3 | 1 | 2 |" %in% rows)
  expect_length(rows, 3)
})

test_that("a csv read problem is counted, not hidden", {
  r <- csv_to_md(csv_bytes(charToRaw("a,b\n\"open,2\n3,4\n")))
  expect_gte(r$other[["csv_read_problems"]], 1L)
  expect_match(paste(section(r$lines, "## Other content"), collapse = "\n"), "csv read problems")
  expect_false("No cell content." %in% r$lines)
})

test_that("a picture relationship outside xl/media is not copied", {
  p <- wb_variant(function(parts) {
    change(parts, "xl/drawings/_rels/drawing1.xml.rels", function(x)
      sub("../media/image1.png", "../comments1.xml", x, fixed = TRUE))
  })
  r <- wb_md(p = p)
  expect_length(list.files(r$media_dir), 0)
  expect_false(any(grepl("![picture]", r$lines, fixed = TRUE)))
  expect_gte(r$other[["other_pictures"]], 1L)
})

test_that("scenarios and data tables are counted and marked", {
  p <- wb_variant(function(parts) {
    change(parts, "xl/worksheets/sheet3.xml", function(x) {
      x <- sub("</sheetData>", paste0(
        "<row r=\"3\"><c r=\"A3\"><v>1</v></c><c r=\"B3\"><f t=\"dataTable\" ref=\"B3:B4\" dt2D=\"0\" dtr=\"0\" r1=\"B1\"/><v>7</v></c></row>",
        "<row r=\"4\"><c r=\"A4\"><v>2</v></c><c r=\"B4\"><v>8</v></c></row></sheetData>",
        "<scenarios><scenario name=\"Best\" count=\"1\"><inputCells r=\"B1\" val=\"50\"/></scenario></scenarios>"),
        x, fixed = TRUE)
      sub("A1:B1", "A1:B4", x, fixed = TRUE)
    })
  })
  r <- wb_md(p = p)
  expect_equal(r$other[["scenarios"]], 1L)
  expect_equal(r$other[["data_tables"]], 1L)
  s3 <- section(r$lines, "## Sheet: Hidden calc (very hidden)")
  expect_true("| 3 | 1 | 7 (data table B3:B4) |" %in% s3)
  expect_true("| 4 | 2 | 8 (data table B3:B4) |" %in% s3)
})

test_that("formula prefixes stripped and spills marked", {
  p <- wb_variant(function(parts) {
    change(parts, "xl/worksheets/sheet3.xml", function(x) {
      x <- sub("</sheetData>", paste0(
        "<row r=\"5\"><c r=\"A5\" cm=\"1\"><f t=\"array\" ref=\"A5:A6\">_xlfn._xlws.SORT(B1:B2)</f><v>3</v></c>",
        "<c r=\"B5\"><f t=\"array\" ref=\"B5\">SUM(B1:B2*2)</f><v>84</v></c>",
        "<c r=\"C5\"><f>_xlfn.LET(_xlpm.x,2,_xlpm.x*3)</f><v>6</v></c></row>",
        "<row r=\"6\"><c r=\"A6\"><v>4</v></c></row></sheetData>"), x, fixed = TRUE)
      sub("A1:B1", "A1:C6", x, fixed = TRUE)
    })
  })
  r <- wb_md(p = p)
  s3 <- section(r$lines, "## Sheet: Hidden calc (very hidden)")
  txt <- paste(s3, collapse = "\n")
  expect_match(txt, "3 `=SORT(B1:B2)` (spills into A5:A6)", fixed = TRUE)
  expect_match(txt, "84 `{=SUM(B1:B2*2)}`", fixed = TRUE)
  expect_match(txt, "6 `=LET(x,2,x*3)`", fixed = TRUE)
  expect_false(grepl("_xl", txt, fixed = TRUE))
})

test_that("an OLE-wrapped pdf is flagged and its images linked", {
  skip_if_no("pdftotext"); skip_if_no("pdfimages")
  src <- withr::local_tempdir()
  pdf <- file.path(src, "inner.pdf")
  grDevices::pdf(pdf, width = 3, height = 3)
  graphics::plot.new(); graphics::text(0.5, 0.5, "Embedded pdf words")
  graphics::rasterImage(matrix(c(0, 1, 1, 0), 2), 0, 0, 0.3, 0.3, interpolate = FALSE)
  invisible(grDevices::dev.off())
  pdf_raw <- readBin(pdf, "raw", file.size(pdf))
  p <- wb_variant(function(parts) {
    writeBin(c(charToRaw("OLE-HEADER-BYTES"), pdf_raw, as.raw(c(0, 0, 0))),
             file.path(parts, "xl", "embeddings", "oleObject2.bin"))
  })
  r <- wb_md(p = p)
  ed <- section(r$lines, "## Embedded document 1")
  txt <- paste(ed, collapse = "\n")
  expect_match(txt, "Embedded pdf words", fixed = TRUE)
  expect_match(txt, "taken out of an embedded object", fixed = TRUE)
  expect_match(txt, "](file1_media/embedded1/img-000.png)", fixed = TRUE)
  expect_true(file.exists(file.path(r$media_dir, "embedded1", "img-000.png")))
})

# Task 7: workbooks through anonymize() end to end. Quill (S01) submits only
# the fixture workbook; Rivera (S02) a .docx.
WB_IMAGE <- "S01/file1_media/image1.png"
# The fixture's defined name "PatQuillRange" glues the name into one
# identifier, which whole-word redaction cannot split; the leftover check
# stops the run on it. nickname = TRUE stages the documented remedy, the form
# added as a nickname in the key.
add_quill_nickname <- function(a) {
  kp <- file.path(a, "anon_key.csv")
  k <- read_key(kp)
  k$nicknames[k$canvas_id == "1001"] <- "PatQuillRange"
  utils::write.csv(k, kp, row.names = FALSE)
}
wb_assignment <- function(xlsx = NULL, decide = TRUE, nickname = TRUE, env = parent.frame()) {
  skip_if_no("tesseract"); skip_if_no("pandoc")
  cc <- anon_course(env = env); a <- a1_assignment(cc)
  if (is.null(xlsx)) xlsx <- fake_workbook(withr::local_tempdir(.local_envir = env))
  file.copy(xlsx, file.path(a, "quillpat_1001_5001_partb.xlsx"))
  mk_docx(file.path(a, "riveramorgan_1002_5002_partb.docx"),
          c("Morgan Rivera answered part B.", "", "Mo checked it."))
  if (decide) {
    utils::write.csv(data.frame(image = WB_IMAGE, decision = "remove"),
                     file.path(a, "anon_images.csv"), row.names = FALSE)
  }
  if (nickname) add_quill_nickname(a)
  list(cc = cc, a = a)
}
# Runs anonymize() and returns the console output; the result is in attr "res".
wb_anonymize <- function(w, ...) {
  out <- capture.output(res <- anonymize(w$cc$proj, "semester/A1", dict = NULL, sweep = FALSE, ...))
  attr(out, "res") <- res
  out
}
coded_md <- function(w) readLines(file.path(w$a, "anon", "S01", "file1.md"), warn = FALSE)

test_that("workbook end to end leaves no name", {
  w <- wb_assignment(nickname = FALSE)
  # A name glued into a defined name is not redacted; the leftover check
  # stops the run, naming the code and the anon/ path only.
  msgs <- character()
  err <- withCallingHandlers(errors_with(wb_anonymize(w)),
    message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") })
  expect_match(err, "leftover", fixed = TRUE)
  expect_true(any(grepl("^LEFTOVER: a value for S01 remains in anon/S01/file1.md", msgs)))
  expect_false(dir.exists(file.path(w$a, "anon")))
  expect_false(any(grepl("quill|1001|partb", c(err, msgs), ignore.case = TRUE)))
  add_quill_nickname(w$a)
  wb_anonymize(w)
  texts <- list.files(file.path(w$a, "anon"), recursive = TRUE, full.names = TRUE)
  texts <- texts[!grepl("\\.(png|jpe?g|gif|emf|wmf|bin)$", texts, ignore.case = TRUE)]
  expect_true(length(texts) >= 3)
  for (f in texts) {
    # "secret" is spelled secret.xlsx here: the external link target (a
    # secret.xlsx in the student's home folder) must not appear, while the
    # very hidden sheet's own cell text "secret calc" is content the grader
    # is shown.
    hits <- grep("quill|rivera|\\bmo\\b|xq100|1001|secret\\.xlsx", readLines(f, warn = FALSE),
                 ignore.case = TRUE, value = TRUE)
    expect_identical(hits, character(), info = f)
  }
  man <- utils::read.csv(file.path(w$a, "anon", "manifest.csv"), colClasses = c(target = "logical"))
  q <- man[man$code == "S01", ]
  expect_equal(nrow(q), 1)
  expect_equal(q$ext, "xlsx")
  expect_true(q$target)
})

test_that("sheet name redacted consistently", {
  p <- wb_variant(function(parts) change(parts, "xl/charts/chart1.xml", function(x) {
    x <- gsub("Summary!\\$A\\$7:\\$A\\$9", "'Pat Quill data'!$A$2:$A$4", x)
    gsub("Summary!\\$B\\$7:\\$B\\$9", "'Pat Quill data'!$B$2:$B$4", x)
  }))
  w <- wb_assignment(p)
  wb_anonymize(w)
  md <- coded_md(w)
  expect_true("## Sheet: [name] data" %in% md)
  expect_true(any(grepl("=SUM('[name] data'!B2:B5)", md, fixed = TRUE)))
  ch <- md[seq_len(which(md == "## Sheet: Summary")[1])]
  expect_true(any(grepl("'[name] data'!$B$2:$B$4", ch, fixed = TRUE)))
})

test_that("split run redacted", {
  w <- wb_assignment()
  wb_anonymize(w)
  txt <- paste(coded_md(w), collapse = "\n")
  expect_false(grepl("Pat\\s+(\\|\\s*)?Quill", txt, ignore.case = TRUE))
  expect_false(grepl("quill", txt, ignore.case = TRUE))
})

test_that("fixture picture held for review", {
  w <- wb_assignment(decide = FALSE)
  msgs <- character()
  err <- withCallingHandlers(errors_with(wb_anonymize(w)),
    message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") })
  expect_match(err, "image(s) need a decision", fixed = TRUE)
  expect_true(any(grepl(WB_IMAGE, msgs, fixed = TRUE)))
  expect_false(dir.exists(file.path(w$a, "anon")))
  expect_false(any(grepl("quill|1001|partb", c(err, msgs), ignore.case = TRUE)))
})

test_that("big sheet ignored end to end", {
  w <- wb_assignment(big_variant(201, 20))
  out <- wb_anonymize(w)
  expect_true(any(grepl("Not read: 201 rows x 20 columns is over the 4,000-cell limit for raw data.",
                        coded_md(w), fixed = TRUE)))
  expect_true("S01 (file1): 1 sheet(s) over the 4,000-cell limit not read" %in% out)
  log <- readLines(file.path(w$a, "deidentification_log.md"))
  expect_true("- workbook sheets over the 4,000-cell limit not read: 1" %in% log)
  expect_equal(attr(out, "res")$ignored_sheets, 1L)
})

test_that("log records skipped and other content", {
  w <- wb_assignment()
  writeLines("x", file.path(w$a, "riveramorgan_1002_5003_old.xls"))
  out <- wb_anonymize(w, skip_types = "xls")
  log <- readLines(file.path(w$a, "deidentification_log.md"))
  expect_true("- files skipped by type: xls 1" %in% log)
  oc <- grep("^- workbook content not read", log, value = TRUE)
  expect_length(oc, 1)
  expect_match(oc, "external_links 1", fixed = TRUE)
  expect_match(oc, "connections 1", fixed = TRUE)
  expect_match(oc, "form_controls 1", fixed = TRUE)
  expect_false(grepl("macros", oc, fixed = TRUE))   # zero counts left out
  expect_true("- workbook sheets over the 4,000-cell limit not read: 0" %in% log)
  expect_false(any(grepl("quill|rivera|1001|1002|5003|partb|\\.xlsx|_old", log, ignore.case = TRUE)))
  res <- attr(out, "res")
  expect_equal(res$other[["external_links"]], 1L)
})

test_that("strict workbook stops anonymize naming code and position", {
  p <- wb_variant(function(parts) {
    change(parts, "xl/workbook.xml", function(x) sub("http://schemas.openxmlformats.org/spreadsheetml/2006/main",
      "http://purl.oclc.org/ooxml/spreadsheetml/main", x, fixed = TRUE))
  })
  w <- wb_assignment(p)
  err <- errors_with(wb_anonymize(w))
  expect_equal(err, paste0("S01 (file1): workbook saved in Strict Open XML format; re-save it as a ",
                           "normal .xlsx workbook, or pass \"xlsx\" in skip_types"))
  expect_false(dir.exists(file.path(w$a, "anon")))
})

test_that("a corrupt workbook's error never names the file", {
  skip_if_no("tesseract")
  cc <- anon_course(); a <- a1_assignment(cc)
  writeLines("x", file.path(a, "quillpat_1001_5001_partb.xlsx"))
  mk_docx(file.path(a, "riveramorgan_1002_5002_partb.docx"), "Hello")
  err <- errors_with(quiet(anonymize(cc$proj, "semester/A1", dict = NULL, sweep = FALSE)))
  expect_match(err, "^S01 \\(file1\\): ")
  expect_false(grepl("quill|1001|5001|partb", err, ignore.case = TRUE))
  expect_false(grepl(normalizePath(a), err, fixed = TRUE))
})

# Fix round 1: an error raised by a third-party reader (tidyxl, xml2) can
# quote workbook content, so only the package's own messages pass through.
WB_UNREADABLE <- "the workbook could not be read; re-save it as .xlsx, or pass skip_types"
test_that("a reader error from tidyxl is replaced by the fixed text", {
  p <- wb_variant(function(parts) change(parts, "xl/_rels/workbook.xml.rels", function(x) {
    gsub('Target="worksheets/', 'Target="./worksheets/', x, fixed = TRUE)
  }))
  w <- wb_assignment(p)
  err <- errors_with(wb_anonymize(w))
  expect_equal(err, paste0("S01 (file1): ", WB_UNREADABLE))
  expect_false(grepl("quill", err, ignore.case = TRUE))
})

test_that("a malformed XML part gives the fixed text", {
  p <- wb_variant(function(parts) change(parts, "xl/worksheets/sheet1.xml", function(x) {
    sub("<sheetData>", "<sheetData><bad>Pat Quill wrote this <row", x, fixed = TRUE)
  }))
  td <- withr::local_tempdir()
  err <- errors_with(convert_to_text(p, file.path(td, "file1.md"), file.path(td, "file1_media")))
  expect_equal(err, WB_UNREADABLE)
  w <- wb_assignment(p)
  err2 <- errors_with(wb_anonymize(w))
  expect_equal(err2, paste0("S01 (file1): ", WB_UNREADABLE))
  expect_false(grepl("quill", err2, ignore.case = TRUE))
})

test_that("an unreadable csv gives the csv fixed text", {
  td <- withr::local_tempdir()
  p <- file.path(td, "in.csv"); writeLines("a,b", p)
  local_mocked_bindings(csv_to_md = function(path) stop("cell Pat Quill broke it"))
  err <- errors_with(convert_to_text(p, file.path(td, "file1.md"), file.path(td, "file1_media")))
  expect_equal(err, "the csv could not be read; re-save it, or pass skip_types")
})

test_that("the package's own workbook messages pass through", {
  td <- withr::local_tempdir()
  p <- file.path(td, "in.xlsx"); writeLines("x", p)
  local_mocked_bindings(workbook_to_md = function(...) wb_stop("own message kept"))
  err <- errors_with(convert_to_text(p, file.path(td, "file1.md"), file.path(td, "file1_media")))
  expect_equal(err, "own message kept")
})

# Fix round 2: warnings and messages from third-party readers can quote the
# workbook (libxml2: "xmlns:q: 'Pat Quill secret' is not a valid URI"); they
# are muffled and only counted.
ns_variant <- function(env = parent.frame()) {
  wb_variant(function(parts) {
    for (rel in c("xl/workbook.xml", "xl/worksheets/sheet1.xml")) change(parts, rel, function(x) {
      sub("(<(workbook|worksheet) )", "\\1xmlns:q=\"Pat Quill secret\" ", x)
    })
  }, env = env)
}
conditions_of <- function(expr) {
  seen <- character()
  withCallingHandlers(force(expr),
    warning = function(w) { seen <<- c(seen, conditionMessage(w)); invokeRestart("muffleWarning") },
    message = function(m) { seen <<- c(seen, conditionMessage(m)); invokeRestart("muffleMessage") })
  seen
}
test_that("reader warnings are muffled and counted", {
  p <- ns_variant()
  td <- withr::local_tempdir()
  expect_no_warning(r <- convert_to_text(p, file.path(td, "file1.md"), file.path(td, "file1_media")))
  seen <- conditions_of(convert_to_text(p, file.path(td, "f2.md"), file.path(td, "f2_media")))
  expect_false(any(grepl("quill", seen, ignore.case = TRUE)))
  expect_true(attr(r, "other")[["reader_warnings"]] > 0)
  w <- wb_assignment(p)
  seen2 <- conditions_of(out <- wb_anonymize(w))
  expect_false(any(grepl("quill", c(seen2, out), ignore.case = TRUE)))
  expect_true(dir.exists(file.path(w$a, "anon")))
  expect_match(grep("^- workbook content not read", readLines(file.path(w$a, "deidentification_log.md")),
                    value = TRUE), "reader_warnings [0-9]+")
})

# Fix round 3: a failed copy warns "problem copying <path>", and the path is
# the Canvas filename. The warning is suppressed; the fixed message stays.
test_that("a failed workbook copy names no file", {
  skip_on_os("windows")
  td <- withr::local_tempdir()
  p <- file.path(td, "quillpat_1001_5001_partb.xlsx"); writeLines("x", p)
  Sys.chmod(p, "000"); withr::defer(Sys.chmod(p, "644"))
  skip_if(file.access(p, 4) == 0, "file stays readable (running as root)")
  seen <- character()
  err <- withCallingHandlers(
    errors_with(convert_to_text(p, file.path(td, "o", "file1.md"), file.path(td, "o", "file1_media"))),
    warning = function(w) { seen <<- c(seen, conditionMessage(w)); invokeRestart("muffleWarning") })
  expect_length(seen, 0)
  expect_equal(err, "could not copy the workbook for reading")
  expect_false(any(grepl("quill", c(err, seen), ignore.case = TRUE)))
})

test_that("a copy that warns is silent and names no file", {
  td <- withr::local_tempdir()
  # A folder with a workbook's name: file.copy() warns and copies nothing.
  p <- file.path(td, "quillpat_1001_5001_partb.xlsx"); dir.create(p)
  seen <- character()
  err <- withCallingHandlers(
    errors_with(convert_to_text(p, file.path(td, "o", "file1.md"), file.path(td, "o", "file1_media"))),
    warning = function(w) { seen <<- c(seen, conditionMessage(w)); invokeRestart("muffleWarning") })
  expect_length(seen, 0)
  expect_equal(err, "could not copy the workbook for reading")
  expect_false(any(grepl("quill", c(err, seen), ignore.case = TRUE)))
})

# Task 8: relink() answers a workbook with markdown.
test_that("feedback_name swaps sheet extensions only", {
  expect_equal(feedback_name("quillpat_1001_5001_partb.xlsx"), "quillpat_1001_5001_partb.md")
  expect_equal(feedback_name("quillpat_1001_5001_partb.xlsm"), "quillpat_1001_5001_partb.md")
  expect_equal(feedback_name("quillpat_1001_5001_partb.CSV"), "quillpat_1001_5001_partb.md")
  expect_equal(feedback_name("quillpat_1001_5001_partb.docx"), "quillpat_1001_5001_partb.docx")
  expect_equal(feedback_name("quillpat_1001_5001_partb.png"), "quillpat_1001_5001_partb.png")
})

test_that("workbook-only student gets md feedback", {
  skip_if_no("tesseract"); skip_if_no("pandoc"); skip_if_no("zip")
  cc <- anon_course(); a <- a1_assignment(cc)
  writeLines(c("item,score", "a,1", "b,2"), file.path(a, "quillpat_1001_5001_partb.csv"))
  mk_docx(file.path(a, "riveramorgan_1002_5002_partb.docx"), "Morgan Rivera answered part B.")
  quiet(anonymize(cc$proj, "semester/A1", dict = NULL, sweep = FALSE))
  fb <- file.path(a, "anon", "feedback"); dir.create(fb, recursive = TRUE)
  writeLines("Good work, S01.", file.path(fb, "S01.md"))
  writeLines("Good work, S02.", file.path(fb, "S02.md"))
  utils::write.csv(data.frame(code = c("S01", "S02"), total = c("9", "8")),
                   file.path(a, "anon", "scores.csv"), row.names = FALSE)
  quiet(relink(cc$proj, "semester/A1", dict = NULL))
  out <- file.path(a, "feedback", "quillpat_1001_5001_partb.md")
  expect_true(file.exists(out))
  expect_false(file.exists(file.path(a, "feedback", "quillpat_1001_5001_partb.csv")))
  expect_match(readLines(out, warn = FALSE), "Pat Quill", fixed = TRUE)
  z <- utils::unzip(file.path(a, "feedback.zip"), list = TRUE)$Name
  expect_true("feedback/quillpat_1001_5001_partb.md" %in% z)
  expect_false(any(grepl("\\.csv$|\\.xlsx$", z)))
})
