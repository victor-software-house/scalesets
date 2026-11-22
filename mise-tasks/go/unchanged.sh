#!/bin/sh
#MISE description="Fail when the tree differs from the commit"
# git has no exit status for a dirty tree: git diff --exit-code misses a new
# file, such as one go generate wrote. So this prints what differs, then fails
# when git status lists anything.
git status --short --untracked-files=all
test -z "$(git status --porcelain --untracked-files=all)"
