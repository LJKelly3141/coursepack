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

# ---- falcon and falcon-light ---------------------------------------------------

falcon_src <- function(id, f = NULL) {
  p <- system.file("templates", "slides", "_extensions", id, package = "coursepack")
  if (is.null(f)) p else file.path(p, f)
}

for (style in list(list("falcon", use_falcon_slides), list("falcon-light", use_falcon_light_slides))) {
  id <- style[[1]]; fn <- style[[2]]
  test_that(paste(id, "installs under slides/, returns its path and refuses to overwrite"), {
    p <- slides_course()
    out <- expect_output(fn(p), "coursepack")
    ext <- file.path(p, "slides", "_extensions", id)
    expect_equal(normalizePath(out), normalizePath(ext))
    for (f in c("_extension.yml", "falcon-palette.scss", "falcon-rules.scss",
                "falcon-fonts.scss", "divider.html", "OFL-BarlowCondensed.txt", "OFL-NunitoSans.txt"))
      expect_true(file.exists(file.path(ext, f)), info = f)
    expect_false(any(grepl("logo", list.files(ext), ignore.case = TRUE)))
    expect_error(fn(p), "already")
    expect_output(fn(p, overwrite = TRUE))
  })
}

test_that("falcon and falcon-light share their rules, fonts and divider byte for byte", {
  # The two styles differ only in falcon-palette.scss and _extension.yml.
  for (f in c("falcon-rules.scss", "falcon-fonts.scss", "divider.html",
              "OFL-BarlowCondensed.txt", "OFL-NunitoSans.txt"))
    expect_identical(unname(tools::md5sum(falcon_src("falcon", f))),
                     unname(tools::md5sum(falcon_src("falcon-light", f))), info = f)
})

test_that("falcon fonts are embedded, never fetched", {
  fonts <- readLines(falcon_src("falcon", "falcon-fonts.scss"), warn = FALSE)
  expect_equal(sum(grepl("@font-face", fonts, fixed = TRUE)), 5L)
  expect_equal(sum(grepl("url(\"data:font/woff2;base64,", fonts, fixed = TRUE)), 5L)
  for (id in c("falcon", "falcon-light"))
    for (f in list.files(falcon_src(id), pattern = "\\.(scss|yml|html)$", full.names = TRUE))
      expect_false(any(grepl("https?://", readLines(f, warn = FALSE))), info = f)
})

test_that("every falcon text colour clears 4.5:1 on the slide and the callout panel", {
  lum <- function(h) {
    v <- strtoi(substring(h, c(2, 4, 6), c(3, 5, 7)), 16L) / 255
    v <- ifelse(v <= 0.04045, v / 12.92, ((v + 0.055) / 1.055)^2.4)
    sum(c(0.2126, 0.7152, 0.0722) * v)
  }
  ratio <- function(a, b) { l <- sort(c(lum(a), lum(b))); (l[2] + 0.05) / (l[1] + 0.05) }
  for (id in c("falcon", "falcon-light")) {
    x <- readLines(falcon_src(id, "falcon-palette.scss"), warn = FALSE)
    m <- regmatches(x, regexec("^\\$falcon-([a-z-]+): *(#[0-9A-Fa-f]{6});", x))
    pal <- stats::setNames(vapply(m[lengths(m) == 3], `[`, "", 3),
                           vapply(m[lengths(m) == 3], `[`, "", 2))
    for (fg in c("ink", "muted", "accent", "label", "green", "orange"))
      for (bg in c("paper", "panel"))
        expect_gte(ratio(pal[[fg]], pal[[bg]]), 4.5)
    expect_gte(ratio(pal[["band-text"]], pal[["band"]]), 4.5)
  }
})

test_that("decks render with format falcon-revealjs and falcon-light-revealjs", {
  skip_if_no("quarto")
  for (id in c("falcon", "falcon-light")) {
    d <- withr::local_tempdir()
    dir.create(file.path(d, "_extensions"))
    file.copy(falcon_src(id), file.path(d, "_extensions"), recursive = TRUE)
    deck <- file.path(d, "deck.qmd")
    writeLines(c("---", "title: \"Deck\"", "format:", paste0("  ", id, "-revealjs:"),
                 "    footer: \"Test\"", "---", "", "## One", "", "- a point",
                 "", "# Two {.section-header}"), deck)
    status <- system2("quarto", c("render", shQuote(deck)), stdout = FALSE, stderr = FALSE)
    expect_equal(status, 0L, info = id)
    html <- readLines(file.path(d, "deck.html"), warn = FALSE)
    # embed-resources inlines each stylesheet URL-encoded: a space is %20.
    expect_true(any(grepl("Barlow%20Condensed", html, fixed = TRUE)), info = id)
    expect_false(any(grepl("fonts.googleapis", html, fixed = TRUE)), info = id)
    # Quarto's own CSS names the class; a logo would be an element carrying it.
    expect_false(any(grepl("class=\"slide-logo", html, fixed = TRUE)), info = id)
  }
})
