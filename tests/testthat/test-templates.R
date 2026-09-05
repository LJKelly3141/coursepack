test_that("render_template fills every placeholder and refuses a leftover", {
  expect_equal(render_template("a {{x}} b {{y}}", list(x = 1, y = "z")), "a 1 b z")
  expect_error(render_template("a {{x}} {{q}}", list(x = 1)), "unfilled template key: q")
})

test_that("every template renders with example values and the YAML ones parse", {
  tpl <- system.file("templates", "course", package = "coursepack")
  vals <- list(code = "ABCD 101", title = "A Course", institution = "Example U", slug = "abcd-101",
               site_url = "https://example.invalid/c", textbook_url = "", textbook_docs = "none",
               timezone = "America/Chicago", canary = LEAK_CANARY, version = coursepack_version())
  for (f in list.files(tpl, recursive = TRUE, all.files = TRUE, full.names = TRUE)) {
    out <- render_template(paste(readLines(f, warn = FALSE), collapse = "\n"), vals)
    # The brief wrote this as expect_no_error(..., info = f). That signature
    # checks its dots are empty and rejects `info`, so the file a failure came
    # from would be lost; expect_error(..., NA) is the same assertion and takes
    # it. Which file failed is the whole value of the loop.
    if (grepl("\\.ya?ml$", f)) expect_error(yaml::yaml.load(out), NA, info = f)
  }
})

test_that("leak_check stops on the canary in docs and passes a clean docs", {
  d <- withr::local_tempdir(); dir.create(file.path(d, "docs"))
  writeLines("<p>fine</p>", file.path(d, "docs", "a.html"))
  expect_output(leak_check(d), "leakcheck: clean")
  writeLines(LEAK_CANARY, file.path(d, "docs", "b.html"))
  expect_error(leak_check(d), "LEAK: assessments/ content reached docs")
  expect_error(leak_check(withr::local_tempdir()), "no docs directory")
})
