# Reviewer brief: Chapter {{chapter}} question bank

You are the independent reviewer for the Chapter {{chapter}} multiple-choice
question bank, written from {{source_name}}. You did not write this bank. Your
job is to find every defect in it and specify the exact fix. Do not edit
`{{bank_dir}}/chapter_<NN>.json` (`<NN>` is {{chapter}} padded to two digits),
the figure scripts, or the PNGs. Do not run git. Your only output file is
`{{bank_dir}}/review_chapter_<NN>.json`.

## Step 1: read the source text yourself

Fetch every page fresh with the skill's helper (it writes the page body to a
text file and refuses pages under 300 words; the key terms page is often
legitimately short, so for that one page the refusal is expected and you should
read the content that comes through or fall back to the key terms at the end of
the section pages):

    python3 .claude/skills/question-bank-authoring/scripts/fetch_openstax.py <URL> <out.txt>

Write into `build/bank/review/ch{{chapter}}/` (create it). Fetch every section
page below, plus the chapter's key concepts page and its key terms page:

{{sections}}

Read every file completely before judging any item. Then read
`{{bank_dir}}/chapter_<NN>.json` in full, every figure script under
`{{bank_dir}}/figures/` named `CH<NN>_*.py`, and open every PNG under
`{{bank_dir}}/images/` named `CH<NN>_*.png` with the Read tool and look at it.

## Step 2: check every item against eight criteria

For each item:

1. **Key correct.** Quote the sentence or passage from the text that
   establishes the keyed option. If you cannot quote support, the item does not
   pass.
2. **Single defensible answer.** Each distractor must be clearly wrong to a
   student who knows the section. Flag any distractor that is arguably correct,
   or any stem that admits two readings.
3. **Agreement with the text.** No factual error, no claim the text
   contradicts, no claim the text does not make presented as settled. If the
   source page contradicts itself anywhere (a misprinted equation, a figure that
   disagrees with the prose), determine the correct form from the prose and the
   key concepts page, check every item that touches it, and report the misprint.
4. **Arithmetic recomputed.** For every item with numbers, redo the computation
   from the givens in the stem or table and confirm the keyed option and that no
   distractor equals a correct alternative computation. Record the computation.
5. **Figure integrity.** For every figure item: the PNG matches what the script
   draws, the alt text states every curve, labeled value, and shift the question
   relies on, the question is answerable from the figure alone, and no title,
   axis label, legend, or caption states another item's key. Flag any value in
   the alt text that disagrees with the script's data.
6. **Stands alone.** No stem or option refers to the text, the textbook, the
   chapter, a book figure or table, or the publisher by name. No "all of the
   above" or "none of the above". Negative stems only with NOT capitalized, at
   most two per section.
7. **Option-length rule.** The keyed option is not longer than every distractor
   by more than 15 percent (character count), and across the chapter the key is
   the single longest option in at most a quarter of the items. Compute this
   yourself with a script and report the counts.
8. **Leakage.** No stem, option, figure label, or explanation gives away
   another item's key in the same section or chapter. Run a phrase-overlap scan
   (keyed option of each item against stems, options, and figure labels of every
   other item, lowercased, four-word and three-word windows) and then read every
   hit by eye. For each real leak, rule fix or leave with a reason, and give the
   exact rewrite; close leaks by rewriting the leaking stem or label, or by
   adding a parallel distractor on the target item, never by weakening the key.

Also read the author's own notes in `{{bank_dir}}/report_chapter_<NN>.md`, the
section on items the author was not confident about, and rule on each one
explicitly.

## Step 3: write `{{bank_dir}}/review_chapter_<NN>.json`

Match the structure of an existing review file in `{{bank_dir}}/` (read it
first; ignore its recheck and confirmed_fixes blocks, which are added after
fixes). Top level: `chapter` ({{chapter}}), `reviewer_read` (list of every file
you read, with word counts for the text files), `summary` `{pass, fix, reject,
leakage_rulings {fix, leave}}`, `leakage_check` (a list of rulings, each with
`cue`, `target`, `should_fix`, `ruling`, `exact_change`), and `questions`: one
entry per item with `id`, `section`, `verdict` (`"pass"`, `"fix"`, or
`"reject"`), `key_correct`, `evidence` (the quoted text), `issues` (list),
`required_change` (null, or the exact replacement wording: the full new stem,
option, or explanation text, so the author can apply it without judgment),
`arithmetic_check`, `figure_check`.

Verdicts: `"pass"` means no change needed. `"fix"` means the item is sound once
the `required_change` is applied. `"reject"` means the item cannot be repaired
by a wording change and must be replaced; say why. Do not mark cosmetic
preferences as fixes; a fix is something that would make a knowledgeable
student miss the item, teach something wrong, or violate one of the eight
criteria.

If the Write tool refuses the file, write it with a shell heredoc through
python3 so the JSON is validated on write.

## Final message

Report, in this order: the summary counts (pass, fix, reject); each fix as one
line (id, criterion, ten-word reason); each reject with the reason; the leakage
rulings (fix and leave counts, and the cue for each fix); the option-length
counts you computed; any misprint you found in the source; your ruling on each
of the author's flagged items; the list of files you read. Do not paraphrase
items you passed.

Conduct: no em-dashes in any wording you propose for stems, options,
explanations, alt text, or figure labels; use commas or separate sentences. Do
not mention AI or any tool in the review file. If you run out of budget, write
the review for the items you completed, make the JSON valid, and state exactly
which ids are unreviewed.
