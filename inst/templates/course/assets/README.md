# assets/

**Everything here is public.**

`_quarto.yml` declares `assets/**` under `resources:`, so every file in this
directory is copied into `docs/` verbatim and served to anyone with the URL.
Putting a file here publishes it. There is no check that will stop you, and the
answer-key canary cannot help: everything here is supposed to ship, so a canary
would fire on every correct build.

| Directory | What goes in it |
|---|---|
| `data/` | datasets students download and work with |
| `images/` | figures, and `course-tile.png`, which `make tile` writes |
| `files/` | handouts, templates, anything else a student downloads |

Link to these from the cartridge by their published URL, never by a path inside
the cartridge. `{site}/assets/data/example.csv` in `modules.yml` resolves
against `urls: site:` in `course.yml`, so the address is written once.

Anything a student should not have before the sitting belongs in `assessments/`,
which is never rendered and never copied.
