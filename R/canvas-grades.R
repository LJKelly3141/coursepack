# Fill assignment scores into a narrow Canvas gradebook import.
#
# Canvas writes back every cell an import carries and reads a blank cell as a
# deletion, but leaves alone any assignment column the import does not carry.
# So the import keeps the identity columns and the mapped assignment columns
# only, and drops every other column. It is cut from the downloaded export as
# text, field by position: every kept byte is the export's own (quoting, line
# endings, a byte-order mark, the Points Possible row's leading spaces, every
# row including the Test Student) except the target cells on the rows of
# students who have a score. Identity lives only in that export and in the
# assignment's key, on this machine; the grader's output only ever carried
# scores and codes.
#
# Exports are read and imports are written, and the two never share a folder:
# the output goes to import_dir, never beside the export or any assignment.
# The default import_dir takes only the term from the export's path.
# Messages print counts, column headers and folder paths, never a student's
# name or id.

IDENTITY_COLUMNS <- c("Student", "ID", "SIS User ID", "SIS Login ID",
                      "Integration ID", "Root Account", "Section")

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
# Scores keyed by code are placed through the folder's own key, or through
# key_path when given, and either way only a key of this folder's run.
read_scores <- function(scores_path, folder, proj, key_path = NULL) {
  s <- utils::read.csv(scores_path, colClasses = "character", check.names = FALSE,
                       na.strings = character())
  if (!"total" %in% names(s)) stop(basename(scores_path), " has no total column", call. = FALSE)
  id_col <- intersect(c("canvas_id", "canvas_user_id"), names(s))
  if (length(id_col)) {
    ids <- s[[id_col[1]]]
  } else if ("code" %in% names(s)) {
    if (is.null(key_path) || !nzchar(key_path)) key_path <- file.path(folder, KEY_FILE)
    if (!file.exists(key_path)) {
      stop(basename(folder), ": scores keyed by code need this assignment's key to be ",
           "placed, and there is none at ", key_path, call. = FALSE)
    }
    k <- check_run(read_key(key_path), key_path, run_id(proj, folder))
    ids <- k$canvas_id[match(s$code, k$code)]
    if (anyNA(ids)) {
      stop(sum(is.na(ids)), " code(s) in ", basename(scores_path), " are not in the key",
           call. = FALSE)
    }
  } else {
    stop(basename(scores_path), " has neither a Canvas id column nor a code column",
         call. = FALSE)
  }
  # A blank id would match the export's Points Possible row and any other row
  # Canvas writes without a student id.
  blank <- (is.na(ids) | !nzchar(trimws(ids))) & nzchar(trimws(s$total))
  if (any(blank)) {
    stop(sum(blank), " score(s) in ", basename(scores_path), " have a blank student id",
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

# The default import name: dated, and named for the one folder filled or for
# how many were.
import_name <- function(targets) {
  what <- if (nrow(targets) == 1L) basename(targets$folder) else
    sprintf("%d-assignments", nrow(targets))
  sprintf("%s_%s_import.csv", format(Sys.Date(), "%Y-%m-%d"), what)
}

# A path made absolute and canonical even where it does not exist yet: the
# deepest part that exists is normalized (resolving links, so /var and
# /private/var agree on macOS) and the rest is appended as written.
resolve_path <- function(p) {
  p <- normalizePath(p, winslash = "/", mustWork = FALSE)
  rest <- character()
  while (!file.exists(p) && dirname(p) != p) {
    rest <- c(basename(p), rest)
    p <- dirname(p)
  }
  p <- normalizePath(p, winslash = "/", mustWork = FALSE)
  sub("/+$", "", do.call(file.path, as.list(c(p, rest))))
}

# A path relative to proj, or the resolved path when it is outside proj.
proj_rel <- function(proj, p) {
  rp <- resolve_path(p); pp <- resolve_path(proj)
  if (startsWith(rp, paste0(pp, "/"))) substring(rp, nchar(pp) + 2L) else rp
}

# The term a path sits in: the folder name right after semester/ in its path
# relative to proj, or NA. For a file, only the folders it sits in count, so
# semester/export.csv has no term.
path_term <- function(proj, p, is_file = FALSE) {
  rp <- resolve_path(p); pp <- resolve_path(proj)
  if (!startsWith(rp, paste0(pp, "/"))) return(NA_character_)
  parts <- strsplit(substring(rp, nchar(pp) + 2L), "/", fixed = TRUE)[[1]]
  if (is_file) parts <- utils::head(parts, -1L)
  if (length(parts) >= 2L && parts[1] == "semester" && nzchar(parts[2])) parts[2] else
    NA_character_
}

# The default import folder, semester/<term>/gradebook_import under proj. Only
# the term is read from the input paths, never a folder to write in. The export
# and every assignment folder must sit in one term, or it stops listing what it
# found: paths and terms, nothing else.
term_import_dir <- function(proj, gradebook_csv, folders) {
  term <- path_term(proj, gradebook_csv, is_file = TRUE)
  fterms <- vapply(folders, function(f) path_term(proj, f), "", USE.NAMES = FALSE)
  if (!is.na(term) && all(!is.na(fterms) & fterms == term)) {
    return(file.path(proj, "semester", term, "gradebook_import"))
  }
  shown <- function(t) ifelse(is.na(t), "(none)", t)
  found <- c(sprintf("  export %s: term %s", proj_rel(proj, gradebook_csv), shown(term)),
             sprintf("  folder %s: term %s",
                     vapply(folders, function(f) proj_rel(proj, f), "", USE.NAMES = FALSE),
                     shown(fterms)))
  why <- if (is.na(term)) "the export is not under semester/<term>/ in proj" else
    "the export and the assignment folders are not all in one term"
  stop("cannot name the default import folder: ", why, ". The default is ",
       "semester/<term>/gradebook_import, with the term read from the export's path; ",
       "keep the export and every assignment folder under one semester/<term>/, or ",
       "pass import_dir or out. Found:\n", paste(found, collapse = "\n"), call. = FALSE)
}

# targets: data.frame(folder, column, scores), paths already resolved. Writes
# one narrow import file to `out`, or to import_dir under import_name(). Every
# target is resolved and validated before a byte is written, so a failing
# assignment leaves no file behind. The output path is never derived from the
# export's own folder.
fill_gradebook <- function(gradebook_csv, targets, proj, import_dir, out = NULL,
                           key_path = NULL, overwrite = FALSE) {
  if (!nrow(targets)) stop("no assignments to fill", call. = FALSE)
  if (is.null(out) || !nzchar(out)) out <- file.path(import_dir, import_name(targets))
  # The export's folder holds only Canvas downloads: nothing is written into
  # it or into any folder below it. Checked on the intended path, before any
  # folder is created.
  out_dir <- resolve_path(dirname(out))
  export_dir <- resolve_path(dirname(gradebook_csv))
  inside <- identical(out_dir, export_dir) ||
    startsWith(paste0(out_dir, "/"), paste0(sub("/+$", "", export_dir), "/"))
  same_file <- identical(resolve_path(out), resolve_path(gradebook_csv))
  if (inside || same_file) {
    stop("the import would be written to ", dirname(out), ", inside the export's own ",
         "folder; exports and imports must live in different folders. Keep exports in ",
         "their own folder, such as semester/<term>/gradebook_export, or point ",
         "import_dir or out elsewhere.", call. = FALSE)
  }
  if (file.exists(out) && !isTRUE(overwrite)) {
    stop(out, " already exists; pass overwrite = TRUE to replace it, for a re-run ",
         "after a ruling", call. = FALSE)
  }
  if (!file.exists(gradebook_csv)) stop("no gradebook export at ", gradebook_csv, call. = FALSE)

  bytes <- readBin(gradebook_csv, "raw", file.info(gradebook_csv)$size)
  bom <- length(bytes) >= 3 && identical(bytes[1:3], as.raw(c(0xEF, 0xBB, 0xBF)))
  if (bom) bytes <- bytes[-(1:3)]
  text <- rawToChar(bytes)
  eol <- if (grepl("\r\n", text, fixed = TRUE)) "\r\n" else "\n"
  final_eol <- endsWith(text, eol)
  lines <- strsplit(text, eol, fixed = TRUE)[[1]]

  raw_header <- split_fields(lines[1], 1)
  header <- unquote(raw_header)
  id_i <- which(header == "ID")
  if (length(id_i) != 1) stop("the export has no single ID column", call. = FALSE)
  # Assignment columns are the ones Canvas tags with an id in parentheses;
  # identity and read-only total columns never carry one.
  assignment <- grepl("\\([0-9]+\\)$", header)
  rows <- lapply(seq_along(lines)[-1], function(i) split_fields(lines[i], i))
  # Fields are dropped by position, so every row must line up with the header.
  for (j in seq_along(rows)) {
    if (length(rows[[j]]) != length(header)) {
      stop("line ", j + 1, " of the export has the wrong number of fields", call. = FALSE)
    }
  }
  ids <- vapply(rows, function(f) unquote(f[id_i]), "")

  plan <- lapply(seq_len(nrow(targets)), function(t) {
    folder <- targets$folder[t]
    if (!dir.exists(folder)) stop("no assignment folder at ", folder, call. = FALSE)
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
    if (is.na(sp) || !nzchar(sp)) sp <- find_scores_file(folder)
    sc <- read_scores(sp, folder, proj, key_path)
    if (any(!sc$canvas_id %in% ids)) {
      stop(basename(folder), ": ", sum(!sc$canvas_id %in% ids),
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
      # Only a student row carries a numeric Canvas id; Points Possible and
      # any other row Canvas adds never take a score.
      if (!grepl("^[0-9]+$", ids[j])) next
      m <- match(ids[j], p$sc$canvas_id)
      if (is.na(m)) next
      if (nzchar(rows[[j]][p$hit])) replaced <- replaced + 1L
      rows[[j]][p$hit] <- sprintf("%.2f", p$sc$total[m])
      filled <- filled + 1L
    }
    report <- c(report, sprintf("  %d student(s) in '%s'%s", filled, header[p$hit],
                                if (replaced) sprintf(" (%d replaced an existing value)", replaced) else ""))
  }

  # Identity columns and the mapped assignment columns, in the export's order.
  id_cols <- which(header %in% IDENTITY_COLUMNS)
  keep <- sort(unique(c(id_cols, hits)))
  narrow <- c(paste(raw_header[keep], collapse = ","),
              vapply(rows, function(f) paste(f[keep], collapse = ","), ""))
  body <- paste(narrow, collapse = eol)
  if (final_eol) body <- paste0(body, eol)
  payload <- charToRaw(body)
  if (bom) payload <- c(as.raw(c(0xEF, 0xBB, 0xBF)), payload)
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  writeBin(payload, out)

  cat(sprintf("%s: filled %d assignment(s); kept %d identity and %d assignment column(s) and all %d row(s), dropped %d other column(s)\n",
              basename(out), length(plan), length(id_cols), length(hits), length(rows),
              length(header) - length(keep)))
  cat(report, sep = "\n")
  invisible(out)
}

#' Fill scores into a narrow Canvas gradebook import
#'
#' Write a gradebook import for the Gradebook's Import that carries the
#' identity columns and the scored assignments' columns, and nothing else.
#' Canvas writes back every cell an import carries and reads a blank cell as a
#' deletion, so a full-width import can roll back grades in other columns. It
#' leaves alone any assignment column the import does not carry, so this file
#' carries only what is being graded.
#'
#' The import is cut from a downloaded Canvas gradebook export as text. It
#' keeps the identity columns the export has (`Student`, `ID`, `SIS User ID`,
#' `SIS Login ID`, `Integration ID`, `Root Account`, `Section`) and the
#' assignment columns named
#' in the map, in the export's order, and drops every other column: other
#' assignments and all the read-only group, total and grade columns. It keeps
#' the header row, the `Points Possible` row with its leading spaces as Canvas
#' writes them, and every data row, including Canvas's Test Student. Every
#' kept cell is the export's own bytes except the target cells on the rows of
#' students who have a score: quoting, line endings, a byte-order mark and the
#' final newline or its absence are all kept. A filled score is written with
#' two decimals, as Canvas writes its own. A student with no score keeps
#' whatever the export had in the kept columns, and the export is never
#' modified.
#'
#' Exports go in one folder and imports in another: the function reads the
#' export and writes only the import, into `import_dir`, and never writes into
#' the folder the export sits in or into any assignment folder: an `out` or
#' `import_dir` in the export's own folder or any folder below it, or `out`
#' naming the export itself,
#' stops the call, whatever `overwrite` says. Only rows whose `ID` is a Canvas
#' id, all digits, ever take a score, so the `Points Possible` row and any
#' other row Canvas writes without a student id are kept as they are.
#'
#' The default `import_dir` is `semester/<term>/gradebook_import` under `proj`.
#' Only the term is read from the input paths, never a folder to write in: the
#' term is the folder name right after `semester/` in the export's path
#' relative to `proj`, so an export at
#' `semester/fall2026/gradebook_export/export.csv` is in term `fall2026`, and
#' every assignment folder, from the map or `folder`, must be in the same term.
#' When the export is not under `semester/<term>/`, or an assignment folder is
#' in another term or in none, the call stops and lists each path with the
#' term found; it never falls back to a folder without a term. An `import_dir`
#' or `out` given explicitly is used as given and no term is read. An export
#' directly in `semester/<term>/` stops at the guard above, because the
#' derived folder would be below the export's own; keep exports in
#' `semester/<term>/gradebook_export/`. The default
#' name is `<YYYY-MM-DD>_<folder>_import.csv` for one assignment, named for its
#' folder, or `<YYYY-MM-DD>_<N>-assignments_import.csv` for several. Download
#' the export right before importing, so every student scored is in it.
#'
#' The assignments to fill come from a map, or from one `folder` and `column`.
#' A target column is the single assignment column, one Canvas tags with an id
#' in parentheses, whose header contains `column` as text, ignoring case.
#' Identity and read-only total columns are never targets. Scores come from the
#' map's `scores` column or `scores` when given; otherwise from the one
#' `*_scores.csv` in the folder that [relink()] wrote, or failing that from
#' `anon/scores.csv` in it. A scores file needs a `total` column and either a
#' Canvas id column (`canvas_id` or `canvas_user_id`) or a `code` column.
#' Codes are placed through the folder's own `anon_key.csv`, the key
#' [anon_key()] built for that assignment, so no `key` is needed.
#'
#' Every assignment is resolved and checked before anything is written, so a
#' failing one leaves no file. It stops when the default import folder cannot
#' be named because the paths are not in one term, when the output file already exists and
#' `overwrite` is `FALSE`, when a mapped folder does not exist, when a column
#' text matches no column or more than one, when two assignments point at the
#' same column, when a score belongs to a student who is not in the export,
#' when a scores row with a total has a blank student id, when a total is
#' not a number, when coded scores have no key or a key of
#' another run, when a code is not in the key, when a student is listed twice,
#' when a row does not have as many fields as the header, and when a quoted
#' field spans lines, rather than guessing. Messages print counts, column
#' headers and folder paths, never a student's name or id.
#'
#' @param proj Course project root. Relative paths are resolved against it,
#'   including the folders and scores files named inside a map.
#' @param gradebook The Canvas gradebook export, downloaded fresh, so every
#'   student scored is in it. Keep exports in their own folder, such as
#'   `semester/<term>/gradebook_export/`; nothing is written there.
#' @param map A CSV with one row per assignment and columns `folder` and
#'   `column`, plus an optional third column `scores` naming a scores file for
#'   that row, for a folder that holds more than one or whose scores are
#'   elsewhere; a blank `scores` cell means the default search. Give either
#'   `map`, or `folder` with `column`.
#' @param folder One assignment's folder, used with `column`.
#' @param column Text that picks out the assignment's gradebook column, such as
#'   `"Case Study 3"`.
#' @param scores A scores file for `folder`, when the folder holds more than
#'   one or its scores are elsewhere.
#' @param key Rarely needed. Coded scores are placed through the folder's own
#'   `anon_key.csv`; a key given here is used instead, and only when its `run`
#'   is that folder.
#' @param out The file to write, a full path that overrides `import_dir` and
#'   the default name.
#' @param import_dir The folder imports are written to, created when missing.
#'   When it and `out` are both `NULL`, it is `semester/<term>/gradebook_import`
#'   under `proj`, with the term read from the export's path.
#' @param overwrite `FALSE` stops when the output file already exists. `TRUE`
#'   replaces it, for a re-run after a ruling.
#' @return The path written, invisibly.
#' @seealso [anon_key()], [anonymize()], [relink()], [anon_forget()]
#' @examples
#' p <- tempfile("course-"); dir.create(p)
#' dir.create(file.path(p, "semester", "fall2026", "gradebook_export"), recursive = TRUE)
#' writeLines(c(
#'   "Student,ID,SIS User ID,SIS Login ID,Section,Essay 1 (101),Quiz 1 (102),Current Score",
#'   "    Points Possible,,,,,10.00,5.00,(read only)",
#'   "\"Quill, Pat\",1001,U1,XQ1001,01,,4.00,0.00"),
#'   file.path(p, "semester", "fall2026", "gradebook_export", "export.csv"))
#' dir.create(file.path(p, "semester", "fall2026", "Essay1"))
#' write.csv(data.frame(canvas_id = "1001", total = "9"),
#'           file.path(p, "semester", "fall2026", "Essay1", "essay1_scores.csv"),
#'           row.names = FALSE)
#' # Written to semester/fall2026/gradebook_import/
#' out <- canvas_grades(p, "semester/fall2026/gradebook_export/export.csv",
#'                      folder = "semester/fall2026/Essay1", column = "Essay 1")
#' readLines(out)
#' unlink(p, recursive = TRUE)
#' @export
canvas_grades <- function(proj, gradebook, map = NULL, folder = NULL, column = NULL,
                          scores = NULL, key = NULL, out = NULL,
                          import_dir = NULL, overwrite = FALSE) {
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
  gradebook_csv <- proj_path(proj, gradebook)
  import_dir <- if (given(import_dir)) {
    proj_path(proj, import_dir)
  } else if (given(out)) {
    ""
  } else {
    term_import_dir(proj, gradebook_csv, targets$folder)
  }
  res <- fill_gradebook(gradebook_csv, targets, proj, import_dir = import_dir,
                        out = if (given(out)) proj_path(proj, out) else NULL,
                        key_path = if (given(key)) proj_path(proj, key) else NULL,
                        overwrite = overwrite)
  version_line("canvas_grades")
  invisible(res)
}
