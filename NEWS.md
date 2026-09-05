# coursepack 0.2.0.9002

* The accessibility audit's target discovery and source checks moved into the package: `discover_target()`, `intended_surfaces()`, `check_filename_alt()`, `check_missing_fig_alt()`, `check_colour_only()`, `contrast_ratio()`, and `suggest_passing_colour()`. `exclude` stays a required argument on both source checks, and `assessments` stays on the source exclusion list as a containment rule.
* `glob_to_regex()` was copied byte for byte. Its three wildcard sentinels are the literal control characters U+0001, U+0002 and U+0003, which most editors render as nothing; the ported glob assertions fail loudly if an editor ever strips them.
* Their tests are ported from the snapshot's audit test script. The section that ran discovery against whatever real repository an environment variable pointed at is replaced by the `pair/alpha` fixture with a `_quarto.yml` written into a copy of it, asserting the framework reads as `quarto`, that discovery finds real pages rather than zero, that every page sits at the output root, and that nothing under a declared pass-through copy is counted as a page.
* Two further assertions wait on libraries that have not moved yet and are named in place: the three cartridge-bearing fixtures in the declared-surfaces negative control call the cartridge library, and four assertions in the pass-through-exclusion section read the audit driver's own source.

# coursepack 0.2.0.9001

* The accessibility audit's serving and finding-model libraries moved into the package: `serve_dir()`, `pa11y_raw()`, `finding()`, `write_findings()`, `read_findings()`, `diff_findings()`, and the axe-core criterion tables behind them. `serve_dir()` now refuses when `python3` is absent and `pa11y_raw()` when `npx` is, instead of failing later with a tool error nobody can read.
* Their tests are ported from the snapshot's audit test script. Three assertions wait on libraries that have not moved yet and are named in place: the fixture-driven distinct-id section (it calls the custom checks), the M11 no-criterion section (it renders a report), and the static coupling to the driver in the dedup collision negative control. The distinct-id property is asserted at the finding-model layer in the meantime, and the M12 page-count contract is asserted against `write_findings()` directly rather than through the driver's metadata builder.

# coursepack 0.2.0

The builder has converged: every output change since 0.1.0 was made on purpose, with the byte gate regenerated in its own commit each time.

* `writef()` forces its text before opening the file, so a stop inside a body builder no longer leaves a connection open.
* Every build reports its iframe heights as undated, stale, fresh or unmappable; an unmappable height is counted, never silently exempt.
* The pre-zip scan guards the Canvas marker file and the manifest header tokens; `announcements.yml` may omit `term:` and read the zone and window from `course.yml`.
* `textbook_docs: none` is threaded through the builder and the preview; local previews serve the course's own `docs/` as `/site`.
* The homework intro and submission note come from `course.yml`; no course prose remains in package code.
* Schema: `published:` on items, `item_id:`, `module_id:`, `resource_id:` overrides, `height_measured:`, `source:` in `reference.yml`.
* Iframe pages use one titled template with a fallback link, a video allow-list, and a required height.
* Grading standard and late policy are optional; `canvas:` keys come from one known-key list and an unknown key stops the build.
* Emit every declared assignment group and route assignments and quizzes by group name.
* Due dates: `due_time:` in `course.yml`; `due:` accepts a clock time; seconds now match Canvas (`:59`).

# coursepack 0.1.0

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
