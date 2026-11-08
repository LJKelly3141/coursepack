# Workbook submissions in anonymize(): design

Date: 2026-11-08. Status: approved; revised the same day after the Excel
spike (charts are text only, no picture, no Excel). Nothing built.

## Why

ECON 740 Module 1 Part B asks for an Excel workbook, a prompt log and a
write-up. On 2026-11-07, coursepack 1.3.0.1 `anonymize()` stopped on the
first `.xlsx` with `unsupported submission type: .xlsx`
(`R/anon-convert.R:62`). The workaround graded only the documents: two of
ten students (workbook only) could not be graded, and two rubric lines
(AI process documentation, Design execution) could not be scored because
the charts, and probably the prompt logs, live in the workbooks. Logan ruled
full marks on those lines for now; workbooks get re-checked once this lands.

Logan grades a workbook **chart first, then the formulas behind it**. He
first wanted to see a picture of each chart. The spike showed Excel cannot
draw one unattended (see "Spike result"), and Logan then ruled: **no
picture, a full text description of each chart instead.** Accepted
consequence: the grader judges design execution from the chart's settings
and data (sort, labels, title, source line, scale, reference line), not
from how it looks (colors, clutter, overlapping labels).

## Goals

1. `anonymize()` reads `.xlsx`, `.xlsm` and `.csv` submissions into the same
   shape as every other type: `anon/<code>/file<k>.md` plus
   `file<k>_media/`.
2. Every chart arrives as a complete text description of its settings and
   the data it plots.
3. Every formula is visible beside its cell.
4. A workbook passes through exactly the same redaction, leftover check,
   image review and privacy sweep as a document, with nothing able to slip
   past them.
5. A student who submitted only a workbook can be graded and gets feedback.
6. A file type the run cannot read can be skipped by name instead of
   blocking the whole run.

## Non-goals

- No chart picture. No Excel and no LibreOffice (Logan's ruling after the
  spike). No redrawing the chart in R.
- No feedback written into a workbook. A workbook is read, never answered
  in its own type (like `.R`).
- No re-grading tooling for last week's run; that is a course-repo task.
- No change to the course repo
  (`/Volumes/SSD8TB/Sync/UWRF/Teaching/data-visulization`). Testing uses
  made-up fixture workbooks only, never student files.

## Anti-goals (a failure even if it "works")

- A chart silently missing from the description, or a chart setting the
  reader cannot interpret dropped without a mention.
- A sheet over the 4,000-cell cap ignored without a line saying so.
- Any text from the workbook (sheet name, comment, text box, chart title,
  header/footer, defined name, hyperlink, hidden sheet) reaching `anon/`
  without going through redaction.
- Author, last-modified-by, company, or comment-author names copied out at
  all.
- Any code path that runs, opens or executes workbook content (macros,
  external links, data connections).

## Decided by Logan

| Question | Ruling |
|---|---|
| Chart picture | None. Text description only (after the spike) |
| Reading-side description (below) | "looks good" |
| Large raw-data sheets | (Revised) A sheet over 4,000 cells is raw data and is ignored; no source-file comparison |
| Workbook-only student's feedback | A markdown file |
| Unreadable/unknown type | Keep stopping by default; Logan names types to skip |
| Names inside a chart | Redacted like every other text (originally "before Excel draws"; with no picture, redaction of the read-out text covers it) |
| `.xls` | Stop with a message to re-save as `.xlsx`; skippable via the skip option |
| Workbook reader | Add `tidyxl` to Imports |
| Content not listed below | Embedded Word/PDF objects extracted and converted like documents; anything else listed by kind and count in the `.md` and the log |

## What the grader gets from each workbook

One `file<k>.md`, written in workbook order:

1. **Charts first** (Logan's reading order). For each chart, read from the
   chart XML:
   - the sheet it sits on, and its position and size in cells
     (e.g. "F2 to O17");
   - chart type and direction (column, bar, line, scatter, pie, combo
     parts listed separately), stacked or clustered;
   - title, axis titles, and any other text on the chart (text boxes inside
     the chart, a source line);
   - each axis: min, max and major unit (or "automatic"), number format,
     reversed or not, where it crosses, log scale;
   - gridlines, data labels (on/off and what they show), legend (on/off,
     position);
   - categories **in the order they are plotted**, so the sort is visible;
   - each series: name, cell ranges (`c:cat`, `c:val`), and the values it
     plots (from the chart's cached values), so the grader can check them
     against the formulas;
   - trendlines, error bars, and any series that is a constant or a single
     repeated value, flagged as a likely reference line.
   Anything in the chart XML the reader does not interpret is named as
   "not described: <element>" so nothing is dropped silently.
2. **Each sheet**, under its own name, marked `(hidden)` or `(very hidden)`
   when so. Cell values with each formula shown beside its cell address.
   Hidden rows and columns included and marked. Autofilter range and
   criteria, sort state, merged cells.
3. **Pivot tables**: location, source range, row/column/value fields and
   aggregation, filters.
4. **Comments and notes** (legacy and threaded), text only, never the
   author.
5. **Text boxes and shapes** with their text (a prompt log may be pasted
   into one).
6. **Hyperlinks** (display text and target) and **defined names**.
7. **Headers and footers.**
8. **Embedded pictures** into `file<k>_media/`.
9. **Embedded objects**: a Word or PDF file pasted in (OLE) is extracted
   and converted through the existing `.docx`/`.pdf` path, its text
   appended under its own heading and its images into `file<k>_media/`.
10. **Anything else** the reader does not handle (form controls,
    sparklines, macro code, other OLE types, ...) is listed by kind and
    count at the end of the `.md` and counted in the de-identification log.
    Never silently dropped, never stops the run.

Workbook metadata (`docProps/core.xml` creator and lastModifiedBy,
`docProps/app.xml` company, `xl/persons`) is never read into the output.

## Privacy path

- Nothing runs or opens the workbook as an application. The `.xlsx` is
  read as a zip of XML by `tidyxl` and `xml2`, so macros, external links
  and data connections are never executed. `vbaProject.bin`, external link
  targets, connection strings, `docProps` author/company fields,
  `xl/persons` and comment authors are never read into the output.
- All text read out (cells, formulas, chart text, comments, text boxes,
  headers/footers, sheet names, defined names, hyperlinks) goes through the
  existing chain unchanged: `redact_paths()`, `redact_patterns()`,
  `redact_lines()`, then the leftover check and the sweep. A name split
  across rich-text runs in one cell is joined before redaction.
- Embedded pictures land in `file<k>_media/`, so the existing tesseract
  scan and `anon_images.csv` keep/remove review cover them with no new code
  path.

## Raw data sheets

Revised 2026-11-08 (Logan): no comparison against the source dataset and no
`source_data` argument. A size cap instead.

- A sheet (or `.csv`) whose used range is more than **4,000 cells**
  (rows x columns of the used range) is raw data and is **ignored**: none of
  its cells, formulas, filters or sort state are read or written.
- Why 4,000: the privacy sweep sends each coded file to the local model
  (gemma-4-31b-it-mlx, loaded context 65,536 tokens) in one request. A
  22-column data row is roughly 90 tokens, so 4,000 cells (about 200 such
  rows) is about 18,000 tokens, leaving room for the rest of the workbook.
- The grader still sees that it existed: one line under the sheet's heading,
  e.g. "Not read: 4,812 rows x 22 columns is over the 4,000-cell limit for
  raw data." (My call, from the "nothing silently dropped" anti-goal; the
  sheet name goes through redaction like any other text.)
- Charts that plot an ignored sheet are still described from their cached
  values; the cells fallback does not read ignored sheets.
- The ignored count goes to the de-identification log.

## Feedback (relink)

- `assign_files()` today stops a student with no document or image. New
  rule: if a student has no document and no image, the latest workbook (or
  `.csv`) is the target.
- `relink()` answers a workbook target with a markdown file. A student who
  also submitted a document still gets feedback on the document, exactly as
  now.
- File name: the workbook's Canvas filename with its extension replaced by
  `.md`. [VERIFY: that Canvas's submission-comment upload matches a file
  whose extension differs from the submission's. If it does not, this needs
  Logan's ruling.]

## Other types

- `.csv`: one plain sheet; the 4,000-cell cap applies.
- `.xlsm`: as `.xlsx`. Macro code is never read; its presence is counted
  under "anything else".
- `.xls`: not read (Logan's ruling). The old binary format cannot be read
  by the XML reader. The run stops naming code and file position and says
  to re-save as `.xlsx`, or to pass `.xls` in the skip option.

## Skipping types

- New argument, e.g. `skip_types = c("pptx")`. Default: none, so an unknown
  type still stops the run as today.
- Skipped files are counted by type on the console and in the
  de-identification log, never named. They get no `file<k>.md`. Whether
  they keep their position number in the manifest is the builder's call.
- A student whose only files are all skipped stops the run ("no document"),
  as today.

## Constraints

- Messages name a code, a file position or a count, never a student, id or
  original filename (existing rule, `R/anon-grading.R:9`).
- `tidyxl` is added to Imports (Logan approved) for cells, formulas,
  formats, merged cells and hidden rows/columns. `xml2` (already imported)
  reads what `tidyxl` does not: charts, pivots, drawings, comments.
  Installing `tidyxl` on Logan's machine is a separate action that needs
  his go at the time.
- No platform-specific tools: no Excel, no AppleScript.
- Fixtures: test workbooks built from text XML parts under
  `tests/testthat/fixtures/`, with fake names in every risky place: sheet
  name, cell, comment author, text box, chart title, header, hidden sheet,
  docProps.

## Spike result (2026-11-08)

- Excel for Mac 16.109.1, driven by AppleScript from a throwaway fixture.
- `save as picture` on a chart object fails every time with "Parameter
  error (-50)", with or without folder access.
- Save-as-PDF works once the folder is granted (chart moved to its own
  sheet, data sheets hidden: one page, chart only).
- Blocker: Excel's sandbox shows a modal "Grant File Access" dialog for
  every folder it has not been granted, and asked again after Excel
  restarted, even for a folder granted minutes before. An unattended run
  hangs on it. Logan ruled Excel out.

## Left to the builder

- Markdown layout of sheets, formulas and the chart description.
- Shared-formula expansion, number formats, date handling.
- Argument names, size threshold, how many header rows to show.
- Whether `.csv` reading uses `utils` or `readr`.

## Open for Logan

- The Canvas `.md` naming question above, if verification fails.
- Version number and NEWS entry at release time.
