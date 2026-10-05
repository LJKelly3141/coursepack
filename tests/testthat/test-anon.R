# Anonymized grading: the key, redaction, conversion, anonymize() and relink().
# Fixtures are invented; see helper-anon.R. Tests that build a .docx need
# pandoc, those that build a PDF need xelatex and poppler, and relink() needs
# zip; each skips through helper-skips.R when its tool is absent.

# ---- key -------------------------------------------------------------------

test_that("Canvas download names parse into prefix, LATE flag, ids and original name", {
  x <- parse_canvas_filename("quillpat_1001_5001_Quiz 2.docx")
  expect_identical(x$prefix, "quillpat")
  expect_identical(x$canvas_id, "1001")
  expect_identical(x$late, FALSE)
  expect_identical(x$original, "Quiz 2.docx")  # original name kept whole
  y <- parse_canvas_filename("riveramorgan_LATE_1002_5002_spec.md")
  expect_identical(y$late, TRUE)
  expect_identical(y$canvas_id, "1002")         # id after LATE
  expect_null(parse_canvas_filename("case03_scores.csv"))
})

test_that("the key drops the points row and test student, and a rebuild keeps hand edits", {
  cc <- anon_course(nickname = FALSE)
  kp <- file.path(cc$td, "k.csv")
  k <- quiet(build_key(fake_gradebook(cc$td), kp, "Quiz"))
  expect_identical(nrow(k), 3L)                                  # points row and test student dropped
  expect_identical(sort(k$code), c("S01", "S02", "S03"))        # codes are a permutation
  expect_identical(k$canvas_id, c("1001", "1002", "1003"))      # rows in id order
  expect_identical(unique(k$run), "Quiz")
  expect_identical(k$name[1], "Pat Quill")
  expect_identical(k$file_prefix[1], "quillpat")
  expect_true("Quill, Pat" %in% split_list(k$name_forms[1]))

  k2 <- read_key(kp); k2$nicknames[2] <- "Mo"; utils::write.csv(k2, kp, row.names = FALSE)
  k3 <- quiet(build_key(fake_gradebook(cc$td), kp, "Quiz"))
  expect_identical(k3$nicknames[2], "Mo")   # rebuild keeps a hand-added nickname
  expect_identical(nrow(k3), 3L)            # rebuild adds no duplicate rows
  expect_identical(k3$code, k$code)         # and changes no code

  tt <- key_terms(read_key(kp))
  rivera <- k$code[k$canvas_id == "1002"]
  expect_true(nchar(tt$term[1]) >= nchar(tt$term[nrow(tt)]))   # longest first
  expect_identical(tt$code[tolower(tt$term) == "pat"], "SXX")    # shared first name
  expect_identical(tt$code[tt$term == "Mo"], rivera)             # nickname present
})

test_that("anon_key() writes the key into the assignment folder, under proj, and prints no name", {
  cc <- anon_course(nickname = FALSE)
  dir.create(file.path(cc$proj, "semester", "Essay"), recursive = TRUE)
  out <- capture.output(k <- anon_key(cc$proj, "gradebook.csv", "semester/Essay"))
  kp <- file.path(cc$proj, "semester", "Essay", "anon_key.csv")
  expect_true(file.exists(kp))
  expect_false(file.exists(file.path(cc$proj, "semester", "Essay", "anon", "anon_key.csv")))
  expect_identical(sort(k$code), c("S01", "S02", "S03"))
  expect_identical(unique(read_key(kp)$run), "semester/Essay")
  expect_false(any(grepl("Quill|Rivera|Stone|100[123]|XQ", out)))
  expect_true(any(grepl("coursepack", out)))
  expect_error(anon_key(file.path(cc$proj, "nope"), "gradebook.csv", "semester/Essay"),
               "not a directory")
  expect_error(anon_key(cc$proj, "gradebook.csv", "semester/Nope"), "no assignment folder")
})

# ---- redaction ---------------------------------------------------------------

test_that("redaction replaces every name form whole-word with the right code", {
  cc <- anon_course()
  terms <- key_terms(read_key(cc$kp))
  r <- redact_text("Written by Pat Quill. Quill's plot; QUILL again.", terms)
  expect_true(grepl("\\[name\\]\\.", r$text))                    # full name becomes one token
  expect_false(grepl("quill", r$text, ignore.case = TRUE))      # possessive and upper case
  expect_identical(redact_text("Thanks, Pat.", terms)$text, "Thanks, [name].")
  expect_true(r$n >= 3L)                                        # counts replacements
  expect_identical(redact_text("file quillpat_1001_5001.docx", terms)$text,
                   "file [name]_[name]_5001.docx")              # underscore-glued prefix
  expect_identical(redact_text("I worked with Morgan Rivera.", terms)$text,
                   "I worked with [name].")                     # classmate gets the same token
  expect_identical(redact_text("Quillon", terms)$text, "Quillon")  # inside a longer word
})

test_that("home-folder user names and email addresses are redacted", {
  # The macOS home root is assembled from pieces so the package's absolute-path
  # audit does not read this fixture as a real path.
  mac_home <- paste0("/Us", "ers/")
  expect_identical(redact_paths(paste0(mac_home, "pquill/data/x.csv")),
                   paste0(mac_home, "USER/data/x.csv"))
  expect_identical(redact_paths("C:\\Users\\pquill\\x.R"), "C:\\Users\\USER\\x.R")
  expect_identical(redact_paths(paste0("C:", mac_home, "pquill/x")),
                   paste0("C:", mac_home, "USER/x"))
  expect_identical(redact_paths("mail pat.quill@my.example.invalid now"), "mail EMAIL now")
})

test_that("the leftover check finds a planted name and reports only its code", {
  cc <- anon_course()
  terms <- key_terms(read_key(cc$kp))
  lf <- file.path(cc$td, "leftover.md"); writeLines("clean text, S01", lf)
  expect_identical(nrow(find_leftovers(lf, terms)), 0L)
  writeLines("oops Rivera slipped through", lf)
  lo <- find_leftovers(lf, terms)
  expect_identical(lo$code, "S02")
  expect_false(any(grepl("Rivera", unlist(lo))))
})

# ---- conversion ----------------------------------------------------------------

test_that("conversion to text drops document metadata and copies text files", {
  skip_if_no("pandoc")
  cc <- anon_course()
  td <- cc$td
  src <- file.path(td, "src.md")
  writeLines(c("# Quiz", "", "Answer by Pat Quill."), src)
  docx <- file.path(td, "in.docx")
  system2("pandoc", c(shQuote(src), "-M", shQuote("author=Pat Quill"), "-o", shQuote(docx)))
  out <- file.path(td, "out_docx.md")
  convert_to_text(docx, out, file.path(td, "media_docx"))
  txt <- paste(readLines(out), collapse = "\n")
  expect_true(grepl("Answer by", txt))
  expect_identical(lengths(regmatches(txt, gregexpr("Pat Quill", txt))), 1L)  # no metadata copy

  qmd <- file.path(td, "in.qmd"); writeLines(c("---", "author: Pat Quill", "---", "x"), qmd)
  out2 <- file.path(td, "out_qmd.md")
  convert_to_text(qmd, out2, file.path(td, "media_qmd"))
  expect_identical(readLines(out2)[2], "author: Pat Quill")

  xl <- file.path(td, "in.xlsx"); writeLines("x", xl)
  expect_true(grepl("\\.xlsx", errors_with(convert_to_text(xl, file.path(td, "o.md"),
                                                            file.path(td, "m")))))
})

test_that("a PDF submission converts to text", {
  skip_if_no("pandoc"); skip_if_no("xelatex"); skip_if_no("pdftotext"); skip_if_no("pdfimages")
  cc <- anon_course()
  src <- file.path(cc$td, "src.md")
  writeLines(c("# Quiz", "", "Answer by Pat Quill."), src)
  pdf <- file.path(cc$td, "in.pdf")
  system2("pandoc", c(shQuote(src), "--pdf-engine=xelatex", "-o", shQuote(pdf)))
  out3 <- file.path(cc$td, "out_pdf.md")
  convert_to_text(pdf, out3, file.path(cc$td, "media_pdf"))
  expect_true(grepl("Answer by", paste(readLines(out3, warn = FALSE), collapse = " ")))
})

# ---- anonymize -----------------------------------------------------------------

quiz_assignment <- function(td) {
  ad <- file.path(td, "Quiz"); dir.create(ad)
  mk_docx(file.path(ad, "quillpat_1001_5001_Quiz 2.docx"),
          c("Pat Quill", "", "Worked with Morgan Rivera.",
            "", "`C:\\Users\\pquill\\q.R`", "", "pat@example.invalid"))
  mk_docx(file.path(ad, "riveramorgan_LATE_1002_5002_My Quiz.docx"),
          c("Morgan Rivera answers."))
  writeLines("x", file.path(ad, "quiz_scores.csv"))
  ad
}

test_that("anonymize writes coded text with no identity left, and refuses to discard grading", {
  skip_if_no("pandoc")
  cc <- anon_course(); proj <- cc$proj; kp <- cc$kp
  ad <- quiz_assignment(cc$td)
  res <- anon(proj, ad, kp)
  an <- file.path(ad, "anon")
  expect_identical(sort(list.dirs(an, full.names = FALSE, recursive = FALSE)), c("S01", "S02"))
  expect_true(file.exists(file.path(an, "S01", "file1.md")))   # single-file student is file1
  expect_false(file.exists(file.path(an, "NOT_READY")))        # released
  all_txt <- paste(unlist(lapply(list.files(an, "\\.(md|csv)$", recursive = TRUE,
                                            full.names = TRUE), readLines)), collapse = "\n")
  expect_false(grepl("Quill|Rivera|quillpat|1001|XQ100|pquill|example\\.invalid", all_txt,
                     ignore.case = TRUE))
  man <- utils::read.csv(file.path(an, "manifest.csv"), colClasses = "character")
  expect_false("late" %in% names(man))   # lateness stays out of anon/
  expect_false("original" %in% names(man))
  expect_identical(res$students, 2L)

  dir.create(file.path(an, "feedback"))
  expect_true(grepl("feedback", errors_with(anon(proj, ad, kp))))
  expect_true(dir.exists(file.path(an, "feedback")))   # feedback survives the refusal
})

test_that("anonymize refuses an anon_dir that would delete files it does not own", {
  skip_if_no("pandoc")
  cc <- anon_course(); proj <- cc$proj; kp <- cc$kp; td <- cc$td
  sfd <- file.path(td, "Safety"); dir.create(sfd)
  mk_docx(file.path(sfd, "quillpat_1001_9001_hw.docx"), "hw text")
  msg_self <- errors_with(anon(proj, sfd, kp, anon_dir = sfd))
  expect_false(is.na(msg_self))   # anon_dir equal to the assignment folder is refused
  expect_true(file.exists(file.path(sfd, "quillpat_1001_9001_hw.docx")))

  bad_out <- file.path(td, "SafetyOut"); dir.create(bad_out)
  writeLines("not ours", file.path(bad_out, "important.txt"))
  msg_unsafe <- errors_with(anon(proj, sfd, kp, anon_dir = bad_out))
  expect_false(is.na(msg_unsafe))   # a non-empty anon_dir with no manifest/NOT_READY
  expect_true(file.exists(file.path(bad_out, "important.txt")))
})

test_that("a student's several files are numbered in upload order with one target", {
  skip_if_no("pandoc")
  cc <- anon_course(); proj <- cc$proj; kp <- cc$kp; td <- cc$td
  cd <- file.path(td, "Case"); dir.create(cd)
  mk_docx(file.path(cd, "quillpat_1001_6001_spec.docx"), "spec by Pat Quill")
  mk_docx(file.path(cd, "quillpat_1001_6002_analysis.docx"), "analysis")
  anon(proj, cd, kp)
  expect_identical(sort(list.files(file.path(cd, "anon", "S01"), "\\.md$")),
                   c("file1.md", "file2.md"))
  man_cd <- utils::read.csv(file.path(cd, "anon", "manifest.csv"), colClasses = "character")
  expect_identical(man_cd$spec[man_cd$file == "file1"], "TRUE")
  expect_identical(man_cd$file[man_cd$target == "TRUE"], "file2")

  writeLines("100", file.path(cd, "anon", "scores.csv"))
  msg_scores <- errors_with(anon(proj, cd, kp))
  expect_true(grepl("scores", msg_scores, ignore.case = TRUE))
  expect_true(file.exists(file.path(cd, "anon", "scores.csv")))

  # Two files that are both specs is not an error; the target is the latest.
  bd <- file.path(td, "Bad"); dir.create(bd)
  mk_docx(file.path(bd, "quillpat_1001_7001_spec.docx"), "a")
  mk_docx(file.path(bd, "quillpat_1001_7002_spec_revised.docx"), "b")
  anon(proj, bd, kp)
  man_bd <- utils::read.csv(file.path(bd, "anon", "manifest.csv"), colClasses = "character")
  expect_identical(sort(man_bd$file), c("file1", "file2"))
  expect_identical(man_bd$file[man_bd$target == "TRUE"], "file2")

  ud <- file.path(td, "Unknown"); dir.create(ud)
  mk_docx(file.path(ud, "nobodyx_4242_8001_q.docx"), "a")
  msg <- errors_with(anon(proj, ud, kp))
  expect_true(!is.na(msg) && !grepl("4242|nobody", msg))   # stops without printing the id
})

test_that("anonymize() resolves relative paths against proj and defaults anon_dir", {
  skip_if_no("tesseract")
  cc <- anon_course()
  ad <- file.path(cc$proj, "semester", "Essay"); dir.create(ad, recursive = TRUE)
  writeLines("Pat Quill wrote this.", file.path(ad, "quillpat_1001_5001_essay.md"))
  stage_key(cc$proj, "semester/Essay", cc$kp)
  out <- capture.output(anonymize(cc$proj, "semester/Essay", dict = NULL))
  expect_identical(readLines(file.path(ad, "anon", "S01", "file1.md")), "[name] wrote this.")
  expect_true(any(grepl("coursepack", out)))
  expect_false(any(grepl("Quill|1001|5001|essay", out)))
})

test_that("a classmate's name in one paper becomes [name], never that student's code", {
  skip_if_no("tesseract")
  cc <- anon_course()
  ad <- file.path(cc$proj, "semester", "Essay"); dir.create(ad, recursive = TRUE)
  writeLines("Pat Quill thanks Morgan for the data.", file.path(ad, "quillpat_1001_5001_essay.md"))
  writeLines("Rivera Morgan wrote this alone.", file.path(ad, "riveramorgan_1002_5002_essay.md"))
  stage_key(cc$proj, "semester/Essay", cc$kp)
  res <- quiet(anonymize(cc$proj, "semester/Essay", dict = NULL))
  txt <- readLines(file.path(ad, "anon", "S01", "file1.md"))
  expect_identical(txt, "[name] thanks [name] for the data.")
  expect_false(any(grepl("S[0-9][0-9]|SXX", txt)))
  expect_gte(res$replacements, 2L)
})

# ---- relink --------------------------------------------------------------------

test_that("relink names feedback like the submission, restores the name and zips exactly", {
  skip_if_no("pandoc"); skip_if_no("zip")
  cc <- anon_course(); proj <- cc$proj; kp <- cc$kp; td <- cc$td
  ad <- quiz_assignment(td)
  anon(proj, ad, kp)
  fbd <- file.path(ad, "anon", "feedback"); dir.create(fbd)
  writeLines(c("# Quiz Feedback: S01", "", "Good work, S01."), file.path(fbd, "S01.md"))
  writeLines(c("# Quiz Feedback: S02", "", "Solid."), file.path(fbd, "S02.md"))
  utils::write.csv(data.frame(code = c("S01", "S02"), Q1 = c("8", "7"), total = c("8", "7")),
                   file.path(ad, "anon", "scores.csv"), row.names = FALSE)

  od <- file.path(td, "out"); dir.create(od)
  relnk(proj, ad, kp, out_dir = od)
  fb1 <- file.path(od, "feedback", "quillpat_1001_5001_Quiz 2.docx")
  expect_true(file.exists(fb1))
  t1 <- paste(system2("pandoc", c(shQuote(fb1), "-t", "plain"), stdout = TRUE), collapse = " ")
  expect_true(grepl("Pat Quill", t1))
  expect_false(grepl("S01", t1))
  sc <- utils::read.csv(file.path(od, "quiz_scores.csv"), colClasses = "character")
  expect_identical(sc$canvas_id[sc$name == "Pat Quill"], "1001")
  z <- utils::unzip(file.path(od, "feedback.zip"), list = TRUE)$Name
  expect_identical(sort(sub("^feedback/", "", z[z != "feedback/"])),
                   sort(c("quillpat_1001_5001_Quiz 2.docx",
                          "riveramorgan_LATE_1002_5002_My Quiz.docx")))

  expect_true(grepl("already", errors_with(relnk(proj, ad, kp, out_dir = od))))

  writeLines(c("# Quiz Feedback: S01", "", "Better than S02."), file.path(fbd, "S01.md"))
  od2 <- file.path(td, "out2"); dir.create(od2)
  msg <- errors_with(relnk(proj, ad, kp, out_dir = od2))
  expect_true(grepl("S01", msg))   # stops when feedback names another student

  writeLines("x", file.path(ad, "anon", "NOT_READY"))
  expect_true(grepl("NOT_READY|not ready", errors_with(relnk(proj, ad, kp, out_dir = od2))))
})

test_that("a PDF submission gets PDF feedback under its exact name", {
  skip_if_no("pandoc"); skip_if_no("xelatex"); skip_if_no("pdftotext"); skip_if_no("pdfimages")
  skip_if_no("zip")
  cc <- anon_course(); proj <- cc$proj; kp <- cc$kp; td <- cc$td
  pd <- file.path(td, "Pdf"); dir.create(pd)
  s <- tempfile(fileext = ".md"); writeLines("answer", s)
  system2("pandoc", c(shQuote(s), "--pdf-engine=xelatex", "-o",
                      shQuote(file.path(pd, "quillpat_1001_9001_quiz.pdf"))))
  anon(proj, pd, kp)
  dir.create(file.path(pd, "anon", "feedback"))
  writeLines(c("# Feedback: S01", "", "ok"), file.path(pd, "anon", "feedback", "S01.md"))
  utils::write.csv(data.frame(code = "S01", total = "9"), file.path(pd, "anon", "scores.csv"),
                   row.names = FALSE)
  od3 <- file.path(td, "out3"); dir.create(od3)
  relnk(proj, pd, kp, out_dir = od3)
  expect_true(file.exists(file.path(od3, "feedback", "quillpat_1001_9001_quiz.pdf")))
})

test_that("a blank login on another student does not block feedback", {
  skip_if_no("pandoc"); skip_if_no("zip")
  cc <- anon_course(); proj <- cc$proj; kp <- cc$kp; td <- cc$td
  # read_key's na.strings = character() turns a blank gradebook cell into "",
  # not NA, and a blank must not act as a wildcard.
  kp_blank <- file.path(td, "anon_key_blank.csv")
  kb <- read_key(kp); kb$login[kb$code == "S03"] <- ""
  utils::write.csv(kb, kp_blank, row.names = FALSE)
  bl <- file.path(td, "BlankLogin"); dir.create(bl)
  mk_docx(file.path(bl, "quillpat_1001_9101_quiz.docx"), "Pat Quill answers.")
  anon(proj, bl, kp_blank)
  dir.create(file.path(bl, "anon", "feedback"))
  writeLines(c("# Feedback: S01", "", "Nice work overall."),
             file.path(bl, "anon", "feedback", "S01.md"))
  utils::write.csv(data.frame(code = "S01", total = "10"),
                   file.path(bl, "anon", "scores.csv"), row.names = FALSE)
  obl <- file.path(td, "out_blank"); dir.create(obl)
  msg_blank <- errors_with(relnk(proj, bl, kp_blank, out_dir = obl))
  expect_true(is.na(msg_blank))
  expect_true(file.exists(file.path(obl, "feedback", "quillpat_1001_9101_quiz.docx")))
})

test_that("relink's output guards fire before anything is written, and a render failure leaves nothing", {
  skip_if_no("pandoc"); skip_if_no("zip")
  cc <- anon_course(); proj <- cc$proj; kp <- cc$kp; td <- cc$td
  rd <- file.path(td, "Relink2"); dir.create(rd)
  mk_docx(file.path(rd, "quillpat_1001_9201_Quiz 9.docx"), "Pat Quill.")
  mk_docx(file.path(rd, "riveramorgan_1002_9202_Quiz 9.docx"), "Morgan Rivera.")
  anon(proj, rd, kp)
  rfbd <- file.path(rd, "anon", "feedback"); dir.create(rfbd)
  writeLines(c("# Feedback: S01", "", "Good."), file.path(rfbd, "S01.md"))
  writeLines(c("# Feedback: S02", "", "Great."), file.path(rfbd, "S02.md"))
  utils::write.csv(data.frame(code = c("S01", "S02"), total = c("9", "10")),
                   file.path(rd, "anon", "scores.csv"), row.names = FALSE)

  ro1 <- file.path(td, "rout1"); dir.create(ro1)
  writeLines("stray", file.path(ro1, "relink2_scores.csv"))
  msg1 <- errors_with(relnk(proj, rd, kp, out_dir = ro1))
  expect_false(is.na(msg1))
  expect_false(dir.exists(file.path(ro1, "feedback")))

  ro2 <- file.path(td, "rout2"); dir.create(ro2)
  writeLines("stray", file.path(ro2, "feedback.zip"))
  msg2 <- errors_with(relnk(proj, rd, kp, out_dir = ro2))
  expect_false(is.na(msg2))
  expect_false(dir.exists(file.path(ro2, "feedback")))

  ro3 <- file.path(td, "rout3"); dir.create(ro3)
  real_render <- render_feedback
  msg3 <- local({
    local_mocked_bindings(render_feedback = function(md_lines, target, ...) {
      if (grepl("riveramorgan", target, fixed = TRUE)) stop("simulated render failure")
      real_render(md_lines, target, ...)
    })
    errors_with(relnk(proj, rd, kp, out_dir = ro3))
  })
  expect_false(is.na(msg3))
  expect_false(dir.exists(file.path(ro3, "feedback")))

  ro4 <- file.path(td, "rout4"); dir.create(ro4)
  relnk(proj, rd, kp, out_dir = ro4)
  z4 <- utils::unzip(file.path(ro4, "feedback.zip"), list = TRUE)$Name
  z4 <- sort(sub("^feedback/", "", z4[z4 != "feedback/"]))
  expect_identical(z4, sort(c("quillpat_1001_9201_Quiz 9.docx",
                              "riveramorgan_1002_9202_Quiz 9.docx")))
})

test_that("relink() defaults anon_dir and out_dir to the assignment folder, under proj", {
  skip_if_no("zip")
  cc <- anon_course()
  ad <- file.path(cc$proj, "semester", "Essay"); dir.create(ad, recursive = TRUE)
  writeLines("Pat Quill wrote this.", file.path(ad, "quillpat_1001_5001_essay.md"))
  anon(cc$proj, "semester/Essay", cc$kp)
  dir.create(file.path(ad, "anon", "feedback"))
  writeLines("Good, S01.", file.path(ad, "anon", "feedback", "S01.md"))
  utils::write.csv(data.frame(code = "S01", total = "9"), file.path(ad, "anon", "scores.csv"),
                   row.names = FALSE)
  out <- capture.output(relink(cc$proj, "semester/Essay", dict = NULL))
  expect_identical(readLines(file.path(ad, "feedback", "quillpat_1001_5001_essay.md")),
                   "Good, Pat Quill.")
  expect_true(file.exists(file.path(ad, "essay_scores.csv")))
  expect_true(file.exists(file.path(ad, "feedback.zip")))
  expect_true(any(grepl("coursepack", out)))
  expect_false(any(grepl("Quill|1001|5001", out)))
})

# ---- final review fixes ----------------------------------------------------------

test_that("joined, initial and accent-stripped forms redact, with letter-only name boundaries", {
  cc <- anon_course()
  td1 <- cc$td
  gb1 <- file.path(td1, "gradebook1.csv")
  writeLines(c(
    'Student,ID,SIS User ID,SIS Login ID,Root Account,Section',
    '    Points Possible,,,,,',
    '"Umlauf, Ashley",2001,U1,XQ2001,x,90',
    '"N\u00fa\u00f1ez, Jos\u00e9",2002,U2,XQ2002,x,90'), gb1, useBytes = TRUE)
  kp1 <- file.path(td1, "anon_key1.csv")
  fixture_key(gb1, kp1)
  terms1 <- key_terms(read_key(kp1))
  f1 <- function(s) redact_text(s, terms1)$text
  expect_identical(f1("by AshleyUmlauf today"), "by [name] today")
  expect_identical(f1("umlaufashley.R"), "[name].R")
  expect_identical(f1("user aumlauf here"), "user [name] here")
  expect_identical(f1("Umlauf2 draft"), "[name]2 draft")
  expect_identical(f1("x_umlauf_y"), "x_[name]_y")
  expect_identical(f1("Jos\u00e9 N\u00fa\u00f1ez wrote this"), "[name] wrote this")
  expect_identical(f1("Jose Nunez wrote this"), "[name] wrote this")
  expect_identical(f1("josenunez"), "[name]")
  expect_identical(f1("XQ2001"), "[name]")         # login still redacted
  expect_identical(f1("x2001y"), "x2001y")       # id glued to letters keeps the alnum rule
  expect_identical(f1("Umlaufen"), "Umlaufen")   # a name inside a longer word left alone

  lf1 <- file.path(td1, "planted.md")
  writeLines("the file xxumlaufashleyxx was attached", lf1)
  lo1 <- find_leftovers(lf1, terms1)
  expect_identical(lo1$code, "S01")                              # loose pass caught it
  expect_identical(f1("xxumlaufashleyxx"), "xxumlaufashleyxx")   # the redactor did not
  writeLines("Umlaufen is a German verb, clean otherwise", lf1)
  expect_identical(nrow(find_leftovers(lf1, terms1)), 0L)
  lf1b <- file.path(td1, "planted2.md")
  writeLines("xxquillpatxx", lf1b)
  expect_identical(find_leftovers(lf1b, key_terms(read_key(cc$kp)))$code, "S01")
})

test_that("Windows and Unix home folders are redacted in every spelling", {
  expect_identical(redact_paths("C:\\Users\\pquill\\x.R"), "C:\\Users\\USER\\x.R")
  expect_identical(redact_paths("C:\\\\Users\\\\pquill\\\\x.R"), "C:\\\\Users\\\\USER\\\\x.R")
  expect_identical(redact_paths("c:\\users\\pquill\\x.R"), "c:\\users\\USER\\x.R")
  expect_identical(redact_paths("/users/pquill/x"), "/users/USER/x")
  expect_identical(redact_paths("/HOME/pquill/x"), "/HOME/USER/x")
})

test_that("ignored files are counted, never named, and unfed submissions reported by code", {
  skip_if_no("pandoc"); skip_if_no("zip"); skip_if_no("tesseract")
  cc <- anon_course(); proj <- cc$proj; kp <- cc$kp; td <- cc$td
  ig <- file.path(td, "Ignored"); dir.create(ig)
  mk_docx(file.path(ig, "quillpat_1001_9901_q.docx"), "a")
  stage_key(proj, ig, kp)
  out_ign <- capture.output(anonymize(proj, ig, dict = NULL))
  expect_false(any(grepl("ignored", out_ign)))   # the key beside the downloads is not counted
  writeLines("x", file.path(ig, "notes.txt"))
  writeLines("x", file.path(ig, "other.csv"))
  out_ign2 <- tryCatch(capture.output(anonymize(proj, ig, dict = NULL)),
                       error = function(e) conditionMessage(e))
  expect_true(any(grepl("^2 file\\(s\\) ignored \\(not Canvas submission names\\)", out_ign2)))
  expect_false(any(grepl("notes|other", out_ign2)))

  nf <- file.path(td, "NoFeedback"); dir.create(nf)
  mk_docx(file.path(nf, "quillpat_1001_9301_q.docx"), "Pat Quill.")
  mk_docx(file.path(nf, "riveramorgan_1002_9302_q.docx"), "Morgan Rivera.")
  mk_docx(file.path(nf, "stonepat_1003_9303_q.docx"), "Pat Stone.")
  anon(proj, nf, kp)
  dir.create(file.path(nf, "anon", "feedback"))
  writeLines(c("# Feedback: S01", "", "ok"), file.path(nf, "anon", "feedback", "S01.md"))
  utils::write.csv(data.frame(code = "S01", total = "9"), file.path(nf, "anon", "scores.csv"),
                   row.names = FALSE)
  onf <- file.path(td, "out_nf"); dir.create(onf)
  out_nf <- capture.output(relink(proj, nf, out_dir = onf, dict = NULL))
  expect_true(any(grepl("^2 submission\\(s\\) have no feedback: S02, S03$", out_nf)))
  expect_false(any(grepl("Rivera|Stone|1002|1003", out_nf)))
})

test_that("a failed re-run leaves NOT_READY, never an old anon/ looking ready", {
  skip_if_no("pandoc")
  cc <- anon_course(); proj <- cc$proj; kp <- cc$kp; td <- cc$td
  nr <- file.path(td, "NotReady"); dir.create(nr)
  mk_docx(file.path(nr, "quillpat_1001_9401_q.docx"), "quiz")
  anon(proj, nr, kp)
  expect_false(file.exists(file.path(nr, "anon", "NOT_READY")))
  mk_docx(file.path(nr, "nobodyx_4242_9402_q.docx"), "unknown student")
  msg4 <- errors_with(anon(proj, nr, kp))
  expect_false(is.na(msg4))
  expect_true(file.exists(file.path(nr, "anon", "NOT_READY")))
})

test_that("'spec' must start a word", {
  cc <- anon_course()
  k5 <- read_key(cc$kp)
  s5 <- data.frame(file = c("a", "b"), prefix = "quillpat", late = FALSE,
                   canvas_id = c("1001", "1001"), submission_id = c("1", "2"),
                   original = c("Perspective analysis.docx", "spec.md"),
                   stringsAsFactors = FALSE)
  r5 <- tryCatch(assign_files(s5, k5), error = function(e) NULL)
  expect_identical(r5$spec, c(FALSE, TRUE))
  expect_identical(r5$anon_name[r5$target], "file1")
})

test_that("a feedback write failure names the code, never the Canvas filename", {
  td <- withr::local_tempdir()
  target <- file.path(td, "no_such_dir", "quillpat_1001_5001_notes.md")
  msg6 <- errors_with(render_feedback("x", target, "S01"))
  expect_true(grepl("S01", msg6))
  expect_false(grepl("quill|1001|5001", msg6, ignore.case = TRUE))
  warn6 <- character()
  invisible(withCallingHandlers(
    errors_with(render_feedback("x", target, "S01")),
    warning = function(w) {
      warn6 <<- c(warn6, conditionMessage(w)); invokeRestart("muffleWarning")
    }))
  expect_false(any(grepl("quill|1001|5001", warn6, ignore.case = TRUE)))
})

test_that("image links in the anonymized text resolve relative to the .md", {
  skip_if_no("pandoc")
  cc <- anon_course(); proj <- cc$proj; kp <- cc$kp; td <- cc$td
  im <- file.path(td, "Img"); dir.create(im)
  png_path <- file.path(td, "fig.png")
  grDevices::png(png_path, width = 50, height = 50)
  grid::grid.rect(gp = grid::gpar(fill = "grey"))
  invisible(grDevices::dev.off())
  mk_docx(file.path(im, "quillpat_1001_9501_hw.docx"),
          c("Figure below.", "", paste0("![](", png_path, ")")))
  anon(proj, im, kp)
  md7 <- file.path(im, "anon", "S01", "file1.md")
  l7 <- regmatches(readLines(md7), regexpr("!\\[[^]]*\\]\\([^)]+\\)", readLines(md7)))
  link7 <- sub("^!\\[[^]]*\\]\\(([^) ]+).*$", "\\1", l7)
  expect_identical(length(link7), 1L)
  expect_false(startsWith(link7, "/"))
  expect_true(file.exists(file.path(dirname(md7), link7)))
  expect_true(startsWith(link7, "file1_media/media/"))
})

test_that("a code listed twice in scores.csv stops relink with nothing written", {
  skip_if_no("pandoc")
  cc <- anon_course(); proj <- cc$proj; kp <- cc$kp; td <- cc$td
  dd <- file.path(td, "Dup"); dir.create(dd)
  mk_docx(file.path(dd, "quillpat_1001_9601_q.docx"), "a")
  mk_docx(file.path(dd, "riveramorgan_1002_9602_q.docx"), "b")
  anon(proj, dd, kp)
  dir.create(file.path(dd, "anon", "feedback"))
  writeLines("ok", file.path(dd, "anon", "feedback", "S01.md"))
  writeLines("ok", file.path(dd, "anon", "feedback", "S02.md"))
  utils::write.csv(data.frame(code = c("S01", "S02", "S02"), total = c("1", "2", "3")),
                   file.path(dd, "anon", "scores.csv"), row.names = FALSE)
  od8 <- file.path(td, "out_dup"); dir.create(od8)
  msg8 <- errors_with(relnk(proj, dd, kp, out_dir = od8))
  expect_identical(msg8, "scores.csv lists a code more than once: S02")
  expect_identical(length(list.files(od8, all.files = TRUE, no.. = TRUE)), 0L)
})

test_that("a conversion failure names the code and file position, and stays NOT_READY", {
  cc <- anon_course(); proj <- cc$proj; kp <- cc$kp; td <- cc$td
  cf <- file.path(td, "ConvFail"); dir.create(cf)
  # A document comes first so the student has a target; a student with no
  # document at all stops earlier, at target selection.
  writeLines("x", file.path(cf, "quillpat_1001_9700_hw.md"))
  writeLines("x", file.path(cf, "quillpat_1001_9701_hw.xlsx"))
  msg9 <- errors_with(anon(proj, cf, kp))
  expect_true(startsWith(msg9, "S01 (file2): unsupported submission type: .xlsx"))
  expect_false(grepl("quill|1001", msg9, ignore.case = TRUE))
  expect_true(file.exists(file.path(cf, "anon", "NOT_READY")))
})

test_that("a classmate's full name in feedback stops relink with nothing written", {
  skip_if_no("pandoc")
  cc <- anon_course(); proj <- cc$proj; kp <- cc$kp; td <- cc$td
  cs <- file.path(td, "Cross"); dir.create(cs)
  mk_docx(file.path(cs, "quillpat_1001_9801_q.docx"), "a")
  mk_docx(file.path(cs, "riveramorgan_1002_9802_q.docx"), "b")
  anon(proj, cs, kp)
  dir.create(file.path(cs, "anon", "feedback"))
  writeLines(c("# Feedback: S01", "", "Compare with Morgan Rivera's plot."),
             file.path(cs, "anon", "feedback", "S01.md"))
  writeLines("ok", file.path(cs, "anon", "feedback", "S02.md"))
  utils::write.csv(data.frame(code = c("S01", "S02"), total = c("1", "2")),
                   file.path(cs, "anon", "scores.csv"), row.names = FALSE)
  od11 <- file.path(td, "out_cross"); dir.create(od11)
  msg11 <- errors_with(relnk(proj, cs, kp, out_dir = od11))
  expect_true(grepl("^S01: feedback mentions another student", msg11))
  expect_false(grepl("Rivera", msg11))
  expect_identical(length(list.files(od11, all.files = TRUE, no.. = TRUE)), 0L)
})

# ---- follow-up rulings -------------------------------------------------------------

test_that("a first-initial+last form that is a word in the word list is not a name", {
  cc <- anon_course(); proj <- cc$proj
  tdf <- cc$td
  dict <- file.path(tdf, "words"); writeLines(c("apple", "Shall", "zebra"), dict)
  gbf <- file.path(tdf, "gradebook_f.csv")
  writeLines(c(
    'Student,ID,SIS User ID,SIS Login ID,Root Account,Section',
    '    Points Possible,,,,,',
    '"Hall, Sam",3001,U1,XQ3001,x,90',
    '"Quill, Pat",3002,U2,XQ3002,x,90'), gbf)
  kpf <- file.path(tdf, "anon_key_f.csv"); fixture_key(gbf, kpf)
  kf <- read_key(kpf)
  tdict <- key_terms(kf, dict_path = dict)
  expect_false("shall" %in% tolower(tdict$term))
  expect_true("pquill" %in% tolower(tdict$term))
  expect_identical(redact_text("Sam Hall wrote", tdict)$text, "[name] wrote")
  expect_identical(redact_text("We shall ask Marshall.", tdict)$text, "We shall ask Marshall.")
  lff <- file.path(tdf, "t.md"); writeLines("We shall ask Marshall.", lff)
  expect_identical(nrow(find_leftovers(lff, tdict)), 0L)
  tnod <- key_terms(kf)
  expect_identical(tnod$code[tolower(tnod$term) == "shall"], "S01")
  expect_true("shall" %in% tolower(suppressMessages(
    key_terms(kf, dict_path = file.path(tdf, "nope")))$term))   # unreadable list keeps all
  # A .md submission keeps this end-to-end check independent of pandoc; the
  # redaction it checks is the same for a converted .docx.
  fd <- file.path(tdf, "Assign"); dir.create(fd)
  writeLines("Sam Hall: we shall see, said Marshall.", file.path(fd, "hallsam_3001_1_q.md"))
  anon(proj, fd, kpf, dict = dict)
  expect_identical(readLines(file.path(fd, "anon", "S01", "file1.md"))[1],
                   "[name]: we shall see, said Marshall.")
  expect_true("dict" %in% names(formals(relink)))
})

test_that("default_dict() names the system word list only when it exists", {
  d <- default_dict()
  if (is.null(d)) expect_null(d) else expect_true(file.exists(d))
  expect_identical(formals(anonymize)$dict, quote(default_dict()))
})

test_that("initial forms and one-word nicknames stay out of the substring pass", {
  cc <- anon_course()
  kn <- read_key(cc$kp); kn$nicknames[kn$code == "S01"] <- "Chris"
  tn <- key_terms(kn)
  lfn <- file.path(cc$td, "xmas.md"); writeLines("Merry christmas to all.", lfn)
  expect_identical(nrow(find_leftovers(lfn, tn)), 0L)
  writeLines("Thanks Chris.", lfn)
  expect_identical(find_leftovers(lfn, tn)$code, "S01")
  writeLines("the xxpquillxx token", lfn)
  expect_identical(nrow(find_leftovers(lfn, tn)), 0L)
  writeLines("the xxquillpatxx token", lfn)
  expect_identical(find_leftovers(lfn, tn)$code, "S01")
})

test_that("two-letter names keep the alphanumeric boundary", {
  te <- data.frame(term = "Ed", code = "S09", stringsAsFactors = FALSE)
  expect_identical(redact_text("commit 3f9ed41", te)$text, "commit 3f9ed41")
  expect_identical(redact_text("Thanks Ed.", te)$text, "Thanks [name].")
  expect_identical(redact_text("Umlauf2", data.frame(term = "Umlauf", code = "S01"))$text,
                   "[name]2")
})

# ---- multi-file submissions --------------------------------------------------------

test_that("assign_files numbers files in upload order and picks one target", {
  cc <- anon_course()
  kmf <- read_key(cc$kp)
  mk_subs <- function(ids, origs) {
    data.frame(file = paste0("f", seq_along(ids), ".docx"), prefix = "quillpat",
               late = FALSE, canvas_id = "1001", submission_id = ids,
               original = origs, stringsAsFactors = FALSE)
  }
  af1 <- assign_files(mk_subs("101", "Quiz 2.docx"), kmf)
  expect_identical(af1$anon_name, "file1")
  expect_identical(af1$target, TRUE)

  # Two specs and one non-spec that is not the latest upload: the non-spec
  # file is still the target.
  af3 <- assign_files(mk_subs(c("201", "202", "203"),
                              c("spec.docx", "Case analysis.docx", "spec_revised.docx")), kmf)
  expect_identical(af3$anon_name, c("file1", "file2", "file3"))
  expect_identical(af3$spec, c(TRUE, FALSE, TRUE))
  expect_identical(af3$anon_name[af3$target], "file2")
  expect_identical(sum(af3$target), 1L)

  af_allspec <- assign_files(mk_subs(c("301", "302"), c("spec.docx", "spec_v2.docx")), kmf)
  expect_identical(af_allspec$anon_name[af_allspec$target], "file2")

  msg_af_u <- errors_with(assign_files(
    data.frame(file = "a.docx", prefix = "nobodyx", late = FALSE,
               canvas_id = "4242", submission_id = "1", original = "q.docx",
               stringsAsFactors = FALSE), kmf))
  expect_false(is.na(msg_af_u))
  expect_false(grepl("4242", msg_af_u))
})

test_that("multi-file submissions anonymize in order and relink attaches only to the target", {
  skip_if_no("pandoc"); skip_if_no("zip")
  cc <- anon_course(); proj <- cc$proj; kp <- cc$kp; td <- cc$td
  mf <- file.path(td, "Multi"); dir.create(mf)
  mk_docx(file.path(mf, "quillpat_1001_6101_spec.docx"), "spec text")
  mk_docx(file.path(mf, "quillpat_1001_6102_Case analysis.docx"), "Pat Quill's analysis.")
  mk_docx(file.path(mf, "quillpat_1001_6103_spec_revised.docx"), "revised spec text")
  anon(proj, mf, kp)
  an_mf <- file.path(mf, "anon")
  expect_identical(sort(list.files(file.path(an_mf, "S01"), "\\.md$")),
                   c("file1.md", "file2.md", "file3.md"))
  man_mf <- utils::read.csv(file.path(an_mf, "manifest.csv"), colClasses = "character")
  man_mf <- man_mf[order(man_mf$file), ]
  expect_identical(man_mf$spec, c("TRUE", "FALSE", "TRUE"))
  expect_identical(man_mf$file[man_mf$target == "TRUE"], "file2")
  expect_false("original" %in% names(man_mf))

  dir.create(file.path(an_mf, "feedback"))
  writeLines(c("# Feedback: S01", "", "Nice analysis."), file.path(an_mf, "feedback", "S01.md"))
  utils::write.csv(data.frame(code = "S01", total = "10"), file.path(an_mf, "scores.csv"),
                   row.names = FALSE)
  omf <- file.path(td, "out_multi"); dir.create(omf)
  relnk(proj, mf, kp, out_dir = omf)
  expect_true(file.exists(file.path(omf, "feedback", "quillpat_1001_6102_Case analysis.docx")))
  zmf <- utils::unzip(file.path(omf, "feedback.zip"), list = TRUE)$Name
  expect_identical(sort(sub("^feedback/", "", zmf[zmf != "feedback/"])),
                   "quillpat_1001_6102_Case analysis.docx")
})

# ---- OpenDocument text and the document-type target rule ----------------------------

md_image_links <- function(md) {
  l <- readLines(md, warn = FALSE)
  m <- regmatches(l, regexpr("!\\[[^]]*\\]\\([^)]+\\)", l))
  sub("^!\\[[^]]*\\]\\(([^) ]+).*$", "\\1", m)
}

test_that("an .odt submission converts like a .docx, images extracted and links resolving", {
  skip_if_no("pandoc")
  cc <- anon_course(); proj <- cc$proj; kp <- cc$kp; td <- cc$td
  od <- file.path(td, "Odt"); dir.create(od)
  png_path <- mk_png(file.path(td, "fig.png"))
  mk_odt(file.path(od, "quillpat_1001_9551_hw.odt"),
         c("Figure by Pat Quill below.", "", paste0("![](", png_path, ")")))
  anon(proj, od, kp)
  md <- file.path(od, "anon", "S01", "file1.md")
  txt <- readLines(md, warn = FALSE)
  expect_true(any(grepl("Figure by [name] below.", txt, fixed = TRUE)))   # text survives, redacted
  expect_false(any(grepl("Quill", txt)))
  link <- md_image_links(md)
  expect_identical(length(link), 1L)
  expect_false(startsWith(link, "/"))
  expect_true(startsWith(link, "file1_media/"))
  expect_true(file.exists(file.path(dirname(md), link)))              # resolves beside the .md
  man <- utils::read.csv(file.path(od, "anon", "manifest.csv"), colClasses = "character")
  expect_identical(man$ext, "odt")
  expect_identical(man$target, "TRUE")
})

test_that("an .odt target gets a valid ODT under its exact name", {
  skip_if_no("pandoc")
  td <- withr::local_tempdir()
  target <- file.path(td, "quillpat_1001_5001_essay.odt")
  render_feedback(c("# Feedback: Pat Quill", "", "Good work, Pat Quill."), target, "S01")
  expect_true(file.exists(target))
  ents <- tryCatch(utils::unzip(target, list = TRUE)$Name, error = function(e) character())
  expect_true(all(c("mimetype", "content.xml") %in% ents))
  ex <- tryCatch(utils::unzip(target, files = "mimetype", exdir = file.path(td, "x")),
                 error = function(e) character())
  expect_identical(length(ex), 1L)
  if (length(ex)) expect_identical(raw_text(ex), "application/vnd.oasis.opendocument.text")
  back <- paste(suppressWarnings(system2("pandoc", c(shQuote(target), "-t", "plain"),
                                         stdout = TRUE, stderr = TRUE)), collapse = " ")
  expect_true(grepl("Pat Quill", back))
})

test_that("relink writes ODT feedback for an .odt submission under its exact name", {
  skip_if_no("pandoc"); skip_if_no("zip")
  cc <- anon_course(); proj <- cc$proj; kp <- cc$kp; td <- cc$td
  od <- file.path(td, "OdtRelink"); dir.create(od)
  mk_odt(file.path(od, "quillpat_1001_9561_Essay 1.odt"), "Pat Quill's essay.")
  anon(proj, od, kp)
  dir.create(file.path(od, "anon", "feedback"))
  writeLines(c("# Feedback: S01", "", "Good work, S01."), file.path(od, "anon", "feedback", "S01.md"))
  utils::write.csv(data.frame(code = "S01", total = "9"), file.path(od, "anon", "scores.csv"),
                   row.names = FALSE)
  oo <- file.path(td, "out_odt"); dir.create(oo)
  relnk(proj, od, kp, out_dir = oo)
  fb <- file.path(oo, "feedback", "quillpat_1001_9561_Essay 1.odt")
  expect_true(file.exists(fb))
  expect_true("content.xml" %in% tryCatch(utils::unzip(fb, list = TRUE)$Name,
                                          error = function(e) character()))
  back <- paste(system2("pandoc", c(shQuote(fb), "-t", "plain"), stdout = TRUE), collapse = " ")
  expect_true(grepl("Good work, Pat Quill", back))
})

test_that("render_feedback writes text for text targets and refuses any other type", {
  td <- withr::local_tempdir()
  for (e in c("md", "qmd", "Rmd", "txt")) {
    t <- file.path(td, paste0("quillpat_1001_5001_notes.", e))
    render_feedback("Good, Pat Quill.", t, "S01")
    expect_identical(readLines(t), "Good, Pat Quill.")
  }
  bad <- file.path(td, "bad"); dir.create(bad)
  for (e in c("R", "xlsx", "html", "pptx")) {
    t <- file.path(bad, paste0("quillpat_1001_5001_script.", e))
    msg <- errors_with(render_feedback("Good, Pat Quill.", t, "S01"))
    expect_false(is.na(msg))
    expect_true(grepl("^S01:", msg))                                   # names the code
    expect_true(grepl(paste0(".", tolower(e)), msg, fixed = TRUE))    # and the extension
    expect_false(grepl("quill|1001|5001|script", msg, ignore.case = TRUE))  # never the filename
  }
  expect_identical(length(list.files(bad, all.files = TRUE, no.. = TRUE)), 0L)   # nothing written
})

test_that("the target is the latest document-type file, never a script", {
  cc <- anon_course()
  k <- read_key(cc$kp)
  mk <- function(ids, origs) {
    data.frame(file = paste0("quillpat_1001_", ids, "_", origs), prefix = "quillpat",
               late = FALSE, canvas_id = "1001", submission_id = ids, original = origs,
               stringsAsFactors = FALSE)
  }
  a <- assign_files(mk(c("401", "402"), c("analysis.docx", "script.R")), k)
  expect_identical(a$original[a$target], "analysis.docx")
  expect_identical(a$anon_name, c("file1", "file2"))

  b <- assign_files(mk(c("501", "502", "503"),
                       c("spec.docx", "spec_v2.odt", "spec_code.R")), k)
  expect_identical(b$original[b$target], "spec_v2.odt")   # every file a spec: latest spec doc

  msg <- errors_with(assign_files(mk("601", "script.R"), k))
  expect_false(is.na(msg))
  expect_true(grepl("^S01:", msg))
  expect_false(grepl("quill|1001|601|script", msg, ignore.case = TRUE))
})

test_that("a .R file is still anonymized as text, and feedback goes to the document", {
  skip_if_no("zip")
  cc <- anon_course(); proj <- cc$proj; kp <- cc$kp; td <- cc$td
  rd <- file.path(td, "WithScript"); dir.create(rd)
  writeLines("Analysis by Pat Quill.", file.path(rd, "quillpat_1001_9571_analysis.md"))
  writeLines("# Pat Quill\nx <- 1", file.path(rd, "quillpat_1001_9572_script.R"))
  anon(proj, rd, kp)
  expect_identical(readLines(file.path(rd, "anon", "S01", "file2.md")), c("# [name]", "x <- 1"))
  man <- utils::read.csv(file.path(rd, "anon", "manifest.csv"), colClasses = "character")
  expect_identical(man$file[man$target == "TRUE"], "file1")
  dir.create(file.path(rd, "anon", "feedback"))
  writeLines("Good, S01.", file.path(rd, "anon", "feedback", "S01.md"))
  utils::write.csv(data.frame(code = "S01", total = "9"), file.path(rd, "anon", "scores.csv"),
                   row.names = FALSE)
  orr <- file.path(td, "out_script"); dir.create(orr)
  relnk(proj, rd, kp, out_dir = orr)
  expect_identical(list.files(file.path(orr, "feedback")), "quillpat_1001_9571_analysis.md")
  expect_identical(readLines(file.path(orr, "feedback", "quillpat_1001_9571_analysis.md")),
                   "Good, Pat Quill.")
})

# ---- one key per grading run (1.2.2) --------------------------------------------

# The mapping a key holds, as "canvas_id=code" pairs in id order.
key_mapping <- function(kp) {
  k <- read_key(kp)
  k <- k[order(as.numeric(k$canvas_id)), ]
  paste(k$canvas_id, k$code, sep = "=", collapse = " ")
}

test_that("each run's codes are a fresh shuffle of S01..Snn", {
  cc <- anon_course(nickname = FALSE)
  maps <- vapply(1:10, function(i) {
    a <- file.path("semester", paste0("Run", i))
    dir.create(file.path(cc$proj, a), recursive = TRUE)
    k <- quiet(anon_key(cc$proj, "gradebook.csv", a))
    expect_identical(sort(k$code), c("S01", "S02", "S03"))   # a permutation, every run
    key_mapping(file.path(cc$proj, a, "anon_key.csv"))
  }, "")
  expect_gt(length(unique(maps)), 1L)   # 10 builds of 3 students: all equal has odds 6^-9
})

test_that("a key records its run, and every function refuses another run's key", {
  cc <- anon_course(nickname = FALSE)
  a <- file.path(cc$proj, "semester", "A"); b <- file.path(cc$proj, "semester", "B")
  dir.create(a, recursive = TRUE); dir.create(b, recursive = TRUE)
  writeLines("Pat Quill wrote this.", file.path(a, "quillpat_1001_5001_essay.md"))
  writeLines("Pat Quill wrote this.", file.path(b, "quillpat_1001_5002_essay.md"))
  quiet(anon_key(cc$proj, "gradebook.csv", "semester/A"))
  ka <- file.path(a, "anon_key.csv")
  expect_identical(unique(read_key(ka)$run), "semester/A")

  msg <- errors_with(anonymize(cc$proj, "semester/B", key = "semester/A/anon_key.csv",
                               dict = NULL))
  expect_true(grepl("semester/A", msg) && grepl("semester/B", msg))
  expect_false(dir.exists(file.path(b, "anon")))   # refused before anything was written
  msg <- errors_with(anonymize(cc$proj, "semester/B", dict = NULL))
  expect_true(grepl("no key", msg))                # B has no key of its own yet

  file.copy(ka, file.path(b, "anon_key.csv"))
  before <- raw_text(file.path(b, "anon_key.csv"))
  expect_true(grepl("run", errors_with(quiet(anon_key(cc$proj, "gradebook.csv", "semester/B")))))
  expect_identical(raw_text(file.path(b, "anon_key.csv")), before)   # left as it was
  expect_true(grepl("semester/A", errors_with(anonymize(cc$proj, "semester/B", dict = NULL))))
  expect_true(grepl("semester/A", errors_with(relink(cc$proj, "semester/B", dict = NULL))))
})

test_that("a same-run rebuild keeps every row and code and adds new students at new codes", {
  cc <- anon_course(nickname = FALSE)
  dir.create(file.path(cc$proj, "Quiz"))
  quiet(anon_key(cc$proj, "gradebook.csv", "Quiz"))
  kp <- file.path(cc$proj, "Quiz", "anon_key.csv")
  k1 <- read_key(kp); k1$nicknames[k1$canvas_id == "1002"] <- "Mo"
  utils::write.csv(k1, kp, row.names = FALSE)
  writeLines(c(readLines(file.path(cc$td, "gradebook.csv")),
               '"Tern, Avery",1004,U4,XQ1004,x,90',
               '"Vale, Robin",1005,U5,XQ1005,x,90'),
             file.path(cc$td, "gradebook2.csv"))
  k2 <- quiet(anon_key(cc$proj, "gradebook2.csv", "Quiz"))
  expect_identical(as.list(k2[1:3, ]), as.list(k1))                                 # old rows byte for byte
  expect_identical(sort(k2$code[4:5]), c("S04", "S05"))             # new students, next free codes
  expect_identical(unique(k2$run), "Quiz")
})

test_that("nicknames from the term nicknames file reach the key and are redacted", {
  skip_if_no("tesseract")
  cc <- anon_course(nickname = FALSE)
  ad <- file.path(cc$proj, "semester", "Essay"); dir.create(ad, recursive = TRUE)
  writeLines(c("canvas_id,nicknames", "1002,Mo; Morgs", "4242,Ghost"),
             file.path(cc$proj, "semester", "nicknames.csv"))
  writeLines("Morgs and Mo wrote this.", file.path(ad, "riveramorgan_1002_5001_essay.md"))
  out <- capture.output(k <- anon_key(cc$proj, "gradebook.csv", "semester/Essay",
                                      nicknames = "semester/nicknames.csv"))
  expect_identical(split_list(k$nicknames[k$canvas_id == "1002"]), c("Mo", "Morgs"))
  expect_identical(k$nicknames[k$canvas_id != "1002"], c("", ""))
  expect_false(any(grepl("Mo|Morgs|Ghost|1002|4242", out)))
  code <- k$code[k$canvas_id == "1002"]
  quiet(anonymize(cc$proj, "semester/Essay", dict = NULL))
  expect_identical(readLines(file.path(ad, "anon", code, "file1.md")),
                   "[name] and [name] wrote this.")

  writeLines("id,nick\n1002,x", file.path(cc$proj, "semester", "bad.csv"))
  expect_true(grepl("canvas_id", errors_with(quiet(anon_key(
    cc$proj, "gradebook.csv", "semester/Essay", nicknames = "semester/bad.csv")))))
})

test_that("anon_forget() refuses before relink has finished, then deletes the key", {
  skip_if_no("zip")
  cc <- anon_course()
  ad <- file.path(cc$proj, "semester", "Essay"); dir.create(ad, recursive = TRUE)
  writeLines("Pat Quill wrote this.", file.path(ad, "quillpat_1001_5001_essay.md"))
  anon(cc$proj, "semester/Essay", cc$kp)
  kp <- file.path(ad, "anon_key.csv")
  msg <- errors_with(quiet(anon_forget(cc$proj, "semester/Essay")))
  expect_true(grepl("relink", msg))
  expect_true(file.exists(kp))

  dir.create(file.path(ad, "anon", "feedback"))
  writeLines("Good, S01.", file.path(ad, "anon", "feedback", "S01.md"))
  utils::write.csv(data.frame(code = "S01", total = "9"), file.path(ad, "anon", "scores.csv"),
                   row.names = FALSE)
  quiet(relink(cc$proj, "semester/Essay", dict = NULL))
  out <- capture.output(anon_forget(cc$proj, "semester/Essay"))
  expect_false(file.exists(kp))
  expect_true(grepl("^anon_forget: deleted ", out[1]))
  expect_false(any(grepl("Quill|1001|5001", out)))
  expect_true(grepl("no key", errors_with(quiet(anon_forget(cc$proj, "semester/Essay")))))
})

test_that("a session seed does not repeat the shuffle, and the caller's RNG state is kept", {
  cc <- anon_course(nickname = FALSE)
  maps <- vapply(1:10, function(i) {
    a <- file.path("semester", paste0("Seeded", i))
    dir.create(file.path(cc$proj, a), recursive = TRUE)
    set.seed(730)
    quiet(anon_key(cc$proj, "gradebook.csv", a))
    key_mapping(file.path(cc$proj, a, "anon_key.csv"))
  }, "")
  expect_gt(length(unique(maps)), 1L)

  dir.create(file.path(cc$proj, "semester", "State"), recursive = TRUE)
  set.seed(1); before <- .Random.seed
  quiet(anon_key(cc$proj, "gradebook.csv", "semester/State"))
  expect_identical(.Random.seed, before)
})

# ---- de-identification hardening ---------------------------------------------------

# An assignment folder semester/A1 under proj with the fixture key staged as
# its own, so S01 is Quill and S02 is Rivera.
a1_assignment <- function(cc) {
  a <- file.path(cc$proj, "semester", "A1"); dir.create(a, recursive = TRUE)
  stage_key(cc$proj, "semester/A1", cc$kp)
  a
}

test_that("anonymize stops before writing anything when tesseract is missing", {
  cc <- anon_course(); a <- a1_assignment(cc)
  writeLines("Pat Quill wrote this.", file.path(a, "quillpat_1001_5001_essay.md"))
  local_mocked_bindings(tesseract_path = function() "")
  expect_error(quiet(anonymize(cc$proj, "semester/A1", dict = NULL)), "brew install tesseract")
  expect_false(dir.exists(file.path(a, "anon")))
  expect_false(file.exists(file.path(a, "deidentification_log.md")))
})

test_that("the coded folder carries no lateness or timing", {
  skip_if_no("tesseract")
  cc <- anon_course(); a <- a1_assignment(cc)
  writeLines("Pat Quill wrote this late.", file.path(a, "quillpat_LATE_1001_5001_x.md"))
  writeLines("Morgan Rivera was on time.", file.path(a, "riveramorgan_1002_5002_y.md"))
  res <- quiet(anonymize(cc$proj, "semester/A1", dict = NULL))
  man <- utils::read.csv(file.path(a, "anon", "manifest.csv"))
  expect_false("late" %in% names(man))
  paths <- c(file.path(a, "anon"),
             list.files(file.path(a, "anon"), recursive = TRUE, full.names = TRUE,
                        include.dirs = TRUE, all.files = TRUE))
  info <- file.info(paths)
  expect_equal(length(unique(as.numeric(info$mtime))), 1L)
})

test_that("anonymize redacts fixed patterns and logs counts, with no names in the log", {
  skip_if_no("tesseract")
  cc <- anon_course(); a <- a1_assignment(cc)
  writeLines("Reach me at 715-555-0142. Pat Quill", file.path(a, "quillpat_1001_5001_x.md"))
  res <- quiet(anonymize(cc$proj, "semester/A1", dict = NULL))
  txt <- readLines(file.path(a, "anon", "S01", "file1.md"))
  expect_true(any(grepl("[PHONE]", txt, fixed = TRUE)))
  expect_identical(res$patterns[["PHONE"]], 1L)
  expect_identical(res$images$scanned, 0L)
  log <- readLines(file.path(a, "deidentification_log.md"))
  expect_true(any(grepl("^## anonymize, ", log)))
  expect_true(any(grepl("fixed patterns: PHONE 1", log, fixed = TRUE)))
  expect_false(any(grepl("Quill|715-555|1001|5001|quillpat|XQ1001", log, ignore.case = TRUE)))
  expect_false(file.exists(file.path(a, "anon", "deidentification_log.md")))
})

test_that("a flagged image holds anon/ at NOT_READY until decided, then releases", {
  skip_if_no("tesseract"); skip_if_no("pandoc")
  cc <- anon_course(); a <- a1_assignment(cc)
  png_path <- file.path(cc$td, "name.png")
  img <- magick::image_annotate(magick::image_blank(600, 120, "white"), "Pat Quill",
                                size = 40, location = "+10+30", color = "black")
  magick::image_write(img, png_path, format = "png")
  mk_docx(file.path(a, "quillpat_1001_5001_Essay.docx"),
          c("Figure below.", "", paste0("![](", png_path, ")")))
  msgs <- character()
  err <- withCallingHandlers(
    errors_with(quiet(anonymize(cc$proj, "semester/A1", dict = NULL))),
    message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") })
  expect_true(grepl("anon_images.csv", err, fixed = TRUE))
  expect_true(file.exists(file.path(a, "anon", "NOT_READY")))
  expect_false(any(grepl("Quill|1001|5001|quillpat|Essay", c(err, msgs), ignore.case = TRUE)))
  man <- utils::read.csv(file.path(a, "anon", "manifest.csv"), colClasses = "character")
  an <- normalizePath(file.path(a, "anon"))
  flagged_rel <- substring(normalizePath(image_files(file.path(an, man$code[1]))),
                           nchar(an) + 2L)
  expect_identical(length(flagged_rel), 1L)
  expect_true(startsWith(flagged_rel, paste0(man$code[1], "/file1_media/media/")))
  expect_true(any(grepl(flagged_rel, msgs, fixed = TRUE)))   # the message names the anon/ path
  utils::write.csv(data.frame(image = flagged_rel, decision = "remove"),
                   file.path(a, "anon_images.csv"), row.names = FALSE)
  out <- capture.output(res <- anonymize(cc$proj, "semester/A1", dict = NULL))
  expect_false(any(grepl("ignored", out)))   # the decisions file and log are not strays
  expect_false(file.exists(file.path(a, "anon", "NOT_READY")))
  expect_false(file.exists(file.path(a, "anon", flagged_rel)))
  expect_identical(res$images$removed, 1L)
  md <- readLines(file.path(a, "anon", man$code[1], "file1.md"))
  expect_true(any(grepl("[image removed]", md, fixed = TRUE)))
  expect_false(file.exists(file.path(a, "anon", "anon_images.csv")))
})

test_that("relink and anon_forget append to the log", {
  skip_if_no("tesseract"); skip_if_no("zip")
  cc <- anon_course(); a <- a1_assignment(cc)
  writeLines("Pat Quill wrote this.", file.path(a, "quillpat_1001_5001_essay.md"))
  quiet(anonymize(cc$proj, "semester/A1", dict = NULL))
  dir.create(file.path(a, "anon", "feedback"))
  writeLines("Good, S01.", file.path(a, "anon", "feedback", "S01.md"))
  utils::write.csv(data.frame(code = "S01", total = "9"), file.path(a, "anon", "scores.csv"),
                   row.names = FALSE)
  quiet(relink(cc$proj, "semester/A1", dict = NULL))
  quiet(anon_forget(cc$proj, "semester/A1"))
  log <- readLines(file.path(a, "deidentification_log.md"))
  expect_true(any(grepl("^## anonymize, ", log)))
  expect_true(any(grepl("^## relink, ", log)))
  expect_true(any(grepl("^## anon_forget, ", log)))
  expect_false(any(grepl("Quill|1001|5001|quillpat|XQ1001|essay", log, ignore.case = TRUE)))
})

test_that("the manifest is sorted by code and file, never in download order", {
  skip_if_no("tesseract")
  cc <- anon_course(); a <- a1_assignment(cc)
  # Codes that sort differently from the surnames: Quill S03, Rivera S01, Stone S02.
  kp <- file.path(a, "anon_key.csv"); k <- read_key(kp)
  k$code <- c(S01 = "S03", S02 = "S01", S03 = "S02")[k$code]
  utils::write.csv(k, kp, row.names = FALSE)
  writeLines("one", file.path(a, "quillpat_1001_5001_x.md"))
  writeLines("two", file.path(a, "quillpat_1001_5004_y.md"))
  writeLines("three", file.path(a, "riveramorgan_1002_5002_x.md"))
  writeLines("four", file.path(a, "stonepat_1003_5003_x.md"))
  quiet(anonymize(cc$proj, "semester/A1", dict = NULL))
  man <- utils::read.csv(file.path(a, "anon", "manifest.csv"), colClasses = "character")
  expect_identical(man$code, sort(man$code))
  expect_identical(man$code, c("S01", "S02", "S03", "S03"))
  expect_identical(man$file, c("file1", "file1", "file1", "file2"))
})

test_that("a log write failure leaves anon/ at NOT_READY", {
  skip_if_no("tesseract")
  cc <- anon_course(); a <- a1_assignment(cc)
  writeLines("Pat Quill wrote this.", file.path(a, "quillpat_1001_5001_essay.md"))
  local_mocked_bindings(append_log = function(...) stop("disk full", call. = FALSE))
  expect_error(quiet(anonymize(cc$proj, "semester/A1", dict = NULL)), "disk full")
  expect_true(file.exists(file.path(a, "anon", "NOT_READY")))
})

# ---- protected phrases (anon_keep.txt) -----------------------------------------

test_that("anon_keep.txt protects the instructor's phrase, not a student's same first name", {
  skip_if_no("tesseract")
  cc <- anon_course(); a <- a1_assignment(cc)
  # The invented instructor shares the first name of the student Morgan Rivera.
  writeLines(c("# instructor", "Morgan J. Ellery"), file.path(cc$proj, "anon_keep.txt"))
  writeLines("Pat Quill, for Dr. Morgan J. Ellery. Thanks Morgan for the data.",
             file.path(a, "quillpat_1001_5001_x.md"))
  writeLines("Morgan Rivera wrote this for morgan j.  Ellery. Signed, Morgan.",
             file.path(a, "riveramorgan_1002_5002_x.md"))
  out <- capture.output(res <- anonymize(cc$proj, "semester/A1", dict = NULL))
  s1 <- readLines(file.path(a, "anon", "S01", "file1.md"))
  s2 <- readLines(file.path(a, "anon", "S02", "file1.md"))
  expect_identical(s1, "[name], for Dr. Morgan J. Ellery. Thanks [name] for the data.")
  expect_identical(s2, "[name] wrote this for morgan j.  Ellery. Signed, [name].")
  expect_equal(res$protected, 2L)
  log <- readLines(file.path(a, "deidentification_log.md"))
  expect_true(any(grepl("protected phrases kept: 2", log, fixed = TRUE)))
  expect_false(any(grepl("Ellery", log, ignore.case = TRUE)))
  expect_false(any(grepl("Ellery", out, ignore.case = TRUE)))
  expect_true(any(grepl("protected phrases kept: 2", out, fixed = TRUE)))
  expect_false(file.exists(file.path(a, "anon", "NOT_READY")))
})

test_that("a bad anon_keep.txt stops the run before anything is written", {
  cc <- anon_course(); a <- a1_assignment(cc)
  writeLines(c("Morgan J. Ellery", "Morgan"), file.path(cc$proj, "anon_keep.txt"))
  writeLines("Pat Quill wrote this.", file.path(a, "quillpat_1001_5001_essay.md"))
  local_mocked_bindings(tesseract_path = function() "/usr/bin/tesseract")
  msg <- errors_with(quiet(anonymize(cc$proj, "semester/A1", dict = NULL)))
  expect_match(msg, "line 2")
  expect_false(grepl("Morgan", msg))
  expect_false(dir.exists(file.path(a, "anon")))
  expect_false(file.exists(file.path(a, "deidentification_log.md")))
})

test_that("a protected phrase split across two lines of a hard-wrapped file survives whole", {
  skip_if_no("tesseract")
  cc <- anon_course(); a <- a1_assignment(cc)
  writeLines("Morgan J. Ellery", file.path(cc$proj, "anon_keep.txt"))
  writeLines(c("Pat Quill, written for Dr. Morgan J.", "Ellery. Thanks Morgan", "", "for the data."),
             file.path(a, "quillpat_1001_5001_x.md"))
  res <- quiet(anonymize(cc$proj, "semester/A1", dict = NULL))
  s1 <- readLines(file.path(a, "anon", "S01", "file1.md"))
  expect_identical(s1, c("[name], written for Dr. Morgan J.", "Ellery. Thanks [name]", "",
                         "for the data."))
  expect_equal(res$protected, 1L)
  expect_equal(res$replacements, 2L)
})

test_that("an anon_keep.txt phrase holding a student's full name stops with nothing written", {
  cc <- anon_course(); a <- a1_assignment(cc)
  writeLines(c("# staff", "Morgan J. Ellery", "TA Morgan Rivera"),
             file.path(cc$proj, "anon_keep.txt"))
  writeLines("Pat Quill wrote this.", file.path(a, "quillpat_1001_5001_essay.md"))
  local_mocked_bindings(tesseract_path = function() "/usr/bin/tesseract")
  msg <- errors_with(quiet(anonymize(cc$proj, "semester/A1", dict = NULL)))
  expect_match(msg, "anon_keep.txt line 3 contains a student's name or id")
  expect_false(grepl("Morgan|Rivera", msg))
  expect_false(dir.exists(file.path(a, "anon")))
  expect_false(file.exists(file.path(a, "deidentification_log.md")))
})
