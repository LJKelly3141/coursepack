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
