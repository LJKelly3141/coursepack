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

test_that("no IMS-CC-FILEBASE token outside the quiz QTI, no assessment source, no canary, in the staged tree", {
  b <- built()
  files <- list.files(b$stage, recursive = TRUE)
  expect_false(any(grepl("\\.(Rmd|qmd|R|Rnw|md)$", files)))
  for (f in files) {
    full <- file.path(b$stage, f)
    bytes <- readBin(full, "raw", file.info(full)$size)
    # Decision D15 admits the token in a quiz's two QTI files and nowhere else.
    # The next test asserts the other half: that every figure it names is
    # staged and declared.
    if (!grepl("^non_cc_assessments/|/assessment_qti\\.xml$", f))
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

test_that("iframe pages use the one titled template, with the allow list only for video", {
  b <- built()
  w <- paste(readLines(file.path(b$stage, "wiki_content", "welcome.html")), collapse = "\n")
  expect_match(w, '<iframe title="Welcome" src="https://example.invalid/course/welcome.html" width="100%" height="800" style="border: 0;" loading="lazy" allowfullscreen=""></iframe>', fixed = TRUE)
  expect_match(w, '<a href="https://example.invalid/course/welcome.html" target="_blank"', fixed = TRUE)
  v <- paste(readLines(file.path(b$stage, "wiki_content", "video-one.html")), collapse = "\n")
  expect_match(v, 'allow="accelerometer; clipboard-write; encrypted-media; gyroscope; picture-in-picture"', fixed = TRUE)
  p <- b$p; edit_yaml(p, "modules.yml", '    height: "800"', "")
  expect_error(build_cartridge(p), "no height:")
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

test_that("the homework body uses the package intro and no submission note unless the course declares them", {
  b <- built()
  hw <- paste(readLines(list.files(b$stage, pattern = "homework-1\\.html$", recursive = TRUE, full.names = TRUE)), collapse = "\n")
  expect_match(hw, "copied from <a[^>]*>Chapter One Homework</a> in the course textbook")
  expect_no_match(hw, "Quarto"); expect_no_match(hw, "MS Word")
  p <- b$p
  edit_yaml(p, "course.yml", "  group: Assignments", "  group: Assignments\n  submission_note: \"<p>Upload a PDF.</p>\"\n  homework_intro: \"<p>See {title}.</p>\"")
  build_cartridge(p)
  hw <- paste(readLines(list.files(b$stage, pattern = "homework-1\\.html$", recursive = TRUE, full.names = TRUE)), collapse = "\n")
  expect_match(hw, "<p>See Chapter One Homework.</p>", fixed = TRUE)
  expect_match(hw, "<p>Upload a PDF.</p>", fixed = TRUE)
})

test_that("a bare due: takes due_time; a clock time is used as given; no due_time is a stop", {
  b <- built()
  all_due <- unlist(lapply(generated_files(b$stage, "assignment_settings\\.xml$"),
                           function(f) regmatches(x <- paste(readLines(f), collapse = ""), gregexpr("(?<=<due_at>)[^<]+", x, perl = TRUE))[[1]]))
  expect_setequal(all_due, c("2026-09-16T04:59:59", "2026-09-21T04:59:59", "2026-09-17T14:30:00"))
  p <- b$p
  edit_yaml(p, "modules.yml", "due: 2026-09-15", 'due: "2026-09-15 09:45"')
  build_cartridge(p)
  s <- paste(unlist(lapply(generated_files(b$stage, "assignment_settings\\.xml$"), readLines)), collapse = "")
  expect_match(s, "2026-09-15T14:45:00")
  edit_yaml(p, "course.yml", 'due_time: "23:59:59"', "")
  edit_yaml(p, "modules.yml", 'due: "2026-09-15 09:45"', "due: 2026-09-15")
  expect_error(build_cartridge(p), "needs due_time")
})

test_that("the R/exams quiz embeds with the prefix rewritten and two distinct idents", {
  b <- built()
  # The bank quiz's QTI is generated too, so the R/exams one is picked by its
  # title rather than by being the only generated file under the directory.
  qti <- Filter(function(f) any(grepl("Sample R/exams Quiz", readLines(f, warn = FALSE), fixed = TRUE)),
                generated_files(file.path(b$stage, "non_cc_assessments")))
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

test_that("both groups are emitted with their weights and each assignment and quiz lands in its own", {
  b <- built()
  ag <- paste(readLines(file.path(b$stage, "course_settings", "assignment_groups.xml")), collapse = "\n")
  expect_length(gregexpr("<assignmentGroup ", ag)[[1]], 2L)
  expect_match(ag, "<title>Quizzes</title>\\s*<position>2</position>\\s*<group_weight>20.0</group_weight>")
  gids <- regmatches(ag, gregexpr('(?<=identifier=")[^"]+', ag, perl = TRUE))[[1]]
  expect_true("g0000000000000000000000000000000b" %in% gids)
  quiz_meta <- paste(unlist(lapply(generated_files(b$stage, "assessment_meta\\.xml$"), readLines)), collapse = "")
  expect_match(quiz_meta, gids[2], fixed = TRUE)
  q1 <- paste(readLines(list.files(b$stage, pattern = "module-1-quiz", recursive = TRUE, full.names = TRUE, include.dirs = TRUE)[1]), collapse = "")
  settings <- generated_files(b$stage, "assignment_settings\\.xml$")
  refs <- vapply(settings, function(f) sub(".*<assignment_group_identifierref>([^<]+).*", "\\1", paste(readLines(f), collapse = "")), "")
  expect_setequal(unique(unname(refs)), gids)
})

test_that("an undeclared group on an assignment stops the build", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  edit_yaml(p, "modules.yml", "    quiz_file: assessments/quizzes/quiz01.md\n    group: Quizzes", "    quiz_file: assessments/quizzes/quiz01.md\n    group: Nowhere")
  expect_error(build_cartridge(p), "names assignment group 'Nowhere'")
})

test_that("item, module and resource id overrides appear where the derived ids would", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  edit_yaml(p, "modules.yml", '  - title: "Module 1: Start Here"', '  - title: "Module 1: Start Here"\n    module_id: gaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
  edit_yaml(p, "modules.yml", "      - page: welcome\n        indent: 1", "      - page: welcome\n        indent: 1\n        item_id: gbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
  edit_yaml(p, "modules.yml", "    title: Welcome\n", "    title: Welcome\n    resource_id: gcccccccccccccccccccccccccccccccc\n")
  res <- build_cartridge(p)
  mm <- paste(readLines(file.path(res$stage, "course_settings", "module_meta.xml")), collapse = "\n")
  expect_match(mm, 'module identifier="gaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"', fixed = TRUE)
  expect_match(mm, 'item identifier="gbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"', fixed = TRUE)
  expect_match(mm, "<identifierref>gcccccccccccccccccccccccccccccccc</identifierref>", fixed = TRUE)
  expect_true(file.exists(file.path(res$stage, "wiki_content", "welcome.html")))
  man <- paste(readLines(file.path(res$stage, "imsmanifest.xml")), collapse = "\n")
  expect_match(man, 'resource identifier="gcccccccccccccccccccccccccccccccc"', fixed = TRUE)
  edit_yaml(p, "modules.yml", "gcccccccccccccccccccccccccccccccc", "not-an-id")
  expect_error(build_cartridge(p), "resource_id must be g plus 32 hex")
})

test_that("course_id: and manifest_id: overrides appear where the derived ids would", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  edit_yaml(p, "course.yml", "title: Example Course",
            paste0("title: Example Course\ncourse_id: gdddddddddddddddddddddddddddddddd",
                   "\nmanifest_id: geeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"))
  res <- build_cartridge(p)
  cs <- paste(readLines(file.path(res$stage, "course_settings", "course_settings.xml")), collapse = "\n")
  expect_match(cs, 'course identifier="gdddddddddddddddddddddddddddddddd"', fixed = TRUE)
  man <- paste(readLines(file.path(res$stage, "imsmanifest.xml")), collapse = "\n")
  expect_match(man, 'manifest identifier="geeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"', fixed = TRUE)
  edit_yaml(p, "course.yml", "gdddddddddddddddddddddddddddddddd", "not-an-id")
  expect_error(build_cartridge(p), "course_id must be g plus 32 hex")
})

test_that("an item-level published: false unpublishes a page item; published over an unpublished definition stops", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  edit_yaml(p, "modules.yml", "      - page: welcome\n        indent: 1", "      - page: welcome\n        indent: 1\n        published: false")
  res <- build_cartridge(p)
  mm <- paste(readLines(file.path(res$stage, "course_settings", "module_meta.xml")), collapse = "\n")
  expect_match(mm, "<workflow_state>unpublished</workflow_state>\\s*<title>Welcome</title>")
  edit_yaml(p, "modules.yml", "      - assignment: todo-1", "      - assignment: todo-1\n        published: true")
  expect_error(build_cartridge(p), "is published but its definition is not")
})

test_that("height_measured is accepted, and a declared source with nothing carried is reported", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  edit_yaml(p, "modules.yml", '    height: "800"', '    height: "800"\n    height_measured: "2026-09-01T10:00:00"')
  drop_carried(p)                       # the reported case is a source nothing uses
  writeLines("source: reference/none.imscc", file.path(p, "reference.yml"))
  expect_output(build_cartridge(p), "source declared, 0 resources carried")
})

test_that("without grading_standard: and late_policy: the two files are neither written nor declared", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  y <- readLines(file.path(p, "course.yml"))
  cut <- function(y, start) { i <- grep(start, y); j <- i; while (j < length(y) && grepl("^  ", y[j + 1])) j <- j + 1; y[-(i:j)] }
  y <- cut(y, "^grading_standard:"); y <- cut(y, "^late_policy:")
  y <- sub("grading_standard_enabled: true", "grading_standard_enabled: false", y)
  writeLines(y, file.path(p, "course.yml"))
  res <- build_cartridge(p)
  expect_false(file.exists(file.path(res$stage, "course_settings", "grading_standards.xml")))
  expect_false(file.exists(file.path(res$stage, "course_settings", "late_policy.xml")))
  man <- paste(readLines(file.path(res$stage, "imsmanifest.xml")), collapse = "\n")
  expect_length(gregexpr('<file href="course_settings/', man)[[1]], 6L)
  cs <- paste(readLines(file.path(res$stage, "course_settings", "course_settings.xml")), collapse = "\n")
  expect_no_match(cs, "grading_standard_identifier_ref")
})

test_that("textbook_docs: none refuses a homework assignment that inlines directions", {
  skip_if_no("zip"); skip_if_no("pandoc")
  p <- copy_course(); zip_fixture_qti(p)
  edit_yaml(p, "course.yml", "textbook_docs: ../fake-textbook/docs", "textbook_docs: none")
  expect_error(build_cartridge(p), "textbook_docs is none")
})

test_that("a bank quiz is generated with its window and due date; its figure is staged, declared and the only FILEBASE user", {
  b <- built()
  qdirs <- list.files(b$stage, pattern = "assessment_meta\\.xml$", recursive = TRUE, full.names = TRUE)
  bank_meta <- qdirs[vapply(qdirs, function(f) any(grepl("Module 1 Bank Quiz", readLines(f, warn = FALSE))), TRUE)]
  expect_length(bank_meta, 1L)
  meta <- paste(readLines(bank_meta), collapse = "\n")
  expect_match(meta, "<unlock_at>2026-09-18T13:00:00</unlock_at>", fixed = TRUE)
  expect_length(gregexpr("<due_at>2026-09-26T04:59:59</due_at>", meta, fixed = TRUE)[[1]], 2L)
  expect_match(meta, "<available>true</available>", fixed = TRUE)
  expect_true(file.exists(file.path(b$stage, "web_resources", "quiz_images", "CH01_Q002.png")))
  expect_match(b$man, 'href="web_resources/quiz_images/CH01_Q002.png"', fixed = TRUE)
  users <- Filter(function(f) any(suppressWarnings(grepl("IMS-CC-FILEBASE", readLines(f, warn = FALSE), fixed = TRUE))),
                  list.files(b$stage, recursive = TRUE, full.names = TRUE))
  expect_true(all(grepl("non_cc_assessments/|/assessment_qti\\.xml$", users)))
  expect_match(b$mm, "<content_type>Quizzes::Quiz</content_type>\\s*<workflow_state>active</workflow_state>\\s*<title>Module 1 Bank Quiz</title>")
})

test_that("a FILEBASE token outside the quiz files, or pointing at an undeclared image, fails the build", {
  msgs <- character(); p_fail <- function(...) msgs <<- c(msgs, paste0(...))
  d <- withr::local_tempdir(); dir.create(file.path(d, "wiki_content"))
  writeLines('<img src="$IMS-CC-FILEBASE$/quiz_images/x.png">', file.path(d, "wiki_content", "p.html"))
  writeLines('<?xml version="1.0"?><manifest xmlns:lomimscc="x" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="y"><metadata><schemaversion>1.1.0</schemaversion><lomimscc:lom/></metadata><organizations/><resources/></manifest>', file.path(d, "imsmanifest.xml"))
  prezip_checks(d, "gx", character(), p_fail)
  expect_true(any(grepl("IMS-CC-FILEBASE in p.html", msgs)))
})

test_that("a description: assignment writes the R settings template with its grading type and body", {
  b <- built()
  f <- list.files(b$stage, pattern = "position-memo-draft\\.html$", recursive = TRUE, full.names = TRUE)
  expect_length(f, 1L)
  expect_match(paste(readLines(f), collapse = ""), "Upload your draft before class on Thursday.", fixed = TRUE)
  s <- paste(readLines(file.path(dirname(f), "assignment_settings.xml")), collapse = "\n")
  expect_match(s, "<grading_type>pass_fail</grading_type>", fixed = TRUE)
  expect_match(s, "<points_possible>2.0</points_possible>", fixed = TRUE)
  expect_match(s, "<due_at>2026-09-17T14:30:00</due_at>", fixed = TRUE)
  p <- b$p; edit_yaml(p, "modules.yml", "grading_type: pass_fail", "grading_type: gold_star")
  expect_error(build_cartridge(p), "grading_type must be points, pass_fail, percent, or letter_grade")
})

test_that("a quiz with two body forms, or an assignment with none, is refused by read_manifest", {
  p <- copy_course()
  edit_yaml(p, "modules.yml", "    qti: build/qti/quiz-sample.zip", "    qti: build/qti/quiz-sample.zip\n    source_ref: g00000000000000000000000000000q01")
  expect_error(read_manifest(p), "quiz 'q-sample' declares more than one of")
  p2 <- copy_course()
  edit_yaml(p2, "modules.yml", '    description: "<p>Upload your draft before class on Thursday.</p>"', "")
  expect_error(read_manifest(p2), "assignment 'memo-1' declares none of")
})

test_that("the pre-zip scan refuses a manifest whose header lost its load-bearing tokens", {
  p_fail_msgs <- character(); p_fail <- function(...) p_fail_msgs <<- c(p_fail_msgs, paste0(...))
  d <- withr::local_tempdir(); dir.create(file.path(d, "course_settings"))
  writeLines("<?xml version=\"1.0\"?><manifest><organizations/><resources/></manifest>", file.path(d, "imsmanifest.xml"))
  prezip_checks(d, settings_res = "gx", ann_res = character(), p_fail = p_fail)
  expect_true(any(grepl("manifest header is missing xmlns:lomimscc", p_fail_msgs)))
  expect_true(any(grepl("canvas_export.txt", p_fail_msgs)))
})
