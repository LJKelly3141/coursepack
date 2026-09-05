# ---- helpers -------------------------------------------------------------
gid <- function(...) paste0("g", digest::digest(paste(..., sep = ""), algo = "md5"))

# An id written by hand in the YAML, overriding the derived one. Used when a
# course is adopting ids that already exist in Canvas, so an import updates the
# object that is already there instead of creating a duplicate beside it.
#
# NULL means no override and the derived id stands. Anything else must be a
# Canvas identifier, "g" plus 32 hex, because a malformed id is exactly the
# defect Canvas accepts and then silently drops: the item imports pointing at a
# resource that is not there, and nothing reports it. `what` names the key, so
# the message says which line of which file to fix.
check_gid <- function(x, what = "resource_id") {
  if (is.null(x)) return(NULL)
  x <- as.character(x)
  if (length(x) != 1L || !grepl("^g[0-9a-f]{32}$", x))
    stop(what, " must be g plus 32 hex, got: ", paste(x, collapse = " "), call. = FALSE)
  x
}

xesc <- function(x) {
  if (is.null(x)) return("")
  x <- gsub("&",  "&amp;",  x, fixed = TRUE)
  x <- gsub("<",  "&lt;",   x, fixed = TRUE)
  x <- gsub(">",  "&gt;",   x, fixed = TRUE)
  x <- gsub('"',  "&quot;", x, fixed = TRUE)
  x
}

# Escape for ELEMENT TEXT rather than an attribute value: a double quote is
# legal there and Canvas's own export leaves it raw. xesc() would write it as
# &quot;, which Canvas would read back identically, but the announcement bodies
# are full of href="..." and matching the export byte for byte is what lets a
# diff against it show real change. Only ever used for text nodes.
xtext <- function(x) {
  if (is.null(x)) return("")
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;",  x, fixed = TRUE)
  x <- gsub(">", "&gt;",  x, fixed = TRUE)
  x
}

# Collapse the folded-scalar newlines YAML leaves in long header text.
oneline <- function(x) trimws(gsub("\\s+", " ", x))

slugify <- function(x) {
  x <- tolower(x)
  x <- gsub("[^a-z0-9]+", "-", x)
  gsub("^-+|-+$", "", x)
}

writef <- function(path, text) {
  # Force the text before opening the file: callers pass expressions such as
  # assignment_body(...), and a stop() inside one used to unwind past an open
  # connection, which R then reported as "closing unused connection" at gc.
  text <- enc2utf8(text)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- file(path, open = "wb")            # binary: no CRLF translation, stable bytes
  on.exit(close(con), add = TRUE)
  writeLines(text, con, sep = "\n", useBytes = TRUE)
}

XSI <- paste0('xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"')
CCV <- paste0('xmlns="http://canvas.instructure.com/xsd/cccv1p0" ', XSI,
              ' xsi:schemaLocation="http://canvas.instructure.com/xsd/cccv1p0',
              ' https://canvas.instructure.com/xsd/cccv1p0.xsd"')

