assignment_group_ids <- function(course) {
  groups <- course$assignment_groups %||% list()
  ids <- vapply(groups, function(g) g$id %||% gid("assignmentgroup", g$name), "")
  names(ids) <- vapply(groups, function(g) as.character(g$name), "")

  if (identical(course$canvas$group_weighting_scheme, "percent")) {
    total <- sum(vapply(groups, function(g) as.numeric(g$weight), 0))
    if (abs(total - 100) > 0.01)
      stop("assignment group weights sum to ", format(total), ", not 100")
  }

  ids
}

group_id_for <- function(name, groups, what) {
  if (is.null(name) || !length(name) || !name %in% names(groups))
    stop(what, " names assignment group '", name %||% "",
         "', which is not declared (declared: ",
         paste(names(groups), collapse = ", "), ")")
  unname(groups[[name]])
}
