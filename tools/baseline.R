#!/usr/bin/env Rscript
# Build a fixture course with the FROZEN snapshot builder and write its hashed
# staging tree. This is the only legitimate way the first expected tree is
# produced. Usage:
#   Rscript tools/baseline.R script  <fixture-course> <out-file>
#   Rscript tools/baseline.R package <fixture-course> <out-file>
# `script` copies the fixture and its sibling fake-textbook into a scratch
# directory, copies project/econ730-toolchain/scripts/{build_cartridge.R,lib/}
# beside it (the frozen script sources lib/ via PROJ), zips the sample QTI,
# and runs the script with PROJ set. That is the last legitimate use of PROJ.
# `package` builds with the working package, for deliberate regenerations.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) stop("usage: baseline.R script|package <fixture-course> <out-file>")
mode <- args[1]; fixture <- normalizePath(args[2]); out <- args[3]
# script mode needs only the gate helpers; package mode loads the whole working tree below
if (mode == "script") { source("R/utils.R"); source("R/gate.R") }

scratch <- tempfile("baseline-"); dir.create(scratch)
file.copy(fixture, scratch, recursive = TRUE)
file.copy(file.path(dirname(fixture), "fake-textbook"), scratch, recursive = TRUE)
proj <- file.path(scratch, basename(fixture))

qti_src <- file.path(dirname(fixture), "qti-sample", "quiz-sample")
dir.create(file.path(proj, "build", "qti"), recursive = TRUE)
old <- setwd(dirname(qti_src))
utils::zip(file.path(proj, "build", "qti", "quiz-sample.zip"),
           list.files(basename(qti_src), recursive = TRUE, full.names = TRUE), flags = "-q -X")
setwd(old)

# The source cartridge, zipped exactly the way copy_course() zips it: at the
# archive root, so the entry names are the hrefs its manifest declares. The
# fixture course carries three definitions out of this file, so a baseline
# built without it is a baseline of a different course.
src_cc <- file.path(dirname(fixture), "src")
dir.create(file.path(proj, "reference"), recursive = TRUE, showWarnings = FALSE)
old <- setwd(src_cc)
utils::zip(file.path(proj, "reference", "source.imscc"),
           list.files(".", recursive = TRUE), flags = "-q -X")
setwd(old)

if (mode == "script") {
  snap <- "project/econ730-toolchain/scripts"
  dir.create(file.path(proj, "scripts", "lib"), recursive = TRUE)
  file.copy(file.path(snap, "build_cartridge.R"), file.path(proj, "scripts"))
  file.copy(list.files(file.path(snap, "lib"), full.names = TRUE), file.path(proj, "scripts", "lib"))
  # PROJ only. Do NOT export TEXTBOOK_DOCS, even empty: the frozen script reads
  # Sys.getenv("TEXTBOOK_DOCS", default) at its line 507, and an empty string
  # defeats the default, which is exactly the make-export trap the gotchas record.
  status <- system2("Rscript", file.path(proj, "scripts", "build_cartridge.R"),
                    env = paste0("PROJ=", proj))
  if (status != 0) stop("the frozen builder failed; fix the fixture, not the builder")
} else if (mode == "package") {
  pkgload::load_all(".", quiet = TRUE)
  build_cartridge(proj)
} else stop("mode must be script or package")

stage <- file.path(proj, "build", "coursepack", "staging")
write_expected_tree(stage, out)
cat(length(readLines(out)), "files hashed into", out, "\n")
