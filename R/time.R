#' Local course time to the UTC stamp Canvas stores
#'
#' Canvas stores every date in UTC with no zone marker and displays it in the
#' course zone. The old builder used a fixed UTC-5 and refused any date after
#' the 2026 daylight-time boundary; this does the arithmetic per date from the
#' IANA zone, so a spring course crossing the March boundary gets each date
#' right. No default zone exists anywhere in the package.
#' @param date `"YYYY-MM-DD"` or a `Date`.
#' @param time `"HH:MM"` or `"HH:MM:SS"`, local.
#' @param tz An IANA zone name.
#' @return `"YYYY-MM-DDTHH:MM:SS"` in UTC.
#' @export
local_to_utc <- function(date, time = "23:59:00", tz) {
  if (!is.character(tz) || length(tz) != 1L || !tz %in% OlsonNames())
    stop("timezone must be an IANA zone name (for example America/Chicago), got: ",
         paste(tz, collapse = ","), call. = FALSE)
  d <- if (inherits(date, "Date")) date else {
    x <- as.character(date)
    if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x)) stop("date must be YYYY-MM-DD, got: ", x, call. = FALSE)
    dd <- as.Date(x, optional = TRUE)
    if (is.na(dd) || format(dd) != x) stop("not a real date: ", x, call. = FALSE)
    dd
  }
  time <- as.character(time)
  if (!grepl("^[0-9]{2}:[0-9]{2}(:[0-9]{2})?$", time)) stop("time must be HH:MM or HH:MM:SS, got: ", time, call. = FALSE)
  if (nchar(time) == 5L) time <- paste0(time, ":00")
  hh <- as.integer(substr(time, 1, 2)); mm <- as.integer(substr(time, 4, 5)); ss <- as.integer(substr(time, 7, 8))
  if (hh > 23L || mm > 59L || ss > 59L) stop("time must be HH:MM or HH:MM:SS within a day, got: ", time, call. = FALSE)
  t <- as.POSIXct(paste(format(d), time), format = "%Y-%m-%d %H:%M:%S", tz = tz)
  if (is.na(t)) stop("not a real date-time in ", tz, ": ", format(d), " ", time, call. = FALSE)
  format(t, "%Y-%m-%dT%H:%M:%S", tz = "UTC")
}

#' Parse a post or due time in one of exactly three forms
#'
#' `immediately` (returns `NULL`), `YYYY-MM-DD` (midnight local), or
#' `YYYY-MM-DD HH:MM[:SS]`. Anything else stops, because a value that fails to
#' parse must never quietly become "post now".
#' @param x The value from YAML.
#' @param tz IANA zone.
#' @param what A label for the error message (the announcement or assignment id).
#' @return `NULL`, or a `POSIXct` in `tz`.
#' @export
parse_when <- function(x, tz, what) {
  x <- trimws(as.character(x))
  if (identical(x, "immediately")) return(NULL)
  if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x)) x <- paste(x, "00:00:00")
  if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$", x)) x <- paste0(x, ":00")
  if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$", x))
    stop(what, ": post must be 'immediately', a date, or a date and HH:MM in the course zone; got: ",
         x, call. = FALSE)
  t <- as.POSIXct(x, format = "%Y-%m-%d %H:%M:%S", tz = tz)
  if (is.na(t) || format(t, "%Y-%m-%d %H:%M:%S", tz = tz) != x)
    stop(what, ": post is not a real date-time: ", x, call. = FALSE)
  t
}

#' The UTC stamp for a due date
#'
#' A bare date takes `due_time` from `course.yml`; a date with a clock time is
#' used as given (an in-person exam ending at 09:45 is due at 09:45, not at
#' midnight). Decision D6: the package has no default `due_time`.
#' @param due `"YYYY-MM-DD"` or `"YYYY-MM-DD HH:MM[:SS]"`.
#' @param due_time `"HH:MM:SS"` from `course.yml`, or `NULL`.
#' @param tz IANA zone.
#' @export
due_stamp <- function(due, due_time, tz) {
  due <- trimws(as.character(due))
  if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", due)) {
    if (is.null(due_time))
      stop("a bare due: date needs due_time: in course.yml (for example \"23:59:59\"); got due: ", due, call. = FALSE)
    return(local_to_utc(due, due_time, tz))
  }
  if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}(:[0-9]{2})?$", due))
    stop("due must be YYYY-MM-DD or YYYY-MM-DD HH:MM[:SS], got: ", due, call. = FALSE)
  local_to_utc(substr(due, 1, 10), substr(due, 12, nchar(due)), tz)
}
