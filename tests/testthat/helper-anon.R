# Fixtures for the anonymized-grading and gradebook-import tests. Every name,
# id, login and address here is invented.

# A gradebook export shaped like Canvas's: a points row and the test student.
fake_gradebook <- function(dir) {
  p <- file.path(dir, "gradebook.csv")
  writeLines(c(
    'Student,ID,SIS User ID,SIS Login ID,Root Account,Section',
    '    Points Possible,,,,,',
    '"Quill, Pat",1001,U1,XQ1001,x,90',
    '"Rivera, Morgan",1002,U2,XQ1002,x,90',
    '"Stone, Pat",1003,U3,XQ1003,x,90',
    '"Student, Test",9999,,,x,90'), p)
  p
}

# A course root holding the gradebook and a built key. proj and the working
# folder are the same temporary directory, removed when the calling test ends.
# With nickname = TRUE the second student carries the hand-added nickname "Mo",
# the state every test after the key tests ran against when these were a
# single script.
anon_course <- function(nickname = TRUE, env = parent.frame()) {
  td <- withr::local_tempdir("anon_", .local_envir = env)
  td <- normalizePath(td)
  kp <- file.path(td, "anon_key.csv")
  invisible(capture.output(build_key(fake_gradebook(td), kp)))
  if (nickname) {
    k <- read_key(kp); k$nicknames[2] <- "Mo"
    utils::write.csv(k, kp, row.names = FALSE)
  }
  list(proj = td, td = td, kp = kp)
}

quiet <- function(expr) { invisible(capture.output(r <- force(expr))); r }

errors_with <- function(expr) {
  tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
}

# The tests pass dict = NULL unless a test is about the word list, so a run
# does not depend on which system word list a machine has.
anon <- function(proj, a, k, ..., dict = NULL) quiet(anonymize(proj, a, k, ..., dict = dict))
relnk <- function(proj, a, k, ...) quiet(relink(proj, a, k, ..., dict = NULL))

mk_docx <- function(path, lines) {
  s <- tempfile(fileext = ".md"); on.exit(unlink(s))
  writeLines(lines, s)
  system2("pandoc", c(shQuote(s), "-o", shQuote(path)))
}

raw_text <- function(p) rawToChar(readBin(p, "raw", file.info(p)$size))
