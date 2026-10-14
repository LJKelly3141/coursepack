---
name: course-slides
description: Use when building, drafting or revising a course's reveal.js slide deck and its speaker notes, or when a deck is going to class or into a narrated video. Covers writing each slide with its narration, checking the notes with lecturecast, rendering for an in-person class, and handing a deck to lecturecast for a narrated explainer video. Triggers on "make slides", "build a deck", "draft lecture slides", "add speaker notes", "render the slides", "the slides aren't in docs", "make a video from this deck", "turn the lecture into a video", "where do the videos go", or "is lecturecast set up".
---

# Course slides: built for class and for video

A deck is one `.qmd` under `slides/`. Its speaker notes are written for the ear
from the start, together with the slides, so one set of notes serves both
routes: the instructor presenting in class, and lecturecast voicing a narrated
video. A fix to a slide or a note reaches both.

## Where things are

| What | Path |
|---|---|
| Deck source | `slides/<deck>.qmd` |
| Slide style | `slides/_extensions/` (a deck opts in through its `format:`) |
| Rendered deck | `docs/slides/<deck>.html` |
| Voice settings | `lecturecast.yml` at the course root |
| Videos | `build/video/` |

`docs/` is the published site and is committed, so a video never goes there.
`build/` is in the course's `.gitignore`, so a video there stays out of git.
Where a finished video is published for students is the instructor's decision.

## Is lecturecast here?

In R, `nzchar(system.file(package = "lecturecast"))`. Without it, every step
below still works except the notes check (step 4) and the video route; say
that once and carry on. Slides for class never depend on it. Installing it is
the instructor's decision.

## Building a deck

1. **Outline.** Sections are level-1 headings (`#`), slides are level-2
   (`##`). The title comes from the YAML. Keep the overview or agenda slide
   short, about 20 seconds of narration (around 50 words): name the parts and
   explain each on the slides that show it.
2. **Write each slide and its notes together.** The instructor approves every
   word of the notes. The full writing rules, the table of abbreviations to
   spell out and the chart-cue details are in lecturecast's `lecture-video`
   skill; follow it. In brief:
   - Every slide gets a `::: {.notes}` block, section slides and closing
     slides included. A section slide's notes are a one- or two-sentence
     spoken transition. The title slide's spoken intro goes in the YAML:

         title-slide-attributes:
           data-notes: "Welcome. This lecture is ..."

   - Notes are speech to one listener: contractions, everyday words, one idea
     per sentence, 30 words at most. Spell out abbreviations in the notes
     ("aggregate demand", not AD); the slide text can keep them. No live-room
     language ("click", "turn to your neighbor", "Ask:"); use "Pause and
     think: ..." instead. No "e.g.", "etc." or URLs.
   - **Show, don't tell.** No slide sits still while the voice explains.
     Change the picture at least every 30 seconds of narration: reveal points
     one at a time (`::: {.incremental}` or `::: {.fragment}`), give a long
     chart explanation more steps, or split the slide in two.
   - **Fragments.** Put a line holding only `---` in the notes before each
     point's narration: one more part than the slide has fragment steps, the
     first part spoken before any appears.
   - **Charts.** A chart button plays when the notes quote its label exactly
     ("AD falls"). Never rephrase a quoted label. Buttons need
     `transition: {duration: 0}`. The notes say what plays and describe what
     the viewer is watching, not only the result.
   - **Play the whole, then point at the parts.** A button that plays a
     multi-step story keeps its full-story button, and gets one more button
     per step whose single frame is that step's end state. Step labels are
     short spoken phrases, unique on the slide. The notes quote the full-story
     label first, then each step's label as that step is discussed.
3. **Render.** The course's `_quarto.yml` renders only what its `render:` list
   names. That list is an allowlist on purpose, and a deck is left out until
   someone adds it:

       render:
         - "slides/**/*.qmd"

   Adding that line is the instructor's call, because it makes every deck
   under `slides/` public. Then `quarto render slides/<deck>.qmd` writes
   `docs/slides/<deck>.html`.
4. **Check the notes.** `lecturecast::lint_notes("slides/<deck>.qmd")` lists,
   by slide, what will read badly aloud and where the screen sits still:
   slides with nothing said, chart buttons the notes never quote, and long
   stretches with nothing new on screen. Propose a fix for each flag, apply
   only what the instructor approves, render, and lint again. Stop when what
   is left is deliberate (an abbreviation inside a quoted button label, for
   example). `lecturecast::lecture_script("slides/<deck>.qmd")` shows every
   word as it will be voiced, for a final read-through.

## Route 1: class

Present the rendered `docs/slides/<deck>.html` in a browser. The notes are in
the speaker view.

## Route 2: narrated video

1. **Tools.** `lecturecast::lecturecast_check()` lists Quarto, Chrome, FFmpeg,
   the Edge voice tool and whether `ELEVENLABS_API_KEY` is set. It never
   prints the key.
2. **Voice settings.** `lecturecast.yml` at the course root covers every deck.
   `lecturecast::use_lecturecast(".")` writes a starter file (Edge voice
   en-US-AndrewNeural, videos to `build/video/`) and never overwrites one.
   The voice is a setting, never a fallback, and choosing it is the
   instructor's decision. The ElevenLabs key comes only from the
   `ELEVENLABS_API_KEY` environment variable and never goes in this file.
   Text sent to ElevenLabs leaves the machine, so only material meant for
   students goes in a deck that uses it.

   A suggested starting point for tighter pacing, not yet confirmed by the
   instructor: under `video:`, `lead_in: 0.2`, `tail: 0.3`, `crossfade: 0.4`,
   and `title_card: false` so the deck's own title slide opens the video.
3. **Build.** lecturecast takes the deck's `.qmd`, finds
   `docs/slides/<deck>.html` itself, and stops if that render is missing or
   older than the `.qmd`. It never runs Quarto. Hand off to the
   `lecture-video` skill, which lecturecast ships and
   `coursepack::install_skills()` copies into `.claude/skills/` when
   lecturecast is installed. It previews changed slides and builds the video.

## Common mistakes

- **Notes written for the room.** "Click here" and "Ask:" do not work in a
  video. Write for the listener from the start.
- **A slide that sits still.** A minute of narration over an unchanging slide
  loses the viewer. Add steps or split it.
- **Rendering the video from a stale deck.** lecturecast stops when the
  `.qmd` is newer than the `.html`. Render, then build again.
- **Writing a video into `docs/`.** It would be committed and published. Use
  `build/video/`.
- **Adding the deck to `render:` without asking.** It publishes the deck.
- **Switching voices when one fails.** A failed voice stops the build. Report
  the message; do not change `provider:`.
