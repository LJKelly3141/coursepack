# Fill assignment scores into a Canvas gradebook export, for re-import.
#
# Canvas only accepts an import that is exactly its own export, so this edits
# the downloaded file as text: every byte is kept (quoting, line endings, a
# byte-order mark, number formats, read-only columns, letter grades) except
# the target assignments' cells on the rows of students who have a score.
# Identity lives only in that export and in the key, on this machine; the
# grader's output only ever carried scores and codes.
#
# Students with no score keep whatever the export had. Messages print counts
# and column headers, never a student's name or id.

# Split one CSV line into its raw fields, quotes left in place.
split_fields <- function(line, n) {
  ch <- strsplit(line, "", fixed = TRUE)[[1]]
  fields <- character(); cur <- character(); inq <- FALSE
  for (c in ch) {
    if (c == '"') { inq <- !inq; cur <- c(cur, c) }
    else if (c == "," && !inq) { fields <- c(fields, paste(cur, collapse = "")); cur <- character() }
    else cur <- c(cur, c)
  }
  if (inq) {
    stop("line ", n, " of the export has a quoted field that spans lines or is unbalanced",
         call. = FALSE)
  }
  c(fields, paste(cur, collapse = ""))
}

unquote <- function(x) {
  q <- grepl('^".*"$', x)
  x[q] <- gsub('""', '"', substr(x[q], 2, nchar(x[q]) - 1), fixed = TRUE)
  x
}

find_scores_file <- function(assignment_dir) {
  s <- list.files(assignment_dir, "_scores\\.csv$", full.names = TRUE)
  if (length(s) == 1) return(s)
  if (length(s) > 1) {
    stop(basename(assignment_dir), ": more than one scores file (",
         paste(basename(s), collapse = ", "), "); name one in the map's scores column",
         call. = FALSE)
  }
  a <- file.path(assignment_dir, "anon", "scores.csv")
  if (file.exists(a)) return(a)
  stop(basename(assignment_dir), ": no scores file found; name one in the map's scores column",
       call. = FALSE)
}

# Scores as data.frame(canvas_id, total), whichever form they arrive in.
read_scores <- function(scores_path, key_path) {
  s <- utils::read.csv(scores_path, colClasses = "character", check.names = FALSE,
                       na.strings = character())
  if (!"total" %in% names(s)) stop(basename(scores_path), " has no total column", call. = FALSE)
  id_col <- intersect(c("canvas_id", "canvas_user_id"), names(s))
  if (length(id_col)) {
    ids <- s[[id_col[1]]]
  } else if ("code" %in% names(s)) {
    if (is.null(key_path) || !nzchar(key_path) || !file.exists(key_path)) {
      stop("scores keyed by code need the anonymization key to be placed", call. = FALSE)
    }
    k <- read_key(key_path)
    ids <- k$canvas_id[match(s$code, k$code)]
    if (anyNA(ids)) {
      stop(sum(is.na(ids)), " code(s) in ", basename(scores_path), " are not in the key",
           call. = FALSE)
    }
  } else {
    stop(basename(scores_path), " has neither a Canvas id column nor a code column",
         call. = FALSE)
  }
  if (anyDuplicated(ids)) stop(basename(scores_path), " lists a student more than once",
                               call. = FALSE)
  tot <- suppressWarnings(as.numeric(s$total))
  bad <- is.na(tot) & nzchar(s$total)
  if (any(bad)) {
    stop(sum(bad), " total(s) in ", basename(scores_path), " are not a number", call. = FALSE)
  }
  keep <- !is.na(tot)
  data.frame(canvas_id = ids[keep], total = tot[keep], stringsAsFactors = FALSE)
}

# The map: one row per assignment, columns `folder` and `column`, optional
# `scores` (a scores file path when the folder holds more than one).
read_map <- function(map_path) {
  if (!file.exists(map_path)) stop("no map at ", map_path, call. = FALSE)
  m <- utils::read.csv(map_path, colClasses = "character", na.strings = character(),
                       strip.white = TRUE)
  miss <- setdiff(c("folder", "column"), names(m))
  if (length(miss)) {
    stop("the map is missing column(s): ", paste(miss, collapse = ", "), call. = FALSE)
  }
  if (!"scores" %in% names(m)) m$scores <- ""
  m[nzchar(m$folder), c("folder", "column", "scores"), drop = FALSE]
}

# targets: data.frame(folder, column, scores), paths already resolved. Writes
# one import file. Every target is resolved and validated before a byte is
# written, so a failing assignment leaves no file behind.
fill_gradebook <- function(gradebook_csv, targets, out = NULL, key_path = NULL) {
  if (is.null(out) || !nzchar(out)) out <- file.path(dirname(gradebook_csv), "canvas_import.csv")
  if (file.exists(out)) stop(basename(out), " already exists; move it first", call. = FALSE)
  if (!nrow(targets)) stop("no assignments to fill", call. = FALSE)
  if (!file.exists(gradebook_csv)) stop("no gradebook export at ", gradebook_csv, call. = FALSE)

  bytes <- readBin(gradebook_csv, "raw", file.info(gradebook_csv)$size)
  bom <- length(bytes) >= 3 && identical(bytes[1:3], as.raw(c(0xEF, 0xBB, 0xBF)))
  if (bom) bytes <- bytes[-(1:3)]
  text <- rawToChar(bytes)
  eol <- if (grepl("\r\n", text, fixed = TRUE)) "\r\n" else "\n"
  final_eol <- endsWith(text, eol)
  lines <- strsplit(text, eol, fixed = TRUE)[[1]]

  header <- unquote(split_fields(lines[1], 1))
  id_i <- which(header == "ID")
  if (length(id_i) != 1) stop("the export has no single ID column", call. = FALSE)
  # Assignment columns are the ones Canvas tags with an id in parentheses;
  # identity and read-only total columns never carry one.
  assignment <- grepl("\\([0-9]+\\)$", header)
  rows <- lapply(seq_along(lines)[-1], function(i) split_fields(lines[i], i))
  ids <- vapply(rows, function(f) if (length(f) >= id_i) unquote(f[id_i]) else "", "")

  plan <- lapply(seq_len(nrow(targets)), function(t) {
    column <- targets$column[t]
    hit <- which(assignment & grepl(tolower(column), tolower(header), fixed = TRUE))
    if (!length(hit)) {
      stop("no gradebook column matches '", column, "'. Assignment columns: ",
           paste(header[assignment], collapse = " | "), call. = FALSE)
    }
    if (length(hit) > 1) {
      stop("'", column, "' matches more than one gradebook column: ",
           paste(header[hit], collapse = " | "), call. = FALSE)
    }
    sp <- targets$scores[t]
    if (is.na(sp) || !nzchar(sp)) sp <- find_scores_file(targets$folder[t])
    sc <- read_scores(sp, key_path)
    if (any(!sc$canvas_id %in% ids)) {
      stop(basename(targets$folder[t]), ": ", sum(!sc$canvas_id %in% ids),
           " score(s) belong to a student not in the gradebook export; download a fresh gradebook",
           call. = FALSE)
    }
    list(hit = hit, sc = sc)
  })
  hits <- vapply(plan, `[[`, 0L, "hit")
  if (anyDuplicated(hits)) {
    stop("two assignments in the map point at the same column: ",
         paste(unique(header[hits[duplicated(hits)]]), collapse = " | "), call. = FALSE)
  }

  report <- character()
  for (p in plan) {
    filled <- 0L; replaced <- 0L
    for (j in seq_along(rows)) {
      m <- match(ids[j], p$sc$canvas_id)
      if (is.na(m)) next
      if (length(rows[[j]]) != length(header)) {
        stop("line ", j + 1, " of the export has the wrong number of fields", call. = FALSE)
      }
      if (nzchar(rows[[j]][p$hit])) replaced <- replaced + 1L
      rows[[j]][p$hit] <- sprintf("%.2f", p$sc$total[m])
      filled <- filled + 1L
    }
    report <- c(report, sprintf("  %d student(s) in '%s'%s", filled, header[p$hit],
                                if (replaced) sprintf(" (%d replaced an existing value)", replaced) else ""))
  }
  touched <- vapply(seq_along(rows), function(j) {
    any(vapply(plan, function(p) ids[j] %in% p$sc$canvas_id, TRUE))
  }, TRUE)
  lines[which(touched) + 1] <- vapply(rows[touched], paste, "", collapse = ",")

  body <- paste(lines, collapse = eol)
  if (final_eol) body <- paste0(body, eol)
  payload <- charToRaw(body)
  if (bom) payload <- c(as.raw(c(0xEF, 0xBB, 0xBF)), payload)
  writeBin(payload, out)

  cat(basename(out), ": filled", length(plan), "assignment(s); every other cell is unchanged\n")
  cat(report, sep = "\n")
  invisible(out)
}

#' Fill scores into a Canvas gradebook export for re-import
#'
#' Write `canvas_import.csv`, a copy of a freshly downloaded Canvas gradebook
#' export with one or more assignments' scores filled in, ready for the
#' Gradebook's Import. Canvas accepts only an import that is exactly its own
#' export, so the file is edited as bytes rather than parsed and rewritten:
#' quoting, line endings, a byte-order mark, the final newline or its absence,
#' number formats, read-only columns and letter grades are all kept, and the
#' only bytes that change are the target assignments' cells on the rows of
#' students who have a score. A filled score is written with two decimals, as
#' Canvas writes its own. A student with no score keeps whatever the export
#' had, and the input export is never modified.
#'
#' The assignments to fill come from a map, or from one `folder` and `column`.
#' A target column is the single assignment column, one Canvas tags with an id
#' in parentheses, whose header contains `column` as text, ignoring case.
#' Identity and read-only total columns are never targets. Scores come from the
#' map's `scores` column or `scores` when given; otherwise from the one
#' `*_scores.csv` in the folder that [relink()] wrote, or failing that from
#' `anon/scores.csv` in it. A scores file needs a `total` column and either a
#' Canvas id column (`canvas_id` or `canvas_user_id`) or a `code` column, which
#' is placed through `key`.
#'
#' Every assignment is resolved and checked before anything is written, so a
#' failing one leaves no file. It stops when the output file already exists,
#' when a column text matches no column or more than one, when two assignments
#' point at the same column, when a score belongs to a student who is not in
#' the export, when a total is not a number, when a code is not in the key,
#' when a student is listed twice, and when a quoted field spans lines, rather
#' than guessing. Messages print counts and column headers, never a student's
#' name or id.
#'
#' @param proj Course project root. Relative paths are resolved against it,
#'   including the folders and scores files named inside a map.
#' @param gradebook The Canvas gradebook export, downloaded fresh, so every
#'   student scored is in it.
#' @param map A CSV with one row per assignment and columns `folder` and
#'   `column`, plus an optional `scores` naming a scores file when a folder
#'   holds more than one. Give either `map`, or `folder` with `column`.
#' @param folder One assignment's folder, used with `column`.
#' @param column Text that picks out the assignment's gradebook column, such as
#'   `"Case Study 3"`.
#' @param scores A scores file for `folder`, when the folder holds more than
#'   one or its scores are elsewhere.
#' @param key The anonymization key [anon_key()] wrote, needed only when scores
#'   are keyed by code.
#' @param out The file to write. `NULL` means `canvas_import.csv` beside
#'   `gradebook`. An existing file is never overwritten.
#' @return The path written, invisibly.
#' @seealso [anon_key()], [anonymize()], [relink()]
#' @examples
#' p <- tempfile("course-"); dir.create(p)
#' writeLines(c(
#'   "Student,ID,SIS User ID,SIS Login ID,Section,Essay 1 (101),Current Score",
#'   "    Points Possible,,,,,10.00,(read only)",
#'   "\"Quill, Pat\",1001,U1,XQ1001,01,,0.00"), file.path(p, "export.csv"))
#' dir.create(file.path(p, "Essay1"))
#' write.csv(data.frame(canvas_id = "1001", total = "9"),
#'           file.path(p, "Essay1", "essay1_scores.csv"), row.names = FALSE)
#' canvas_grades(p, "export.csv", folder = "Essay1", column = "Essay 1")
#' readLines(file.path(p, "canvas_import.csv"))
#' unlink(p, recursive = TRUE)
#' @export
canvas_grades <- function(proj, gradebook, map = NULL, folder = NULL, column = NULL,
                          scores = NULL, key = NULL, out = NULL) {
  proj <- anon_proj(proj)
  given <- function(x) !is.null(x) && length(x) == 1L && !is.na(x) && nzchar(x)
  if (given(map) && (given(folder) || given(column))) {
    stop("give map, or folder with column, not both", call. = FALSE)
  }
  targets <- if (given(map)) {
    read_map(proj_path(proj, map))
  } else if (given(folder) && given(column)) {
    data.frame(folder = folder, column = column,
               scores = if (given(scores)) scores else "", stringsAsFactors = FALSE)
  } else {
    stop("give map, or folder with column", call. = FALSE)
  }
  targets$folder <- vapply(targets$folder, function(f) proj_path(proj, f), "",
                           USE.NAMES = FALSE)
  targets$scores <- vapply(targets$scores, function(s) {
    if (is.na(s) || !nzchar(s)) "" else proj_path(proj, s)
  }, "", USE.NAMES = FALSE)
  res <- fill_gradebook(proj_path(proj, gradebook), targets,
                        out = if (given(out)) proj_path(proj, out) else NULL,
                        key_path = if (given(key)) proj_path(proj, key) else NULL)
  version_line("canvas_grades")
  invisible(res)
}
