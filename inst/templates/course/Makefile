# Every target here calls a function in the installed coursepack package. There
# is no build script in this repository to keep in step with it: the toolchain
# is a dependency, `make install-toolchain` updates it, and nothing else moves.
#
# Read this once. A zip that builds proves nothing. Canvas discards malformed
# content silently and still reports a successful import, so the only proof is
# importing into a throwaway shell and looking at it.

.PHONY: site leakcheck checkyml coursepack refdiff mockup qti paper a11y tile \
        skills test clean install-toolchain

# ---- the public site ------------------------------------------------------

# docs/ is what the published site serves, so the containment check runs on
# every render rather than whenever somebody remembers it.
site:
	quarto render
	@touch docs/.nojekyll
	$(MAKE) leakcheck

# Refuses if anything from assessments/ reached the public site. It reads bytes,
# so the canary cannot hide inside a rendered PDF or an image, and a missing
# docs/ is a refusal too: nothing was scanned, so nothing is known.
leakcheck:
	@Rscript -e 'coursepack::leak_check(".")'

# ---- the cartridge --------------------------------------------------------

# Validates course.yml and modules.yml before anything is generated from them.
checkyml:
	@Rscript -e 'coursepack::check_manifests(".")'

# Builds the cartridge and then diffs it against the reference export.
coursepack: checkyml
	Rscript -e 'coursepack::build_cartridge(".")'
	$(MAKE) refdiff

# Structural diff against the export named in reference.yml. A course with no
# reference export says so and carries on: there is nothing to diff against.
refdiff:
	@Rscript -e 'coursepack::diff_against_reference(".")'

# ---- reviewing before importing -------------------------------------------

# A local, browsable mockup of the module tree. It is served rather than opened
# from disk because a browser gives every file:// document its own opaque origin
# and refuses to frame one from another, so opening the page from disk gives a
# working tree and a permanently blank preview pane.
MOCKUP_BASE ?= local
MOCKUP_PORT ?= 8765
mockup:
	Rscript -e 'coursepack::build_preview(".", base = "$(MOCKUP_BASE)")'
	@echo "serving http://localhost:$(MOCKUP_PORT)/  (ctrl-c to stop)"
	@python3 -m http.server $(MOCKUP_PORT) --directory build/mockup & \
	SERVER_PID=$$!; \
	sleep 1; \
	open "http://localhost:$(MOCKUP_PORT)/" 2>/dev/null \
	  || xdg-open "http://localhost:$(MOCKUP_PORT)/" 2>/dev/null \
	  || echo "open http://localhost:$(MOCKUP_PORT)/ in a browser"; \
	wait $$SERVER_PID

# ---- quizzes and paper forms ----------------------------------------------

# No default. The quiz is named on the command line, because building the wrong
# definition and importing it is worse than being told to say which one.
QUIZ ?=
qti:
	@if [ -z "$(QUIZ)" ]; then \
		echo "make qti needs a definition: make qti QUIZ=assessments/quizzes/<name>.R"; \
		exit 1; \
	fi
	Rscript -e 'coursepack::build_qti("$(QUIZ)", ".")'

# One fixed form of a bank quiz or an assignment, with its answer key beside it,
# for a make-up sitting or a proctored room. The seed names the form: the same
# seed prints the same paper.
ID ?=
SEED ?=
paper:
	@if [ -z "$(ID)" ] || [ -z "$(SEED)" ]; then \
		echo "make paper needs both: make paper ID=<quiz or assignment id> SEED=<whole number>"; \
		exit 1; \
	fi
	Rscript -e 'coursepack::print_assessment(".", id = "$(ID)", seed = $(SEED))'

# ---- everything else ------------------------------------------------------

# Accessibility audit. Repositories are passed as arguments, never as exported
# environment variables: make exports an unset variable as an empty string, and
# R's Sys.getenv(name, default) does not fall back on empty, so exporting a name
# silently disables what it was meant to configure. Add a second repository
# here to audit the site and its textbook together.
A11Y_REPOS ?= .
a11y:
	Rscript -e 'coursepack::audit_course(commandArgs(TRUE))' $(A11Y_REPOS)

# The Canvas dashboard card, written to assets/images/course-tile.png.
tile:
	Rscript -e 'coursepack::course_tile(".")'

# Copies the skills that ship with the toolchain into .claude/skills/, replacing
# the shipped files already there and leaving anything this course added beside
# them. The copies are committed with the course, so a clone carries them
# whether or not the toolchain is installed on that machine.
skills:
	Rscript -e 'coursepack::install_skills(".", overwrite = TRUE)'

# What a course can check about itself: that its manifests are consistent, and
# that nothing from assessments/ reached the published site. The toolchain's own
# test suite runs in the toolchain's checkout and is not a course's concern.
test: checkyml leakcheck

# docs/ is NOT removed. On a Pages course that directory is the published site
# and it is committed; deleting it and pushing serves a 404 to everyone reading.
# Getting it back is a full render, not a git restore.
clean:
	rm -rf build .quarto

# Optional. Unset, the toolchain is installed from its repository. Set to a
# local checkout, it is installed from there instead, which is what a session
# working on the toolchain itself wants.
COURSEPACK ?=
install-toolchain:
	@if [ -z "$(COURSEPACK)" ]; then \
		Rscript -e 'remotes::install_github("LJKelly3141/coursepack")'; \
	else \
		Rscript -e 'remotes::install_local("$(COURSEPACK)", force = TRUE)'; \
	fi
