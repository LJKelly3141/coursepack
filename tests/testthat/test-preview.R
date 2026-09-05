model <- function(base = "local") {
  skip_if_no("pandoc")
  to <- withr::local_tempdir(.local_envir = parent.frame())
  p <- copy_course(to = to)
  j <- build_preview(p, base = base)
  list(p = p, j = jsonlite::fromJSON(file.path(p, "build", "mockup", "course.json"), simplifyVector = FALSE),
       items = unlist(lapply(j$modules, function(m) m$items), recursive = FALSE))
}

test_that("shape: course block, stats block, modules, textbook_present TRUE against the fake textbook", {
  m <- model()
  expect_false(is.null(m$j$course$code)); expect_false(is.null(m$j$stats$items))
  expect_true(length(m$j$modules) > 0); expect_true(isTRUE(m$j$course$textbook_present))
  expect_equal(length(m$j$modules), m$j$stats$modules); expect_equal(length(m$items), m$j$stats$items)
})

test_that("every item is well formed and type rules hold", {
  m <- model(); it <- m$items
  expect_true(all(vapply(it, function(i) i$form %in% c("header", "page", "link", "assignment", "quiz"), TRUE)))
  expect_true(all(vapply(it, function(i) i$content_type %in% c("ContextModuleSubHeader", "WikiPage", "ExternalUrl", "Assignment", "Quizzes::Quiz"), TRUE)))
  expect_true(all(vapply(it, function(i) i$target$state %in% c("ok", "missing-chapter", "missing-anchor", "unchecked", "none", "external"), TRUE)))
  expect_true(all(vapply(it, function(i) nzchar(i$title), TRUE)))
  hdr <- Filter(function(i) i$form == "header", it); lnk <- Filter(function(i) i$form == "link", it); pag <- Filter(function(i) i$form == "page", it)
  expect_true(all(vapply(hdr, function(i) is.null(i$url), TRUE)))
  expect_true(length(lnk) > 0 && all(vapply(lnk, function(i) !is.null(i$url), TRUE)))
  bare <- function(x) !is.null(x) && grepl("^[0-9]+$", as.character(x))
  expect_true(all(vapply(pag, function(i) !is.null(i$frame$width) && !is.null(i$frame$height), TRUE)))
  expect_false(any(vapply(pag, function(i) bare(i$frame$width) || bare(i$frame$height), TRUE)))
})

test_that("todo items are unpublished and the stats reconcile", {
  m <- model(); it <- m$items
  td <- Filter(function(i) !is.null(i$todo), it)
  expect_true(all(vapply(td, function(i) isFALSE(i$published), TRUE)))
  brk <- Filter(function(i) i$target$state %in% c("missing-chapter", "missing-anchor"), it)
  expect_equal(length(brk), m$j$stats$broken); expect_equal(length(td), m$j$stats$todo)
})

test_that("body pages, homework directions and quiz questions are written as same-origin pages", {
  m <- model()
  expect_true(file.exists(file.path(m$p, "build", "mockup", "pages", "chapter-one.html")))
  expect_true(file.exists(file.path(m$p, "build", "mockup", "assignments", "hw-1.html")))
  expect_true(file.exists(file.path(m$p, "build", "mockup", "quizzes", "quiz-1.html")))
  q <- paste(readLines(file.path(m$p, "build", "mockup", "quizzes", "quiz-1.html")), collapse = "\n")
  expect_no_match(q, "ANSWER KEY")
  expect_true(file.exists(file.path(m$p, "build", "mockup", "mockup.js")))
  expect_true(Sys.readlink(file.path(m$p, "build", "mockup", "textbook")) != "")
})

test_that("live mode points links at the published textbook and creates no symlink", {
  m <- model("live")
  lnk <- Filter(function(i) i$form == "link" && !is.null(i$url) && grepl("ch01", i$url), m$items)
  expect_match(lnk[[1]]$url, "^https://example.invalid/book/")
  expect_false(file.exists(file.path(m$p, "build", "mockup", "textbook")))
})

test_that("textbook_docs: none previews with every chapter target unchecked and no symlink", {
  skip_if_no("pandoc")
  p <- copy_course()
  edit_yaml(p, "course.yml", "textbook_docs: ../fake-textbook/docs", "textbook_docs: none")
  build_preview(p)
  j <- jsonlite::fromJSON(file.path(p, "build", "mockup", "course.json"), simplifyVector = FALSE)
  expect_false(isTRUE(j$course$textbook_present))
  expect_false(file.exists(file.path(p, "build", "mockup", "textbook")))
  it <- unlist(lapply(j$modules, function(m) m$items), recursive = FALSE)
  ch <- Filter(function(i) identical(i$form, "link"), it)
  expect_true(all(vapply(ch, function(i) identical(i$target$state, "unchecked") ||
                                         identical(i$target$state, "external"), TRUE)))
  expect_true(any(vapply(ch, function(i) identical(i$target$detail, "textbook_docs: none"), TRUE)))
})

test_that("in local mode a rendered docs/ is served as /site and {site} points at it", {
  skip_if_no("pandoc")
  p <- copy_course(); dir.create(file.path(p, "docs")); writeLines("<p>w</p>", file.path(p, "docs", "welcome.html"))
  build_preview(p)
  j <- jsonlite::fromJSON(file.path(p, "build", "mockup", "course.json"), simplifyVector = FALSE)
  welcome <- Filter(function(i) identical(i$title, "Welcome"), unlist(lapply(j$modules, function(m) m$items), recursive = FALSE))[[1]]
  expect_equal(welcome$url, "/site/welcome.html")
  expect_true(nzchar(Sys.readlink(file.path(p, "build", "mockup", "site"))))
})

test_that("an absent textbook_docs key is an error, not a sibling-layout guess", {
  p <- copy_course()
  y <- readLines(file.path(p, "course.yml")); writeLines(y[!grepl("^textbook_docs:", y)], file.path(p, "course.yml"))
  expect_error(build_preview(p), "textbook_docs")
})
