# The local privacy sweep, run by anonymize() before anon/ is released.
#
# A local vision model (LM Studio on localhost) reads every coded file with
# its images and lists anything that could still identify a student.
# anonymize() releases anon/ only when every file was reviewed, no student
# code is left in the text, and the instructor has marked every finding
# noise in anon_review.csv; until then NOT_READY stays. anonymize(sweep =
# FALSE) skips it, and the log says so. Messages, the progress file and the
# log carry codes, files, kinds and counts, never flagged text.

REVIEW_FILE <- "anon_review.csv"
REVIEW_CACHE <- "anon_review_cache"
REVIEW_CONTEXT <- "review_context.txt"
SWEEP_PROGRESS <- "anon_sweep_progress.txt"
REVIEW_KINDS <- c("person_name", "organization", "place", "contact", "id_number",
                  "personal_detail", "signature", "code_token", "image_person",
                  "image_name", "image_account", "other")
REVIEW_IMAGE_EXTS <- c("png", "jpg", "jpeg", "gif", "webp")
REVIEW_MARKS <- paste0("^\\[(name|PHONE|SSN|DOB|ADDRESS|PROFILE|HANDLE|image removed)\\]$",
                       "|^(USER|EMAIL)$")

review_local <- function(url) grepl("^http://(localhost|127\\.0\\.0\\.1)(:[0-9]+)?/?$", url)

review_models <- function(url) {
  tryCatch(jsonlite::fromJSON(paste0(sub("/$", "", url), "/v1/models"))$data$id,
           error = function(e) NULL)
}

review_check_server <- function(url, model) {
  if (!review_local(url)) {
    stop("url must be http://localhost or http://127.0.0.1; the sweep never leaves this machine.",
         call. = FALSE)
  }
  if (!requireNamespace("curl", quietly = TRUE)) {
    stop("the privacy sweep needs the curl package: install.packages(\"curl\"). anon/ is not released.",
         call. = FALSE)
  }
  ids <- review_models(url)
  if (is.null(ids)) {
    stop("No model server answers at ", url, ". Start LM Studio's server (lms server start), ",
         "load ", model, " (lms load ", model, ") and re-run. anon/ is not released.",
         call. = FALSE)
  }
  if (!model %in% ids) {
    stop(model, " is not loaded. Load it (lms load ", model, ") and re-run. ",
         "anon/ is not released.", call. = FALSE)
  }
  invisible(TRUE)
}

read_term_list <- function(path) {
  if (is.null(path) || is.na(path) || !file.exists(path)) return(character())
  x <- readLines(path, warn = FALSE, encoding = "UTF-8")
  if (length(x)) x[1] <- sub("^\ufeff", "", x[1])
  x <- trimws(x)
  x[nzchar(x) & !startsWith(x, "#")]
}

review_prompt <- function(keep = character(), context = character()) {
  p <- paste(readLines(system.file("review", "prompt.md", package = "coursepack"),
                       warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  if (length(keep)) {
    p <- paste0(p, "\n\nINSTRUCTOR NAME PHRASES (never flag):\n", paste("-", keep, collapse = "\n"))
  }
  if (length(context)) {
    p <- paste0(p, "\n\nCOURSE AND DATA TERMS FOR THIS ASSIGNMENT (never flag):\n",
                paste("-", context, collapse = "\n"))
  }
  p
}

review_images <- function(anon_dir, code, file) {
  d <- file.path(anon_dir, code, paste0(file, "_media"))
  f <- if (dir.exists(d)) list.files(d, recursive = TRUE, full.names = TRUE) else character()
  sort(f[tolower(tools::file_ext(f)) %in% REVIEW_IMAGE_EXTS])
}

review_schema <- function() list(
  type = "object",
  properties = list(findings = list(type = "array", items = list(
    type = "object",
    properties = list(text = list(type = "string"),
                      kind = list(type = "string", enum = REVIEW_KINDS),
                      where = list(type = "string", enum = c("text", "image")),
                      image_number = list(type = "integer"),
                      reason = list(type = "string")),
    required = c("text", "kind", "where", "image_number", "reason")))),
  required = I("findings"))   # I(): a one-element vector must stay a JSON array

review_mime <- function(p) switch(tolower(tools::file_ext(p)), jpg = , jpeg = "image/jpeg",
                                  gif = "image/gif", webp = "image/webp", "image/png")

review_body <- function(text, images, prompt, model) {
  parts <- c(list(list(type = "text", text = paste0(
    "THE PAPER (one file of the student's submission):\n\n", text,
    "\n\nIMAGES ATTACHED: ", length(images),
    "\n\nList every finding as instructed, or an empty list."))),
    lapply(images, function(p) list(type = "image_url", image_url = list(
      url = paste0("data:", review_mime(p), ";base64,",
                   jsonlite::base64_enc(readBin(p, "raw", file.info(p)$size)))))))
  jsonlite::toJSON(list(model = model, temperature = 0, max_tokens = 8000,
                        messages = list(list(role = "system", content = prompt),
                                        list(role = "user", content = parts)),
                        response_format = list(type = "json_schema", json_schema = list(
                          name = "privacy", strict = TRUE, schema = review_schema()))),
                   auto_unbox = TRUE)
}

# The one function that talks to the server. Returns the parsed findings or
# a short failure reason; never the reply text.
review_call <- function(body, url) {
  h <- curl::new_handle(post = TRUE, postfields = body,
                        timeout = getOption("coursepack.review_timeout", 3600))
  curl::handle_setheaders(h, "Content-Type" = "application/json")
  res <- tryCatch(curl::curl_fetch_memory(paste0(sub("/$", "", url), "/v1/chat/completions"),
                                          handle = h),
                  error = function(e) list(error = conditionMessage(e)))
  if (!is.null(res$error)) return(list(fail = paste("connection:", substr(res$error, 1, 100))))
  fr <- tryCatch(jsonlite::fromJSON(rawToChar(res$content), simplifyVector = FALSE),
                 error = function(e) NULL)
  if (res$status_code != 200) {
    e <- fr$error
    return(list(fail = substr(paste("HTTP", res$status_code,
                                    if (is.list(e)) e$message else paste(e)), 1, 160)))
  }
  g <- tryCatch(jsonlite::fromJSON(fr$choices[[1]]$message$content, simplifyVector = FALSE),
                error = function(e) NULL)
  if (is.null(g) || !is.list(g$findings)) {
    return(list(fail = sprintf("reply was not valid (stop: %s)",
                               fr$choices[[1]]$finish_reason %||% "?")))
  }
  list(findings = g$findings)
}

# One coded file: cached reply if the exact request was sent before,
# otherwise one request, retried once. A second failure stops the sweep.
review_file <- function(anon_dir, code, file, prompt, model, url, cache_dir) {
  text <- paste(readLines(file.path(anon_dir, code, paste0(file, ".md")), warn = FALSE,
                          encoding = "UTF-8"), collapse = "\n")
  body <- review_body(text, review_images(anon_dir, code, file), prompt, model)
  hit <- file.path(cache_dir, paste0(digest::digest(body, algo = "md5", serialize = FALSE), ".json"))
  if (file.exists(hit)) {
    return(list(findings = jsonlite::fromJSON(hit, simplifyVector = FALSE)$findings, cached = TRUE))
  }
  r <- review_call(body, url)
  if (!is.null(r$fail)) r <- review_call(body, url)
  if (!is.null(r$fail)) {
    stop("privacy sweep failed for ", code, " ", file, ": ", r$fail,
         ". anon/ is not released; re-run anonymize() to resume (finished files are cached).",
         call. = FALSE)
  }
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(jsonlite::toJSON(list(findings = r$findings), auto_unbox = TRUE), hit)
  list(findings = r$findings, cached = FALSE)
}

code_tokens_left <- function(text) {
  m <- gregexpr("(?<![A-Za-z0-9])(S[0-9]{2}|SXX)(?![A-Za-z0-9])", text, perl = TRUE)[[1]]
  sum(m > 0)
}

# The sweep itself. anonymize() calls it on the finished coded folder, while
# NOT_READY still stands. Returns whether it passed, a one-line result, the
# log lines and counts; it never prints or returns flagged text.
run_sweep <- function(anon_dir, assignment_dir, keep, model, url, context_path) {
  ctx <- read_term_list(context_path)
  prompt <- review_prompt(keep, ctx)
  cache_dir <- file.path(assignment_dir, REVIEW_CACHE)
  prog <- file.path(assignment_dir, SWEEP_PROGRESS)
  man <- utils::read.csv(file.path(anon_dir, "manifest.csv"), colClasses = "character")
  files <- unique(man[, c("code", "file")])
  files <- files[order(files$code, files$file), , drop = FALSE]
  n_img <- sum(vapply(seq_len(nrow(files)), function(i)
    length(review_images(anon_dir, files$code[i], files$file[i])), 0L))
  writeLines(sprintf("privacy sweep started %s: %d files, %d images, model %s",
                     format(Sys.time(), "%Y-%m-%d %H:%M"), nrow(files), n_img, model), prog)
  say <- function(line) { cat(line, "\n", sep = ""); cat(line, "\n", sep = "", file = prog, append = TRUE) }

  low_keep <- tolower(keep); low_ctx <- tolower(ctx)
  rows <- list(); cached <- 0L; codes_left <- 0L; t0 <- Sys.time()
  for (i in seq_len(nrow(files))) {
    cd <- files$code[i]; fl <- files$file[i]
    r <- review_file(anon_dir, cd, fl, prompt, model, url, cache_dir)
    cached <- cached + r$cached
    txt <- paste(readLines(file.path(anon_dir, cd, paste0(fl, ".md")), warn = FALSE,
                           encoding = "UTF-8"), collapse = "\n")
    codes_left <- codes_left + code_tokens_left(txt)
    imgs <- review_images(anon_dir, cd, fl)
    n_here <- 0L
    for (g in r$findings) {
      s <- trimws(as.character(g$text %||% ""))
      is_img <- identical(g$where, "image")
      if (!is_img && (!nzchar(s) || grepl(REVIEW_MARKS, s) || tolower(s) %in% c(low_keep, low_ctx))) next
      img <- if (is_img) {
        k <- suppressWarnings(as.integer(g$image_number))
        p <- if (!is.na(k) && k >= 1 && k <= length(imgs)) imgs[k] else if (length(imgs)) imgs[1] else ""
        if (nzchar(p)) sub(paste0("^", rx_escape(normalizePath(anon_dir)), "/?"), "", normalizePath(p)) else ""
      } else ""
      in_file <- if (is_img) NA else grepl(tolower(s), tolower(txt), fixed = TRUE)
      rows[[length(rows) + 1]] <- data.frame(
        code = cd, file = fl, kind = as.character(g$kind %||% "other"),
        where = if (is_img) "image" else "text", image = img, in_file = in_file,
        text = s, reason = as.character(g$reason %||% ""), stringsAsFactors = FALSE)
      n_here <- n_here + 1L
    }
    el <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
    say(sprintf("[%d/%d] %s %s (%d images)  %.1f min elapsed, about %.1f min left  %s%s",
                i, nrow(files), cd, fl, length(imgs), el, el / i * (nrow(files) - i),
                if (n_here) paste(n_here, "flagged") else "nothing flagged",
                if (r$cached) " (cached)" else ""))
  }

  fd <- if (length(rows)) do.call(rbind, rows) else
    data.frame(code = character(), file = character(), kind = character(), where = character(),
               image = character(), in_file = logical(), text = character(), reason = character())
  # A text finding that is not in the file cannot leak anything: it is
  # recorded and marked noise. Everything else waits for the instructor.
  fd$decision <- ifelse(fd$where == "text" & fd$in_file %in% FALSE, "noise", "")
  rec_path <- file.path(assignment_dir, REVIEW_FILE)
  if (file.exists(rec_path)) {
    old <- utils::read.csv(rec_path, colClasses = "character", na.strings = character(),
                           fileEncoding = "UTF-8-BOM")
    if (all(c("code", "file", "text", "decision") %in% names(old))) {
      k_old <- paste(old$code, old$file, tolower(old$text), old$image %||% "")
      k_new <- paste(fd$code, fd$file, tolower(fd$text), fd$image)
      m <- match(k_new, k_old)
      prior <- tolower(trimws(old$decision[m]))
      fd$decision <- ifelse(!is.na(m) & nzchar(prior %||% ""), prior, fd$decision)
    }
  }
  if (any(!fd$decision %in% c("", "noise", "real"))) {
    stop(REVIEW_FILE, ": decision must be noise, real or blank", call. = FALSE)
  }
  utils::write.csv(fd, rec_path, row.names = FALSE)

  undecided <- sum(fd$decision == ""); real <- sum(fd$decision == "real")
  kinds <- if (nrow(fd)) paste(names(table(fd$kind)), table(fd$kind), sep = " x", collapse = ", ") else "none"
  passed <- undecided == 0 && real == 0 && codes_left == 0
  result <- if (passed) "passed" else
    sprintf("not passed (%d undecided, %d marked real, %d student codes in the text)",
            undecided, real, codes_left)
  say(sprintf("privacy sweep: %s", result))
  list(passed = passed, result = result,
       log = c(sprintf("privacy sweep: model %s; files: %d; images: %d; replies from cache: %d",
                       model, nrow(files), n_img, cached),
               sprintf("privacy sweep findings: %d (%s); not in the file: %d; decisions: %d noise, %d real, %d undecided",
                       nrow(fd), kinds, sum(fd$in_file %in% FALSE), sum(fd$decision == "noise"),
                       real, undecided),
               sprintf("student-code tokens in the coded text: %d", codes_left),
               sprintf("privacy sweep result: %s", result)),
       counts = list(files = nrow(files), images = n_img, findings = nrow(fd),
                     undecided = undecided, real = real, cached = cached))
}
