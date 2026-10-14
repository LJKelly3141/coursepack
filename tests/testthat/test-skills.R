test_that("install_skills copies every skill, stamps the version, refuses to overwrite, overwrites when told", {
  local_mocked_bindings(pkg_skill_dir = function(pkg) if (pkg == "lecturecast") "" else system.file("skills", package = pkg))
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

# lecturecast is optional and not installed on GitHub's automatic test run, so
# its skill directory is stood in for by a temporary one.
fake_lecturecast <- function(env = parent.frame(), names = "lecture-video") {
  d <- withr::local_tempdir(.local_envir = env)
  for (n in names) {
    dir.create(file.path(d, n))
    writeLines(c("---", paste0("name: ", n), "description: x", "---", "", "body"),
               file.path(d, n, "SKILL.md"))
  }
  testthat::local_mocked_bindings(
    pkg_skill_dir = function(pkg) if (pkg == "lecturecast") d else system.file("skills", package = pkg),
    pkg_version = function(pkg) if (pkg == "lecturecast") "0.9.0" else coursepack_version(),
    .env = env
  )
}

test_that("without lecturecast only coursepack's skills are installed", {
  local_mocked_bindings(pkg_skill_dir = function(pkg) if (pkg == "lecturecast") "" else system.file("skills", package = pkg))
  p <- withr::local_tempdir(); out <- install_skills(p)
  expect_false("lecture-video" %in% basename(out))
})

test_that("an installed lecturecast's skills are installed too, stamped with its version", {
  fake_lecturecast()
  p <- withr::local_tempdir(); out <- install_skills(p)
  expect_true(all(c("lecture-video", "make-coursepack") %in% basename(out)))
  s <- readLines(file.path(p, ".claude", "skills", "lecture-video", "SKILL.md"))
  expect_match(tail(s, 1), "installed from lecturecast 0.9.0", fixed = TRUE)
  m <- readLines(file.path(p, ".claude", "skills", "make-coursepack", "SKILL.md"))
  expect_match(tail(m, 1), paste0("installed from coursepack ", coursepack_version()), fixed = TRUE)
  q <- withr::local_tempdir(); install_skills(q, which = "lecture-video")
  expect_identical(list.files(file.path(q, ".claude", "skills")), "lecture-video")
})

test_that("a skill name shipped by both packages stops before anything is copied", {
  fake_lecturecast(names = "preview-course")
  p <- withr::local_tempdir()
  expect_error(install_skills(p), "more than one package: preview-course")
  expect_false(dir.exists(file.path(p, ".claude")))
})
