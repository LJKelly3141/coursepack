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
  k <- quiet(build_key(fake_gradebook(cc$td), cc$kp))
  expect_identical(nrow(k), 3L)                       # points row and test student dropped
  expect_identical(k$code, c("S01", "S02", "S03"))   # codes in id order
  expect_identical(k$name[1], "Pat Quill")
  expect_identical(k$file_prefix[1], "quillpat")
  expect_true("Quill, Pat" %in% split_list(k$name_forms[1]))

  k2 <- read_key(cc$kp); k2$nicknames[2] <- "Mo"; utils::write.csv(k2, cc$kp, row.names = FALSE)
  k3 <- quiet(build_key(fake_gradebook(cc$td), cc$kp))
  expect_identical(k3$nicknames[2], "Mo")   # rebuild keeps a hand-added nickname
  expect_identical(nrow(k3), 3L)            # rebuild adds no duplicate rows

  tt <- key_terms(read_key(cc$kp))
  expect_true(nchar(tt$term[1]) >= nchar(tt$term[nrow(tt)]))   # longest first
  expect_identical(tt$code[tolower(tt$term) == "pat"], "SXX")    # shared first name
  expect_identical(tt$code[tt$term == "Mo"], "S02")              # nickname present
})

test_that("anon_key() resolves paths against proj and prints no name", {
  cc <- anon_course(nickname = FALSE)
  out <- capture.output(k <- anon_key(cc$proj, "gradebook.csv", "semester/key.csv"))
  expect_true(file.exists(file.path(cc$proj, "semester", "key.csv")))
  expect_identical(k$code, c("S01", "S02", "S03"))
  expect_false(any(grepl("Quill|Rivera|Stone|100[123]|XQ", out)))
  expect_true(any(grepl("coursepack", out)))
  expect_error(anon_key(file.path(cc$proj, "nope"), "gradebook.csv"), "not a directory")
})

# ---- redaction ---------------------------------------------------------------

test_that("redaction replaces every name form whole-word with the right code", {
  cc <- anon_course()
  terms <- key_terms(read_key(cc$kp))
  r <- redact_text("Written by Pat Quill. Quill's plot; QUILL again.", terms)
  expect_true(grepl("S01\\.", r$text))                          # full name becomes one code
  expect_false(grepl("quill", r$text, ignore.case = TRUE))      # possessive and upper case
  expect_identical(redact_text("Thanks, Pat.", terms)$text, "Thanks, SXX.")
  expect_true(r$n >= 3L)                                        # counts replacements
  expect_identical(redact_text("file quillpat_1001_5001.docx", terms)$text,
                   "file S01_S01_5001.docx")                    # underscore-glued prefix
  expect_identical(redact_text("I worked with Morgan Rivera.", terms)$text,
                   "I worked with S02.")                        # classmate gets their code
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
  expect_identical(man$late[man$code == "S02"], "TRUE")
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
  cc <- anon_course()
  ad <- file.path(cc$proj, "semester", "Essay"); dir.create(ad, recursive = TRUE)
  writeLines("Pat Quill wrote this.", file.path(ad, "quillpat_1001_5001_essay.md"))
  out <- capture.output(anonymize(cc$proj, "semester/Essay", "anon_key.csv", dict = NULL))
  expect_identical(readLines(file.path(ad, "anon", "S01", "file1.md")), "S01 wrote this.")
  expect_true(any(grepl("coursepack", out)))
  expect_false(any(grepl("Quill|1001|5001|essay", out)))
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
  anon(cc$proj, "semester/Essay", "anon_key.csv")
  dir.create(file.path(ad, "anon", "feedback"))
  writeLines("Good, S01.", file.path(ad, "anon", "feedback", "S01.md"))
  utils::write.csv(data.frame(code = "S01", total = "9"), file.path(ad, "anon", "scores.csv"),
                   row.names = FALSE)
  out <- capture.output(relink(cc$proj, "semester/Essay", "anon_key.csv", dict = NULL))
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
  quiet(build_key(gb1, kp1))
  terms1 <- key_terms(read_key(kp1))
  f1 <- function(s) redact_text(s, terms1)$text
  expect_identical(f1("by AshleyUmlauf today"), "by S01 today")
  expect_identical(f1("umlaufashley.R"), "S01.R")
  expect_identical(f1("user aumlauf here"), "user S01 here")
  expect_identical(f1("Umlauf2 draft"), "S012 draft")
  expect_identical(f1("x_umlauf_y"), "x_S01_y")
  expect_identical(f1("Jos\u00e9 N\u00fa\u00f1ez wrote this"), "S02 wrote this")
  expect_identical(f1("Jose Nunez wrote this"), "S02 wrote this")
  expect_identical(f1("josenunez"), "S02")
  expect_identical(f1("XQ2001"), "S01")         # login still redacted
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
  skip_if_no("pandoc"); skip_if_no("zip")
  cc <- anon_course(); proj <- cc$proj; kp <- cc$kp; td <- cc$td
  ig <- file.path(td, "Ignored"); dir.create(ig)
  mk_docx(file.path(ig, "quillpat_1001_9901_q.docx"), "a")
  out_ign <- capture.output(anonymize(proj, ig, kp, dict = NULL))
  expect_false(any(grepl("ignored", out_ign)))
  writeLines("x", file.path(ig, "notes.txt"))
  writeLines("x", file.path(ig, "other.csv"))
  out_ign2 <- tryCatch(capture.output(anonymize(proj, ig, kp, dict = NULL)),
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
  out_nf <- capture.output(relink(proj, nf, kp, out_dir = onf, dict = NULL))
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
  writeLines("x", file.path(cf, "quillpat_1001_9701_hw.xlsx"))
  msg9 <- errors_with(anon(proj, cf, kp))
  expect_true(startsWith(msg9, "S01 (file1): unsupported submission type: .xlsx"))
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
  kpf <- file.path(tdf, "anon_key_f.csv"); quiet(build_key(gbf, kpf))
  kf <- read_key(kpf)
  tdict <- key_terms(kf, dict_path = dict)
  expect_false("shall" %in% tolower(tdict$term))
  expect_true("pquill" %in% tolower(tdict$term))
  expect_identical(redact_text("Sam Hall wrote", tdict)$text, "S01 wrote")
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
                   "S01: we shall see, said Marshall.")
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
  expect_identical(redact_text("Thanks Ed.", te)$text, "Thanks S09.")
  expect_identical(redact_text("Umlauf2", data.frame(term = "Umlauf", code = "S01"))$text,
                   "S012")
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
