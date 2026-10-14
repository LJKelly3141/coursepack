# PDF/UA validation for the PDFs a course publishes.
#
# pa11y reads HTML and nothing else, so a PDF in the rendered output reached
# students unchecked. inventory_media() never listed it either: that inventory
# excludes the output directory on purpose, because it lists sources. This
# file looks in the output directory, where the published copy actually is.
#
# veraPDF does the validation and is NOT required. A machine without it (or
# without the Java it runs on) gets every PDF reported as "not checked" with
# the install instructions, and the audit carries on. "Not checked" and
# "passed" must never print the same way.

PDF_UA_FLAVOUR   <- "ua1"
PDF_UA_LABEL     <- "PDF/UA-1"
# Not a WCAG number. Follows "broken-embed": a criterion string of the
# audit's own, so these rows group and render as their own kind.
PDF_UA_CRITERION <- "pdf-ua"
# veraPDF pays the JVM's start-up once per call, so files go in batches.
VERAPDF_BATCH    <- 50L

VERAPDF_INSTALL_HINT <- paste(
  "veraPDF was not found or could not start, so PDFs cannot be validated.",
  "Install Java 8 or later, then run `quarto install verapdf`.",
  "To use a copy elsewhere, pass its launcher as audit_course(verapdf = ).")

# Where `quarto install verapdf` puts the launcher. It is not on PATH.
# The macOS location is verified (Quarto 1.10.18, 2026-10-13). The Linux one
# follows Quarto's data-directory convention and is NOT verified. Windows is
# found through PATH or the `verapdf` argument only: its location hangs off
# an environment variable, and this package reads none.
quarto_verapdf_candidates <- function() {
  home <- path.expand("~")
  file.path(c(file.path(home, "Library", "Application Support"),
              file.path(home, ".local", "share")),
            "quarto", "verapdf", "verapdf")
}

#' Find the veraPDF launcher
#'
#' Looks on `PATH`, then in the directory `quarto install verapdf` installs
#' into. A copy anywhere else is passed to [audit_course()] as `verapdf`.
#'
#' @return The launcher's path, or `NA` when veraPDF is not found.
#' @examples
#' find_verapdf()
#' @export
find_verapdf <- function() {
  onpath <- unname(Sys.which("verapdf"))
  if (nzchar(onpath)) return(onpath)
  hit <- Filter(file.exists, quarto_verapdf_candidates())
  if (length(hit)) hit[[1]] else NA_character_
}

# A launcher that exists can still fail to start: veraPDF needs Java, and
# macOS ships a /usr/bin/java stub that exists without one. So this runs it.
verapdf_usable <- function(verapdf) {
  if (is.na(verapdf)) return(FALSE)
  st <- suppressWarnings(try(
    system2(verapdf, "--version", stdout = FALSE, stderr = FALSE),
    silent = TRUE))
  identical(st, 0L)
}

# Asked once, before any work, when veraPDF is missing: install it now, or
# carry on without PDF validation. Where nobody can answer (GitHub's automatic
# test run, a script with no terminal) it carries on. A missing optional tool
# never fails the audit, and neither does an install that did not work.
can_prompt <- function() interactive() || isatty(stdin())

prompt_line <- function(msg) {
  if (interactive()) return(readline(msg))
  cat(msg)
  con <- file("stdin")
  on.exit(close(con), add = TRUE)
  readLines(con, n = 1L)
}

install_verapdf <- function() {
  if (!nzchar(Sys.which("quarto"))) {
    cat("quarto is not on PATH, so veraPDF was not installed.\n")
    return(invisible(FALSE))
  }
  st <- suppressWarnings(system2("quarto",
                                 c("install", "verapdf", "--no-prompt")))
  invisible(identical(st, 0L))
}

# Returns the launcher to use, or NA to run without PDF validation.
ask_about_verapdf <- function(ask = can_prompt(), read = prompt_line,
                              install = install_verapdf) {
  cat("\n", VERAPDF_INSTALL_HINT, "\n", sep = "")
  if (ask) {
    ans <- read("Install veraPDF now with `quarto install verapdf`? [y = install, n = continue without it] ")
    if (tolower(trimws(ans)) %in% c("y", "yes")) {
      install()
      found <- find_verapdf()
      if (verapdf_usable(found)) return(found)
      cat("veraPDF still cannot start. It needs Java 8 or later.\n")
    }
  }
  cat("Continuing without PDF validation.\n\n")
  NA_character_
}

# Every PDF in the rendered output, split two ways. "built" has a .qmd or
# .Rmd of the same path and name in the repo, so this course renders it and
# the fix has a source file to land in. "carried" is everything else: a
# publisher handout, a form, a scan. It is validated and reported, but it is
# not this course's to fix and is never a finding.
published_pdfs <- function(tgt) {
  empty <- data.frame(file = character(), origin = character(),
                      source_file = character(), stringsAsFactors = FALSE)
  if (is.na(tgt$output_dir) || !dir.exists(tgt$output_dir)) return(empty)
  f <- list.files(tgt$output_dir, pattern = "\\.pdf$", recursive = TRUE,
                  ignore.case = TRUE)
  if (!length(f)) return(empty)
  src <- vapply(tools::file_path_sans_ext(f), function(stem) {
    cand <- paste0(stem, c(".qmd", ".Rmd"))
    hit  <- cand[file.exists(file.path(tgt$repo, cand))]
    if (length(hit)) hit[1] else NA_character_
  }, character(1), USE.NAMES = FALSE)
  data.frame(file = f, origin = ifelse(is.na(src), "carried", "built"),
             source_file = src, stringsAsFactors = FALSE)
}

rule_line <- function(r) {
  sprintf("%s clause %s test %s: %s (%s failed checks)", r$specification,
          r$clause, r$testNumber, r$description, r$failedChecks)
}

# One veraPDF call over `paths` (absolute). Returns a list keyed by path, each
# list(status =, rules =). veraPDF exits non-zero whenever any file fails, so
# the exit status is ignored and the JSON is what is read. A path with no job
# in the JSON is "unreadable", never silently "passed".
run_verapdf <- function(verapdf, paths) {
  out <- tempfile(fileext = ".json")
  on.exit(unlink(out), add = TRUE)
  suppressWarnings(system2(
    verapdf, c("-f", PDF_UA_FLAVOUR, "--format", "json", shQuote(paths)),
    stdout = out, stderr = FALSE))
  parsed <- tryCatch(jsonlite::fromJSON(out, simplifyVector = FALSE),
                     error = function(e) NULL)
  res <- stats::setNames(
    rep(list(list(status = "unreadable",
                  rules = "veraPDF returned no result for this file")),
        length(paths)), paths)
  for (job in parsed$report$jobs) {
    p <- job$itemDetails$name
    if (!p %in% paths) next
    vr <- job$validationResult[[1]]
    if (is.null(vr)) {
      res[[p]] <- list(status = "unreadable",
                       rules = job$taskException$exceptionMessage %||%
                               "veraPDF could not parse this file")
    } else if (isTRUE(vr$compliant)) {
      res[[p]] <- list(status = "passed", rules = character())
    } else {
      res[[p]] <- list(status = "failed",
                       rules = vapply(vr$details$ruleSummaries, rule_line, ""))
    }
  }
  res
}

#' Validate a target's published PDFs against PDF/UA-1
#'
#' Runs veraPDF over every PDF in the target's rendered output. A PDF this
#' course builds from a `.qmd` or `.Rmd` and that fails is a finding whose fix
#' target is that source file. A PDF the course only carries is reported and
#' never a finding. Without veraPDF every PDF is reported as not checked.
#'
#' veraPDF tests what a machine can test: tags, structure, language, title,
#' table headers. Reading order and whether the text makes sense read aloud
#' still need a person.
#'
#' @param tgt A target from [discover_target()].
#' @param surface Surface these results belong to.
#' @param verapdf The veraPDF launcher, or `NA` for none.
#' @return A list with `results` (one row per PDF: `surface`, `file`,
#'   `origin`, `source_file`, `status`, and a `rules` list column),
#'   `findings` (a findings data frame) and `checked` (whether veraPDF ran).
#' @export
check_published_pdfs <- function(tgt, surface, verapdf = find_verapdf()) {
  pdfs <- published_pdfs(tgt)
  no_findings <- finding("x","x","x","x","x","x","x")[0, ]
  usable <- nrow(pdfs) > 0 && verapdf_usable(verapdf)
  pdfs$surface <- rep(surface, nrow(pdfs))
  pdfs$status  <- rep("not checked", nrow(pdfs))
  pdfs$rules   <- I(rep(list(character()), nrow(pdfs)))
  if (!usable) {
    return(list(results = pdfs, findings = no_findings, checked = FALSE))
  }

  abs <- normalizePath(file.path(tgt$output_dir, pdfs$file))
  res <- list()
  for (b in split(abs, ceiling(seq_along(abs) / VERAPDF_BATCH))) {
    res <- c(res, run_verapdf(verapdf, b))
  }
  pdfs$status <- vapply(abs, function(p) res[[p]]$status, "", USE.NAMES = FALSE)
  pdfs$rules  <- I(lapply(abs, function(p) res[[p]]$rules))

  out <- list()
  for (i in which(pdfs$origin == "built" & pdfs$status != "passed")) {
    f <- finding(
      surface = surface, file = pdfs$file[i], criterion = PDF_UA_CRITERION,
      level = NA_character_, selector = "pdf", severity = "serious",
      issue = if (pdfs$status[i] == "failed") {
        sprintf("published PDF fails %s on %d rule(s)", PDF_UA_LABEL,
                length(pdfs$rules[[i]]))
      } else {
        sprintf("published PDF could not be read by veraPDF, so %s is unverified",
                PDF_UA_LABEL)
      },
      detail = paste(pdfs$rules[[i]], collapse = "; "),
      source_file = pdfs$source_file[i], source = "verapdf")
    # The fix lands in the source that renders the PDF, never in the output.
    f$fix_target <- pdfs$source_file[i]
    out[[length(out) + 1]] <- f
  }
  list(results = pdfs,
       findings = if (length(out)) do.call(rbind, out) else no_findings,
       checked = TRUE)
}

# ---- the source side: is the PDF even built to the standard ---------------
#
# veraPDF judges the published file. The fix is one line of front matter,
# `pdf-standard: ua-1`, which makes Typst or LaTeX build a tagged PDF and
# makes Quarto validate it at render time. This check reads the source, so it
# works with or without veraPDF and names the file the fix lands in.

PDF_FORMAT_RE   <- "(^|-)(pdf|typst)$"
PDF_UA_STANDARD <- "ua-1"

qmd_front_matter <- function(path) {
  lines <- readLines(path, warn = FALSE)
  if (!length(lines) || !grepl("^---\\s*$", lines[1])) return(list())
  end <- which(grepl("^(---|\\.\\.\\.)\\s*$", lines[-1]))[1]
  if (is.na(end)) return(list())
  y <- tryCatch(yaml::yaml.load(paste(lines[seq_len(end - 1L) + 1L],
                                      collapse = "\n")),
                error = function(e) NULL)
  if (is.list(y)) y else list()
}

pdf_formats <- function(meta) {
  fmt <- meta$format
  nm  <- if (is.character(fmt)) fmt else names(fmt)
  nm[grepl(PDF_FORMAT_RE, nm)]
}

# `pdf-standard` may sit at the top level or under the format, and may be one
# value or several (e.g. [a-2b, ua-1]).
declared_standards <- function(meta, fmt) {
  under <- if (is.list(meta$format) && is.list(meta$format[[fmt]])) {
    meta$format[[fmt]][["pdf-standard"]]
  }
  tolower(as.character(unlist(c(meta[["pdf-standard"]], under))))
}

#' Flag sources that render a PDF without asking for PDF/UA-1
#'
#' A `.qmd` or `.Rmd` whose front matter renders to `typst` or `pdf`, with no
#' `pdf-standard: ua-1` in its own front matter or in the project's
#' `_quarto.yml`, builds a PDF that is not tagged for assistive technology.
#' A `_quarto.yml` that declares such a format itself is flagged once.
#'
#' @param repo Repository to scan.
#' @param surface Surface these findings belong to.
#' @param exclude Repo-relative paths this project only copies rather than
#'   authors. Required, as for [check_missing_fig_alt()].
#' @return A findings data frame, one row per source and format.
#' @export
check_pdf_standard <- function(repo, surface, exclude) {
  require_exclude(exclude, "check_pdf_standard")
  proj_file <- file.path(repo, "_quarto.yml")
  proj <- if (file.exists(proj_file)) {
    tryCatch(yaml::yaml.load_file(proj_file), error = function(e) list())
  } else list()
  if (!is.list(proj)) proj <- list()

  mk <- function(rel, fmt) {
    f <- finding(
      surface = surface, file = rel, criterion = PDF_UA_CRITERION,
      level = NA_character_, selector = sprintf("format:%s", fmt),
      severity = "serious",
      issue = sprintf("renders to %s without `pdf-standard: %s`, so the PDF is not built to %s",
                      fmt, PDF_UA_STANDARD, PDF_UA_LABEL),
      detail = sprintf("Add `pdf-standard: %s` under `format: %s:` in %s.",
                       PDF_UA_STANDARD, fmt, rel),
      source_file = rel, source = "custom")
    f$fix_target <- rel
    f
  }

  out <- list()
  for (fmt in pdf_formats(proj)) {
    if (!PDF_UA_STANDARD %in% declared_standards(proj, fmt)) {
      out[[length(out) + 1]] <- mk("_quarto.yml", fmt)
    }
  }
  root <- normalizePath(repo)
  for (q in source_files_for_checks(repo, exclude)) {
    meta <- qmd_front_matter(q)
    rel  <- sub(paste0(root, "/"), "", normalizePath(q), fixed = TRUE)
    for (fmt in pdf_formats(meta)) {
      std <- c(declared_standards(meta, fmt), declared_standards(proj, fmt))
      if (!PDF_UA_STANDARD %in% std) out[[length(out) + 1]] <- mk(rel, fmt)
    }
  }
  if (length(out)) do.call(rbind, out) else finding("x","x","x","x","x","x","x")[0, ]
}
