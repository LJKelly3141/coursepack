mk <- function(...) {
  d <- withr::local_tempdir(.local_envir = parent.frame())
  for (f in list(...)) writeLines(f$text, file.path(d, f$name))
  d
}
yml <- function(name, text) list(name = name, text = text)

test_that("read_course and read_modules stop on missing files, naming proj", {
  d <- withr::local_tempdir()
  expect_error(read_course(d), "course.yml")
  expect_error(read_modules(d), "modules.yml")
})

test_that("read_manifest names pages by slug and definitions by id", {
  d <- mk(yml("course.yml", "code: ABCD 101\ntitle: T\n"),
          yml("modules.yml", paste(
            "modules:", "  - title: M", "    items:", "      - page: a", "      - assignment: hw",
            "pages:", "  - slug: a", "    title: A", "    body: true",
            "assignments:", "  - id: hw", "    title: HW",
            "quizzes:", "  - id: q1", "    title: Q", "    qti: build/qti/q1.zip", sep = "\n")))
  m <- read_manifest(d)
  expect_named(m$pages, "a"); expect_named(m$assignments, "hw"); expect_named(m$quizzes, "q1")
  expect_equal(m$course$code, "ABCD 101")
})

test_that("read_manifest stops on a duplicate slug or id", {
  d <- mk(yml("course.yml", "code: ABCD 101\n"),
          yml("modules.yml", "modules: []\npages:\n  - slug: a\n  - slug: a\nassignments: []\n"))
  expect_error(read_manifest(d), "duplicate page slug: a")
})

test_that("read_reference and read_announcements return NULL when absent", {
  d <- mk(yml("course.yml", "code: ABCD 101\n"))
  expect_null(read_reference(d)); expect_null(read_announcements(d))
})

test_that("read_announcements validates like the builder did", {
  base <- c("body_dir: content/announcements",
            "term: {timezone: America/Chicago, first_day: 2026-09-01, last_day: 2026-12-15}")
  ok <- c(base, "announcements:", "  - {id: w, title: Welcome, body: w.html, post: immediately}")
  d <- mk(yml("announcements.yml", paste(ok, collapse = "\n")))
  a <- read_announcements(d)
  expect_equal(a$tz, "America/Chicago"); expect_named(a$announcements, "w")
  expect_equal(a$body_dir, file.path(d, "content/announcements"))
  bad_tz <- sub("America/Chicago", "Central", ok)
  d2 <- mk(yml("announcements.yml", paste(bad_tz, collapse = "\n")))
  expect_error(read_announcements(d2), "not an IANA zone name")
  d3 <- mk(yml("announcements.yml", paste(base, collapse = "\n")))
  expect_error(read_announcements(d3), "declares no announcements")
  dup <- c(ok, "  - {id: w, title: Again, body: x.html, post: immediately}")
  d4 <- mk(yml("announcements.yml", paste(dup, collapse = "\n")))
  expect_error(read_announcements(d4), "duplicate id: w")
})

test_that("read_timezone requires a real IANA zone under term:", {
  expect_equal(read_timezone(list(term = list(timezone = "Europe/London"))), "Europe/London")
  expect_error(read_timezone(list(term = "TBD")), "term: timezone")
  expect_error(read_timezone(list(term = list(timezone = "Central"))), "term: timezone")
})

test_that("textbook_docs_path resolves relative paths, honours none, refuses absence", {
  expect_equal(textbook_docs_path(list(textbook_docs = "../book/docs"), "/p/course"),
               "/p/course/../book/docs")
  expect_equal(textbook_docs_path(list(textbook_docs = "/abs/docs"), "/p"), "/abs/docs")
  expect_null(textbook_docs_path(list(textbook_docs = "none"), "/p"))
  expect_error(textbook_docs_path(list(), "/p"), "textbook_docs")
})

test_that("course_slug prefers slug:, then the Canvas course code, then code", {
  expect_equal(course_slug(list(slug = "my-course")), "my-course")
  expect_equal(course_slug(list(code = "ABCD 101", canvas = list(course_code = "ABCD 101-01"))), "abcd-101-01")
  expect_equal(course_slug(list(code = "ABCD 101")), "abcd-101")
})
