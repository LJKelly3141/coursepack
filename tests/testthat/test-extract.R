# The export under test is fixtures/src/, the synthetic Canvas export
# copy_course() zips into every fixture copy: one module carrying one page that
# is a pure iframe wrapper, one page that is not, an assignment, a quiz, a
# subheader and an external link.
extracted <- function() {
  skip_if_no("zip")
  to <- withr::local_tempdir(.local_envir = parent.frame())
  p <- copy_course(to = to); out <- withr::local_tempdir(.local_envir = parent.frame())
  extract_manifest(file.path(p, "reference", "source.imscc"), out)
  out
}

test_that("extract writes three files the package can read, and copies the export", {
  out <- extracted()
  expect_true(all(file.exists(file.path(out, c("course.yml", "modules.yml", "reference.yml", "reference/source.imscc")))))
  m <- read_manifest(out)
  expect_equal(m$course$code, "SRC 100"); expect_equal(m$course$urls$site, "https://example.invalid/course")
  expect_equal(m$course$assignment_groups[[1]]$id, "g0000000000000000000000000000000b")
  expect_equal(read_reference(out)$source, "reference/source.imscc")
})

test_that("a pure wrapper page becomes iframe:, everything else becomes source_ref:", {
  out <- extracted(); m <- read_manifest(out)
  # A page's slug is its href stem, so the fixture's wiki_content/wrapper-page.html
  # is keyed "wrapper-page" whatever its title says.
  w <- m$pages[["wrapper-page"]]; expect_equal(w$iframe, "https://example.invalid/course/wrapped.html"); expect_equal(w$height, "1200px"); expect_null(w$source_ref)
  cp <- m$pages[["carried-page"]]; expect_equal(cp$source_ref, "g00000000000000000000000000000c01"); expect_null(cp$iframe)
  expect_equal(m$assignments[["old-assignment-title"]]$source_ref, "g00000000000000000000000000000a01")
  expect_equal(m$quizzes[["old-quiz-title"]]$source_ref, "g00000000000000000000000000000q01")
  forms <- vapply(m$mods$modules[[1]]$items, function(it) intersect(c("header", "page", "link", "assignment", "quiz"), names(it))[1], "")
  expect_equal(forms, c("page", "page", "assignment", "quiz", "header", "link"))
  expect_equal(m$mods$modules[[1]]$items[[6]]$url, "https://example.invalid/out")
  expect_null(w$height_measured)
})

test_that("extract never overwrites unless told", {
  out <- extracted()
  p <- copy_course()
  expect_error(extract_manifest(file.path(p, "reference", "source.imscc"), out), "already exist")
  expect_no_error(extract_manifest(file.path(p, "reference", "source.imscc"), out, overwrite = TRUE))
})

test_that("a page holding the wrapper and anything else is carried, never regenerated", {
  # Review 9, and the one case the fixture cannot show: the extractor this ports
  # rebuilt any page holding an <iframe> from that one frame, so a page carrying
  # a frame AND a paragraph of the instructor's own writing came back as a bare
  # frame with the paragraph gone.
  inner <- iframe_wrapper("A", "https://example.invalid/a.html", "100%", "600px")
  page <- function(x) paste0("<html>\n<head>\n<title>A</title>\n</head>\n<body>\n", x, "\n</body>\n</html>")
  expect_true(page_from_html(page(inner), "a")$wrapper)
  expect_false(page_from_html(page(paste0(inner, "\n<p>Read this first.</p>")), "a")$wrapper)
})

test_that("the site URL is a directory, never a truncated segment", {
  skip_if_no("zip")
  d <- withr::local_tempdir()
  z <- write_a11y_cartridge(file.path(d, "c.imscc"), pages = list(
    list(slug = "a", title = "A", src = "https://example.invalid/pages/ch01/CH01.html"),
    list(slug = "b", title = "B", src = "https://example.invalid/pages/ch02/CH02.html")))
  out <- file.path(d, "out"); extract_manifest(z, out)
  expect_equal(read_course(out)$urls$site, "https://example.invalid/pages")
})
