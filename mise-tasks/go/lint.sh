#!/bin/sh
#MISE description="Lint with golangci-lint, after verifying its configuration"
#MISE depends=["go:lint:config"]
# depguard fails an import that .golangci.yml does not allow.
# The standard library and this module are always allowed.
golangci-lint run ./...
