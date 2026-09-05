# coursepack 0.0.0.9011

* `build_preview()`; mockup templates ship in `inst/templates/mockup/`; the sibling-layout textbook fallback is gone.

# coursepack 0.0.0.9010

* `build_qti()`; output goes under `proj`.

# coursepack 0.0.0.9009

* `build_cartridge()` moved, split across seven files along the script's own banners; due dates route through `local_to_utc()`; the filename is `<slug>-<date>.imscc`.

# coursepack 0.0.0.9008

* `diff_against_reference()`; the reference export and the declared divergences move to `reference.yml`.

# coursepack 0.0.0.9007

* `check_manifests()`; counts come from `reference.yml` and are fatal when declared; new assignment-group check.

# coursepack 0.0.0.9006

* Body helpers moved; `LEAK_CANARY` and `ANSWER_KEY_HEADING_RE` are package constants and not yet configurable.

# coursepack 0.0.0.9005

* `interp_urls()`, `chapter_url()`, `resolve_target()`, `collect_refs()` moved from `scripts/lib/resolve.R`.

# coursepack 0.0.0.9004

* The byte gate: `gate_check()`, `tree_hashes()`; `tools/baseline.R`; the first expected tree from the frozen builder.

# coursepack 0.0.0.9003

* Synthetic fixture course, fake textbook, sample QTI, and the skip helpers.
* Timezone helper: `local_to_utc()`, `parse_when()`, `due_stamp()`; replaces the fixed UTC-5 arithmetic and the 2026-11-01 stop.

# coursepack 0.0.0.9002

* `%||%` is defined once, in `R/utils.R`.
* `coursepack_version()` and the closing version line every entry point prints.
* Config readers: `read_manifest()`, `read_announcements()`, `read_timezone()`, `textbook_docs_path()`, `course_slug()`.
