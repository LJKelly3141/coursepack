# questions/

Question banks, one JSON file per chapter, named `chapter_01.json` upward.
Figures live under `questions/images/` and are named by each question's `image`
field.

**Never rendered.** This directory is absent from the `project: render:` list in
`_quarto.yml`, the same way `assessments/` is, so nothing here reaches `docs/`.
A bank holds the correct answer to every question in it.

## The schema

```json
{
  "chapter": 1,
  "title": "Chapter title",
  "source": "where the questions were written from",
  "sections": [
    {
      "section": "Section title",
      "questions": [
        {
          "id": 1,
          "type": "multiple_choice",
          "difficulty": "easy",
          "objective": "what the item tests",
          "question": "The stem, as HTML.",
          "options": {"A": "...", "B": "...", "C": "...", "D": "..."},
          "answer": "B",
          "explanation": "why B, and why the others are wrong",
          "image": "optional-figure.png",
          "figure": {"file": "optional-figure.png", "script": "make_figure.R",
                     "alt": "what the figure shows"}
        }
      ]
    }
  ]
}
```

A stem is HTML, so `<br>`, `<em>` and `<table>` in it are content rather than
mistakes. Ids are whole numbers and unique within a chapter: the item identifier
Canvas receives is derived from the chapter, the section and the id, so two
questions sharing an id collapse into one item.

## What is refused, and what is only reported

`check_bank()` refuses a type other than `multiple_choice`, a question with
fewer than two options, an answer naming no option, a duplicate id, and an
`image` naming a file that is not under `images/`. A figure with no alt text is
reported as a warning instead: the item still renders, so the build carries on
and the author is told what to write.

## Drawing a quiz from a bank

A `quiz:` in `modules.yml` declares a `bank:` block naming the chapters, the
draws per group, and the total points. The draws have to sum to the points and
no draw may be larger than the group it comes from; all of that is checked by
`make checkyml`, before anything is built.

`make paper ID=<quiz id> SEED=<number>` prints one fixed form of that draw, with
its answer key beside it, for a make-up sitting or a proctored room.
