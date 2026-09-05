---
name: strip-ai-characters
description: "Find and remove characters that mark text as machine-generated, and replace them with standard ASCII. Triggers on 'strip ai characters', 'check for hidden characters', 'find hidden text', 'smart quotes', 'zero width', 'invisible characters', 'clean up unicode', 'does this look AI generated', or before shipping anything student-facing or submitted. Dry run by default; nothing is written without an explicit instruction."
---

# Strip the characters that give away a machine

Some characters almost never come from a person typing. Smart quotes, a Unicode
ellipsis, a non-breaking space, and above all the zero-width characters. They
survive copy and paste, they are invisible in most editors, and they travel into
anything the text is pasted into.

This skill finds them and replaces them with what the author would have typed.

## Run it

```bash
python3 .claude/skills/strip-ai-characters/scan_characters.py            # report
python3 .claude/skills/strip-ai-characters/scan_characters.py --show     # report, with lines
python3 .claude/skills/strip-ai-characters/scan_characters.py --write    # apply
python3 .claude/skills/strip-ai-characters/scan_characters.py PATH ...   # narrow the scope
python3 .claude/skills/strip-ai-characters/scan_characters.py --skip bak # skip a directory
```

Those paths are where the skill lands in a course: `coursepack::install_skills(".")`,
or `make skills` in the scaffold, copies the shipped skills into `.claude/skills/`
and stamps the package version at the bottom of each `SKILL.md`.

With no path named it scans the current directory. **Dry run by default.** It
prints what it would change and changes nothing. `--write` applies the safe tier
only. It never commits.

## The two tiers, which are the whole design

**Tier 1, replaced.** Characters with no legitimate use in this project's source.

- Smart quotes and apostrophes, `’ ‘ “ ” ‚ „ ′ ″`, become `'` and `"`. Quarto
  produces typographic quotes at render time, so the source should carry the
  straight forms.
- The ellipsis character becomes three periods.
- Every non-standard space becomes a normal space.
- Every invisible character is deleted outright: zero-width space, zero-width
  joiner and non-joiner, word joiner, soft hyphen, byte order mark, the
  directional marks, and the invisible math operators.

**Tier 2, reported and never touched.** Characters that are sometimes right.

- **Em dash.** House rules often forbid new ones and grandfather old ones;
  rebuilding a sentence is a judgement no script can make. So these are listed
  and left alone, always.
- **En dash.** Correct in a number range. A tell anywhere else.
- **Unicode minus sign.** Correct in rendered math, wrong in prose and code.

Everything else non-ASCII is left alone and not even reported: Greek letters,
currency symbols, mathematical operators, superscripts and subscripts, the box
drawing characters that make folder trees in a chapter, and accented letters in
author names in the `.bib` files. A tool that flagged `β` or `£` here would be
crying wolf.

## What it will not touch

- **Anything outside the paths you name, or outside the current directory when
  you name none.**
- **`docs/`, `_book/`, `build/`, `site_libs/`, `.quarto/`.** Generated. A
  character there is a symptom; fix the source and re-render.
- **Anything named with `--skip`.** Two cases that come up repeatedly:
  `--skip chapter_notes` for recorded review transcripts, which are a record of
  what someone actually said and would be falsified by an edit, and
  `--skip bak` for superseded drafts.

## After running with `--write`

Review with `git diff` before committing. The script says so and commits nothing.

Two checks worth doing on a diff this wide:

1. **Did an apostrophe change inside an R string or a file path?** Straight
   quotes are what R wants, so this is a fix rather than a risk, but look.
2. **Re-render before committing.** Where `docs/` is tracked, a source fix is not
   a shipped fix until the render is committed too.
