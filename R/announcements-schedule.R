# Weekly announcements, generated from a schedule.
#
# One announcement per week, released Monday morning, carrying that week's
# calendar: the week's notes, each class day's plan and preparation, anything
# due that day, and what is due by Sunday. The instructor lines a schedule
# carries for its own use are left out; an announcement speaks to students.
#
# This is the port of the snapshot's announcements.py, with one change that
# matters. There, the due dates came from a `due_dates:` map in course.yml keyed
# by the item's TITLE, maintained by hand beside the manifest that already held
# every due date. Two places to write one fact is one place to forget, and a
# title typed differently in the two files fell out of the announcement with
# nothing reported. Here the due items are the manifest's own definitions with
# `due:`, assignments and quizzes together, so an announcement cannot disagree
# with the cartridge it is announcing.
#
# Nothing here writes into the cartridge. It writes the two things the builder
# already reads: one HTML body per week under `out_dir`, and an
# `announcements.yml` declaring them. That keeps the generator out of the build
# path, so a course can edit a generated body by hand and rebuild, and the
# builder is none the wiser.

# Locale-independent names. format(d, "%A") is the C library's idea of the
# weekday in whatever locale R happens to be running under, which would put a
# French heading in a body on a French machine and change the bytes of an
# otherwise identical build. "%u" and "%m" are numbers everywhere.
WEEKDAYS_EN <- c("Monday", "Tuesday", "Wednesday", "Thursday", "Friday",
                 "Saturday", "Sunday")
MONTHS_EN <- c("January", "February", "March", "April", "May", "June", "July",
               "August", "September", "October", "November", "December")
WEEKDAY_KEYS <- tolower(WEEKDAYS_EN)

# "Tuesday, September 15": no leading zero on the day, which is what a person
# writing the week out by hand would type.
fmt_day <- function(d)
  paste0(WEEKDAYS_EN[as.integer(format(d, "%u"))], ", ",
         MONTHS_EN[as.integer(format(d, "%m"))], " ",
         as.integer(format(d, "%d")))

# "11:59 pm", "9:30 am". Lower case and no leading zero, again because that is
# how the time reads in a sentence.
fmt_clock <- function(t, tz) {
  h <- as.integer(format(t, "%H", tz = tz))
  h12 <- h %% 12L
  if (h12 == 0L) h12 <- 12L
  paste0(h12, ":", format(t, "%M", tz = tz), " ", if (h < 12L) "am" else "pm")
}

# An exam is called an exam. The label is read off the title because that is the
# only thing a definition carries that says what kind of thing it is.
due_label <- function(title) if (grepl("Exam", title, fixed = TRUE)) "Exam" else "Due"

# The local instant a definition's `due:` names. A bare date takes `due_time:`
# from course.yml, exactly as due_stamp() does for the cartridge, so the time an
# announcement prints is the time Canvas enforces. This returns local time
# rather than the UTC stamp due_stamp() returns, because everything below is
# about which local day and which local hour a student sees.
due_local <- function(due, due_time, tz, what) {
  due <- trimws(as.character(due))
  if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", due)) {
    if (is.null(due_time))
      stop(what, ": a bare due: date needs due_time: in course.yml ",
           "(for example \"23:59:59\"); got due: ", due, call. = FALSE)
    due <- paste(due, trimws(as.character(due_time)))
  }
  if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}(:[0-9]{2})?$", due))
    stop(what, ": due must be YYYY-MM-DD or YYYY-MM-DD HH:MM[:SS], got: ", due,
         call. = FALSE)
  if (nchar(due) == 16L) due <- paste0(due, ":00")
  t <- as.POSIXct(due, format = "%Y-%m-%d %H:%M:%S", tz = tz)
  if (is.na(t)) stop(what, ": due is not a real date-time in ", tz, ": ", due, call. = FALSE)
  t
}

# Every assignment and quiz that declares a `due:`, as one table sorted by the
# instant: title, local day, weekday number, and the clock label to print.
# Definitions with no `due:` are not due dates and are simply absent.
due_index <- function(m, course, tz) {
  empty <- data.frame(title = character(), date = as.Date(character()),
                      wday = integer(), time = character(), at = numeric(),
                      stringsAsFactors = FALSE)
  defs <- c(m$assignments, m$quizzes)
  if (!length(defs)) return(empty)
  defs <- defs[vapply(defs, function(d) !is.null(d$due), TRUE)]
  if (!length(defs)) return(empty)
  rows <- lapply(seq_along(defs), function(i) {
    k <- names(defs)[i]
    ttl <- trimws(as.character(defs[[i]]$title %||% ""))
    if (!nzchar(ttl))
      stop("'", k, "' has a due: but no title:; an announcement has nothing to ",
           "call it", call. = FALSE)
    t <- due_local(defs[[i]]$due, course$due_time, tz, paste0("'", k, "'"))
    d <- as.Date(format(t, "%Y-%m-%d", tz = tz))
    data.frame(title = ttl, date = d, wday = as.integer(format(d, "%u")),
               time = fmt_clock(t, tz), at = as.numeric(t), stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  out[order(out$at, out$title), , drop = FALSE]
}

# The Monday a week is built from. Everything in the week is placed by counting
# off it, so a `monday:` that is not a Monday would put every heading and every
# due item on the wrong day while every line still read plausibly. It stops.
week_monday <- function(w, i) {
  v <- w$monday
  if (is.null(v)) stop("schedule week ", i, " has no monday:", call. = FALSE)
  x <- if (inherits(v, "Date")) format(v) else trimws(as.character(v))
  if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x))
    stop("schedule week ", i, ": monday: must be YYYY-MM-DD, got: ", x, call. = FALSE)
  d <- as.Date(x, optional = TRUE)
  if (is.na(d) || !identical(format(d), x))
    stop("schedule week ", i, ": monday: is not a real date: ", x, call. = FALSE)
  wd <- as.integer(format(d, "%u"))
  if (wd != 1L)
    stop("schedule week ", i, ": monday: ", x, " is a ", WEEKDAYS_EN[wd],
         ". Every heading and every due item in the week is placed by counting ",
         "off that date.", call. = FALSE)
  d
}

# One class day: the heading, then In class or the holiday, Assigned, whatever
# is due that day, and what to prepare. `entry` is NULL for a day that the week
# does not declare but something is due on; the heading still appears, because
# dropping the item would be the one failure a student notices.
day_block <- function(d, entry, dd) {
  parts <- paste0("<h3>", xesc(fmt_day(d)), "</h3>")
  lines <- character()
  if (is.null(entry)) {
    parts <- c(parts, "<p>No class meeting.</p>")
  } else {
    if (!is.null(entry$holiday))
      lines <- c(lines, paste0("<li><b>", xesc(oneline(entry$holiday)), ".</b></li>"))
    else if (!is.null(entry$class))
      lines <- c(lines, paste0("<li><b>In class:</b> ", xesc(oneline(entry$class)), "</li>"))
    if (!is.null(entry$assigned))
      lines <- c(lines, paste0("<li><b>Assigned:</b> ", xesc(oneline(entry$assigned)), "</li>"))
  }
  for (j in seq_len(nrow(dd)))
    lines <- c(lines, paste0("<li><b>", due_label(dd$title[j]), ", ", dd$time[j],
                             ":</b> ", xesc(dd$title[j]), "</li>"))
  if (!is.null(entry) && !is.null(entry$prepare))
    lines <- c(lines, paste0("<li><b>Prepare before class:</b> ",
                             xesc(oneline(entry$prepare)), "</li>"))
  # An empty <ul> is a list with no items, which a screen reader announces as a
  # list of zero. A day with nothing to say gets its heading and no list.
  if (length(lines)) parts <- c(parts, paste0("<ul>", paste(lines, collapse = ""), "</ul>"))
  parts
}

read_schedule <- function(proj, schedule) {
  f <- proj_path(proj, schedule)
  if (!file.exists(f)) stop("no ", schedule, " under ", proj, call. = FALSE)
  s <- yaml::yaml.load_file(f)
  w <- s$weeks
  if (is.null(w) || !length(w))
    stop(schedule, " declares no weeks:. A schedule with none generates no ",
         "announcements, which is indistinguishable from a generator that ran ",
         "and failed.", call. = FALSE)
  w
}

#' Weekly announcements from a schedule
#'
#' Turn a `schedule.yml` into one announcement per week: an HTML body per week
#' under `out_dir` and an `announcements.yml` declaring them, which is what
#' [build_cartridge()] already reads. Nothing here touches the cartridge.
#'
#' Each week is one entry under `weeks:`. `monday:` is that week's Monday and
#' must be one. `module:` names the module the week covers and `label:`
#' overrides the counted `Week N`. `notes:` is a sentence for the top. Any of
#' `tuesday:` to `sunday:` is a class day, written as a mapping with `class:` or
#' `holiday:`, and optionally `assigned:` and `prepare:`. The body carries one
#' `<h3>` block per class day, in weekday order, and then what is due by Sunday.
#'
#' Due items are the manifest's own assignments and quizzes that declare a
#' `due:`. An item due Monday to Thursday is listed under its own day; Friday,
#' Saturday and Sunday collect into the closing `Due by Sunday` list, because
#' that is the deadline a student is working to over the weekend. An item due on
#' a weekday the schedule does not declare still gets a heading of its own,
#' marked as no class meeting, rather than being dropped. A title containing
#' `Exam` is labelled `Exam` rather than `Due`.
#'
#' An existing `announcements.yml` is never overwritten. The declaration is
#' written to `announcements.generated.yml` instead and the function says so, so
#' a course that has edited its announcements by hand can merge rather than
#' discover the loss later.
#'
#' @param proj Course project root.
#' @param schedule The schedule file, relative to `proj` or absolute.
#' @param out_dir Where the bodies are written, relative to `proj`. Also the
#'   `body_dir:` of the declaration.
#' @param release_time `"HH:MM"` in the course zone; every week posts at that
#'   time on its Monday.
#' @param calendar_url A link to the course calendar for the closing paragraph.
#'   `NULL` writes the paragraph without it.
#' @return Invisibly, a data frame with one row per week: `id`, `title`, `post`
#'   and `body`, the four fields the declaration carries.
#' @export
announcements_from_schedule <- function(proj = ".", schedule = "schedule.yml",
                                        out_dir = "content/announcements",
                                        release_time = "07:00",
                                        calendar_url = NULL) {
  if (!is.character(release_time) || length(release_time) != 1L ||
      !grepl("^[0-9]{2}:[0-9]{2}$", release_time))
    stop("release_time must be HH:MM in the course zone, got: ",
         paste(release_time, collapse = " "), call. = FALSE)
  m <- read_manifest(proj)
  course <- m$course
  tz <- read_timezone(course)
  weeks <- read_schedule(proj, schedule)
  dues <- due_index(m, course, tz)
  zone <- as.character(course$term$timezone_label %||% course$term$timezone)

  ids <- character(); titles <- character(); posts <- character()
  files <- character(); bodies <- list()
  n <- 0L
  for (i in seq_along(weeks)) {
    w <- weeks[[i]]
    monday <- week_monday(w, i)
    sunday <- monday + 6L
    if (is.null(w$module) || !nzchar(trimws(as.character(w$module))))
      stop("schedule week ", i, " (", format(monday), ") has no module:",
           call. = FALSE)
    label <- if (!is.null(w$label) && nzchar(trimws(as.character(w$label))))
      trimws(as.character(w$label)) else { n <- n + 1L; paste("Week", n) }
    title <- paste0(label, ": ", trimws(as.character(w$module)))

    wk <- dues[dues$date >= monday & dues$date <= sunday, , drop = FALSE]
    sun_d <- wk[wk$wday >= 5L, , drop = FALSE]
    day_d <- wk[wk$wday <= 4L, , drop = FALSE]

    # The h2 is NOT escaped: the builder reads it back and compares it with the
    # title this declares, so the two have to be the same characters.
    body <- c(paste0("<h2>", title, "</h2>"),
              paste0("<p>Here is the plan for the week of ", xesc(fmt_day(monday)),
                     ".</p>"))
    if (!is.null(w$notes)) body <- c(body, paste0("<p>", xesc(oneline(w$notes)), "</p>"))

    declared <- integer()
    for (wd in 2:7) {
      v <- w[[WEEKDAY_KEYS[wd]]]
      if (is.null(v)) next
      if (!is.list(v))
        stop("schedule week ", i, ": ", WEEKDAY_KEYS[wd], ": must be a mapping ",
             "with class: or holiday:, and optionally assigned: and prepare:",
             call. = FALSE)
      declared <- c(declared, wd)
    }
    for (wd in sort(unique(c(declared, day_d$wday))))
      body <- c(body, day_block(monday + (wd - 1L),
                                if (wd %in% declared) w[[WEEKDAY_KEYS[wd]]] else NULL,
                                day_d[day_d$wday == wd, , drop = FALSE]))

    body <- c(body, paste0("<h3>Due by ", xesc(fmt_day(sunday)), ", 11:59 pm</h3>"))
    body <- c(body, if (nrow(sun_d))
      paste0("<ul>", paste0("<li>", xesc(sun_d$title), "</li>", collapse = ""), "</ul>")
      else "<p>Nothing is due this Sunday.</p>")
    body <- c(body, if (!is.null(calendar_url) && nzchar(calendar_url))
      paste0("<p>The full term is on the <a href=\"", xesc(calendar_url),
             "\">Course Calendar</a>. All times are ", xesc(zone), ".</p>")
      else paste0("<p>All times are ", xesc(zone), ".</p>"))

    id <- paste0("week-", format(monday))
    ids <- c(ids, id); titles <- c(titles, title)
    posts <- c(posts, paste(format(monday), release_time))
    files <- c(files, paste0(id, ".html"))
    bodies[[length(bodies) + 1L]] <- paste(body, collapse = "\n")
  }
  if (anyDuplicated(ids))
    stop("two weeks share a monday:, so they would share an announcement id: ",
         paste(unique(ids[duplicated(ids)]), collapse = ", "), call. = FALSE)

  body_root <- proj_path(proj, out_dir)
  dir.create(body_root, recursive = TRUE, showWarnings = FALSE)
  for (i in seq_along(ids)) writef(file.path(body_root, files[i]), bodies[[i]])

  decl <- list(body_dir = out_dir)
  tm <- course$term
  if (is.list(tm) && !is.null(tm$timezone) && !is.null(tm$first_day) && !is.null(tm$last_day))
    decl$term <- list(timezone = tz,
                      first_day = as.character(tm$first_day),
                      last_day = as.character(tm$last_day))
  decl$announcements <- lapply(seq_along(ids), function(i)
    list(id = ids[i], title = titles[i], body = files[i], post = posts[i]))

  ann_file <- file.path(proj, "announcements.yml")
  generated <- file.exists(ann_file)
  target <- if (generated) file.path(proj, "announcements.generated.yml") else ann_file
  writef(target, sub("[[:space:]]+$", "", yaml::as.yaml(decl)))

  cat(sprintf("  %d announcement(s) from %s, %s to %s\n", length(ids),
              basename(proj_path(proj, schedule)),
              if (length(ids)) ids[1] else "-",
              if (length(ids)) ids[length(ids)] else "-"))
  cat("  bodies  ", body_root, "\n", sep = "")
  cat("  declared", basename(target), "\n")
  if (generated)
    message("announcements.yml is already there and was left alone; the ",
            "generated declaration is in announcements.generated.yml. Merge ",
            "what you want from it by hand.")
  cat("  A generated announcement is not a posted one. Build the cartridge and ",
      "read the bodies before importing.\n", sep = "")
  version_line("announcements_from_schedule")
  invisible(data.frame(id = ids, title = titles, post = posts, body = files,
                       stringsAsFactors = FALSE))
}
