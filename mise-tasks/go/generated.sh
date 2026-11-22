#!/bin/sh
#MISE description="Regenerate, then fail when that changes a file"
#MISE depends_post=["go:unchanged"]
# CI runs it first, on the clean checkout, so any change is go generate's.
go generate ./...
