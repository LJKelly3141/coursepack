# coursepack 0.3.0.9006

* Question banks are read and checked in R. `read_bank()` parses `chapter_<NN>.json` out of a bank directory and refuses a chapter that is not there; `check_question()` refuses the three shapes the generator cannot render, an unsupported type, fewer than two options, and an answer key naming no option, each message prefixed with the item's location; `check_bank()` runs that over the whole chapter, requires ids to be unique within it and every named `image` to exist under the images directory, and returns the figures that carry no alt text as warnings rather than stopping, because such an item still renders. All three are exported so a bank-authoring session can check its own work without building anything. Two invented fixture banks and one 8 by 8 figure back the tests. No cartridge output changed.

# coursepack 0.3.0.9005

* Build, extract, build reproduces the staging tree on the synthetic course, and `test-roundtrip.R` holds it there. Six asymmetries had to close for it. `course_id:` and `manifest_id:` in `course.yml` override the two identifiers a course carries as a whole, both otherwise derived from `code:`, which an export does not carry; `extract_manifest()` writes them, along with `new_tab:` on a link item, each assignment's and quiz's `due:` read from `<due_at>`, `all_day_date:` where the export shows one, `term: timezone: UTC` above them because that is the zone Canvas stored those instants in, and `carry: repair_html: false`, because an extracted course is carried bytes throughout and the repair changes them. `all_day_date:` on a carried definition is new: the local day Canvas displays for an end-of-day deadline, which falls before the `due:` instant's own day whenever the course zone is behind UTC. Blanking a carried date no longer rewrites `<due_at/>` into `<due_at></due_at>`, and a carried assignment page whose `<title>` already reads `Assignment: X` keeps it rather than losing the prefix this builder wrote.

* A carried `<resource>` block is now written where its definition sits in the manifest, rather than after everything generated. Segregating them made the order depend on which definitions happened to be carried, so a cartridge rebuilt from an export of itself listed the same resources in a different order. The cartridge was supposed to change: `imsmanifest.xml` is regenerated in the fixture's expected tree, and the change is four `<resource>` blocks moving; putting them back at the end reproduces the frozen hash byte for byte.

# coursepack 0.3.0.9004

* `extract_manifest()`: a Canvas export becomes `course.yml`, `modules.yml`, `reference.yml` in the package schema, with the export copied under `reference/`. A page is regenerated as an `iframe:` definition only when its body is the builder's wrapper template and nothing else; every other page, and every assignment and quiz, carries its exported bytes forward with `source_ref:`. The site URL is the common prefix of the wrapper targets cut at the last `/`, so it is always a directory. The `canvas:` keys are the one shared `CANVAS_SETTINGS_KEYS` list the builder emits from. Announcements, grading standards, the late policy and LTI links are counted in the closing summary and not written, and neither is `due:` or `height_measured:`. All three files are refused when they already exist unless `overwrite = TRUE`, because re-running an extractor over hand-edited manifests has destroyed those edits before. The cartridge is unchanged: the builder's iframe template moved into one shared `iframe_wrapper()` that both the writer and the extractor read.

# coursepack 0.3.0.9003

* Carried HTML is repaired for accessibility on the way into the cartridge: every `<th>` with no `scope` gains one, `col` in its table's first row and `row` after it, and a leading `<p><strong>X</strong></p>` in a carried `<description>` becomes `<h2>X</h2>`. The header row is deliberately not wrapped in `<thead>`, because Canvas tables open with `<tbody>` and inserting one there is invalid nesting. Carried files only: a generated page is fixed at its source. `carry: repair_html: false` in `course.yml` turns it off and leaves the carried bytes alone; any value other than `true` or `false` stops the build. The cartridge was supposed to change: `g...q01/assessment_meta.xml` and `wiki_content/carried-page.html` are regenerated in the fixture's expected tree, and so is `wiki_content/chapter-one.html`, whose fixture body gained an unscoped table proving generated pages are left alone.

# coursepack 0.3.0.9002

* A carried assignment or quiz takes its title from the definition's `title:` and its due date from its `due:`, in every slot the carried bytes hold one: both `<title>` elements of a quiz's `assessment_meta.xml`, the carried assignment's settings file and its HTML. A definition with no `due:` has the carried `<due_at>` and `<all_day_date>` blanked rather than inheriting the source course's date, and a `due:` whose carried file holds no `<due_at>` stops the build. The cartridge was supposed to change: `g...a01/assignment_settings.xml`, `g...a01/carried-assignment.html` and `g...q01/assessment_meta.xml` are regenerated in the fixture's expected tree.

# coursepack 0.3.0.9001

* Carry-through: `source_ref` on any definition, bytes from `reference.yml`'s `source:`.

# coursepack 0.3.0

The accessibility audit is in the package: its seven files moved from the course toolchain with their test script ported section by section, and `audit_course()` drives the whole run from arguments alone.

* `audit_course()`'s cartridge search default is the shared `CARTRIDGE_SEARCH_DIRS` constant, and the announcement-body test injects a fetcher, so the default suite makes no network call.
* The cartridge audit reads announcement bodies; counts on a course with announcements rise. Every `imsdt_xmlv1p1` topic's `<text texttype="text/html">` body is XML-unescaped and audited for untitled iframes and for link text that says nothing out of context, with the finding attributed to the topic's own `.xml` and its fix target set to the announcement body file, which is authored rather than generated. `audit_cartridge()` reports how many bodies it read as `topics_read`, beside `wiki_pages_read`.
* `intended_surfaces()` gained a `cartridge_dirs` argument and `audit_course()` passes its own through, so the declaration and the audit loop can no longer read different sets of cartridges at any non-default value.
* A real pa11y run is now exercised end to end in `test-a11y-integration.R`, against a fixture page carrying three planted defects: no `lang` on `<html>`, an alt attribute that is really a filename, and link text that says nothing out of context. It asserts that the custom filename-as-alt check fired where axe cannot see a defect at all, that the missing language criterion came back, that the audit wrote its findings JSON, and that both runners actually reported. The runner claim is checked against pa11y's own issue list, because a finding's `source` records the producer rather than the runner and nothing downstream of `from_pa11y()` can tell htmlcs and axe apart.
* The section is opt-in: it skips unless `COURSEPACK_PA11Y_TESTS` is set, because npx fetches pa11y at run time and the first run downloads a Chromium build.
* The `pair/alpha` fixture gained a `_quarto.yml` and a second page, so discovery places its output directory from config rather than failing to place it at all.
* The accessibility audit's driver moved into the package as `audit_course()`, the last of the audit's seven files. The repositories to audit, the project root, the output directory, the server port, the cartridge search directories and the video fetcher are all arguments; nothing is read from the environment and no repository is assumed. An empty `repos` stops with the usage text. The return value is `invisible(list(findings, meta, files))`, and the closing console block prints the version line last.
* Its tests are ported from the snapshot's audit test script. The three sections that read the driver's own source read it by deparsing `audit_course()` rather than by reading a script file, which gives the same comment-free code the snapshot's grep gave; the one anchored pattern loses its `^`, because a function body is indented where a script's top level was not.
* The last three hand-offs land, and none is left. The four assertions that require the driver to build its source exclusion from discovery's `resource_dirs` and `unproduced_sources` and to name no course directory, and the static coupling proving it calls `halt_on_collision()` on its findings frame, are in `test-a11y-driver.R`. The fixture-driven distinct-id section now drives the three custom checks directly, beside the finding-model assertions that stood in for it.
* The accessibility audit's cartridge checks and its report renderer moved into the package: `audit_cartridge()`, `cartridges_in()`, `check_untitled_iframes()`, `check_weak_link_text()`, `video_caption_state()`, `inventory_media()`, `classify_fixes()`, `render_report()`, `render_plan()`, and `level_for()`. `cartridges_in()` gained a `dirs` argument, defaulting to the conventional pair, so a differently shaped repository does not have to move its files.
* The finding text every cartridge check sets as its fix target now reads `modules.yml or the coursepack cartridge builder`. A finding's id does not hash `fix_target`, so no id changed.
* Their tests are ported from the snapshot's audit test script, with two replacements. The section that audited a real Canvas export runs against a synthetic cartridge, `write_a11y_cartridge()` in the test helpers: two wiki pages, one untitled iframe beside a titled one, one weblink whose text says nothing out of context, and one embedded video resolved through an injected fetcher. The section that inventoried a real textbook repository runs against the `pair/alpha` fixture with one image, one PDF, and one PDF under `bibtex/` written into a copy of it.
* Two sections reach YouTube over the network and skip unless `COURSEPACK_NETWORK_TESTS` is set.
* Three hand-offs land: the cartridge-bearing fixtures of the declared-surfaces negative control, which drive `intended_surfaces()` through `cartridges_in()` and `cartridge_wiki_page_count()`, and the M11 no-criterion section, which renders a report. Two markers remain for the task that moves the driver.
* The accessibility audit's target discovery and source checks moved into the package: `discover_target()`, `intended_surfaces()`, `check_filename_alt()`, `check_missing_fig_alt()`, `check_colour_only()`, `contrast_ratio()`, and `suggest_passing_colour()`. `exclude` stays a required argument on both source checks, and `assessments` stays on the source exclusion list as a containment rule.
* `glob_to_regex()` was copied byte for byte. Its three wildcard sentinels are the literal control characters U+0001, U+0002 and U+0003, which most editors render as nothing; the ported glob assertions fail loudly if an editor ever strips them.
* Their tests are ported from the snapshot's audit test script. The section that ran discovery against whatever real repository an environment variable pointed at is replaced by the `pair/alpha` fixture with a `_quarto.yml` written into a copy of it, asserting the framework reads as `quarto`, that discovery finds real pages rather than zero, that every page sits at the output root, and that nothing under a declared pass-through copy is counted as a page.
* Two further assertions wait on libraries that have not moved yet and are named in place: the three cartridge-bearing fixtures in the declared-surfaces negative control call the cartridge library, and four assertions in the pass-through-exclusion section read the audit driver's own source.
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
