# The one-off converter from the Python manifest schema to this package's.
#
# It exists because the toolchain this package replaces read a different pair of
# files: a `course.yml` whose deadlines were a map keyed by an item's exact
# title, and a `modules.yml` that inlined every page, quiz and assignment into
# the module item that used it. The package schema separates the two: a module
# item names a definition, and the definition says where its content comes from.
# A course crosses that gap exactly once, by hand, in its own session.
#
# So this is a migration, not a build step. It is exported because the human
# running it needs to call it, and it makes three promises that matter more here
# than in code that runs every day:
#
#   IDENTIFIERS ARE PINNED. A course that has already imported its cartridge has
#   objects in Canvas with identifiers derived the Python way. `gid_py()`
#   reproduces those, and every module, item and resource identifier is written
#   into the converted files, so the first import after the migration updates
#   what is there instead of creating a second copy of the whole course beside
#   it. Anything the Python file did not name is derived by the Python's own
#   rule, not by this package's.
#
#   NOTHING IS DROPPED IN SILENCE. A `generate:` key this converter does not
#   read, a `canvas:` key that is not a Canvas setting, a `due_dates` entry
#   naming nothing, an item type it cannot write: each stops. The two things
#   that genuinely have no place in the package schema, `exam_pools:` and
#   `canvas: course_image:`, are printed as notes rather than dropped quietly.
#
#   THE FILE IS CHECKED BEFORE IT IS WRITTEN. Positions, unique titles within a
#   kind, and the deadline map are all verified first, so a defective input
#   leaves no half-written pair of manifests behind.

# ---- the Python identifier convention ------------------------------------

#' A Canvas identifier derived the way the Python toolchain derived it
#'
#' `"g"` plus the md5 of the arguments joined by `"::"`. This package's own
#' `gid()` joins them with nothing, so the two disagree for every key of more
#' than one part. Both are correct; what matters is that a course adopting this
#' package keeps the identifiers its Canvas course already holds, and those were
#' written by the first rule.
#'
#' Exported because the converter's output is checked against it, and because a
#' migration session sometimes has to work out by hand which object in Canvas an
#' identifier names.
#'
#' @param ... Key parts. Coerced to character and joined with `"::"`.
#' @return A Canvas identifier: `"g"` followed by 32 hex characters.
#' @export
gid_py <- function(...) {
  key <- paste(as.character(unlist(list(...))), collapse = "::")
  paste0("g", digest::digest(key, algo = "md5", serialize = FALSE))
}

# ---- what the converter reads --------------------------------------------
#
# Every key of a `generate:` block this converter understands, per kind. A key
# outside these lists stops: the Python generator read more keys than the
# package schema has homes for, and a course that set one would otherwise find
# it silently gone after the migration, with the defect showing up in Canvas
# rather than here.
QUIZ_GENERATE_KEYS <- c(
  "kind", "bank", "chapters", "draws", "splits", "group_by", "points", "group",
  "allowed_attempts", "shuffle_answers", "quiz_type", "description",
  "unlock_at", "lock_at", "position")

ASSIGNMENT_GENERATE_KEYS <- c(
  "kind", "points", "grading_type", "submission", "allowed_extensions",
  "group", "description", "position")

# The leading comment block of a YAML file: every line from the top until the
# first that is not a comment. It is the only part of the Python file that
# carries no data and cannot be reconstructed, so it travels verbatim.
header_block <- function(path) {
  lines <- readLines(path, warn = FALSE)
  n <- 0L
  while (n < length(lines) && startsWith(lines[[n + 1L]], "#")) n <- n + 1L
  if (n == 0L) character() else lines[seq_len(n)]
}

# A definition's key in the package schema. One rule for all three kinds, so a
# reader of the converted file can go from an item's title to the definition it
# names without knowing which kind it is.
def_key <- function(title) {
  key <- slugify(title)
  if (!nzchar(key))
    stop("item '", title, "' has a title that slugifies to nothing, so it ",
         "cannot be given a definition id in modules.yml.", call. = FALSE)
  key
}

# The `bank:` block a `generate: kind: quiz` becomes. `dir:` is the converter's
# own argument rather than anything in the Python file, because the bank moved
# with the course; a Python block naming a different directory stops instead of
# being overruled in silence.
bank_block <- function(spec, bank_dir, title) {
  named <- spec$bank
  if (!is.null(named) && !identical(as.character(named), as.character(bank_dir)))
    stop(title, ": generate.bank names the directory '", as.character(named),
         "' but the converter was given bank_dir = '", bank_dir,
         "'. Pass bank_dir = '", as.character(named), "' to keep it.", call. = FALSE)
  b <- list(dir = as.character(bank_dir))
  b$chapters <- spec$chapters
  b$draws <- spec$draws
  b$splits <- spec$splits
  b$group_by <- spec$group_by
  b$points <- spec$points
  b$allowed_attempts <- spec$allowed_attempts
  b$shuffle_answers <- spec$shuffle_answers
  b$quiz_type <- spec$quiz_type
  b$description <- spec$description
  b$unlock_at <- spec$unlock_at
  b$lock_at <- spec$lock_at
  b$position <- spec$position
  b
}

check_generate_keys <- function(spec, allowed, title) {
  unknown <- setdiff(names(spec), allowed)
  if (length(unknown))
    stop(title, ": generate.", unknown[[1]], " is a key this converter does not ",
         "write, so converting would drop it. Remove it from the Python file, ",
         "or fold it into the converted manifest by hand afterward.", call. = FALSE)
  invisible(NULL)
}

# ---- the converter --------------------------------------------------------

#' Convert a course from the Python manifest schema
#'
#' Read the `course.yml` and `modules.yml` of the toolchain this package
#' replaces and write the same course under `out_dir` in the package schema.
#' Run once per course, by hand, in that course's own session; the converted
#' files are then the course's own and are hand-edited from there.
#'
#' @section What changes shape:
#' `course_code:` becomes both `code:` and `canvas: course_code:`. `urls:`,
#' `term:` and `due_time:` travel unchanged, and `textbook_docs: none` is
#' written because the Python schema had no such key. The `canvas:` block is
#' filtered through `CANVAS_SETTINGS_KEYS`; a key that is not a Canvas setting
#' stops. Assignment groups keep their identifiers, and a group that named none
#' is given the one the Python generator derived, because a carried quiz or
#' assignment names its group by identifier inside its own bytes.
#'
#' The title-keyed `due_dates:` map dissolves: each entry becomes the `due:` of
#' the definition whose title it named, and an entry naming no definition stops
#' rather than being ignored. `exam_pools:` is dropped, with a printed note when
#' it holds anything, because exams are generated from `bank:` blocks here.
#' `canvas: course_image:` is not a Canvas setting and is not written; the
#' converter prints where to put the file instead.
#'
#' Every module item becomes an item naming a definition plus the definition
#' itself. A wiki page with a `url:` becomes an `iframe:` page; one marked
#' `carry_through:` becomes a `source_ref:` page. A quiz or assignment with a
#' `generate:` block becomes a `bank:` quiz or a `description:` assignment; one
#' without becomes `source_ref:`. A generated quiz that named no group is given
#' `Module Quizzes`, which is the default the Python generator applied without
#' writing it down; a generated assignment that names no group stops, as it did
#' there. Definition ids are the slugified title.
#'
#' @section What it refuses:
#' Module positions that do not strictly increase across the file, item
#' positions that do not strictly increase within a module, two definitions of
#' one kind claiming one title, a `due_dates` key matching no definition, an
#' item type it cannot write, a `generate:` key it does not read, and a page
#' with neither a `url:` nor `carry_through:`. All of them before anything is
#' written.
#'
#' Positions themselves are not written: in the package schema a module's and an
#' item's position is its place in the file. Where a declared position and that
#' place disagree, which is what a merged module leaves behind, the converter
#' prints `positions renumbered: <old> -> <new>` so the change is on the record.
#'
#' @param course_py Path to the Python schema's `course.yml`.
#' @param modules_py Path to the Python schema's `modules.yml`.
#' @param out_dir Directory the converted `course.yml` and `modules.yml` are
#'   written into. Created if absent.
#' @param bank_dir The question bank directory, relative to the course project
#'   root, written as `dir:` in every converted `bank:` block.
#' @return `out_dir`, invisibly.
#' @export
convert_python_manifests <- function(course_py, modules_py, out_dir,
                                     bank_dir = "questions") {
  py_course <- yaml::yaml.load_file(course_py)
  py_mods <- yaml::yaml.load_file(modules_py)
  due_dates <- py_course$due_dates %||% list()
  notes <- character()

  due_for <- function(title) {
    v <- due_dates[[title]]
    if (is.null(v)) NULL else as.character(v)[[1L]]
  }

  defs <- list(page = list(), assignment = list(), quiz = list())
  mods_out <- list()
  ctypes <- character()
  carried <- character()

  prev_mpos <- 0L
  for (mi in seq_along(py_mods$modules)) {
    m <- py_mods$modules[[mi]]
    mtitle <- as.character(m$title %||% "")
    if (!nzchar(mtitle)) stop("module ", mi, " has no title:", call. = FALSE)
    mpos <- as.integer(m$position %||% mi)
    if (mpos <= prev_mpos)
      stop("module positions are not strictly increasing across the file: '",
           mtitle, "' is at position ", mpos, ", after ", prev_mpos,
           ". Two modules at one position, or a module out of order, is a ",
           "defect in the file rather than an ordering this can honor.",
           call. = FALSE)
    prev_mpos <- mpos
    if (mpos != mi)
      notes <- c(notes, sprintf("positions renumbered: %d -> %d (module '%s')",
                                mpos, mi, mtitle))

    row <- list(title = mtitle)
    row$module_id <- check_gid(m$module_id, "module_id")
    row$published <- isTRUE(m$published %||% TRUE)
    row$sequential <- isTRUE(m$require_sequential_progress)
    row$items <- list()

    prev_ipos <- 0L
    for (pi in seq_along(m$items)) {
      it <- m$items[[pi]]
      title <- as.character(it$title %||% "")
      if (!nzchar(title))
        stop("module '", mtitle, "' has an item at position ", pi, " with no title:",
             call. = FALSE)
      ipos <- as.integer(it$position %||% pi)
      if (ipos <= prev_ipos)
        stop("item positions are not strictly increasing in module '", mtitle,
             "': '", title, "' is at position ", ipos, ", after ", prev_ipos,
             ". Item positions restart at 1 in every module and must rise from ",
             "there.", call. = FALSE)
      prev_ipos <- ipos
      if (ipos != pi)
        notes <- c(notes, sprintf("positions renumbered: %d -> %d (item '%s')",
                                  ipos, pi, title))

      type <- as.character(it$type %||% "")
      ctypes <- c(ctypes, type)
      published <- isTRUE(it$published %||% TRUE)
      # The identifier the Python builder gave this item's resource: the one the
      # file names, else the one it derived. Either way it is written down here,
      # so the package's own derivation never gets the chance to replace it.
      item_res <- check_gid(it$resource_id)
      rid <- item_res %||% gid_py("res", mtitle, title)

      claim <- function(kind) {
        key <- def_key(title)
        if (!is.null(defs[[kind]][[key]]))
          stop("titles are not unique within kind: ", title, ". Two ", kind,
               "s become the definition id '", key,
               "', and the manifest can hold only one of them under that id.",
               call. = FALSE)
        key
      }

      if (identical(type, "WikiPage")) {
        key <- claim("page")
        d <- list(slug = key, title = title)
        if (isTRUE(it$carry_through)) {
          if (is.null(item_res))
            stop("page '", title, "' is marked carry_through: but names no ",
                 "resource_id:, so there is nothing in the source to carry.",
                 call. = FALSE)
          d$source_ref <- item_res
          carried <- c(carried, "page")
        } else {
          url <- as.character(it$url %||% "")
          if (!nzchar(url))
            stop("page '", title, "' has neither a url: nor carry_through:, so ",
                 "there is nothing to put in it.", call. = FALSE)
          height <- as.character(it$height %||% "")
          if (!nzchar(height))
            stop("page '", title, "' has a url: but no height:. A guessed ",
                 "height gives the frame an inner scrollbar and nobody is told.",
                 call. = FALSE)
          d$iframe <- url
          d$width <- "100%"
          d$height <- height
          d$height_measured <- if (is.null(it$height_measured)) NULL
                               else as.character(it$height_measured)
          # Pinned even when the Python file named none. The Python builder
          # derived exactly this id for a page it had no resource_id for, so
          # writing it down changes nothing about which Canvas object the page
          # is; leaving it out would let this package derive its own from the
          # slug, and the next import would create a second copy of the page.
          d$resource_id <- rid
        }
        defs$page[[key]] <- d
        form <- list(page = key)

      } else if (identical(type, "Quizzes::Quiz")) {
        key <- claim("quiz")
        spec <- it$generate
        d <- list(id = key, title = title)
        if (is.null(spec)) {
          if (is.null(item_res))
            stop("quiz '", title, "' has no generate: block and names no ",
                 "resource_id:, so there is nothing in the source to carry.",
                 call. = FALSE)
          d$published <- published
          d$due <- due_for(title)
          d$source_ref <- item_res
          carried <- c(carried, "quiz")
        } else {
          check_generate_keys(spec, QUIZ_GENERATE_KEYS, title)
          # The Python generator defaulted a quiz with no group to Module
          # Quizzes at generate_resources.py line 586, and wrote the default
          # nowhere. Written here, so the converted file says what it means.
          d$group <- as.character(spec$group %||% "Module Quizzes")
          d$published <- published
          d$due <- due_for(title)
          d$resource_id <- rid
          d$bank <- bank_block(spec, bank_dir, title)
        }
        defs$quiz[[key]] <- d
        form <- list(quiz = key)

      } else if (identical(type, "Assignment")) {
        key <- claim("assignment")
        spec <- it$generate
        d <- list(id = key, title = title)
        if (is.null(spec)) {
          if (is.null(item_res))
            stop("assignment '", title, "' has no generate: block and names no ",
                 "resource_id:, so there is nothing in the source to carry.",
                 call. = FALSE)
          d$published <- published
          d$due <- due_for(title)
          d$source_ref <- item_res
          carried <- c(carried, "assignment")
        } else {
          check_generate_keys(spec, ASSIGNMENT_GENERATE_KEYS, title)
          if (is.null(spec$group) || !nzchar(as.character(spec$group)))
            stop(title, ": generate.group (an assignment group name) is required",
                 call. = FALSE)
          html <- trimws(paste(as.character(unlist(spec$description %||% "")),
                               collapse = "\n"))
          if (!nzchar(html))
            stop(title, ": generate.description is empty. An assignment with no ",
                 "directions imports into Canvas without complaint and looks ",
                 "like a finished assignment nobody can do.", call. = FALSE)
          d$points <- spec$points
          d$grading_type <- spec$grading_type
          d$submission_types <- spec$submission
          d$allowed_extensions <- spec$allowed_extensions
          d$group <- as.character(spec$group)
          d$published <- published
          d$due <- due_for(title)
          d$resource_id <- rid
          d$description <- html
        }
        defs$assignment[[key]] <- d
        form <- list(assignment = key)

      } else if (identical(type, "ExternalUrl")) {
        url <- as.character(it$url %||% "")
        if (!nzchar(url))
          stop("link '", title, "' carries no url:. A link with no target is ",
               "not a link.", call. = FALSE)
        form <- list(link = title, url = url)
        if (isTRUE(it$new_tab)) form$new_tab <- TRUE

      } else {
        stop("module item '", title, "' has type '", type, "', which this ",
             "converter does not write. It stops rather than dropping the item, ",
             "because a manifest missing one item looks exactly like a course ",
             "that never had it.", call. = FALSE)
      }

      form$item_id <- check_gid(it$item_id, "item_id")
      form$indent <- as.integer(it$indent %||% 0L)
      form$published <- published
      row$items[[length(row$items) + 1L]] <- form
    }
    mods_out[[length(mods_out) + 1L]] <- row
  }

  # THE DEADLINE MAP. Every key named an item by its exact title, which is the
  # one handle the Python schema had. A key matching no definition is a deadline
  # nothing carries: it was silently ignored there, and it stops here.
  have <- unlist(lapply(defs, function(dd)
    vapply(dd, function(d) as.character(d$title), "")), use.names = FALSE)
  for (k in names(due_dates))
    if (!k %in% have)
      stop("due_dates names an item that does not exist: ", k,
           ". Every entry becomes the due: of the definition whose title it ",
           "names, so an entry naming nothing is a deadline that never ships.",
           call. = FALSE)

  # ---- course.yml --------------------------------------------------------
  cs <- py_course$canvas %||% list()
  image <- cs$course_image
  cs$course_image <- NULL
  unknown <- setdiff(names(cs), CANVAS_SETTINGS_KEYS)
  if (length(unknown))
    stop("unknown canvas: key: ", unknown[[1]],
         ". The canvas: block holds Canvas course settings and nothing else; ",
         "the settings this package writes are ",
         paste(CANVAS_SETTINGS_KEYS, collapse = ", "), ".", call. = FALSE)
  cs$course_code <- as.character(py_course$course_code)
  canvas <- list()
  for (k in CANVAS_SETTINGS_KEYS) if (!is.null(cs[[k]])) canvas[[k]] <- cs[[k]]

  groups <- lapply(py_course$assignment_groups %||% list(), function(g) {
    row <- list(name = as.character(g$name))
    row$id <- as.character(g$id %||% gid_py("group", g$name))
    row$position <- if (is.null(g$position)) NULL else as.integer(g$position)
    row$weight <- if (is.null(g$weight)) NULL else as.numeric(g$weight)
    row
  })

  course <- list(code = as.character(py_course$course_code),
                 title = as.character(py_course$title))
  # The Python schema has no course-wide identifiers, so both are normally
  # derived from `code:` on the first build. A Python file that carries them
  # anyway is a course that has already been told what Canvas holds.
  course$course_id <- check_gid(py_course$course_id, "course_id")
  course$manifest_id <- check_gid(py_course$manifest_id, "manifest_id")
  course$urls <- py_course$urls
  course$term <- py_course$term
  course$due_time <- if (is.null(py_course$due_time)) NULL
                     else as.character(py_course$due_time)
  course$textbook_docs <- "none"
  course$canvas <- canvas
  course$assignment_groups <- groups

  modules_out <- list(modules = mods_out)
  sections <- c(page = "pages", assignment = "assignments", quiz = "quizzes")
  for (kind in names(sections))
    if (length(defs[[kind]])) modules_out[[sections[[kind]]]] <- unname(defs[[kind]])

  if (length(py_course$exam_pools %||% list()))
    notes <- c(notes, paste0(
      "exam_pools: ", length(py_course$exam_pools), " pool(s) dropped. Exams ",
      "are generated from bank: blocks here, so the pool arithmetic has no ",
      "consumer; rewrite each exam as a quiz definition with a bank: block."))
  if (!is.null(image))
    notes <- c(notes, paste0(
      "course image: copy ", as.character(image),
      " to assets/images/course-tile.png; the builder ships it as ",
      "web_resources/course_image/course_img.png"))

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_dir <- normalizePath(out_dir, mustWork = TRUE)
  write_extracted(file.path(out_dir, "course.yml"), character(), course)
  write_extracted(file.path(out_dir, "modules.yml"), header_block(modules_py),
                  modules_out)

  cat("=== converted ===\n")
  cat(sprintf("  from %s and %s\n", basename(course_py), basename(modules_py)))
  cat(sprintf("  modules: %d\n  items:   %d\n", length(mods_out), length(ctypes)))
  for (k in unique(ctypes)) cat(sprintf("    %s: %d\n", k, sum(ctypes == k)))
  for (kind in names(sections))
    cat(sprintf("  %s: %d, of which carried: %d\n", sections[[kind]],
                length(defs[[kind]]), sum(carried == kind)))
  cat(sprintf("  due dates dissolved into definitions: %d\n", length(due_dates)))
  for (n in notes) cat("  ", n, "\n", sep = "")
  cat(sprintf("  wrote course.yml and modules.yml under %s\n", out_dir))
  cat("  positions are not written: in this schema a module's and an item's\n")
  cat("  position is its place in the file.\n")
  version_line("convert_python_manifests")
  invisible(out_dir)
}
