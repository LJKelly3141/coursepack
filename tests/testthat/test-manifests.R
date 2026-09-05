# Every test that expects a pass needs the sample QTI zip in place, because the
# checker fails on a missing zip before anything else is judged.
ready <- function() {
  skip_if_no("zip")
  to <- withr::local_tempdir(.local_envir = parent.frame())
  p <- copy_course(to = to)
  zip_fixture_qti(p)
  p
}

test_that("the fixture course passes, reporting the textbook skip when docs are absent", {
  p <- ready()
  res <- check_manifests(p)
  expect_length(res$fails, 0)
  expect_true(any(grepl("counts", res$skipped)))       # no reference.yml -> counts skipped, loudly
  unlink(file.path(dirname(p), "fake-textbook"), recursive = TRUE)
  res2 <- check_manifests(p)
  expect_true(any(grepl("textbook docs not found", res2$skipped)))
})

test_that("counts in reference.yml are fatal when they disagree", {
  p <- ready()
  writeLines(c("counts:", "  modules: 2", "  items: 13", "  header: 2", "  page: 3", "  link: 4",
               "  assignment: 3", "  quiz: 1"), file.path(p, "reference.yml"))
  expect_no_error(check_manifests(p))
  writeLines(c("counts:", "  modules: 9"), file.path(p, "reference.yml"))
  expect_error(check_manifests(p), "modules: 2 vs 9")
})

test_that("referential integrity: undefined and orphan definitions fail", {
  p <- copy_course()
  y <- readLines(file.path(p, "modules.yml"))
  writeLines(sub("- page: welcome", "- page: nowhere", y), file.path(p, "modules.yml"))
  expect_error(check_manifests(p), "page slug not defined: nowhere")
  expect_error(check_manifests(p), "orphan pages: welcome")
})

test_that("a broken anchor fails when the textbook is present and is a manifest defect when empty", {
  p <- copy_course()
  y <- readLines(file.path(p, "modules.yml"))
  writeLines(sub("anchor: sec-intro", "anchor: sec-missing", y), file.path(p, "modules.yml"))
  expect_error(check_manifests(p), "anchor missing: ch01#sec-missing")
})

test_that("todo plus published is a violation; a missing QTI zip fails before build time", {
  p <- copy_course()
  y <- readLines(file.path(p, "modules.yml"))
  y <- sub("    todo: \"write this once the chapter exists\"", "    todo: x", y)
  i <- grep("id: todo-1", y); y[i + 2] <- "    published: true"
  writeLines(y, file.path(p, "modules.yml"))
  expect_error(check_manifests(p), "VIOLATION: todo-1 has todo AND published: true")
  p2 <- copy_course()
  expect_error(check_manifests(p2), "quiz 'q-sample' QTI zip missing")
})

test_that("an assignment group that is not declared fails", {
  p <- ready()
  c1 <- readLines(file.path(p, "course.yml"))
  writeLines(sub("  group: Assignments", "  group: Homework", c1), file.path(p, "course.yml"))
  expect_error(check_manifests(p), "assignment_defaults.group 'Homework' is not a declared assignment group")
})

test_that("textbook_docs: none skips the target checks loudly", {
  p <- ready()
  c1 <- readLines(file.path(p, "course.yml"))
  writeLines(sub("textbook_docs: .*", "textbook_docs: none", c1), file.path(p, "course.yml"))
  res <- check_manifests(p)
  expect_true(any(grepl("textbook_docs: none", res$skipped)))
})
