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

# lecturecast, a separate package that turns slide decks into narrated videos,
# ships skills of its own. It is optional and not declared in DESCRIPTION (its
# repository is private for now, so GitHub's automatic test run could not
# install it), so it is found by system.file() alone and no lecturecast
# function is ever called from here. When it is installed its skills travel
# with coursepack's, and one call gives a course both.
skill_packages <- c("coursepack", "lecturecast")

pkg_skill_dir <- function(pkg) system.file("skills", package = pkg)
pkg_version <- function(pkg) as.character(utils::packageVersion(pkg))

# One row per shipped skill: its name, the package that ships it and the
# directory it is copied from. A name shipped by both packages stops here,
# before anything is copied, because the second copy would land on the first
# under .claude/skills/ and nobody would see it happen.
skill_index <- function() {
  rows <- lapply(skill_packages, function(pkg) {
    d <- pkg_skill_dir(pkg)
    if (!nzchar(d)) {
      if (pkg == "coursepack") stop("coursepack skills are not installed", call. = FALSE)
      return(NULL)
    }
    dirs <- list.dirs(d, recursive = FALSE)
    data.frame(name = basename(dirs), package = rep(pkg, length(dirs)),
               dir = dirs, stringsAsFactors = FALSE)
  })
  idx <- do.call(rbind, rows)
  dup <- unique(idx$name[duplicated(idx$name)])
  if (length(dup))
    stop("skill shipped by more than one package: ", paste(dup, collapse = ", "),
         call. = FALSE)
  idx
}

shipped_skills <- function() skill_index()$name

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
stamp_skill <- function(path, version, pkg = "coursepack") {
  n <- file.size(path)
  ends_newline <- n > 0 && identical(readBin(path, "raw", n = n)[n], as.raw(10L))
  cat(if (ends_newline) "" else "\n",
      "\n<!-- installed from ", pkg, " ", version, " -->\n",
      sep = "", file = path, append = TRUE)
}

#' Install the shipped skills into a course
#'
#' Copies each skill directory out of the installed package into
#' `<proj>/.claude/skills/` and stamps the package version at the bottom of
#' every copied `SKILL.md`.
#'
#' When the optional lecturecast package is installed, its shipped skills (such
#' as `lecture-video`, for narrated videos made from a slide deck) are copied
#' too, stamped with lecturecast's version, so one call gives a course both
#' packages' skills. Without lecturecast nothing changes. A skill name shipped
#' by both packages stops the call before anything is copied.
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
#' @param which Skill names to install. `NULL` installs every shipped skill,
#'   lecturecast's included when it is installed.
#' @param overwrite Whether to replace a skill already installed under `proj`.
#' @return The destination directories, invisibly.
#' @examples
#' root <- init_course(tempfile("course-"), code = "ABCD 101",
#'                     title = "Demo Course",
#'                     site_url = "https://example.org/demo",
#'                     timezone = "America/Chicago", git = FALSE,
#'                     skills = FALSE)
#' install_skills(root)
#' list.files(file.path(root, ".claude", "skills"))
#' unlink(root, recursive = TRUE)
#' @export
install_skills <- function(proj = ".", which = NULL, overwrite = FALSE) {
  idx <- skill_index()
  available <- idx$name
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

  for (i in seq_along(which)) {
    row <- idx[idx$name == which[i], ]
    files <- copy_tree(row$dir, dest[i])
    stamp_skill(file.path(dest[i], "SKILL.md"), pkg_version(row$package), row$package)
    cat(sprintf("  %-28s %2d file%s\n", which[i], length(files),
                if (length(files) == 1L) "" else "s"))
  }
  cat("wrote ", length(which), " skill", if (length(which) == 1L) "" else "s",
      " to ", root, "\n", sep = "")
  version_line("install_skills")
  invisible(dest)
}
