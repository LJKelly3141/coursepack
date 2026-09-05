fixture_path <- function(...) testthat::test_path("fixtures", ...)

copy_course <- function(name = "minimal-course", to = withr::local_tempdir(.local_envir = parent.frame())) {
  ok <- file.copy(fixture_path(name), to, recursive = TRUE)
  ok2 <- file.copy(fixture_path("fake-textbook"), to, recursive = TRUE)
  stopifnot(all(ok), all(ok2))
  p <- normalizePath(file.path(to, name))
  # Every copy of the fixture carries a source cartridge, because the fixture's
  # reference.yml names one and three of its definitions carry out of it. No
  # zip binary means no archive, and every test that needs one skips on zip.
  if (nzchar(Sys.which("zip"))) zip_fixture_source(p)
  p
}

# fixtures/src/ is an unzipped synthetic Canvas export. Zip it at
# the archive root, so the entry names are the hrefs the manifest declares.
zip_fixture_source <- function(course_dir) {
  src <- fixture_path("src")
  dir.create(file.path(course_dir, "reference"), showWarnings = FALSE)
  zipf <- normalizePath(file.path(course_dir, "reference", "source.imscc"), mustWork = FALSE)
  old <- setwd(src); on.exit(setwd(old), add = TRUE)
  utils::zip(zipf, list.files(".", recursive = TRUE), flags = "-q -X")
  zipf
}

# The fixture course without the carried module and its three definitions, for
# the tests that need a course whose source cartridge is declared and unused.
drop_carried <- function(p) {
  edit_yaml(p, "modules.yml", paste0(
    "  - title: \"Module 3: Carried\"\n    published: true\n    items:\n",
    "      - page: carried-page\n      - assignment: carried-asg\n      - quiz: carried-quiz\n"), "")
  edit_yaml(p, "modules.yml",
    "  - slug: carried-page\n    title: Carried Page\n    source_ref: g00000000000000000000000000000c01\n", "")
  edit_yaml(p, "modules.yml", paste0(
    "  - id: carried-asg\n    title: Carried Assignment\n    published: true\n",
    "    due: 2026-10-01\n    source_ref: g00000000000000000000000000000a01\n"), "")
  edit_yaml(p, "modules.yml", paste0(
    "\n  - id: carried-quiz\n    title: Carried Quiz\n    published: true\n",
    "    due: 2026-10-02\n    source_ref: g00000000000000000000000000000q01"), "")
  invisible(p)
}

zip_fixture_qti <- function(course_dir) {
  src <- fixture_path("qti-sample", "quiz-sample")
  out_dir <- file.path(course_dir, "build", "qti")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  zipf <- normalizePath(file.path(out_dir, "quiz-sample.zip"), mustWork = FALSE)
  old <- setwd(dirname(src)); on.exit(setwd(old), add = TRUE)
  utils::zip(zipf, list.files(basename(src), recursive = TRUE, full.names = TRUE), flags = "-q -X")
  zipf
}

built <- function() {
  skip_if_no("zip"); skip_if_no("pandoc")
  to <- withr::local_tempdir(.local_envir = parent.frame())   # bind the tempdir to the TEST, not to this helper
  p <- copy_course(to = to); zip_fixture_qti(p)
  res <- build_cartridge(p)
  list(p = p, stage = res$stage, imscc = res$imscc,
       man = paste(readLines(file.path(res$stage, "imsmanifest.xml")), collapse = "\n"),
       mm = paste(readLines(file.path(res$stage, "course_settings", "module_meta.xml")), collapse = "\n"))
}

# Staged files the builder GENERATED, with everything carried out of the source
# cartridge left out. A carried file keeps the source fixture's identifier, a
# run of 29 zeros; a derived id is an md5 and never looks like that. Tests that
# assert "exactly one of these" mean exactly one generated one.
generated_files <- function(dir, pattern = NULL) {
  f <- list.files(dir, pattern = pattern, recursive = TRUE, full.names = TRUE)
  f[!grepl("g00000000000000000000000000000", f, fixed = TRUE)]
}

# Replace one literal line fragment in a fixture YAML file. `from` is matched
# fixed, so regex metacharacters in YAML need no escaping.
edit_yaml <- function(p, file, from, to) {
  y <- paste(readLines(file.path(p, file)), collapse = "\n")
  stopifnot(grepl(from, y, fixed = TRUE))
  writeLines(sub(from, to, y, fixed = TRUE), file.path(p, file))
}
