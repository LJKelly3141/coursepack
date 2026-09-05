#' The byte gate
#'
#' A cartridge's staging tree, hashed file by file. `imsmanifest.xml` embeds
#' the build date, so that one line is normalized before hashing (spec 2f);
#' everything else is hashed as bytes. The gate compares two such listings and
#' refuses on any difference. Never regenerate an expected tree to make a
#' failing gate pass: a regeneration is a declaration that the cartridge was
#' supposed to change.
#' @param dir A staging directory.
#' @param path,expected A file of `<md5> <path>` lines.
#' @name gate
NULL

normalize_manifest_date <- function(text) {
  sub("<lomimscc:dateTime>[^<]*</lomimscc:dateTime>",
      "<lomimscc:dateTime>DATE</lomimscc:dateTime>", text)
}

#' @rdname gate
#' @export
tree_hashes <- function(dir) {
  files <- sort(list.files(dir, recursive = TRUE, all.files = TRUE, no.. = TRUE))
  vapply(files, function(f) {
    full <- file.path(dir, f)
    h <- if (identical(basename(f), "imsmanifest.xml")) {
      txt <- paste(readLines(full, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
      digest::digest(normalize_manifest_date(txt), algo = "md5", serialize = FALSE)
    } else unname(tools::md5sum(full))
    paste(h, f)
  }, "", USE.NAMES = FALSE)
}

#' @rdname gate
#' @export
write_expected_tree <- function(dir, path) {
  writeLines(tree_hashes(dir), path)
  invisible(path)
}

#' @rdname gate
#' @export
gate_check <- function(dir, expected) {
  want <- readLines(expected, warn = FALSE)
  got <- tree_hashes(dir)
  split2 <- function(v) {
    p <- sub("^[0-9a-f]{32} ", "", v); h <- substr(v, 1, 32); stats::setNames(h, p)
  }
  w <- split2(want); g <- split2(got)
  missing <- setdiff(names(w), names(g)); extra <- setdiff(names(g), names(w))
  common <- intersect(names(w), names(g))
  changed <- common[w[common] != g[common]]
  res <- list(missing = missing, extra = extra, changed = changed)
  if (length(missing) || length(extra) || length(changed)) {
    stop("GATE FAILED against ", expected, "\n",
         paste0(c(paste0("  missing: ", missing), paste0("  extra: ", extra),
                  paste0("  changed: ", changed)), collapse = "\n"),
         "\nRead the diff before touching anything. A regeneration is a deliberate output change.",
         call. = FALSE)
  }
  invisible(res)
}
