test_that("an ExternalUrl carries two distinct ids: module_meta self-references, the manifest names the weblink", {
  b <- built()
  item_ids <- regmatches(b$mm, gregexpr('(?<=<item identifier=")[^"]+', b$mm, perl = TRUE))[[1]]
  mm_refs  <- regmatches(b$mm, gregexpr('(?<=<identifierref>)[^<]+', b$mm, perl = TRUE))[[1]]
  self <- intersect(item_ids, mm_refs)
  expect_length(self, 4L)                                   # the four link items
  man_refs <- regmatches(b$man, gregexpr('(?<=identifierref=")[^"]+', b$man, perl = TRUE))[[1]]
  expect_length(intersect(self, man_refs), 0L)              # never the item id in the manifest
})

test_that("a published todo refuses to build; an absent published: means unpublished", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  y <- readLines(file.path(p, "modules.yml")); i <- grep("id: todo-1", y); y[i + 2] <- "    published: true"
  writeLines(y, file.path(p, "modules.yml"))
  expect_error(build_cartridge(p), "REFUSING TO BUILD: todo-1")
  b <- built()
  expect_match(b$mm, "<title>Module 2: Unpublished</title>\\s*<workflow_state>unpublished")
})

test_that("two builds on the same day are byte-identical", {
  b <- built()
  h1 <- tree_hashes(b$stage); z1 <- unname(tools::md5sum(b$imscc))
  build_cartridge(b$p)
  expect_identical(tree_hashes(b$stage), h1)
  expect_identical(unname(tools::md5sum(b$imscc)), z1)
})

test_that("no IMS-CC-FILEBASE token, no assessment source, no canary, in the staged tree", {
  b <- built()
  files <- list.files(b$stage, recursive = TRUE, full.names = TRUE)
  expect_false(any(grepl("\\.(Rmd|qmd|R|Rnw|md)$", files)))
  for (f in files) {
    bytes <- readBin(f, "raw", file.info(f)$size)
    expect_length(grepRaw("IMS-CC-FILEBASE", bytes, fixed = TRUE), 0)
    expect_length(grepRaw(LEAK_CANARY, bytes, fixed = TRUE), 0)
  }
})

test_that("a body page with a missing or empty body file refuses to build", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  f <- file.path(p, "content", "canvas", "chapter-one.html")
  writeLines("", f); expect_error(build_cartridge(p), "empty body file")
  unlink(f);        expect_error(build_cartridge(p), "content/canvas/chapter-one.html")
})

test_that("the quiz assignment body carries the questions and not the key; the homework body carries the directions", {
  b <- built()
  qdir <- list.files(b$stage, pattern = "module-1-quiz\\.html$", recursive = TRUE, full.names = TRUE)
  expect_length(qdir, 1L)
  q <- paste(readLines(qdir), collapse = "\n")
  expect_match(q, "Questions"); expect_no_match(q, "ANSWER KEY")
  hw <- paste(readLines(list.files(b$stage, pattern = "homework-1\\.html$", recursive = TRUE, full.names = TRUE)), collapse = "\n")
  expect_match(hw, "Instructions"); expect_no_match(hw, "Step 1")
})

test_that("due dates route through the timezone helper", {
  b <- built()
  s <- paste(readLines(list.files(b$stage, pattern = "assignment_settings\\.xml$", recursive = TRUE, full.names = TRUE)[1]), collapse = "")
  expect_match(paste(list.files(b$stage, recursive = TRUE), collapse = " "), "assignment_settings")
  all_due <- unlist(lapply(list.files(b$stage, pattern = "assignment_settings\\.xml$", recursive = TRUE, full.names = TRUE),
                           function(f) regmatches(x <- paste(readLines(f), collapse = ""), gregexpr("(?<=<due_at>)[^<]+", x, perl = TRUE))[[1]]))
  expect_setequal(all_due, c("2026-09-16T04:59:00", "2026-09-21T04:59:00"))
})

test_that("the R/exams quiz embeds with the prefix rewritten and two distinct idents", {
  b <- built()
  qti <- list.files(file.path(b$stage, "non_cc_assessments"), full.names = TRUE)
  expect_length(qti, 1L)
  x <- paste(readLines(qti), collapse = "\n")
  expect_no_match(x, "quiz-sample_[0-9]+")
  idents <- regmatches(x, gregexpr('<item ident="[^"]*"', x))[[1]]
  expect_length(unique(idents), 2L)
  expect_no_match(x, "DOCTYPE")
})

test_that("the cartridge filename comes from the course slug", {
  b <- built()
  expect_match(basename(b$imscc), "^abcd-101-01-[0-9]{4}-[0-9]{2}-[0-9]{2}\\.imscc$")
})
