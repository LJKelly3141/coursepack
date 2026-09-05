test_that("the package builds the fixture into the frozen builder's tree", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  build_cartridge(p)
  expect_no_error(gate_check(file.path(p, "build", "coursepack", "staging"),
                             fixture_path("minimal-course-expected-tree.txt")))
})
