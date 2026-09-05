test_that("announcements: two topics, two metas, the right states and a UTC stamp from the declared zone", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  res <- build_cartridge(p)
  man <- paste(readLines(file.path(res$stage, "imsmanifest.xml")), collapse = "\n")
  expect_length(gregexpr('type="imsdt_xmlv1p1"', man)[[1]], 2L)
  metas <- list.files(res$stage, pattern = "\\.xml$", full.names = TRUE)
  metas <- metas[vapply(metas, function(f) any(grepl("<topicMeta", readLines(f, warn = FALSE))), TRUE)]
  expect_length(metas, 2L)
  txt <- vapply(metas, function(f) paste(readLines(f), collapse = "\n"), "")
  expect_true(any(grepl("<workflow_state>active</workflow_state>", txt) & !grepl("delayed_post_at", txt)))
  expect_true(any(grepl("<delayed_post_at>2026-09-08T05:00:00</delayed_post_at>", txt, fixed = TRUE)))
  # the body lost its <h2>
  topics <- list.files(res$stage, pattern = "\\.xml$", full.names = TRUE)
  topics <- topics[vapply(topics, function(f) any(grepl("<topic ", readLines(f, warn = FALSE))), TRUE)]
  expect_false(any(grepl("&lt;h2&gt;", vapply(topics, function(f) paste(readLines(f), collapse = ""), ""))))
})

test_that("a different zone produces a different stamp, and a missing body stops", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  y <- readLines(file.path(p, "announcements.yml"))
  writeLines(sub("America/Chicago", "Europe/London", y), file.path(p, "announcements.yml"))
  res <- build_cartridge(p)
  allx <- vapply(list.files(res$stage, pattern = "\\.xml$", full.names = TRUE), function(f) paste(readLines(f), collapse = ""), "")
  expect_true(any(grepl("<delayed_post_at>2026-09-07T23:00:00</delayed_post_at>", allx, fixed = TRUE)))
  unlink(file.path(p, "content", "announcements", "week-2.html"))
  expect_error(build_cartridge(p), "names a body file that does not exist")
})

test_that("an unknown post: form stops, and a body whose h2 disagrees with the title stops", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  y <- readLines(file.path(p, "announcements.yml"))
  writeLines(sub("post: 2026-09-08", "post: next monday", y), file.path(p, "announcements.yml"))
  expect_error(build_cartridge(p), "post must be 'immediately'")
  writeLines(y, file.path(p, "announcements.yml"))
  writeLines(c("<h2>Different</h2>", "<p>x</p>"), file.path(p, "content", "announcements", "week-2.html"))
  expect_error(build_cartridge(p), "the body's <h2> reads")
})

test_that("the term window is required only when an announcement posts on a date", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  # A fresh scaffold's shape: the registrar's dates are not in yet, so the term
  # window is null, and the one announcement posts on import.
  edit_yaml(p, "course.yml", "  first_day: 2026-09-01\n  last_day: 2026-12-15\n",
            "  first_day: null\n  last_day: null\n")
  now <- c("body_dir: content/announcements", "announcements:",
           "  - id: welcome", "    title: Welcome to the course",
           "    body: welcome.html", "    post: immediately")
  writeLines(now, file.path(p, "announcements.yml"))
  res <- build_cartridge(p)
  allx <- vapply(list.files(res$stage, pattern = "\\.xml$", full.names = TRUE),
                 function(f) paste(readLines(f), collapse = ""), "")
  expect_false(any(grepl("delayed_post_at", allx, fixed = TRUE)))

  # One dated post and the window is required again, because that post time is
  # the thing the window exists to check.
  writeLines(c(now, "  - id: week-2", "    title: Week 2 begins",
               "    body: week-2.html", "    post: 2026-09-08"),
             file.path(p, "announcements.yml"))
  expect_error(build_cartridge(p), "needs term: timezone, first_day and last_day")
})

test_that("announcements.yml without term: reads the zone and window from course.yml", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  y <- readLines(file.path(p, "announcements.yml")); y <- y[!grepl("^term:|^  (timezone|first_day|last_day):", y)]
  writeLines(y, file.path(p, "announcements.yml"))
  res <- build_cartridge(p)
  allx <- vapply(list.files(res$stage, pattern = "\\.xml$", full.names = TRUE), function(f) paste(readLines(f), collapse = ""), "")
  expect_true(any(grepl("<delayed_post_at>2026-09-08T05:00:00</delayed_post_at>", allx, fixed = TRUE)))
})
