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

# A course root holding the gradebook and a fixture key. proj and the working
# folder are the same temporary directory, removed when the calling test ends.
# With nickname = TRUE the second student carries the hand-added nickname "Mo",
# the state every test after the key tests ran against when these were a
# single script.
#
# The fixture key is built with the code shuffle switched off, so S01, S02 and
# S03 are Quill, Rivera and Stone and the redaction tests can name a code. It
# records the placeholder run "fixture"; stage_key() copies it into an
# assignment folder under that assignment's own run. The shuffle itself is
# tested on its own, against the real anon_key().
anon_course <- function(nickname = TRUE, env = parent.frame()) {
  td <- withr::local_tempdir("anon_", .local_envir = env)
  td <- normalizePath(td)
  kp <- file.path(td, "anon_key.csv")
  fixture_key(fake_gradebook(td), kp)
  if (nickname) {
    k <- read_key(kp); k$nicknames[2] <- "Mo"
    utils::write.csv(k, kp, row.names = FALSE)
  }
  list(proj = td, td = td, kp = kp)
}

# build_key() with codes in Canvas id order, for fixtures that name a code.
fixture_key <- function(gradebook, key_path, run = "fixture") {
  testthat::with_mocked_bindings(
    quiet(build_key(gradebook, key_path, run)),
    shuffle = function(x) x)
}

# Copy a fixture key into <a>/anon_key.csv under a's own run, the key
# anonymize() and relink() read by default.
stage_key <- function(proj, a, k) {
  ad <- proj_path(proj, a)
  key <- read_key(k)
  key$run <- run_id(proj, ad)
  utils::write.csv(key, file.path(ad, "anon_key.csv"), row.names = FALSE)
  file.path(ad, "anon_key.csv")
}

quiet <- function(expr) { invisible(capture.output(r <- force(expr))); r }

errors_with <- function(expr) {
  tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
}

# The tests pass dict = NULL unless a test is about the word list, so a run
# does not depend on which system word list a machine has. Both stage the
# given fixture key as the assignment's own key, then use the default.
# anonymize() needs tesseract to check image text, so anon() skips without it.
anon <- function(proj, a, k, ..., dict = NULL) {
  skip_if_no("tesseract")
  stage_key(proj, a, k)
  quiet(anonymize(proj, a, ..., dict = dict))
}
relnk <- function(proj, a, k, ...) {
  stage_key(proj, a, k)
  quiet(relink(proj, a, ..., dict = NULL))
}

mk_docx <- function(path, lines) {
  s <- tempfile(fileext = ".md"); on.exit(unlink(s))
  writeLines(lines, s)
  system2("pandoc", c(shQuote(s), "-o", shQuote(path)))
}

# pandoc picks the writer from the output extension, so the same builder makes
# an OpenDocument text file when the path ends in .odt.
mk_odt <- mk_docx

# A small PNG to embed in a built document.
mk_png <- function(path) {
  grDevices::png(path, width = 50, height = 50)
  grid::grid.rect(gp = grid::gpar(fill = "grey"))
  invisible(grDevices::dev.off())
  path
}

raw_text <- function(p) rawToChar(readBin(p, "raw", file.info(p)$size))
