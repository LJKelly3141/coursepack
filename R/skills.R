# The skills ship inside the package, so one installed copy is the only source
# of them and no course keeps its own drifting fork. A course still needs them
# on disk under .claude/skills/, because that is where an agent session looks,
# so this is a copy rather than a reference: a clone of the course carries the
# skills with it whether or not the package is installed on that machine.
#
# The copy is stamped with the package version for the reason coursepack_version()
# exists at all. A skill names functions and Makefile targets that exist at a
# version; a copy installed a release ago can name one that has since changed,
# and the line at the bottom of SKILL.md is the only place that shows it.

skills_root <- function() {
  d <- system.file("skills", package = "coursepack")
  if (!nzchar(d)) stop("coursepack skills are not installed", call. = FALSE)
  d
}

shipped_skills <- function() basename(list.dirs(skills_root(), recursive = FALSE))

# Copied file by file rather than by removing the destination and copying the
# directory whole. A skill directory in a course is editable, and a course that
# added a file of its own beside SKILL.md keeps it; overwrite = TRUE replaces
# what ships, not what the course put there.
copy_tree <- function(from, to) {
  rel <- list.files(from, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  for (f in rel) {
    dst <- file.path(to, f)
    dir.create(dirname(dst), recursive = TRUE, showWarnings = FALSE)
    file.copy(file.path(from, f), dst, overwrite = TRUE)
  }
  rel
}

# Appended as bytes rather than rewritten through readLines(), so an installed
# SKILL.md is the shipped file plus exactly two lines and nothing else. The
# leading newline is conditional only because a shipped file with no final
# newline would otherwise glue the stamp onto its last line of prose.
stamp_skill <- function(path, version) {
  n <- file.size(path)
  ends_newline <- n > 0 && identical(readBin(path, "raw", n = n)[n], as.raw(10L))
  cat(if (ends_newline) "" else "\n",
      "\n<!-- installed from coursepack ", version, " -->\n",
      sep = "", file = path, append = TRUE)
}

#' Install the shipped skills into a course
#'
#' Copies each skill directory out of the installed package into
#' `<proj>/.claude/skills/` and stamps the package version at the bottom of
#' every copied `SKILL.md`.
#'
#' A skill directory is editable once it is in a course, so an existing
#' destination stops the call and names what it found. Overwriting is a
#' deliberate argument, because the alternative is losing a local edit without
#' anyone seeing it happen.
#'
#' Nothing is written outside `proj`: the destination is built from `proj` and
#' a skill name, and a name this package does not ship stops before any copy.
#'
#' @param proj Course project root.
#' @param which Skill names to install. `NULL` installs every shipped skill.
#' @param overwrite Whether to replace a skill already installed under `proj`.
#' @return The destination directories, invisibly.
#' @export
install_skills <- function(proj = ".", which = NULL, overwrite = FALSE) {
  src <- skills_root()
  available <- shipped_skills()
  which <- which %||% available

  unknown <- setdiff(which, available)
  if (length(unknown))
    stop("unknown skill: ", paste(unknown, collapse = ", "),
         "; shipped: ", paste(available, collapse = ", "), call. = FALSE)

  root <- file.path(proj, ".claude", "skills")
  dest <- file.path(root, which)

  if (!overwrite) {
    present <- which[dir.exists(dest)]
    if (length(present))
      stop("these skills already exist under ", root, ": ",
           paste(present, collapse = ", "),
           "; pass overwrite = TRUE to replace them", call. = FALSE)
  }

  version <- coursepack_version()
  for (i in seq_along(which)) {
    files <- copy_tree(file.path(src, which[i]), dest[i])
    stamp_skill(file.path(dest[i], "SKILL.md"), version)
    cat(sprintf("  %-28s %2d file%s\n", which[i], length(files),
                if (length(files) == 1L) "" else "s"))
  }
  cat("wrote ", length(which), " skill", if (length(which) == 1L) "" else "s",
      " to ", root, "\n", sep = "")
  version_line("install_skills")
  invisible(dest)
}
