# Serving is not optional. Chrome gives every file:// document a unique opaque
# origin, so a headless audit of file:// URLs sees a different document than
# a student does, and framed content does not load at all. Decision 008 hit
# the same wall from the mockup side. Serve, audit, tear down.

# TRUE if nothing answers a raw TCP connect on this port yet. Checked before
# spawning. Fixed 2026-08-12 code review, finding 1: the only liveness signal
# serve_dir had was "does an HTTP GET here return anything," which cannot
# distinguish the process this call just spawned from a server some earlier,
# leaked call left running on the same fixed port. A leaked server made every
# later pa11y_raw() call silently audit the wrong directory: valid JSON came
# back, nothing errored, and it measured stale content. Failing loudly on a
# collision, before spawning, is cheaper than detecting it after the fact.
port_is_free <- function(port) {
  con <- suppressWarnings(try(
    socketConnection(host = "localhost", port = port, server = FALSE,
                      blocking = TRUE, timeout = 1),
    silent = TRUE))
  if (inherits(con, "try-error")) return(TRUE)
  close(con)
  FALSE
}

#' Serve a directory over HTTP for the audit
#'
#' Chrome gives every `file://` document a unique opaque origin, so a headless
#' audit of `file://` URLs sees a different document than a student does, and
#' framed content does not load at all. The audit serves the rendered pages
#' over HTTP, audits them, and tears the server down.
#'
#' Refuses to attach to a port something is already answering on: a leaked
#' server from an earlier call would return valid JSON for the wrong
#' directory, which reads as a clean audit of content nobody asked for.
#'
#' @param dir Directory to serve. Must exist.
#' @param port Port to listen on.
#' @return A list of `url`, `port`, `pid`, and `stop`, a function that kills
#'   the server this call spawned. Call `stop()` yourself; nothing else will.
#' @export
serve_dir <- function(dir, port = 8766L) {
  stopifnot(dir.exists(dir))

  if (!nzchar(Sys.which("python3"))) {
    stop("python3 is needed to serve pages for the audit; install it")
  }

  if (!port_is_free(port)) {
    stop("port ", port, " is already in use, refusing to attach to it. ",
         "A previous serve_dir() call on this port may have leaked (an ",
         "error between serve_dir() and srv$stop() would do it). Find and ",
         "kill whatever is listening, e.g. `lsof -i :", port, "`, then retry.")
  }

  pid_file <- tempfile("httpd-pid-")
  system(sprintf(
    "python3 -m http.server %d --directory %s >/dev/null 2>&1 & echo $! > %s",
    port, shQuote(normalizePath(dir)), shQuote(pid_file)))
  Sys.sleep(0.3)
  pid <- as.integer(readLines(pid_file, warn = FALSE))[1]
  url <- sprintf("http://localhost:%d", port)

  # Poll until it answers. A fixed sleep is a race on a cold machine.
  up <- FALSE
  for (i in 1:50) {
    probe <- suppressWarnings(try(
      readLines(url, n = 1, warn = FALSE), silent = TRUE))
    if (!inherits(probe, "try-error")) { up <- TRUE; break }
    Sys.sleep(0.2)
  }
  if (!up) {
    system(sprintf("kill %d 2>/dev/null", pid))
    stop("server on port ", port, " never came up for ", dir)
  }

  # An HTTP response proves something is answering, not that it is the pid
  # we just spawned. Confirm directly: closes the race between the
  # port_is_free() check above and the spawn (another process could still
  # have grabbed the port in between), and catches a spawn that failed with
  # "address already in use" while some other server kept answering.
  alive <- identical(
    system2("kill", c("-0", as.character(pid)), stdout = FALSE, stderr = FALSE),
    0L)
  if (!alive) {
    system(sprintf("kill %d 2>/dev/null", pid))
    stop("server on port ", port, " answered HTTP, but pid ", pid,
         " (the process this call spawned) is not running. Something else ",
         "is serving this port; refusing to audit content we did not spawn.")
  }

  list(url = url, port = port, pid = pid,
       stop = function() system(sprintf("kill %d 2>/dev/null", pid)))
}

# Runs pa11y over one URL and returns the parsed issue list.
# PA11Y_VERSION is pinned here and nowhere else.
#
# Verified against a real invocation (2026-08-12, pa11y 9.1.1, --help output):
# --standard, --reporter, --timeout are the real flag names, unchanged from
# the draft. See the snapshot's log/gotchas.md for the full record, including
# the Chrome-for-Testing cache corruption that session hit and how it was
# fixed.
#
# CORRECTED from the draft: --include-warnings and --include-notices are
# required. Without them the JSON reporter silently drops every issue that
# is not type "error". Measured on one real rendered chapter: 242 errors
# reported by default, 699 total (242 error + 280 warning + 177 notice) with
# these flags on. That is 65% of real findings missing, including every
# contrast and structural warning, which is most of what a WCAG AA audit is
# for.
#
# Fixed 2026-08-13, coordinator review, Finding 3 (critical, the
# coordinator's own error, not this file's): "Runner is left at its default
# (htmlcs); --runner axe was not exercised here" was true and stayed true
# through the entire first acceptance run. `--runner` was never passed at
# all, and pa11y's own default is `htmlcs` alone, verified live against a
# real page: every one of 685 issues on one chapter came back
# `runner: "htmlcs"`, zero `"axe"`. The decision record and this project's
# own instructions all said "pa11y bundles axe-core and HTML_CodeSniffer, so
# one invocation runs both engines"; as actually invoked, that was never
# true. The axe-core ruleset had never once executed. `--runner` is
# documented by `pa11y --help` as repeatable ("the test runners to use:
# htmlcs (default), axe"), so it is passed twice, not comma-joined.
# Confirmed this actually changes what runs, not just what the flag list
# says: re-invoked against the same page with both runners named, and the
# real output now contains BOTH `runner: "htmlcs"` (685, unchanged) AND
# `runner: "axe"` (274, new). A flag that parses without error is not
# evidence it changed anything; only the `runner` field in the real returned
# issues is.
PA11Y_VERSION <- "9.1.1"

# Task 8 negative control, ruling R14 (Task 1 re-review): "output file
# missing or zero-size" was the ONLY failure this function could raise, and
# every caller's tryCatch(..., error = function(e) ...) therefore had to
# treat every failure alike. A crash that leaves a non-empty but malformed
# JSON file (pa11y itself segfaulting mid-write, a truncated pipe, a future
# pa11y version changing its output shape) threw inside fromJSON() and
# landed in the exact same `error` handler as "pa11y is not installed on
# this machine." Those are different realities, absent may SKIP and broken
# must FAIL, so failures are raised as two distinguishable condition
# classes and a caller can route on the class instead of on catching
# everything the same way.
pa11y_condition <- function(class, msg) {
  structure(
    class = c(class, "error", "condition"),
    list(message = msg, call = sys.call(-1)))
}

# Given the outcome of the system2() call already made (an output file that
# may or may not exist/be non-empty, a stderr file, the exit status, and the
# url that was requested), decide which of the two realities this run is:
# pa11y_unavailable (never produced output, a launch or availability
# failure; the tool did not run) or pa11y_broken (produced non-empty output
# that is not valid JSON, the tool ran and the run is not trustworthy).
# Split out from pa11y_raw() so this decision is unit-testable directly
# against a file on disk, without shelling out to npx.
pa11y_classify_output <- function(out, err, status, url) {
  # pa11y exits nonzero when it finds issues. That is success, not failure.
  if (!file.exists(out) || file.info(out)$size == 0) {
    err_lines <- if (file.exists(err)) readLines(err, warn = FALSE) else character()
    err_snippet <- if (length(err_lines)) {
      paste(utils::head(err_lines, 20), collapse = "\n")
    } else {
      "(nothing on stderr)"
    }
    stop(pa11y_condition("pa11y_unavailable",
      paste0("pa11y produced no output for ", url, " (exit ", status, ")\n",
             "stderr:\n", err_snippet)))
  }
  parsed <- tryCatch(jsonlite::fromJSON(out, simplifyVector = FALSE),
                      error = function(e) e)
  if (inherits(parsed, "error")) {
    stop(pa11y_condition("pa11y_broken",
      paste0("pa11y produced non-empty output for ", url,
             " that is not valid JSON. The tool RAN and broke; this is not ",
             "an absent-tool case and must not be treated as one: ",
             conditionMessage(parsed))))
  }
  parsed
}

#' Audit one URL with pa11y
#'
#' Runs pa11y over one URL and returns its parsed issue list. Both runners
#' are named explicitly, and warnings and notices are included: pa11y's JSON
#' reporter drops every issue that is not type `error` without them, which is
#' most of what a WCAG AA audit is for.
#'
#' Two failures are distinguished, because they are different realities. A
#' tool that never produced output raises a `pa11y_unavailable` condition and
#' a caller may skip on it; a tool that ran and wrote something that is not
#' valid JSON raises `pa11y_broken` and must never read as "not run".
#'
#' @param url URL to audit. Serve the pages first; see [serve_dir()].
#' @param timeout_s Per-page timeout, in seconds.
#' @return The parsed pa11y issue list, one element per issue.
#' @export
pa11y_raw <- function(url, timeout_s = 120L) {
  if (!nzchar(Sys.which("npx"))) {
    stop("npx (Node.js) is needed to run pa11y; install Node.js")
  }
  out <- tempfile(fileext = ".json")
  # stderr goes to a file, not FALSE/discarded. Fixed 2026-08-12 code review,
  # finding 2: the one real failure that session hit, a corrupted
  # Chrome-for-Testing cache, put its entire diagnostic (the dlopen error
  # naming the missing framework) on stderr. Discarding it means the next
  # person who hits the same class of failure gets only "pa11y produced no
  # output ... (exit 1)" and has to rediscover the fix from nothing.
  err <- tempfile(fileext = ".stderr")
  status <- system2("npx",
    c("--yes", paste0("pa11y@", PA11Y_VERSION),
      "--standard", "WCAG2AA",
      "--reporter", "json",
      "--runner", "htmlcs",
      "--runner", "axe",
      "--include-warnings",
      "--include-notices",
      "--timeout", as.character(timeout_s * 1000L),
      url),
    stdout = out, stderr = err)
  pa11y_classify_output(out, err, status, url)
}
