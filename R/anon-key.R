# The anonymization key: one row per student, a stable code for the term.
#
# The key is the only place a code meets a name. It lives in the course's
# git-ignored semester folder beside the Canvas downloads, and the grader never
# reads it. Nothing in this file prints a name, an id or a login: an error
# names a gradebook row number, a count or a code.

KEY_COLUMNS <- c("code", "canvas_id", "name", "name_forms",
                 "file_prefix", "login", "nicknames")

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

# Adds rows for students not yet in the key. Existing rows, including any
# nicknames typed in by hand, are kept exactly.
build_key <- function(gradebook_csv, key_path) {
  if (!file.exists(gradebook_csv)) {
    stop("no gradebook export at ", gradebook_csv, call. = FALSE)
  }
  g <- utils::read.csv(gradebook_csv, check.names = FALSE,
                       colClasses = "character", na.strings = character())
  miss <- setdiff(c("Student", "ID", "SIS Login ID"), names(g))
  if (length(miss)) {
    stop("gradebook export is missing column(s): ", paste(miss, collapse = ", "),
         call. = FALSE)
  }
  rows <- which(grepl("^[0-9]+$", g$ID) & trimws(g$Student) != "Student, Test")
  key <- if (file.exists(key_path)) read_key(key_path) else empty_key()
  rows <- rows[!(g$ID[rows] %in% key$canvas_id)]
  rows <- rows[order(as.numeric(g$ID[rows]))]
  n0 <- if (nrow(key)) max(as.integer(sub("^S", "", key$code))) else 0L
  if (length(rows)) {
    add <- do.call(rbind, lapply(seq_along(rows), function(i) {
      r <- rows[i]
      f <- name_forms(g$Student[r], r)
      data.frame(code = sprintf("S%02d", n0 + i), canvas_id = g$ID[r],
                 name = f$full, name_forms = paste(f$forms, collapse = "; "),
                 file_prefix = f$prefix, login = g[["SIS Login ID"]][r],
                 nicknames = "", stringsAsFactors = FALSE)
    }))
    key <- rbind(key, add)
  }
  dir.create(dirname(key_path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(key, key_path, row.names = FALSE)
  cat(sprintf("key: %d students (%d new)\n", nrow(key), length(rows)))
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

#' Build or extend the anonymization key
#'
#' Read a Canvas gradebook export and give every student in it a code, `S01`,
#' `S02` and so on, that stays theirs for the term. The key is the only file
#' that joins a code to a name, and it belongs in the course's git-ignored
#' semester folder: the grader is never given it.
#'
#' A key that already exists is extended and never rebuilt. Students already
#' in it keep their codes and every field exactly as it is, including any
#' `nicknames` typed in by hand, and no row is ever dropped, so a student who
#' left the course keeps their code. New students get the next free codes, in
#' Canvas id order. The export's `Points Possible` row and Canvas's
#' `Student, Test` row are skipped.
#'
#' Each row carries `code`, `canvas_id`, `name` ("First Last"), `name_forms`
#' (every spelling redacted from a submission, semicolon separated: the full
#' name both ways round, each name part, the joined forms such as
#' "patquill", the first-initial-plus-surname form, and accent-stripped copies
#' of all of them), `file_prefix` (the name prefix Canvas puts on downloaded
#' files), `login` and `nicknames`. To catch a name a student uses that the
#' roster does not, add it to `nicknames`, semicolon separated, and re-run
#' [anonymize()].
#'
#' Nothing printed names a student. A malformed row is reported by its row
#' number in the export.
#'
#' @param proj Course project root. Relative paths are resolved against it.
#' @param gradebook Canvas gradebook export, downloaded from the Gradebook's
#'   Export menu. Needs the `Student`, `ID` and `SIS Login ID` columns, and
#'   `Student` in "Last, First" form.
#' @param key The key to create or extend.
#' @return The key as a data frame, invisibly.
#' @seealso [anonymize()], [relink()], [canvas_grades()]
#' @examples
#' p <- tempfile("course-"); dir.create(p)
#' writeLines(c(
#'   "Student,ID,SIS User ID,SIS Login ID,Root Account,Section",
#'   "    Points Possible,,,,,",
#'   "\"Quill, Pat\",1001,U1,XQ1001,x,01",
#'   "\"Rivera, Morgan\",1002,U2,XQ1002,x,01"), file.path(p, "gradebook.csv"))
#' key <- anon_key(p, "gradebook.csv")
#' key$code
#' unlink(p, recursive = TRUE)
#' @export
anon_key <- function(proj, gradebook, key = "semester/anon_key.csv") {
  proj <- anon_proj(proj)
  out <- build_key(proj_path(proj, gradebook), proj_path(proj, key))
  version_line("anon_key")
  invisible(out)
}

anon_proj <- function(proj) {
  if (!is.character(proj) || length(proj) != 1L || !dir.exists(proj))
    stop("proj is not a directory: ", paste(proj, collapse = ""), call. = FALSE)
  normalizePath(proj, mustWork = TRUE)
}
