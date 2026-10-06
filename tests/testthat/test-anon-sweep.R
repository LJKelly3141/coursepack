# The local privacy sweep inside anonymize(). Every model call is mocked:
# these tests never need LM Studio.

a1_course <- function(text = "Pat Quill wrote this.", env = parent.frame()) {
  skip_if_no("tesseract")
  cc <- anon_course(env = env); a <- a1_assignment(cc)
  writeLines(text, file.path(a, "quillpat_1001_5001_essay.md"))
  list(cc = cc, a = a, an = file.path(a, "anon"))
}
model_up <- function(findings = list(), env = parent.frame()) {
  local_mocked_bindings(review_models = function(url) "gemma-4-31b-it-mlx",
                        review_call = function(body, url) list(findings = findings),
                        .env = env)
}
finding <- function(text, kind = "person_name", where = "text", n = 0L) {
  list(text = text, kind = kind, where = where, image_number = n, reason = "r")
}
run <- function(s, ...) quiet(anonymize(s$cc$proj, "semester/A1", dict = NULL, sweep = TRUE, ...))

test_that("a clean sweep releases anon/ and logs it", {
  s <- a1_course(); model_up()
  run(s)
  expect_true(dir.exists(s$an)); expect_false(file.exists(file.path(s$an, "NOT_READY")))
  log <- readLines(file.path(s$a, "deidentification_log.md"))
  expect_true(any(grepl("privacy sweep result: passed", log, fixed = TRUE)))
})

test_that("the server down stops before anything is written", {
  s <- a1_course()
  local_mocked_bindings(review_models = function(url) NULL)
  expect_match(errors_with(run(s)), "lms server start", fixed = TRUE)
  expect_false(dir.exists(s$an))
})

test_that("a model not loaded or a non-local url stops before anything is written", {
  s <- a1_course()
  local_mocked_bindings(review_models = function(url) "other-model")
  expect_match(errors_with(run(s)), "lms load gemma-4-31b-it-mlx", fixed = TRUE)
  expect_match(errors_with(run(s, sweep_url = "http://example.com:1234")), "localhost")
  expect_false(dir.exists(s$an))
})

test_that("a finding keeps anon/ unreleased until the instructor marks it noise", {
  s <- a1_course("I thank my roommate Jordan Whitfield.")
  model_up(list(finding("Jordan Whitfield")))
  e <- errors_with(run(s))
  expect_match(e, "anon_review.csv", fixed = TRUE)
  expect_false(grepl("Whitfield", e))
  expect_false(dir.exists(s$an))
  for (f in c(file.path(s$a, "deidentification_log.md"), file.path(s$a, "anon_sweep_progress.txt"))) {
    expect_false(any(grepl("Whitfield", readLines(f))))
  }
  d <- utils::read.csv(file.path(s$a, "anon_review.csv"), colClasses = "character")
  d$decision <- "real"; utils::write.csv(d, file.path(s$a, "anon_review.csv"), row.names = FALSE)
  expect_match(errors_with(run(s)), "1 marked real")
  expect_false(dir.exists(s$an))
  d$decision <- "noise"; utils::write.csv(d, file.path(s$a, "anon_review.csv"), row.names = FALSE)
  run(s)
  expect_true(dir.exists(s$an)); expect_false(file.exists(file.path(s$an, "NOT_READY")))
})

test_that("findings that cannot leak do not hold the release", {
  s <- a1_course()
  model_up(list(finding("Nobody Anywhere"), finding("[name]"), finding("USER")))
  run(s)
  expect_true(dir.exists(s$an)); expect_false(file.exists(file.path(s$an, "NOT_READY")))
})

test_that("a failure stops naming code and file, no anon/ is released, a re-run resumes", {
  s <- a1_course()
  local_mocked_bindings(review_models = function(url) "gemma-4-31b-it-mlx",
                        review_call = function(body, url) list(fail = "HTTP 500 boom"))
  expect_match(errors_with(run(s)), "privacy sweep failed for S", fixed = TRUE)
  expect_false(dir.exists(s$an))
  model_up(); run(s)
  expect_true(dir.exists(s$an)); expect_false(file.exists(file.path(s$an, "NOT_READY")))
})

test_that("a re-run sends nothing for unchanged files", {
  s <- a1_course(); n <- 0L
  local_mocked_bindings(review_models = function(url) "gemma-4-31b-it-mlx",
                        review_call = function(body, url) { n <<- n + 1L; list(findings = list()) })
  run(s); first <- n
  run(s)
  expect_equal(n, first)
})

test_that("sweep = FALSE skips the sweep and the log records the bypass", {
  s <- a1_course()
  quiet(anonymize(s$cc$proj, "semester/A1", dict = NULL, sweep = FALSE))
  expect_true(dir.exists(s$an)); expect_false(file.exists(file.path(s$an, "NOT_READY")))
  log <- readLines(file.path(s$a, "deidentification_log.md"))
  expect_true(any(grepl("privacy sweep: BYPASSED", log, fixed = TRUE)))
})

test_that("anon_forget() removes the sweep cache and progress file", {
  skip_if_no("zip")
  s <- a1_course(); model_up(); run(s)
  dir.create(file.path(s$an, "feedback"))
  writeLines("Good, S01.", file.path(s$an, "feedback", "S01.md"))
  utils::write.csv(data.frame(code = "S01", total = "9"), file.path(s$an, "scores.csv"), row.names = FALSE)
  quiet(relink(s$cc$proj, "semester/A1", dict = NULL))
  quiet(anon_forget(s$cc$proj, "semester/A1"))
  expect_false(dir.exists(file.path(s$a, "anon_review_cache")))
  expect_false(file.exists(file.path(s$a, "anon_sweep_progress.txt")))
})

test_that("the request body keeps the schema's required list an array", {
  b <- jsonlite::fromJSON(review_body("hello", character(), "P", "m"), simplifyVector = FALSE)
  expect_equal(b$response_format$json_schema$schema$required, list("findings"))
})

test_that("no anon/ exists while the sweep runs, not even an earlier released one", {
  s <- a1_course(); model_up(); run(s)
  expect_true(dir.exists(s$an))                     # an earlier run was released
  seen <- logical()
  local_mocked_bindings(review_models = function(url) "gemma-4-31b-it-mlx",
                        review_call = function(body, url) {
                          seen <<- c(seen, dir.exists(s$an)); list(findings = list()) })
  writeLines("Pat Quill wrote this, revised.", file.path(s$a, "quillpat_1001_5001_essay.md"))
  run(s)
  expect_true(length(seen) > 0)
  expect_false(any(seen))                           # anon/ was gone during every request
  expect_true(dir.exists(s$an))
  expect_false(dir.exists(file.path(s$a, ".anon_build")))
})
