url_for <- function(it, urls) {
  if (!is.null(it$url)) return(it$url)
  chapter_url(it$chapter, it$anchor, urls$textbook)
}


# An assignment or quiz item may not claim to be published past its own
# definition. Canvas shows the definition's state, so the module would list a
# live item pointing at something a student cannot open, and nothing in the
# import reports it. Refuse instead of quietly preferring one of the two.
item_over_def <- function(it, def, title) {
  if (isTRUE(it$published) && !isTRUE(def$published))
    stop("item ", title, " is published but its definition is not", call. = FALSE)
  invisible(NULL)
}

# ---- which modules a build stages -----------------------------------------
#
# `modules =` on build_cartridge() names them by title. NULL is every module,
# which is the whole course and the only form the byte gate stands behind.
#
# An unknown title STOPS, and the message lists the titles the manifest does
# declare. A title is typed by hand, so a typo is the likely case rather than a
# rare one, and a build that quietly dropped a name it did not recognise would
# report a successful build of nothing: on the console that reads exactly like
# a build of the modules that were asked for.
#
# Returns the POSITIONS of the selected modules in the declared order, so a
# staged module keeps the position it holds in the whole course rather than
# being renumbered from one.
select_modules <- function(mods, modules) {
  if (is.null(modules)) return(seq_along(mods))
  titles <- vapply(mods, function(x) as.character(x$title %||% ""), "")
  want <- unique(as.character(modules))
  unknown <- setdiff(want, titles)
  if (length(unknown))
    stop("modules= names modules not in modules.yml: ",
         paste(unknown, collapse = ", "), ". The modules it declares are: ",
         paste(titles, collapse = ", "), call. = FALSE)
  which(titles %in% want)
}

# ---- resolve every module item into a flat, fully-identified table --------
#
# `modules` restricts the walk to the modules it names; see select_modules().
# Every id below is still computed for EVERY definition, because an id is a
# fact about the definition rather than about this build, and a course that
# names its own `resource_id:` must get the same one whichever modules are
# staged. What the selection changes is `used`: the definitions the staged
# items point at, in the order the manifest declares them, which is what the
# writers loop over.
resolve_items <- function(m, modules = NULL) {
mods <- m$mods
urls <- m$course$urls
pages <- stats::setNames(mods$pages,       vapply(mods$pages,       `[[`, "", "slug"))
asg   <- stats::setNames(mods$assignments, vapply(mods$assignments, `[[`, "", "id"))
quiz  <- if (is.null(mods$quizzes)) list() else
         stats::setNames(mods$quizzes, vapply(mods$quizzes, `[[`, "", "id"))

# Resource ids are computed ONCE, here, and every writer reads them from the
# returned ids block. A definition may name its own with `resource_id:`, which
# is how a course adopts an id Canvas already holds; check_gid() rejects
# anything that is not "g" plus 32 hex. Re-deriving the same id downstream
# would silently ignore the override, so nothing below calls gid() for a
# resource again.

# A CARRIED definition's resource id is the id it carries. The resource block
# and the files come out of the source cartridge under that id, so deriving a
# fresh one would leave the module item pointing at a resource nothing wrote.
# An explicit resource_id: still wins, which is how a course renames a carried
# resource on the way through.
res_id <- function(def, kind, k)
  check_gid(def$resource_id) %||% def$source_ref %||% gid(kind, k)

# Quizzes need three ids each: the assessment resource (which the module item
# points at), the meta resource, and the inner assignment. Only the assessment
# resource is overridable: it is the one Canvas exposes as the quiz.
quiz_res  <- vapply(names(quiz), function(k) res_id(quiz[[k]], "quiz", k), "")
quiz_meta <- vapply(names(quiz), function(k) gid("quizmeta", k),       "")
quiz_aid  <- vapply(names(quiz), function(k) gid("quizassignment", k), "")

# Assignment resource ids and directory names, needed before the item walk.
asg_res <- vapply(names(asg), function(k) res_id(asg[[k]], "assignment", k), "")
asg_dir <- asg_res
asg_pos <- stats::setNames(seq_along(names(asg)), names(asg))

page_res <- vapply(names(pages), function(k) res_id(pages[[k]], "page", k), "")

items <- list(); modmeta <- list()
# The module a quiz is FIRST used in. A generated quiz's default description
# names it ("Quiz for <module>"), and the module title is a fact about the walk
# rather than about the definition, so it is recorded here where the walk runs
# instead of being searched for again by the writer.
quiz_module <- character()
# The definitions the walk actually reaches. A whole-course build reaches every
# one of them, because check_manifests() already refuses a definition no item
# references; a staged build reaches only what its modules point at.
used_p <- character(); used_a <- character(); used_q <- character()
for (mi in select_modules(mods$modules, modules)) {
  m <- mods$modules[[mi]]
  mrow <- list(id = check_gid(m$module_id, "module_id") %||% gid("module", m$title),
               title = m$title, position = mi,
               state = if (isTRUE(m$published)) "active" else "unpublished",
               sequential = isTRUE(m$sequential), items = list())
  for (pi in seq_along(m$items)) {
    it <- m$items[[pi]]
    key <- paste(m$title, pi, sep = "#")
    r <- list(position = pi, indent = if (is.null(it$indent)) 0L else as.integer(it$indent),
              item_id = check_gid(it$item_id, "item_id") %||% gid("item", key),
              new_tab = "false", url = NULL,
              mm_idref = NULL, man_idref = NULL, state = "active")

    if (!is.null(it$header)) {
      r$ctype <- "ContextModuleSubHeader"; r$title <- oneline(it$header)

    } else if (!is.null(it$page)) {
      r$ctype <- "WikiPage"; r$title <- pages[[it$page]]$title
      r$mm_idref <- r$man_idref <- page_res[[it$page]]
      used_p <- c(used_p, it$page)

    } else if (!is.null(it$link)) {
      r$ctype <- "ExternalUrl"; r$title <- oneline(it$link); r$url <- url_for(it, urls)
      if (isTRUE(it$new_tab)) r$new_tab <- "true"
      # THE QUIRK: module_meta self-references; the manifest points at the resource.
      r$mm_idref  <- r$item_id
      r$man_idref <- gid("weblink", key)

    } else if (!is.null(it$assignment)) {
      a <- asg[[it$assignment]]
      r$ctype <- "Assignment"; r$title <- a$title
      r$mm_idref <- r$man_idref <- asg_res[[it$assignment]]
      used_a <- c(used_a, it$assignment)
      if (!isTRUE(a$published)) r$state <- "unpublished"
      item_over_def(it, a, r$title)

    } else if (!is.null(it$quiz)) {
      q <- quiz[[it$quiz]]
      if (is.null(q)) stop("module item references undefined quiz: ", it$quiz)
      r$ctype <- "Quizzes::Quiz"; r$title <- q$title
      r$mm_idref <- r$man_idref <- quiz_res[[it$quiz]]
      used_q <- c(used_q, it$quiz)
      if (!it$quiz %in% names(quiz_module)) quiz_module[[it$quiz]] <- m$title
      # Canvas writes <new_tab/> empty for quiz items, not "false".
      r$new_tab <- ""
      if (!isTRUE(q$published)) r$state <- "unpublished"
      item_over_def(it, q, r$title)

    } else stop("module item has no recognized form at ", key)

    # An item may unpublish itself. A header, a page and a link have no
    # definition carrying a state, so `published:` on one of those IS the
    # item's state; without it the item follows the module, as before. On an
    # assignment or quiz item it can only agree with the definition or take
    # that item out of the module, which is what item_over_def() enforces
    # above.
    if (isFALSE(it$published)) r$state <- "unpublished"

    mrow$items[[pi]] <- r
    items[[length(items) + 1]] <- r
  }
  # Appended rather than indexed by mi: a staged build's selection has gaps,
  # and modmeta[[mi]] would leave a NULL where every reader expects a module.
  modmeta[[length(modmeta) + 1L]] <- mrow
}

# In DEFINITION order, not in the order the walk met them: a writer's output
# order is the order the manifest declares its definitions in, and for a whole
# course this hands back exactly the manifest it was given.
list(items = items, modmeta = modmeta, quiz_module = quiz_module,
     used = list(pages = intersect(names(pages), used_p),
                 assignments = intersect(names(asg), used_a),
                 quizzes = intersect(names(quiz), used_q)),
     ids = list(quiz_res = quiz_res, quiz_meta = quiz_meta, quiz_aid = quiz_aid,
                asg_res = asg_res, asg_pos = asg_pos, page_res = page_res))
}

# The definitions the selected modules reference, in the order the manifest
# declares them. Everything below the walk loops over these rather than over the
# whole manifest, so a definition is written only when a staged item points at
# it. For a whole course the two are the same list: an unreferenced definition
# is already an orphan failure in check_manifests().
selected_defs <- function(m, used) {
  m$pages       <- m$pages[used$pages]
  m$assignments <- m$assignments[used$assignments]
  m$quizzes     <- m$quizzes[used$quizzes]
  m
}
