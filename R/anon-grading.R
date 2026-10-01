# anonymize() and relink(): grading without student identity.
#
# The instructor's machine is the only place identity is handled. anonymize()
# turns one assignment's Canvas downloads into coded plain text under anon/,
# the grader reads only anon/ and writes coded feedback and scores beside it,
# and relink() puts the names back and names each feedback file exactly like
# the submission it answers, so the Canvas upload works as it always has.
#
# Every message names a code (S07), a position (file2) or a count. None names
# a student, an id or an original filename, because these messages end up in
# terminal scrollback and logs that are not the key.

list_submissions <- function(assignment_dir) {
  f <- list.files(assignment_dir, all.files = FALSE, no.. = TRUE)
  f <- f[!dir.exists(file.path(assignment_dir, f))]
  parsed <- lapply(f, parse_canvas_filename)
  keep <- !vapply(parsed, is.null, logical(1))
  if (!any(keep)) stop("no Canvas submission files found in ", assignment_dir, call. = FALSE)
  p <- parsed[keep]
  out <- data.frame(file = f[keep],
                    prefix = vapply(p, `[[`, "", "prefix"),
                    late = vapply(p, `[[`, TRUE, "late"),
                    canvas_id = vapply(p, `[[`, "", "canvas_id"),
                    submission_id = vapply(p, `[[`, "", "submission_id"),
                    original = vapply(p, `[[`, "", "original"),
                    stringsAsFactors = FALSE)
  attr(out, "ignored") <- sum(!keep)
  out
}

# A student may submit any number of files. For each student, files are
# ordered by upload (submission_id) and numbered file1, file2, ... in that
# order. "spec" must start a word: "Perspective analysis" is not a spec.
# Exactly one file per student is the target, the file feedback attaches to.
# It must be a document type, one relink() can write back under the same name
# as a valid file of that type: the latest-uploaded non-spec document, or, if
# every document is a spec, the latest document. A student with no document
# at all stops the run, because there is nothing to attach feedback to.
assign_files <- function(subs, key) {
  unknown <- !(subs$canvas_id %in% key$canvas_id)
  if (any(unknown)) {
    stop(sum(unknown), " submission file(s) belong to a student not in the key; ",
         "remove the file(s) or rebuild the key from a fresh gradebook export",
         call. = FALSE)
  }
  subs$code <- key$code[match(subs$canvas_id, key$canvas_id)]
  subs$spec <- grepl("(^|[^a-z])spec", subs$original, ignore.case = TRUE, perl = TRUE)
  doc <- tolower(tools::file_ext(subs$original)) %in% DOCUMENT_EXTS
  subs$position <- NA_integer_
  subs$target <- FALSE
  for (cd in unique(subs$code)) {
    i <- which(subs$code == cd)
    ord <- i[order(as.numeric(subs$submission_id[i]))]
    subs$position[ord] <- seq_along(ord)
    docs <- ord[doc[ord]]
    if (!length(docs)) {
      stop(cd, ": no document file (", paste(DOCUMENT_EXTS, collapse = ", "),
           ") to attach feedback to", call. = FALSE)
    }
    non_spec <- docs[!subs$spec[docs]]
    tgt <- if (length(non_spec)) non_spec[length(non_spec)] else docs[length(docs)]
    subs$target[tgt] <- TRUE
  }
  subs$anon_name <- paste0("file", subs$position)
  subs
}

#' Anonymize one assignment's Canvas downloads for grading
#'
#' Turn a folder of Canvas submission downloads into coded plain text that a
#' grader, a person or an agent, can read without learning who wrote it. The
#' grader is given `anon_dir` and the rubric and nothing else.
#'
#' Every file whose name has Canvas's bulk-download shape,
#' `prefix[_LATE]_canvasid_submissionid_original`, is converted to text: a
#' `.docx` or `.odt` through pandoc with tracked changes accepted and its
#' images extracted, a `.pdf` through `pdftotext -layout` with its images
#' through `pdfimages`, and `.md`, `.qmd`, `.Rmd`, `.R` and `.txt` copied as
#' text.
#' Converting is what removes document metadata such as an author field. Any
#' other type stops the run, naming the code and file position. Files without
#' the Canvas shape are skipped and counted, never named.
#'
#' A student may submit any number of files. Each student's files are numbered
#' in upload order and written as `anon_dir/<code>/file1.md`, `file2.md` and so
#' on, with images under `file<k>_media/`. A file is a spec when "spec" starts a
#' word in its original name. Exactly one file per student is the target that
#' [relink()] attaches feedback to, and it is always a document type
#' (`.docx`, `.odt`, `.pdf`, `.md`, `.qmd`, `.Rmd` or `.txt`), never a script
#' such as `.R`: the latest-uploaded document that is not a spec, or the
#' latest document when every document is a spec. A student with no document
#' at all stops the run, naming only the code. `anon_dir/manifest.csv` records
#' `code`, `file`, `late`, `ext`, `spec` and `target`, and carries no names, ids
#' or original filenames.
#'
#' Redaction runs on the text, longest term first, case-insensitive and whole
#' word, with underscores counted as boundaries. Every name form, nickname,
#' file prefix, login and Canvas id of every student in the key becomes that
#' student's code, so a classmate named in a paper is coded too. A term two
#' students share, such as a common first name, becomes `SXX`. Home-folder
#' user names in file paths become `USER` and email addresses become `EMAIL`.
#'
#' Then the leftover check reads every `.md` and `.csv` under `anon_dir` for
#' every key value: once mirroring the redactor, and once as a bare substring
#' search for every name value of five or more letters with spaces and
#' punctuation removed, so a name glued inside a longer token is still found.
#' Any hit stops the run and prints the code and the anonymized file path,
#' never the value found. Until the check passes, `anon_dir/NOT_READY` exists,
#' and [relink()] refuses a folder carrying it, so a failed run never leaves an
#' old folder looking ready. The fix for a leftover is to add the missing form
#' to the student's `nicknames` in the key and run again.
#'
#' A re-run replaces the previous output. It refuses when `anon_dir/feedback/`
#' or `anon_dir/scores.csv` exists, because that is grading work. It also
#' refuses, before deleting anything, when `anon_dir` is the assignment folder
#' or one of its parents, or when it already holds files that no earlier run of
#' this function wrote (no `manifest.csv` and no `NOT_READY`).
#'
#' Images are not searched. A screenshot can show a name, and that risk is
#' accepted because plots are needed for grading.
#'
#' @param proj Course project root. Relative paths are resolved against it.
#' @param assignment Folder of one assignment's Canvas downloads, usually
#'   under the course's git-ignored semester folder.
#' @param key The anonymization key [anon_key()] wrote.
#' @param anon_dir Where the coded text is written. `NULL` means `anon/`
#'   inside `assignment`.
#' @param dict Word list, one word per line. A first-initial-plus-surname form
#'   found in it ("Hall, Sam" gives "shall") is an ordinary word and is not
#'   redacted. `NULL` keeps every form. The default is [default_dict()], the
#'   system word list where one exists.
#' @return A list with `students`, `files` and `replacements` counts,
#'   invisibly. The run stops instead of returning when a leftover is found.
#' @seealso [anon_key()], [relink()], [canvas_grades()]
#' @examples
#' p <- tempfile("course-"); dir.create(p)
#' writeLines(c(
#'   "Student,ID,SIS User ID,SIS Login ID,Root Account,Section",
#'   "\"Quill, Pat\",1001,U1,XQ1001,x,01",
#'   "\"Rivera, Morgan\",1002,U2,XQ1002,x,01"), file.path(p, "gradebook.csv"))
#' anon_key(p, "gradebook.csv")
#' a <- file.path(p, "semester", "Essay1"); dir.create(a, recursive = TRUE)
#' writeLines("Pat Quill wrote this with Morgan Rivera.",
#'            file.path(a, "quillpat_1001_5001_essay.md"))
#' writeLines("By Morgan Rivera.", file.path(a, "riveramorgan_1002_5002_essay.md"))
#' anonymize(p, "semester/Essay1", dict = NULL)
#' readLines(file.path(a, "anon", "S01", "file1.md"))
#' unlink(p, recursive = TRUE)
#' @export
anonymize <- function(proj, assignment, key = "semester/anon_key.csv",
                      anon_dir = NULL, dict = default_dict()) {
  proj <- anon_proj(proj)
  assignment_dir <- proj_path(proj, assignment)
  key_path <- proj_path(proj, key)
  anon_dir <- if (is.null(anon_dir) || !nzchar(anon_dir)) {
    file.path(assignment_dir, "anon")
  } else proj_path(proj, anon_dir)
  dict_path <- dict
  if (!dir.exists(assignment_dir)) {
    stop("no assignment folder at ", assignment_dir, call. = FALSE)
  }

  if (dir.exists(file.path(anon_dir, "feedback")) ||
      file.exists(file.path(anon_dir, "scores.csv"))) {
    stop("anon/feedback or anon/scores.csv exists; re-running would discard ",
         "grading work. Move it out first.", call. = FALSE)
  }

  # anon_dir is about to be wiped. Refuse before touching anything unless it
  # is unmistakably a spot anonymize() itself owns: this is what stands
  # between a bad anon_dir and deleting the Canvas downloads or the key.
  assignment_real <- sub("/+$", "", normalizePath(assignment_dir, mustWork = FALSE))
  anon_real <- sub("/+$", "", normalizePath(anon_dir, mustWork = FALSE))
  if (identical(anon_real, assignment_real) ||
      startsWith(assignment_real, paste0(anon_real, "/"))) {
    stop("anon_dir must not be the assignment folder itself or a parent of ",
         "it; that would delete student submissions and the key. Point it ",
         "at a folder inside the assignment, such as anon/.", call. = FALSE)
  }
  existing <- if (dir.exists(anon_dir)) {
    list.files(anon_dir, all.files = TRUE, no.. = TRUE)
  } else character()
  looks_like_our_output <- length(existing) == 0 ||
    file.exists(file.path(anon_dir, "manifest.csv")) ||
    file.exists(file.path(anon_dir, "NOT_READY"))
  if (!looks_like_our_output) {
    stop("anon_dir already contains files anonymize() did not create; ",
         "refusing to delete them. Point anon_dir at an empty folder or a ",
         "prior anonymize() output.", call. = FALSE)
  }
  # From here on a stop anywhere must not leave an old anon/ looking ready.
  if (dir.exists(anon_dir)) {
    writeLines("anonymize has not finished its leftover check",
               file.path(anon_dir, "NOT_READY"))
  }

  key <- read_key(key_path)
  listed <- list_submissions(assignment_dir)
  ignored <- attr(listed, "ignored")
  if (!is.null(ignored) && ignored > 0) {
    cat(sprintf("%d file(s) ignored (not Canvas submission names)\n", ignored))
  }
  subs <- assign_files(listed, key)
  terms <- key_terms(key, extra = data.frame(term = subs$prefix, code = subs$code,
                                             stringsAsFactors = FALSE),
                     dict_path = dict_path)

  dir.create(anon_dir, recursive = TRUE, showWarnings = FALSE)
  old <- list.files(anon_dir, full.names = TRUE)
  unlink(old[!basename(old) %in% c("feedback", "scores.csv")], recursive = TRUE)
  writeLines("anonymize has not finished its leftover check", file.path(anon_dir, "NOT_READY"))

  n <- 0L
  for (r in seq_len(nrow(subs))) {
    s <- subs[r, ]
    out_md <- file.path(anon_dir, s$code, paste0(s$anon_name, ".md"))
    tryCatch(convert_to_text(file.path(assignment_dir, s$file), out_md,
                             file.path(anon_dir, s$code, paste0(s$anon_name, "_media"))),
             error = function(e) {
               stop(s$code, " (", s$anon_name, "): ", conditionMessage(e), call. = FALSE)
             })
    txt <- redact_paths(readLines(out_md, warn = FALSE, encoding = "UTF-8"))
    red <- redact_text(txt, terms)
    writeLines(red$text, out_md, useBytes = TRUE)
    n <- n + red$n
  }
  utils::write.csv(data.frame(code = subs$code, file = subs$anon_name, late = subs$late,
                              ext = tolower(tools::file_ext(subs$file)), spec = subs$spec,
                              target = subs$target),
                   file.path(anon_dir, "manifest.csv"), row.names = FALSE)

  texts <- list.files(anon_dir, "\\.(md|csv)$", recursive = TRUE, full.names = TRUE)
  left <- find_leftovers(texts, terms)
  if (nrow(left)) {
    for (i in seq_len(nrow(left))) {
      message("LEFTOVER: a value for ", left$code[i], " remains in ",
              sub(paste0("^", rx_escape(anon_dir), "/?"), "anon/", left$file[i]))
    }
    stop(nrow(left), " leftover(s); anon/ is NOT ready for grading. ",
         "Add the missing form as a nickname in the key and re-run.", call. = FALSE)
  }
  unlink(file.path(anon_dir, "NOT_READY"))
  cat(sprintf("anonymize: %d students, %d files, %d replacements, 0 leftovers. anon/ is ready.\n",
              length(unique(subs$code)), nrow(subs), n))
  version_line("anonymize")
  invisible(list(students = length(unique(subs$code)), files = nrow(subs),
                 replacements = n))
}

# Identity strings that must not appear in one student's finished feedback:
# every other student's code, full name forms, prefix, login and id. Single
# first or last names are left out; ordinary words ("young") would trip it.
foreign_terms <- function(key, code) {
  o <- key[key$code != code, , drop = FALSE]
  full <- unlist(lapply(o$name_forms, function(x) {
    f <- split_list(x); f[grepl("[ ,]", f)]
  }))
  bad <- c(o$code, full, o$file_prefix, o$login, o$canvas_id)
  # Same filter as key_terms(): a blank field (read_key's na.strings =
  # character() turns an empty gradebook cell into "", not NA) must not
  # become a zero-width word_rx() that matches almost any text.
  bad[!is.na(bad) & nchar(bad) >= 2]
}

# `code` is what an error names; target is a Canvas filename and carries the
# student's name prefix and id.
# Every feedback file must be a valid file of its submission's type, so a type
# with no writer here stops before anything is written.
render_feedback <- function(md_lines, target, code) {
  ext <- tolower(tools::file_ext(target))
  if (!ext %in% DOCUMENT_EXTS) {
    stop(code, ": cannot write feedback as a .", ext, " file; feedback is written ",
         "only as ", paste(DOCUMENT_EXTS, collapse = ", "), call. = FALSE)
  }
  tmp <- tempfile(fileext = ".md")
  on.exit(unlink(tmp), add = TRUE)
  writeLines(md_lines, tmp, useBytes = TRUE)
  if (ext == "pdf") {
    run_tool("pandoc", c(shQuote(tmp), "--pdf-engine=xelatex",
                         "-V", "geometry:margin=1in", "-o", shQuote(target)))
  } else if (ext %in% c("docx", "odt")) {
    # pandoc picks the writer from the target's extension.
    run_tool("pandoc", c(shQuote(tmp), "-o", shQuote(target)))
  } else {
    # file.copy's own warning would print the target path (a Canvas filename).
    if (!suppressWarnings(file.copy(tmp, target))) {
      stop("could not write feedback for ", code, call. = FALSE)
    }
  }
}

#' Link graded, coded feedback back to the real Canvas submissions
#'
#' The second half of grading without student identity. The grader has
#' written `anon_dir/feedback/<code>.md` for each student graded and
#' `anon_dir/scores.csv` with a `code` column and one column per score, keyed
#' by code and nothing else. This puts the names back on this machine only.
#'
#' For each code in `scores.csv`, the code in the feedback is replaced by the
#' student's name and the result is checked against every other student: their
#' code, every multi-word name form, file prefix, login and Canvas id. A hit
#' stops the run naming only the code whose feedback to fix. Feedback is then
#' rendered under the exact file name of that student's target submission (see
#' [anonymize()], which picks it by the same rule), and the file is a valid
#' file of that type: a `.pdf` submission gets a PDF through pandoc and
#' xelatex, a `.docx` submission a Word file and an `.odt` submission an
#' OpenDocument text file, both through pandoc, and a `.md`, `.qmd`, `.Rmd` or
#' `.txt` submission gets the feedback text. Any other type stops the run,
#' naming the code and the extension, before that file is written.
#'
#' Three files are written to `out_dir`: `feedback/`, holding one file per
#' scored student; `<assignment>_scores.csv`, named from the assignment
#' folder's name in lower case, carrying `name`, `canvas_id`,
#' `submission_file`, `late` and the score columns; and `feedback.zip`,
#' holding `feedback/` without `.DS_Store`, ready for Canvas's
#' submission-comment upload. The zip is checked to hold exactly the rendered
#' files and is removed when it does not.
#'
#' Nothing is written unless everything can be. It refuses while
#' `anon_dir/NOT_READY` exists; when `out_dir` already has a non-empty
#' `feedback/`, the scores file or `feedback.zip`, before reading anything;
#' when `scores.csv` has no `code` column or lists a code twice; and when the
#' codes in `scores.csv` and the feedback files disagree. Feedback renders into
#' a scratch folder that moves into place only once every file has rendered,
#' so a failure partway through leaves no partial `feedback/`. Submissions
#' with no feedback are reported by code at the end.
#'
#' @param proj Course project root. Relative paths are resolved against it.
#' @param assignment Folder of the assignment's Canvas downloads, the one
#'   [anonymize()] read.
#' @param key The anonymization key [anon_key()] wrote.
#' @param anon_dir The graded coded folder. `NULL` means `anon/` inside
#'   `assignment`.
#' @param out_dir Where feedback, scores and the zip are written. `NULL` means
#'   `assignment` itself.
#' @param dict Accepted so [anonymize()] and `relink()` take the same
#'   arguments. It changes nothing here: the cross-student check already uses
#'   only multi-word name forms, and a first-initial-plus-surname form is a
#'   single word.
#' @return A list with the `students` count, invisibly.
#' @seealso [anon_key()], [anonymize()], [canvas_grades()]
#' @examples
#' p <- tempfile("course-"); dir.create(p)
#' writeLines(c(
#'   "Student,ID,SIS User ID,SIS Login ID,Root Account,Section",
#'   "\"Quill, Pat\",1001,U1,XQ1001,x,01"), file.path(p, "gradebook.csv"))
#' anon_key(p, "gradebook.csv")
#' a <- file.path(p, "semester", "Essay1"); dir.create(a, recursive = TRUE)
#' writeLines("Pat Quill's essay.", file.path(a, "quillpat_1001_5001_essay.md"))
#' anonymize(p, "semester/Essay1", dict = NULL)
#' dir.create(file.path(a, "anon", "feedback"))
#' writeLines("Good work, S01.", file.path(a, "anon", "feedback", "S01.md"))
#' write.csv(data.frame(code = "S01", total = "9"),
#'           file.path(a, "anon", "scores.csv"), row.names = FALSE)
#' if (nzchar(Sys.which("zip"))) {
#'   relink(p, "semester/Essay1")
#'   readLines(file.path(a, "feedback", "quillpat_1001_5001_essay.md"))
#' }
#' unlink(p, recursive = TRUE)
#' @export
relink <- function(proj, assignment, key = "semester/anon_key.csv",
                   anon_dir = NULL, out_dir = NULL, dict = default_dict()) {
  proj <- anon_proj(proj)
  assignment_dir <- proj_path(proj, assignment)
  key_path <- proj_path(proj, key)
  anon_dir <- if (is.null(anon_dir) || !nzchar(anon_dir)) {
    file.path(assignment_dir, "anon")
  } else proj_path(proj, anon_dir)
  out_dir <- if (is.null(out_dir) || !nzchar(out_dir)) assignment_dir else proj_path(proj, out_dir)
  if (!dir.exists(assignment_dir)) {
    stop("no assignment folder at ", assignment_dir, call. = FALSE)
  }

  if (file.exists(file.path(anon_dir, "NOT_READY"))) {
    stop("anon/ is NOT_READY: anonymize did not pass its leftover check", call. = FALSE)
  }

  # Every output-existence guard runs first, before anything is read or
  # written, so a refusal never leaves a partial or finished-looking output.
  fb_out <- file.path(out_dir, "feedback")
  if (dir.exists(fb_out) && length(list.files(fb_out))) {
    stop("feedback/ already has files in the output folder; move them first", call. = FALSE)
  }
  scores_path <- file.path(out_dir, paste0(tolower(basename(assignment_dir)), "_scores.csv"))
  if (file.exists(scores_path)) {
    stop("scores file already exists in the output folder; move it first", call. = FALSE)
  }
  zip_path <- file.path(out_dir, "feedback.zip")
  if (file.exists(zip_path)) {
    stop("feedback.zip already exists in the output folder; move it first", call. = FALSE)
  }

  key <- read_key(key_path)
  subs <- assign_files(list_submissions(assignment_dir), key)
  if (!file.exists(file.path(anon_dir, "scores.csv"))) {
    stop("no scores.csv in anon/; the grader writes it, keyed by code", call. = FALSE)
  }
  scores <- utils::read.csv(file.path(anon_dir, "scores.csv"), colClasses = "character",
                            check.names = FALSE)
  if (!"code" %in% names(scores)) stop("anon/scores.csv has no code column", call. = FALSE)
  dup <- unique(scores$code[duplicated(scores$code)])
  if (length(dup)) {
    stop("scores.csv lists a code more than once: ",
         paste(sort(dup), collapse = ", "), call. = FALSE)
  }
  fb <- sub("\\.md$", "", list.files(file.path(anon_dir, "feedback"), "^S[0-9]+\\.md$"))
  gap <- c(setdiff(scores$code, fb), setdiff(fb, scores$code))
  if (length(gap)) {
    stop("scores and feedback files disagree for: ", paste(sort(gap), collapse = ", "),
         call. = FALSE)
  }

  targets <- subs[subs$target, , drop = FALSE]
  finished <- list()
  for (cd in scores$code) {
    t <- targets[targets$code == cd, , drop = FALSE]
    if (nrow(t) != 1) stop(cd, ": no single submission file to attach feedback to", call. = FALSE)
    name <- key$name[key$code == cd]
    txt <- readLines(file.path(anon_dir, "feedback", paste0(cd, ".md")),
                     warn = FALSE, encoding = "UTF-8")
    txt <- gsub(word_rx(cd), name, txt, perl = TRUE)
    body <- paste(txt, collapse = "\n")
    bad <- foreign_terms(key, cd)
    hit <- vapply(bad, function(b) grepl(word_rx(b), body, perl = TRUE,
                                         ignore.case = TRUE), logical(1))
    if (any(hit)) stop(cd, ": feedback mentions another student; fix anon/feedback/",
                       cd, ".md and re-run", call. = FALSE)
    finished[[cd]] <- list(lines = txt, target = t$file)
  }

  # Render into a scratch folder beside the destination and move it into
  # place only once every file has rendered, so a render failure partway
  # through never leaves a partial feedback/ under out_dir.
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  tmp_out <- file.path(out_dir, paste0(".feedback.tmp.", Sys.getpid()))
  unlink(tmp_out, recursive = TRUE)
  dir.create(tmp_out, recursive = TRUE)
  on.exit(unlink(tmp_out, recursive = TRUE), add = TRUE)
  for (cd in names(finished)) {
    render_feedback(finished[[cd]]$lines, file.path(tmp_out, finished[[cd]]$target), cd)
  }
  if (!file.rename(tmp_out, fb_out)) {
    stop("could not move rendered feedback into ", fb_out, call. = FALSE)
  }

  m <- match(scores$code, key$code)
  tgt <- targets[match(scores$code, targets$code), ]
  out_scores <- data.frame(name = key$name[m], canvas_id = key$canvas_id[m],
                           submission_file = tgt$file, late = tgt$late,
                           scores[setdiff(names(scores), "code")],
                           check.names = FALSE, stringsAsFactors = FALSE)
  utils::write.csv(out_scores, scores_path, row.names = FALSE)

  old <- setwd(out_dir); on.exit(setwd(old), add = TRUE)
  run_tool("zip", c("-r", "-X", "-q", "feedback.zip", "feedback", "-x", shQuote("*.DS_Store")))
  setwd(old)
  entries <- utils::unzip(zip_path, list = TRUE)$Name
  entries <- sub("^feedback/", "", entries[entries != "feedback/"])
  wanted <- vapply(finished, function(x) x$target, character(1))
  if (anyDuplicated(entries) || !setequal(entries, wanted)) {
    unlink(zip_path)
    stop("feedback.zip entries do not match the rendered feedback files exactly",
         call. = FALSE)
  }

  missing <- sort(setdiff(unique(targets$code), scores$code))
  if (length(missing)) {
    cat(sprintf("%d submission(s) have no feedback: %s\n", length(missing),
                paste(missing, collapse = ", ")))
  }
  cat(sprintf("relink: %d feedback files, scores and feedback.zip written\n", length(finished)))
  version_line("relink")
  invisible(list(students = length(finished)))
}
