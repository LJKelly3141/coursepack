#' coursepack: build tools for plain-text course authoring
#'
#' `coursepack` holds the build toolchain that turns a course's declarative
#' manifests into the artefacts a learning management system can import. It
#' holds no course content of its own.
#'
#' @section The contract every entry point keeps:
#'
#' - The first argument is `proj`, the course project root. There are no
#'   absolute paths in package code and no default pointing at any one course.
#' - Nothing is read from the environment that has a default. Defaults are
#'   function arguments; a `Makefile` supplies them.
#' - Course-specific facts (module counts, expected item counts, output file
#'   names, known divergences from a reference export) live in the course's own
#'   YAML, never as literals in R.
#'
#' Those three rules are what let one installed copy serve several courses
#' while keeping them separate. A function that reaches outside its `proj`
#' breaks the separation, so it is a defect regardless of what it was trying to
#' accomplish.
#'
#' @section Status:
#'
#' Skeleton only. No entry points have been migrated yet. The migration is
#' specified in `project/`; see `README.md`.
#'
#' @keywords internal
"_PACKAGE"
