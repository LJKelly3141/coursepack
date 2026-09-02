# The point of these tests is not "does it draw". It is that no fact about any
# one course is baked into the function: two different course.yml files must
# produce two different cards, and neither may be ECON 730's.

fixture <- function(dir, ...) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  yaml::write_yaml(list(...), file.path(dir, "course.yml"))
  dir
}

png_size <- function(path) {
  # IHDR width and height are big-endian uint32 at bytes 17..24.
  b <- readBin(path, "raw", n = 24L)
  as.integer(c(sum(as.integer(b[17:20]) * 256^(3:0)),
               sum(as.integer(b[21:24]) * 256^(3:0))))
}

test_that("the card is exactly Canvas's documented 262x146", {
  p <- fixture(file.path(tempdir(), "c1"), code = "ABCD 101", title = "A Course")
  out <- course_tile(p)
  expect_true(file.exists(out))
  expect_equal(png_size(out), c(262L, 146L))
})

test_that("the size is an argument, not a constant", {
  p <- fixture(file.path(tempdir(), "c2"), code = "ABCD 101", title = "A Course")
  out <- course_tile(p, out = file.path(tempdir(), "c2.png"),
                     width = 400L, height = 200L)
  expect_equal(png_size(out), c(400L, 200L))
})

test_that("it defaults into the course's own assets/images, not the caller's wd", {
  p <- fixture(file.path(tempdir(), "c3"), code = "ABCD 101", title = "A Course")
  out <- course_tile(p)
  expect_equal(normalizePath(out),
               normalizePath(file.path(p, "assets", "images", "course-tile.png")))
})

test_that("two different courses produce two different cards", {
  a <- fixture(file.path(tempdir(), "ca"), code = "ECON 202", title = "Macro Principles")
  b <- fixture(file.path(tempdir(), "cb"), code = "HIST 310", title = "Modern Europe")
  fa <- course_tile(a); fb <- course_tile(b)
  expect_false(identical(readBin(fa, "raw", file.size(fa)),
                         readBin(fb, "raw", file.size(fb))))
})

test_that("the palette comes from course.yml when the course declares one", {
  plain <- fixture(file.path(tempdir(), "cp1"), code = "ABCD 101", title = "A Course")
  fancy <- fixture(file.path(tempdir(), "cp2"), code = "ABCD 101", title = "A Course",
                   card = list(ink = "#301010", paper = "#ffffff",
                               accent = "#ffaa00", muted = "#aa7744"))
  f1 <- course_tile(plain); f2 <- course_tile(fancy)
  expect_false(identical(readBin(f1, "raw", file.size(f1)),
                         readBin(f2, "raw", file.size(f2))))
})

test_that("a given course renders reproducibly", {
  p <- fixture(file.path(tempdir(), "cr"), code = "ABCD 101", title = "A Course")
  f1 <- course_tile(p, out = file.path(tempdir(), "r1.png"), seed = 5L)
  f2 <- course_tile(p, out = file.path(tempdir(), "r2.png"), seed = 5L)
  expect_identical(readBin(f1, "raw", file.size(f1)),
                   readBin(f2, "raw", file.size(f2)))
})

test_that("a missing course.yml is a hard stop, not a default card", {
  d <- file.path(tempdir(), "empty"); dir.create(d, showWarnings = FALSE)
  expect_error(course_tile(d), "course\\.yml")
})
