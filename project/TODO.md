# coursepack TODO

## For 1.3.0 (open as of 2026-10-06, after 1.2.8.1)

Already shipped in 1.2.7 to 1.2.8.1: the Gemma privacy sweep inside `anonymize()`, `anon/` released only after it passes (hidden `.anon_build/`), the progress file, the log, the skill rules, image-only transcription (photo never placed in `anon/`).

1. Help-page examples need `sweep = FALSE` (anonymize, relink, anon_forget). This is why GitHub's automatic test run fails on 1.2.8 and 1.2.8.1: the examples run the sweep and GitHub's machine has no LM Studio.
2. Automatic redaction of sweep findings. Logan originally chose "flag and redact"; what shipped is flag-only, with every finding waiting for a noise/real decision in `anon_review.csv`.
3. Course URLs in `anon_keep.txt`. On Case Study 6 the dataset's public GitHub address was redacted as a profile link (PROFILE 5).
4. Canvas filenames with text after the extension (e.g. `spec.md Case #5`) still stop the run as an unsupported type.
5. README and SETUP do not yet describe the sweep, transcription, LM Studio or the `curl` package.
6. Stale plan file `project/plans/2026-10-05-local-privacy-review.md` (uncommitted) describes the rejected separate-function design; delete or rewrite.
7. Untested: personal details woven into a student's argument, and planted image content (faces, name tags) for the sweep.

## Workbook submissions (added 2026-11-08)

8. Glued names are a known possible leak. A student name run into another word (a workbook defined name like `PatQuillRange`, or `PatQuill` in text) is not redacted. Logan ruled on 2026-11-08 that, for workbook and csv submissions only, the leftover check reports these instead of stopping the run, so such a name can reach the grader. Documents still stop the run. Fix in the future: redact glued names at the source (for example, treat a capital letter as a word break) so the check can go back to stopping the run.
9. Not yet tried live: whether Canvas's submission-comment upload accepts a Word (`.docx`) feedback file answering an `.xlsx` or `.csv` submission (workbook-only students). Checked 2026-11-08 against Canvas source (instructure/canvas-lms, `app/models/abstract_assignment.rb`, `infer_comment_context_from_filename`): Canvas matches a file by its first two all-digit tokens (user id, then submitted attachment id) and does not compare the extension, so `prefix_12345_678901_partb.docx` should attach. No extension filter was found, but none was ruled out either. Confirm with one student before relying on it.
10. Checked 2026-11-08: two real Excel-saved newer-type charts (box and whisker; histogram, from LibreOffice's test data) are described in full, with Excel's hidden `_xlchart` names resolved to their cell ranges and nothing left undescribed.
