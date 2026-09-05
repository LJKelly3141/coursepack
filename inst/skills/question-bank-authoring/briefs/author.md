# Author brief: Chapter {{chapter}} question bank

You are authoring the Chapter {{chapter}} multiple-choice question bank from
{{source_name}}. Work only inside the course repository, and only on the files
named below. Do not run git. Do not edit any existing file. Do not touch
`modules.yml`, `course.yml`, or anything under `content/`, `assets/`, or
`docs/`.

Use these exact section names. They must match the course manifest character
for character:

{{sections}}

## Step 1: read the full text (required, measured)

Fetch each page with the skill's helper, which writes the page body to a text
file and refuses any page under 300 words:

    python3 .claude/skills/question-bank-authoring/scripts/fetch_openstax.py <URL> <out.txt>

Write the text files into `build/bank/ch{{chapter}}/` (create the directory).
Fetch every section page listed above, plus the chapter's key concepts page
and its key terms page.

The key terms page is often short and may trip the 300-word floor; that
refusal is expected for that one page. Read whatever content came through, or
read the key terms as they appear at the end of the section pages. Every other
page must clear the floor. If a fetch fails, retry once; if it still fails,
stop and report which page failed.

Read every text file completely before writing a single question. Record each
page's word count for the report. Do not write questions for a section you
have not read in full.

## Step 2: write `{{bank_dir}}/chapter_<NN>.json`

`<NN>` is {{chapter}} padded to two digits. Match the schema of a chapter file
already admitted into `{{bank_dir}}/` exactly, and read that file first; it is
the pattern. Top level: `chapter` ({{chapter}}), `title`, `source` (the book
and edition, with the date the sections were read), `sections` (a list of
`{section, questions}`). Each question: `id` (integer, unique across the
chapter, increasing in file order from 1), `type` `"multiple_choice"`,
`difficulty` (`recall`, `application`, or `analysis`), `objective` (one
sentence, what the item tests), `question`, `options` `{A, B, C, D}`, `answer`
(one letter), `explanation` (why the key is right, why the strongest
distractors are wrong, ending with the section number, for example
`"Section {{chapter}}.2."`), `image` (null, or the PNG file name), `figure`
(null, or `{file, script, alt}`).

Counts, exact: 12 questions per section. Per section: 5 recall, 5 application,
2 analysis. Per section the key letters are exactly 3 A, 3 B, 3 C, 3 D, and
the keyed letter of consecutive items should not form an obvious pattern (no
letter twice in a row).

Chapter guidance: [one paragraph, written for this chapter: the ideas the
items must cover, and the figures the chapter calls for.]

Question rules, all of them:

1. Exactly one correct answer. Four options, all distinct, all grammatically
   parallel with the stem.
2. Distractors are real misconceptions or plausible errors a student would
   actually make. Never filler.
3. No "all of the above", "none of the above", "both A and B". No negatively
   phrased stems unless the word NOT is capitalized and essential; keep those
   to two or fewer per section.
4. No reference to "the text", "the textbook", "the chapter", the publisher by
   name, or any figure or table number from the book, in any stem or option.
   The item must stand on its own.
5. Option-length rule: the keyed option may not be longer than every distractor
   by more than 15 percent, and the key may be the single longest option in at
   most a quarter of the chapter's items. Write the distractors as fully as the
   key.
6. Leakage rule: no stem, option, or explanation may state or give away the key
   of another item in the same section or anywhere in the chapter. In
   particular, do not state a mechanism as a premise in one stem when a
   neighboring item asks for that mechanism; and do not let a figure's title,
   axis label, legend, or caption state another item's key. Before you finish,
   scan every stem and every figure label against every other item's keyed
   option.
7. Arithmetic works out cleanly. Present givens in an HTML table inside the
   question string where there are more than two numbers (use `<table>` with
   `<th scope="col">` headers), and make the numbers round. Use constructed
   data, never real-world figures presented as current.
8. Application items ask the student to compute, apply, or classify; analysis
   items ask the student to reason about a change, compare two situations, or
   judge a claim. Recall items test definitions and stated relationships.
9. Cover the whole section, not just its first half. Each section's 12 items
   should touch every major idea in it.
10. Explanations are complete sentences, name why the key is right, address the
    strongest distractor, and end with the section number.

## Step 3: figures

Draw at least two figures, and more where the chapter guidance calls for them.
For each figure:

- A Python script at `{{bank_dir}}/figures/CH<NN>_Qnnn.py` where `nnn` is the
  zero-padded id of the question that uses it (for example `CH<NN>_Q017.py`).
  matplotlib and numpy only. Read an existing figure script under
  `{{bank_dir}}/figures/` first and follow its conventions, including the
  savefig path `{{bank_dir}}/images/CH<NN>_Qnnn.png`, white background, labeled
  axes, values labeled where the question depends on reading them. Axis labels
  and titles say what is measured; they never state a conclusion an item asks
  for.
- Run the script so the PNG exists at `{{bank_dir}}/images/CH<NN>_Qnnn.png`.
  Then open the PNG with the Read tool and confirm it shows what the question
  needs, with no overlapping labels.
- The question's `image` field is the file name (`CH<NN>_Qnnn.png`), and
  `figure` is `{file, script, alt}`. The alt text must describe the figure
  completely enough that the question could be answered from the alt text
  alone: every curve, every labeled point or value, the direction of every
  shift.
- The question must be answerable from the figure alone, without outside data.
  A figure may serve two items (one application, one analysis) if both are
  answerable from it.

## Step 4: self-check, then report

Run the measurement script and fix anything it flags before you finish:

    python3 .claude/skills/question-bank-authoring/scripts/measure_bank.py {{bank_dir}} {{chapter}}
    python3 .claude/skills/question-bank-authoring/scripts/bank_checks.py {{bank_dir}} {{chapter}}
    Rscript -e 'b <- coursepack::read_bank("{{bank_dir}}", {{chapter}}); coursepack::check_bank(b, file.path("{{bank_dir}}", "images"))'

Also run a leakage scan yourself: for every item, check whether any other
item's stem, options, or figure labels contain the substance of this item's
keyed option (a script that lowercases and compares four-word and three-word
windows is fine; then read the hits by eye). Fix leaks by rewriting the leaking
stem or label, never by weakening the key.

Write `{{bank_dir}}/report_chapter_<NN>.md`, following an existing report in
`{{bank_dir}}/` as the pattern (the Write tool may refuse `.md` files; use a
shell heredoc if so): source pages read with word counts, question counts and
difficulty mix by section, key-letter counts by section, the option-length
check, the leakage scan result, the figures list, and anything you were unsure
about.

Your final message must contain: the full output of `measure_bank.py`, the
leakage scan result, the list of figure files created, the word count table,
and any item you are not confident about with the reason. Do not summarize the
questions; the file will be read.

Rules of conduct: no em-dashes anywhere in student-facing text (stems, options,
explanations, alt text, figure labels); use commas or separate sentences. Do
not mention AI or any tool in the report or the bank. If you run out of budget,
write what you have, make the JSON valid, and say exactly which sections are
complete.
