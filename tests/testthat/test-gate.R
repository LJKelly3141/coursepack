test_that("normalize_manifest_date pins the one dated line", {
  x <- "<a>\n            <lomimscc:dateTime>2026-09-04</lomimscc:dateTime>\n</a>"
  expect_equal(normalize_manifest_date(x),
               "<a>\n            <lomimscc:dateTime>DATE</lomimscc:dateTime>\n</a>")
  expect_equal(normalize_manifest_date("<b/>"), "<b/>")
})

test_that("tree_hashes is stable across the manifest date and sorted by path", {
  d <- withr::local_tempdir()
  dir.create(file.path(d, "sub"))
  writeLines("<lomimscc:dateTime>2026-01-01</lomimscc:dateTime>", file.path(d, "imsmanifest.xml"))
  writeLines("b", file.path(d, "sub", "b.txt")); writeLines("a", file.path(d, "a.txt"))
  h1 <- tree_hashes(d)
  writeLines("<lomimscc:dateTime>2027-05-05</lomimscc:dateTime>", file.path(d, "imsmanifest.xml"))
  expect_identical(tree_hashes(d), h1)
  expect_equal(sub("^[0-9a-f]{32} ", "", h1), c("a.txt", "imsmanifest.xml", "sub/b.txt"))
  expect_true(all(grepl("^[0-9a-f]{32} ", h1)))
})

test_that("gate_check names missing, extra and changed files, and passes on identity", {
  d <- withr::local_tempdir(); writeLines("x", file.path(d, "x.txt"))
  # The expected tree is written OUTSIDE the tree it describes, as the real
  # one is (tests/testthat/fixtures/, not the staging directory).
  exp <- tempfile(fileext = ".txt"); write_expected_tree(d, exp)
  expect_no_error(gate_check(d, exp))
  writeLines("stray", file.path(d, "extra.txt"))
  expect_error(gate_check(d, exp), "extra: extra.txt")
  unlink(file.path(d, "extra.txt"))
  writeLines("y", file.path(d, "x.txt"))
  expect_error(gate_check(d, exp), "changed: x.txt")
  unlink(file.path(d, "x.txt"))
  expect_error(gate_check(d, exp), "missing: x.txt")
})
