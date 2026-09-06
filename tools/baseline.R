#!/usr/bin/env Rscript
# Build a fixture course with the working package and write its hashed staging
# tree. This is how the expected tree is regenerated after a deliberate output
# change; the regeneration lands in its own commit naming the changed files.
# Usage:
#   Rscript tools/baseline.R <fixture-course> <out-file>
# The fixture is copied with its sibling fake-textbook into a scratch directory,
# the sample QTI and the source cartridge are zipped beside it the way
# copy_course() zips them, and the bank is copied under questions/.
#
# The first expected tree was produced the same way by the frozen builder this
# package was ported from. That builder is no longer in the repository; the
# frozen tree it produced is the record.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("usage: baseline.R <fixture-course> <out-file>")
fixture <- normalizePath(args[1]); out <- args[2]

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

# The question bank, copied under the course's questions/ directory exactly the
# way copy_course() copies it; the build draws its bank quiz from it.
bank_src <- file.path(dirname(fixture), "bank")
dir.create(file.path(proj, "questions"), recursive = TRUE, showWarnings = FALSE)
file.copy(list.files(bank_src, full.names = TRUE), file.path(proj, "questions"), recursive = TRUE)

pkgload::load_all(".", quiet = TRUE)
build_cartridge(proj)

stage <- file.path(proj, "build", "coursepack", "staging")
write_expected_tree(stage, out)
cat(length(readLines(out)), "files hashed into", out, "\n")
