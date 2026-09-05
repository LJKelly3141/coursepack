# ---- helpers -------------------------------------------------------------
gid <- function(...) paste0("g", digest::digest(paste(..., sep = ""), algo = "md5"))

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
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- file(path, open = "wb")            # binary: no CRLF translation, stable bytes
  writeLines(enc2utf8(text), con, sep = "\n", useBytes = TRUE)
  close(con)
}

XSI <- paste0('xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"')
CCV <- paste0('xmlns="http://canvas.instructure.com/xsd/cccv1p0" ', XSI,
              ' xsi:schemaLocation="http://canvas.instructure.com/xsd/cccv1p0',
              ' https://canvas.instructure.com/xsd/cccv1p0.xsd"')

