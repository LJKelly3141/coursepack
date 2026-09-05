---
name: course-schedule-review
description: Use before writing or changing any due date, open date, or term date in a course. Triggers on "set the due dates", "fix the due dates", "the dates are wrong", "when is module 3 due", "roll the course to spring", "update the schedule", "change the due date on homework 4", any edit to a `due:` field in `modules.yml`, any edit to the Course Outline table in a syllabus, and any request to build or import a cartridge whose assignments carry dates. Also use when a term's first or last day changes, when a holiday or break is added, and when checking whether a published course's Canvas dates still match the source.
---

# Review a course schedule before anyone sees it

Seventeen due dates that are uniformly wrong look exactly like seventeen that are
right. This skill exists because that happened on a live course on the first day
of a term: every date in `modules.yml` was seven days late, and every one was
still a Friday. Nothing looked out of place. All seventeen had to be corrected by
hand in Canvas, with no API available to do it.

The failure was not arithmetic. Nothing computed the dates, nothing compared them
to the registrar's calendar, and nothing compared them to the scheduling rule the
course itself prints for students. Each step below closes one of those gaps.

Run the whole thing. A schedule is a system of constraints, and checking six of
seven leaves the same class of error in place.

## 1. Read the registrar's academic calendar, from the PDF

The calendar is the only authority on term boundaries and no-class days. Read it
first, before touching any date.

    pdftotext -layout reference/policy/<academic-calendar>.pdf -

Registrar calendars are often print-to-PDF. Naive HTML fetching returns
nothing useful from one, and an earlier session concluded from that the calendar
could not be read and asked the author to read it instead. That was wrong.
`pdftotext -layout` handles it immediately, in one command, with no download.
**The calendar is readable. Do not give up on it and do not delegate reading it
to the author.**

Evidence required: the extracted lines themselves, quoted, not a summary of them.

Prevents failure 1, the calendar never being read at all.

## 2. Never accept a web search in place of the calendar

A search summary during the incident stated that "Labor Day is observed on
Thursday-Friday, October 22-23, 2026," and flagged its own answer as unusual. It
had collided Labor Day with Fall Break. The calendar settled it in seconds.

A search result about an academic calendar is a lead, never a source. If step 1
produced text, step 2 is already satisfied and no search is needed.

Prevents failure 2.

## 3. Ask for anything the calendar does not carry

A calendar can carry full-semester dates and still leave a sub-session boundary
unstated. Two real inventions came out of exactly that gap.

A prior session reasoned backward from a later session's start date and was
wrong; the correct date came from the author, and it was not derivable from any
document in the repository.

The same rule caught a second invention. To make a printed "opens Monday" rule
fit a term that starts midweek, an assistant invented an opening Monday before
the term began. Nothing opened that day, and in that state, starting a term then
would have been unlawful.

**Anything the sources do not state gets asked. It never gets derived and it
never gets invented.** The term's first day, its last day, the session end, and
the week count are all in this category unless a document says otherwise.

Prevents failures 8 and 9.

## 4. Find the rule the course prints to students, and treat it as a constraint

The rule is printed on the welcome page and in the syllabus. For example, one
course prints:

> Modules open on Mondays and each module's work is due at 11:59 PM Central on
> the Friday of the following week.

That is a rule students will hold the course to. During the incident the dates in
`modules.yml` violated it, and nothing ever compared the two. Printing a rule and
storing data that contradicts it is the defect, whichever half is wrong.

Quote the rule verbatim from the source file. Then decide with the author which
half changes when they disagree.

Prevents failure 4.

## 5. Compute every date from the rule, then diff against what is stored

Do not read the stored dates and judge them. Generate the schedule the rule
implies, from the term's first day and the no-class list, and diff it against
`modules.yml`.

Seventeen hand-typed literals were all exactly seven days late. Reading them one
at a time will not find that, because each one individually looks fine and the
set is internally consistent. Only a computed comparison surfaces a uniform
offset.

Evidence required: the computed list and the stored list, side by side, with the
delta in days on every row.

Prevents failures 3 and 7.

## 6. Print the weekday next to every date

An off-by-one-week error preserves the weekday. Every wrong date in the incident
was still a Friday, which is exactly why eyeballing the list passed it.

The weekday column is not there to catch the week error. It is there to catch the
day error, which is the one the eye does find, and to make the week error's
invisibility explicit rather than accidental.

Prevents failure 7.

## 7. Check every due date against the no-class days

Once the week-late error was corrected, two items landed on a break day.
Correcting one error moved work onto a day with no classes, and nothing checked
for that.

For each due date, look it up in the no-class list from step 1. A collision is
not automatically an error, but it is always a decision for the author. There the
fix was to move the module to the last class day before the break, which gave
that module 9 days instead of 11.

Evidence required: an explicit collision column, filled in for every row,
including the empty ones.

Prevents failure 6.

## 8. Check that the first and last dates fall inside the term

The last two items were due after teaching had ended. Nothing checked that the
schedule ended inside the term, and the syllabus even said so out loud, calling
that date "after teaching ends, so all work must be completed by then," which
reads as a deliberate choice rather than the symptom it was.

Assert two boundaries: no date earlier than the first day of classes, and no date
later than the last day of the term.

Prevents failure 5.

## 9. Cross-check every surface that carries a date

Dates live in five places, and they drift independently.

| Surface | What it carries |
|---|---|
| `modules.yml` | the `due:` field on every assignment and quiz |
| the syllabus page | the Course Outline table plus the schedule prose |
| the welcome page | the Course Schedule bullet |
| `content/announcements/` | announcement bodies, which name their own dates |
| Canvas | edited by hand after import, drifts silently, no API to read it back |

Canvas is the one that cannot be checked from here. Once a course is published,
correcting `modules.yml` does not correct Canvas, and a fresh import does not
either. Say so in the output rather than implying a source fix is a shipped fix.

Prevents failure 4, and the silent divergence that follows any hand edit in
Canvas.

## 10. Read the source comments for unactioned questions before trusting anything

The welcome page carried a note in front matter reading, in effect, "this date
was derived and is probably wrong; ask." A prior session wrote it, correctly, and
nobody acted on it. The wrong dates shipped past a comment that named the exact
defect.

Grep the schedule-bearing files for that class of marker before starting, and
report any you find as part of the output. An unresolved question in the source
is a finding, not context.

Prevents failure 8.

## Output

Produce one table and nothing else. Every assignment, in module order:

| Assignment | Stored date | Proposed date | Weekday | Delta | No-class collision |
|---|---|---|---|---|---|

Include every row even where nothing changes, because a row with a zero delta is
evidence the row was examined. Follow it with the module open dates, the term
boundaries used, and the no-class list quoted from the calendar.

Two of seven modules in that course deviated from the printed rule, for reasons
the calendar supplied. That is the normal shape of a real term, and it is why the
rule alone cannot generate the schedule.

## Hard rule

**Nothing is edited, rendered, committed, or imported until the author approves
the table.**

During the incident the dates were corrected without approval and the corrections
had to be fully reverted. The author's standing rules are explicit: suggest
freely, never act unilaterally; feedback is delivered through questions, not
unilateral action; nothing is written until the user confirms.

This step is where the review ends. Put the table in front of the author and
stop. Approval to review a schedule is not approval to change one, and approval
to change `modules.yml` is not approval to commit it or to rebuild the cartridge.

## Open, not decided: computing dates instead of typing them

Half of this now exists. `course.yml` carries `term:` with `first_day`,
`last_day` and `breaks`, so the term boundaries and the no-class days are
declared data rather than something a reviewer holds in their head.

Computing the due dates from the printed rule is still not built. Every `due:`
in `modules.yml` is a hand-typed literal. An `opens:` date on each module, plus
a rule the build could evaluate, would let it generate the schedule and fail
when a computed date lands on a break day or outside the term. The
seven-days-late error could not have survived that.

The cost is real and it is why this is undecided. It changes the source format,
so `build_cartridge()`, `build_preview()`, and the manifest checks all have to
learn the new fields, and `modules.yml` is often heavily commented with the
reason for each deliberate divergence from the reference export. It also encodes
a rule that real terms already break, so the exceptions need a representation of
their own rather than being typed over the top.

Decide it with the author before building it. Until then this review is the
control, and it has to be run by hand every time a date moves.
