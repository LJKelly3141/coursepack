#' Validate course.yml and modules.yml before anything generates a cartridge
#'
#' Referential integrity (every slug and id defined and used), item-form
#' validation, textbook target resolution against the rendered textbook, the
#' todo/published rule, and the assignment-group check. Structural counts are
#' compared against `reference.yml`'s `counts:` block and are fatal when it is
#' present; absent, they are printed and the skip is reported, never hidden.
#' @param proj Course project root.
#' @param textbook_docs Override for `course.yml`'s `textbook_docs:`; `NULL` reads it.
#' @return `invisible(list(fails, skipped))`. Stops when `fails` is non-empty.
#' @examples
#' root <- init_course(tempfile("course-"), code = "ABCD 101",
#'                     title = "Demo Course", site_url = "https://example.org/demo",
#'                     timezone = "America/Chicago", git = FALSE, skills = FALSE)
#' # Prints the whole report. A fresh scaffold passes, with two checks skipped:
#' # it has no reference.yml counts block and no separate textbook.
#' res <- check_manifests(root)
#' res$fails
#' res$skipped
#' unlink(root, recursive = TRUE)
#' @export
check_manifests <- function(proj = ".", textbook_docs = NULL) {
  m <- read_manifest(proj); course <- m$course; mods <- m$mods
  pages <- m$pages; asg <- m$assignments; quiz <- m$quizzes
  fails <- character(); skipped <- character()
  fail <- function(...) fails <<- c(fails, paste0(...))
  skip <- function(...) {
    skipped <<- c(skipped, paste0(...))
    cat("  SKIPPED: ", paste0(...), "\n", sep = "")
  }
  tb_docs <- if (!is.null(textbook_docs)) textbook_docs else textbook_docs_path(course, proj)

  cat("both files parse as YAML: OK\n\n")
  # ---- 1. structure ------------------------------------------------------
  forms <- c("header", "page", "link", "assignment", "quiz")
  counts <- stats::setNames(integer(length(forms)), forms); n_items <- 0L
  for (mm in mods$modules) for (it in mm$items) {
    n_items <- n_items + 1L
    k <- forms[forms %in% names(it)]
    if (length(k) != 1L) fail("item has ", length(k), " type keys: ", paste(names(it), collapse = ","))
    else counts[k] <- counts[k] + 1L
  }
  ref <- read_reference(proj)
  cat(sprintf("modules: %d   items: %d\n", length(mods$modules), n_items))
  for (k in forms) cat(sprintf("  %-11s %2d\n", k, counts[k]))
  if (is.null(ref$counts)) skip("counts: no reference.yml counts block; structural counts not enforced")
  else {
    want <- ref$counts
    chk <- function(label, got) if (!is.null(want[[label]]) && got != want[[label]])
      fail("count mismatch, ", label, ": ", got, " vs ", want[[label]], " in reference.yml")
    chk("modules", length(mods$modules)); chk("items", n_items)
    for (k in forms) chk(k, unname(counts[k]))
  }
  # ---- 2. referential integrity -----------------------------------------
  cat("\n=== referential integrity ===\n")
  used_p <- character(); used_a <- character(); used_q <- character()
  for (mm in mods$modules) for (it in mm$items) {
    if (!is.null(it$page)) {
      used_p <- c(used_p, it$page)
      if (!it$page %in% names(pages)) fail("page slug not defined: ", it$page)
    }
    if (!is.null(it$assignment)) {
      used_a <- c(used_a, it$assignment)
      if (!it$assignment %in% names(asg)) fail("assignment id not defined: ", it$assignment)
    }
    if (!is.null(it$link) && is.null(it$chapter) && is.null(it$url))
      fail("link has neither chapter nor url: ", it$link)
    if (!is.null(it$quiz)) {
      used_q <- c(used_q, it$quiz)
      if (!it$quiz %in% names(quiz)) fail("quiz id not defined: ", it$quiz)
    }
  }
  orphan_p <- setdiff(names(pages), used_p); orphan_a <- setdiff(names(asg), used_a)
  if (length(orphan_p)) fail("orphan pages: ",       paste(orphan_p, collapse = ", "))
  if (length(orphan_a)) fail("orphan assignments: ", paste(orphan_a, collapse = ", "))
  cat(sprintf("  pages       defined=%d used=%d\n", length(pages), length(unique(used_p))))
  cat(sprintf("  assignments defined=%d used=%d\n", length(asg),   length(unique(used_a))))
  cat(sprintf("  quizzes     defined=%d used=%d\n", length(quiz),  length(unique(used_q))))
  orphan_q <- setdiff(names(quiz), used_q)
  if (length(orphan_q)) fail("orphan quizzes: ", paste(orphan_q, collapse = ", "))

  # A quiz whose QTI zip is missing produces a cartridge with a quiz item pointing
  # at nothing. Fail here rather than at build time.
  for (k in names(quiz)) {
    # A carried quiz has no QTI zip to build: its three files come out of the
    # source cartridge. Reported rather than passed over, so a quiz that lost
    # its qti: key does not read as a carried one.
    if (!is.null(quiz[[k]]$source_ref)) {
      cat(sprintf("  quiz %-10s carried from the source cartridge: %s\n",
                  k, quiz[[k]]$source_ref))
      next
    }
    # A generated quiz has no zip either: its questions come out of the bank.
    # The pooling arithmetic is checked HERE, before anything is built, because
    # every one of its refusals (a draw larger than its group, draws that do
    # not sum to the points) is a defect in the manifest rather than in the
    # build.
    if (!is.null(quiz[[k]]$bank)) {
      g <- bank_groups(quiz[[k]]$bank, proj, paste0("quiz '", k, "'"))
      cat(sprintf("  quiz %-10s bank: %d groups, %d of %d questions drawn\n", k,
                  length(g$groups), sum(g$draws),
                  sum(vapply(g$groups, function(x) length(x$qs), 0L))))
      next
    }
    z <- quiz[[k]]$qti
    if (is.null(z)) { fail("quiz '", k, "' has no qti: path"); next }
    zp <- if (startsWith(z, "/")) z else file.path(proj, z)
    if (!file.exists(zp)) fail("quiz '", k, "' QTI zip missing: ", z, "  (run: make qti)")
    else cat(sprintf("  quiz %-10s QTI zip present: %s\n", k, basename(zp)))
  }
  # ---- 2b. assignment groups --------------------------------------------
  groups <- vapply(course$assignment_groups %||% list(), function(g) as.character(g$name), "")
  dg <- course$assignment_defaults$group
  if (!is.null(dg) && !dg %in% groups)
    fail("assignment_defaults.group '", dg, "' is not a declared assignment group (", paste(groups, collapse = ", "), ")")
  for (k in names(asg)) if (!is.null(asg[[k]]$group) && !asg[[k]]$group %in% groups)
    fail("assignment '", k, "' names group '", asg[[k]]$group, "', which is not declared")
  # ---- 3. textbook targets ----------------------------------------------
  cat("\n=== textbook targets ===\n")
  refs <- collect_refs(mods)
  if (is.null(tb_docs)) skip("textbook_docs: none, so ", length(refs), " chapter/anchor targets are not checked")
  else if (!dir.exists(tb_docs)) skip("textbook docs not found at ", tb_docs)
  else {
    n_ch <- 0L; n_anc <- 0L
    for (r in refs) {
      res <- resolve_target(r$ch, r$anc, tb_docs)
      # The textbook is present (we are inside this branch because dir.exists(tb_docs)
      # is TRUE), so "unchecked" here cannot mean "no textbook to check against" - it
      # means resolve_target got a null/empty chapter for a ref that collect_refs
      # still emitted (e.g. an assignment's homework$chapter is ""). That is a
      # manifest defect, not a skipped check: fail loudly rather than silently
      # counting it as resolved.
      if (res$state == "unchecked") {
        fail("target could not be checked though the textbook is present: ", r$what,
             "  (", res$detail, ")")
        next
      }
      if (res$state == "missing-chapter") { fail("chapter file missing: ", r$ch, ".html  (", r$what, ")"); next }
      n_ch <- n_ch + 1L
      if (res$state == "missing-anchor") fail("anchor missing: ", r$ch, "#", r$anc, "  (", r$what, ")")
      else if (!is.null(r$anc))          n_anc <- n_anc + 1L
    }
    cat(sprintf("  chapter files resolved: %d\n", n_ch))
    cat(sprintf("  anchors resolved:       %d\n", n_anc))
  }
  # ---- the safety rule --------------------------------------------------
  cat("\n=== todo/published safety rule ===\n")
  pub <- character(); td <- character()
  for (a in mods$assignments) {
    if (isTRUE(a$published)) pub <- c(pub, a$id)
    if (!is.null(a$todo))    td  <- c(td,  a$id)
    if (!is.null(a$todo) && isTRUE(a$published))
      fail("VIOLATION: ", a$id, " has todo AND published: true")
  }
  cat(sprintf("  published (%d): %s\n", length(pub), paste(pub, collapse = ", ")))
  cat(sprintf("  todo, must be unpublished (%d): %s\n", length(td), paste(td, collapse = ", ")))
  # ---- verdict -----------------------------------------------------------
  cat("\n")
  if (length(fails)) {
    cat("FAILURES (", length(fails), "):\n", sep = ""); for (f in fails) cat("  ! ", f, "\n", sep = "")
    stop(length(fails), " manifest check(s) failed:\n  ", paste(fails, collapse = "\n  "), call. = FALSE)
  }
  if (length(skipped)) cat("skipped (", length(skipped), "): ", paste(skipped, collapse = "; "), "\n", sep = "")
  cat("All checks passed.\n"); version_line("check_manifests")
  invisible(list(fails = fails, skipped = skipped))
}
