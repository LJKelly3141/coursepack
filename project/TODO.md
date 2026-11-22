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

## tidyxl crashes (added 2026-11-10, after 1.3.3)

11. ECON 740 part-b-1: S10's third file still fails. tidyxl segfaults on it in the child process; workbook_faults() finds none of the seven known patterns. Cause unknown; Logan to decide whether S10 re-saves it.
12. A child-process crash still prints one console line ("sh: line 1: NNN Segmentation fault: 11" plus the temporary command). No student data, only a temp path. The subshell redirect in xlsx_cells_isolated() did not silence it.
13. tidyxl's styles reader (xlsxstyles.cpp) and shared-strings reader (xlsxbook.cpp) have unchecked pointers and indexes not yet fuzzed: cellXfs missing, numFmt without numFmtId, cellStyle without xfId, font/fill/border ids out of range, sharedStrings uniqueCount wrong. Likely home of S10's fault.

## Module audits (added 2026-11-22, after 1.3.5; reported by the ECON 740 session testing Module 5)

14. Title matching: `audit_course(modules = "Module 5")` stops with "names modules not in modules.yml"; only the full title "Module 5: Graphical integrity" works. Asked for: prefix match on "Module N", stopping when it matches more than one module. `select_modules()` is shared with `build_cartridge()`, which also matches exactly, so a change reaches both; Logan to decide.
15. Pages missing from scope, and the report did not show it. The run declared 14 pages and left out (a) `content/pages/module-05-part-b.html`, reached only through assignment part-b-5's description iframe, and (b) three slide decks the module's video pages link to (`slides/tell-graphical-integrity.html`, `slides/tell-animation-integrity.html`, `slides/module-05-intro.html`), probably linked by absolute `{site}` URL, which `page_links()` drops. Measured vs declared passed 14/14 because both counts come from `scope_target()`, so a page missing from the scope cannot show as a shortfall. Fix both gaps and give the scope an independent check.
16. Stale cartridges: an old `build/coursepack/econ-740-2026-10-25.imscc` with no Module 5 stopped the run (`cartridge_scope_files()`); worked around with `cartridge_dirs` pointing at a folder holding only the current cartridge. Recommended: skip a cartridge that lacks the module and list it in the report; stop only when no cartridge has it.
