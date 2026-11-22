#!/bin/sh
#MISE description="Fail when go mod tidy would change go.mod or go.sum"
go mod tidy -diff
