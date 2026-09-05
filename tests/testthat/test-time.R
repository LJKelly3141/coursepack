test_that("local_to_utc reproduces the fixed-offset strings for every live 2026 date", {
  # The first course's seventeen due dates all fall before 2026-11-01, so the old builder's
  # `next day T04:59:00` arithmetic must be reproduced character for character.
  # Synthetic list spanning the same window, never read from modules.yml.
  dates <- as.Date("2026-09-11") + c(0, 7, 14, 21, 28, 35, 40, 42, 49)
  for (d in dates) {
    d <- as.Date(d, origin = "1970-01-01")
    expect_equal(local_to_utc(d, "23:59:00", "America/Chicago"),
                 paste0(format(d + 1, "%Y-%m-%d"), "T04:59:00"))
  }
})

test_that("local_to_utc handles the two 2026 daylight-time boundaries", {
  expect_equal(local_to_utc("2026-10-31", "23:59:00", "America/Chicago"), "2026-11-01T04:59:00")
  expect_equal(local_to_utc("2026-11-01", "23:59:00", "America/Chicago"), "2026-11-02T05:59:00")
  expect_equal(local_to_utc("2026-03-07", "23:59:00", "America/Chicago"), "2026-03-08T05:59:00")
  expect_equal(local_to_utc("2026-03-08", "23:59:00", "America/Chicago"), "2026-03-09T04:59:00")
})

test_that("local_to_utc: a midnight post and an in-person morning exam", {
  expect_equal(local_to_utc("2026-09-08", "00:00", "America/Chicago"), "2026-09-08T05:00:00")
  expect_equal(local_to_utc("2026-12-22", "09:45:00", "America/Chicago"), "2026-12-22T15:45:00")
  expect_equal(local_to_utc("2026-09-08", "00:00", "Europe/London"), "2026-09-07T23:00:00")
})

test_that("local_to_utc refuses bad input", {
  expect_error(local_to_utc("2026-13-01", "23:59", "America/Chicago"), "not a real date")
  expect_error(local_to_utc("2026-09-01", "25:00", "America/Chicago"), "time must be HH:MM")
  expect_error(local_to_utc("2026-09-01", "23:59", "Central"), "IANA")
})

test_that("parse_when accepts exactly three forms", {
  tz <- "America/Chicago"
  expect_null(parse_when("immediately", tz, "a"))
  expect_equal(format(parse_when("2026-09-08", tz, "a"), "%Y-%m-%d %H:%M", tz = tz), "2026-09-08 00:00")
  expect_equal(format(parse_when("2026-09-08 07:30", tz, "a"), "%H:%M", tz = tz), "07:30")
  expect_equal(format(parse_when("2026-09-08 07:30:15", tz, "a"), "%H:%M:%S", tz = tz), "07:30:15")
  expect_error(parse_when("now", tz, "welcome"), "welcome: post must be 'immediately'")
  expect_error(parse_when("2026-09-31", tz, "a"), "not a real date-time")
})

test_that("due_stamp uses due_time for a bare date and refuses a bare date without one", {
  expect_equal(due_stamp("2026-09-13", "23:59:59", "America/Chicago"), "2026-09-14T04:59:59")
  expect_equal(due_stamp("2026-12-22 09:45:00", "23:59:59", "America/Chicago"), "2026-12-22T15:45:00")
  expect_error(due_stamp("2026-09-13", NULL, "America/Chicago"), "needs due_time")
})
