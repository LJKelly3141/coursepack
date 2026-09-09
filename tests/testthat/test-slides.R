# use_uwrf_slides() installs the UWRF reveal.js format extension into a course.
# The fixture is the package's own scaffold, as everywhere else in the suite.

slides_course <- function() {
  d <- withr::local_tempdir(.local_envir = parent.frame()); p <- file.path(d, "c")
  init_course(p, code = "ABCD 101", title = "A Course", site_url = "https://example.invalid/c",
              timezone = "America/Chicago", ask = FALSE, git = FALSE)
  p
}

test_that("use_uwrf_slides copies the extension under slides/ and returns its path", {
  p <- slides_course()
  out <- expect_output(use_uwrf_slides(p), "coursepack")
  ext <- file.path(p, "slides", "_extensions", "uwrf")
  expect_equal(normalizePath(out), normalizePath(ext))
  for (f in c("_extension.yml", "uwrf.scss", "uwrf-logo.png"))
    expect_true(file.exists(file.path(ext, f)), info = f)
  # The logo is binary and must arrive byte for byte, not through the template
  # renderer that init_course() pushes the course template through.
  src <- system.file("templates", "slides", "_extensions", "uwrf", "uwrf-logo.png",
                     package = "coursepack")
  expect_identical(unname(tools::md5sum(file.path(ext, "uwrf-logo.png"))),
                   unname(tools::md5sum(src)))
})

test_that("use_uwrf_slides refuses to overwrite an installed copy unless told to", {
  p <- slides_course()
  expect_output(use_uwrf_slides(p))
  scss <- file.path(p, "slides", "_extensions", "uwrf", "uwrf.scss")
  writeLines("// edited", scss)
  expect_error(use_uwrf_slides(p), "already")
  expect_equal(readLines(scss), "// edited")
  expect_output(use_uwrf_slides(p, overwrite = TRUE))
  expect_true(any(grepl("scss:defaults", readLines(scss), fixed = TRUE)))
})

test_that("use_uwrf_slides takes another deck directory and refuses a missing course", {
  p <- slides_course()
  expect_output(use_uwrf_slides(p, dir = "decks"))
  expect_true(file.exists(file.path(p, "decks", "_extensions", "uwrf", "_extension.yml")))
  expect_false(dir.exists(file.path(p, "slides")))
  expect_error(use_uwrf_slides(file.path(p, "nowhere")), "not a directory")
})

test_that("a deck in the course renders with format uwrf-revealjs", {
  skip_if_no("quarto")
  p <- slides_course()
  expect_output(use_uwrf_slides(p))
  deck <- file.path(p, "slides", "deck.qmd")
  writeLines(c("---", "title: \"Deck\"", "format:", "  uwrf-revealjs:",
               "    footer: \"Test\"", "---", "", "## One", "", "- a point"), deck)
  # A file outside the scaffold's render allowlist renders standalone, beside
  # its source, and never reaches docs/. The closing summary tells a course to
  # add the deck directory to the list; this is that step, done to the fixture.
  # As a text edit: yaml::write_yaml() emits YAML 1.1 booleans (`yes`, `no`),
  # and Quarto reads YAML 1.2 and refuses the file.
  qy <- file.path(p, "_quarto.yml"); lines <- readLines(qy)
  at <- grep('- "content/**/*.qmd"', lines, fixed = TRUE)
  expect_length(at, 1L)
  writeLines(append(lines, '    - "slides/**/*.qmd"', after = at), qy)
  status <- system2("quarto", c("render", shQuote(deck)), stdout = FALSE, stderr = FALSE)
  expect_equal(status, 0L)
  html <- file.path(p, "docs", "slides", "deck.html")
  expect_true(file.exists(html))
  expect_true(any(grepl("slide-logo", readLines(html, warn = FALSE), fixed = TRUE)))
})
