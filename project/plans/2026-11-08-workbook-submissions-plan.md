# Workbook Submissions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `anonymize()` reads `.xlsx`, `.xlsm` and `.csv` submissions (each chart as a full text description, formulas beside cells) through the same redaction and review as documents, refuses `.xls`, can skip named types, and `relink()` answers a workbook-only student with markdown.

**Architecture:** A workbook becomes `file<k>.md` + `file<k>_media/` like any document. It is read as a zip of XML only (`tidyxl` for cells and formulas, `xml2` for charts, pivots, drawings, comments); nothing opens or runs it. The markdown it produces then goes through the existing text chain, leftover check, image scan and sweep unchanged.

**Tech Stack:** R, `tidyxl` (new Import), `xml2`, `utils::unzip`, testthat 3.

**Spec:** `project/plans/2026-11-08-workbook-submissions-design.md` (revised after the spike: no chart picture, no Excel).

## Global Constraints

- Messages name a code, a file position or a count; never a student, id or original filename (`R/anon-grading.R:9`).
- Nothing opens, runs or executes the workbook. No Excel, no AppleScript, no LibreOffice.
- `vbaProject.bin`, external-link targets, connection strings, `docProps/core.xml` creator/lastModifiedBy, `docProps/app.xml` company, `xl/persons/*` and comment authors are never written to `anon/`.
- A chart, or a chart element the reader does not interpret, is never dropped silently: unknown elements are listed as `not described: <element>`.
- A sheet or `.csv` over 4,000 cells (used range) is raw data: ignored, with one "Not read" line saying so (Logan, 2026-11-08). No other cutting.
- `.xls` is never read. Stop message names code and position and says: re-save as `.xlsx`, or pass `"xls"` in `skip_types`.
- Fixtures are invented (reuse the names in `tests/testthat/helper-anon.R`: Pat Quill, Morgan Rivera "Mo", Pat Stone). Never student files. Never touch `/Volumes/SSD8TB/Sync/UWRF/Teaching/data-visulization`.
- **Logan's rules for this repo:** do not install `tidyxl` (or anything) until Logan says so for that action; do not bump `Version`; **every "Commit" step means: report the change and wait for Logan to say commit.** No AI attribution in commit messages. No em-dashes in roxygen, NEWS, or any user-facing message.
- Test commands: `Rscript -e 'testthat::test_local(filter = "<name>")'`; whole suite `Rscript -e 'testthat::test_local()'`.

## Review Focus

1. A sheet named after a student ("Pat Quill data") appears in formulas, chart series ranges and defined names. Expected: redacted to the same `[name] data` everywhere, so the grader can still follow which range a chart plots. Test in Task 7.
2. A name split across rich-text runs in one cell (`<r><t>Pat </t></r><r><t>Quill</t></r>`). Expected: the cell is read as one string and redacted. Test in Task 7.
3. A chart with no cached values (`c:numCache` absent, common in files written by other tools). Expected: values are looked up from the referenced cells and marked "(from cells)"; if the range cannot be resolved, "values not available" is written, never an empty list. Test in Task 4.
4. A combo chart with a secondary axis or a constant series used as a reference line. Expected: each part and both axes are described; the constant series is flagged as a likely reference line. Test in Task 4.
5. A sheet exactly at the 4,000-cell cap. Expected: read in full; only above the cap is a sheet ignored. Test in Task 6.

---

### Task 1: Spike (done)

Completed 2026-11-08. Result recorded in the spec's "Spike result" section: Excel cannot run unattended (sandbox "Grant File Access" dialogs), Logan ruled Excel out and charts text-only. Nothing to build.

---

### Task 2: Fixture workbook built from text parts

**Files:**
- Create: `tests/testthat/fixtures/workbook/` (the unzipped `.xlsx` parts as text: `[Content_Types].xml`, `_rels/.rels`, `docProps/core.xml`, `docProps/app.xml`, `xl/workbook.xml`, `xl/_rels/workbook.xml.rels`, `xl/sharedStrings.xml`, `xl/styles.xml`, `xl/worksheets/sheet1.xml`..`sheet3.xml` + rels, `xl/drawings/drawing1.xml` + rels, `xl/charts/chart1.xml` (column chart, cached values), `xl/charts/chart2.xml` (combo: column + constant line on secondary axis, **no** `c:numCache`), `xl/comments1.xml`, `xl/persons/person.xml`, `xl/threadedComments/threadedComment1.xml`, `xl/pivotTables/pivotTable1.xml` + `xl/pivotCache/*`, `xl/media/image1.png`, `xl/embeddings/oleObject1.bin` placeholder, `xl/vbaProject.bin` placeholder bytes, `xl/externalLinks/externalLink1.xml`, `xl/connections.xml`)
- Create: `tests/testthat/fixtures/hcahps-source.csv`
- Create: `tests/testthat/helper-workbook.R`
- Modify: `DESCRIPTION` (Imports: `tidyxl`)
- Test: `tests/testthat/test-anon-workbook.R`

**Interfaces:**
- Produces: `fake_workbook(dir, name = "quillpat_1001_5001_partb.xlsx", macro = FALSE) -> path`: zips the fixture parts into `dir/name`; `macro = TRUE` keeps `vbaProject.bin` with the macro content type and uses `.xlsm`. `fake_hcahps()` returns the path of `hcahps-source.csv`.

Invented names placed in every risky spot: "Pat Quill" in docProps creator, "Morgan Rivera" lastModifiedBy, company "Quill LLC", sheet 2 named "Pat Quill data", a cell "Prepared by Pat Quill", a name split across two rich-text runs, comment author "Pat Quill" (legacy, threaded and `persons`), chart title "Chart by Pat Quill", an axis title, a category label "Mo", a chart source line text box "Source: Pat Quill", a sheet text box "prompt log: Pat Quill asked...", header "&LPat Quill", defined name `PatQuillRange`, hyperlink `mailto:pat.quill@example.edu`, external link target `/Users/patquill/secret.xlsx`, connection string with `XQ1001`, sheet 3 `state="veryHidden"`, a hidden row and column, a formula `=SUM('Pat Quill data'!B2:B5)`, a shared formula range, an autofilter, a picture (`image1.png` with the text "Pat Quill" drawn in), and an HCAHPS-shaped 30-row data sheet (invented hospitals, an id column `facility_id`).

- [ ] **Step 1:** test `fake_workbook builds a readable xlsx`: `tidyxl::xlsx_sheet_names(p)` equals the three sheet names; `utils::unzip(p, list = TRUE)$Name` contains `"xl/charts/chart1.xml"` and `"xl/charts/chart2.xml"`.
- [ ] **Step 2:** run, expect FAIL (`fake_workbook` not found).
- [ ] **Step 3:** write the parts and the helper. Ask Logan before installing `tidyxl`; then add it to `DESCRIPTION` Imports.
- [ ] **Step 4:** run, expect PASS.
- [ ] **Step 5:** Commit (wait for Logan).

---

### Task 3: Types, `.xls` refusal, `skip_types`

**Files:**
- Modify: `R/anon-convert.R:5-14` (constants), `R/anon-convert.R:61-62` (`.xls` refusal before the final stop), `R/anon-grading.R:13-75` (`list_submissions`, `assign_files`), `R/anon-grading.R:245` (`anonymize` signature)
- Test: `tests/testthat/test-anon-workbook.R`

**Interfaces:**
- Produces: `WORKBOOK_EXTS <- c("xlsx", "xlsm")`, `SHEET_EXTS <- c(WORKBOOK_EXTS, "csv")`. `list_submissions(assignment_dir, skip_types = character())` drops skipped files and sets `attr(out, "skipped")` to a named integer count by extension. `assign_files()` target rule: latest non-spec document, else latest image, else latest `SHEET_EXTS` file, else stop (existing message). `anonymize(..., skip_types = character(), source_data = NULL)` (wired in Task 7; here only accepted and passed to `list_submissions`).

- [ ] **Step 1:** tests:
  - `xls stops with re-save advice`: an `.xls` file in an assignment; error matches `"S0[0-9] \\(file1\\).*re-save as .xlsx.*skip_types"` and does not contain `"quill"`.
  - `skip_types drops a type and counts it`: `list_submissions(a, skip_types = "xls")` has no `.xls` row and `attr(, "skipped")[["xls"]] == 1`; matching is case-insensitive and tolerates a leading dot (`".XLS"`).
  - `workbook-only student targets the workbook`: a student with only `.xlsx` has `target` TRUE on it; a student with `.xlsx` + `.docx` targets the `.docx`.
  - `all files skipped still stops`: a student with only a skipped file stops with `"no document"`.
- [ ] **Step 2:** run, expect FAIL.
- [ ] **Step 3:** implement. Skipped counts print as `"%d file(s) skipped (.%s)"`.
- [ ] **Step 4:** run, expect PASS; run `filter = "anon"` for no regression.
- [ ] **Step 5:** Commit (wait for Logan).

---

### Task 4: Describe charts from the chart XML

**Files:**
- Create: `R/anon-workbook-chart.R`
- Test: `tests/testthat/test-anon-workbook.R`

**Interfaces:**
- Produces: `workbook_charts(xlsx) -> list` of one entry per chart in workbook order (sheet order, then drawing order), each `list(sheet, anchor, xml)` where `anchor` is `"F2:O17"` (from `twoCellAnchor` from/to, or `oneCellAnchor` + `ext` converted with the sheet's column widths and row heights, default 64 px / 20 px, 9525 EMU per px). `describe_chart(chart, cells) -> character` markdown lines, `cells` being the `tidyxl::xlsx_cells()` data frame for cache fallback.

Description content and order (spec, "What the grader gets" item 1): heading `### Chart <n> (sheet <name>, <anchor>)`; type per plot group (`c:barChart` + `c:barDir`/`c:grouping`, `c:lineChart`, `c:scatterChart`, `c:pieChart`, `c:areaChart`, ...); title; every axis with title, min/max/major unit or "automatic", number format, orientation (reversed), crosses, log base, primary/secondary; gridlines; data labels and what they show; legend and position; other chart text (`c:userShapes` text boxes, so a source line appears); categories in plotted order (honouring reversed category axis); each series: name, `c:cat` and `c:val` ranges, values (cache, else looked up in `cells` and marked "(from cells)", else "values not available"); trendlines; error bars; a series whose values are all equal flagged "constant: likely reference line". Every child element of `c:plotArea` and `c:chart` the function does not handle: `not described: <element name>`.

- [ ] **Step 1:** tests on `fake_workbook()`:
  - `charts found in order with anchors`: two charts; first `sheet == "data"`, `anchor` matches `"^[A-Z]+[0-9]+:[A-Z]+[0-9]+$"`.
  - `column chart described`: lines contain `"column"`, `"Chart by Pat Quill"` (raw, before redaction), the axis title, `"automatic"` or the fixture's set max, the category labels in plotted order, and each cached value.
  - `values from cells when no cache`: chart 2's series values appear with `"(from cells)"` (Review Focus 3); a series pointing at a missing sheet gives `"values not available"`.
  - `combo and reference line`: chart 2 lists a column part and a line part, a secondary axis, and `"likely reference line"` (Review Focus 4).
  - `source line text box`: `"Source: Pat Quill"` appears.
  - `unknown element named`: inject `<c:foo/>` into a copy of chart 1; output contains `"not described: foo"`.
- [ ] **Step 2:** run, expect FAIL.
- [ ] **Step 3:** implement with `xml2` (namespace-aware XPath; read parts with `utils::unzip(exdir = tempdir)` and remove the temp dir on exit).
- [ ] **Step 4:** run, expect PASS.
- [ ] **Step 5:** Commit (wait for Logan).

---

### Task 5: Read the rest of the workbook into markdown

**Files:**
- Create: `R/anon-workbook-read.R`
- Test: `tests/testthat/test-anon-workbook.R`

**Interfaces:**
- Consumes: `workbook_charts()`, `describe_chart()` (Task 4).
- Produces: `workbook_to_md(xlsx, media_dir, media_rel, sources = NULL) -> list(lines = character, other = named integer, big_sheets = data.frame(sheet_pos, rows))`. `csv_to_md(path, sources = NULL) -> same shape`. `media_rel` is the link prefix written into markdown (`"file<k>_media"`). Section order fixed by the spec: Charts, then each sheet, Pivot tables, Comments, Text boxes, Hyperlinks and defined names, Headers and footers, Embedded documents, Other content. `sources` is used from Task 6; until then `NULL`.

Sheet layout (builder's call per spec, but formulas visible with their address): heading `## Sheet: <name>` plus ` (hidden)` / ` (very hidden)`; markdown table with a row-number column and column letters; a formula cell shows the value then `` `=FORMULA` ``; hidden rows/columns listed under the heading; autofilter range and criteria, sort state, merged ranges as lines. Shared formulas expanded (`tidyxl` `formula` column). Rich-text cells read as one string. Dates ISO.

Never read: `docProps/*`, `xl/persons/*`, comment `author`/`personId`, `xl/vbaProject.bin`, `xl/externalLinks/*` targets, `xl/connections.xml`. Their presence is counted in `other` (`macros`, `external_links`, `connections`).

Embedded pictures: each `xl/media/*` file used by a drawing is copied to `media_dir` as `image<N>.<ext>` and linked under its sheet. Embedded OLE: a Word or PDF object under `xl/embeddings/` is written to a temp file and run through `convert_to_text()` (existing), its text under `## Embedded document <N>`, its images into `media_dir`. Anything else (form controls, sparklines, other OLE, macros, ...) counted in `other` and listed under `## Other content`.

Big sheets: with no matching source, every row is written and the sheet is recorded in `big_sheets` when rows > 1000 (Task 7 prints the warning with code and position).

- [ ] **Step 1:** tests on `fake_workbook()`:
  - `charts come first`: the first `##` heading is `## Charts`, holding both chart descriptions.
  - `sheets in order with hidden marks`: sheet headings in workbook order; third ends `(very hidden)`; hidden row and column lines present.
  - `formulas beside values`: a line contains `` `=SUM('Pat Quill data'!B2:B5)` `` and its value.
  - `split run read whole`: the text `"Pat Quill"` appears once from the rich-text cell (joined).
  - `pivot, comment, text box, hyperlink, defined name, header present`: each under its heading.
  - `metadata never read`: output contains neither `"Rivera"` (only in lastModifiedBy), `"Quill LLC"`, `"patquill/secret"`, nor `"XQ1001"`; `other[["macros"]] == 1` for `macro = TRUE`.
  - `embedded picture lands in media`: `media_dir/image1.png` exists and is linked as `file1_media/image1.png`.
  - `nothing silently dropped`: the fixture's form control and sparkline are listed under Other content.
  - `csv reads as one sheet`: `csv_to_md(fake_hcahps())$lines` has one `## Sheet:` heading and 30 data rows.
  - `big sheet recorded`: a 1,500-row csv gives one `big_sheets` row with `rows == 1500` and all rows written.
- [ ] **Step 2:** run, expect FAIL.
- [ ] **Step 3:** implement with `tidyxl::xlsx_cells`, `tidyxl::xlsx_formats`, `xml2` for the rest.
- [ ] **Step 4:** run, expect PASS.
- [ ] **Step 5:** Commit (wait for Logan).

---

### Task 6: Ignore raw-data sheets over 4,000 cells

Revised 2026-11-08 (Logan): replaces the source-file comparison. No `source_data` argument; the `sources` hooks and the 1,000-row `big_sheets` warning go away.

**Files:**
- Modify: `R/anon-workbook-read.R` (cap per sheet and for `csv_to_md`; drop the `sources` argument and `big_sheets`), `R/anon-workbook-chart.R` (cells fallback skips ignored sheets), `R/anon-grading.R` (remove the `source_data` stub from `anonymize()` and its roxygen; regenerate `man/`)
- Test: `tests/testthat/test-anon-workbook.R` (replace the big-sheet test)

**Interfaces:**
- Produces: `RAW_CELL_CAP <- 4000L`. `workbook_to_md(xlsx, media_dir, media_rel) -> list(lines, other, ignored = data.frame(sheet_pos, rows, cols))`; `csv_to_md(path) -> same shape`. Used range = rows x columns from the first to the last non-empty cell (sheet `<dimension>` if present, else from the cells). A sheet with used range > `RAW_CELL_CAP` cells: none of its cells, formulas, filters or sort state are read into the output; under its normal heading one line: `"Not read: <rows> rows x <cols> columns is over the 4,000-cell limit for raw data."` (numbers with thousands separators). Charts, pivots, comments and text boxes on that sheet are still read. `describe_chart()`'s cells fallback treats an ignored sheet like a missing one ("values not available"); cached values still print.
- The cap is checked before `tidyxl::xlsx_cells()` loads the sheet where possible (pass `sheets =` for the kept ones), so a 100,000-row sheet does not slow the run.

- [ ] **Step 1:** tests:
  - `sheet over the cap is ignored`: a variant whose data sheet is 201 rows x 20 columns (4,020 cells); the sheet heading is present, the "Not read: 201 rows x 20 columns" line is present, and no cell value from that sheet appears; `ignored` has one row.
  - `sheet at the cap is read`: 200 x 20 (4,000 cells) is written in full (Review Focus 5).
  - `csv over the cap is ignored`: a 4,001-cell csv gives the "Not read" line and no data rows.
  - `charts on an ignored sheet still described`: a chart plotting the ignored sheet prints its cached values; with the cache removed it prints "values not available", not the cells.
  - `anonymize has no source_data argument`: `"source_data" %in% names(formals(anonymize))` is FALSE.
- [ ] **Step 2:** run, expect FAIL.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run, expect PASS.
- [ ] **Step 5:** Commit (wait for Logan).

---

### Task 7: Wire workbooks into anonymize()

**Files:**
- Modify: `R/anon-convert.R:23-65` (`convert_to_text` returns `other`/`ignored` as attributes), `R/anon-grading.R:245-480` (skipped/other/ignored counts, roxygen), `R/anon-log.R` (skipped and other-content counts in the log record)
- Test: `tests/testthat/test-anon-workbook.R`

**Interfaces:**
- Consumes: Tasks 3, 5, 6.
- `convert_to_text()` for `WORKBOOK_EXTS`: `workbook_to_md(path, media_dir, basename(media_dir))`; for `csv`: `csv_to_md(path)`; writes `lines` to `out_md`. The existing redaction chain in `anonymize()` then runs on that `.md` unchanged.
- `anonymize()`: console line per file with ignored sheets: `"%s (%s): %d sheet(s) over the 4,000-cell limit not read"` with code and file position. Roxygen documents workbook handling, the chart description (no picture), `skip_types`, the 4,000-cell cap, `.xls` and Strict-format refusal.

- [ ] **Step 1:** tests (end-to-end, `skip_if_no("tesseract")`, `sweep = FALSE`, `dict = NULL`):
  - `workbook end to end leaves no name`: assignment with Quill's fixture `.xlsx` and Rivera's `.docx`; `anonymize()` succeeds after `anon_images.csv` marks the fixture picture `remove`; grep every text file under `anon/` for `quill|rivera|\\bmo\\b|xq100|1001|secret` (ignore case) gives zero hits; `manifest.csv` row for the workbook-only student has `ext == "xlsx"` and `target == TRUE`.
  - `sheet name redacted consistently`: the coded `.md` contains `"[name] data"` in the sheet heading, in the `SUM` formula and in the chart series range (Review Focus 1).
  - `split run redacted`: no `"Pat "` followed by `"Quill"` anywhere (Review Focus 2).
  - `fixture picture held for review`: first run stops listing `file1_media/image1.png` (OCR finds "Pat Quill").
  - `big sheet ignored end to end`: a workbook with a 4,001-cell sheet gives the "Not read" line in the coded `.md`, the console line, and an ignored count in the log.
  - `log records skipped and other content`: `deidentification_log.md` gains the skipped count by type and the other-content counts, no names.
- [ ] **Step 2:** run, expect FAIL.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run `filter = "anon"`, expect PASS; then the whole suite.
- [ ] **Step 5:** Commit (wait for Logan).

---

### Task 8: relink() answers a workbook with markdown

**Files:**
- Modify: `R/anon-grading.R:500-532` (`render_feedback`), `R/anon-grading.R:663-718` (target name, zip check), roxygen of `relink()`; `NEWS.md`
- Test: `tests/testthat/test-anon-workbook.R`

**Interfaces:**
- Produces: `feedback_name(target) -> character`: unchanged for document and image types; for `SHEET_EXTS` replaces the extension with `.md` (`quillpat_1001_5001_partb.xlsx` -> `quillpat_1001_5001_partb.md`). Used where `relink()` records each target (line ~678) and in the zip check (~709).

- [ ] **Step 1:** tests:
  - `feedback_name swaps sheet extensions only`: `.xlsx`, `.xlsm`, `.csv` give `.md`; `.docx` and `.png` unchanged.
  - `workbook-only student gets md feedback`: after an anonymize run, write `feedback/S01.md` and `scores.csv`; `relink()` writes `feedback/quillpat_1001_5001_partb.md` with `"Pat Quill"` in place of the code; the zip holds exactly that name.
- [ ] **Step 2:** run, expect FAIL.
- [ ] **Step 3:** implement; NEWS entry under the development heading (no version bump).
- [ ] **Step 4:** run `filter = "anon"` then the whole suite; expect PASS. Report pass/fail/skip counts.
- [ ] **Step 5:** Before Logan relies on it: verify Canvas's submission-comment upload accepts a `.md` file answering an `.xlsx` submission (spec `[VERIFY]`). If unverified, say so in the report; do not claim it.
- [ ] **Step 6:** Commit (wait for Logan).

---

### Task 9: Glued names in workbooks are reported, not blocking

Added 2026-11-08 (Logan). A student name glued into another word (`PatQuillRange`) is not redacted; the leftover check's second pass (bare substring of loose terms, `R/anon-redact.R:149-155`) finds it and today stops the run. Logan's ruling: **for workbook and csv files only** (`SHEET_EXTS`), a hit found only by that second pass is reported, not blocking. Every other file type, and any hit from the first pass (whole-word match), still stops the run exactly as today. Known possible leak; recorded in `project/TODO.md` item 8 for a future fix.

**Files:**
- Modify: `R/anon-redact.R` (`find_leftovers()` returns which pass found each hit), `R/anon-grading.R:~489` (split hits: workbook-file glued-only hits are reported, everything else stops), `R/anon-log.R` (count of reported glued-name hits), roxygen of `anonymize()`; `NEWS.md`
- Test: `tests/testthat/test-anon-workbook.R`, plus a regression test in `tests/testthat/test-anon.R` that a glued name in a `.md`/`.docx` submission still stops the run

**Interfaces:**
- `find_leftovers(files, terms, keep)` gains a `pass` column (`"word"` or `"glued"`); a file/code pair found by both keeps `"word"`.
- The coded file's type comes from `manifest`/`subs` (ext of the source submission), not from the `.md` name.
- Reported hit console line: `"GLUED NAME: a value for %s may remain in %s (glued into another word; not redacted)"` with code and the anonymized path only, like the existing LEFTOVER line. Log record: count of such hits. `anon/` is released when these are the only hits.

- [ ] **Step 1:** tests:
  - `glued name in a workbook is reported, not blocking`: the fixture with `PatQuillRange` (no nickname added) anonymizes successfully; console shows the GLUED NAME line naming S01 and `anon/S01/file1.md`; log has the count; no NOT_READY.
  - `whole-word name in a workbook still stops`: a workbook cell that escapes redaction as a whole word still stops (use a mocked redactor or a term absent from redaction but present in the leftover terms, per existing leftover tests).
  - `glued name in a document still stops`: a `.md` submission containing `PatQuillRange` stops with the LEFTOVER message as today.
- [ ] **Step 2:** run, expect FAIL.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run `filter = "anon-workbook"`, `filter = "anon"`; expect PASS.
- [ ] **Step 5:** Commit (wait for Logan).
