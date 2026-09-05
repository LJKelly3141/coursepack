u <- list(textbook = "https://tb.example", site = "https://site.example", legacy = "https://old.example")

test_that("interp_urls replaces each named token and passes NULL through", {
  expect_equal(interp_urls("{textbook}/ch.html", u), "https://tb.example/ch.html")
  expect_equal(interp_urls("{legacy}/w.html", u), "https://old.example/w.html")
  expect_equal(interp_urls("{site}/x.html", u), "https://site.example/x.html")
  expect_equal(interp_urls("https://youtube/embed/1", u), "https://youtube/embed/1")
  expect_null(interp_urls(NULL, u))
})

test_that("chapter_url builds the textbook link, root for an empty chapter", {
  expect_equal(chapter_url("030_regression", NULL, "https://tb.example"), "https://tb.example/030_regression.html")
  expect_equal(chapter_url("030_regression", "homework", "https://tb.example"), "https://tb.example/030_regression.html#homework")
  expect_equal(chapter_url(NULL, NULL, "https://tb.example"), "https://tb.example/")
  expect_equal(chapter_url("", NULL, "https://tb.example"), "https://tb.example/")
})

test_that("resolve_target reports the four states, and empty chapter is unchecked even with a real dir", {
  tmp <- withr::local_tempdir()
  writeLines('<h2 id="homework-assignment">HW</h2>', file.path(tmp, "030_regression.html"))
  expect_equal(resolve_target("030_regression", "homework-assignment", tmp)$state, "ok")
  expect_equal(resolve_target("030_regression", "nope", tmp)$state, "missing-anchor")
  expect_equal(resolve_target("999_nope", NULL, tmp)$state, "missing-chapter")
  expect_equal(resolve_target("030_regression", NULL, tmp)$state, "ok")
  expect_equal(resolve_target("030_regression", NULL, "/definitely/not/here")$state, "unchecked")
  # Regression: the fail-open scar. An empty chapter with a real textbook dir
  # must come back unchecked, not silently resolved.
  expect_equal(resolve_target("", NULL, tmp)$state, "unchecked")
})

test_that("collect_refs includes chapter items and homework chapters, excludes the empty root link", {
  mods_t <- list(
    modules = list(list(items = list(
      list(chapter = "010_intro-R", anchor = NULL, link = "Reading: Chapter 1"),
      list(chapter = "", anchor = NULL, link = "Textbook root")))),
    assignments = list(list(id = "homework-1",
      homework = list(chapter = "015_case-first_look", anchor = "homework-assignment")))
  )
  refs <- collect_refs(mods_t)
  expect_length(refs, 2L)
  expect_length(Filter(function(r) identical(r$ch, "010_intro-R"), refs), 1L)
  expect_length(Filter(function(r) identical(r$ch, ""), refs), 0L)
  expect_length(Filter(function(r) identical(r$ch, "015_case-first_look"), refs), 1L)
})
