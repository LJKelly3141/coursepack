# Published PDFs against PDF/UA-1. Most of this runs with veraPDF mocked, so
# it runs everywhere; the one block that starts the real tool skips without
# it. The fixture PDFs come from grDevices::pdf(), which writes an untagged
# file that genuinely fails PDF/UA-1.

pdf_repo <- function() {
  repo <- withr::local_tempdir("pdfrepo-", .local_envir = parent.frame())
  dir.create(file.path(repo, "docs", "pages"), recursive = TRUE)
  dir.create(file.path(repo, "docs", "assets"))
  dir.create(file.path(repo, "pages"))
  for (f in c("docs/pages/summary.pdf", "docs/assets/handout.pdf")) {
    grDevices::pdf(file.path(repo, f))
    plot(1)
    grDevices::dev.off()
  }
  writeLines(c("---", "title: Summary", "format:", "  html: default",
               "  typst: default", "---", "body"),
             file.path(repo, "pages", "summary.qmd"))
  list(repo = repo, output_dir = file.path(repo, "docs"))
}

test_that("published PDFs split into built here and carried", {
  tgt <- pdf_repo()
  p <- published_pdfs(tgt)
  expect_identical(p$file, c("assets/handout.pdf", "pages/summary.pdf"))
  expect_identical(p$origin, c("carried", "built"))
  expect_identical(p$source_file, c(NA_character_, "pages/summary.qmd"))
  expect_identical(nrow(published_pdfs(list(repo = tgt$repo,
                                            output_dir = NA_character_))), 0L,
    info = "a target with no output directory has no PDFs, and does not error")
})

test_that("without veraPDF every PDF is not checked and nothing is a finding", {
  tgt <- pdf_repo()
  r <- check_published_pdfs(tgt, "demo", verapdf = NA_character_)
  expect_false(r$checked)
  expect_identical(r$results$status, c("not checked", "not checked"))
  expect_identical(nrow(r$findings), 0L,
    info = "a missing optional tool must not manufacture findings")
})

test_that("a launcher that cannot start counts as not installed", {
  expect_false(verapdf_usable(NA_character_))
  expect_false(verapdf_usable(file.path(tempdir(), "no-such-verapdf")))
})

test_that("a failing built PDF is a finding aimed at its source; a carried one is not", {
  tgt <- pdf_repo()
  local_mocked_bindings(
    verapdf_usable = function(verapdf) TRUE,
    run_verapdf = function(verapdf, paths) {
      stats::setNames(lapply(paths, function(p) {
        list(status = "failed", rules = c("rule one", "rule two"))
      }), paths)
    })
  r <- check_published_pdfs(tgt, "demo", verapdf = "mock")
  expect_true(r$checked)
  expect_identical(r$results$status, c("failed", "failed"))
  expect_identical(nrow(r$findings), 1L,
    info = "the carried handout failed too and must not be a finding")
  expect_identical(r$findings$file, "pages/summary.pdf")
  expect_identical(r$findings$fix_target, "pages/summary.qmd",
    info = "the fix lands in the source, never in docs/")
  expect_identical(r$findings$criterion, PDF_UA_CRITERION)
  expect_match(r$findings$issue, "2 rule")
  expect_match(r$findings$detail, "rule one; rule two", fixed = TRUE)
})

test_that("a passing PDF is no finding, an unreadable built one is", {
  tgt <- pdf_repo()
  local_mocked_bindings(
    verapdf_usable = function(verapdf) TRUE,
    run_verapdf = function(verapdf, paths) {
      stats::setNames(lapply(paths, function(p) {
        if (grepl("summary", p)) list(status = "unreadable", rules = "could not parse")
        else list(status = "passed", rules = character())
      }), paths)
    })
  r <- check_published_pdfs(tgt, "demo", verapdf = "mock")
  expect_identical(r$results$status, c("passed", "unreadable"))
  expect_identical(nrow(r$findings), 1L)
  expect_match(r$findings$issue, "could not be read")
})

test_that("real veraPDF fails an untagged PDF and names the rules", {
  v <- find_verapdf()
  skip_if(!verapdf_usable(v), "veraPDF (and Java) not installed")
  tgt <- pdf_repo()
  writeLines("not a pdf", file.path(tgt$output_dir, "pages", "broken.pdf"))
  r <- check_published_pdfs(tgt, "demo", verapdf = v)
  st <- stats::setNames(r$results$status, r$results$file)
  expect_identical(st[["pages/summary.pdf"]], "failed")
  expect_identical(st[["assets/handout.pdf"]], "failed")
  expect_identical(st[["pages/broken.pdf"]], "unreadable",
    info = "a file veraPDF cannot parse is never silently passed")
  rules <- r$results$rules[[which(r$results$file == "pages/summary.pdf")]]
  expect_true(length(rules) > 0 && all(grepl("clause", rules)))
})

test_that("the prompt continues without veraPDF when nobody can answer or the answer is no", {
  expect_output(v <- ask_about_verapdf(ask = FALSE), "Continuing without PDF validation")
  expect_identical(v, NA_character_)
  installed <- FALSE
  expect_output(v <- ask_about_verapdf(ask = TRUE, read = function(msg) "n",
                                       install = function() installed <<- TRUE),
                "Continuing without PDF validation")
  expect_identical(v, NA_character_)
  expect_false(installed, info = "answering no must not run the install")
})

test_that("answering yes runs the install, and a failed install still continues", {
  installed <- FALSE
  local_mocked_bindings(find_verapdf = function() NA_character_)
  expect_output(v <- ask_about_verapdf(ask = TRUE, read = function(msg) " Y ",
                                       install = function() installed <<- TRUE),
                "still cannot start")
  expect_true(installed)
  expect_identical(v, NA_character_,
    info = "an install that did not work never fails the audit")
})

test_that("answering yes returns the launcher once the install works", {
  local_mocked_bindings(find_verapdf = function() "/opt/verapdf",
                        verapdf_usable = function(verapdf) TRUE)
  expect_output(v <- ask_about_verapdf(ask = TRUE, read = function(msg) "yes",
                                       install = function() TRUE))
  expect_identical(v, "/opt/verapdf")
})

test_that("a source rendering a PDF without pdf-standard: ua-1 is flagged", {
  repo <- withr::local_tempdir("stdrepo-")
  qmd <- function(name, ...) writeLines(c("---", ..., "---", "body"),
                                        file.path(repo, name))
  qmd("typst-bare.qmd", "format:", "  html: default", "  typst: default")
  qmd("typst-ua.qmd", "format:", "  typst:", "    pdf-standard: ua-1")
  qmd("pdf-a2b.qmd", "format: pdf", "pdf-standard: [a-2b]")
  qmd("pdf-both.qmd", "format: pdf", "pdf-standard: [a-2b, ua-1]")
  qmd("html-only.qmd", "format: html")
  writeLines("no front matter", file.path(repo, "plain.qmd"))

  f <- check_pdf_standard(repo, "demo", exclude = character(0))
  expect_setequal(f$file, c("typst-bare.qmd", "pdf-a2b.qmd"))
  expect_identical(f$fix_target, f$file)
  expect_setequal(f$selector, c("format:typst", "format:pdf"))
  expect_error(check_pdf_standard(repo, "demo"), "exclude")
})

test_that("the project file sets the standard for its pages, and is flagged itself", {
  repo <- withr::local_tempdir("projrepo-")
  writeLines(c("---", "format:", "  typst: default", "---"),
             file.path(repo, "page.qmd"))
  writeLines(c("project:", "  type: book", "format:", "  typst:",
               "    pdf-standard: ua-1"), file.path(repo, "_quarto.yml"))
  expect_identical(nrow(check_pdf_standard(repo, "demo", exclude = character(0))), 0L)

  writeLines(c("project:", "  type: book", "format:", "  html: default",
               "  pdf: default"), file.path(repo, "_quarto.yml"))
  f <- check_pdf_standard(repo, "demo", exclude = character(0))
  expect_setequal(f$file, c("_quarto.yml", "page.qmd"))
})

test_that("the report lists every PDF and says NOT CHECKED when veraPDF did not run", {
  res <- data.frame(file = c("pages/summary.pdf", "assets/handout.pdf"),
                    origin = c("built", "carried"),
                    source_file = c("pages/summary.qmd", NA),
                    surface = "demo", status = c("failed", "passed"),
                    stringsAsFactors = FALSE)
  res$rules <- I(list("clause 7.1 test 11: no structure tree", character()))
  meta <- list(date = "2026-10-13", standard = "WCAG 2.1 AA", tool = "pa11y",
               repos = "demo", pages_examined = list(demo = 1L),
               declared = list(demo = 1L), surfaces = "demo",
               failed_pages = character(), cartridge_files = list(),
               zero_page_targets = character(), media_inventory = list(),
               notices = NULL,
               pdf_validation = list(standard = PDF_UA_LABEL, checked = TRUE,
                                     results = list(demo = res)))
  out <- withr::local_tempfile(fileext = ".md")
  empty <- finding("x","x","x","x","x","x","x")[0, ]
  render_report(empty, meta, out)
  txt <- paste(readLines(out), collapse = "\n")
  expect_match(txt, "## Published PDFs, validated against PDF/UA-1", fixed = TRUE)
  expect_match(txt, "built here, from `pages/summary.qmd` | failed", fixed = TRUE)
  expect_match(txt, "carried, not built here | passed", fixed = TRUE)
  expect_match(txt, "no structure tree", fixed = TRUE)
  expect_match(txt, "reading order", fixed = TRUE)
  expect_false(grepl("NOT CHECKED", txt, fixed = TRUE))

  meta$pdf_validation$checked <- FALSE
  meta$pdf_validation$results$demo$status <- "not checked"
  render_report(empty, meta, out)
  txt <- paste(readLines(out), collapse = "\n")
  expect_match(txt, "**NOT CHECKED.**", fixed = TRUE)
  expect_match(txt, "quarto install verapdf", fixed = TRUE)
})
