# Ported from the snapshot's own self-checking audit test script: the
# serve_dir section, the pa11y_raw fixture check, and the negative control
# that a broken pa11y run must FAIL rather than SKIP. Each section there
# opened with a printed banner and asserted through a check() helper; here
# each banner is a test_that() block and each check() is an expectation
# carrying the original label.

test_that("serve_dir", {
  skip_if_no("python3")
  tmp <- file.path(tempdir(), "servetest"); unlink(tmp, recursive = TRUE)
  dir.create(tmp)
  writeLines("<!doctype html><html lang='en'><title>t</title><body>hi</body></html>",
             file.path(tmp, "index.html"))
  srv <- serve_dir(tmp, port = 8791L)
  # Bound to the test, not to the call: an expectation that fails below must
  # not leak a server onto the fixed port every later call checks first.
  stopped <- FALSE
  withr::defer(if (!stopped) srv$stop())

  body <- paste(readLines(paste0(srv$url, "/index.html"), warn = FALSE), collapse = "")
  expect_identical(grepl("hi", body), TRUE, info = "serves a file")

  # All four fields of the returned handle are load-bearing, not just url:
  # port and pid are what let a caller tell the server it spawned from one an
  # earlier leaked call left running on the same fixed port.
  expect_identical(srv$url, "http://localhost:8791", info = "reports the url it serves")
  expect_identical(srv$port, 8791L, info = "reports the port it was asked for")
  expect_identical(is.na(srv$pid), FALSE, info = "reports a pid")
  expect_identical(
    system2("kill", c("-0", as.character(srv$pid)), stdout = FALSE, stderr = FALSE),
    0L, info = "the reported pid is the live process this call spawned")

  srv$stop(); stopped <- TRUE
  Sys.sleep(0.3)
  expect_identical(
    inherits(suppressWarnings(
      try(readLines(paste0(srv$url, "/index.html"), warn = FALSE),
          silent = TRUE)), "try-error"),
    TRUE, info = "stops cleanly")
})

# Serves a fixture with one known, deliberate defect (an <img> with no alt)
# and asserts pa11y_raw() actually finds it. This is the half of the library
# that a hand verification once caught misconfigured; that verification is
# not repeatable, this check is.
test_that("pa11y_raw finds the known missing-alt defect (code H37 or type error)", {
  skip_if_no("npx")
  skip_if_no("python3")

  run_pa11y_fixture_check <- function() {
    fixture <- file.path(tempdir(), "pa11ytest"); unlink(fixture, recursive = TRUE)
    dir.create(fixture)
    writeLines(paste0(
      "<!doctype html><html lang='en'><head><meta charset='utf-8'>",
      "<title>a11y fixture</title></head><body><h1>Fixture</h1>",
      "<img src='missing-alt.png'></body></html>"),
      file.path(fixture, "index.html"))

    srv2 <- serve_dir(fixture, port = 8792L)
    on.exit(srv2$stop(), add = TRUE)
    pa11y_raw(paste0(srv2$url, "/index.html"))
  }

  pa11y_label <- "pa11y_raw finds the known missing-alt defect (code H37 or type error)"
  # Narrowed from a bare `error` handler: a run that produced malformed JSON
  # (the tool RAN and broke) would otherwise be caught by the SAME handler as
  # "pa11y is not installed" and silently reported as a SKIP. pa11y_raw()
  # raises pa11y_unavailable for a genuine launch or availability failure and
  # pa11y_broken for everything else it can detect about its own output; only
  # the former is skip-worthy. Anything else, pa11y_broken included, is a
  # failure, so a broken tool costs the run its green result instead of
  # reading as "not run."
  pa11y_result <- tryCatch(run_pa11y_fixture_check(),
    pa11y_unavailable = function(e) e,
    error              = function(e) e)

  if (inherits(pa11y_result, "pa11y_unavailable")) {
    skip(conditionMessage(pa11y_result))
  } else if (inherits(pa11y_result, "error")) {
    expect_identical(
      paste0("ERROR, not a skip: ", conditionMessage(pa11y_result)),
      "pa11y_raw() must either succeed or raise pa11y_unavailable",
      info = pa11y_label)
  } else {
    codes <- vapply(pa11y_result, function(i) i$code %||% "", "")
    types <- vapply(pa11y_result, function(i) i$type %||% "", "")
    found <- any(grepl("H37", codes, fixed = TRUE)) || any(types == "error")
    expect_identical(found, TRUE, info = pa11y_label)
  }
})

test_that("negative control: a broken pa11y run must FAIL, not SKIP (ruling R14)", {
  skip_if_no("npx")
  # pa11y_raw() used to gate only on "output file missing or zero-size." A
  # crash leaving a non-empty but malformed JSON file threw inside fromJSON()
  # and was caught by the caller's outer tryCatch as a SKIP, exactly like
  # "pa11y is not installed." A tool that ran and broke must FAIL; a tool
  # that is absent may SKIP. Collapsing those into one state is how a
  # corrupted audit reads as "not run" and nobody investigates.

  # PREMISE check, not a negative control, and not counted as one. This
  # asserts jsonlite's OWN behaviour on bad input (that fromJSON() throws on
  # malformed text), not anything this package wrote. No change to any file
  # here can turn it red; only a change to the jsonlite package could. It
  # stays because it is the premise the routing proof just below relies on
  # (pa11y_classify_output() only behaves correctly if fromJSON() really does
  # throw on malformed input), but it guards jsonlite, not this codebase, so
  # it must never be mistaken for part of this file's own negative-control
  # coverage.
  nc_bad_json <- tempfile(fileext = ".json")
  writeLines("{ this is not json", nc_bad_json)
  nc_parsed <- try(jsonlite::fromJSON(nc_bad_json, simplifyVector = FALSE), silent = TRUE)
  expect_identical(inherits(nc_parsed, "try-error"), TRUE,
    info = "premise (not a negative control): jsonlite::fromJSON errors on malformed input")

  # Now the actual routing, exercised directly against pa11y_classify_output(),
  # the function pa11y_raw() delegates to after its system2() call returns.
  # This is real reachability through the extracted seam, not just a
  # restatement that fromJSON() throws: it proves a non-empty malformed file
  # and a genuinely absent one are classified into two DIFFERENT condition
  # classes, which is the fact the caller's narrowed tryCatch depends on.
  nc_broken_out <- tempfile(fileext = ".json")
  writeLines("{ this is not json", nc_broken_out)
  nc_broken_err <- tempfile(fileext = ".stderr")
  writeLines("", nc_broken_err)
  nc_broken_cond <- tryCatch(
    pa11y_classify_output(nc_broken_out, nc_broken_err, 0L, "http://negctl/broken"),
    error = function(e) e)
  expect_identical(inherits(nc_broken_cond, "pa11y_broken"), TRUE,
    info = "negative control: a malformed non-empty pa11y output is classified pa11y_broken")
  expect_identical(inherits(nc_broken_cond, "pa11y_unavailable"), FALSE,
    info = "negative control: a broken tool is NOT misclassified as pa11y_unavailable")

  nc_absent_out <- tempfile(fileext = ".json")  # never written: genuinely absent
  nc_absent_err <- tempfile(fileext = ".stderr")
  writeLines("dlopen: framework not found", nc_absent_err)
  nc_absent_cond <- tryCatch(
    pa11y_classify_output(nc_absent_out, nc_absent_err, 127L, "http://negctl/absent"),
    error = function(e) e)
  expect_identical(inherits(nc_absent_cond, "pa11y_unavailable"), TRUE,
    info = "negative control: a genuinely absent tool is classified pa11y_unavailable")
  expect_identical(inherits(nc_absent_cond, "pa11y_broken"), FALSE,
    info = "negative control: an absent tool is NOT misclassified as pa11y_broken")
})
