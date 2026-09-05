# ---- quizzes -------------------------------------------------------------
#
# Canvas packages a Classic quiz as THREE files, confirmed against a real export
# containing 36 of them (see log/decisions/007-quizzes-in-the-cartridge.md):
#
#   <qid>/assessment_qti.xml            a CC-profile stub with an EMPTY section
#   <qid>/assessment_meta.xml           Canvas quiz settings
#   non_cc_assessments/<qid>.xml.qti    the real QTI, with all the questions
#
# and TWO manifest resources: the assessment (type imsqti_xmlv1p2/imscc_xmlv1p1/
# assessment, pointing at the stub) with a <dependency> on the meta resource,
# which in turn declares BOTH the meta file and the non_cc_assessments file.
#
# The stub really is empty. The questions live only in non_cc_assessments/.
# Do not "fix" the stub by populating its section.

embed_quiz <- function(k, q, ids, ag_id, stage, proj) {
quiz_res <- ids$quiz_res
quiz_meta <- ids$quiz_meta
quiz_aid <- ids$quiz_aid
  zipf <- if (grepl("^/", q$qti)) q$qti else file.path(proj, q$qti)
  if (!file.exists(zipf))
    stop("quiz '", k, "' points at a QTI zip that does not exist: ", zipf,
         "\n  run: make qti QUIZ=<definition>")

  tmp <- file.path(tempdir(), paste0("qti_", k)); unlink(tmp, recursive = TRUE)
  dir.create(tmp, recursive = TRUE)
  utils::unzip(zipf, exdir = tmp)

  metaf <- list.files(tmp, "assessment_meta\\.xml$", recursive = TRUE, full.names = TRUE)
  if (length(metaf) != 1) stop("quiz '", k, "': expected exactly one assessment_meta.xml, found ", length(metaf))
  assf <- setdiff(list.files(dirname(metaf), "\\.xml$", full.names = TRUE), metaf)
  if (length(assf) != 1) stop("quiz '", k, "': expected exactly one assessment XML, found ", length(assf))

  meta <- paste(readLines(metaf, warn = FALSE), collapse = "\n")
  ass  <- paste(readLines(assf,  warn = FALSE), collapse = "\n")

  # R/exams stamps a fresh random number into every build, so ids must be
  # rewritten or no two cartridge builds are comparable.
  #
  # It uses THREE independent random numbers, not one. The assessment ident, the
  # meta's <quiz identifier>, and the inner <assignment identifier> all differ.
  # Substituting only the assessment ident silently leaves the meta pointing at
  # a quiz that does not exist. Confirmed against the reference: the meta's quiz
  # identifier must equal the assessment resource id.
  grab <- function(txt, pat) {
    m <- regmatches(txt, regexpr(pat, txt, perl = TRUE))
    if (!length(m)) "" else sub(pat, "\\1", m, perl = TRUE)
  }
  old_ident <- grab(ass,  '<assessment ident="([^"]+)"')
  old_quiz  <- grab(meta, '<quiz identifier="([^"]+)"')
  if (!nzchar(old_ident)) stop("quiz '", k, "': no assessment ident found")
  if (!nzchar(old_quiz))  stop("quiz '", k, "': no <quiz identifier> in assessment_meta.xml")

  # R/exams uses TWO independent random suffixes on the same base name, and the
  # meta file references both. Substituting one leaves the other dangling, so
  # every <base>_<digits> token has to be rewritten. Canvas collapses these to a
  # single id: in the reference, the assessment ident and the meta's quiz
  # identifier hold the same value.
  #
  # This must be a PREFIX substitution, not a whole-token one.
  #
  # R/exams names each question by extending the base id:
  #   <base>_<A>_section_1_item_01_num ... _item_20_num
  # Matching whole tokens ("[A-Za-z0-9._-]+_[0-9]+") swallows the
  # `_section_1_item_01` part too, collapsing all 20 idents into one value.
  # Canvas then treats them as the same question and keeps ONE, silently. The
  # quiz still appears, still opens, and has lost 19 of 20 variants. Caught only
  # by a round-trip diff.
  #
  # So: find every `<base>_<digits>` PREFIX and replace just that, leaving
  # whatever follows intact. Located by literal search, because course slugs
  # contain regex metacharacters and hand-escaping them broke this earlier.
  base <- sub("_[0-9]+$", "", old_ident)
  prefixes <- function(txt) {
    hits <- gregexpr(base, txt, fixed = TRUE)[[1]]
    if (identical(as.integer(hits), -1L)) return(character())
    out <- character()
    for (p in hits) {
      after <- substr(txt, p + nchar(base), p + nchar(base) + 24)
      m <- regmatches(after, regexpr("^_[0-9]+", after))
      if (length(m)) out <- c(out, paste0(base, m))
    }
    unique(out)
  }
  ids <- unique(c(prefixes(ass), prefixes(meta)))
  for (id in ids) {
    for (pfx in c("AID_", "GID_")) {          # prefixed forms first
      tgt <- if (pfx == "AID_") quiz_aid[[k]] else ag_id
      ass  <- gsub(paste0(pfx, id), tgt, ass,  fixed = TRUE)
      meta <- gsub(paste0(pfx, id), tgt, meta, fixed = TRUE)
    }
    ass  <- gsub(id, quiz_res[[k]], ass,  fixed = TRUE)
    meta <- gsub(id, quiz_res[[k]], meta, fixed = TRUE)
  }

  # Put the quiz in the same assignment group as the homework, rather than
  # letting it fall into Canvas's default group.
  meta <- gsub("<assignment_group_identifierref>[^<]*</assignment_group_identifierref>",
               paste0("<assignment_group_identifierref>", ag_id,
                      "</assignment_group_identifierref>"), meta)

  # No <base>_<digits> token may survive, or the rewrite half-applied and the
  # quiz imports pointing at an id that does not exist. Scoped to the base name:
  # R/exams' per-question `_num_RESPONSE_<n>` ids are internal and stay as they
  # are.
  leftover <- unique(c(prefixes(ass), prefixes(meta)))
  if (length(leftover))
    stop("quiz '", k, "': identifier rewrite incomplete, still present: ",
         paste(leftover, collapse = ", "))

  # Per-question idents must stay DISTINCT. Collapsing them is a silent data
  # loss: Canvas keeps one question and discards the rest without an error.
  n_item <- length(regmatches(ass, gregexpr("<item ident=", ass))[[1]])
  n_uniq <- length(unique(regmatches(ass, gregexpr('<item ident="[^"]*"', ass))[[1]]))
  if (n_item != n_uniq)
    stop("quiz '", k, "': ", n_item, " questions collapsed to ", n_uniq,
         " distinct idents. Canvas would silently keep ", n_uniq, ".")
  cat(sprintf("  quiz %-10s %d questions, %d distinct idents\n", k, n_item, n_uniq))

  # Title: modules.yml wins over R/exams' file-derived name.
  if (!is.null(q$title)) {
    ass  <- sub('(<assessment ident="[^"]+" title=")[^"]*(")', paste0("\\1", xesc(q$title), "\\2"), ass)
    meta <- gsub("<title>[^<]*</title>", paste0("<title>", xesc(q$title), "</title>"), meta)
  }
  # Publish state.
  meta <- sub("<available>[^<]*</available>",
              paste0("<available>", tolower(as.character(isTRUE(q$published))), "</available>"), meta)

  # Canvas's copies carry no DOCTYPE; R/exams emits one. Match the reference.
  ass <- sub("(?s)<!DOCTYPE[^>]*>\\s*", "", ass, perl = TRUE)

  writef(file.path(stage, "non_cc_assessments", paste0(quiz_res[[k]], ".xml.qti")), ass)
  writef(file.path(stage, quiz_res[[k]], "assessment_meta.xml"), meta)
  writef(file.path(stage, quiz_res[[k]], "assessment_qti.xml"), paste0(
'<?xml version="1.0" encoding="UTF-8"?>\n',
'<questestinterop xmlns="http://www.imsglobal.org/xsd/ims_qtiasiv1p2" ', XSI,
' xsi:schemaLocation="http://www.imsglobal.org/xsd/ims_qtiasiv1p2',
' http://www.imsglobal.org/profile/cc/ccv1p1/ccv1p1_qtiasiv1p2p1_v1p0.xsd">\n',
'  <assessment ident="', quiz_res[[k]], '" title="', xesc(q$title), '">\n',
'    <qtimetadata>\n',
'      <qtimetadatafield>\n        <fieldlabel>cc_profile</fieldlabel>\n',
'        <fieldentry>cc.exam.v0p1</fieldentry>\n      </qtimetadatafield>\n',
'      <qtimetadatafield>\n        <fieldlabel>qmd_assessmenttype</fieldlabel>\n',
'        <fieldentry>Examination</fieldentry>\n      </qtimetadatafield>\n',
'      <qtimetadatafield>\n        <fieldlabel>qmd_scoretype</fieldlabel>\n',
'        <fieldentry>Percentage</fieldentry>\n      </qtimetadatafield>\n',
'      <qtimetadatafield>\n        <fieldlabel>cc_maxattempts</fieldlabel>\n',
'        <fieldentry>unlimited</fieldentry>\n      </qtimetadatafield>\n',
'    </qtimetadata>\n',
'    <section ident="root_section">\n    </section>\n',
'  </assessment>\n</questestinterop>'))
}
