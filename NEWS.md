# coursepack 0.1.0

* Schema: `published:` on items, `item_id:`, `module_id:`, `resource_id:` overrides, `height_measured:`, `source:` in `reference.yml`.
* Iframe pages use one titled template with a fallback link, a video allow-list, and a required height.
* Grading standard and late policy are optional; `canvas:` keys come from one known-key list and an unknown key stops the build.
* Emit every declared assignment group and route assignments and quizzes by group name.
* Due dates: `due_time:` in `course.yml`; `due:` accepts a clock time; seconds now match Canvas (`:59`).
* `build_preview()`; mockup templates ship in `inst/templates/mockup/`; the sibling-layout textbook fallback is gone.
* `build_qti()`; output goes under `proj`.
* `build_cartridge()` moved, split across seven files along the script's own banners; due dates route through `local_to_utc()`; the filename is `<slug>-<date>.imscc`.
* `diff_against_reference()`; the reference export and the declared divergences move to `reference.yml`.
* `check_manifests()`; counts come from `reference.yml` and are fatal when declared; new assignment-group check.
* Body helpers moved; `LEAK_CANARY` and `ANSWER_KEY_HEADING_RE` are package constants and not yet configurable.
* `interp_urls()`, `chapter_url()`, `resolve_target()`, `collect_refs()` moved from `scripts/lib/resolve.R`.
* The byte gate: `gate_check()`, `tree_hashes()`; `tools/baseline.R`; the first expected tree from the frozen builder.
* Synthetic fixture course, fake textbook, sample QTI, and the skip helpers.
* Timezone helper: `local_to_utc()`, `parse_when()`, `due_stamp()`; replaces the fixed UTC-5 arithmetic and the 2026-11-01 stop.
* `%||%` is defined once, in `R/utils.R`.
* `coursepack_version()` and the closing version line every entry point prints.
* Config readers: `read_manifest()`, `read_announcements()`, `read_timezone()`, `textbook_docs_path()`, `course_slug()`.
* `course_tile()` writes no PNG `tIME` chunk, so a given course renders byte-identically every time.
