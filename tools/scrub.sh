#!/usr/bin/env bash
# Public-readiness greps. Exit 1 on any hit outside the allowed set.
#
# The allowed set is exactly two things, and nothing else:
#   1. the string LJKelly3141/coursepack inside inst/templates/course/Makefile,
#      README.md and DESCRIPTION, which is this package's own repository address;
#   2. the Authors@R person line of DESCRIPTION, which carries the maintainer's
#      name and institutional email because a package has to name a maintainer,
#      together with the \author{} block of man/coursepack-package.Rd, which is
#      roxygen's mechanical copy of that same line and is rewritten from it on
#      every roxygenise(), so it cannot be edited away while the entry stands.
#
# Run from the package root: tools/scrub.sh
set -u
status=0
# Course residue. test-fixtures.R and test-skills-content.R carry this regex
# themselves, so those two files are excluded by name here and nowhere else.
hits=$(grep -rniE 'econ ?730|econ ?202|managerial|macro_principles|logankelly|uwrf|river falls|real-world-statistics|kellyecon|My_Books|Teaching/' \
  --exclude=test-fixtures.R --exclude=test-skills-content.R \
  R/ inst/ tests/ man/ NAMESPACE README.md NEWS.md CONTRIBUTING.md DESCRIPTION 2>/dev/null \
  | grep -vE '^DESCRIPTION:[0-9]+: *person\(' \
  | grep -vE '^man/coursepack-package\.Rd:[0-9]+:.*\\email\{')
[ -n "$hits" ] && { echo "course residue:"; echo "$hits"; status=1; }
addr=$(grep -rn 'ljkelly3141' -i R/ inst/ tests/ man/ NAMESPACE README.md NEWS.md CONTRIBUTING.md DESCRIPTION 2>/dev/null \
  | grep -viE '^(inst/templates/course/Makefile|README\.md|DESCRIPTION):.*LJKelly3141/coursepack')
[ -n "$addr" ] && { echo "repository address outside the allowed files:"; echo "$addr"; status=1; }
env=$(grep -rn 'Sys.getenv' R/); [ -n "$env" ] && { echo "Sys.getenv in R/:"; echo "$env"; status=1; }
paths=$(grep -rnE '~/|/Users/|/home/' R/ inst/ tests/); [ -n "$paths" ] && { echo "absolute paths:"; echo "$paths"; status=1; }
dash=$(grep -rn -- '—' R/ inst/ README.md NEWS.md CONTRIBUTING.md 2>/dev/null); [ -n "$dash" ] && { echo "em-dashes in shipped text:"; echo "$dash"; status=1; }
# Token shapes anywhere in the history. Two things keep this check from flagging
# its own specification rather than a real leak. The plan documents under
# project/plans/ and .superpowers/ quote this very grep, so those two paths are
# left out of the diff; every other path ever committed is still read, including
# the rest of the project/ snapshot. And the two literal terms are written with a
# bracketed character so this line does not match itself once it is committed.
# Both spellings match exactly the strings the plain literals matched.
secrets=$(git log -p --all -- . ':(exclude)project/plans' ':(exclude).superpowers' | grep -cE '[0-9]{4,5}~[A-Za-z0-9]{40,}|Bea[r]er |CANVAS_API[_]TOKEN')
[ "$secrets" != "0" ] && { echo "token shapes in history: $secrets"; status=1; }
[ $status -eq 0 ] && echo "scrub: clean"
exit $status
