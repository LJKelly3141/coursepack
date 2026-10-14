---
name: course-slides
description: Use when a course's reveal.js slide deck is going to class or into a narrated video. Covers rendering a deck for an in-person class and handing a deck to lecturecast to make a narrated explainer video. Triggers on "render the slides", "the slides aren't in docs", "make a video from this deck", "turn the lecture into a video", "where do the videos go", or "is lecturecast set up".
---

# Course slides: for class, or into a video

A deck is one `.qmd` under `slides/`, and it has two routes. Both start from the
same source, so a fix to a slide reaches the class and the video alike.

1. **In-person class.** Render the deck and present it in a browser.
2. **Narrated video.** Hand the rendered deck to lecturecast, which voices each
   slide's speaker notes and writes an MP4, captions and a transcript.

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

## Route 1: render for class

The course's `_quarto.yml` renders only what its `render:` list names. That list
is an allowlist on purpose, and a deck is left out until someone adds it:

    render:
      - "slides/**/*.qmd"

Adding that line is the instructor's call, because it makes every deck under
`slides/` public. Then `quarto render slides/<deck>.qmd` writes
`docs/slides/<deck>.html`.

## Route 2: narrated video

1. **Is lecturecast installed?** In R, `nzchar(system.file(package = "lecturecast"))`.
   If it is `FALSE`, videos are unavailable on this machine. Say so and stop;
   installing it is the instructor's decision. Nothing else in the course
   depends on it.
2. **Are the tools there?** `lecturecast::lecturecast_check()` lists Quarto,
   Chrome, FFmpeg, the Edge voice tool and whether `ELEVENLABS_API_KEY` is
   set. It never prints the key.
3. **Voice settings.** `lecturecast.yml` at the course root covers every deck.
   `lecturecast::use_lecturecast(".")` writes a starter file (Edge voice
   en-US-AndrewNeural, videos to `build/video/`) and never overwrites one.
   The voice is a setting, never a fallback, and choosing it is the
   instructor's decision. The ElevenLabs key comes only from the
   `ELEVENLABS_API_KEY` environment variable and never goes in this file.
   Text sent to ElevenLabs leaves the machine, so only material meant for
   students goes in a deck that uses it.
4. **Render the deck first** (route 1). lecturecast takes the deck's `.qmd`,
   finds `docs/slides/<deck>.html` itself, and stops if that render is
   missing or older than the `.qmd`. It never runs Quarto. Render again
   after any change to the notes.
5. **Hand off to the `lecture-video` skill.** lecturecast ships it, and
   `coursepack::install_skills()` copies it into `.claude/skills/` when
   lecturecast is installed. It reviews the speaker notes with the instructor,
   since every word is voiced as written, and then builds the video.

## Common mistakes

- **Rendering the video from a stale deck.** lecturecast stops when the
  `.qmd` is newer than the `.html`. Render, then build again.
- **Writing a video into `docs/`.** It would be committed and published. Use
  `build/video/`.
- **Adding the deck to `render:` without asking.** It publishes the deck.
- **Switching voices when one fails.** A failed voice stops the build. Report
  the message; do not change `provider:`.
