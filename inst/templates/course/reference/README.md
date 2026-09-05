# reference/

Canvas exports. **Read-only.** Never delete one, never regenerate one, never
tidy one up. An export is evidence about what Canvas actually produced and
accepted, which is not always what the standards documents say.

A new course has none, and `reference.yml` is not written until it does.
`make refdiff` says so and carries on.

## Getting one

In Canvas, open the course, then Settings, then Export Course Content. Choose
Course, start the export, and download the `.imscc` file when it is ready. Put
it here, commit it, and name it in `reference.yml` at the repository root.

The export is a zip. Read it without unpacking it into the repository:

```
unzip -l reference/<name>.imscc
unzip -q reference/<name>.imscc -d /tmp/cc
```

The files worth opening first are `imsmanifest.xml`, which declares every
resource, and `course_settings/module_meta.xml`, which is the live module tree
that `modules.yml` has to be able to reproduce.

## `reference.yml`

```yaml
export: reference/<name>.imscc
source: reference/<name>.imscc
counts:
  modules: 9
  items: 72
divergences:
  - match: "a substring of the reported difference"
    why: "why this one is expected"
```

**`export:`** is the cartridge `make refdiff` compares a fresh build against.
It answers one question: what did this build change that nobody meant to
change? The comparison is structural, matching items on title and content type,
because Canvas regenerates every identifier on import, so identifiers always
differ and that is never a finding. A divergence that is expected is declared
under `divergences:` with the reason, and anything undeclared fails.

**`source:`** is the cartridge a definition's `source_ref:` carries bytes out
of. It is how a course that already exists in Canvas keeps a page or an
assignment exactly as it was rather than regenerating it: the file travels into
the new cartridge unchanged apart from its title and its due date. `export:` is
the fallback when `source:` is absent, because a course usually carries out of
the same export it diffs against and should not have to name it twice.

**`counts:`** is a structural expectation. Present, `make checkyml` enforces it
and a manifest that has lost a module fails before anything is built. Absent,
the counts are printed and the check reports that it skipped.

## Two exports, two jobs

A course that has been through a round trip ends up with two files here, and
they are not the same kind of thing.

The **specification** is a real export of the live course. Divergence between a
generated cartridge and this one is a bug in the generator.

The **verification evidence** is a generated cartridge that was imported into a
throwaway shell and exported straight back out. It exists to answer what Canvas
silently dropped. A clean import log proves nothing, because Canvas discards
malformed content without reporting it, and nobody notices one missing item in
seventy by looking. Diffing the re-export against what went in does. Do not
treat this file as a specification: it is not a course anyone taught.
