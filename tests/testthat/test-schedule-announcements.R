test_that("one announcement per week, dues placed by weekday, bodies and yml written", {
  p <- copy_course(); unlink(file.path(p, "announcements.yml"))
  a <- announcements_from_schedule(p, calendar_url = "https://example.invalid/course/calendar.html")
  expect_equal(a$id, c("week-2026-09-14", "week-2026-09-21", "week-2026-09-28"))
  expect_equal(a$post[1], "2026-09-14 07:00")
  b1 <- paste(readLines(file.path(p, "content", "announcements", "week-2026-09-14.html")), collapse = "\n")
  expect_match(b1, "^<h2>Week 1: Module 1: Start Here</h2>")
  expect_match(b1, "<h3>Tuesday, September 15</h3>"); expect_match(b1, "Due, 11:59 pm:</b> Homework 1")
  expect_match(b1, "<h3>Thursday, September 17</h3>"); expect_match(b1, "Due, 9:30 am:</b> Position Memo Draft")
  expect_match(b1, "<h3>Due by Sunday, September 20, 11:59 pm</h3>\\s*<ul><li>Module 1 Quiz</li></ul>")
  expect_match(b1, "All times are America/Chicago.")
  b2 <- paste(readLines(file.path(p, "content", "announcements", "week-2026-09-21.html")), collapse = "\n")
  expect_match(b2, "<li><b>No class today.</b></li>")
  expect_match(b2, "<h3>Due by Sunday, September 27, 11:59 pm</h3>\\s*<ul><li>Module 1 Bank Quiz</li></ul>")
  # The brief called the third week empty. It is not: the fixture's carried
  # definitions are due 2026-10-01 and 2026-10-02, and the week of Monday
  # 2026-09-28 runs to Sunday 2026-10-04, so the assignment lands on that week's
  # Thursday and the quiz, being a Friday, lands in the Sunday list. The fixture
  # dates are the ones Tasks 30 and 36 left; the placement is derived from them.
  b3 <- paste(readLines(file.path(p, "content", "announcements", "week-2026-09-28.html")), collapse = "\n")
  expect_match(b3, "<h3>Thursday, October 1</h3>"); expect_match(b3, "Due, 11:59 pm:</b> Carried Assignment")
  expect_match(b3, "<h3>Due by Sunday, October 4, 11:59 pm</h3>\\s*<ul><li>Carried Quiz</li></ul>")
  y <- yaml::yaml.load_file(file.path(p, "announcements.yml"))
  expect_equal(y$body_dir, "content/announcements"); expect_length(y$announcements, 3L)
  # U+2014 is the em-dash, named by code point so this file holds none itself.
  expect_false(any(grepl(intToUtf8(8212L), c(b1, b2, b3), fixed = TRUE)))
})

test_that("a week with nothing due says so", {
  p <- copy_course()
  writeLines(c("weeks:",
               "  - monday: 2026-10-05",
               "    module: \"Module 4\"",
               "    thursday:",
               "      class: \"Fourth chapter.\""),
             file.path(p, "schedule-quiet.yml"))
  a <- announcements_from_schedule(p, schedule = "schedule-quiet.yml")
  expect_equal(a$id, "week-2026-10-05")
  b <- paste(readLines(file.path(p, "content", "announcements", "week-2026-10-05.html")), collapse = "\n")
  expect_match(b, "<h3>Due by Sunday, October 11, 11:59 pm</h3>\\s*<p>Nothing is due this Sunday.</p>")
  expect_false(grepl("Course Calendar", b))
})

test_that("an existing announcements.yml is never overwritten", {
  p <- copy_course()
  expect_message(announcements_from_schedule(p), "announcements.generated.yml")
  expect_true(file.exists(file.path(p, "announcements.generated.yml")))
})

test_that("a monday: that is not a Monday stops", {
  p <- copy_course()
  edit_yaml(p, "schedule.yml", "monday: 2026-09-14", "monday: 2026-09-15")
  expect_error(announcements_from_schedule(p), "is a Tuesday")
})

test_that("the generated announcements build into the cartridge", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p); unlink(file.path(p, "announcements.yml"))
  announcements_from_schedule(p)
  res <- build_cartridge(p)
  expect_length(gregexpr('type="imsdt_xmlv1p1"', paste(readLines(file.path(res$stage, "imsmanifest.xml")), collapse = ""))[[1]], 3L)
})
