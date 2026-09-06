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
#'   `course_id:` and `manifest_id:` in `course.yml` do the same for the two
#'   identifiers a course carries as a whole: the one on `<course>` in
#'   `course_settings.xml` and the one on `<manifest>` in `imsmanifest.xml`.
#'   Both are otherwise derived from `code:`, and both must be "g" plus 32 hex.
#'   `extract_manifest()` writes them, because an export carries the Canvas
#'   course code rather than the `code:` those ids were derived from.
#'
#'   `all_day_date:` on a carried assignment or quiz definition is the local
#'   calendar day Canvas displays for an end-of-day deadline. Without it the
#'   day is the `due:` date's own, which is right for a course whose `due:` is
#'   local and wrong for one whose `due:` is the UTC instant an export stored.
#'   It needs a `due:` beside it and must be `YYYY-MM-DD`.
#'
#'   `published:` on a module item. On a header, page or link it is that
#'   item's own state. On an assignment or quiz item it may not claim more
#'   than the definition holds.
#'
#'   `height_measured:` on an iframe page records when `height:` was last
#'   measured. The cartridge builder reads `height:` and ignores this one.
#'
#'   `homework_intro:` and `submission_note:` under `assignment_defaults:` in
#'   `course.yml`, or on one assignment definition, are the HTML that sits
#'   above and below the copied directions in an assignment body.
#'   `homework_intro:` fills `{href}` and `{title}` from the textbook link and
#'   defaults to one neutral sentence; `submission_note:` defaults to empty,
#'   and an empty note appends nothing.
#'
#'   `source:` in `reference.yml` names a cartridge whose resources a course
#'   can carry forward, and `source_ref:` on a definition names one of them. A
#'   carried definition needs a `title:` and declares no body key of its own;
#'   a declared source with nothing carried is reported by `build_cartridge()`.
#'
#'   `carry:` in `course.yml` holds the settings that apply to carried
#'   resources. Its one key today is `repair_html:`, which defaults to `true`
#'   and repairs two accessibility defects in the carried bytes on the way into
#'   the cartridge: a `<th>` with no `scope`, and a leading bold paragraph used
#'   as a heading. Set it to `false` and every carried file travels exactly as
#'   the source wrote it, apart from the title and the due date. Anything other
#'   than `true` or `false` stops the build.
#' @param proj Course project root.
#' @return `read_manifest()` returns `list(course, mods, pages, assignments, quizzes)`.
#' @examples
#' root <- init_course(tempfile("course-"), code = "ABCD 101",
#'                     title = "Demo Course", site_url = "https://example.org/demo",
#'                     timezone = "America/Chicago", git = FALSE, skills = FALSE)
#' read_course(root)$code
#' names(read_modules(root))
#' m <- read_manifest(root)
#' names(m)
#' # The definitions are named by slug or id, ready to index.
#' names(m$pages)
#' # reference.yml is optional, and a fresh scaffold carries none.
#' read_reference(root)
#' unlink(root, recursive = TRUE)
#' @export
read_course <- function(proj) read_yaml_under(proj, "course.yml")

#' @rdname read_course
#' @export
read_modules <- function(proj) read_yaml_under(proj, "modules.yml")

# ---- one body form per definition ----------------------------------------
#
# Every page, assignment and quiz definition says exactly once where its
# content comes from. The keys that say it, per kind:
#
#   page        iframe, body, source_ref
#   assignment  homework, quiz_file, todo, description, source_ref
#   quiz        qti, bank, source_ref
#
# Two of them on one definition is two different answers to that question, and
# whichever the builder happened to prefer would be invisible in the output: a
# quiz declaring both `qti:` and `source_ref:` builds either the R/exams zip or
# the carried bytes, looks right in Canvas either way, and only a byte diff
# tells which. None of them is a definition with no body at all, which imports
# as an empty page or an assignment with no directions.
#
# The one admitted pair is `todo:` beside `homework:`. A placeholder names the
# chapter it is waiting on, and the todo/published rule keeps it unpublished
# until the chapter exists; the pair is checked below rather than merged into
# one key so that rule keeps something to read.
DEFINITION_FORMS <- list(
  page = c("iframe", "body", "source_ref"),
  assignment = c("homework", "quiz_file", "todo", "description", "source_ref"),
  quiz = c("qti", "bank", "source_ref"))

check_definition_shape <- function(defs, what) {
  forms <- DEFINITION_FORMS[[what]]
  said <- paste0(". Exactly one key says where a ", what, "'s content comes from.")
  for (k in names(defs)) {
    have <- intersect(names(defs[[k]]), forms)
    # A placeholder that names its chapter carries both; the chapter is what the
    # placeholder is waiting for, not a second body.
    if (identical(what, "assignment") && all(c("todo", "homework") %in% have))
      have <- setdiff(have, "todo")
    if (length(have) > 1L)
      stop(what, " '", k, "' declares more than one of ", paste(forms, collapse = ", "),
           ": ", paste(have, collapse = " and "), said, call. = FALSE)
    if (!length(have))
      stop(what, " '", k, "' declares none of ", paste(forms, collapse = ", "), said,
           " A definition with none has no body to build, and an empty one ",
           "imports into Canvas without complaint.", call. = FALSE)
  }
  invisible(NULL)
}

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
  m <- list(course = course, mods = mods,
            pages = named_by(mods$pages, "slug", "page"),
            assignments = named_by(mods$assignments, "id", "assignment"),
            quizzes = named_by(mods$quizzes, "id", "quiz"))
  # The definition shape is checked HERE rather than in the builder, so
  # check_manifests() rejects a definition that says both "carry these bytes"
  # and "generate a body", or says neither, before anything has been built.
  for (kind in c("page", "assignment", "quiz")) {
    defs <- switch(kind, page = m$pages, assignment = m$assignments, quiz = m$quizzes)
    check_definition_shape(defs, kind)
    check_carried_shape(defs, kind)
  }
  m
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
#'
#' `term:` in `announcements.yml` is optional. Absent, the zone and the window
#' come from `course$term`, which is where every other dated thing in the course
#' reads them, so the two files cannot drift apart. Present, it wins, because a
#' course that deliberately posts on a different calendar has to be able to say so.
#'
#' The zone is always required: it is what a post time is read in. The window,
#' `first_day` and `last_day`, is required only when at least one announcement
#' posts on a date, because that window exists to catch a post time outside the
#' term and an announcement that posts on import has no time to catch. A fresh
#' scaffold is exactly that case: its term dates are null until someone reads
#' them off the registrar's calendar, and its one announcement posts on import,
#' so it builds before those dates are in without any of them being invented.
#' @param proj Course project root.
#' @param course A parsed `course.yml`, or `NULL`. Supplies `term:` when
#'   `announcements.yml` omits it.
#' @return `NULL` when the file is absent, else `list(body_dir, tz, first_day,
#'   last_day, announcements)`. `first_day` and `last_day` are `NULL` when no
#'   announcement posts on a date.
#' @examples
#' root <- init_course(tempfile("course-"), code = "ABCD 101",
#'                     title = "Demo Course", site_url = "https://example.org/demo",
#'                     timezone = "America/Chicago", git = FALSE, skills = FALSE)
#' ann <- read_announcements(root, read_course(root))
#' ann$tz
#' names(ann$announcements)
#' # The scaffold's one announcement posts on import, so the term window is
#' # not needed yet and comes back NULL.
#' ann$first_day
#' unlink(root, recursive = TRUE)
#' @export
read_announcements <- function(proj, course = NULL) {
  ann_file <- file.path(proj, "announcements.yml")
  if (!file.exists(ann_file)) return(NULL)
  ay <- yaml::yaml.load_file(ann_file)
  if (is.null(ay$body_dir) || !nzchar(ay$body_dir))
    stop("announcements.yml has no body_dir:", call. = FALSE)
  body_dir <- proj_path(proj, ay$body_dir)

  # The declarations are read before the term, because whether a term window is
  # needed at all is a property of what they say.
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
  # Anything that is not the literal `immediately` is treated as a post time
  # here, including a form `parse_when()` will later refuse. A window is then
  # asked for on a value that turns out to be unparseable, which is the safe
  # way round: the alternative is deciding a malformed post: needs no checking.
  dated <- names(anns)[vapply(anns, function(a)
    !identical(trimws(as.character(a$post)), "immediately"), TRUE)]

  tm <- ay$term
  if (is.null(tm)) tm <- if (is.list(course$term)) course$term else NULL
  if (is.null(tm$timezone))
    stop("announcements.yml needs term: timezone:, in its own term: block or in ",
         "course.yml. Every post time is read in that zone.", call. = FALSE)
  tz <- as.character(tm$timezone)
  if (!tz %in% OlsonNames())
    stop("announcements.yml: timezone '", tz, "' is not an IANA zone name ",
         "(for example America/Chicago)", call. = FALSE)

  first <- NULL; last <- NULL
  if (length(dated)) {
    if (is.null(tm$first_day) || is.null(tm$last_day))
      stop("announcements.yml needs term: timezone, first_day and last_day. ",
           "Every post time is read in that zone and must fall inside that window. ",
           "The window is needed because these post on a date: ",
           paste(dated, collapse = ", "),
           ". An announcement that posts immediately needs no window.", call. = FALSE)
    ymd <- function(x, what) {
      x <- as.character(x)
      if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x))
        stop("announcements.yml: ", what, " must be YYYY-MM-DD, got: ", x, call. = FALSE)
      d <- as.Date(x); if (is.na(d)) stop("announcements.yml: ", what, " is not a real date: ", x, call. = FALSE)
      d
    }
    first <- ymd(tm$first_day, "term first_day"); last <- ymd(tm$last_day, "term last_day")
    if (first > last) stop("announcements.yml: term first_day is after last_day", call. = FALSE)
  }
  list(body_dir = body_dir, tz = tz, first_day = first, last_day = last, announcements = anns)
}

#' The course timezone
#'
#' Read from `course$term$timezone`. There is no default: a default zone is a
#' fact about one instructor, and a wrong zone moves every due date and every
#' announcement by hours while looking fine in the XML.
#' @param course A parsed `course.yml`.
#' @return The IANA zone name, a length-one character vector. Stops when
#'   `course.yml` declares no `term: timezone:` or names a zone R does not know.
#' @examples
#' root <- init_course(tempfile("course-"), code = "ABCD 101",
#'                     title = "Demo Course", site_url = "https://example.org/demo",
#'                     timezone = "America/Chicago", git = FALSE, skills = FALSE)
#' read_timezone(read_course(root))
#' unlink(root, recursive = TRUE)
#' # The zone is read straight off the parsed term block.
#' read_timezone(list(term = list(timezone = "America/New_York")))
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
#' @examples
#' root <- init_course(tempfile("course-"), code = "ABCD 101",
#'                     title = "Demo Course", site_url = "https://example.org/demo",
#'                     timezone = "America/Chicago", git = FALSE, skills = FALSE)
#' course <- read_course(root)
#' # The scaffold writes textbook_docs: none, so there is no path to hand back
#' # and every textbook check skips loudly.
#' textbook_docs_path(course, root)
#' # A relative value resolves against the project root.
#' course$textbook_docs <- "textbook/_book"
#' textbook_docs_path(course, root)
#' unlink(root, recursive = TRUE)
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
#' @return The slug, a length-one character vector.
#' @examples
#' # A declared slug: wins.
#' course_slug(list(slug = "stat-101", code = "STAT 101"))
#' # No slug:, so the Canvas course code is slugified.
#' course_slug(list(code = "ABCD 101", canvas = list(course_code = "ABCD 101 F26")))
#' # Neither, so code: is.
#' course_slug(list(code = "ABCD 101"))
#' @export
course_slug <- function(course) {
  course$slug %||% slugify(course$canvas$course_code %||% course$code)
}
