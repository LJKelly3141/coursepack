# coursepack 0.0.0.9003

* Timezone helper: `local_to_utc()`, `parse_when()`, `due_stamp()`; replaces the fixed UTC-5 arithmetic and the 2026-11-01 stop.

# coursepack 0.0.0.9002

* `%||%` is defined once, in `R/utils.R`.
* `coursepack_version()` and the closing version line every entry point prints.
* Config readers: `read_manifest()`, `read_announcements()`, `read_timezone()`, `textbook_docs_path()`, `course_slug()`.
