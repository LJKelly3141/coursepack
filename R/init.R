# The scaffold's two moving parts, written before the function that uses them.
# `init_course()` renders every file in inst/templates/course/ into a new course
# directory; `leak_check()` is what the scaffolded Makefile runs after every
# render, and what a course keeps running for the rest of its life.

# ---- the template renderer -----------------------------------------------
#
# A template is plain text with {{key}} holes in it. There is no template engine
# here and no dependency on one: the keys a scaffold needs are a fixed short
# list, the substitution is literal, and the only behaviour worth having beyond
# substitution is refusing to write a file with a hole left in it.
#
# A leftover hole is a stop rather than a warning because of where the output
# goes. A rendered template is a file in a new course repository that nobody has
# read yet. `{{timezone}}` left in course.yml parses as a YAML string, passes
# every structural check, and reaches Canvas as a deadline in a zone nobody
# named; `{{site_url}}` left in modules.yml builds a cartridge whose every link
# 404s in a way that is invisible until a student clicks one. Stopping at the
# render is the last point where the defect is one character to fix.

#' Fill a template's placeholders
#'
#' Replace every `{{key}}` in `text` with the matching entry of `values`, and
#' refuse to return text that still holds a placeholder.
#'
#' Substitution is literal, not a regular expression, so a value containing a
#' backslash or a dollar sign travels unchanged. A key `values` does not carry
#' is not silently left alone: the leftover check names it and stops.
#'
#' @param text The template, as one string or as lines to be joined with
#'   newlines. An empty file renders to an empty string rather than stopping.
#' @param values A named list of replacements. Each is coerced with
#'   `as.character()`; `NULL` renders as an empty string.
#' @return The rendered text, as one string.
#' @export
render_template <- function(text, values) {
  text <- paste(as.character(text), collapse = "\n")
  for (k in names(values)) {
    v <- values[[k]]
    v <- if (is.null(v)) "" else paste(as.character(v), collapse = "")
    text <- gsub(paste0("{{", k, "}}"), v, text, fixed = TRUE)
  }
  left <- regmatches(text, gregexpr("\\{\\{[^{}]*\\}\\}", text))[[1]]
  if (length(left))
    stop("unfilled template key: ",
         paste(unique(gsub("^\\{\\{|\\}\\}$", "", left)), collapse = ", "),
         call. = FALSE)
  text
}

# Two of the files a scaffold writes begin with a dot, and a dot file cannot
# travel inside an R package under its own name. R CMD build deletes any file
# named `.gitignore` anywhere in the source tree, and R CMD check reports every
# other hidden file it finds as one that was most likely included in error. So
# they ship undotted and the dot is put back when they are written out. The
# mapping lives here rather than in the writer, because the writer is one line
# of a loop and this is the fact the loop has to know.
TEMPLATE_DOTFILES <- c(gitignore = ".gitignore", gitkeep = ".gitkeep")

template_dest <- function(rel) {
  base <- basename(rel)
  if (!base %in% names(TEMPLATE_DOTFILES)) return(rel)
  dir <- dirname(rel)
  if (identical(dir, ".")) TEMPLATE_DOTFILES[[base]]
  else file.path(dir, TEMPLATE_DOTFILES[[base]])
}

# ---- the containment check -----------------------------------------------
#
# A course repository holds answer keys and a public web site in one tree. The
# separation is a render allowlist in `_quarto.yml`, which is a configuration
# file one careless edit away from a blocklist, so it is not trusted on its own.
# `assessments/leak-canary.qmd` carries a string that exists nowhere else, and
# this reads the bytes of everything that would be published looking for it.
#
# BYTES, not lines. A canary can reach `docs/` inside a rendered PDF, a Word
# file, an image's metadata or a self-contained HTML page's base64 payload, and
# readLines() on any of those either mangles the content or refuses it. readBin()
# plus grepRaw() has no opinion about encoding and no opinion about what a line
# is, so a binary file cannot hide a hit and cannot break the scan either.
#
# A missing `docs/` is a stop, not a pass. Nothing was scanned, so nothing is
# known, and "leakcheck: clean" printed over an unrendered site is the exact
# sentence somebody pushes on.

#' Refuse to publish an answer key
#'
#' Read every byte of everything under `<proj>/<docs>` looking for the leak
#' canary, and stop when it is found.
#'
#' `docs/` is what GitHub Pages serves, so everything in it is public and
#' everything outside it is not. The canary is a string that lives in
#' `assessments/` and nowhere else; finding it under `docs/` means the render
#' allowlist let assessment content through.
#'
#' This is one of three independent guards on the same failure, and none of them
#' covers the others: the quiz body extractor truncates at the answer-key
#' heading, it stops if the canary survives that truncation, and
#' [build_cartridge()] scans its whole staging tree before it zips. This one
#' guards the web site, which the other two never touch.
#'
#' @param proj Course project root.
#' @param docs The published directory, relative to `proj` or absolute. A
#'   missing directory stops: nothing was scanned, so nothing is known.
#' @return `invisible(character(0))` when clean. Otherwise it stops, naming
#'   every file that carries the canary.
#' @export
leak_check <- function(proj = ".", docs = "docs") {
  root <- proj_path(proj, docs)
  if (!dir.exists(root))
    stop("no docs directory at ", root,
         ". Nothing was scanned, so nothing is known about what would be ",
         "published. Render the site first.", call. = FALSE)

  files <- list.files(root, recursive = TRUE, all.files = TRUE,
                      full.names = TRUE, no.. = TRUE)
  files <- files[!dir.exists(files)]
  smallest <- nchar(LEAK_CANARY, type = "bytes")
  carries <- vapply(files, function(f) {
    n <- file.size(f)
    if (is.na(n) || n < smallest) return(FALSE)
    length(grepRaw(LEAK_CANARY, readBin(f, "raw", n = n),
                   fixed = TRUE, all = FALSE)) > 0L
  }, TRUE, USE.NAMES = FALSE)

  leaked <- files[carries]
  if (length(leaked)) {
    rel <- substring(leaked, nchar(root) + 2L)
    stop("LEAK: assessments/ content reached ", docs, ". Do not push.\n",
         paste0("  ", rel, collapse = "\n"), call. = FALSE)
  }

  cat("leakcheck: clean\n")
  cat("  ", length(files), " file(s) read as bytes under ", root, "\n", sep = "")
  version_line("leak_check")
  invisible(character(0))
}
