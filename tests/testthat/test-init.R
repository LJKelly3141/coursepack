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

# ---- existing = TRUE ------------------------------------------------------
#
# A snapshot is every path under the directory, dot files included, with the
# bytes of every file. Two snapshots compare equal only when nothing was added,
# removed or changed.
dir_snapshot <- function(d) {
  rel <- sort(list.files(d, recursive = TRUE, all.files = TRUE, no.. = TRUE,
                         include.dirs = TRUE))
  bytes <- lapply(rel, function(f) {
    p <- file.path(d, f)
    if (dir.exists(p)) "<dir>" else readBin(p, "raw", n = file.size(p))
  })
  stats::setNames(bytes, rel)
}

existing_dir <- function() {
  d <- withr::local_tempdir(.local_envir = parent.frame())
  dir.create(file.path(d, "archive", "v1"), recursive = TRUE)
  writeLines(c("old notes", "kept as they are"), file.path(d, "archive", "v1", "notes.md"))
  writeBin(as.raw(c(0:255)), file.path(d, "archive", "v1", "data.bin"))
  writeLines("Version: 1.0", file.path(d, "x.Rproj"))
  writeLines("x <- 1", file.path(d, ".Rhistory"))
  d
}

init_existing <- function(d, ...) {
  init_course(d, code = "ABCD 101", title = "A Course", site_url = "https://example.invalid/c",
              timezone = "America/Chicago", ask = FALSE, git = FALSE, ...)
}

test_that("the default still refuses a non-empty directory and names existing = TRUE", {
  d <- existing_dir(); before <- dir_snapshot(d)
  expect_error(init_existing(d, skills = FALSE), "existing = TRUE")
  expect_identical(dir_snapshot(d), before)
})

test_that("existing = TRUE scaffolds beside unrelated files and leaves them byte-identical", {
  d <- existing_dir(); before <- dir_snapshot(d)
  archive_before <- sort(list.files(file.path(d, "archive"), recursive = TRUE, all.files = TRUE,
                                    include.dirs = TRUE, no.. = TRUE))
  init_existing(d, existing = TRUE)
  after <- dir_snapshot(d)
  for (f in names(before)) expect_identical(after[[f]], before[[f]], info = f)
  expect_identical(sort(list.files(file.path(d, "archive"), recursive = TRUE, all.files = TRUE,
                                   include.dirs = TRUE, no.. = TRUE)), archive_before)
  for (f in c("course.yml", "modules.yml", "Makefile", ".gitignore", "CLAUDE.md",
              ".claude/skills/make-coursepack/SKILL.md"))
    expect_true(file.exists(file.path(d, f)), info = f)
  expect_equal(read_manifest(d)$course$code, "ABCD 101")
})

test_that("existing = TRUE stops on a template collision and writes nothing", {
  d <- existing_dir()
  writeLines("my own make file", file.path(d, "Makefile"))
  dir.create(file.path(d, "reference"))
  writeLines("mine", file.path(d, "reference", "README.md"))
  before <- dir_snapshot(d)
  err <- expect_error(init_existing(d, existing = TRUE), "never replaces one")
  expect_match(conditionMessage(err), "Makefile", fixed = TRUE)
  expect_match(conditionMessage(err), "reference/README.md", fixed = TRUE)
  expect_identical(dir_snapshot(d), before)
})

test_that("existing = TRUE honours claude_md = FALSE when checking collisions", {
  d <- existing_dir(); writeLines("mine", file.path(d, "CLAUDE.md"))
  before <- dir_snapshot(d)
  init_existing(d, existing = TRUE, claude_md = FALSE, skills = FALSE)
  expect_identical(dir_snapshot(d)[["CLAUDE.md"]], before[["CLAUDE.md"]])
})

test_that("existing = TRUE stops on a skill directory collision before anything is written", {
  d <- existing_dir()
  dir.create(file.path(d, ".claude", "skills", "make-coursepack"), recursive = TRUE)
  writeLines("local", file.path(d, ".claude", "skills", "make-coursepack", "notes.md"))
  before <- dir_snapshot(d)
  err <- expect_error(init_existing(d, existing = TRUE), "never replaces one")
  expect_match(conditionMessage(err), ".claude/skills/make-coursepack", fixed = TRUE)
  expect_identical(dir_snapshot(d), before)
  # With skills off the same directory is not a collision.
  init_existing(d, existing = TRUE, skills = FALSE)
  expect_true(file.exists(file.path(d, "course.yml")))
})

test_that("existing = TRUE with from_export stops when reference.yml or the export copy is there", {
  skip_if_no("zip")
  src <- copy_course(); imscc <- file.path(src, "reference", "source.imscc")
  d <- existing_dir(); writeLines("mine", file.path(d, "reference.yml"))
  before <- dir_snapshot(d)
  err <- expect_error(init_existing(d, existing = TRUE, from_export = imscc), "never replaces one")
  expect_match(conditionMessage(err), "reference.yml", fixed = TRUE)
  expect_identical(dir_snapshot(d), before)
  d2 <- existing_dir(); dir.create(file.path(d2, "reference"))
  file.copy(imscc, file.path(d2, "reference", "source.imscc"))
  before2 <- dir_snapshot(d2)
  err <- expect_error(init_existing(d2, existing = TRUE, from_export = imscc), "never replaces one")
  expect_match(conditionMessage(err), "reference/source.imscc", fixed = TRUE)
  expect_identical(dir_snapshot(d2), before2)
})

test_that("the template gitignore ignores .Rhistory", {
  g <- readLines(system.file("templates", "course", "gitignore", package = "coursepack"))
  expect_true(".Rhistory" %in% g)
})
