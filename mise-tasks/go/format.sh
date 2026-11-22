#!/bin/sh
#MISE description="Fail when a Go file needs formatting"
# The pre-commit hook runs this. --diff prints the change and exits non-zero
# instead of rewriting the file.
golangci-lint fmt --diff ./...
