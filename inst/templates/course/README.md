# {{code}}: {{title}}

Plain-text source for a course: the module structure Canvas imports, the pages
the site publishes, and the assessments neither of them ever sees.

Three commands do the work. `make site` renders the public site into `docs/` and
checks that no answer key came with it. `make mockup` shows the module tree in a
browser so the ordering can be read before anyone imports it. `make coursepack`
builds the Canvas cartridge and diffs it against the reference export.

Content goes in `content/pages/` for pages the site renders and Canvas frames,
`content/canvas/` for bodies authored as raw Canvas HTML, `assets/` for anything
students download, `assessments/` for quizzes and exams, and `questions/` for
question banks. `course.yml` and `modules.yml` are the two manifests everything
is generated from.

`assessments/` and `questions/` are never rendered and never public. `assets/`
and `docs/` always are. `make leakcheck` is what keeps the line where it is.

The toolchain is the coursepack R package; `make install-toolchain` installs it.
A zip that builds proves nothing: import it into a throwaway Canvas shell and
look.
