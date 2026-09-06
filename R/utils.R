# Defined once. The snapshot defines this operator in eight files because each
# had to be sourceable alone; a package defines it once and every file sees it.
`%||%` <- function(a, b) if (is.null(a)) b else a

#' The installed coursepack version
#'
#' Every entry point prints this in its closing summary, because editing `R/`
#' and forgetting to reinstall builds a course with old code silently. The
#' printed version is what tells the two apart.
#' @return The version string, invisibly printed by the entry points.
#' @examples
#' coursepack_version()
#' @export
coursepack_version <- function() as.character(utils::packageVersion("coursepack"))

version_line <- function(what) {
  cat(sprintf("%s: coursepack %s\n", what, coursepack_version()))
  invisible(coursepack_version())
}
