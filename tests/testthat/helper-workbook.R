# Fixture workbook for the anonymize() workbook tests. The .xlsx is kept as
# plain-text XML parts under fixtures/workbook/ and zipped here, so a diff
# shows what changed. Every name, address and id in the parts is invented.

fake_hcahps <- function() {
  testthat::test_path("fixtures", "hcahps-source.csv")
}

# Zip the parts into dir/name and return the path. macro = FALSE leaves out
# xl/vbaProject.bin and its relationship; macro = TRUE keeps it, switches the
# workbook to the macro content type, and the name should end in .xlsm.
fake_workbook <- function(dir, name = "quillpat_1001_5001_partb.xlsx",
                          macro = FALSE) {
  src <- normalizePath(testthat::test_path("fixtures", "workbook"))
  work <- tempfile("wbparts_")
  dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  file.copy(list.files(src, all.files = TRUE, no.. = TRUE, full.names = TRUE),
            work, recursive = TRUE)

  edit <- function(rel, f) {
    p <- file.path(work, rel)
    writeLines(f(readLines(p, warn = FALSE)), p)
  }
  if (macro) {
    edit("[Content_Types].xml", function(x) {
      sub("spreadsheetml.sheet.main+xml", "ms-excel.sheet.macroEnabled.main+xml",
          x, fixed = TRUE)
    })
  } else {
    unlink(file.path(work, "xl", "vbaProject.bin"))
    edit("[Content_Types].xml", function(x) x[!grepl("vbaProject", x)])
    edit("xl/_rels/workbook.xml.rels", function(x) x[!grepl("vbaProject", x)])
  }

  out <- file.path(normalizePath(dir), name)
  if (file.exists(out)) unlink(out)
  files <- c("[Content_Types].xml",
             setdiff(list.files(work, recursive = TRUE, all.files = TRUE),
                     "[Content_Types].xml"))
  old <- setwd(work)
  on.exit(setwd(old), add = TRUE, after = FALSE)
  utils::zip(out, files, flags = "-X -q")
  out
}

# A one-sheet workbook from its parts, for faults the cell reader (tidyxl)
# crashes on. sheet_xml is everything inside <worksheet>; comments_xml, when
# given, is the sheet's comments part. Every value is invented.
tiny_workbook <- function(dir, sheet_xml, comments_xml = NULL,
                          name = "tiny.xlsx") {
  M <- 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
  R <- 'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
  ct <- "application/vnd.openxmlformats-officedocument.spreadsheetml."
  rel <- "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
  pkg <- "http://schemas.openxmlformats.org/package/2006/"
  parts <- list(
    "[Content_Types].xml" = paste0(
      '<Types xmlns="', pkg, 'content-types">',
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>',
      '<Default Extension="xml" ContentType="application/xml"/>',
      '<Override PartName="/xl/workbook.xml" ContentType="', ct, 'sheet.main+xml"/>',
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="', ct, 'worksheet+xml"/>',
      '<Override PartName="/xl/styles.xml" ContentType="', ct, 'styles+xml"/>',
      if (!is.null(comments_xml)) paste0('<Override PartName="/xl/comments1.xml" ContentType="', ct, 'comments+xml"/>'),
      "</Types>"),
    "_rels/.rels" = paste0('<Relationships xmlns="', pkg, 'relationships">',
      '<Relationship Id="rId1" Type="', rel, 'officeDocument" Target="xl/workbook.xml"/></Relationships>'),
    "xl/workbook.xml" = sprintf('<workbook %s %s><sheets><sheet name="Data" sheetId="1" r:id="rId1"/></sheets></workbook>', M, R),
    "xl/_rels/workbook.xml.rels" = paste0('<Relationships xmlns="', pkg, 'relationships">',
      '<Relationship Id="rId1" Type="', rel, 'worksheet" Target="worksheets/sheet1.xml"/>',
      '<Relationship Id="rId2" Type="', rel, 'styles" Target="styles.xml"/></Relationships>'),
    "xl/styles.xml" = sprintf(paste0('<styleSheet %s><fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>',
      '<fills count="1"><fill><patternFill patternType="none"/></fill></fills><borders count="1"><border/></borders>',
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>',
      '<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs></styleSheet>'), M),
    "xl/worksheets/sheet1.xml" = sprintf("<worksheet %s %s>%s</worksheet>", M, R, sheet_xml))
  if (!is.null(comments_xml)) {
    parts[["xl/comments1.xml"]] <- sprintf("<comments %s>%s</comments>", M, comments_xml)
    parts[["xl/worksheets/_rels/sheet1.xml.rels"]] <- paste0('<Relationships xmlns="', pkg, 'relationships">',
      '<Relationship Id="rId1" Type="', rel, 'comments" Target="../comments1.xml"/></Relationships>')
  }
  work <- tempfile("tinywb_")
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  for (p in names(parts)) {
    dir.create(dirname(file.path(work, p)), recursive = TRUE, showWarnings = FALSE)
    writeLines(parts[[p]], file.path(work, p), useBytes = TRUE)
  }
  out <- file.path(normalizePath(dir), name)
  if (file.exists(out)) unlink(out)
  old <- setwd(work)
  on.exit(setwd(old), add = TRUE, after = FALSE)
  utils::zip(out, names(parts), flags = "-X -q")
  out
}
