# Shared case-study assignment body extraction. Sourced, never executed.
#
# WHY THIS EXISTS. The case study directions live in the textbook. Until
# 2026-09-01 a Canvas assignment carried only a sentence and a link, so a
# student had to leave Canvas to find out what to do. The directions are now
# COPIED into the assignment description. The chapter is the source of truth and
# is never modified; this reads its RENDERED output and takes a copy.
#
# WHY IT READS RENDERED HTML RATHER THAN THE .qmd. The anchors in modules.yml
# are Quarto-generated ids, and they only exist after a render. Parsing the
# .qmd would mean reimplementing Quarto's heading-to-id rules and getting them
# subtly wrong. Reading docs/ means the copy is exactly what a reader sees.
#
# THE COST, STATED PLAINLY: this makes the cartridge depend on the textbook
# having been rendered. If docs/ is stale, the copied directions are stale, and
# nothing here can detect that. The build fails loudly when a chapter or anchor
# is missing, which is the case that matters, but it cannot tell fresh output
# from old output. Render the textbook before building a cartridge for import.
#
# WHY IT IS SHARED. build_cartridge() inlines this into the Canvas assignment
# and build_preview() shows the same thing in the mockup. Two callers, one
# function, so a preview cannot show directions that differ from what ships.

# Pull one section out of a rendered chapter, by its Quarto anchor id.
# Returns HTML, with relative links and images rewritten to absolute URLs so
# they still resolve once the fragment is sitting inside Canvas.
#' Extract a homework section from rendered textbook HTML
#'
#' Reads the rendered textbook, never the .qmd.
#' Refuses rather than falling back to the whole case study.
#'
#' @param chapter Textbook chapter slug.
#' @param anchor Quarto anchor id for the homework section.
#' @param tb_docs Path to the rendered textbook directory.
#' @param tb_base Base URL for the rendered textbook.
#' @param id Assignment identifier used in error messages.
#' @return The extracted student-facing HTML fragment.
#' @examples
#' # Stand in for a rendered chapter. Only the subsections that carry no
#' # subsections of their own are kept, so a walkthrough is left behind.
#' docs <- tempfile("textbook-")
#' dir.create(docs)
#' writeLines(c('<section id="homework"><h2>Homework 1</h2>',
#'              '<section id="instructions"><h3>Instructions</h3>',
#'              '<p>Fit the model, then upload your write-up.</p>',
#'              '<p><a href="data/wages.csv">data/wages.csv</a></p>',
#'              '</section></section>'),
#'            file.path(docs, "ch01.html"))
#'
#' # The relative link comes back absolute and the headings start at h2.
#' cat(homework_section_html("ch01", "homework", docs, "https://example.org/book"))
#'
#' unlink(docs, recursive = TRUE)
#' @export
homework_section_html <- function(chapter, anchor, tb_docs, tb_base, id = chapter) {
  f <- file.path(tb_docs, paste0(chapter, ".html"))
  if (!file.exists(f))
    stop("assignment '", id, "': chapter is not rendered: ", f,
         "\n  Render the textbook before building.")
  h <- paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  # Literal search rather than a regex built from the anchor. Quarto ids are
  # lowercase letters, digits and hyphens, so escaping them into a pattern buys
  # nothing and an escaping bug here fails in a confusing way.
  needle <- paste0('id="', anchor, '"')
  at <- regexpr(needle, h, fixed = TRUE)
  if (at[1] == -1)
    stop("assignment '", id, "': anchor '#", anchor, "' not found in ", chapter,
         ".html. The heading may have been renamed. Refusing to build.")

  # Back up to the <section that carries this id.
  head_part <- substr(h, 1, at[1])
  opens <- gregexpr("<section\\b", head_part, perl = TRUE)[[1]]
  if (opens[1] == -1)
    stop("assignment '", id, "': anchor '#", anchor, "' is not inside a section.")
  start <- opens[length(opens)]
  after <- at[1] + attr(at, "match.length")
  # the opening tag ends at the next '>' after the id
  gt <- regexpr(">", substr(h, after, nchar(h)), fixed = TRUE)
  if (gt[1] == -1) stop("assignment '", id, "': malformed section tag for #", anchor)
  after <- after + gt[1]

  # Walk nested <section> tags to find this section's own close.
  toks <- gregexpr("</?section\\b", substr(h, after, nchar(h)), perl = TRUE)[[1]]
  if (toks[1] == -1) stop("assignment '", id, "': unterminated section for #", anchor)
  depth <- 1L; endpos <- NA_integer_
  for (k in seq_along(toks)) {
    tk <- substr(h, after + toks[k] - 1, after + toks[k])
    depth <- depth + if (identical(tk, "</")) -1L else 1L
    if (depth == 0L) { endpos <- after + toks[k] + 8L; break }
  }
  if (is.na(endpos)) stop("assignment '", id, "': could not close section #", anchor)

  seg <- substr(h, start, endpos)

  # KEEP ONLY THE INSTRUCTIONS, not the whole case study. Decided 2026-09-01.
  #
  # A homework section is built from subsections that are consistently named:
  # "Objective", "Instructions", "Submission Instructions", and in the longer
  # chapters a data walkthrough ("The Data") holding step-by-step subsections
  # with worked example code. Copying the whole thing put a 21 KB duplicate of
  # the chapter into the Canvas assignment, which is not what an assignment is
  # for and doubled the accessibility findings for the same defects.
  #
  # So: keep the subsections that tell a student what to do and what to hand in,
  # drop the walkthrough, and let the chapter link carry the rest. On the long
  # chapters this is a 21 KB to 3 KB reduction; on the short ones almost nothing
  # is dropped, because they were already only instructions.
  keep <- character(0)
  consumed <- 0L    # end of the last TOP-LEVEL subsection already handled
  subs <- gregexpr('<section[^>]*id="[^"]*"[^>]*>', seg, perl = TRUE)[[1]]
  if (subs[1] != -1) {
    for (k in seq_along(subs)) {
      s0 <- subs[k]
      if (s0 == 1L) next                      # the wrapper section itself
      # Skip descendants. Without this the walkthrough's own step subsections
      # are each judged separately, and because a single step has no children
      # every one of them is kept, which puts the whole walkthrough back.
      if (s0 <= consumed) next
      op <- s0 + attr(subs, "match.length")[k]
      d <- 1L; e <- NA_integer_
      tk <- gregexpr("</?section\\b", substr(seg, op, nchar(seg)), perl = TRUE)[[1]]
      if (tk[1] == -1) next
      for (j in seq_along(tk)) {
        piece <- substr(seg, op + tk[j] - 1, op + tk[j])
        d <- d + if (identical(piece, "</")) -1L else 1L
        if (d == 0L) { e <- op + tk[j] + 8L; break }
      }
      if (is.na(e)) next
      sub <- substr(seg, s0, e)

      # WHAT GETS DROPPED, and why the test is structural rather than by name.
      # A step-by-step walkthrough is a subsection that itself contains
      # subsections, one per step, usually with worked example code. Everything
      # else at this level is prose telling a student what to do.
      #
      # An earlier version whitelisted headings called Objective or
      # Instructions. That broke immediately on 085_case-omitted, whose
      # subsections are "The situation", "What to do" and "A warning about the
      # direction". Chasing heading names is whack-a-mole; the structure is the
      # real signal and it does not depend on an author's word choice.
      has_children <- grepl("<section", substr(sub, 2, nchar(sub)), fixed = TRUE)
      if (!has_children) keep <- c(keep, sub)
      consumed <- e
    }
  }
  # Fail loudly rather than falling back to the whole section. A silent fallback
  # here would put the entire case study back into the assignment and look like
  # success, which is how this was wrong the first time.
  if (!length(keep))
    stop("assignment '", id, "': found no Objective or Instructions subsection ",
         "under #", anchor, " in ", chapter, ".html. The homework headings may ",
         "have been renamed. Refusing to build rather than copying the whole case.")
  seg <- paste(keep, collapse = "\n")

  # Quarto's hover anchor links are noise inside Canvas.
  seg <- gsub('<a class="anchorjs-link[^"]*"[^>]*>.*?</a>', "", seg, perl = TRUE)

  # NORMALISE HEADING LEVELS so the fragment starts at <h2>.
  #
  # The extracted subsections carry the levels they had in the chapter, where
  # they sat under the chapter's own <h1> and a section <h2>, so they are
  # usually <h3>. Dropped into a Canvas assignment, whose title Canvas renders
  # as the <h1>, that skips a level. Canvas's own course accessibility checker
  # flagged exactly this as "Page contains skipped headings" on all ten case
  # study assignments.
  #
  # The shift is computed from the fragment rather than hardcoded, because the
  # chapters do not all nest their homework sections at the same depth, and a
  # fixed h3-to-h2 rule would silently do nothing on a chapter that used h4.
  lv <- as.integer(regmatches(seg, gregexpr("(?<=<h)[1-6]", seg, perl = TRUE))[[1]])
  if (length(lv)) {
    shift <- min(lv) - 2L
    if (shift > 0L) {
      for (h in sort(unique(lv))) {
        nh <- max(2L, h - shift)
        seg <- gsub(paste0("<h", h, "(?=[ >])"), paste0("<H", nh), seg, perl = TRUE)
        seg <- gsub(paste0("</h", h, ">"), paste0("</H", nh, ">"), seg, fixed = TRUE)
      }
      # lowercase the placeholders only now, so a shifted h3 cannot be shifted
      # a second time by a later iteration of the same loop.
      seg <- gsub("<H([1-6])", "<h\\1", seg, perl = TRUE)
      seg <- gsub("</H([1-6])>", "</h\\1>", seg, perl = TRUE)
    }
  }

  # A PARAGRAPH THAT IS NOTHING BUT BOLD TEXT IS A HEADING. Canvas's checker
  # flagged seven of these on one case study as "styles might be used instead of
  # semantic markup for structure", and it is right: the numbered steps of that
  # assignment were <p><strong>1. Write Your Specification First</strong></p>,
  # which looks like a heading, is navigated to like a heading by nobody, and is
  # skipped entirely by a screen reader moving between headings.
  #
  # The test is deliberately strict: the <strong> must be the WHOLE paragraph.
  # A paragraph that merely begins with bold text is emphasis inside prose, and
  # promoting that would invent structure the author did not write. Only a
  # paragraph consisting of exactly one bold run qualifies.
  #
  # Level is h3, one below the h2 the fragment was just normalised to, so these
  # nest under their section rather than competing with it.
  seg <- gsub("<p>\\s*<strong>((?:(?!</strong>).)+)</strong>\\s*</p>",
              "<h3>\\1</h3>", seg, perl = TRUE)

  # A BARE URL IS NOT LINK TEXT. Canvas flagged "link has nondescript text" on a
  # data-file link whose visible text was the full URL. Read aloud that is a
  # character-by-character recital of a path, and in a list of links it is
  # indistinguishable from every other link to the same host.
  #
  # The filename is what the student actually needs, so the visible text becomes
  # the last path segment. The href is untouched.
  seg <- gsub('(<a[^>]*href="[^"]*/([^"/]+)"[^>]*>)https?://[^<]*(</a>)',
              "\\1\\2\\3", seg, perl = TRUE)

  # Relative hrefs and srcs must become absolute or they break in Canvas.
  base <- sub("/+$", "", tb_base)
  seg <- gsub('(<(?:a|img|source)[^>]*\\s(?:href|src)=")(?!https?:|mailto:|#|data:)([^"]+)"',
              paste0("\\1", base, "/\\2\""), seg, perl = TRUE)

  seg
}
