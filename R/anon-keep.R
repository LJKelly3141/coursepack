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
    if (!grepl("[^\\s\\x{00A0}][\\s\\x{00A0}]+[^\\s\\x{00A0}]", l, perl = TRUE)) {
      stop(sprintf(paste0("anon_keep.txt line %d: a protected phrase needs at least ",
                          "two words; a single name is never protected. Fix the line ",
                          "and re-run."), i), call. = FALSE)
    }
    if (l %in% out) next
    out <- c(out, l); at <- c(at, i)
  }
  structure(out, line = at)
}

# A phrase holding any of a student's key terms (key_terms(): every name form,
# re-derived, joined and initial forms, nicknames, file prefix, login, Canvas
# id) would exempt that student from redaction and blind the leftover check.
# Refused by line number only. One exception: a single bare word equal to a
# student's first or last name, so an instructor who shares a first or last
# name with a student can still protect their own multi-word name; that
# student's standalone name is still redacted. The name in either order, with
# or without a comma or space, and the first initial with the surname
# ("M. Rivera", "Rivera, M.") are refused too.
check_keep_phrases <- function(keep, key, dict_path = NULL) {
  if (!length(keep)) return(invisible(TRUE))
  sp <- function(x) gsub("[\\s\\x{00A0}]+", " ", trimws(x), perl = TRUE)
  terms <- if (nrow(key)) key_terms(key, dict_path = dict_path)$term else character()
  bare <- character()
  rxs <- character()
  parts_rx <- function(x) {
    paste(rx_escape(strsplit(x, "[ -]+", perl = TRUE)[[1]]), collapse = "[ -]?")
  }
  for (i in seq_len(nrow(key))) {
    for (x in grep(",", split_list(key$name_forms[i]), fixed = TRUE, value = TRUE)) {
      p <- trimws(strsplit(x, ",", fixed = TRUE)[[1]])
      if (length(p) != 2 || !all(nzchar(p))) next
      pairs <- list(p)
      s <- strip_accents(p)
      if (length(s) == 2) pairs <- c(pairs, list(s))
      for (pr in pairs) {
        last <- pr[1]; first <- pr[2]
        bare <- c(bare, first, last, unlist(strsplit(c(first, last), "[ -]+", perl = TRUE)))
        ini <- substr(gsub("[^\\p{L}]", "", first, perl = TRUE), 1, 1)
        f <- parts_rx(first); l <- parts_rx(last)
        body <- c(paste0(f, "[ ,]*", l), paste0(l, "[ ,]*", f))
        if (nzchar(ini)) {
          body <- c(body, paste0(rx_escape(ini), "\\.? ?", l),
                    paste0(l, ",? ?", rx_escape(ini), "\\.?"))
        }
        rxs <- c(rxs, paste0("(?<![A-Za-z])(?:", body, ")(?![A-Za-z])"))
      }
    }
  }
  bare <- unique(tolower(bare))
  single <- grepl("^[\\p{L}'-]+$", terms, perl = TRUE) & tolower(terms) %in% bare
  rxs <- unique(c(rxs, vapply(sp(terms[!single]), word_rx, character(1), USE.NAMES = FALSE)))
  lines <- attr(keep, "line")
  if (is.null(lines)) lines <- seq_along(keep)
  for (i in seq_along(keep)) {
    ph <- sp(keep[i])
    for (r in rxs) {
      if (grepl(r, ph, perl = TRUE, ignore.case = TRUE)) {
        stop(sprintf("anon_keep.txt line %d contains a student's name or id; remove it",
                     lines[i]), call. = FALSE)
      }
    }
  }
  invisible(TRUE)
}

# Any whitespace run in the text matches a space in the phrase (a double
# space, a tab, a line break, a non-breaking space as Word puts in headings;
# redact_lines() joins a file's lines so a phrase split across two lines still
# matches). Boundaries follow word_rx(): letters, or letters and digits when
# the phrase holds a digit.
KEEP_SPACE_RX <- "[\\s\\x{00A0}]+"
keep_rx <- function(phrase) {
  words <- strsplit(trimws(phrase), KEEP_SPACE_RX, perl = TRUE)[[1]]
  words <- words[nzchar(words)]
  body <- paste(rx_escape(words), collapse = KEEP_SPACE_RX)
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
# protected phrase split across two lines is masked whole, then split back
# into lines for redaction and unmasking (a mask never holds a line break;
# a line vector is far faster than one long string with many hits), then
# joined and split again: the file keeps its line structure exactly. No key
# term holds a line break, so the redaction count is the same as line by
# line. Any \u0002 already in the text is dropped first, so no sequence in a
# submission can pass for a mask.
split_lines <- function(x) strsplit(paste0(x, "\n"), "\n", fixed = TRUE)[[1]]
redact_lines <- function(lines, terms, keep) {
  if (!length(lines)) return(list(text = lines, n = 0L, kept = 0L))
  lines <- gsub("\u0002", "", lines, fixed = TRUE)
  mk <- mask_keep(paste(lines, collapse = "\n"), keep)
  red <- redact_text(split_lines(mk$text), terms)
  # Unmasked line by line too (a phrase restored across a line break joins
  # back through the paste below).
  out <- split_lines(paste(unmask_keep(red$text, mk), collapse = "\n"))
  list(text = out, n = red$n, kept = mk$n)
}

# For checks only: each protected occurrence becomes \u0003, so the name
# check never sees it, the words around it stay apart, and two phrases can
# never join through it into a new match.
drop_keep <- function(text, keep) {
  for (ph in ordered_keep(keep)) {
    text <- gsub(keep_rx(ph), "\u0003", text, perl = TRUE, ignore.case = TRUE)
  }
  text
}
