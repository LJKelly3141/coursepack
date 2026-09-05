proj_path <- function(proj, p) if (startsWith(p, "/")) p else file.path(proj, p)

read_yaml_under <- function(proj, name) {
  f <- file.path(proj, name)
  if (!file.exists(f)) stop("no ", name, " under ", proj, call. = FALSE)
  yaml::yaml.load_file(f)
}

#' Read a course's manifests
#'
#' `read_course()` and `read_modules()` parse `course.yml` and `modules.yml`
#' under `proj`. `read_manifest()` parses both and names the `pages:`,
#' `assignments:` and `quizzes:` definitions by slug or id, stopping on a
#' duplicate, because every later step indexes by those names.
#'
#' @section Optional keys these readers pass through:
#' Nothing here validates a key it does not use, so a key added for a later
#' step travels untouched. The ones a course may write today:
#'
#'   `module_id:` on a module, `item_id:` on a module item, and `resource_id:`
#'   on a page, assignment or quiz definition replace the derived Canvas id.
#'   Each must be "g" plus 32 hex; see `check_gid()`.
#'
#'   `published:` on a module item. On a header, page or link it is that
#'   item's own state. On an assignment or quiz item it may not claim more
#'   than the definition holds.
#'
#'   `height_measured:` on an iframe page records when `height:` was last
#'   measured. The cartridge builder reads `height:` and ignores this one.
#'
#'   `source:` in `reference.yml` names a cartridge whose resources a course
#'   can carry forward, and `source_ref:` on a definition names one of them.
#'   Nothing carries a resource yet; a declared source with nothing carried is
#'   reported by `build_cartridge()`.
#' @param proj Course project root.
#' @return `read_manifest()` returns `list(course, mods, pages, assignments, quizzes)`.
#' @export
read_course <- function(proj) read_yaml_under(proj, "course.yml")

#' @rdname read_course
#' @export
read_modules <- function(proj) read_yaml_under(proj, "modules.yml")

named_by <- function(x, key, what) {
  if (is.null(x) || !length(x)) return(stats::setNames(list(), character()))
  keys <- vapply(x, function(e) as.character(e[[key]] %||% ""), "")
  if (any(!nzchar(keys))) stop("a ", what, " has no ", key, ":", call. = FALSE)
  if (anyDuplicated(keys)) stop("duplicate ", what, " ", key, ": ",
                                paste(unique(keys[duplicated(keys)]), collapse = ", "), call. = FALSE)
  stats::setNames(x, keys)
}

#' @rdname read_course
#' @export
read_manifest <- function(proj) {
  course <- read_course(proj); mods <- read_modules(proj)
  list(course = course, mods = mods,
       pages = named_by(mods$pages, "slug", "page"),
       assignments = named_by(mods$assignments, "id", "assignment"),
       quizzes = named_by(mods$quizzes, "id", "quiz"))
}

#' @rdname read_course
#' @export
read_reference <- function(proj) {
  f <- file.path(proj, "reference.yml")
  if (!file.exists(f)) return(NULL)
  yaml::yaml.load_file(f)
}

#' Read and validate announcements.yml
#'
#' Optional as a file, binding once present. Every message below is the one
#' the original course builder printed; the checks moved here so a defective file
#' stops the build before anything is staged.
#' @param proj Course project root.
#' @return `NULL` when the file is absent, else `list(body_dir, tz, first_day, last_day, announcements)`.
#' @export
read_announcements <- function(proj) {
  ann_file <- file.path(proj, "announcements.yml")
  if (!file.exists(ann_file)) return(NULL)
  ay <- yaml::yaml.load_file(ann_file)
  if (is.null(ay$body_dir) || !nzchar(ay$body_dir))
    stop("announcements.yml has no body_dir:", call. = FALSE)
  body_dir <- proj_path(proj, ay$body_dir)
  tm <- ay$term
  if (is.null(tm$timezone) || is.null(tm$first_day) || is.null(tm$last_day))
    stop("announcements.yml needs term: timezone, first_day and last_day. ",
         "Every post time is read in that zone and must fall inside that window.", call. = FALSE)
  tz <- as.character(tm$timezone)
  if (!tz %in% OlsonNames())
    stop("announcements.yml: timezone '", tz, "' is not an IANA zone name ",
         "(for example America/Chicago)", call. = FALSE)
  ymd <- function(x, what) {
    x <- as.character(x)
    if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x))
      stop("announcements.yml: ", what, " must be YYYY-MM-DD, got: ", x, call. = FALSE)
    d <- as.Date(x); if (is.na(d)) stop("announcements.yml: ", what, " is not a real date: ", x, call. = FALSE)
    d
  }
  first <- ymd(tm$first_day, "term first_day"); last <- ymd(tm$last_day, "term last_day")
  if (first > last) stop("announcements.yml: term first_day is after last_day", call. = FALSE)
  anns <- ay$announcements
  if (is.null(anns) || !length(anns))
    stop("announcements.yml declares no announcements. Delete the file if none are wanted; ",
         "an empty declaration is indistinguishable from a forgotten one.", call. = FALSE)
  for (a in anns) for (need in c("id", "title", "body", "post"))
    if (is.null(a[[need]]) || !nzchar(trimws(as.character(a[[need]]))))
      stop("announcements.yml: an announcement is missing ", need, ": ",
           if (is.null(a$id)) "(no id)" else a$id, call. = FALSE)
  anns <- stats::setNames(anns, vapply(anns, `[[`, "", "id"))
  for (fld in c("id", "title", "body")) {
    v <- vapply(anns, function(a) as.character(a[[fld]]), "")
    if (anyDuplicated(v))
      stop("announcements.yml: duplicate ", fld, ": ", paste(unique(v[duplicated(v)]), collapse = ", "), call. = FALSE)
  }
  list(body_dir = body_dir, tz = tz, first_day = first, last_day = last, announcements = anns)
}

#' The course timezone
#'
#' Read from `course$term$timezone`. There is no default: a default zone is a
#' fact about one instructor, and a wrong zone moves every due date and every
#' announcement by hours while looking fine in the XML.
#' @param course A parsed `course.yml`.
#' @export
read_timezone <- function(course) {
  tz <- if (is.list(course$term)) course$term$timezone else NULL
  if (is.null(tz) || !is.character(tz) || !nzchar(tz) || !tz %in% OlsonNames())
    stop("course.yml needs term: timezone: <IANA name>, for example America/Chicago", call. = FALSE)
  tz
}

#' Where the rendered textbook lives
#'
#' `textbook_docs:` is the one place a checkout location is recorded. The
#' literal value `none` means the course has no separate textbook and every
#' textbook check skips loudly. An absent key is an error, never a guess.
#' @param course A parsed `course.yml`.
#' @param proj Course project root; relative values resolve against it.
#' @return An absolute path, or `NULL` for `none`.
#' @export
textbook_docs_path <- function(course, proj) {
  v <- course$textbook_docs
  if (is.null(v))
    stop("course.yml needs textbook_docs: a path to the rendered textbook, or none", call. = FALSE)
  if (identical(v, "none")) return(NULL)
  proj_path(proj, v)
}

#' The course slug used in the cartridge filename
#'
#' `slug:` in `course.yml` when set, else the slugified Canvas course code,
#' else the slugified `code`. Decision D1 of the portable plan.
#' @param course A parsed `course.yml`.
#' @export
course_slug <- function(course) {
  course$slug %||% slugify(course$canvas$course_code %||% course$code)
}
