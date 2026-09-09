# slides/

The UWRF slide style, packaged as a Quarto reveal.js format extension. It
carries the university brand: Passion Red headings in Impact, Arial body text,
a white background, the UWRF logo in the corner, and the table, list, and
callout styling used across department and course decks.

## Use it in a course

1. Copy `_extensions/` into the directory that holds the deck sources. Quarto
   looks for `_extensions/` beside the document or at the project root.

   ```
   cp -r inst/templates/slides/_extensions  <course>/slides/
   ```

2. Set the format on each deck. Everything else (theme, logo, slide numbers,
   linear navigation, 1280 by 720, embedded resources) comes from the
   extension.

   ```yaml
   ---
   title: "Week One"
   subtitle: "How this course works"
   author: "Instructor Name"
   format:
     uwrf-revealjs:
       footer: "<course>, <term>"
   ---
   ```

   Any reveal.js option can be set under `uwrf-revealjs:` and overrides the
   extension's default.

## Classes the style provides

A `#` heading makes a divider slide, and divider slides show no logo.

| Class | Where | What it does |
|---|---|---|
| `.section-header` | on a `#` heading | red divider slide with a white title, footer, and slide number |
| `.callout-box` | a fenced div | short takeaway with a red rule down the left |
| `.two-column` | a fenced div | two equal columns, as an alternative to Quarto's `.columns` |
| `.highlight-stat` | a fenced div | big-number stat callout; inside it use `.big-number`, `.stat-label`, or a `.stat-row` of `.stat-item` with `.number` and `.label` spans |
| `.impact-label` | a span | small uppercase red label above a paragraph |
| `.status-green`, `.status-yellow`, `.status-red` | a span | bold colored status word |
| `.small-table` | a div around a table | shrinks a wide table to fit |
| `.smaller` | on a `##` heading | Quarto's smaller slide; tables inside scale with it |
| `.num` | a `td` or `th` | right-aligns a numeric cell; other cells align left |
| `.sr-only` | a table `caption` | caption read by screen readers, not shown |
| `.slide-footer-band` | a div | source line or note at the bottom of a slide |

## Files

| File | Role |
|---|---|
| `_extensions/uwrf/_extension.yml` | registers the `uwrf-revealjs` format and its defaults |
| `_extensions/uwrf/uwrf.scss` | brand colors, fonts, and the classes above |
| `_extensions/uwrf/uwrf-logo.png` | the logo shown on every slide but the dividers |
| `_extensions/uwrf/divider.html` | the script that lets the style tell a divider slide from the rest |

The style was extracted from the Economics Department's 2026 Program Audit and
Review deck. Components specific to that deck (faculty grid, faculty profile,
research cards, impact slide) were left out.
