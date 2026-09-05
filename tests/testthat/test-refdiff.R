one_module <- function(extra = list()) list(list(title = "M1", items = c(list(
  list(title = "A", ctype = "WikiPage"), list(title = "B", ctype = "ExternalUrl", url = "https://example.invalid/b")), extra)))

test_that("no reference.yml means a loud skip and an empty result", {
  p <- copy_course()
  expect_output(res <- diff_against_reference(p, generated = tempfile(fileext = ".imscc")), "SKIPPED: no reference export declared")
  expect_length(res$divergences, 0)
})

test_that("an identical cartridge reports no divergence", {
  skip_if_no("zip")
  p <- copy_course(); dir.create(file.path(p, "reference"), showWarnings = FALSE)
  ref <- write_mini_cartridge(file.path(p, "reference", "ref.imscc"), one_module())
  gen <- write_mini_cartridge(file.path(p, "gen.imscc"), one_module())
  writeLines("export: reference/ref.imscc", file.path(p, "reference.yml"))
  res <- diff_against_reference(p, gen)
  expect_length(res$divergences, 0)
})

test_that("an undeclared divergence stops; a declared one is accounted for by substring", {
  skip_if_no("zip")
  p <- copy_course(); dir.create(file.path(p, "reference"), showWarnings = FALSE)
  write_mini_cartridge(file.path(p, "reference", "ref.imscc"), one_module())
  gen <- write_mini_cartridge(file.path(p, "gen.imscc"), one_module(list(list(title = "C", ctype = "WikiPage"))))
  writeLines("export: reference/ref.imscc", file.path(p, "reference.yml"))
  expect_error(diff_against_reference(p, gen), "UNEXPECTED divergences")
  writeLines(c("export: reference/ref.imscc", "divergences:",
               "  - match: 'items: 2 -> 3'", "    why: one page added on purpose",
               "  - match: 'WikiPage: 1 -> 2'", "    why: same page",
               "  - match: 'webcontent: 1 -> 2'", "    why: same page",
               "  - match: 'item added: WikiPage|C'", "    why: same page"), file.path(p, "reference.yml"))
  res <- diff_against_reference(p, gen)
  expect_length(res$unexpected, 0); expect_length(res$accounted, 4)
})

test_that("divergence_declared matches on substring, first hit wins", {
  decl <- list(list(match = "due_at", why = "dates set by hand"), list(match = "items: 72 -> 73", why = "added link"))
  expect_equal(divergence_declared("assignment HW due_at: x -> y", decl), "dates set by hand")
  expect_true(is.na(divergence_declared("modules: 9 -> 11", decl)))
})
