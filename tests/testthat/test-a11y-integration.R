# The one section that runs the real tool chain end to end: a local server,
# pa11y over every page of a fixture site, both runners, and the three files
# the audit writes. It is opt-in, because npx fetches pa11y at run time and
# the first run downloads a Chromium build, which is minutes of network on a
# cold machine and has no place in a default suite.
#
# The fixture page carries three planted defects, one per assertion below
# plus one the run only has to survive: no `lang` on <html> (3.1.1), an alt
# attribute that is really a filename (1.1.1, the custom check, which axe
# cannot see at all because the attribute is present), and link text that
# says nothing out of context.
#
# The port is pinned rather than searched for. serve_dir() refuses a port
# something is already answering on, so a server leaked by an earlier run
# fails this section loudly instead of letting it audit whatever that other
# server happens to be serving.
#
# BOTH RUNNERS ARE ASSERTED AGAINST pa11y's OWN OUTPUT, not against the
# findings frame. A finding's `source` says which PRODUCER made the row
# (`pa11y` or one of the custom checks); the runner that found it is read by
# pa11y_parse_issue() to pick a criterion vocabulary and is then dropped, so
# no column downstream of from_pa11y() can distinguish htmlcs from axe. That
# distinction is the whole point of this assertion: `--runner axe` was absent
# for this project's entire first acceptance run, every issue came back from
# htmlcs alone, and nothing anywhere said so. Asserting it on the raw issue
# list is the only place the claim is actually checkable.

test_that("a real pa11y run against the fixture finds the planted defects with both runners", {
  skip_if_no("npx"); skip_if_no("python3")
  skip_if(!nzchar(Sys.getenv("COURSEPACK_PA11Y_TESTS")), "set COURSEPACK_PA11Y_TESTS=1 to run pa11y (downloads Chromium on first use)")
  out <- withr::local_tempdir()
  res <- audit_course(fixture_path("pair", "alpha"), proj = out, out_dir = out, port = 8794L)
  df <- res$findings
  expect_setequal(unique(df$source), c("pa11y", "custom"))
  expect_true(any(df$criterion == "1.1.1" & grepl("filename", df$issue, ignore.case = TRUE)))
  expect_true(any(df$criterion == "3.1.1"))
  expect_length(list.files(out, pattern = "-findings\\.json$"), 1L)

  # audit_course() has torn its own server down by now, but a kill returns
  # before the process is reaped, so wait for the port rather than race it.
  for (i in 1:25) { if (port_is_free(8794L)) break; Sys.sleep(0.2) }
  srv <- serve_dir(fixture_path("pair", "alpha", "site"), port = 8794L)
  raw <- tryCatch(pa11y_raw(paste0(srv$url, "/bad.html")), finally = srv$stop())
  runners <- unique(vapply(raw, function(iss) iss$runner %||% NA_character_,
                           character(1)))
  expect_setequal(intersect(runners, c("htmlcs", "axe")), c("htmlcs", "axe"))
})
