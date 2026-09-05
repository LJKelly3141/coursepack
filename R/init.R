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

# ---- the scaffold --------------------------------------------------------
#
# Asking is a fallback, not the interface. Every value this needs is an
# argument, so a scaffold can be written from a script and, more to the point,
# from a test; the prompts exist for the person typing the call at a console and
# run only when `ask` is on AND the session is interactive, because readline()
# in a non-interactive session returns "" without waiting and would turn a
# missing argument into an empty one.
#
# An empty answer is not an answer. It stops with the same message a missing
# argument gets, and that matters most for the timezone. `Sys.timezone()` is
# printed beside the prompt as a suggestion and is never accepted by pressing
# return: the machine's zone is a fact about the machine, and a course whose
# zone was never typed by anyone is a course whose every deadline and every
# announcement is off by hours while the generated XML reads perfectly.

ask_value <- function(prompt, suggestion = NULL) {
  msg <- if (is.null(suggestion) || !nzchar(suggestion)) paste0(prompt, ": ")
         else paste0(prompt, "\n  (this machine is set to ", suggestion,
                     "; type it if that is right): ")
  trimws(readline(msg))
}

need_value <- function(value, name, prompt, asking, suggestion = NULL) {
  v <- if (is.null(value)) "" else trimws(paste(as.character(value), collapse = ""))
  if (!nzchar(v) && asking) v <- ask_value(prompt, suggestion)
  if (!nzchar(v)) stop(name, " is required", call. = FALSE)
  v
}

# What the export does not carry, written back over what it does. Canvas stores
# every date as a UTC instant and no zone; the site address, the local textbook
# checkout and the clock a bare `due:` means are facts about this repository
# rather than about the course inside Canvas, and the export has never seen any
# of them. Every other key the extractor read stays exactly as it read it, which
# is why this is a parse and a rewrite rather than a template.
#
# The comments the extractor wrote into the file do not survive the rewrite.
# They are restated in what init_course() prints, and the one they exist to warn
# about is printed as its own line when it applies.
reapply_course_facts <- function(f, code, title, site_url, timezone,
                                 textbook_docs, due_time) {
  cy <- yaml::yaml.load_file(f)
  cy$code <- code
  cy$title <- title
  cy$urls <- if (is.list(cy$urls)) cy$urls else list()
  cy$urls$site <- site_url
  cy$term <- if (is.list(cy$term)) cy$term else list()
  cy$term$timezone <- timezone
  cy$textbook_docs <- textbook_docs
  cy$due_time <- due_time
  yaml::write_yaml(cy, f)
  invisible(cy)
}

#' Scaffold a course repository
#'
#' Write a new course under `path`: the two manifests, the containment
#' scaffold, the Makefile whose every target calls a function in this package,
#' and, optionally, the skills. With `from_export` it starts from a Canvas
#' export instead of from placeholders.
#'
#' Nothing here is guessed. `code`, `title`, `site_url` and `timezone` have no
#' defaults, and a missing one stops unless `ask` is on and the session is
#' interactive, in which case it is prompted for. `Sys.timezone()` is shown
#' beside the timezone prompt as a suggestion and is never used silently: a
#' wrong zone moves every deadline and every announcement by hours and looks
#' correct in the generated XML.
#'
#' No date is written. `term: first_day:` and `last_day:` are `null`, because
#' those come from the registrar's calendar and counting weeks is how a course
#' ends up with a deadline on a day it does not meet. The scaffold still builds:
#' its one announcement posts on import, and a term window is required only for
#' an announcement that posts on a date.
#'
#' `path` must not exist or must be empty, and nothing is ever overwritten.
#'
#' @section Starting from a Canvas export:
#' `from_export` names an `.imscc`. The scaffold is written first, then
#' [extract_manifest()] replaces `course.yml`, `modules.yml` and
#' `reference.yml` with the export's own structure and copies the export under
#' `reference/`. The caller's `code`, `title`, `site_url`, `timezone`,
#' `textbook_docs` and the template's `due_time` are then written back into the
#' extracted `course.yml`, because an export carries none of them.
#'
#' The zone is the one to be careful with. The extractor writes every carried
#' `due:` as the UTC instant Canvas stored and `term: timezone: UTC` above them,
#' so those two lines belong to each other. Naming a different zone here moves
#' every carried deadline by the offset between them, and the extracted `due:`
#' dates have to be rewritten to match. The closing summary says so when it
#' applies.
#'
#' @param path Directory to scaffold into. Must not exist, or be empty.
#' @param code Course code, for example `"ABCD 101"`. The `slug:` is derived
#'   from it and every derived Canvas identifier from that.
#' @param title Course title.
#' @param site_url Where the rendered site is published. Must start with
#'   `https://`.
#' @param timezone IANA zone name, validated against `OlsonNames()`.
#' @param institution Optional institution name.
#' @param textbook_url Optional base URL of a separate textbook site, which a
#'   `{textbook}` token in `modules.yml` resolves against.
#' @param textbook_docs A checkout of the rendered textbook, or `"none"`.
#' @param skills Whether to install the shipped skills under `.claude/skills/`.
#' @param claude_md Whether to write the course's `CLAUDE.md`.
#' @param git Whether to run `git init` in `path`. Nothing is committed, ever.
#' @param from_export Optional path to a Canvas `.imscc` to start from.
#' @param ask Whether to prompt for a missing required value. Prompts only when
#'   this is `TRUE` and the session is interactive.
#' @return `path`, invisibly.
#' @export
init_course <- function(path, code, title, site_url, timezone,
                        institution = NULL, textbook_url = NULL,
                        textbook_docs = "none", skills = TRUE,
                        claude_md = TRUE, git = TRUE, from_export = NULL,
                        ask = interactive()) {
  # Refuse before asking anything. Four prompts answered and then a refusal
  # because the directory was never empty is four answers thrown away.
  if (file.exists(path) && !dir.exists(path))
    stop(path, " is a file, not an empty directory. init_course() never ",
         "overwrites anything.", call. = FALSE)
  if (dir.exists(path) && length(list.files(path, all.files = TRUE, no.. = TRUE)))
    stop(path, " is not empty. init_course() never overwrites anything: ",
         "scaffold into a new directory.", call. = FALSE)

  asking <- isTRUE(ask) && interactive()
  code <- need_value(if (missing(code)) NULL else code, "code",
                     "Course code, for example ABCD 101", asking)
  title <- need_value(if (missing(title)) NULL else title, "title",
                      "Course title", asking)
  site_url <- need_value(if (missing(site_url)) NULL else site_url, "site_url",
                         "Published site URL, for example https://user.github.io/repo",
                         asking)
  timezone <- need_value(if (missing(timezone)) NULL else timezone, "timezone",
                         "Course timezone, an IANA name such as America/Chicago",
                         asking, suggestion = Sys.timezone())

  if (!startsWith(site_url, "https://"))
    stop("site_url must start with https://, got: ", site_url,
         ". Every asset the cartridge points at is an absolute URL under it, ",
         "and a page served over http inside the Canvas frame is blocked.",
         call. = FALSE)
  if (!timezone %in% OlsonNames())
    stop("timezone '", timezone, "' is not an IANA zone name (for example ",
         "America/Chicago). Every due date and every announcement is read in ",
         "it.", call. = FALSE)
  if (!is.null(from_export) && !file.exists(from_export))
    stop("from_export names no file: ", from_export, call. = FALSE)

  root <- system.file("templates", "course", package = "coursepack")
  if (!nzchar(root)) stop("coursepack templates are not installed", call. = FALSE)

  values <- list(code = code, title = title,
                 institution = institution %||% "",
                 slug = slugify(code),
                 site_url = site_url,
                 textbook_url = textbook_url %||% "",
                 textbook_docs = textbook_docs,
                 timezone = timezone,
                 canary = LEAK_CANARY,
                 version = coursepack_version())

  rel <- sort(list.files(root, recursive = TRUE, all.files = TRUE, no.. = TRUE))
  if (!isTRUE(claude_md)) rel <- setdiff(rel, "CLAUDE.md")

  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  path <- normalizePath(path, mustWork = TRUE)
  written <- character()
  for (f in rel) {
    dst_rel <- template_dest(f)
    dst <- file.path(path, dst_rel)
    if (file.exists(dst))
      stop("refusing to overwrite ", dst, call. = FALSE)
    dir.create(dirname(dst), recursive = TRUE, showWarnings = FALSE)
    src <- file.path(root, f)
    # An empty template is written empty. The .gitkeep files are what this is
    # for: a placeholder whose whole content is its name.
    if (isTRUE(file.size(src) == 0)) file.create(dst)
    else writeLines(render_template(readLines(src, warn = FALSE), values), dst)
    written <- c(written, dst_rel)
  }

  # Read back off disk rather than hard-coded here, so the clock a bare due:
  # means is the template's own and the two cannot drift apart.
  due_time <- yaml::yaml.load_file(file.path(path, "course.yml"))$due_time

  carried_dates <- FALSE
  if (!is.null(from_export)) {
    cat("\n")
    extract_manifest(from_export, path, overwrite = TRUE)
    reapply_course_facts(file.path(path, "course.yml"), code, title, site_url,
                         timezone, textbook_docs, due_time)
    mods <- read_modules(path)
    carried_dates <- any(vapply(c(mods$assignments, mods$quizzes),
                                function(d) !is.null(d$due), TRUE))
    written <- union(written, c("course.yml", "modules.yml", "reference.yml",
                                file.path("reference", basename(from_export))))
    cat("\n")
  }

  cat("=== scaffolded ===\n")
  cat("  ", path, "\n", sep = "")
  for (f in sort(written)) cat("    ", f, "\n", sep = "")
  cat("  ", length(written), " file", if (length(written) == 1L) "" else "s",
      "\n", sep = "")

  if (isTRUE(skills)) install_skills(path)

  if (isTRUE(git)) {
    if (!nzchar(Sys.which("git"))) {
      cat("  git is not on the PATH, so no repository was initialised here\n")
    } else {
      st <- system2("git", c("init", shQuote(path)), stdout = FALSE, stderr = FALSE)
      cat(if (identical(as.integer(st), 0L))
            "  git init, and nothing else. Nothing is committed here, ever\n"
          else "  git init failed; initialise the repository by hand\n")
    }
  }

  version_line("init_course")

  if (carried_dates && !identical(timezone, "UTC")) {
    cat("\n  READ THIS: the extracted due: dates are the UTC instants Canvas\n")
    cat("  stored, and term: timezone: now reads ", timezone, ". Rewrite those\n", sep = "")
    cat("  dates into that zone before the first build, or every carried\n")
    cat("  deadline moves by the offset between the two.\n")
  }

  cat("\nNext:\n")
  cat("  1. Fill in term: first_day: and last_day: from the registrar's calendar.\n")
  cat("  2. quarto render, then make leakcheck.\n")
  cat("  3. Commit, push, and enable Pages from main /docs. The site has to\n")
  cat("     answer before a cartridge built from it is imported.\n")
  cat("  4. make coursepack.\n")
  cat("  5. Import into a throwaway Canvas shell, look at it, export it back\n")
  cat("     out, and compare.\n")
  cat("\nStep 5 is not optional. A zip that builds proves nothing: Canvas\n")
  cat("discards malformed content silently and reports a successful import.\n")
  invisible(path)
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
