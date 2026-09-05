# Course-agnostic discovery. Takes a repo path and answers: what built this,
# where did it put the HTML, which files are real pages, and is there an
# authored stylesheet to put shared fixes into.
#
# The last question is not cosmetic. If a repo has no stylesheet, every
# contrast and focus finding would be filed as a per-page fix and repeated
# once per page. Knowing there is no stylesheet is what lets the plan say
# "create one first" instead.
#
# NOTHING here defaults to any one course's path. The repo is always an
# argument.

# list_pages() below calls exclusion_matches(), which lives with the source
# checks. That is the one cross-file call this file makes, and it is
# deliberate: a project's declared `resources:` entries are globs, both the
# page scan here and the source scan there have to interpret them
# identically, and two copies of a matching rule is exactly how one shared
# key silently drifted apart once already.

# Directories whose contents are never authored by the project: dependency
# caches and build output. Shared by the two places in this file that have
# to tell "a real page/stylesheet nobody wrote yet" apart from "something a
# package manager or bundler put here": the loud HTML-exists warning in
# find_output_dir() below, and (in spirit; it takes no fallback path at all
# now) the reasoning behind find_stylesheet()'s config-only design.
#
# dist/ and build/ are also perfectly ordinary real output directory names
# for a Vite- or webpack-style static site. Putting them on this list is a
# real, accepted trade-off, not an oversight: see the DISTINCT warning
# find_output_dir() emits when HTML exists ONLY under one of these names,
# which exists specifically so that trade-off never has to be silent.
VENDOR_BUILD_DIRS <- c("node_modules", "vendor", "dist", "build",
                       "bower_components", "renv", "packrat", ".git")

is_vendor_or_build_path <- function(path) {
  esc <- gsub(".", "\\.", VENDOR_BUILD_DIRS, fixed = TRUE)
  grepl(paste0("(^|/)(", paste(esc, collapse = "|"), ")(/|$)"), path)
}

# Which known vendor/build directory name a path matched, for a warning
# message that names the actual directory rather than just repeating a raw
# relative path. Checks VENDOR_BUILD_DIRS in the same fixed order every
# time, so this is deterministic across calls with the same input.
matched_vendor_dir <- function(path) {
  for (d in VENDOR_BUILD_DIRS) {
    if (grepl(paste0("(^|/)", gsub(".", "\\.", d, fixed = TRUE), "(/|$)"), path)) {
      return(d)
    }
  }
  NA_character_
}

detect_framework <- function(repo) {
  if (file.exists(file.path(repo, "_quarto.yml")))   return("quarto")
  if (file.exists(file.path(repo, "_bookdown.yml"))) return("bookdown")
  if (length(Sys.glob(file.path(repo, "*.html"))))   return("static")
  "unknown"
}

# Where the framework wrote its HTML. Config first, then convention.
find_output_dir <- function(repo, framework) {
  if (framework == "quarto") {
    cfg <- try(yaml::yaml.load_file(file.path(repo, "_quarto.yml")), silent = TRUE)
    od  <- if (!inherits(cfg, "try-error")) cfg$project$`output-dir` else NULL
    if (!is.null(od)) {
      p <- file.path(repo, od)
      if (dir.exists(p)) return(normalizePath(p))
    }
  }
  # Symmetric with the quarto branch above: bookdown's real config key is a
  # top-level `output_dir:` in _bookdown.yml (not nested under `project:`,
  # and underscore not hyphen, since it is a different tool with a different
  # schema).
  # Without this, a bookdown project that sets output_dir to anything other
  # than one of the convention names below (e.g. "public_html") silently
  # fell through to a wrong or NA answer even though the config said exactly
  # where to look.
  if (framework == "bookdown") {
    cfg <- try(yaml::yaml.load_file(file.path(repo, "_bookdown.yml")), silent = TRUE)
    od  <- if (!inherits(cfg, "try-error")) cfg$output_dir else NULL
    if (!is.null(od)) {
      p <- file.path(repo, od)
      if (dir.exists(p)) return(normalizePath(p))
    }
  }
  for (cand in c("docs", "_site", "_book", "public", ".")) {
    p <- file.path(repo, cand)
    if (dir.exists(p) && length(Sys.glob(file.path(p, "*.html")))) {
      return(normalizePath(p))
    }
  }
  # Nothing at any conventional top-level name, and no config pointed
  # anywhere else either. From here, three states are possible, and each
  # must look different from the other two. A silent NA that could mean
  # either "there is genuinely no HTML here" or "there is HTML here, this
  # function just couldn't place it" is exactly the failure shape this
  # project keeps getting bitten by.
  all_html   <- list.files(repo, pattern = "\\.html$", recursive = TRUE)
  real_html  <- all_html[!is_vendor_or_build_path(all_html)]

  if (length(real_html)) {
    # State: HTML exists outside every excluded vendor/build directory, but
    # nothing above could place it under a recognized output directory --
    # a static site with only nested pages, or a build tool this discovery
    # doesn't recognize. Guessing which nested directory is "the" output
    # directory risks the exact class of bug already fixed once in
    # find_stylesheet(): a wrong, confident answer sent downstream. Warn
    # loudly instead.
    warning("a11y_targets: HTML exists under ", repo,
            " but no output directory could be confidently identified; ",
            "returning NA rather than guessing.", call. = FALSE)
  } else if (length(all_html)) {
    # State: every HTML file found lives ONLY under an excluded vendor or
    # build directory (node_modules/, dist/, etc). This must not collapse
    # into the same silence as "no HTML anywhere" below. dist/ and
    # build/ in particular are also real output directory names a genuine
    # static site generator might use (see VENDOR_BUILD_DIRS above), so a
    # confident silent NA here could just as easily be hiding a real,
    # undiscovered course as it could be correctly ignoring node_modules/.
    # Name the actual directory and one real path so whoever reads this can
    # tell at a glance which it is.
    example <- all_html[1]
    dir_hit <- matched_vendor_dir(example) %||% "an excluded directory"
    warning("a11y_targets: the only HTML found under ", repo,
            " is under an excluded vendor/build directory (", dir_hit,
            "/, e.g. ", example, "); if that is actually this project's ",
            "real output, discovery needs to be told explicitly rather ",
            "than guessed at.", call. = FALSE)
  }
  # else: no HTML anywhere in the repo, not even under an excluded
  # directory. Genuinely nothing to report; silence is correct here.
  NA_character_
}

# Directories a Quarto project itself declares as pass-through resources
# (project: resources: in _quarto.yml). These are copied into output_dir
# byte for byte, never rendered by this build, so an .html file that happens
# to live there was never a page in this project's sense of the word. One
# real book project used to develop this copies a directory of 25
# pre-existing standalone .html files this way, none of them one of its 21
# rendered chapters. This is read from config, not guessed from the
# directory's name, so it generalizes to any project that lists resources.
quarto_resource_dirs <- function(repo) {
  cfg <- try(yaml::yaml.load_file(file.path(repo, "_quarto.yml")), silent = TRUE)
  if (inherits(cfg, "try-error")) return(character())
  res <- cfg$project$resources %||% character()
  as.character(res)
}

# The pass-through directories a project declares, for any caller that needs
# to know which paths this build copies rather than authors.
#
# Added 2026-08-13. list_pages() above already excludes these directories'
# HTML on the grounds that a copied file was never a page this project
# rendered. The identical reasoning applies one layer down, to SOURCE files:
# a `.qmd` or `.Rmd` sitting inside a declared resource directory was never
# rendered by this build either, so it is not this course's source and a
# fig-alt finding against it names a figure this course does not publish.
# Confirmed against a real book repo whose `_quarto.yml` declares three
# resource directories and whose rendered chapters are all at the repo root.
#
# Read from config, never a directory NAME this project recognizes. No
# package code may know what any one course happens to call its working
# directories, which is why "exclude the working notes" is implemented as
# "exclude what the project itself declares it only copies" rather than as a
# literal string. A course that declares no resources gets character(), and
# everything in it is scanned.
#
# Framework coverage matches find_output_dir()/find_stylesheet(): quarto
# only. bookdown has no pass-through-resources key at all (its `rmd_files:`
# is the inverse signal, an explicit inclusion list, and reading it would
# mean treating an absent key as "include everything" in one framework and
# "exclude nothing" in the other, two different defaults for one argument).
# A bookdown or static repo therefore excludes nothing here, which is the
# same answer this file already gives for its stylesheet.
resource_dirs <- function(repo, framework) {
  if (identical(framework, "quarto")) quarto_resource_dirs(repo) else character()
}

# Sources that render to nothing.
#
# The rule, ruled 2026-08-13: material counts only if it is PRODUCED TO
# STUDENTS. Instructor-only material does not. A `.qmd` that produces no page
# was never delivered to anyone, so a finding against it names a figure or a
# chart the course does not publish, and acting on it is wasted work.
#
# This is DERIVED, never named. A source is unproduced when no rendered page
# with its name exists under the output directory. That one test happens to
# cover several distinct reasons a file is not an input, without this project
# having to know or hardcode any of them:
#   - Quarto excludes any path segment beginning with an underscore, so an
#     underscore-prefixed directory is never a project input at all.
#   - a book renders the chapters its config lists, so a directory it does
#     not list is simply absent from that list.
#   - a directory can be dropped from a render allowlist at any time.
# Naming those directories in package code would hardcode one course's layout.
# Asking "did this produce a page" asks the question the rule actually cares
# about, and keeps working when the layout changes.
#
# Composes with resource_dirs() rather than duplicating it. A file copied
# verbatim by `resources:` DOES have an HTML counterpart in the output tree,
# so this test alone would keep it; the resources exclusion is what removes
# it. Two different reasons, two separate filters, both required.
#
# An UNRENDERED repo returns character(): with no output there is no evidence
# either way, so nothing is excluded on this basis and everything is scanned.
# That is the safe direction, it is the fallback the fig-alt check already
# reports as its mode, and a repo that rendered nothing is separately reported
# as having examined nothing.
unproduced_sources <- function(repo, output_dir) {
  if (is.na(output_dir) || !dir.exists(output_dir)) return(character())
  src <- list.files(repo, pattern = "\\.(qmd|Rmd)$", recursive = TRUE)
  if (!length(src)) return(character())
  rendered <- file.path(output_dir, sub("\\.(qmd|Rmd)$", ".html", src))
  src[!file.exists(rendered)]
}

# Real pages only. Two kinds of thing under output_dir are not a page:
# (1) Quarto's own build artifacts, always named by convention: *_files/
#     directories and site_libs/ or /libs/ trees hold widget and library
#     HTML that is never navigated to, and
# (2) whatever the project declared under project: resources:, copied
#     verbatim rather than rendered (see quarto_resource_dirs() above).
# Auditing either kind inflates the page count and reports findings on files
# nobody can navigate to as a "page". Both exclusions match on path
# structure, a naming convention or a config value, not on guessing from
# a directory's name, so the same rule that gives 2 pages on a synthetic
# fixture with no resources: key gives 21 on a real book repo, which has one.
list_pages <- function(repo, framework, output_dir) {
  if (is.na(output_dir)) return(character())
  all <- list.files(output_dir, pattern = "\\.html$", recursive = TRUE)
  is_artifact <- grepl("(^|/)(site_libs|libs)/|_files/", all)

  # Matched with exclusion_matches(), which the source checks share, not with
  # a literal `== d || startsWith(d "/")` comparison. Fixed 2026-08-13,
  # re-review finding 1 (moderate): a real repo's `_quarto.yml` declares
  # `resources: ["assets/**"]`, and the literal string `assets/**` can never
  # equal or prefix a real path, so the most common Quarto glob idiom
  # excluded nothing here and said nothing about it. The same flaw was in
  # the source-file scan and both now share one matcher, so a fix to glob
  # semantics can never land in one and miss the other.
  res_dirs <- if (identical(framework, "quarto")) quarto_resource_dirs(repo)
              else character()
  is_resource <- rep(FALSE, length(all))
  for (d in res_dirs) {
    is_resource <- is_resource | exclusion_matches(all, d)
  }

  all[!is_artifact & !is_resource]
}

# Bookdown's css: setting is not part of _bookdown.yml (that file holds
# book-level settings like output_dir, book_filename, delete_merged_file --
# see find_output_dir() above). It lives per output format in _output.yml,
# e.g. `bookdown::gitbook: css: style.css` or `bookdown::bs4_book: css:
# style.css`, since a book can render to several formats at once and each
# can have its own stylesheet. A bare top-level css: directly in
# _bookdown.yml is also checked; non-standard, but seen in the wild, and
# costs nothing to try. Returns every candidate path found, in the order
# found; find_stylesheet() below tries each until one resolves to a real
# file.
bookdown_stylesheet_candidates <- function(repo) {
  candidates <- character()
  for (f in c("_output.yml", "_bookdown.yml")) {
    # Gate on file.exists() first, matching every other config read in this
    # file: _output.yml in particular is optional (many bookdown projects
    # have none), and calling yaml.load_file() on a path that doesn't exist
    # emits a readLines() warning before try() ever gets to the error, which
    # would otherwise print confusing noise into clean test output.
    if (!file.exists(file.path(repo, f))) next
    cfg <- try(yaml::yaml.load_file(file.path(repo, f)), silent = TRUE)
    if (inherits(cfg, "try-error") || !is.list(cfg)) next
    if (!is.null(cfg$css)) candidates <- c(candidates, as.character(cfg$css))
    for (fmt in cfg) {
      if (is.list(fmt) && !is.null(fmt$css)) {
        candidates <- c(candidates, as.character(fmt$css))
      }
    }
  }
  candidates
}

# An authored stylesheet, not a vendored or cached one.
#
# Trusts ONLY a stylesheet the project's own config explicitly points at
# (quarto's css: or theme:, bookdown's css: in _output.yml or _bookdown.yml,
# each resolving to a real file). Does NOT fall back to scanning the repo
# for the first .css/.scss file found anywhere. An earlier version did
# exactly that, filtered by a fixed exclusion regex, and the regex was
# always going to be wrong somewhere: it hardcoded the literal string
# "/docs/" instead of the actual resolved output_dir, so a Quarto project
# with output-dir: _output and a generated theme-compiled.css sitting there
# was returned as "the" stylesheet, and it had no entries at all for
# node_modules/, vendor/, dist/, build/, or bower_components/, so a repo
# with nothing but vendored or webpack-bundled CSS also returned a
# confident, wrong path.
#
# A wrong non-NA answer here is worse than NA. A downstream shared fix
# routed into a vendored or generated file gets silently overwritten by the
# next `npm install` or build and the fix disappears with no error anywhere.
# NA correctly produces "create a stylesheet first," which is the safe
# answer whenever the project's own config doesn't say. Trusting only what
# config explicitly declares also has no denylist to keep up to date: it
# does not matter what a vendor or build-output directory happens to be
# named, because nothing outside a config-declared path is ever considered.
#
# Framework coverage: quarto and bookdown are both handled, symmetrically
# with what find_output_dir() already reads for each. Static sites are NOT
# handled, because there is no config file to read a css: link out of, and
# parsing <link rel="stylesheet"> out of raw HTML was deliberately not
# built (see the report's deferred section). A static-framework repo always
# returns NA here, even when it has an obvious, real, authored stylesheet
# sitting right next to its HTML.
find_stylesheet <- function(repo, framework) {
  if (framework == "quarto") {
    cfg <- try(yaml::yaml.load_file(file.path(repo, "_quarto.yml")), silent = TRUE)
    if (!inherits(cfg, "try-error")) {
      css <- cfg$format$html$css %||% cfg$format$html$theme
      # A bare built-in theme name (e.g. "sandstone") is not a file in the
      # repo and won't resolve below; a custom theme given as a path, alone
      # (e.g. "theme.scss") or alongside a built-in base (e.g.
      # theme: [cosmo, custom.scss]), will. Trying every candidate is what
      # tells a built-in keyword and an authored file apart.
      if (!is.null(css)) {
        for (cand in css) {
          p <- file.path(repo, cand)
          if (file.exists(p)) return(normalizePath(p))
        }
      }
    }
  }
  if (framework == "bookdown") {
    for (cand in bookdown_stylesheet_candidates(repo)) {
      p <- file.path(repo, cand)
      if (file.exists(p)) return(normalizePath(p))
    }
  }
  NA_character_
}

#' Discover what an audit should look at in a rendered repository
#'
#' Takes a repository path and answers, from that project's own config and
#' layout, what built it, where the HTML went, which of those files are real
#' pages, which directories it only copies, which sources render to nothing,
#' and whether there is an authored stylesheet to put shared fixes into.
#'
#' Nothing here defaults to any one course's path; the repository is always an
#' argument. A missing stylesheet is reported as `NA` rather than guessed at,
#' because a shared fix routed into a vendored or generated file is silently
#' overwritten by the next build.
#'
#' @param repo_path Path to the repository to audit. Must exist.
#' @return A list of `repo`, `framework` (`"quarto"`, `"bookdown"`,
#'   `"static"`, or `"unknown"`), `output_dir` (`NA` when it cannot be placed
#'   confidently), `source_dir`, `pages`, `resource_dirs`,
#'   `unproduced_sources`, and `stylesheet`.
#' @export
discover_target <- function(repo_path) {
  repo <- normalizePath(repo_path, mustWork = TRUE)
  fw   <- detect_framework(repo)
  od   <- find_output_dir(repo, fw)
  list(
    repo       = repo,
    framework  = fw,
    output_dir = od,
    source_dir = repo,
    pages      = list_pages(repo, fw, od),
    # Directories this project declares as pass-through resources, read from
    # the project's own config rather than named anywhere in package code.
    # Added 2026-08-13: the source-layer checks take this as a REQUIRED
    # argument, the same discipline `surface` already follows. The
    # check knows what to skip only because the caller, which owns discovery,
    # says so. See resource_dirs()'s own comment below for why a `resources:`
    # entry is the honest signal for source files and not only for HTML.
    resource_dirs = resource_dirs(repo, fw),
    # Individual sources that render to no page. See unproduced_sources().
    # The driver unions these with resource_dirs into the exclusion the
    # source-layer checks require.
    unproduced_sources = unproduced_sources(repo, od),
    stylesheet = find_stylesheet(repo, fw))
}

# The one raw "repo path -> its surface base name" rule underneath every
# surface name this project derives, page or cartridge. page_surface_name()
# applies it to an already-discovered target's own normalized repo path;
# cartridge_surface_name() (below) applies it directly to a raw repo path (a
# cartridge has no discover_target() of its own to read a normalized path
# back from). Both ultimately compute the identical
# `basename(normalizePath(repo))`; pulled out here so the two can never
# silently drift into disagreement (coordinator review, Task 8 finding 4
# addendum: they duplicated this formula independently before).
repo_surface_base <- function(repo) basename(normalizePath(repo))

# The surface name a page-auditing pass derives from a discover_target()
# result. Pulled out as its own function, not left as an inline
# `basename(tgt$repo)` in the audit driver, so the rule the driver uses to
# BUILD its declared surface list and the rule a test uses to independently
# verify that declaration are provably the one same rule, never two copies
# that could quietly drift apart.
page_surface_name <- function(target) repo_surface_base(target$repo)

# The surface name the audit driver derives for a repo's cartridge findings,
# suffixed so a cartridge finding and a rendered-page finding for the same
# course never share a surface (coordinator review, finding 4).
cartridge_surface_name <- function(repo) paste0(repo_surface_base(repo), "-cartridge")

# ---- surface identity is a basename, and that has two real consequences ----
#
# Added 2026-08-13, final whole-branch review, finding I8 (important).
# repo_surface_base() above is `basename(normalizePath(repo))`, so a surface
# identity is a DIRECTORY NAME, not a repo identity. Two consequences, one
# fixed here and one recorded rather than fixed:
#
# 1. COLLISION (fixed here, loudly). Two repos whose paths end in the same
#    directory name (~/courses/abcd101/book and ~/archive/abcd101/book, or a
#    repo and its own git worktree checked out under the same leaf name)
#    resolve to ONE surface. The driver keys targets[[surface]] by that name,
#    intended_surfaces() writes out[surface] by that name, and the second repo
#    silently overwrites the first: one course's findings would classify
#    against the OTHER course's stylesheet, and its page count would vanish
#    from the declaration. This is the same silent-collapse failure mode the
#    cartridge `surface` argument was added to prevent, one level up, so it
#    gets the same answer: HALT rather than continue with two things merged
#    into one. Both intended_surfaces() below and the audit driver call this,
#    so the guarantee does not depend on the driver remembering to.
# 2. PORTABILITY (recorded, not fixed). Because the identity is a path
#    basename and the finding id hashes the surface, auditing the SAME course
#    from a different path (a clone, a worktree, a renamed directory) produces
#    a disjoint id set, so the next diff against a prior findings JSON reports
#    100% fixed and 100% new. Recorded rather than papered over: a stable
#    per-repo identity (a git remote URL, a declared
#    id in the repo's own config) is a real design question, not a rename.
halt_on_surface_collision <- function(repos) {
  if (length(repos) < 2) return(invisible(repos))
  bases <- vapply(repos, repo_surface_base, character(1))
  dup   <- unique(bases[duplicated(bases)])
  if (length(dup)) {
    for (d in dup) {
      which_repos <- vapply(repos[bases == d], function(r) normalizePath(r),
                            character(1))
      stop("a11y_targets: two or more repos resolve to the same surface name '",
           d, "': ", paste(which_repos, collapse = ", "),
           ". A surface name is a path basename, so these would silently ",
           "collapse into one surface: one course's findings would classify ",
           "against the other's stylesheet and one page count would ",
           "disappear from the declaration. Rename a directory, or audit ",
           "them in separate runs.")
    }
  }
  invisible(repos)
}

# The one increment used by every empirical page counter in this project.
#
# Added 2026-08-13, final whole-branch review, finding C1 (critical).
# `pages_examined` must be an EMPIRICAL measurement accumulated inside the
# loops that do the work, never a second read of intended_surfaces() (which
# is the DECLARATION). Two signals from one function call cannot cross-check
# each other, and render_report()'s coverage comparison is exactly that
# cross-check. This helper exists so the increment is a named, testable
# operation rather than an inline `v[s] <- v[s] + n` that silently produces
# NA the first time a surface is seen (`integer(0)["new"]` is NA, and
# NA + 1L is NA, which would quietly poison the count instead of starting
# it at 1).
bump_examined <- function(v, surface, n = 1L) {
  cur <- if (surface %in% names(v)) v[[surface]] else 0L
  v[[surface]] <- as.integer(cur) + as.integer(n)
  v
}

# What a driver intends to declare in BOTH pages_examined and meta$surfaces
# for an entire run: one entry per page surface (from discover_target(),
# valued at its real page count) and one entry per cartridge surface that
# actually has at least one `.imscc` under CARTRIDGE_SEARCH_DIRS (from the
# cartridge library's cartridges_in(), valued at its total wiki-page count
# via cartridge_wiki_page_count(), never a raw `.imscc` FILE count, which
# would mix units with every page-surface entry sitting next to it; see the
# coordinator's finding 5).
#
# Coordinator review, Task 8 finding 4, round 2 (important): the first
# version of this function (then named intended_page_surfaces(), page
# surfaces only) was checked by a test that computed its OWN expected value
# with the identical inline expression this function's body uses --
# `vapply(repos, function(r) page_surface_name(discover_target(r)), ...)`,
# typed out a second time in the test. That is a function checked against a
# hand-copied restatement of its own definition; it cannot fail under any
# real regression, only under non-determinism, and it never touched the
# driver's actual `pages_examined`/`meta$surfaces` at all, so a real driver
# bug (a wrong surface name, a repo silently skipped) was invisible to it.
# Fixed two ways at once: this is now the ONE function both the audit driver
# (to build the real declaration a run writes) and the suite (to exercise
# that exact same code path against hand-built fixtures) call. No second,
# parallel copy of the derivation exists anywhere for a test to accidentally
# re-derive instead of independently check, and cartridge surfaces,
# previously excluded entirely (zero automated coverage of
# `cartridge_surface_name()`'s formula), are now in scope.
#
# Amended 2026-08-13, final whole-branch review, finding C1 (critical). This
# is the DECLARATION, and as of that review it is the source of meta$surfaces
# ONLY. The audit driver briefly built BOTH meta$surfaces and
# pages_examined from this one call, which made the renderer's coverage
# cross-check compare a value against itself: neutering an entire audit loop
# left the page count and the surface list both intact, fired no banner, and
# the report read as a clean audit. pages_examined is now accumulated inside
# the loops that do the work, via bump_examined() above. Do not re-merge them.
#' The surfaces a run intends to declare
#'
#' One entry per page surface, valued at its real page count, plus one entry
#' per cartridge surface that actually has a cartridge, valued at its total
#' wiki-page count rather than a raw file count. This is the DECLARATION; the
#' empirical `pages_examined` count is accumulated separately inside the loops
#' that do the work, so the report's coverage comparison is a real
#' cross-check and not a value compared against itself.
#'
#' Halts when two repositories resolve to the same surface name, since a
#' surface name is a path basename and the two would otherwise collapse into
#' one, classifying one course's findings against the other's stylesheet.
#'
#' @param repos Character vector of repository paths.
#' @return A named integer vector, surface name to count.
#' @export
intended_surfaces <- function(repos) {
  halt_on_surface_collision(repos)
  out <- integer(0)
  for (r in repos) {
    tgt <- discover_target(r)
    out[page_surface_name(tgt)] <- length(tgt$pages)
  }
  for (r in repos) {
    imsccs <- cartridges_in(r)
    if (length(imsccs)) {
      out[cartridge_surface_name(r)] <-
        sum(vapply(imsccs, cartridge_wiki_page_count, integer(1)))
    }
  }
  out
}
