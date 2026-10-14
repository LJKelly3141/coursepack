# Explainer Video Facility Plan

**Goal:** Let a course built with coursepack make narrated explainer videos with `prajwal-y/video_explainer`, as an optional facility. coursepack works exactly as before on a machine without it; only the video functions are unavailable there.

**Architecture:** The tool is installed once per machine, outside every course and outside this package, pinned to one commit. coursepack never contains its code. A new `R/video.R` finds it, checks it, installs it on request, and stages a course's public source in and the finished video out. Two shipped skills sit on top: one installs and diagnoses the facility, one makes a video.

**Tech Stack:** R (base), testthat 3. No new R package. External, optional: git, uv (Python 3.11+), Node.js 20+, FFmpeg, the `claude` CLI.

**Status:** Superseded 2026-10-14 by lecturecast (separate package, repo LJKelly3141/lecturecast). Steps 2 to 5 will not be built. The install was removed on 2026-10-14. The step 1 log below is kept as the record of why. Originally requested by the instructor on 2026-10-13 (relayed from the ECON 740 session, then confirmed here).

## What is known (read from the repo on 2026-10-13, nothing run)

| Fact | Source |
|---|---|
| Latest commit `c033e28d6eccae43c1762f4653f9c320b16b050e`, 2026-02-24. Repo idle since. | GitHub API, commits |
| No LICENSE file. README and `pyproject.toml` say MIT. Issue #1 asks for one; maintainer replied "Feel free to send a pull request". | repo root listing, issue #1 |
| Needs Python >= 3.10, Node.js 20+, FFmpeg. | `pyproject.toml`, README |
| `edge-tts` is a core dependency; Whisper is the optional extra `[whisper]`. | `pyproject.toml` |
| The `claude-code` provider runs `claude --print -p <prompt>`, adds `--model` from config, and adds `--dangerously-skip-permissions` when a step is given tools. | `src/understanding/llm_provider.py` lines 664 to 676 |
| Default model string is `claude-sonnet-4-20250514`. Default TTS provider is `mock`. | `config.yaml` |
| `voiceover --provider` takes `elevenlabs`, `edge`, `mock`, `manual`; `manual` uses `--audio-dir`, `--whisper-model`, `--export-script`. | `docs/CLI.md` |
| Pipeline: plan, script, narration, scenes, voiceover, storyboard, render. `generate --mock` runs it with no LLM or TTS. `--from` and `--to` bound it. | `docs/CLI.md` |
| Output is `projects/<project>/output/video.mp4`. | `docs/CLI.md` |
| Remotion is pinned at 4.0.242. | `remotion/package.json` |
| This machine: Python 3.9.6 as `python3`, but uv 0.12.11 has 3.11, 3.12 and 3.13; Node v26.8.1; npm 11.19.0; FFmpeg 9.0.1; claude 2.1.299. | checked locally 2026-10-13 |

## Not yet verified (step 1 answers these)

1. Whether the tool runs at all on Node 26 and FFmpeg 9, and whether the `claude-code` provider works with claude 2.1.299.
2. Whether `projects/` can live outside the tool's folder. `config.yaml` has no projects path, so assume not.
3. Whether it produces captions or a transcript.
4. Whether an existing figure (an R plot as PNG) can be used in a scene without hand-editing the generated `.tsx`.
5. Remotion's licence terms for university use.
6. Which current model string to put in `config.yaml`.

## Global Constraints

- **Optional, always.** No check at package load. Nothing in `Imports` or `Suggests`. One "Optional:" sentence in `SystemRequirements`. Cartridge, QTI, preview, accessibility audit and grading never look for the tool.
- **Clean stop when absent.** A video function on a machine without the facility stops with one message that says it is not installed and names the setup skill. No partial files.
- **None of the tool's code enters this package.** Not its prompts, not its Remotion components, not its bundled skill. Fixes to the tool live in a fork or a local patch set.
- **Pinned.** The commit hash is written in one place in `R/video.R`. Installing means that commit.
- **Course content stays in the course.** Only files named explicitly are staged into the tool. `assessments/`, `anon/` and anything the course does not publish are refused.
- **The permission-skipping sessions run inside the tool's own folder only**, never with a course repo as the working directory.
- Tests and help-page examples skip when the facility is absent, so GitHub's automatic test run does not depend on it.
- No install, version change, commit or push without the instructor's go-ahead for that action. No em-dashes in anything published.
- Never touch `inst/skills/uwrf-syllabus/` (another session's untracked work).

## Steps

### Step 1: Install the facility on this machine, by hand

- [ ] Instructor names the install location.
- [ ] Clone the repo and check out `c033e28`.
- [ ] Create the Python environment with uv on 3.11 or later; `pip install -e .` inside it.
- [ ] `npm install` in `remotion/`.
- [ ] Run `generate <project> --mock` end to end and confirm an MP4 is written.
- [ ] Run one short real video with the `claude-code` provider and `--voice-provider edge` from a public source document.
- [ ] Record the exact commands that worked, every failure and its fix, and answers to the six unverified items above. Write them into this file.

Gate: steps 2 to 4 are rewritten from what step 1 finds. If the tool does not run, stop and report.

### Step 2: Optional facility in coursepack

- [ ] `R/video.R` (create): `find_video_explainer()` reads `COURSEPACK_VIDEO_EXPLAINER`, then the default location; returns the path or `NA`. A set variable that names a missing folder stops, as `find_verapdf()` does.
- [ ] `video_explainer_usable()`: confirms the pinned commit, the Python environment, `remotion/node_modules`, FFmpeg and the `claude` CLI, and says which one is missing.
- [ ] `install_video_explainer()`: the commands from step 1, at the pin, asking before any download. Never runs unasked.
- [ ] Tests that need the tool skip without it; tests of the absent path run everywhere.
- [ ] `DESCRIPTION` `SystemRequirements`, `SETUP.md`, `README.md`, `NEWS.md`.

### Step 3: Install skill

- [ ] `inst/skills/explainer-video-setup/SKILL.md`: prerequisites, run `install_video_explainer()`, verify with the mock pipeline, a table of failures and fixes from step 1.
- [ ] Confirm `install_skills()` picks it up and `tests/testthat/test-skills-content.R` still passes.

### Step 4: Make a video

- [ ] `make_video(proj, ...)`: stage named public files into the tool, run the pipeline, bring the MP4 (and transcript, if the tool makes one) back under the course. Shape depends on step 1 items 2 and 3.
- [ ] `inst/skills/explainer-video/SKILL.md`: pick the source, review the plan, review the script, fact-check, choose the voice, preview render, feedback, final render. Stops for the instructor at the plan, the script and the preview.

### Step 5: Publishing

- [ ] Captions and a transcript before a video is linked from a course site.
- [ ] MP4s kept out of git; hosting decided.
- [ ] How the accessibility audit treats a linked video.

## Open decisions (the instructor's)

1. **Install location on this machine.** Suggested: `~/Library/Application Support/coursepack/video_explainer`, beside Quarto's `verapdf`. Outside the coursepack workspace, so it needs to be named.
2. **Release.** Its own version after 1.3.0, which still has seven open items in `project/TODO.md`.
3. **Licence.** Send the one-file MIT pull request upstream, or leave it. Pressing only if a public fork is needed for fixes.
4. **Default voice.** Edge, ElevenLabs, or own recording.
5. **Hosting for finished videos.**

## Step 1 log

### 2026-10-13: install (authorized: this location, uv on Python 3.12)

Location: `~/Library/Application Support/coursepack/video_explainer`. 449 MB (`.venv` 97 MB, `remotion/node_modules` 335 MB).

Commands that worked, in order, from the install folder's parent:

```
git clone https://github.com/prajwal-y/video_explainer.git video_explainer
cd video_explainer
git checkout c033e28d6eccae43c1762f4653f9c320b16b050e
uv venv --python 3.12 .venv            # CPython 3.12.14
uv pip install --python .venv/bin/python -e .
cd remotion && npm install             # 326 packages
```

Run the tool as `.venv/bin/python -m src.cli <command>` from the install folder.

Findings:

- **`--projects-dir` exists** as a top-level CLI option (default `projects`). Answers unverified item 2 in principle; not yet tried with a folder outside the tool.
- **`generate --mock` is not fully mock.** Plan, script and narration ran mocked and passed. The scenes step called the real `claude` CLI anyway (5 scenes, 3 attempts each). Every call failed with "Claude Sonnet 4 was retired on June 15, 2026", so nothing was generated and the run stopped at step 4 of 7. Voiceover, storyboard and render are untested.
- **The shipped model string is dead.** `config.yaml` `llm.model: claude-sonnet-4-20250514` must be changed before any real run. Not changed yet.
- `npm install` reported 33 vulnerabilities (1 low, 8 moderate, 10 high, 14 critical) and did not run the install scripts of `esbuild` and `fsevents`. `esbuild` 0.24.0 still loads. Nothing was "fixed".
- `npx remotion versions` prints 4.0.242 and then errors on Node v26.8.1. Whether rendering works on Node 26 is still unknown.
- `remotion.config` warns that a default project `llm-image-understanding` has no storyboard. The clone ships no `projects/` folder.
- `pymupdf` 1.28.2 prints a deprecation warning for the `fitz` import on every command. Harmless so far.
- Throwaway project left in place: `projects/install-check/` (60 KB), with a six-line source document written for the check.

Still open from the unverified list: 1 (render on Node 26 and FFmpeg 9; the `claude-code` provider with a live model), 3, 4, 5, 6.

### 2026-10-13: first real video (authorized: claude-code + Edge demo)

Result: `projects/scatter-demo/output/final-720p.mp4`, 1280x720 h264 + aac, 94.5 s, 15.5 MB, from the six-line scatter-plot source. Four scenes; default Edge voice `en-US-GuyNeural`.

Problems hit, in order, and what fixed each:

1. Retired model hard-coded in 10 source files (11 lines), not only `config.yaml`. Replaced `claude-sonnet-4-20250514` with `sonnet` everywhere (local patch, uncommitted in the clone). Still old and untouched: `claude-opus-4-5-20251101` (factcheck), `claude-3-haiku-20240307` (sound).
2. `generate` crashes after the storyboard step: `cmd_storyboard` reads `args.verbose`, which `cmd_generate` never sets (`src/cli/main.py` line 628). Workaround: run `render` as its own command.
3. A generated scene ended with a stray `};`. The scenes step printed the syntax error and then "completed successfully". Fixed by deleting the line (original kept as `.tsx.orig`). The tool's own `scenes --verify` reports many false positives (apostrophes in comments read as unterminated strings); esbuild is the real check.
4. First render downloaded Chrome Headless Shell (81 MB) and then hung extracting it: 0% CPU, no message, no timeout. Fixed by killing it and unzipping by hand into `remotion/node_modules/.remotion/chrome-headless-shell/mac-arm64/`. One-time per install.

Python output is block-buffered when redirected, so logs lag; run with `PYTHONUNBUFFERED=1`.

Implication for step 2: the wrapper must time out every step, check each step's output files itself rather than trust "completed successfully", and run `render` separately from `generate`.
