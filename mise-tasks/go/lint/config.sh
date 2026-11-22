#!/bin/sh
#MISE description="Verify .golangci.yml against the golangci-lint v2 schema"
# golangci-lint run ignores a key that the schema lacks and gives no warning.
# A leftover v1 linters-settings block is an example.
golangci-lint config verify
