#' Unpack a cartridge for inspection
#'
#' @param zip Path to a Common Cartridge archive.
#' @return The temporary directory containing the unpacked cartridge.
#' @export
unpack_cartridge <- function(zip) {
  d <- file.path(tempdir(), paste0("cc_", basename(tools::file_path_sans_ext(zip))))
  unlink(d, recursive = TRUE)
  dir.create(d, recursive = TRUE)
  utils::unzip(zip, exdir = d)
  d
}

#' Match a divergence to its declaration
#'
#' @param d A reported divergence.
#' @param declared A list of declarations with `match` and `why` fields.
#' @return The reason for the first substring match, or `NA_character_`.
#' @export
divergence_declared <- function(d, declared) {
  if (is.null(declared) || !length(declared)) return(NA_character_)
  hit <- vapply(declared, function(x) grepl(as.character(x$match), d, fixed = TRUE), logical(1))
  if (any(hit)) as.character(declared[[which(hit)[1]]]$why) else NA_character_
}

#' Diff a generated cartridge against a reference export
#'
#' Compares cartridge structure, never opaque identifiers. The reference export
#' and deliberate divergences are declared in `reference.yml` under `proj`.
#'
#' @param proj Course project root.
#' @param generated Generated cartridge path. When `NULL`, use the newest
#'   `.imscc` file under `build/coursepack`.
#' @return Invisibly, a list of all, accounted-for, and unexpected divergences.
#' @export
diff_against_reference <- function(proj = ".", generated = NULL) {
  cfg <- read_reference(proj)
  empty <- list(divergences = character(0), accounted = character(0),
                unexpected = character(0))
  if (is.null(cfg) || is.null(cfg$export) || !nzchar(as.character(cfg$export))) {
    cat("SKIPPED: no reference export declared\n")
    version_line("diff_against_reference")
    return(invisible(empty))
  }

  ref <- proj_path(proj, as.character(cfg$export))
  gen <- generated
  if (is.null(gen)) {
    f <- sort(list.files(file.path(proj, "build", "coursepack"), "\\.imscc$", full.names = TRUE))
    if (!length(f)) stop("no generated cartridge found under build/coursepack; run build_cartridge() first", call. = FALSE)
    gen <- utils::tail(f, 1)
  }

  root_r <- unpack_cartridge(ref)
  root_g <- unpack_cartridge(gen)

  ns_strip <- function(x) {
    xml2::xml_ns_strip(x)
    x
  }
  load_mm <- function(root) {
    f <- file.path(root, "course_settings", "module_meta.xml")
    if (!file.exists(f)) return(NULL)
    ns_strip(xml2::read_xml(f))
  }

  cat("reference: ", basename(ref), "\n", sep = "")
  cat("generated: ", basename(gen), "\n\n", sep = "")

  divergences <- character()
  note <- function(...) divergences <<- c(divergences, paste0(...))

  mm_r <- load_mm(root_r); mm_g <- load_mm(root_g)
  mods_r <- xml2::xml_find_all(mm_r, "//module"); mods_g <- xml2::xml_find_all(mm_g, "//module")
  cat(sprintf("modules: reference=%d generated=%d\n", length(mods_r), length(mods_g)))
  if (length(mods_r) != length(mods_g))
    note("modules: ", length(mods_r), " -> ", length(mods_g))

  tt <- function(n, p) xml2::xml_text(xml2::xml_find_first(n, p))
  for (i in seq_len(min(length(mods_r), length(mods_g)))) {
    a <- mods_r[[i]]; b <- mods_g[[i]]
    for (fld in c("title", "workflow_state", "position", "require_sequential_progress")) {
      va <- tt(a, fld); vb <- tt(b, fld)
      if (!identical(va, vb)) note(sprintf("module %d %s: %s -> %s", i, fld, va, vb))
    }
  }

  items <- function(mm) {
    n <- xml2::xml_find_all(mm, "//module/items/item")
    data.frame(
      title = vapply(n, tt, "", "title"),
      ctype = vapply(n, tt, "", "content_type"),
      indent = vapply(n, tt, "", "indent"),
      newtab = vapply(n, tt, "", "new_tab"),
      url = vapply(n, function(x) { v <- tt(x, "url"); if (is.na(v)) "" else v }, ""),
      stringsAsFactors = FALSE
    )
  }
  ir <- items(mm_r); ig <- items(mm_g)
  cat(sprintf("items:   reference=%d generated=%d\n", nrow(ir), nrow(ig)))
  if (nrow(ir) != nrow(ig)) note("items: ", nrow(ir), " -> ", nrow(ig))

  cat("\nitem types:\n")
  tr <- table(ir$ctype); tg <- table(ig$ctype)
  for (k in union(names(tr), names(tg))) {
    a <- if (k %in% names(tr)) tr[[k]] else 0L
    b <- if (k %in% names(tg)) tg[[k]] else 0L
    cat(sprintf("  %-24s %3d -> %3d %s\n", k, a, b, if (a == b) "" else "  <-- differs"))
    if (a != b) note(k, ": ", a, " -> ", b)
  }

  key <- function(d) paste(d$ctype, d$title, sep = "|")
  only_r <- setdiff(key(ir), key(ig)); only_g <- setdiff(key(ig), key(ir))
  if (length(only_r)) { cat("\nin reference only:\n"); for (k in only_r) cat("  - ", k, "\n", sep = "") }
  if (length(only_g)) { cat("\nin generated only:\n"); for (k in only_g) cat("  + ", k, "\n", sep = "") }
  for (k in only_r) note("item dropped: ", k)
  for (k in only_g) note("item added: ", k)

  common <- intersect(key(ir), key(ig))
  mism <- 0
  for (k in common) {
    a <- ir[key(ir) == k, ][1, ]; b <- ig[key(ig) == k, ][1, ]
    for (fld in c("indent", "newtab", "url")) {
      if (!identical(a[[fld]], b[[fld]])) {
        note(sprintf("item %s %s: %s -> %s", k, fld, a[[fld]], b[[fld]])); mism <- mism + 1
      }
    }
  }
  cat(sprintf("\nshared items=%d  field mismatches=%d\n", length(common), mism))

  restab <- function(root) {
    m <- ns_strip(xml2::read_xml(file.path(root, "imsmanifest.xml")))
    table(xml2::xml_attr(xml2::xml_find_all(m, "//resources/resource"), "type"))
  }
  rr <- restab(root_r); rg <- restab(root_g)
  cat("\nresource types:\n")
  for (k in union(names(rr), names(rg))) {
    a <- if (k %in% names(rr)) rr[[k]] else 0L
    b <- if (k %in% names(rg)) rg[[k]] else 0L
    cat(sprintf("  %-62s %3d -> %3d %s\n", k, a, b, if (a == b) "" else "  <-- differs"))
    if (a != b) note(k, ": ", a, " -> ", b)
  }

  asgs <- function(root) {
    fs <- list.files(root, "assignment_settings.xml", recursive = TRUE, full.names = TRUE)
    do.call(rbind, lapply(fs, function(f) {
      x <- ns_strip(xml2::read_xml(f))
      data.frame(title = tt(x, "title"), state = tt(x, "workflow_state"),
                 pts = tt(x, "points_possible"),
                 due = { v <- tt(x, "due_at"); if (is.na(v)) "" else v },
                 stringsAsFactors = FALSE)
    }))
  }
  ar <- asgs(root_r); ag <- asgs(root_g)
  ar <- ar[order(ar$title), ]; ag <- ag[order(ag$title), ]
  cat(sprintf("\nassignments: reference=%d generated=%d\n", nrow(ar), nrow(ag)))
  cat(sprintf("  %-22s %-24s %s\n", "title", "reference", "generated"))
  for (t in union(ar$title, ag$title)) {
    a <- ar[ar$title == t, ]; b <- ag[ag$title == t, ]
    fa <- if (nrow(a)) sprintf("%s %s due=%s", a$state[1], a$pts[1], ifelse(nzchar(a$due[1]), substr(a$due[1], 1, 10), "-")) else "(absent)"
    fb <- if (nrow(b)) sprintf("%s %s due=%s", b$state[1], b$pts[1], ifelse(nzchar(b$due[1]), substr(b$due[1], 1, 10), "-")) else "(absent)"
    same <- nrow(a) && nrow(b) &&
      identical(a$state[1], b$state[1]) && identical(a$pts[1], b$pts[1])
    cat(sprintf("  %-22s %-26s %-26s%s\n", t, fa, fb, if (same) "" else "  <-- differs"))
    if (nrow(a) && nrow(b)) {
      if (!identical(a$state[1], b$state[1]))
        note("assignment ", t, " state: ", a$state[1], " -> ", b$state[1])
      if (!identical(a$pts[1], b$pts[1]))
        note("assignment ", t, " points: ", a$pts[1], " -> ", b$pts[1])
    }
  }

  reasons <- vapply(divergences, divergence_declared, "", declared = cfg$divergences)
  unexpected <- divergences[is.na(reasons)]

  cat("\n", strrep("=", 72), "\n", sep = "")
  if (!length(divergences)) {
    cat("No divergence from the reference.\n")
    version_line("diff_against_reference")
    return(invisible(empty))
  }

  accounted <- divergences[!is.na(reasons)]
  if (length(accounted)) {
    cat("ACCOUNTED-FOR divergences:\n")
    for (i in which(!is.na(reasons)))
      cat("  ok  ", divergences[i], "\n         ", reasons[i], "\n", sep = "")
  }
  if (length(unexpected)) {
    cat("\nUNEXPECTED divergences -- these are generator bugs:\n")
    for (d in unexpected) cat("  !!  ", d, "\n", sep = "")
    version_line("diff_against_reference")
    stop("UNEXPECTED divergences", call. = FALSE)
  }
  cat("\nAll ", length(divergences), " divergences are accounted for.\n", sep = "")
  version_line("diff_against_reference")
  invisible(list(divergences = divergences, accounted = accounted,
                 unexpected = unexpected))
}
