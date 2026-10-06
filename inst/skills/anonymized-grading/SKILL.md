---
name: anonymized-grading
description: >
  Grade student submissions without student identity leaving the instructor's
  machine. Use when the user says "grade these submissions", "grade the case
  study", "grade the quiz", "anonymize the submissions", "relink the feedback",
  "make the feedback zip", "grades CSV for Canvas", "gradebook import", or has
  just downloaded a Canvas bulk submission folder or a gradebook export. Also
  use when agents are about to read student work for any reason.
---

# Grading without student identity

A grader, human or agent, never needs to know whose paper it is. Canvas
downloads carry the student's name and ids in every filename, and about one
file in eight carries the name inside the document as well. So the grader works
only on coded copies (`S07`), and names come back on the instructor's machine
at the very end.

**The rule this skill exists to keep:** no agent reads anything under the
course's `semester/` folder except the `anon/` folder of the assignment it is
grading. Not the downloads, not the key, not a scores file, not a grading
notes file, not the nicknames file, not a gradebook export or import.

## The pipeline

| Step | Who | Command or action |
|---|---|---|
| 1. Key | instructor's machine | `coursepack::anon_key(".", gradebook = "semester/<term>/gradebook_export/<latest export>.csv", assignment = "semester/<term>/<Assignment>", nicknames = "semester/<term>/nicknames.csv")` |
| 2. Key review | the instructor, by hand | opens the key, adds nicknames to the nicknames file |
| 3. Anonymize | instructor's machine | `coursepack::anonymize(".", "semester/<term>/<Assignment>")` |
| 4. Grade | one agent per assignment | reads `anon/` only, writes `anon/feedback/` and `anon/scores.csv` |
| 5. Rulings | the instructor | one decision at a time |
| 6. Relink | instructor's machine | `coursepack::relink(".", "semester/<term>/<Assignment>")` |
| 7. Grades for Canvas | instructor's machine | `coursepack::canvas_grades(".", gradebook = "semester/<term>/gradebook_export/<fresh export>.csv", map = "semester/<term>/canvas_columns.csv")`, written to `semester/<term>/gradebook_import/` |
| 8. Forget the key | instructor's machine | `coursepack::anon_forget(".", "semester/<term>/<Assignment>")`, once the upload is confirmed |

Every command prints counts and codes only. That output is safe to read.

### 1 and 2: the key

Every assignment gets its own key, built from the latest gradebook export
right before that assignment is anonymized. `anon_key()` writes it to
`<Assignment>/anon_key.csv`, beside the downloads and never inside `anon/`,
and hands out the codes in a random order, so no two assignments share a
mapping and a key that leaks exposes one assignment only. The key records its
run, the assignment folder, and `anonymize()`, `relink()` and
`canvas_grades()` refuse a key of another run. Running `anon_key()` again for
the same assignment keeps every row and code and adds only students who are
new in the export.

Nicknames do not live in any key. The instructor keeps them in the term
nicknames file, `canvas_id,nicknames` with nicknames separated by `;`, which
holds no codes, and `anon_key()` copies them in through `nicknames =`.

Then hand the key to the instructor: open it in their spreadsheet app
(`open` on macOS) and do not read it yourself. Ask them to check the
`name_forms` column for a name part that is also an ordinary word, and to add
any nickname a student goes by to the nicknames file, then run `anon_key()`
again for the assignment.

### 3: anonymize

Run it per assignment folder. It converts every file each student submitted,
in upload order, to `anon/<code>/file1.md`, `file2.md`, with images beside
them, and redacts every student's names, ids, logins, home-folder user names
and emails. Every redacted name, whoever's it was, becomes the same token,
`[name]`, so the grader never sees whose name was redacted and never sees a
student code inside the text; codes only name folders and feedback files. It also redacts phone numbers, SSNs, birth dates, street
addresses, profile URLs and handles, and reads the text in images. It needs
tesseract and stops before writing anything without it (`brew install
tesseract`). It writes `anon/NOT_READY` until its own leftover check passes.
The coded folder shows no lateness and no submission times.

- To keep an instructor's or TA's name readable (a heading such as "Dr.
  Avery Thorn"), the instructor creates `anon_keep.txt` at the course root,
  the `proj` folder, one phrase per line, `#` comments and blank lines
  ignored. Each phrase must be a whole phrase of two or more words. A single
  name is refused (the run stops, naming only the line number) because a
  student may share it, and that student's name must still be redacted. A
  phrase holding any form of a student's name (full name in either order,
  run together, initial and surname, or a nickname), or a student's file
  prefix, login or Canvas id, is refused too, by line number; a first or
  last name alone inside a phrase is allowed. "Dr. Thorn" counts as two words
  and would be kept wherever it is written, so list exact phrases. A kept
  phrase stays whole, also across a line break; the same name alone still
  becomes `[name]`. The run and the log report how many were kept, never the
  phrase. The file is the instructor's: do not open it.
- A leftover stop names a code and a file. The instructor adds the missing
  form to the nicknames file, you run `anon_key()` again for the assignment,
  and then run `anonymize()` again. Never open the file to look.
- An unsupported file type stops it. Report the code and the type.
- When it stops on images, it lists image paths: ones whose text held a name,
  id or other identifier, every SVG (each one always needs a decision), and
  files it cannot read. The instructor opens each
  one, on the instructor's machine, and writes `anon_images.csv` beside the
  key with `image,decision` rows, `keep` or `remove`; then run `anonymize()`
  again. You never open the images. You may relay the list of paths. `remove`
  deletes the image and replaces its links with `[image removed]`, and works
  for any image under `anon/`, listed or not. Give each image one decision; two
  different decisions for one image stop the run. A kept EMF
  or WMF file is released unaltered, metadata included, so tell the instructor
  that when asking.
- After the run, the instructor can read `deidentification_log.md` beside the
  key. It holds counts only and is the record of de-identification. Keep it
  with the course records; `anon_forget()` does not delete it.
- It refuses to run while `anon/feedback/` or `anon/scores.csv` exists, so it
  can never wipe grading work.

### 4: grade

The rubric, answer key and grading guide must exist first, in the course's
private assessment folder. Write them before grading if they do not.

Dispatch **one fresh agent per assignment**, all in parallel. Each dispatch
contains exactly these parts:

1. The `anon/` folder path for that assignment, and nothing else from
   `semester/`.
2. The rubric, answer key and grading guide paths.
3. The rulings file, if the instructor has made rulings for this assignment:
   general rules, no student names.
4. The calibration the instructor gave (for example "generous but fair").
5. Its own scratch subfolder, named for the assignment
   (`<scratch>/grade-<assignment>/`), and an order to use no other.
6. The outputs: `anon/feedback/<code>.md` per student, titled
   `<Assignment> Feedback: <code>`, and `anon/scores.csv` with a `code`
   column, one column per criterion or question, and `total`.
7. A notes file for the instructor: every judgment call, by code, quoting the
   student's own words.
8. The checks it must run before reporting: totals equal parts, every score is
   a rubric value, no other student's code inside a student's feedback, no
   em-dashes, no mention of AI.

When a student uploaded several files, the grader sees all of them. Feedback
attaches to that student's latest document (`.docx`, `.odt`, `.pdf`, `.md`,
`.qmd`, `.Rmd` or `.txt`) whose name does not start a word with "spec", or to
the latest document when every one is a spec. A script such as `.R` is read but
never gets feedback, and a student with no document at all stops the run.

### 5: rulings

Read the grader's notes and bring each call to the instructor **one at a
time**. Each message opens with the assignment and the question or criterion,
quotes the student's actual words from the coded file, gives the rubric line
and the current score, and offers the options with their effect on the total.
Never summarize a student's answer in your own words. A summary can carry the
wrong idea from a neighbouring question.

Apply each ruling through the same grading agent that wrote the feedback. Keep
the feedback filenames identical, and record the ruling in its notes.

### 6: relink

`relink()` puts the names back, refuses any feedback that names another
student, renders each file under the exact name of its submission (a PDF
submission gets PDF feedback), and builds `feedback.zip`. It writes nothing
until every check passes and never overwrites an existing `feedback/`, scores
file or zip. Move the old ones out first when re-running after a ruling.

Before handing the zip over, confirm that every entry matches a submission
filename in the folder.

### 7: grades for Canvas

Canvas writes back every cell an import carries, and reads a blank cell as a
deletion, but leaves alone any assignment column the import does not carry.
So `canvas_grades()` writes a narrow import: the identity columns (`Student`,
`ID`, `SIS User ID`, `SIS Login ID`, `Integration ID`, `Root Account`, `Section`) and the
mapped assignment columns only, with the header row, the `Points Possible`
row and every student row of the export, the Test Student included. Every
kept cell is the export's own text except the filled scores, written with two
decimals. Every other assignment and every read-only total is dropped, so the
import cannot roll back a grade it does not carry.

Exports go in `semester/<term>/gradebook_export/` and imports go in the
sibling `semester/<term>/gradebook_import/`, which is the default. The tool
reads exports and writes only imports, never into the export's folder or an
assignment folder, and it stops if `import_dir` or `out` points at the
export's folder or anywhere below it. Only the term is read from the paths,
never a folder to write in: it is the folder name right after `semester/` in
the export's path, and every mapped assignment folder must be in the same
term. If the export is not under `semester/<term>/`, or a folder is in another
term or in none, the call stops and lists each path with its term; fix the
paths or the map rather than passing `import_dir` to get past it. Ask the instructor to download a new export after
relinking and right before importing, so every student scored is in it, then
fill it:

```r
coursepack::canvas_grades(".", gradebook = "semester/<term>/gradebook_export/<export>.csv",
                          map = "semester/<term>/canvas_columns.csv")
```

The map has one row per assignment, `folder,column`, where `column` is text
that matches exactly one assignment column, and an optional third column,
`scores`, naming a scores file for a folder that holds more than one or whose
scores are elsewhere. End case studies with a colon (`Case Study 1:`) so they
cannot also match `Case Study 10`. Coded scores are placed through each
folder's own key, so no `key` is passed. The result is
`<YYYY-MM-DD>_<folder>_import.csv` in `semester/<term>/gradebook_import/` for one assignment, or
`<YYYY-MM-DD>_<N>-assignments_import.csv` for several. It never replaces an
existing file; after a ruling, re-run with `overwrite = TRUE`. Tell the
instructor to read Canvas's import preview before confirming.

### 8: forget the key

Once the instructor confirms the feedback upload and the grade import in
Canvas, delete the assignment's key:

```r
coursepack::anon_forget(".", "semester/<term>/<Assignment>")
```

It refuses until `relink()` has written `feedback/` and the scores file into
the assignment folder, because until then the key is still needed. After it,
nothing on the machine links that run's codes to students.

## Common mistakes

| Mistake | What it costs | Do instead |
|---|---|---|
| Grading agents share one scratch folder | one agent's drafts land in another assignment's feedback | a subfolder per assignment, and a title check before zipping |
| A grader is given a downloads folder, a notes file or a scores file | names reach the grader | give it `anon/` and the rubric files only |
| Rulings sent as a batch across assignments | the instructor cannot tell which assignment a call belongs to | one call per message, assignment first |
| A student's answer paraphrased in a ruling | the instructor rules on words the student never wrote | quote the coded file |
| Feedback regenerated as `.docx` for a PDF submission | the name no longer matches and Canvas skips it | regenerate through `relink()` |
| The zip rebuilt before every ruling is applied | students receive superseded feedback | rebuild after the last ruling, then check entry names |
| Canvas downloads edited or renamed to get past a stop | the instructor's record of what was submitted is gone | work on the coded copy; ask the instructor |
| A full-width import, or one with blank cells for other assignments | Canvas writes every cell back, rolling back or deleting grades | `canvas_grades()`, which carries the mapped columns only |
| One key reused across assignments | a single leaked file de-anonymizes all of them | `anon_key()` per assignment, `anon_forget()` when done |
| Nicknames typed into a key | they are lost when the key is deleted | the term nicknames file |
| An import written beside the export | exports and imports get mixed up | let `canvas_grades()` write to `semester/<term>/gradebook_import/` |
| Anything under `semester/` committed | student data enters git history for good | `semester/` stays git-ignored; check before every commit |
