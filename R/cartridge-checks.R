# ---- self-checks before zipping -----------------------------------------
prezip_checks <- function(stage, settings_res, ann_res, p_fail) {
mh <- paste(readLines(file.path(stage, "imsmanifest.xml"), warn = FALSE), collapse = "\n")
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

if (grepl("IMS-CC-FILEBASE", mh, fixed = TRUE)) p_fail("manifest contains $IMS-CC-FILEBASE$")
# .xml as well as .html since 2026-09-02: announcement bodies travel inside a
# topic .xml, and a token there would have passed an html-only scan.
allhtml <- list.files(stage, pattern = "\\.(html|xml)$", recursive = TRUE, full.names = TRUE)
for (f in allhtml) {
  h <- paste(readLines(f, warn = FALSE), collapse = "\n")
  if (grepl("IMS-CC-FILEBASE", h, fixed = TRUE)) p_fail("IMS-CC-FILEBASE in ", basename(f))
}
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

# every idref in the manifest resolves to a declared resource
rids <- unique(regmatches(mh, gregexpr('(?<=<resource identifier=")[^"]+', mh, perl = TRUE))[[1]])
irefs <- unique(regmatches(mh, gregexpr('(?<=identifierref=")[^"]+', mh, perl = TRUE))[[1]])

# course_settings.xml can also point at a resource, and does for the course card
# image. Count those as references rather than exempting the resource id: if the
# settings file ever stops naming it, the orphan check should fire, which an
# exemption would suppress. Same reason the manifest checks are written as two
# directions rather than one.
csh <- paste(readLines(file.path(stage, "course_settings/course_settings.xml"),
                       warn = FALSE), collapse = "\n")
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
