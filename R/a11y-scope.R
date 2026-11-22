# Module scope for audit_course(modules =).
#
# A module audit reads the same surfaces a full audit reads, cut down to what
# modules.yml places in the named modules:
#
#   rendered pages  the pages a scoped item's URL lands on (an iframe page's
#                   src, a link's url: or chapter:, a homework's chapter), in
#                   whichever audited repo serves that URL, plus every slide
#                   deck one of those pages links to
#   source checks   the .qmd/.Rmd sources of those pages, and no others
#   published PDFs  the PDFs those pages link to
#   cartridge       the wiki pages, weblinks and embedded videos the
#                   cartridge's own module tree places in modules of those
#                   titles. Announcements are not module content and are not
#                   read.
#
# A URL is matched to a repo by the course's urls: block. The repo that is the
# course project (`proj`) serves {site}; any other audited repo serves
# {textbook}. More than one other repo cannot be told apart, so a scoped run
# refuses it rather than guessing.
#
# A scoped item whose URL falls under {site} or {textbook} but lands on no
# rendered page is a finding, not a silent drop: it is part of the module and
# nothing about it was audited. A URL under neither base (a video, another
# site) is counted and listed in the report, never audited.

# The selected module titles, every scoped URL, and what each URL is.
audit_scope <- function(proj, modules, repos) {
  if (is.null(modules)) return(NULL)
  if (!length(modules) || !is.character(modules))
    stop("modules= must name at least one module by its modules.yml title",
         call. = FALSE)
  mods   <- read_modules(proj)
  urls   <- read_course(proj)$urls
  sel    <- select_modules(mods$modules, modules)       # stops on an unknown title
  titles <- vapply(mods$modules[sel], function(m) as.character(m$title), "")

  pages <- stats::setNames(mods$pages, vapply(mods$pages, `[[`, "", "slug"))
  asg   <- stats::setNames(mods$assignments, vapply(mods$assignments, `[[`, "", "id"))
  want  <- character()
  for (m in mods$modules[sel]) for (it in m$items) {
    u <- NULL
    if (!is.null(it$page)) u <- interp_urls(pages[[it$page]]$iframe, urls)
    else if (!is.null(it$link)) u <- url_for(it, urls)
    else if (!is.null(it$assignment)) {
      ch <- asg[[it$assignment]]$homework$chapter
      if (!is.null(ch) && nzchar(ch) && !is.null(urls$textbook))
        u <- chapter_url(ch, NULL, urls$textbook)
    }
    if (!is.null(u) && nzchar(u)) want <- c(want, u)
  }
  want <- unique(want)

  # Which repo serves which base.
  proj_n <- normalizePath(proj, mustWork = TRUE)
  repo_n <- vapply(repos, normalizePath, "", mustWork = TRUE, USE.NAMES = FALSE)
  others <- repo_n[repo_n != proj_n]
  if (length(others) > 1L)
    stop("modules= can tell the course repo ({site}) from one textbook repo ",
         "({textbook}), not from ", length(others), " repos besides the course: ",
         paste(basename(others), collapse = ", "), ". Audit them in separate runs.",
         call. = FALSE)
  if (length(others) && is.null(urls$textbook))
    stop("modules= needs urls: textbook: in course.yml to place pages in ",
         basename(others), call. = FALSE)
  base <- stats::setNames(character(), character())
  if (proj_n %in% repo_n) base[proj_n] <- urls$site %||% NA_character_
  if (length(others)) base[others] <- urls$textbook
  base <- base[!is.na(base)]

  list(modules = titles, slug = scope_slug(titles), urls = want, base = base)
}

# "Module 5" -> "module-5"; two modules join with "+".
scope_slug <- function(titles) {
  s <- tolower(gsub("[^A-Za-z0-9]+", "-", titles))
  paste(gsub("^-+|-+$", "", s), collapse = "+")
}

# A URL under `base`, as the path of the page it lands on, or NA.
url_to_rel <- function(u, base) {
  u <- sub("[?#].*$", "", u); b <- sub("/+$", "", base)
  if (identical(u, b)) return("index.html")
  if (!startsWith(u, paste0(b, "/"))) return(NA_character_)
  rel <- substring(u, nchar(b) + 2L)
  if (!nzchar(rel) || endsWith(rel, "/")) rel <- paste0(rel, "index.html")
  rel
}

# "a/b/../c.html" -> "a/c.html". NA when it climbs out of the output dir.
norm_rel <- function(p) {
  out <- character()
  for (s in strsplit(p, "/", fixed = TRUE)[[1]]) {
    if (s == "" || s == ".") next
    if (s == "..") { if (!length(out)) return(NA_character_); out <- out[-length(out)] }
    else out <- c(out, s)
  }
  paste(out, collapse = "/")
}

# Every relative href/src on a rendered page, resolved against the page.
page_links <- function(output_dir, rel) {
  f <- file.path(output_dir, rel)
  if (!file.exists(f)) return(character())
  h <- paste(readLines(f, warn = FALSE), collapse = "\n")
  v <- regmatches(h, gregexpr("(?:href|src)=\"([^\"]+)\"", h, perl = TRUE))[[1]]
  v <- sub("^(?:href|src)=\"", "", sub("\"$", "", v), perl = TRUE)
  v <- sub("[?#].*$", "", v)
  v <- v[nzchar(v) & !grepl("^[a-zA-Z][a-zA-Z0-9+.-]*:|^/", v)]
  d <- dirname(rel); if (d == ".") d <- ""
  out <- vapply(v, function(x) norm_rel(if (nzchar(d)) paste(d, x, sep = "/") else x),
                "", USE.NAMES = FALSE)
  unique(out[!is.na(out)])
}

is_reveal_deck <- function(path)
  file.exists(path) && any(grepl("class=\"reveal", readLines(path, warn = FALSE), fixed = TRUE))

# What the scope reaches in one discovered target: its scoped pages (item
# pages first, then the decks they link to), the PDFs those pages link to,
# the scoped URLs under its base that land on no page, and the out-of-scope
# sources the source checks must skip.
scope_target <- function(scope, tgt) {
  base <- unname(scope$base[tgt$repo])
  empty <- list(pages = character(), decks = character(), pdfs = character(),
                missing = character(), exclude = character(), in_base = character())
  if (!length(base) || is.na(base)) return(empty)
  rel <- vapply(scope$urls, url_to_rel, "", base = base, USE.NAMES = FALSE)
  in_base <- scope$urls[!is.na(rel)]
  rel <- rel[!is.na(rel)]
  hit <- rel %in% tgt$pages
  pages <- unique(rel[hit])
  missing <- unique(in_base[!hit])

  linked <- if (is.na(tgt$output_dir)) character() else
    unique(unlist(lapply(pages, function(p) page_links(tgt$output_dir, p))))
  decks <- setdiff(linked[linked %in% tgt$pages &
                   vapply(linked, function(p) is_reveal_deck(file.path(tgt$output_dir, p)), NA)],
                   pages)
  pdfs <- linked[grepl("\\.pdf$", linked, ignore.case = TRUE) &
                 file.exists(file.path(tgt$output_dir, linked))]

  # Sources of the scoped pages, by the path Quarto mirrors into the output
  # dir, falling back to a unique basename. Every other source is excluded.
  srcs <- list.files(tgt$repo, pattern = "\\.(qmd|Rmd)$", recursive = TRUE)
  srcs <- srcs[!grepl(SOURCE_EXCLUDE_RE, srcs)]
  stem <- tools::file_path_sans_ext(srcs)
  keep <- character()
  for (p in c(pages, decks, sub("\\.pdf$", ".html", pdfs, ignore.case = TRUE))) {
    s <- tools::file_path_sans_ext(p)
    k <- srcs[stem == s]
    if (!length(k)) {
      k <- srcs[basename(stem) == basename(s)]
      if (length(k) != 1L) k <- character()
    }
    keep <- c(keep, k)
  }
  list(pages = pages, decks = decks, pdfs = unique(pdfs), missing = missing,
       exclude = setdiff(srcs, keep), in_base = in_base)
}

# The resources a cartridge's own module tree places in modules titled
# `titles`, as paths inside the unzipped cartridge. Stops when a title is not
# a module of this cartridge: the cartridge is older than modules.yml, and a
# module audit of it would read nothing and look clean.
cartridge_scope_files <- function(dir, titles, label) {
  man <- xml2::xml_ns_strip(xml2::read_xml(file.path(dir, "imsmanifest.xml")))
  mods <- xml2::xml_find_all(man, "/manifest/organizations/organization/item/item")
  mt <- xml2::xml_text(xml2::xml_find_first(mods, "./title"))
  gone <- setdiff(titles, mt)
  if (length(gone))
    stop("the cartridge ", label, " has no module titled ",
         paste(gone, collapse = ", "), "; rebuild it, or move it out of the ",
         "searched directories, before a module audit", call. = FALSE)
  refs <- unlist(lapply(mods[mt %in% titles], function(m)
    xml2::xml_attr(xml2::xml_find_all(m, ".//item[@identifierref]"), "identifierref")))
  files <- character()
  for (r in unique(refs)) {
    res <- xml2::xml_find_first(man, sprintf("/manifest/resources/resource[@identifier='%s']", r))
    if (inherits(res, "xml_missing")) next
    files <- c(files, xml2::xml_attr(res, "href"),
               xml2::xml_attr(xml2::xml_find_all(res, "./file"), "href"))
  }
  files <- unique(files[!is.na(files)])
  file.path(dir, files[file.exists(file.path(dir, files))])
}
