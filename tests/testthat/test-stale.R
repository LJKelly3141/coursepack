test_that("undated, stale, fresh and unmappable are each reported by slug", {
  p <- copy_course(); dir.create(file.path(p, "docs"))
  writeLines("x", file.path(p, "docs", "welcome.html"))
  course <- read_course(p); pages <- read_manifest(p)$pages
  r <- check_stale_heights(p, course, pages)
  expect_equal(r$undated, "welcome")
  pages$welcome$height_measured <- format(Sys.time() + 3600, "%Y-%m-%dT%H:%M:%S")
  expect_equal(check_stale_heights(p, course, pages)$fresh, "welcome")
  Sys.setFileTime(file.path(p, "docs", "welcome.html"), Sys.time() + 7200)
  expect_equal(check_stale_heights(p, course, pages)$stale, "welcome")
  pages$welcome$iframe <- "{site}/nowhere/else.html"
  expect_equal(check_stale_heights(p, course, pages)$unmappable, "welcome")
})
