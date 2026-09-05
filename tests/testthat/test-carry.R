test_that("read_source_cartridge parses every resource, including a self-closing one, with files and deps", {
  skip_if_no("zip")
  p <- copy_course(); src <- read_source_cartridge(file.path(p, "reference", "source.imscc"))
  r <- src$resources
  expect_true("g00000000000000000000000000000e01" %in% names(r))
  expect_true(r[["g00000000000000000000000000000e01"]]$self_closing)
  expect_equal(r[["g00000000000000000000000000000q01"]]$deps, "g00000000000000000000000000000m01")
  expect_setequal(r[["g00000000000000000000000000000m01"]]$files,
                  c("g00000000000000000000000000000q01/assessment_meta.xml", "non_cc_assessments/g00000000000000000000000000000q01.xml.qti"))
  expect_match(r[["g00000000000000000000000000000q01"]]$raw, "^<resource identifier=\"g00000000000000000000000000000q01\"")
})

test_that("carried files are byte-identical to the source, the objectbank is dropped, module items point at the carried ids", {
  b <- built()
  src <- fixture_path("src")
  # Every file this builder rewrites on purpose is off this list, and cannot be
  # on it: assignment_settings.xml, assessment_meta.xml and the carried
  # assignment's HTML take the course's own title: and due:, and the carried
  # page's HTML is repaired for accessibility. The two sections below assert
  # what all four say. Everything else still travels byte for byte, the carried
  # XML the repair had nothing to fix in included.
  for (f in c("non_cc_assessments/g00000000000000000000000000000q01.xml.qti",
              "g00000000000000000000000000000q01/assessment_qti.xml"))
    expect_identical(unname(tools::md5sum(file.path(b$stage, f))), unname(tools::md5sum(file.path(src, f))), info = f)
  expect_false(file.exists(file.path(b$stage, "non_cc_assessments", "g00000000000000000000000000000b01.xml.qti")))
  expect_match(b$mm, "<identifierref>g00000000000000000000000000000c01</identifierref>", fixed = TRUE)
  expect_match(b$man, 'identifier="g00000000000000000000000000000m01"', fixed = TRUE)
})

test_that("a source_ref not in the source, a missing source:, and a carried group the course does not declare all stop", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  edit_yaml(p, "modules.yml", "source_ref: g00000000000000000000000000000c01", "source_ref: g00000000000000000000000000000fff")
  expect_error(build_cartridge(p), "carries source_ref g00000000000000000000000000000fff, which is not in")
  edit_yaml(p, "modules.yml", "source_ref: g00000000000000000000000000000fff", "source_ref: g00000000000000000000000000000c01")
  unlink(file.path(p, "reference.yml"))
  expect_error(build_cartridge(p), "carried-page.*needs reference.yml with source: or export:")
  writeLines("source: reference/source.imscc", file.path(p, "reference.yml"))
  edit_yaml(p, "course.yml", "    id: g0000000000000000000000000000000b", "    id: g0000000000000000000000000000000c")
  expect_error(build_cartridge(p), "references assignment group g0000000000000000000000000000000b, which course.yml does not declare")
})

test_that("a definition with source_ref and a body key is refused", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  edit_yaml(p, "modules.yml", "    source_ref: g00000000000000000000000000000c01", "    source_ref: g00000000000000000000000000000c01\n    body: true")
  expect_error(build_cartridge(p), "carried-page.*source_ref and body")
})

test_that("carried titles follow the definition in every title slot, and dates come from due: or are blanked", {
  b <- built()
  meta <- paste(readLines(file.path(b$stage, "g00000000000000000000000000000q01", "assessment_meta.xml")), collapse = "\n")
  expect_length(gregexpr("<title>Carried Quiz</title>", meta, fixed = TRUE)[[1]], 2L)
  expect_no_match(meta, "Old Quiz Title")
  expect_length(gregexpr("<due_at>2026-10-03T04:59:59</due_at>", meta, fixed = TRUE)[[1]], 2L)
  expect_match(meta, "<all_day_date>2026-10-02</all_day_date>", fixed = TRUE)
  st <- paste(readLines(file.path(b$stage, "g00000000000000000000000000000a01", "assignment_settings.xml")), collapse = "\n")
  expect_match(st, "<title>Carried Assignment</title>", fixed = TRUE)
  expect_match(st, "<due_at>2026-10-02T04:59:59</due_at>", fixed = TRUE)
})

test_that("a carried date is blanked when the definition has no due:, and a due: with nothing to rewrite stops", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  edit_yaml(p, "modules.yml", "    due: 2026-10-01\n    source_ref: g00000000000000000000000000000a01", "    source_ref: g00000000000000000000000000000a01")
  res <- build_cartridge(p)
  st <- paste(readLines(file.path(res$stage, "g00000000000000000000000000000a01", "assignment_settings.xml")), collapse = "\n")
  expect_match(st, "<due_at></due_at>", fixed = TRUE); expect_no_match(st, "2025-02-01")
  edit_yaml(p, "modules.yml", "    source_ref: g00000000000000000000000000000c01", "    due: 2026-10-05\n    source_ref: g00000000000000000000000000000c01")
  expect_error(build_cartridge(p), "has due: but its carried file has no due_at")
})

test_that("carried tables gain scope and a leading bold paragraph becomes a heading; generated pages are untouched; the switch turns it off", {
  b <- built()
  cp <- paste(readLines(file.path(b$stage, "wiki_content", "carried-page.html")), collapse = "\n")
  expect_match(cp, '<th scope="col">A</th><th scope="col">B</th>', fixed = TRUE)
  meta <- paste(readLines(file.path(b$stage, "g00000000000000000000000000000q01", "assessment_meta.xml")), collapse = "\n")
  expect_match(meta, "&lt;h2&gt;Read this first&lt;/h2&gt;", fixed = TRUE)
  # The generated page carries a table with a bare <th> of its own. The repair
  # reaches carried files only, so that one stays exactly as the course wrote it.
  gen <- paste(readLines(file.path(b$stage, "wiki_content", "chapter-one.html")), collapse = "\n")
  expect_match(gen, "<table><tr><th>X</th></tr></table>", fixed = TRUE)
  expect_no_match(gen, "scope=", fixed = TRUE)
  p <- b$p; edit_yaml(p, "course.yml", "due_time: \"23:59:59\"", "due_time: \"23:59:59\"\ncarry:\n  repair_html: false")
  build_cartridge(p)
  cp2 <- paste(readLines(file.path(b$stage, "wiki_content", "carried-page.html")), collapse = "\n")
  expect_no_match(cp2, 'scope="col"')
  # A value that is neither true nor false stops. Read as "off" it would look
  # exactly like a course that asked for the repair and did not get it.
  expect_error(repair_html_on(list(carry = list(repair_html = "no"))),
               "must be true or false")
})

test_that("a source cartridge that declares an unsafe path is refused before anything is written", {
  skip_if_no("zip")
  st <- withr::local_tempdir()
  expect_error(safe_stage_path(st, "../evil.html"), "unsafe path: ../evil.html")
  expect_error(safe_stage_path(st, "/etc/passwd"), "unsafe path")
  expect_error(safe_stage_path(st, "a/../../b.html"), "unsafe path")
  expect_error(safe_stage_path(st, "a\\b.html"), "unsafe path")
  expect_equal(safe_stage_path(st, "wiki_content/ok.html"), file.path(st, "wiki_content", "ok.html"))
  # A whole cartridge carrying one bad href, placed on the LAST file the walk
  # reaches: the quiz meta's pooling file, which sits behind a <dependency>
  # edge from the last carried definition. Per-write validation would have
  # staged the page and the assignment before reaching it; whole-walk
  # validation stages nothing. The test tells the two apart.
  p <- copy_course(); zip_fixture_qti(p)
  src <- fixture_path("src"); d <- withr::local_tempdir(); file.copy(src, d, recursive = TRUE)
  man <- file.path(d, "src", "imsmanifest.xml")
  m <- readLines(man)
  bad <- sub('<file href="non_cc_assessments/g00000000000000000000000000000q01.xml.qti"/>',
             '<file href="../g00000000000000000000000000000q01.xml.qti"/>', m, fixed = TRUE)
  expect_false(identical(bad, m))
  writeLines(bad, man)
  old <- setwd(file.path(d, "src")); utils::zip(file.path(p, "reference", "source.imscc"), list.files(".", recursive = TRUE), flags = "-q -X"); setwd(old)
  expect_error(build_cartridge(p), "unsafe path: ../g00000000000000000000000000000q01.xml.qti")
  expect_false(file.exists(file.path(p, "build", "coursepack", "g00000000000000000000000000000q01.xml.qti")))
  st <- file.path(p, "build", "coursepack", "staging")
  for (f in c("wiki_content/carried-page.html",
              "g00000000000000000000000000000a01/assignment_settings.xml",
              "g00000000000000000000000000000a01/carried-assignment.html",
              "g00000000000000000000000000000q01/assessment_qti.xml",
              "g00000000000000000000000000000q01/assessment_meta.xml"))
    expect_false(file.exists(file.path(st, f)), info = f)
})
