# Redaction on plain text. Whole-word, case-insensitive, longest term first.
# "Whole word" treats underscores as boundaries on purpose: Canvas filenames
# glue the name prefix to ids with underscores.

rx_escape <- function(x) gsub("([.\\\\|()\\[\\]{}^$*+?])", "\\\\\\1", x, perl = TRUE)

# A term of 3+ characters with no digit is a name form: only a letter ends
# it, so "Umlauf2" and "_umlauf_" are caught. A term with a digit (an id, a
# login) keeps alphanumeric boundaries, so "1001" inside "x1001y" is left
# alone; so does a two-letter name, so "Ed" does not corrupt "3f9ed41".
word_rx <- function(term) {
  if (grepl("[0-9]", term) || nchar(term) < 3) {
    paste0("(?<![A-Za-z0-9])", rx_escape(term), "(?![A-Za-z0-9])")
  } else {
    paste0("(?<![A-Za-z])", rx_escape(term), "(?![A-Za-z])")
  }
}

redact_text <- function(text, terms) {
  n <- 0L
  for (i in seq_len(nrow(terms))) {
    p <- word_rx(terms$term[i])
    hits <- gregexpr(p, text, perl = TRUE, ignore.case = TRUE)
    n <- n + sum(vapply(hits, function(h) sum(h > 0), integer(1)))
    text <- gsub(p, terms$code[i], text, perl = TRUE, ignore.case = TRUE)
  }
  list(text = text, n = n)
}

# The user folder in a home-directory path becomes USER, in the macOS, Linux
# and Windows spellings, and an email address becomes EMAIL. The patterns are
# case-insensitive and spelled in lower case, with one bracketed letter, so the
# package's own absolute-path audit does not read them as paths.
redact_paths <- function(text) {
  text <- gsub("(?i)(/users/|/hom[e]/)[^/\\\\\\s]+", "\\1USER", text, perl = TRUE)
  # One or more backslashes between parts: pandoc doubles them in .docx prose.
  text <- gsub("(?i)([A-Za-z]:(?:\\\\)+Users(?:\\\\)+)[^\\\\\\s]+", "\\1USER",
               text, perl = TRUE)
  gsub("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", "EMAIL", text, perl = TRUE)
}

# Which files still contain a key value. Reports the code, never the value.
# Two passes. The first mirrors the redactor. The second is one it cannot
# mirror: a plain substring search, no boundaries, for every name value of
# 5+ letters once spaces and punctuation are removed ("Pat Quill" ->
# "patquill", prefixes, joined forms), so a name glued inside a longer token
# is still found. Single name words ("quill"), the first-initial+last form
# and one-word nicknames (terms$loose FALSE, set by key_terms()) are left out
# of the second pass: as substrings they hit ordinary words and would block
# every run.
loose_terms <- function(terms) {
  t <- terms[!grepl("[0-9]", terms$term), , drop = FALSE]
  if ("loose" %in% names(t)) t <- t[t$loose, , drop = FALSE]
  if (!nrow(t)) return(data.frame(term = character(), code = character()))
  squashed <- tolower(gsub("[^\\p{L}]", "", t$term, perl = TRUE))
  words <- unique(tolower(unlist(strsplit(t$term[grepl("[^\\p{L}]", t$term, perl = TRUE)],
                                          "[^\\p{L}]+", perl = TRUE))))
  keep <- nchar(squashed) >= 5 & !(squashed %in% words)
  unique(data.frame(term = squashed[keep], code = t$code[keep],
                    stringsAsFactors = FALSE))
}

find_leftovers <- function(files, terms) {
  out <- data.frame(file = character(), code = character(), stringsAsFactors = FALSE)
  loose <- loose_terms(terms)
  for (f in files) {
    txt <- paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    for (i in seq_len(nrow(terms))) {
      if (grepl(word_rx(terms$term[i]), txt, perl = TRUE, ignore.case = TRUE)) {
        out <- rbind(out, data.frame(file = f, code = terms$code[i],
                                     stringsAsFactors = FALSE))
      }
    }
    low <- tolower(txt)
    for (i in seq_len(nrow(loose))) {
      if (grepl(loose$term[i], low, fixed = TRUE)) {
        out <- rbind(out, data.frame(file = f, code = loose$code[i],
                                     stringsAsFactors = FALSE))
      }
    }
  }
  unique(out)
}
