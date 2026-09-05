skills <- function() list.dirs(system.file("skills", package = "coursepack"), recursive = FALSE)

read_all <- function(paths) unlist(lapply(paths, readLines, warn = FALSE), use.names = FALSE)

test_that("the package ships skills at all", {
  # list.dirs("") is character(0), so every loop below would pass vacuously if
  # inst/skills/ were missing. This is the guard that makes the loops mean something.
  expect_gt(length(skills()), 0)
})

test_that("every shipped skill has frontmatter and no course residue", {
  for (d in skills()) {
    s <- readLines(file.path(d, "SKILL.md"), warn = FALSE)
    expect_equal(s[1], "---", info = d)
    expect_true(any(grepl("^name: ", s)), info = d); expect_true(any(grepl("^description:", s)), info = d)
    txt <- paste(read_all(list.files(d, recursive = TRUE, full.names = TRUE)), collapse = "\n")
    expect_no_match(txt, "(?i)econ ?730|econ ?202|managerial|macro_principles|ljkelly3141|uwrf|river falls|real-world-statistics|kellyecon|My_Books|Teaching/|/Users/", perl = TRUE, info = d)
    expect_no_match(txt, "scripts/(build_|check_|diff_|audit_)", info = d)
    expect_false(grepl(intToUtf8(8212L), txt, fixed = TRUE), info = d)
  }
})

test_that("every coursepack:: call in a skill names an exported function", {
  ex <- getNamespaceExports("coursepack")
  for (d in skills()) {
    txt <- paste(readLines(file.path(d, "SKILL.md"), warn = FALSE), collapse = "\n")
    called <- unique(regmatches(txt, gregexpr("(?<=coursepack::)[A-Za-z_][A-Za-z0-9_.]*", txt, perl = TRUE))[[1]])
    expect_true(all(called %in% ex), info = paste(d, ":", paste(setdiff(called, ex), collapse = ", ")))
  }
})
