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
