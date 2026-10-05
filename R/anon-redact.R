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
    n <- n + sum(vapply(hits, function(h) sum(h > 0, na.rm = TRUE), integer(1)))
    text <- gsub(p, terms$code[i], text, perl = TRUE, ignore.case = TRUE)
  }
  list(text = text, n = n)
}

# The user folder in a home-directory path becomes USER, in the macOS, Linux
# and Windows spellings, and an email address becomes EMAIL. The patterns are
# case-insensitive and spelled in lower case, with one bracketed letter, so the
# package's own absolute-path audit does not read them as paths.
redact_paths <- function(text, counts = FALSE) {
  p1 <- "(?i)(/users/|/hom[e]/)[^/\\\\\\s]+"
  # One or more backslashes between parts: pandoc doubles them in .docx prose.
  p2 <- "(?i)([A-Za-z]:(?:\\\\)+Users(?:\\\\)+)[^\\\\\\s]+"
  p3 <- "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
  cnt <- function(p) sum(vapply(gregexpr(p, text, perl = TRUE),
                                function(h) sum(h > 0, na.rm = TRUE), integer(1)))
  n_path <- cnt(p1) + cnt(p2)
  n_email <- cnt(p3)
  text <- gsub(p1, "\\1USER", text, perl = TRUE)
  text <- gsub(p2, "\\1USER", text, perl = TRUE)
  text <- gsub(p3, "EMAIL", text, perl = TRUE)
  if (isTRUE(counts)) {
    list(text = text, counts = c(PATH = n_path, EMAIL = n_email))
  } else {
    text
  }
}

# Fixed patterns that identify a person without naming them. Applied before
# the name redaction, to document text and to OCR text. Each match becomes a
# bracketed type token; counts are reported by type, never the value.
STREET_TYPES <- c("Street","St","Avenue","Ave","Road","Rd","Drive","Dr","Lane",
                  "Ln","Boulevard","Blvd","Court","Ct","Way","Place","Pl",
                  "Circle","Cir","Trail","Trl","Parkway","Pkwy","Highway","Hwy")

# Each entry: the pattern and its replacement. DOB keeps its label ("born on",
# "DOB:") and replaces only the date; PCRE has no variable-length lookbehind,
# so the label is captured and written back as \\1\\2.
PII_PATTERNS <- list(
  SSN   = list(p = "(?<![0-9-])[0-9]{3}-[0-9]{2}-[0-9]{4}(?![0-9-])", r = "[SSN]"),
  # A bare space never separates the unparenthesized form, and both of its
  # separators must be the same: "105 230 1450" in R output is not a phone.
  PHONE = list(p = paste0("(?<![0-9.\\-])(?:\\+?1[ .\\-]?)?",
                          "(?:\\([0-9]{3}\\)\\s?[0-9]{3}[ .\\-]|[0-9]{3}([.\\-])[0-9]{3}\\1)",
                          "[0-9]{4}(?![0-9\\-]|\\.[0-9])"),
               r = "[PHONE]"),
  DOB   = list(p = paste0("(?i)\\b(born(?: on)?|dob|d\\.o\\.b\\.|date of birth|birthday)([:\\s]{1,3})",
                          "(?:[0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4}|[0-9]{4}-[0-9]{2}-[0-9]{2}|",
                          "(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\\.?\\s+[0-9]{1,2},?\\s+[0-9]{4})"),
               r = "\\1\\2[DOB]"),
  PROFILE = list(p = paste0("(?i)(?<![A-Za-z0-9.\\-])(?:https?://)?(?:www\\.)?",
                            "(?:github\\.com|linkedin\\.com/in|twitter\\.com|x\\.com|instagram\\.com|",
                            "facebook\\.com|tiktok\\.com/@?|youtube\\.com/(?:@|c/|channel/|user/))",
                            "/?[A-Za-z0-9_.\\-]+/?"),
                 r = "[PROFILE]"),
  # Not a handle: an email or slot (word character, "@" or "." before it), a
  # citation ("[@smith2020; @lee2019]") or a Quarto cross-reference
  # ("@fig-scatter", a "-" after it). Roxygen lines are skipped in
  # redact_patterns().
  HANDLE = list(p = "(?<![A-Za-z0-9_@.)\\]\\[;])(?<!;\\s)@[A-Za-z0-9_]{2,30}\\b(?!-)",
                r = "[HANDLE]"),
  ADDRESS = list(p = paste0("\\b[0-9]{1,6}\\s+(?:[NSEW]\\.?\\s+)?",
                            "(?:(?!(?:", paste(STREET_TYPES, collapse = "|"), ")\\b)[A-Z][a-z]+\\s+){1,3}",
                            "(?:", paste(STREET_TYPES, collapse = "|"), ")\\b\\.?"),
                 r = "[ADDRESS]")
)

redact_patterns <- function(text) {
  counts <- integer(0)
  for (type in names(PII_PATTERNS)) {
    p <- PII_PATTERNS[[type]]$p
    # "#' @param" in an R script is roxygen, not a handle.
    idx <- if (type == "HANDLE") !grepl("^\\s*#'", text) else rep(TRUE, length(text))
    hits <- gregexpr(p, text[idx], perl = TRUE)
    counts[type] <- sum(vapply(hits, function(h) sum(h > 0, na.rm = TRUE), integer(1)))
    text[idx] <- gsub(p, PII_PATTERNS[[type]]$r, text[idx], perl = TRUE)
  }
  list(text = text, counts = counts)
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
