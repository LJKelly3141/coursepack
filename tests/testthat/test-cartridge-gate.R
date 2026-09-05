test_that("the package builds the fixture into the frozen builder's tree", {
  skip_if_no("zip"); skip_if_no("pandoc")
  skip_if(!exists("build_cartridge"), "build_cartridge has not moved into the package yet")
  p <- copy_course(); zip_fixture_qti(p)
  build_cartridge(p)
  gate_check(file.path(p, "build", "coursepack", "staging"),
             fixture_path("minimal-course-expected-tree.txt"))
})
