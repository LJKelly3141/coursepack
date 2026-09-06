# Going public: the checklist (Task 50 of the 2026-09-04 build plan)

Written 2026-09-05 at the end of the unattended run, with the run's own findings
attached to each line. Every line is a command or a yes/no for Logan. The
package is at 0.5.0.9003 on `main` at commit 8d47bb8; nothing is pushed; local
annotated tags v0.1.0 to v0.5.0 mark the five phase closes. `Version: 1.0.0`
is written when the flip happens, not before.

## Measured on the final tree (2026-09-05 19:05 CDT)

| Fact | Value |
|---|---|
| `tools/scrub.sh` | `scrub: clean` |
| suite (`testthat::test_local()`) | 1089 pass, 0 fail, 3 opt-in skips (2 network, 1 pa11y) |
| `R CMD check --no-manual` | 0 errors, 0 warnings, 0 notes |
| commits since the base before Task 1 (97a0ef0) | 60 |
| exported functions | 68 |
| exported functions with a roxygen example | 0 of 68 |
| `/Users/logankelly` in the whole history, outside `project/` and `.superpowers/` | 0 |
| `/Users/logankelly` in the history under `project/` | 36 |
| `chapter_13` in the whole history | 21 |

## The lines

- [x] `tools/scrub.sh` clean on the final tree. Done above; run it again after
  any edit made from this list.

- [x] **`project/` contents (decision D10, re-opened).** `project/` held the
  two toolchain snapshots (a live exam bank with keys under
  `econ202-toolchain/inputs/questions/`, 38 pages of course prose under
  `econ730-toolchain/inputs/content/canvas/`, both courses' full manifests, both
  `CLAUDE.md`s), the plans, the migration spec, the inventory, and the
  onboarding note. **Ruled 2026-09-05 by Logan: keep the plans, delete the
  rest; the toolchains exist in their own repositories.** Done the same day:
  the five paths came out of the tree (commit "Drop the toolchain snapshots
  and the migration notes from the tree"; `tools/baseline.R` lost the
  `script` mode that copied the frozen builder out of the snapshot), then
  `git filter-branch` removed the same five paths from every commit on `main`
  and re-pointed the five annotated tags. Two commits that only added
  snapshot files were pruned as empty. The pre-rewrite refs were bundled to
  the session scratchpad before the rewrite and the old objects were purged
  after it. The two tests that read a snapshot now skip on every checkout.

- [x] `git log -p --all | grep -c '/Users/logankelly'` is 0 outside `project/`.
  Re-measured after the rewrite: 0 outside `project/plans`; 9 inside the
  plans, every one this checklist's own grep line, the workspace path, a
  Makefile default, or a command example. `chapter_13` occurs 3 times in
  history, all of them the name in plan prose; the bank itself is gone.

- [x] **The GitHub remote (found 2026-09-05).** `origin` is
  `github.com/LJKelly3141/coursepack`, pushed four times before the run, last
  at "Add M19: a paper version of any assignment". Its history never received
  the bank (`chapter_13` count 0) but does carry the migration spec, the
  inventory, and the onboarding note. After the rewrite `main` shares no
  commit with `origin/main`: 66 ahead, 4 behind. The first push is therefore a
  force push, by Logan, by hand, and it belongs with the visibility flip
  below. The local `origin/main` ref was left untouched on purpose so it still
  records what GitHub holds.

- [ ] `R CMD check --as-cran` on a machine without Node or Chrome: 0 errors,
  0 warnings; pa11y and parity tests report as skipped. Not done: this machine
  has both. The suite's opt-in tests skip by environment variable, and the
  parity and snapshot tests skip when `project/` is absent, so the tarball is
  expected to pass; the run did not have a second machine to prove it.

- [ ] **Every exported function has a roxygen page whose example runs in
  `tempdir()`.** Not true yet: 0 of 68 exports carry an `\examples{}` section.
  `R CMD check` passes because there is nothing to run. This is the one item on
  the list that is package work rather than a decision; it is a follow-up task
  (one example per entry point, each against the synthetic fixture in a
  temporary directory), and it should land before the flip, because a CRAN-style
  reader expects it.

- [x] `DESCRIPTION` `Authors@R` carries the email Logan chooses (D8). The
  run's standing ruling kept the name and email as they stand; the scrub
  allows that one line (and roxygen's copy of it in
  `man/coursepack-package.Rd`) by name. Change it if you want a different
  address; nothing else references it. The package name stays `coursepack`.

- [ ] README quick start followed on a clean machine from `install_github()`
  to an imported scaffold, by Logan pretending to be a stranger. Not done.

- [ ] Repository description and topics set; issues on or off (D11).
  `CONTRIBUTING.md` says the outside-contributions question is open until the
  maintainer decides.

- [ ] The visibility flip, by Logan, by hand. Then `Version: 1.0.0` and the
  commit `Close phase 6: ready to go public`. The push that precedes the flip
  is `git push --force --tags origin main`, because the rewrite above replaced
  every commit the remote knows. Push before the flip, not after: the four old
  commits on GitHub carry the migration spec and the inventory, and a force
  push is what removes them from the branch.

## The human gates the run could not pass (Appendix D)

None of these was done from this repository, by design:

- Phase 1: the real-course byte gate in the first course's repository (A1 item 4).
- Phase 2: build that course with the package, import into a throwaway shell, export, compare field by field.
- Phase 3: the real audit diff (A3 item 1).
- Phase 4: the second course's B1 equivalence gate and the B2 round trips and import.
- Phase 5: import the scaffold cartridge into a throwaway shell.
- Phase 6: push, CI green, this list, the flip.

Every builder in the package prints it and every phase report repeated it: a
zip that builds proves nothing. Until the imports above are done, nothing this
package produced has been seen by Canvas.

## Two hand-offs the run left for you

- Port 8793 on this machine is held by a `python3 -m http.server` (pid 72763)
  leaked on 2026-08-13, serving a textbook repository outside this project. The
  run did not kill it; the pa11y integration test pins 8794 instead.
- Appendix B1 of the build plan gained five declared divergences and a manual
  paste (items 6 and 7) that the second course's conversion session needs to
  read before its equivalence gate.
