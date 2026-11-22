#!/bin/sh
#MISE description="Check against the Go vulnerability database; needs the network"
# Not in go:verify: CI runs it on its own, on each pull request and nightly.
govulncheck ./...
