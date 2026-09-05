# Emit a data model of the course for the local mockup, plus the static page
# that renders it. See log/decisions/008-local-course-mockup.md.
#
# This writes a MODEL, not HTML. The page builds its DOM from the JSON at
# runtime. That is deliberate: drag-to-reorder writing back into modules.yml is
# wanted later, and it mutates a model rather than reverse-engineering markup.
#
# Nothing here is course-specific. It reads course.yml and modules.yml and works
# for any course using that pattern.

#' Build the local course preview
#'
#' Writes the preview model and static assets under `build/mockup/`. Serve that
#' directory from the course root with `python3 -m http.server` so browser
#' iframe origin rules permit the local textbook symlink.
#'
#' @param proj Course project root.
#' @param base Whether textbook links use the local same-origin textbook or the live URL.
#' @param textbook_docs Optional path to rendered textbook documents. When `NULL`,
#'   read `textbook_docs` from `course.yml`.
#' @return The preview model, invisibly.
#' @export
build_preview <- function(proj = ".", base = c("local", "live"), textbook_docs = NULL) {
  base <- match.arg(base)
  manifest <- read_manifest(proj)
  course <- manifest$course
  mods <- manifest$mods
  pages <- manifest$pages
  asg <- manifest$assignments

  # The textbook checkout is a local filesystem path, so it lives in
  # course.yml's `textbook_docs:` key. A relative course.yml value resolves
  # against the project root; the function argument permits a one-off override.
  tb_docs <- if (!is.null(textbook_docs)) textbook_docs else textbook_docs_path(course, proj)
  mode <- base

out   <- file.path(proj, "build", "mockup")
unlink(out, recursive = TRUE)          # same reason as build_cartridge.R: stale files lie
dir.create(out, recursive = TRUE, showWarnings = FALSE)

# In local mode the textbook is served from a sibling path on the same origin.
# Chrome blocks file:// iframes from a file:// page, so this is served over HTTP
# and the symlink keeps it same-origin. See the decision record.
tb_base <- if (mode == "local") "/textbook" else course$urls$textbook
urls    <- course$urls
urls$textbook <- tb_base


TYPE <- c(header = "ContextModuleSubHeader", page = "WikiPage",
          link = "ExternalUrl", assignment = "Assignment", quiz = "Quizzes::Quiz")

nn <- function(x, d = NULL) if (is.null(x)) d else x

# modules.yml carries some page width/height values as bare digit strings
# ("630", "1120"): valid HTML iframe attributes, but not valid CSS lengths.
# Assigning a bare number to element.style.height in the browser is silently
# ignored, so those previews collapsed to the ~150px default. Append "px" to
# anything that is all digits; leave values that already carry a unit
# ("2000px") or a percentage ("100%") alone.
css_len <- function(x) if (!is.null(x) && grepl("^[0-9]+$", x)) paste0(x, "px") else x

build_item <- function(it, pos, mod_published) {
  form <- intersect(names(TYPE), names(it))
  if (length(form) != 1L) stop("item ", pos, " has ", length(form), " type keys")
  form <- form[[1]]

  title <- NULL; url <- NULL; frame <- NULL; todo <- NULL; points <- NULL
  published <- mod_published
  target <- list(state = "none", detail = "")

  if (form == "header") {
    title <- it$header

  } else if (form == "page") {
    p <- pages[[it$page]]
    if (is.null(p)) stop("page slug not defined: ", it$page)
    title <- p$title

    if (isTRUE(p$body)) {
      # A generated page. Its body is real HTML that the cartridge embeds
      # directly, so the preview must show THAT rather than an empty frame.
      #
      # This matters more than it looks. The preview's only job is to be honest
      # about what ships, and 38 of the 44 pages now use this form. Left
      # unhandled, every chapter and every module overview would preview as a
      # blank pane while the cartridge shipped a full page, which is precisely
      # the failure mode the skill's own rule names: "a preview that differs
      # from what ships is lying about its only job."
      #
      # The body is written into the served directory rather than inlined,
      # because the pane is an iframe and a same-origin file keeps that working
      # without a data: URI or a CSP argument.
      url <- paste0("pages/", it$page, ".html")
      frame <- list(width = "100%", height = "900px")
    } else {
      url   <- interp_urls(p$iframe, urls)
      frame <- list(width = css_len(nn(p$width, "100%")), height = css_len(nn(p$height, "800px")))
    }

  } else if (form == "link") {
    title <- it$link
    if (!is.null(it$chapter)) {
      url    <- chapter_url(it$chapter, it$anchor, tb_base)
      target <- resolve_target(it$chapter, it$anchor, tb_docs)
    } else {
      url    <- interp_urls(it$url, urls)
      target <- list(state = "external", detail = "off-textbook URL, not checked")
    }

  } else if (form == "assignment") {
    a <- asg[[it$assignment]]
    if (is.null(a)) stop("assignment id not defined: ", it$assignment)
    title     <- a$title
    published <- isTRUE(a$published)
    todo      <- a$todo
    points    <- nn(a$points, course$assignment_defaults$points)
    if (!is.null(a$homework$chapter)) {
      # Still resolve the textbook target, because that check is what catches a
      # renamed heading before it becomes a broken assignment.
      target <- resolve_target(a$homework$chapter, a$homework$anchor, tb_docs)

      # Since 2026-09-01 the directions are COPIED into the Canvas assignment
      # rather than linked to, so previewing the chapter would no longer show
      # what a student actually sees. Render the same body the cartridge builds.
      if (!is.null(a$homework$anchor) && identical(target$state, "ok")) {
        adir <- file.path(out, "assignments")
        dir.create(adir, recursive = TRUE, showWarnings = FALSE)
        afile <- paste0(a$id, ".html")
        body <- tryCatch(
          homework_section_html(a$homework$chapter, a$homework$anchor,
                                tb_docs, tb_base, a$id),
          error = function(e) paste0("<p><strong>Could not extract directions:</strong> ",
                                     conditionMessage(e), "</p>"))
        writeLines(paste0(
          '<!doctype html><html><head><meta charset="utf-8"><title>', a$title, '</title>',
          '<style>body{font:15px/1.6 -apple-system,system-ui,sans-serif;',
          'max-width:46em;margin:2rem auto;padding:0 1.5rem;color:#1a1a1a}',
          'h1,h2,h3{line-height:1.25}code{background:#f4f4f5;padding:.1em .3em;',
          'border-radius:3px}pre{background:#f4f4f5;padding:1rem;overflow-x:auto}',
          'table{border-collapse:collapse}td,th{border:1px solid #d4d4d8;padding:.3rem .5rem}',
          '</style></head><body>', body, '</body></html>'), file.path(adir, afile))
        url <- paste0("/assignments/", afile)
      } else {
        url <- chapter_url(a$homework$chapter, a$homework$anchor, tb_base)
      }

    } else if (!is.null(a$quiz_file)) {
      # A quiz carries its questions in its own Canvas description rather than
      # linking out, so there is no external target to preview. Without this
      # branch the item renders as a bare title and a point value, which is
      # useless for reviewing seventy questions before an import.
      #
      # The HTML comes from the SAME function build_cartridge.R uses, so what
      # is reviewed here is exactly what ships. See scripts/lib/quiz_body.R.
      qdir <- file.path(out, "quizzes")
      dir.create(qdir, recursive = TRUE, showWarnings = FALSE)
      qfile <- paste0(a$id, ".html")
      writeLines(paste0(
        '<!doctype html><html><head><meta charset="utf-8">',
        '<title>', a$title, '</title>',
        '<style>body{font:15px/1.6 -apple-system,system-ui,sans-serif;',
        'max-width:46em;margin:2rem auto;padding:0 1.5rem;color:#1a1a1a}',
        'h1,h2,h3{line-height:1.25}code{background:#f4f4f5;padding:.1em .3em;',
        'border-radius:3px}pre{background:#f4f4f5;padding:1rem;overflow-x:auto}',
        'blockquote{border-left:3px solid #d4d4d8;margin-left:0;padding-left:1rem;',
        'color:#52525b}</style></head><body>',
        quiz_student_html(file.path(proj, a$quiz_file), a$id, course$urls$site),
        '</body></html>'), file.path(qdir, qfile))
      url    <- paste0("/quizzes/", qfile)
      target <- list(state = "ok", detail = "quiz questions, answer key withheld")
    }

  } else if (form == "quiz") {
    q <- nn(mods$quizzes, list())
    q <- Filter(function(z) identical(z$id, it$quiz), q)
    if (!length(q)) stop("quiz id not defined: ", it$quiz)
    title     <- q[[1]]$title
    published <- isTRUE(q[[1]]$published)
  }

  list(position = pos, form = form, content_type = unname(TYPE[[form]]),
       title = title, indent = as.integer(nn(it$indent, 0L)),
       url = url, published = published, todo = todo, points = points,
       frame = frame, target = target)
}

modules <- list()
for (mi in seq_along(mods$modules)) {
  m  <- mods$modules[[mi]]
  mp <- isTRUE(m$published)          # matches build_cartridge.R:130; absent means unpublished
  items <- list()
  for (ii in seq_along(m$items))
    items[[ii]] <- build_item(m$items[[ii]], ii, mp)
  modules[[mi]] <- list(title = m$title, published = mp,
                        sequential = isTRUE(m$sequential),
                        position = mi, items = items)
}

all_items <- unlist(lapply(modules, function(m) m$items), recursive = FALSE)
st <- function(f) sum(vapply(all_items, f, TRUE))

model <- list(
  course = list(code = course$code, section = as.character(nn(course$section, "")),
                title = course$title, institution = course$institution,
                term = as.character(nn(course$term, "")),
                base_mode = mode, textbook_base = tb_base,
                textbook_present = dir.exists(tb_docs),
                generated = format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  stats = list(
    modules            = length(modules),
    items              = length(all_items),
    unpublished_modules= sum(vapply(modules, function(m) !isTRUE(m$published), TRUE)),
    unpublished_items  = st(function(i) !isTRUE(i$published)),
    todo               = st(function(i) !is.null(i$todo)),
    broken             = st(function(i) i$target$state %in% c("missing-chapter", "missing-anchor")),
    unchecked          = st(function(i) identical(i$target$state, "unchecked"))),
  modules = modules)

jsonlite::write_json(model, file.path(out, "course.json"),
           auto_unbox = TRUE, null = "null", pretty = TRUE)

tpl <- system.file("templates", "mockup", package = "coursepack")
if (!nzchar(tpl)) stop("coursepack mockup templates are not installed", call. = FALSE)
for (f in list.files(tpl)) file.copy(file.path(tpl, f), file.path(out, f), overwrite = TRUE)

# Generated page bodies, wrapped so they render standalone in a preview pane.
# The wrapper is presentation only; the cartridge embeds the same inner HTML
# with Canvas's own metadata head, so what is previewed is what ships.
#
# Media is referenced by absolute Pages URL in these bodies. If the media has
# not been pushed yet, images and players will be broken IN THE PREVIEW while
# being correct in the cartridge. That is a property of previewing unpublished
# assets, not a defect, and it is stated here so nobody debugs it twice.
canvas_dir <- file.path(proj, "content", "canvas")
if (dir.exists(canvas_dir)) {
  pdir <- file.path(out, "pages"); dir.create(pdir, showWarnings = FALSE)
  n <- 0L
  for (f in list.files(canvas_dir, "\\.html$", full.names = TRUE)) {
    slug <- tools::file_path_sans_ext(basename(f))
    ttl  <- if (!is.null(pages[[slug]]$title)) pages[[slug]]$title else slug
    writeLines(c(
      '<!doctype html><html><head><meta charset="utf-8">',
      paste0('<title>', ttl, '</title>'),
      '<style>body{font:15px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;',
      'max-width:900px;margin:0 auto;padding:24px;color:#2d3b45;}',
      'h3{margin-top:1.6em;font-size:1.05rem;color:#394b58;}',
      'img{max-width:100%;height:auto;border:1px solid #e5e5e5;border-radius:3px;}',
      'a{color:#0374b5;}</style></head><body>',
      readLines(f, warn = FALSE),
      '</body></html>'), file.path(pdir, paste0(slug, ".html")))
    n <- n + 1L
  }
  cat("generated page bodies: ", n, "\n", sep = "")
} else {
  cat("NOTE: content/canvas/ missing.\n")
  cat("      every chapter and module page will preview blank without it.\n")
}

# Same-origin textbook. Chrome refuses a file:// iframe from a file:// page, so
# the mockup is served over HTTP and the textbook is reached through this
# symlink inside the served directory. The path is computed once, here, so the
# Makefile does not need a second copy of it.
if (mode == "local") {
  if (dir.exists(tb_docs)) {
    file.symlink(normalizePath(tb_docs), file.path(out, "textbook"))
    cat("linked textbook: ", normalizePath(tb_docs), "\n", sep = "")
  } else {
    cat("NOTE: no textbook build at ", tb_docs, "\n", sep = "")
    cat("      previews will be empty. Render it, or use base = \"live\".\n")
  }
}

cat(sprintf("mockup model: %d modules, %d items  (base=%s)\n",
            model$stats$modules, model$stats$items, mode))
cat(sprintf("  unpublished items %d | todo %d | broken targets %d | unchecked %d\n",
            model$stats$unpublished_items, model$stats$todo,
            model$stats$broken, model$stats$unchecked))
# Warn off the directory check, NOT off the unchecked count. `unchecked` also
# counts items with no chapter to check (the deliberate chapter: "" root link),
# so it is never zero and warning off it would cry wolf on every healthy build.
if (!dir.exists(tb_docs))
  cat("  NOTE: textbook not found at ", tb_docs, "; targets unverified.\n", sep = "")
cat("wrote ", file.path(out, "course.json"), "\n", sep = "")
  version_line("build_preview")
  invisible(model)
}
