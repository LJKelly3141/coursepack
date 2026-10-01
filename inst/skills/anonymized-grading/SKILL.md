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
notes file, not the gradebook export.

## The pipeline

| Step | Who | Command or action |
|---|---|---|
| 1. Key | instructor's machine | `coursepack::anon_key(".", gradebook = "semester/<term>/<export>.csv", key = "semester/<term>/anon_key.csv")` |
| 2. Key review | the instructor, by hand | opens the key, adds nicknames |
| 3. Anonymize | instructor's machine | `coursepack::anonymize(".", "semester/<term>/<Assignment>", key = ...)` |
| 4. Grade | one agent per assignment | reads `anon/` only, writes `anon/feedback/` and `anon/scores.csv` |
| 5. Rulings | the instructor | one decision at a time |
| 6. Relink | instructor's machine | `coursepack::relink(".", "semester/<term>/<Assignment>", key = ...)` |
| 7. Grades for Canvas | instructor's machine | `coursepack::canvas_grades(".", gradebook = "semester/<term>/<fresh export>.csv", map = ..., key = ...)` |

Every command prints counts and codes only. That output is safe to read.

### 1 and 2: the key

Build the key from a Canvas gradebook export. Rebuilding keeps every existing
row and its code and only adds new students at the next code, so run
`anon_key()` again with the newest export before every assignment: a student
who joined after the key was built otherwise stops `anonymize()` as unknown.

Then hand the key to the instructor: open it in their spreadsheet app
(`open` on macOS) and do not read it yourself. Ask them to check the
`name_forms` column for a name part that is also an ordinary word, and to add
any nickname a student goes by to `nicknames`, separated by `;`.

### 3: anonymize

Run it per assignment folder. It converts every file each student submitted,
in upload order, to `anon/<code>/file1.md`, `file2.md`, with images beside
them, and redacts every student's names, ids, logins, home-folder user names
and emails. It writes `anon/NOT_READY` until its own leftover check passes.

- A leftover stop names a code and a file. The instructor adds the missing
  form as a nickname and you run it again. Never open the file to look.
- An unsupported file type stops it. Report the code and the type.
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

Canvas accepts an import only when it is exactly its own export, and the
import writes back every cell the file carries. An export downloaded before
grading finished can carry a stale grade for some other assignment, so ask the
instructor to download a new export after relinking and right before
importing, then fill it:

```r
coursepack::canvas_grades(".", gradebook = "semester/<term>/<export>.csv",
                          map = "semester/<term>/canvas_columns.csv",
                          key = "semester/<term>/anon_key.csv")
```

The map has one row per assignment, `folder,column`, where `column` is text
that matches exactly one assignment column. End case studies with a colon
(`Case Study 1:`) so they cannot also match `Case Study 10`. The result,
`canvas_import.csv` beside the export, is the export byte for byte except the
filled cells. Students with no score keep what the export had. Tell the
instructor to read Canvas's import preview before confirming.

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
| An import CSV built with only some columns | Canvas rejects it | `canvas_grades()` on a fresh, complete export |
| Anything under `semester/` committed | student data enters git history for good | `semester/` stays git-ignored; check before every commit |
