# The paper form of an assessment.
#
# A bank quiz in Canvas is a draw. Every student meets a different five items,
# and nobody, the instructor included, ever holds the whole thing in one hand.
# A make-up sitting, a proctored room and an accommodation each need one fixed
# form on paper, with a key that matches it item for item. That is what this
# writes.
#
# THE SEED IS THE FORM'S NAME. The draw is `set.seed(seed)` and then one sample
# without replacement per question group, in group order, so seed 7 is one paper
# and seed 8 is another, and asking for seed 7 again next term hands back the
# same paper. Nothing written here carries a timestamp for exactly that reason:
# `date: today` in the front matter is a Quarto keyword evaluated at render, not
# a literal, so two runs of one seed produce byte-identical files and a diff of
# two forms shows the questions rather than the clock.
#
# WHAT IS PRINTABLE, AND WHY THE REST IS REFUSED. A quiz whose questions this
# package owns (`bank:`), and an assignment whose directions it can read
# (`description:` or `homework:`). An R/exams `qti:` zip, a carried
# `source_ref:` resource and a `quiz_file:` assignment all keep their
# student-facing text somewhere this function does not read, and a paper form
# built out of the part it can see would be a form with questions missing. It
# refuses instead, and says which forms it does print.
#
# THE KEY IS A SEPARATE FILE. It is never a section of the form, never a page
# the form's last page runs into, and it is written beside the form rather than
# into it, so the two are handed to a copier separately or not at all.

# Pandoc's markdown writer prefers simple tables, whose columns are held
# together by their spacing alone. Indented under a numbered item, then edited
# by hand at a desk, those fall apart without anything looking wrong. Turning
# the three off leaves pipe tables, whose cell boundaries survive both.
PRINT_MD_WRITER <- "markdown-simple_tables-multiline_tables-grid_tables"

# A <div> or a <section> in the source is a wrapper, not content. Read as a
# native div it comes back out as a `::: {}` fence, which is Quarto syntax
# standing where a question should be, and which has to be indented as a block
# to stay inside its numbered item. Read with the two extensions off, the
# wrapper dissolves and its heading keeps the id.
PRINT_HTML_READER <- "html-native_divs-native_spans"

# The formats the front matter written here declares. A format outside this list
# would fail inside quarto with a message about a format rather than about the
# call that asked for it.
PRINT_FORMATS <- c("docx", "pdf")

# Block-level tags a stem may carry. Used only to find a redundant <br>.
PRINT_BLOCK_TAGS <- "table|ul|ol|p|div|h[1-6]|pre|blockquote|figure"

# ---- helpers -------------------------------------------------------------

# A <br> immediately before a block element is redundant in HTML and harmful
# here: pandoc reads it as a hard line break, ends the paragraph with it, and
# writes a stray backslash on the line above the block, which a reader sees as a
# backslash on the page. Bank stems write one before a table often enough to
# matter. Every other <br> is left alone and stays a line break.
drop_br_before_block <- function(html) {
  gsub(paste0("(?i)<br\\s*/?>\\s*(?=<(?:", PRINT_BLOCK_TAGS, ")\\b)"), "", html, perl = TRUE)
}

# Drop the blank lines pandoc leaves at both ends of a converted fragment.
trim_blank_ends <- function(x) {
  keep <- which(nzchar(trimws(x)))
  if (!length(keep)) return(character())
  x[seq.int(keep[1], keep[length(keep)])]
}

# One HTML fragment to Markdown, through pandoc.
#
# Each fragment is converted on its own rather than as one document holding
# every question, because pandoc writes a list whose items begin with inline
# content as a TIGHT list, with no blank line between an item's paragraph and
# the table or figure under it. Markdown written that way does not read back as
# a table: pandoc's own round trip loses it. Converting a fragment at a time
# leaves the blocks at the top level, where they are separated properly, and the
# numbering is added afterwards by numbered_item().
html_to_md <- function(html, what) {
  f <- tempfile(fileext = ".html")
  on.exit(unlink(f), add = TRUE)
  con <- file(f, open = "wb")
  writeLines(enc2utf8(html), con, useBytes = TRUE)
  close(con)
  md <- tryCatch(
    system2("pandoc", c(paste0("--from=", PRINT_HTML_READER),
                        paste0("--to=", PRINT_MD_WRITER), shQuote(f)),
            stdout = TRUE),
    error = function(e) stop("pandoc failed converting ", what, ": ",
                             conditionMessage(e), call. = FALSE))
  status <- attr(md, "status")
  if (!is.null(status) && !identical(as.integer(status), 0L))
    stop("pandoc exited ", status, " converting ", what, call. = FALSE)
  Encoding(md) <- "UTF-8"
  md <- trim_blank_ends(md)
  if (!length(md))
    stop(what, " converted to empty Markdown. A blank question on a printed ",
         "form is a question nobody can answer. Refusing to write it.", call. = FALSE)
  md
}

# Indent a converted fragment under its own number, so every block it holds
# belongs to the list item rather than ending it.
numbered_item <- function(n, md) {
  marker <- paste0(n, ".")
  width <- max(4L, nchar(marker) + 1L)
  out <- paste0(strrep(" ", width), md)
  out[!nzchar(trimws(md))] <- ""
  substr(out[1], 1L, nchar(marker)) <- marker
  out
}

# A cell of the key's table. A pipe inside a value would end the cell early.
md_cell <- function(x) {
  x <- gsub("\\", "\\\\", as.character(x), fixed = TRUE)
  gsub("|", "\\|", x, fixed = TRUE)
}

# A title inside double quotes in YAML.
yaml_quoted <- function(x) {
  x <- gsub("\\", "\\\\", as.character(x), fixed = TRUE)
  paste0('"', gsub('"', '\\"', x, fixed = TRUE), '"')
}

# `date: today` is a Quarto keyword resolved at render. Writing the date here
# instead would put a timestamp in the file and two runs of one seed would stop
# being the same paper.
front_matter <- function(title) {
  c("---", paste0("title: ", yaml_quoted(title)), "date: today",
    "format:", "  docx: default", "  pdf: default", "---", "")
}

# ---- the draw ------------------------------------------------------------

# The seed names the form, so it has to be something a person can write down and
# type again.
check_seed <- function(seed) {
  ok <- length(seed) == 1L && is.numeric(seed) && is.finite(seed) &&
    abs(seed) <= .Machine$integer.max && seed == trunc(seed)
  if (!ok)
    stop("seed must be one whole number. It is the name of the form: the same ",
         "seed prints the same paper, and the key says which seed it belongs to.",
         call. = FALSE)
  as.integer(seed)
}

# One draw per group, in group order, without replacement.
#
# sample.int() is what sample() calls; it is used directly so that a group
# holding exactly one question cannot be read as "sample from 1:n".
#
# The session's RNG state is put back afterwards. Printing a form is not
# supposed to move a simulation running in the same session.
draw_items <- function(out, seed) {
  if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) {
    old <- get(".Random.seed", envir = globalenv(), inherits = FALSE)
    on.exit(assign(".Random.seed", old, envir = globalenv()), add = TRUE)
  } else {
    on.exit(suppressWarnings(rm(".Random.seed", envir = globalenv())), add = TRUE)
  }
  set.seed(seed)
  picked <- list()
  for (gi in seq_along(out$groups)) {
    g <- out$groups[[gi]]
    n <- as.integer(out$draws[[gi]])
    if (n < 1L || !length(g$qs)) next
    for (j in sample.int(length(g$qs), n))
      picked[[length(picked) + 1L]] <- list(ch = g$ch, section = g$name, q = g$qs[[j]])
  }
  picked
}

# The letter a student writes down, which is the option's POSITION in the
# printed list. It is the bank's own key wherever a bank labels its options
# A to D, and it stays right for one that does not.
answer_letter <- function(q, where) {
  k <- match(as.character(q$answer), names(q$options))
  if (is.na(k) || k > length(LETTERS))
    stop(where, ": answer '", as.character(q$answer), "' is not one of ",
         paste(names(q$options), collapse = ", "), call. = FALSE)
  LETTERS[k]
}

# One question as HTML: the stem, its figure if it has one, and the options as
# an A-to-D list in bank order. Options are text/plain in a bank, so they are
# escaped on the way into HTML.
print_stem_html <- function(q) {
  body <- drop_br_before_block(normalize_tables(trimws(as.character(q$question))))
  image <- as.character(q$image %||% "")
  if (nzchar(image))
    body <- paste0(body, '<p><img src="', html_escape(image), '" alt="',
                   html_escape(as.character(q$figure$alt %||% "")), '"></p>')
  opts <- vapply(q$options, as.character, "")
  paste0(body, '<ol type="A">',
         paste0("<li>", html_escape(opts), "</li>", collapse = ""), "</ol>")
}

# ---- the two documents ---------------------------------------------------

quiz_form_lines <- function(title, picked) {
  body <- character()
  for (i in seq_along(picked)) {
    where <- paste0(title, ": question ", i)
    check_question(picked[[i]]$q, where)
    body <- c(body, numbered_item(i, html_to_md(print_stem_html(picked[[i]]$q), where)), "")
  }
  c(front_matter(title), body)
}

key_lines <- function(title, picked, seed) {
  rows <- vapply(seq_along(picked), function(i) {
    p <- picked[[i]]
    paste0("| ", i, " | ", p$ch, " | ", md_cell(p$section), " | ", p$q$id, " | ",
           answer_letter(p$q, paste0(title, ": question ", i)), " |")
  }, "")
  c(front_matter(paste0(title, " answer key")),
    paste0("Drawn with seed ", seed, ". Written by coursepack ",
           coursepack_version(), "."),
    "",
    "| Number | Chapter | Section | Bank id | Answer |",
    "|-------:|--------:|:--------|--------:|:-------|",
    rows, "")
}

assignment_form_lines <- function(a, course, proj, id) {
  # Only a homework assignment reads the rendered textbook, so only a homework
  # assignment is stopped by a course that has none.
  tb_docs <- if (!is.null(a$homework)) textbook_docs_path(course, proj) else NULL
  body <- assignment_body(a, course, tb_docs)
  c(front_matter(as.character(a$title)),
    html_to_md(body, paste0("assignment '", id, "'")), "")
}

# Every figure a drawn question names, copied beside the qmd and referenced by
# its bare filename, so the pair travels as a folder and the form renders
# wherever it is opened.
copy_figures <- function(picked, proj, bank_dir, out_dir, title) {
  copied <- character()
  for (p in picked) {
    image <- as.character(p$q$image %||% "")
    if (!nzchar(image)) next
    src <- file.path(proj, bank_dir, "images", image)
    if (!file.exists(src))
      stop(title, ": question id ", p$q$id, " names image ", src,
           ", which does not exist", call. = FALSE)
    if (!file.copy(src, file.path(out_dir, image), overwrite = TRUE))
      stop(title, ": could not copy ", src, " beside the printed form", call. = FALSE)
    copied <- c(copied, image)
  }
  unique(copied)
}

# ---- which definitions print ---------------------------------------------

declared_form <- function(def, forms) {
  have <- intersect(forms, names(def))
  if (!length(have)) "no body key at all" else paste0(have[1], ":")
}

refuse_form <- function(kind, id, form) {
  stop("printable forms are bank quizzes and description: and homework: ",
       "assignments. The ", kind, " '", id, "' declares ", form, ", whose ",
       "student-facing text lives somewhere this package does not read, so a ",
       "paper form of it would be missing the questions.", call. = FALSE)
}

resolve_printable <- function(m, id) {
  if (id %in% names(m$quizzes)) {
    q <- m$quizzes[[id]]
    if (!is.null(q$bank)) return(list(kind = "quiz", def = q))
    refuse_form("quiz", id, declared_form(q, DEFINITION_FORMS$quiz))
  }
  if (id %in% names(m$assignments)) {
    a <- m$assignments[[id]]
    if (!is.null(a$description) || !is.null(a$homework))
      return(list(kind = "assignment", def = a))
    refuse_form("assignment", id, declared_form(a, DEFINITION_FORMS$assignment))
  }
  stop("modules.yml declares no assignment or quiz '", id, "'. It declares: ",
       paste(sort(c(names(m$assignments), names(m$quizzes))), collapse = ", "),
       call. = FALSE)
}

# ---- rendering -----------------------------------------------------------

render_paper <- function(qmd, formats) {
  out <- character()
  for (fmt in formats) {
    res <- system2("quarto", c("render", shQuote(qmd), "--to", fmt),
                   stdout = TRUE, stderr = TRUE)
    status <- attr(res, "status")
    if (!is.null(status) && !identical(as.integer(status), 0L))
      stop("quarto render failed on ", basename(qmd), " to ", fmt, ":\n",
           paste(res, collapse = "\n"), call. = FALSE)
    f <- file.path(dirname(qmd),
                   paste0(tools::file_path_sans_ext(basename(qmd)), ".", fmt))
    if (!file.exists(f))
      stop("quarto reported success but ", f, " was not written", call. = FALSE)
    out <- c(out, stats::setNames(f, fmt))
  }
  out
}

# ---- the entry point -----------------------------------------------------

#' Print a paper form of an assessment
#'
#' Write one fixed form of an assessment as a Quarto document, and, for a quiz
#' drawn from a question bank, the answer key that goes with it.
#'
#' A `bank:` quiz is a draw: `set.seed(seed)`, then one sample without
#' replacement from each question group, in group order. The same seed produces
#' the same paper, because nothing written here carries a timestamp; `date:
#' today` in the front matter is a Quarto keyword resolved at render. Two runs
#' of one seed are byte-identical files, and two forms differ only where their
#' questions do.
#'
#' Question stems are HTML in a bank, so they are converted to Markdown with
#' pandoc: tables become pipe tables, and a figure is copied beside the document
#' and referenced by its bare filename with the bank's alt text. Options are
#' listed `A.` to `D.` in the order the bank wrote them, and the key records the
#' letter as printed.
#'
#' The printable forms are a quiz declaring `bank:` and an assignment declaring
#' `description:` or `homework:`. A `qti:` quiz, a `quiz_file:` assignment and
#' any carried `source_ref:` definition keep their student-facing text outside
#' this package, so they are refused rather than printed with the questions
#' missing.
#'
#' @param proj Course project root.
#' @param id A quiz or assignment id from `modules.yml`. Quizzes are looked up
#'   first.
#' @param seed One whole number. It names the form: the key records it, and the
#'   same seed prints the same paper.
#' @param out_dir Where the documents are written. Figures are copied here too.
#' @param formats Formats to render, from `docx` and `pdf`, which are the two
#'   the front matter declares.
#' @param render Render with quarto when it is on the PATH. With `FALSE`, or
#'   with no quarto, the documents are written and where they are is printed.
#' @return `invisible(list(qmd, key, rendered))`. `key` is `NULL` for an
#'   assignment, which has no answer key. `rendered` is the form's rendered
#'   files, named by format, and is empty when nothing was rendered; a key is
#'   rendered to the same formats beside its form.
#' @examples
#' \dontrun{
#' # Both calls need pandoc, which converts the bank's question HTML to
#' # Markdown, and the second one needs quarto as well.
#'
#' # Write the form and its key, and say where they landed.
#' paper <- print_assessment(".", "module-1-quiz", seed = 7, render = FALSE)
#' basename(c(paper$qmd, paper$key))
#'
#' # The same seed prints the same paper, here rendered to docx.
#' print_assessment(".", "module-1-quiz", seed = 7, formats = "docx")
#' }
#' @export
print_assessment <- function(proj = ".", id, seed,
                             out_dir = file.path(proj, "build", "paper"),
                             formats = c("docx", "pdf"), render = TRUE) {
  id <- as.character(id)
  seed <- check_seed(seed)
  formats <- as.character(formats)
  if (!length(formats)) stop("formats is empty; nothing would be rendered", call. = FALSE)
  bad <- setdiff(formats, PRINT_FORMATS)
  if (length(bad))
    stop("the front matter written here declares ",
         paste(PRINT_FORMATS, collapse = " and "), ", so ",
         paste(bad, collapse = ", "), " cannot be rendered from it", call. = FALSE)

  m <- read_manifest(proj)
  target <- resolve_printable(m, id)

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  base <- file.path(out_dir, paste0(id, "-seed", seed))
  qmd <- paste0(base, ".qmd")
  key <- NULL
  figures <- character()

  if (identical(target$kind, "quiz")) {
    q <- target$def
    title <- as.character(q$title)
    spec <- q$bank
    picked <- draw_items(bank_groups(spec, proj, title), seed)
    if (!length(picked))
      stop(title, ": the bank block draws no questions, so there is nothing to ",
           "print", call. = FALSE)
    figures <- copy_figures(picked, proj, as.character(spec$dir %||% "questions"),
                            out_dir, title)
    writef(qmd, quiz_form_lines(title, picked))
    key <- paste0(base, "-key.qmd")
    writef(key, key_lines(title, picked, seed))
  } else {
    writef(qmd, assignment_form_lines(target$def, m$course, proj, id))
  }

  rendered <- stats::setNames(character(), character())
  if (isTRUE(render) && nzchar(Sys.which("quarto"))) {
    rendered <- render_paper(qmd, formats)
    if (!is.null(key)) render_paper(key, formats)
  }

  cat("Wrote: ", qmd, "\n", sep = "")
  if (!is.null(key)) cat("       ", key, "\n", sep = "")
  for (f in figures) cat("       ", file.path(out_dir, f), "\n", sep = "")
  if (length(rendered)) {
    for (fmt in names(rendered)) cat("Rendered ", fmt, ": ", rendered[[fmt]], "\n", sep = "")
    if (!is.null(key)) cat("The key rendered beside it, in the same formats.\n")
  } else if (isTRUE(render)) {
    cat("quarto is not on the PATH, so nothing was rendered. The files above ",
        "render with: quarto render <file> --to docx\n", sep = "")
  }
  cat("A form that renders proves nothing about the draw. Read it against the ",
      "key before it is copied.\n", sep = "")
  version_line("print_assessment")
  invisible(list(qmd = qmd, key = key, rendered = rendered))
}
