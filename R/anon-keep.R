# Protected phrases. <proj>/anon_keep.txt lists whole phrases, one per line,
# that are never redacted: the instructor's or a TA's name as it appears in a
# heading ("Dr. Avery Thorn"). A phrase must have at least two words, so a
# single name is never protected: a student who shares the instructor's first
# name is still redacted wherever that name stands alone. Lines starting with
# "#" and blank lines are skipped. The file is read, never written.
#
# Protection applies to the name checks only (name redaction, the image name
# check, the leftover check). Path, email and fixed-pattern checks still see
# the full text.

keep_path <- function(proj) file.path(proj, "anon_keep.txt")

# An error names the line number only, never the line's text: the line may be
# a name. The result carries each phrase's line number in attr "line", for
# check_keep_phrases().
read_keep_phrases <- function(proj) {
  p <- keep_path(proj)
  if (!file.exists(p)) return(character())
  lines <- readLines(p, warn = FALSE, encoding = "UTF-8")
  if (length(lines)) lines[1] <- sub("^\ufeff", "", lines[1])
  lines <- trimws(lines)
  out <- character(); at <- integer()
  for (i in seq_along(lines)) {
    l <- lines[i]
    if (!nzchar(l) || startsWith(l, "#")) next
    if (!grepl("\\s", l)) {
      stop(sprintf(paste0("anon_keep.txt line %d: a protected phrase needs at least ",
                          "two words; a single name is never protected. Fix the line ",
                          "and re-run."), i), call. = FALSE)
    }
    if (l %in% out) next
    out <- c(out, l); at <- c(at, i)
  }
  structure(out, line = at)
}

# A phrase holding a student's multi-word name form (the same filter as
# foreign_terms()), login or Canvas id would exempt that student from
# redaction and blind the leftover check. Refused by line number only. A single
# first or last name is allowed: the instructor may share it with a student,
# and that student's standalone name is still redacted.
check_keep_phrases <- function(keep, key) {
  if (!length(keep)) return(invisible(TRUE))
  forms <- unlist(lapply(c(key$name_forms, key$nicknames), split_list))
  forms <- forms[grepl("[ ,]", forms)]
  bad <- c(forms, key$login, key$canvas_id)
  bad <- unique(gsub("\\s+", " ", trimws(bad[!is.na(bad) & nchar(trimws(bad)) >= 2])))
  lines <- attr(keep, "line")
  if (is.null(lines)) lines <- seq_along(keep)
  for (i in seq_along(keep)) {
    ph <- gsub("\\s+", " ", keep[i])
    for (b in bad) {
      if (grepl(word_rx(b), ph, perl = TRUE, ignore.case = TRUE)) {
        stop(sprintf("anon_keep.txt line %d contains a student's name or id; remove it",
                     lines[i]), call. = FALSE)
      }
    }
  }
  invisible(TRUE)
}

# Any whitespace run in the text matches a space in the phrase (a double
# space, a tab, a line break; redact_lines() joins a file's lines so a phrase
# split across two lines still matches). Boundaries follow word_rx(): letters, or letters and digits when the
# phrase holds a digit.
keep_rx <- function(phrase) {
  words <- strsplit(trimws(phrase), "\\s+", perl = TRUE)[[1]]
  body <- paste(rx_escape(words), collapse = "\\s+")
  b <- if (grepl("[0-9]", phrase)) "A-Za-z0-9" else "A-Za-z"
  paste0("(?<![", b, "])", body, "(?![", b, "])")
}

# The mask for occurrence j: \u0002, j in base 6400 as private-use code points
# (U+E000 to U+F8FF), \u0002. No ASCII letter or digit, so no key term (a
# Canvas id, a login) can match inside it through word_rx(), and no overlap
# with redact_text()'s \u0001 sentinel.
KEEP_BASE <- 6400L
keep_token <- function(j) {
  vapply(j, function(x) {
    d <- integer()
    repeat {
      d <- c(x %% KEEP_BASE, d)
      x <- x %/% KEEP_BASE
      if (x == 0) break
    }
    paste0("\u0002", intToUtf8(0xE000 + d), "\u0002")
  }, character(1))
}

KEEP_TOKEN_RX <- "\u0002[\\x{E000}-\\x{F8FF}]+\u0002"

keep_index <- function(tok) {
  d <- utf8ToInt(gsub("\u0002", "", tok, fixed = TRUE)) - 0xE000
  sum(d * KEEP_BASE^(rev(seq_along(d)) - 1))
}

ordered_keep <- function(keep) keep[order(-nchar(keep))]

# Each protected occurrence becomes its own mask; the matched text is stored
# in order so unmask_keep() restores it exactly (case and spacing included).
mask_keep <- function(text, keep) {
  orig <- character()
  for (ph in ordered_keep(keep)) {
    m <- gregexpr(keep_rx(ph), text, perl = TRUE, ignore.case = TRUE)
    hits <- regmatches(text, m)
    if (!sum(lengths(hits))) next
    tokens <- vector("list", length(hits))
    for (i in seq_along(hits)) {
      h <- hits[[i]]
      j <- length(orig) + seq_along(h)
      orig <- c(orig, h)
      tokens[[i]] <- if (length(h)) keep_token(j) else character()
    }
    regmatches(text, m) <- tokens
  }
  list(text = text, n = length(orig), orig = orig)
}

unmask_keep <- function(text, masked_from) {
  orig <- masked_from$orig
  if (!length(orig)) return(text)
  m <- gregexpr(KEEP_TOKEN_RX, text, perl = TRUE)
  hits <- regmatches(text, m)
  regmatches(text, m) <- lapply(hits, function(h) {
    vapply(h, function(tok) {
      j <- keep_index(tok)
      if (j >= 1 && j <= length(orig)) orig[j] else tok
    }, character(1), USE.NAMES = FALSE)
  })
  text
}

# Name redaction over one file's lines. The lines are joined with "\n" so a
# protected phrase split across two lines is masked whole, then split back:
# the file keeps its line structure exactly. No key term holds a line break,
# so the redaction count is the same as line by line.
redact_lines <- function(lines, terms, keep) {
  if (!length(lines)) return(list(text = lines, n = 0L, kept = 0L))
  mk <- mask_keep(paste(lines, collapse = "\n"), keep)
  red <- redact_text(mk$text, terms)
  out <- strsplit(paste0(unmask_keep(red$text, mk), "\n"), "\n", fixed = TRUE)[[1]]
  list(text = out, n = red$n, kept = mk$n)
}

# For checks only: each protected occurrence becomes one space, so the name
# check never sees it and the words around it stay apart.
drop_keep <- function(text, keep) {
  for (ph in ordered_keep(keep)) {
    text <- gsub(keep_rx(ph), " ", text, perl = TRUE, ignore.case = TRUE)
  }
  text
}
