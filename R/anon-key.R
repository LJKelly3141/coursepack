# The anonymization key: one row per student, for one grading run.
#
# The key is the only place a code meets a name. Each assignment gets its own,
# at <assignment>/anon_key.csv beside the Canvas downloads and never inside
# anon/, with the codes shuffled afresh, so a leaked key de-anonymizes one
# assignment and no other. The grader never reads it. Nothing in this file
# prints a name, an id or a login: an error names a gradebook row number, a
# count, a code or a folder path.

KEY_COLUMNS <- c("run", "code", "canvas_id", "name", "name_forms",
                 "file_prefix", "login", "nicknames")

KEY_FILE <- "anon_key.csv"

# A random order, kept in its own function so the fixtures can switch it off.
# It draws from a fresh, unseeded stream, so a set.seed() earlier in the
# session cannot make two runs share a mapping, and it puts the session's RNG
# state back afterwards, as draw_items() does, so a simulation running in the
# same session is not moved.
shuffle <- function(x) {
  if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) {
    old <- get(".Random.seed", envir = globalenv(), inherits = FALSE)
    on.exit(assign(".Random.seed", old, envir = globalenv()), add = TRUE)
  } else {
    on.exit(suppressWarnings(rm(".Random.seed", envir = globalenv())), add = TRUE)
  }
  set.seed(NULL)
  x[sample.int(length(x))]
}

# The run a key belongs to: the assignment folder's path relative to proj,
# always with forward slashes. A folder outside proj has no run.
run_id <- function(proj, assignment_dir) {
  p <- sub("/+$", "", normalizePath(proj, winslash = "/", mustWork = TRUE))
  a <- sub("/+$", "", normalizePath(assignment_dir, winslash = "/", mustWork = TRUE))
  if (!startsWith(a, paste0(p, "/"))) {
    stop("assignment folder ", assignment_dir, " is not inside the project ", proj,
         call. = FALSE)
  }
  substring(a, nchar(p) + 2L)
}

# Stops unless every row of the key records `run`.
check_run <- function(key, key_path, run) {
  r <- unique(key$run)
  if (length(r) != 1L || !nzchar(r)) {
    stop("key ", key_path, " does not record a single run; rebuild it with anon_key()",
         call. = FALSE)
  }
  if (!identical(r, run)) {
    stop("key ", key_path, " belongs to the run '", r, "', not '", run, "'. Each ",
         "assignment has its own key; build this one's with anon_key()", call. = FALSE)
  }
  invisible(key)
}

# Canvas bulk-download names: prefix[_LATE]_canvasid_submissionid_original
parse_canvas_filename <- function(name) {
  m <- regmatches(name, regexec("^([^_]+)(_LATE)?_([0-9]+)_([0-9]+)_(.*)$",
                                name))[[1]]
  if (!length(m)) return(NULL)
  list(prefix = m[2], late = nzchar(m[3]), canvas_id = m[4],
       submission_id = m[5], original = m[6])
}

split_list <- function(x) {
  if (length(x) != 1 || is.na(x) || !nzchar(x)) return(character())
  out <- trimws(strsplit(x, ";", fixed = TRUE)[[1]])
  out[nzchar(out)]
}

# An accented name loses its accents: the transliteration leaves each accent
# as a mark beside its letter on some platforms, so those marks are dropped,
# and anything iconv cannot represent (NA, or a "?") is dropped rather than
# kept as a broken form.
strip_accents <- function(x) {
  y <- iconv(x, from = "UTF-8", to = "ASCII//TRANSLIT")
  y <- gsub("[`'~\"^]", "", y)
  y[!is.na(y) & !grepl("?", y, fixed = TRUE)]
}

name_forms <- function(student, row) {
  parts <- trimws(strsplit(student, ",", fixed = TRUE)[[1]])
  if (length(parts) != 2 || !all(nzchar(parts))) {
    stop("gradebook row ", row, " is not in 'Last, First' form", call. = FALSE)
  }
  last <- parts[1]; first <- parts[2]
  tokens <- unlist(strsplit(c(first, last), "[ -]+"))
  letters_only <- function(x) tolower(gsub("[^\\p{L}]", "", x, perl = TRUE))
  initial <- paste0(substr(letters_only(first), 1, 1), letters_only(last))
  joined <- c(paste0(letters_only(first), letters_only(last)),
              paste0(letters_only(last), letters_only(first)), initial)
  forms <- unique(c(paste(first, last), paste0(last, ", ", first),
                    first, last, tokens, joined))
  forms <- unique(c(forms, strip_accents(forms)))
  initial <- unique(c(initial, strip_accents(initial)))
  list(full = paste(first, last),
       forms = forms[nchar(forms) >= 2],
       initial = initial[nchar(initial) >= 2],
       prefix = tolower(gsub("[^A-Za-z]", "", paste0(last, first))))
}

empty_key <- function() {
  k <- replicate(length(KEY_COLUMNS), character(), simplify = FALSE)
  names(k) <- KEY_COLUMNS
  as.data.frame(k, stringsAsFactors = FALSE)
}

read_key <- function(key_path) {
  if (!file.exists(key_path)) {
    stop("no key at ", key_path, "; run anon_key() first", call. = FALSE)
  }
  k <- utils::read.csv(key_path, colClasses = "character",
                       na.strings = character(), check.names = FALSE)
  miss <- setdiff(KEY_COLUMNS, names(k))
  if (length(miss)) {
    stop("key ", key_path, " is missing column(s): ", paste(miss, collapse = ", "),
         call. = FALSE)
  }
  k[KEY_COLUMNS]
}

# The term nicknames file: canvas_id,nicknames, nicknames separated by ";".
# It carries no codes, so it says nothing about any grading run. Returns the
# nicknames as a list named by canvas_id.
read_nicknames <- function(path) {
  if (!file.exists(path)) stop("no nicknames file at ", path, call. = FALSE)
  n <- utils::read.csv(path, colClasses = "character", na.strings = character(),
                       check.names = FALSE, strip.white = TRUE)
  miss <- setdiff(c("canvas_id", "nicknames"), names(n))
  if (length(miss)) {
    stop("nicknames file ", path, " is missing column(s): ", paste(miss, collapse = ", "),
         "; it needs canvas_id,nicknames", call. = FALSE)
  }
  ids <- unique(n$canvas_id[nzchar(n$canvas_id)])
  stats::setNames(lapply(ids, function(id) {
    unique(unlist(lapply(n$nicknames[n$canvas_id == id], split_list)))
  }), ids)
}

# Builds the key for one run, or extends it when it already exists for the
# same run: existing rows, codes and any nicknames typed in by hand are kept
# exactly, and only new students are added, at the next free codes in a
# random order. A key of another run stops before anything is written.
# Nicknames from the term nicknames file are merged into every matching row.
build_key <- function(gradebook_csv, key_path, run, nicknames_path = NULL) {
  if (!file.exists(gradebook_csv)) {
    stop("no gradebook export at ", gradebook_csv, call. = FALSE)
  }
  nick <- if (!is.null(nicknames_path)) read_nicknames(nicknames_path) else list()
  g <- utils::read.csv(gradebook_csv, check.names = FALSE,
                       colClasses = "character", na.strings = character())
  miss <- setdiff(c("Student", "ID", "SIS Login ID"), names(g))
  if (length(miss)) {
    stop("gradebook export is missing column(s): ", paste(miss, collapse = ", "),
         call. = FALSE)
  }
  rows <- which(grepl("^[0-9]+$", g$ID) & trimws(g$Student) != "Student, Test")
  key <- if (file.exists(key_path)) {
    check_run(read_key(key_path), key_path, run)
  } else empty_key()
  rows <- rows[!(g$ID[rows] %in% key$canvas_id)]
  rows <- rows[order(as.numeric(g$ID[rows]))]
  n0 <- if (nrow(key)) max(as.integer(sub("^S", "", key$code))) else 0L
  if (length(rows)) {
    codes <- sprintf("S%02d", shuffle(n0 + seq_along(rows)))
    add <- do.call(rbind, lapply(seq_along(rows), function(i) {
      r <- rows[i]
      f <- name_forms(g$Student[r], r)
      data.frame(run = run, code = codes[i], canvas_id = g$ID[r],
                 name = f$full, name_forms = paste(f$forms, collapse = "; "),
                 file_prefix = f$prefix, login = g[["SIS Login ID"]][r],
                 nicknames = "", stringsAsFactors = FALSE)
    }))
    key <- rbind(key, add)
  }
  matched <- 0L
  for (i in which(key$canvas_id %in% names(nick))) {
    merged <- unique(c(split_list(key$nicknames[i]), nick[[key$canvas_id[i]]]))
    key$nicknames[i] <- paste(merged, collapse = "; ")
    matched <- matched + 1L
  }
  dir.create(dirname(key_path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(key, key_path, row.names = FALSE)
  cat(sprintf("key: %d students (%d new) for run %s%s\n", nrow(key), length(rows), run,
              if (length(nick)) sprintf(", nicknames for %d", matched) else ""))
  invisible(key)
}

#' The default word list for anonymized grading
#'
#' A first-initial-plus-surname form of a student's name can be an ordinary
#' English word: "Hall, Sam" gives "shall". Redacting it would mangle every
#' "shall" in every paper, and the leftover check would then refuse to release
#' the folder. A form found in a word list is therefore treated as a word and
#' not as a name. Full names, joined forms and the other forms are kept.
#'
#' This is the one place the package names a system path. `/usr/share/dict/words`
#' is the standard word list on macOS and on most Linux systems, and it lives
#' outside any course, so it is read and never written. Where it is absent the
#' default is `NULL` and every name form is kept, which is the safe direction:
#' too much is redacted rather than too little.
#'
#' @return The path of the system word list when it exists, otherwise `NULL`.
#' @seealso [anonymize()], [relink()]
#' @examples
#' default_dict()
#' @export
default_dict <- function() {
  p <- "/usr/share/dict/words"
  if (file.exists(p)) p else NULL
}

# An optional word list, one word per line. A first-initial+last form found in
# it is an ordinary word, not a name, and is dropped. NULL, or an unreadable
# file, keeps every form.
read_word_list <- function(dict_path) {
  if (is.null(dict_path) || !nzchar(dict_path)) return(NULL)
  if (!file.exists(dict_path) || file.access(dict_path, 4) != 0) {
    message("word list ", dict_path, " is not readable; keeping every name form")
    return(NULL)
  }
  unique(tolower(trimws(readLines(dict_path, warn = FALSE, encoding = "UTF-8"))))
}

# Every string that identifies a student, with the code that replaces it.
# A term shared by two students (a common first name) becomes SXX, so it can
# never be relinked to the wrong person.
key_terms <- function(key, extra = NULL, dict_path = NULL) {
  words <- read_word_list(dict_path)
  rows <- lapply(seq_len(nrow(key)), function(i) {
    forms <- split_list(key$name_forms[i])
    # A key built before the joined and accent-stripped forms existed still
    # gets them: re-derive from the stored "Last, First" form.
    lf <- forms[grepl(",", forms, fixed = TRUE)]
    nf <- lapply(lf, function(x) {
      tryCatch(name_forms(x, i), error = function(e) list(forms = character(),
                                                           initial = character()))
    })
    derived <- unlist(lapply(nf, `[[`, "forms"))
    initial <- tolower(unlist(lapply(nf, `[[`, "initial")))
    t <- c(forms, derived)
    if (!is.null(words)) {
      t <- t[!(tolower(t) %in% intersect(initial, words))]
    }
    # `loose`: whether find_leftovers() may search the term as a bare
    # substring. Not for the initial form or a one-word nickname: "pray",
    # "chris" sit inside ordinary words ("spray", "christmas").
    nick <- split_list(key$nicknames[i])
    t_loose <- !(tolower(t) %in% initial)
    t <- c(t, nick, key$file_prefix[i], key$login[i], key$canvas_id[i])
    loose <- c(t_loose, grepl("[^\\p{L}]", nick, perl = TRUE), TRUE, TRUE, TRUE)
    data.frame(term = t, code = key$code[i], loose = loose, stringsAsFactors = FALSE)
  })
  if (!is.null(extra) && !"loose" %in% names(extra)) extra$loose <- TRUE
  out <- do.call(rbind, c(rows, list(extra)))
  out <- out[!is.na(out$term) & nchar(out$term) >= 2, , drop = FALSE]
  out <- unique(out)
  lower <- tolower(out$term)
  shared <- tapply(out$code, lower, function(z) length(unique(z)) > 1)
  out$code[shared[lower]] <- "SXX"
  # A term that reaches the key by any loose-eligible route stays loose.
  any_loose <- tapply(out$loose, lower, any)
  out$loose <- as.logical(any_loose[lower])
  out <- out[!duplicated(tolower(out$term)), , drop = FALSE]
  out[order(-nchar(out$term), out$term), , drop = FALSE]
}

#' Build the anonymization key for one grading run
#'
#' Read a Canvas gradebook export and give every student in it a code for one
#' assignment's grading run: `S01` to `Snn`, handed out in a random order, so
#' no two runs share a mapping. The key is written to
#' `<assignment>/anon_key.csv`, beside the Canvas downloads and never inside
#' `anon/`, which is what the grader reads. It is the only file that joins a
#' code to a name, and because every assignment has its own, a key that leaks
#' de-anonymizes that one assignment and no other. Build it from the latest
#' export right before anonymizing, and delete it with [anon_forget()] once
#' the feedback and grades are in Canvas.
#'
#' Every row records the run it belongs to in a `run` column: the assignment
#' folder's path relative to `proj`, the same on every row. Running
#' `anon_key()` again for the same assignment keeps every row, code and field
#' exactly as it is, including `nicknames` typed in by hand, and adds only
#' students who are new in the export, at the next free codes in a random
#' order. A key already in the folder that records a different run stops the
#' call before anything is written. The export's `Points Possible` row and
#' Canvas's `Student, Test` row are skipped.
#'
#' Each row carries `run`, `code`, `canvas_id`, `name` ("First Last"),
#' `name_forms` (every spelling redacted from a submission, semicolon
#' separated: the full name both ways round, each name part, the joined forms
#' such as "patquill", the first-initial-plus-surname form, and
#' accent-stripped copies of all of them), `file_prefix` (the name prefix
#' Canvas puts on downloaded files), `login` and `nicknames`.
#'
#' Nicknames belong in a term nicknames file that the instructor keeps, a CSV
#' with columns `canvas_id,nicknames` and the nicknames separated by `;`. It
#' holds no codes, so it reveals no grading if it leaks. When `nicknames` names
#' it, each student's nicknames are merged into that student's `nicknames` in
#' the key. To catch a name a student uses that the roster does not, add it to
#' the nicknames file, run `anon_key()` again and re-run [anonymize()].
#'
#' Nothing printed names a student. A malformed row is reported by its row
#' number in the export.
#'
#' @param proj Course project root. Relative paths are resolved against it.
#' @param gradebook Canvas gradebook export, downloaded from the Gradebook's
#'   Export menu. Needs the `Student`, `ID` and `SIS Login ID` columns, and
#'   `Student` in "Last, First" form.
#' @param assignment Folder of one assignment's Canvas downloads, inside
#'   `proj`. The key is written to `anon_key.csv` in it.
#' @param nicknames Optional term nicknames file, columns `canvas_id` and
#'   `nicknames`. `NULL` adds no nicknames.
#' @return The key as a data frame, invisibly.
#' @seealso [anonymize()], [relink()], [anon_forget()], [canvas_grades()]
#' @examples
#' p <- tempfile("course-"); dir.create(p)
#' writeLines(c(
#'   "Student,ID,SIS User ID,SIS Login ID,Root Account,Section",
#'   "    Points Possible,,,,,",
#'   "\"Quill, Pat\",1001,U1,XQ1001,x,01",
#'   "\"Rivera, Morgan\",1002,U2,XQ1002,x,01"), file.path(p, "gradebook.csv"))
#' dir.create(file.path(p, "semester", "Essay1"), recursive = TRUE)
#' key <- anon_key(p, "gradebook.csv", "semester/Essay1")
#' key[c("run", "code")]
#' unlink(p, recursive = TRUE)
#' @export
anon_key <- function(proj, gradebook, assignment, nicknames = NULL) {
  proj <- anon_proj(proj)
  assignment_dir <- proj_path(proj, assignment)
  if (!dir.exists(assignment_dir)) {
    stop("no assignment folder at ", assignment_dir, call. = FALSE)
  }
  nick <- if (!is.null(nicknames) && length(nicknames) == 1L && !is.na(nicknames) &&
              nzchar(nicknames)) proj_path(proj, nicknames) else NULL
  out <- build_key(proj_path(proj, gradebook), file.path(assignment_dir, KEY_FILE),
                   run_id(proj, assignment_dir), nicknames_path = nick)
  version_line("anon_key")
  invisible(out)
}

#' Delete one assignment's anonymization key once grading is finished
#'
#' Delete `<assignment>/anon_key.csv`, the key [anon_key()] built for this
#' assignment's grading run. After that, nothing on the machine can link this
#' run's codes back to students, so the coded folder, the grader's notes and
#' any terminal scrollback carrying codes stop being identifying.
#'
#' It refuses until [relink()] has finished for the assignment, because the
#' key is needed to put the names back: the assignment's `feedback/` folder and
#' its relinked `<assignment>_scores.csv` must both exist in the assignment
#' folder, which is where [relink()] writes them by default. Run it once the
#' Canvas feedback upload and the grade import are confirmed. It prints one
#' line naming the file deleted, then the version line every entry point
#' prints.
#'
#' @param proj Course project root. Relative paths are resolved against it.
#' @param assignment Folder of the assignment's Canvas downloads, the one
#'   [anon_key()], [anonymize()] and [relink()] were given.
#' @return The path of the deleted key, invisibly.
#' @seealso [anon_key()], [relink()], [canvas_grades()]
#' @examples
#' p <- tempfile("course-"); dir.create(p)
#' writeLines(c(
#'   "Student,ID,SIS User ID,SIS Login ID,Root Account,Section",
#'   "\"Quill, Pat\",1001,U1,XQ1001,x,01"), file.path(p, "gradebook.csv"))
#' a <- file.path(p, "semester", "Essay1"); dir.create(a, recursive = TRUE)
#' anon_key(p, "gradebook.csv", "semester/Essay1")
#' writeLines("Pat Quill's essay.", file.path(a, "quillpat_1001_5001_essay.md"))
#' anonymize(p, "semester/Essay1", dict = NULL)
#' code <- list.files(file.path(a, "anon"), pattern = "^S")
#' dir.create(file.path(a, "anon", "feedback"))
#' writeLines("Good work.", file.path(a, "anon", "feedback", paste0(code, ".md")))
#' write.csv(data.frame(code = code, total = "9"),
#'           file.path(a, "anon", "scores.csv"), row.names = FALSE)
#' if (nzchar(Sys.which("zip"))) {
#'   relink(p, "semester/Essay1", dict = NULL)
#'   anon_forget(p, "semester/Essay1")
#' }
#' unlink(p, recursive = TRUE)
#' @export
anon_forget <- function(proj, assignment) {
  proj <- anon_proj(proj)
  assignment_dir <- proj_path(proj, assignment)
  if (!dir.exists(assignment_dir)) {
    stop("no assignment folder at ", assignment_dir, call. = FALSE)
  }
  key_path <- file.path(assignment_dir, KEY_FILE)
  if (!file.exists(key_path)) {
    stop("no key at ", key_path, "; there is nothing to forget", call. = FALSE)
  }
  scores <- paste0(tolower(basename(assignment_dir)), "_scores.csv")
  missing <- c(if (!dir.exists(file.path(assignment_dir, "feedback"))) "feedback/",
               if (!file.exists(file.path(assignment_dir, scores))) scores)
  if (length(missing)) {
    stop("relink() has not finished for this assignment (no ",
         paste(missing, collapse = " and no "), " in ", assignment_dir,
         "); the key is still needed to put the names back. Keep it until ",
         "relink() has run and the Canvas upload is confirmed.", call. = FALSE)
  }
  if (!file.remove(key_path)) stop("could not delete ", key_path, call. = FALSE)
  cat(sprintf("anon_forget: deleted %s; this run's codes can no longer be linked to students\n",
              key_path))
  version_line("anon_forget")
  invisible(key_path)
}

anon_proj <- function(proj) {
  if (!is.character(proj) || length(proj) != 1L || !dir.exists(proj))
    stop("proj is not a directory: ", paste(proj, collapse = ""), call. = FALSE)
  normalizePath(proj, mustWork = TRUE)
}
