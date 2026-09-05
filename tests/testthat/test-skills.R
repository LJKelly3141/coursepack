test_that("install_skills copies every skill, stamps the version, refuses to overwrite, overwrites when told", {
  p <- withr::local_tempdir()
  out <- install_skills(p)
  expect_setequal(basename(out), basename(list.dirs(system.file("skills", package = "coursepack"), recursive = FALSE)))
  s <- readLines(file.path(p, ".claude", "skills", "make-coursepack", "SKILL.md"))
  expect_match(tail(s, 1), paste0("installed from coursepack ", coursepack_version()))
  expect_true(file.exists(file.path(p, ".claude", "skills", "strip-ai-characters", "scan_characters.py")))
  expect_error(install_skills(p), "already exist.*make-coursepack")
  expect_no_error(install_skills(p, which = "preview-course", overwrite = TRUE))
  expect_error(install_skills(p, which = "no-such-skill"), "unknown skill: no-such-skill")
})

test_that("an installed copy differs from inst/ only by the version line", {
  p <- withr::local_tempdir(); install_skills(p, which = "preview-course")
  a <- readLines(file.path(p, ".claude", "skills", "preview-course", "SKILL.md"))
  b <- readLines(system.file("skills", "preview-course", "SKILL.md", package = "coursepack"))
  expect_identical(head(a, length(b)), b); expect_length(a, length(b) + 2L)
})
