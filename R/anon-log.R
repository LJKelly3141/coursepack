# The de-identification log: the record that each grading run was
# de-identified and how. Lives beside the key, never inside anon/. Appended,
# never rewritten. Holds counts, types, codes and anon/ paths only.
log_path <- function(assignment_dir) file.path(assignment_dir, "deidentification_log.md")

# Named counts as "a 1, b 2", zero counts left out, sorted by name; "none"
# when nothing is left. Used for files skipped by type and workbook content
# not read by kind: types and kinds only, never a name or filename.
count_text <- function(x) {
  x <- x[!is.na(x) & x > 0]
  if (!length(x)) return("none")
  x <- x[order(names(x))]
  paste(names(x), as.integer(x), collapse = ", ")
}

append_log <- function(assignment_dir, event, lines) {
  p <- log_path(assignment_dir)
  head <- if (file.exists(p)) character() else c("# De-identification log", "")
  stamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  block <- c(head, sprintf("## %s, %s, coursepack %s", event, stamp, coursepack_version()),
             "", paste0("- ", lines), "")
  cat(block, file = p, sep = "\n", append = TRUE)
  invisible(p)
}
