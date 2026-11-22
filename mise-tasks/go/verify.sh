#!/bin/sh
#MISE description="Every offline Go check; go:vuln runs in CI on its own"
#MISE depends=["go:lint", "go:tidy", "go:fix", "go:test"]
# The one gate. Its dependencies run in parallel.
