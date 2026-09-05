new_course <- function(...) {
  d <- withr::local_tempdir(.local_envir = parent.frame()); p <- file.path(d, "c")
  init_course(p, code = "ABCD 101", title = "A Course", site_url = "https://example.invalid/c",
              timezone = "America/Chicago", ask = FALSE, git = FALSE, ...)
  p
}

test_that("the scaffold writes every file, parses, and installs the skills", {
  p <- new_course()
  for (f in c("course.yml", "modules.yml", "announcements.yml", "_quarto.yml", "Makefile", "CLAUDE.md", "README.md",
              "content/pages/welcome.qmd", "content/announcements/welcome.html", "assessments/leak-canary.qmd",
              "reference/README.md", ".claude/skills/make-coursepack/SKILL.md", "questions/README.md"))
    expect_true(file.exists(file.path(p, f)), info = f)
  m <- read_manifest(p)
  expect_equal(m$course$code, "ABCD 101"); expect_equal(read_timezone(m$course), "America/Chicago")
  expect_equal(m$course$slug, "abcd-101"); expect_true(!is.null(m$assignments[["first-assignment"]]$todo))
  q <- yaml::yaml.load_file(file.path(p, "_quarto.yml"))
  # The brief wrote the expected value as list("index.qmd", "content/**/*.qmd").
  # A YAML sequence whose entries are all length-one strings comes back from
  # yaml.load_file() as a character vector, so the list() form can never match
  # and the assertion would have been a permanent failure rather than a check on
  # the allowlist. Same two entries, same order, the type the parser returns.
  expect_equal(q$project$render, c("index.qmd", "content/**/*.qmd"))
  expect_true(any(grepl(LEAK_CANARY, readLines(file.path(p, "assessments", "leak-canary.qmd")), fixed = TRUE)))
})

test_that("refusals: non-empty path, bad site_url, unknown timezone, missing required args when not asking", {
  d <- withr::local_tempdir(); writeLines("x", file.path(d, "f"))
  expect_error(init_course(d, "ABCD 101", "T", "https://x", "America/Chicago", ask = FALSE), "not empty")
  expect_error(init_course(file.path(d, "a"), "ABCD 101", "T", "http://x", "America/Chicago", ask = FALSE), "must start with https://")
  expect_error(init_course(file.path(d, "b"), "ABCD 101", "T", "https://x", "Central", ask = FALSE), "IANA")
  expect_error(init_course(file.path(d, "c"), title = "T", site_url = "https://x", timezone = "UTC", ask = FALSE), "code is required")
})

test_that("from_export replaces the manifests with the extracted ones and keeps the caller's zone", {
  skip_if_no("zip")
  src <- copy_course(); imscc <- file.path(src, "reference", "source.imscc")
  d <- withr::local_tempdir(); p <- file.path(d, "x")
  init_course(p, code = "SRC 100", title = "Source Course", site_url = "https://example.invalid/course",
              timezone = "Europe/London", ask = FALSE, git = FALSE, from_export = imscc)
  m <- read_manifest(p)
  expect_true(!is.null(m$pages[["carried-page"]]$source_ref)); expect_equal(read_timezone(m$course), "Europe/London")
  expect_true(file.exists(file.path(p, "reference", "source.imscc")))
  expect_equal(read_reference(p)$source, "reference/source.imscc")
})
