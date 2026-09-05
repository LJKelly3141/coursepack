# The Python-schema snapshot this package was ported from, when the checkout
# holds one. Found by what a directory CONTAINS rather than by its name: the
# name carries a course number, and no course number belongs in a test file.
# The marker is a modules.yml whose first module declares
# require_sequential_progress, which is the Python schema and nothing else.
python_snapshot <- function() {
  root <- testthat::test_path("..", "..", "project")
  if (!dir.exists(root)) return(NULL)
  for (d in list.dirs(root, recursive = FALSE)) {
    inputs <- file.path(d, "inputs")
    f <- file.path(inputs, "modules.yml")
    if (!file.exists(f) || !file.exists(file.path(inputs, "course.yml"))) next
    y <- tryCatch(yaml::yaml.load_file(f), error = function(e) NULL)
    if (is.null(y$modules) || !length(y$modules)) next
    if (is.null(y$modules[[1]]$require_sequential_progress)) next
    return(inputs)
  }
  NULL
}

test_that("the converter writes the R schema with pinned ids, dissolved due dates and the header comments", {
  out <- withr::local_tempdir()
  convert_python_manifests(fixture_path("python-schema", "course.yml"), fixture_path("python-schema", "modules.yml"), out)
  m <- read_manifest(out)
  expect_equal(m$course$textbook_docs, "none"); expect_equal(m$course$due_time, "23:59:59")
  # chapters comes back as an integer vector, not a list: the YAML reader
  # simplifies a sequence of like scalars, so no file it could write would give
  # a list. bank_groups() unlists it either way.
  q <- m$quizzes[[1]]; expect_equal(q$bank$chapters, c(1L, 2L)); expect_equal(q$due, "2026-09-13")
  expect_equal(q$resource_id, gid_py("res", m$mods$modules[[1]]$title, q$title))
  expect_true(any(vapply(m$pages, function(p) !is.null(p$source_ref), TRUE)))
  expect_true(any(vapply(m$pages, function(p) !is.null(p$height_measured), TRUE)))
  expect_equal(readLines(file.path(out, "modules.yml"), n = 1), readLines(fixture_path("python-schema", "modules.yml"), n = 1))
  groups <- vapply(m$quizzes, function(q) q$group, "")
  expect_true(all(nzchar(groups))); expect_true("Module Quizzes" %in% groups)
  expect_null(m$course$canvas$course_image)
})

test_that("a position gap is renumbered with a printed note; the course image produces a printed instruction", {
  out <- withr::local_tempdir()
  expect_output(convert_python_manifests(fixture_path("python-schema", "course.yml"), fixture_path("python-schema", "modules.yml"), out),
                "positions renumbered: 3 -> 2")
  expect_output(convert_python_manifests(fixture_path("python-schema", "course.yml"), fixture_path("python-schema", "modules.yml"), file.path(out, "b")),
                "course image: copy images/card.png to assets/images/course-tile.png")
})

test_that("an unmatched due_dates key, a duplicate title, and a non-increasing position each stop", {
  out <- withr::local_tempdir()
  c1 <- fixture_path("python-schema", "course.yml"); m1 <- fixture_path("python-schema", "modules.yml")
  cbad <- file.path(out, "c.yml"); writeLines(c(readLines(c1), '  "Nowhere Quiz": 2026-10-01'), cbad)
  expect_error(convert_python_manifests(cbad, m1, file.path(out, "a")), "due_dates names an item that does not exist: Nowhere Quiz")
  y <- readLines(m1); i <- grep("position: 2$", y)[1]; y[i] <- "        position: 1"
  mbad <- file.path(out, "m.yml"); writeLines(y, mbad)
  expect_error(convert_python_manifests(c1, mbad, file.path(out, "b")), "positions are not strictly increasing")
  y2 <- readLines(m1); titles <- grep("^      - title: ", y2); y2[titles[2]] <- y2[titles[1]]
  mdup <- file.path(out, "d.yml"); writeLines(y2, mdup)
  expect_error(convert_python_manifests(c1, mdup, file.path(out, "c")), "titles are not unique within kind")
})

test_that("gid_py matches the Python convention", {
  expect_equal(gid_py("res", "M", "T"), paste0("g", digest::digest("res::M::T", algo = "md5", serialize = FALSE)))
})

test_that("the Python-schema snapshot converts and parses, when present", {
  snap <- python_snapshot()
  skip_if(is.null(snap), "snapshot not present")
  out <- withr::local_tempdir()
  convert_python_manifests(file.path(snap, "course.yml"), file.path(snap, "modules.yml"), out)
  m <- read_manifest(out); py <- yaml::yaml.load_file(file.path(snap, "modules.yml"))
  expect_length(m$mods$modules, length(py$modules))
  expect_equal(sum(lengths(lapply(m$mods$modules, `[[`, "items"))), sum(lengths(lapply(py$modules, `[[`, "items"))))
})
