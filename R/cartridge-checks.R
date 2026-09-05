# ---- self-checks before zipping -----------------------------------------

# The text of one <resource> block, found by its identifier, or "" when the
# manifest holds no such resource. Located with fixed matching so an identifier
# is never read as a pattern.
resource_block <- function(mh, rid) {
  at <- regexpr(paste0('<resource identifier="', rid, '"'), mh, fixed = TRUE)
  if (at < 0) return("")
  blk <- substring(mh, at)
  end <- regexpr("</resource>", blk, fixed = TRUE)
  if (end < 0) blk else substr(blk, 1, end - 1)
}

# Text of a staged file, or "" when it is not there. A check that reads a file
# the tree is missing must record the miss and carry on; stopping here would
# hide every problem after it.
staged_text <- function(stage, rel) {
  f <- file.path(stage, rel)
  if (!file.exists(f)) return("")
  paste(readLines(f, warn = FALSE), collapse = "\n")
}

prezip_checks <- function(stage, settings_res, ann_res, p_fail, carried_ids = character()) {
mh <- paste(readLines(file.path(stage, "imsmanifest.xml"), warn = FALSE), collapse = "\n")

# The manifest header, everything ahead of <organizations>, carries the four
# tokens Canvas uses to recognise the package as Common Cartridge 1.1.0 with
# LOM metadata. Drop any of them in a future edit and the import does not
# report an error; it reads the cartridge as something else, or not at all.
# Checked against the header text rather than the whole file so a token that
# only appears further down cannot stand in for a missing one.
hdr_cut <- regexpr("<organizations", mh, fixed = TRUE)
hdr <- if (hdr_cut > 0) substr(mh, 1, hdr_cut - 1) else mh
for (tok in c("xmlns:lomimscc", "xsi:schemaLocation", "<lomimscc:lom>",
              "<schemaversion>1.1.0</schemaversion>"))
  if (!grepl(tok, hdr, fixed = TRUE)) p_fail("manifest header is missing ", tok)

declared <- unique(regmatches(mh, gregexpr('(?<=<file href=")[^"]+', mh, perl = TRUE))[[1]])
for (f in declared)
  if (!file.exists(file.path(stage, f))) p_fail("manifest declares a missing file: ", f)
# imsmanifest.xml is never declared in itself. Confirmed against the reference
# export, which declares it 0 times. Everything else on disk must be declared,
# or it ships as dead weight Canvas will not read.
on_disk <- setdiff(list.files(stage, recursive = TRUE), c(declared, "imsmanifest.xml"))
for (f in on_disk) p_fail("file on disk not declared in manifest: ", f)
cat(sprintf("  files declared=%d  on disk=%d  undeclared=%d\n",
            length(declared), length(list.files(stage, recursive = TRUE)), length(on_disk)))

# course_settings/canvas_export.txt is the marker that tells Canvas this package
# came out of Canvas and that the course_settings files are worth reading. It is
# the settings resource's own href, so both halves are checked: the file on disk
# and the declaration inside that resource. Either half alone imports quietly and
# leaves the course settings behind.
marker <- "course_settings/canvas_export.txt"
if (!file.exists(file.path(stage, marker))) p_fail("the staged tree is missing ", marker)
if (!grepl(paste0('href="', marker, '"'), resource_block(mh, settings_res), fixed = TRUE))
  p_fail("the settings resource does not declare ", marker)

if (grepl("IMS-CC-FILEBASE", mh, fixed = TRUE)) p_fail("manifest contains $IMS-CC-FILEBASE$")
# .xml as well as .html since 2026-09-02: announcement bodies travel inside a
# topic .xml, and a token there would have passed an html-only scan. .xml.qti
# since decision D15, because that is where a quiz's questions live and the one
# admitted token now lives with them.
#
# DECISION D15, AND WHY IT IS A NARROW EXCEPTION RATHER THAN A RELAXATION.
# $IMS-CC-FILEBASE$ is how a cartridge says "a file inside this course", and
# the rule against it exists because a page that embeds a file makes the file
# public on the site the pages mirror. A quiz figure cannot be published that
# way: an exam question's picture would give the question away. So a figure is
# the one thing that must travel INSIDE the cartridge, and the token is the
# only way to point at it.
#
# The exception is therefore scoped three ways, and each way is checked:
#   1. the token may appear only in a quiz's two QTI files,
#   2. only in the form $IMS-CC-FILEBASE$/quiz_images/<file>, and
#   3. every <file> named must be staged under web_resources/quiz_images/ AND
#      declared in the manifest.
# Anywhere else, in any other form, or pointing at a picture that is not there,
# it is still a failure. A token pointing at an absent file is worse than no
# figure: Canvas renders a broken image inside a graded question.
quiz_qti <- "^non_cc_assessments/[^/]+\\.xml\\.qti$|^[^/]+/assessment_qti\\.xml$"
figure_token <- "^\\$IMS-CC-FILEBASE\\$/quiz_images/[^/]+$"
allhtml <- list.files(stage, pattern = "\\.(html|xml|qti)$", recursive = TRUE)
n_fig <- 0L
for (rel in allhtml) {
  h <- staged_text(stage, rel)
  if (!grepl("IMS-CC-FILEBASE", h, fixed = TRUE)) next
  if (!grepl(quiz_qti, rel)) { p_fail("IMS-CC-FILEBASE in ", basename(rel)); next }
  for (tok in unique(regmatches(h, gregexpr('\\$IMS-CC-FILEBASE\\$[^"\'<> ]*', h))[[1]])) {
    if (!grepl(figure_token, tok)) {
      p_fail("IMS-CC-FILEBASE in ", basename(rel), " is not a quiz figure: ", tok)
      next
    }
    href <- sub("^\\$IMS-CC-FILEBASE\\$/", "web_resources/", tok)
    n_fig <- n_fig + 1L
    if (!file.exists(file.path(stage, href)))
      p_fail("quiz figure named in ", basename(rel), " is not staged: ", href)
    else if (!href %in% declared)
      p_fail("quiz figure named in ", basename(rel), " is not declared in the manifest: ", href)
  }
}
cat(sprintf("  quiz figure references: %d\n", n_fig))
# Answer-key containment. A filename check was too blunt: Canvas's own quiz files
# are legitimately called assessment_meta.xml and assessment_qti.xml. Check for
# what actually must not be here instead.
#
# Note what IS allowed and why: quiz QTI contains answer keys, deliberately,
# because Canvas needs them to grade. That is safe because the cartridge is
# imported into Canvas and never rendered into docs/. The containment rule is
# about the PUBLIC SITE, not about the cartridge. See the package README.
canary <- LEAK_CANARY
srcs <- list.files(stage, pattern = "\\.(Rmd|qmd|R|Rnw)$", recursive = TRUE, ignore.case = TRUE)
for (f in srcs) p_fail("assessment SOURCE file leaked into cartridge: ", f)
# Read every file as BYTES, not as lines. readLines() on the course card PNG
# warns "input string is invalid in this locale" and returns mangled text, so a
# canary sitting in a binary file could have been missed. Bytes have no locale
# and this searches image and text files identically.
canary_hits <- 0L
for (f in list.files(stage, recursive = TRUE, full.names = TRUE)) {
  bytes <- tryCatch(readBin(f, "raw", n = file.info(f)$size), error = function(e) raw())
  if (length(bytes) && length(grepRaw(canary, bytes, fixed = TRUE))) {
    canary_hits <- canary_hits + 1L
    p_fail("leak canary found in ", basename(f))
  }
}
cat(sprintf("  answer-key containment: %d source files, %d canary hits\n",
            length(srcs), canary_hits))

# A carried resource id that the generator also minted would be declared twice.
# Canvas keeps one of the two and drops the other's files without saying which,
# so the cartridge imports looking complete and is not. Read from the manifest
# rather than from the carry's own bookkeeping, because the collision is
# between what the two writers put on the page.
all_rids <- regmatches(mh, gregexpr('(?<=<resource identifier=")[^"]+', mh, perl = TRUE))[[1]]
for (id in intersect(carried_ids, unique(all_rids[duplicated(all_rids)])))
  p_fail("carried resource ", id, " declared twice")

# every idref in the manifest resolves to a declared resource
rids <- unique(all_rids)
irefs <- unique(regmatches(mh, gregexpr('(?<=identifierref=")[^"]+', mh, perl = TRUE))[[1]])

# course_settings.xml can also point at a resource, and does for the course card
# image. Count those as references rather than exempting the resource id: if the
# settings file ever stops naming it, the orphan check should fire, which an
# exemption would suppress. Same reason the manifest checks are written as two
# directions rather than one.
csh <- staged_text(stage, "course_settings/course_settings.xml")
irefs <- unique(c(irefs, regmatches(csh,
  gregexpr('(?<=<image_identifier_ref>)[^<]+', csh, perl = TRUE))[[1]]))

dangling <- setdiff(irefs, rids)
if (length(dangling)) p_fail("dangling identifierref: ", paste(dangling, collapse = ", "))
# Announcement topics are roots, like course_settings: nothing in the manifest
# points at them, verified in the round-trip export. Admitted by their declared
# ids, not by resource type, so an imsdt resource the YAML did not declare
# still reads as an orphan.
orph <- setdiff(rids, c(irefs, settings_res, unname(ann_res)))
if (length(orph)) p_fail("orphan resource: ", paste(orph, collapse = ", "))
cat(sprintf("  resources=%d  idrefs=%d  dangling=%d  orphans=%d\n",
            length(rids), length(irefs), length(dangling), length(orph)))

# XML well-formedness for everything we wrote
xmls <- list.files(stage, pattern = "\\.xml$", recursive = TRUE, full.names = TRUE)
badxml <- 0
for (f in xmls) if (inherits(try(xml2::read_xml(f), silent = TRUE), "try-error")) {
  p_fail("malformed XML: ", f); badxml <- badxml + 1
}
cat(sprintf("  xml files=%d  malformed=%d\n", length(xmls), badxml))

}

# ---- checks that only apply to carried bytes ------------------------------

# A carried settings file names its assignment group by the id the SOURCE
# course minted. This course declares its own groups, and a carried file
# pointing at a group this manifest does not declare imports into Canvas's
# default group without reporting anything: the assignment appears, the weight
# is wrong, and the only symptom is a grade book that does not add up.
#
# Read from the STAGED file, not from the source archive, because what ships is
# what matters and the two could differ if anything ever rewrites them.
check_carried <- function(stage, carried, groups, p_fail) {
  if (!length(carried$files)) return(invisible(NULL))
  settings <- carried$files[basename(carried$files) %in%
                            c("assignment_settings.xml", "assessment_meta.xml")]
  n <- 0L
  for (f in settings) {
    txt <- staged_text(stage, f)
    ids <- unique(regmatches(txt, gregexpr(
      "(?<=<assignment_group_identifierref>)[^<]+", txt, perl = TRUE))[[1]])
    n <- n + length(ids)
    for (id in ids) if (!id %in% groups)
      p_fail("carried ", f, " references assignment group ", id,
             ", which course.yml does not declare")
  }
  cat(sprintf("  carried: %d resources, %d files, %d group references\n",
              length(carried$carried), length(carried$files), n))
  invisible(NULL)
}
