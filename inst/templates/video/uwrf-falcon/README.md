# UWRF video themes: falcon and falcon_light

Two looks for Manim-built lecture videos, kept beside the UWRF slide style
(`inst/templates/slides/_extensions/uwrf/`). They were picked from a storyboard
of seven looks made for the "Statistics in Motion" series.

## Files

- `rwsr_style.py`: the Manim style module. Its `THEMES` dict holds all seven
  storyboard looks; these two are the keys `falcon` and `falcon_light`. The
  theme is chosen by the environment variable `RWSR_THEME` (default `paper`).
  The band-style `heading()` and the `TitleCard` changes are in the same file.
- `series_cards.py`: mock-up series intro (about 6 s) and outro (about 5 s)
  scenes, `SeriesIntro` and `SeriesOutro`, that follow the active theme.

Render with, for example:

    RWSR_THEME=falcon manim -qh series_cards.py SeriesIntro

Sample frames, contact sheets (`sheet_falcon.png`, `sheet_falcon_light.png`),
the rendered intro and outro clips and the storyboard of all seven looks are
kept with the project notes, not shipped: `project/video-themes/uwrf-falcon/`.

## Colours

Roles: PAPER background, INK text, OLIVE secondary and notes, TEAL primary
(median), RUST accent (mean), THIRD a third series (mode).

| Role  | falcon (dark) | falcon_light |
|-------|---------------|--------------|
| PAPER | #141414       | #FFFFFF      |
| INK   | #FFFFFF       | #141414      |
| OLIVE | #A9A9A9       | #6B6B6B      |
| TEAL  | #41C7F4       | #1593C4      |
| RUST  | #E8325F       | #D31144      |
| THIRD | #F5F5F5       | #8F181A      |

Fonts in both: Avenir Next for body text, DIN Condensed in capitals for headings.

Headings use the "band" treatment in both themes: white condensed capitals on a
red #D31144 bar across the top left of the frame. The bar has a slanted right
end, followed by a thin slanted sky-blue #41C7F4 stripe. The heading group
includes an invisible mirror point so it stays centred on x = 0, and scenes that
place content with `next_to(title, DOWN)` do not drift left. On the intro and
outro the series name sits in white capitals on a red #D31144 rectangle.

## Source of the colours

Measured from the UWRF "Brand Standards Guide for Recognized Student
Organizations" (2024),
<https://students.uwrf.edu/sites/default/files/2024-09/24-1695%20RSO%20Brand%20Standard%20Guide_8.5x11%20REV1.pdf>:
red #D31144, dark red #8F181A, sky blue #41C7F4. The guide's display face is a
condensed bold font, so DIN Condensed stands in for it; its body font, Gotham,
is not installed, so Avenir Next stands in.

These differ from the slide style's colours, which came from a department
presentation (red #BE0F34, dark red #8F010A, blue #2EC7FF).

The themes use no UWRF logos, wordmarks, falcon marks or university name; the
guide says those marks are trademarked. UMC offers a brand review at
<https://students.uwrf.edu/umc/request-brand-review>.
