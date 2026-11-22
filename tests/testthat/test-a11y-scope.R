# audit_course(modules =): a module audit reads only what modules.yml places
# in the named modules, says so, and never becomes the full-course baseline.

scope_fixture <- function(env = parent.frame()) {
  d <- withr::local_tempdir(.local_envir = env)
  proj <- file.path(d, "course")
  invisible(capture.output(init_course(proj, code = "ABCD 101", title = "A Course",
    site_url = "https://example.org/c", textbook_url = "https://example.org/book",
    timezone = "UTC", ask = FALSE, git = FALSE, skills = FALSE)))
  writeLines(c(
    "modules:",
    "  - title: \"Module A\"",
    "    published: true",
    "    items:",
    "      - page: welcome",
    "      - link: \"Chapter 1\"",
    "        chapter: ch01",
    "      - assignment: first-assignment",
    "  - title: \"Module B\"",
    "    published: true",
    "    items:",
    "      - page: other",
    "      - link: \"Gone\"",
    "        url: \"{site}/content/pages/gone.html\"",
    "      - link: \"A video\"",
    "        url: \"https://video.example.org/watch?v=abc\"",
    "pages:",
    "  - slug: welcome",
    "    title: Welcome",
    "    iframe: \"{site}/content/pages/welcome.html\"",
    "    height: \"800\"",
    "  - slug: other",
    "    title: Other",
    "    iframe: \"{site}/content/pages/other.html\"",
    "    height: \"800\"",
    "assignments:",
    "  - id: first-assignment",
    "    title: First Assignment",
    "    published: false",
    "    todo: \"replace me\""), file.path(proj, "modules.yml"))
  pg <- file.path(proj, "docs", "content", "pages"); dir.create(pg, recursive = TRUE)
  dir.create(file.path(proj, "docs", "slides"))
  dir.create(file.path(proj, "content", "pages"), recursive = TRUE, showWarnings = FALSE)
  page <- function(f, body) writeLines(paste0("<html lang='en'><title>t</title><body>",
                                              body, "</body></html>"), f)
  page(file.path(pg, "welcome.html"),
       "<a href=\"../../slides/deck.html\">Slides</a> <a href=\"handout.pdf\">Handout</a>")
  page(file.path(pg, "other.html"), "<a href=\"../../slides/other-deck.html\">x</a>")
  page(file.path(proj, "docs", "index.html"), "home")
  writeLines("<div class=\"reveal\"></div>", file.path(proj, "docs", "slides", "deck.html"))
  writeLines("<div class=\"reveal\"></div>", file.path(proj, "docs", "slides", "other-deck.html"))
  writeLines("%PDF-1.4", file.path(pg, "handout.pdf"))
  writeLines("Hi", file.path(proj, "content", "pages", "welcome.qmd"))
  writeLines("Hi", file.path(proj, "content", "pages", "other.qmd"))

  book <- file.path(d, "book")
  dir.create(file.path(book, "docs"), recursive = TRUE)
  writeLines(c("project:", "  type: book", "  output-dir: docs"), file.path(book, "_quarto.yml"))
  page(file.path(book, "docs", "ch01.html"), "one")
  page(file.path(book, "docs", "ch02.html"), "two")
  writeLines("x", file.path(book, "ch01.qmd")); writeLines("x", file.path(book, "ch02.qmd"))
  list(proj = proj, book = book)
}

test_that("a module scope reaches its item pages, their decks and PDFs, and the textbook", {
  fx <- scope_fixture()
  sc <- audit_scope(fx$proj, "Module A", c(fx$proj, fx$book))
  expect_equal(sc$modules, "Module A")
  expect_equal(sc$slug, "module-a")
  site <- scope_target(sc, discover_target(fx$proj))
  expect_equal(site$pages, "content/pages/welcome.html")
  expect_equal(site$decks, "slides/deck.html")         # other-deck is Module B's
  expect_equal(site$pdfs, "content/pages/handout.pdf")
  expect_length(site$missing, 0)
  expect_false("content/pages/welcome.qmd" %in% site$exclude)
  expect_true("content/pages/other.qmd" %in% site$exclude)
  tb <- scope_target(sc, discover_target(fx$book))
  expect_equal(tb$pages, "ch01.html")
  expect_equal(tb$exclude, "ch02.qmd")
})

test_that("a scoped item URL with no rendered page is reported; an outside URL is not audited", {
  fx <- scope_fixture()
  sc <- audit_scope(fx$proj, "Module B", fx$proj)
  st <- scope_target(sc, discover_target(fx$proj))
  expect_equal(st$pages, "content/pages/other.html")
  expect_equal(st$missing, "https://example.org/c/content/pages/gone.html")
  expect_true("https://video.example.org/watch?v=abc" %in% sc$urls)
})

test_that("an unknown module title and an ambiguous textbook repo both stop", {
  fx <- scope_fixture()
  expect_error(audit_scope(fx$proj, "Module Z", fx$proj), "not in modules.yml")
  other <- file.path(dirname(fx$book), "book2"); dir.create(other)
  expect_error(audit_scope(fx$proj, "Module A", c(fx$proj, fx$book, other)), "separate runs")
  expect_null(audit_scope(fx$proj, NULL, fx$proj))
})

test_that("a module audit of a cartridge reads only that module's wiki pages", {
  skip_if_no("zip")
  fx <- scope_fixture()
  invisible(capture.output(build_cartridge(fx$proj)))
  z <- cartridges_in(fx$proj)
  expect_length(z, 1)
  stub <- function(id) ""
  all <- audit_cartridge(z, "c-cartridge", video_fetch = stub)
  one <- audit_cartridge(z, "c-cartridge", video_fetch = stub, modules = "Module A")
  expect_equal(attr(all, "wiki_pages_read"), 2L)
  expect_equal(attr(one, "wiki_pages_read"), 1L)
  expect_equal(attr(one, "topics_read"), 0L)
  expect_equal(cartridge_wiki_page_count(z, "Module A"), 1L)
  expect_error(audit_cartridge(z, "c-cartridge", video_fetch = stub, modules = "Module Z"),
               "rebuild it")
})

test_that("audit_course(modules =) states its scope, counts against it, and keeps the baseline apart", {
  fx <- scope_fixture()
  out <- file.path(dirname(fx$proj), "a11y")
  local_mocked_bindings(
    pa11y_raw = function(url, ...) list(),
    serve_dir = function(dir, port = 8766L) list(url = "http://127.0.0.1:1", stop = function() NULL),
    ask_about_verapdf = function(...) NA_character_)
  run <- function(...) {
    res <- NULL
    invisible(capture.output(res <- audit_course(c(fx$proj, fx$book), proj = fx$proj,
      out_dir = out, cartridge_dirs = "none", video_fetch = function(id) "",
      verapdf = NA_character_, ...)))
    res
  }
  full <- run()
  today <- format(Sys.Date(), "%Y-%m-%d")
  expect_equal(basename(full$files[1]), paste0(today, "-findings.json"))
  expect_null(full$meta$scope)
  full_bytes <- readBin(full$files[1], "raw", file.size(full$files[1]))

  mod <- run(modules = "Module B")
  expect_equal(basename(mod$files), paste0(today, "-module-b-", c("findings.json", "findings.md", "plan.md")))
  expect_identical(readBin(full$files[1], "raw", file.size(full$files[1])), full_bytes)
  expect_equal(mod$meta$scope$modules, "Module B")
  pe <- unlist(mod$meta$pages_examined); dec <- unlist(mod$meta$declared)
  expect_equal(pe[["course"]], 2L)                 # other.html and its deck
  expect_equal(dec[["course"]], 2L)
  expect_false("book" %in% names(dec))             # Module B places nothing there
  expect_true(any(grepl("gone.html", mod$findings$file, fixed = TRUE)))
  rep <- readLines(mod$files[2])
  expect_true(any(grepl("NOT a full-course audit", rep, fixed = TRUE)))
  expect_true(any(grepl("video.example.org", rep, fixed = TRUE)))
  expect_true(any(grepl("module audit of Module B", readLines(mod$files[3]), fixed = TRUE)))

  # The full-course run never diffs against a module audit.
  writeLines(readLines(mod$files[1]), file.path(out, "2000-01-01-module-b-findings.json"))
  msg <- capture.output(audit_course(c(fx$proj, fx$book), proj = fx$proj, out_dir = out,
    cartridge_dirs = "none", video_fetch = function(id) "", verapdf = NA_character_))
  expect_false(any(grepl("module-b", msg, fixed = TRUE)))
})
