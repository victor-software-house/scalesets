# Spec Delta

## Purpose

Fixes how the repository is laid out, built, tested and released, so that Go and Swift ship one version from one tree.

## ADDED Requirements

### Requirement: One tree in the libsignal layout

The Go module SHALL sit at the root, the C interface in `capi/` as a main package of the same module, and the Swift sources in `swift/`.
`Package.swift` SHALL sit at the root.

#### Scenario: A Go consumer

- **WHEN** a Go program runs `go get github.com/victor-software-house/scalesets@v0.0.1`
- **THEN** it gets the library with no Swift or C build step

### Requirement: Nothing generated is committed

The repository SHALL commit no C archive, header build output, XCFramework or recorded token.
Tasks SHALL build them, and releases SHALL carry them.

#### Scenario: A built archive in a commit

- **WHEN** a pull request adds a `.a` file or an `.xcframework` folder
- **THEN** a repository check fails

### Requirement: The template renders the build

The repository SHALL take its CI, hooks and lints from the shared template's repository layer.
A go-module and a swift-package component SHALL both sit at the root.
The `go_xcframework` piece SHALL build `capi/` into the module `CScaleSets`.

#### Scenario: A template update

- **WHEN** a new template tag changes a rendered file
- **THEN** the Template check reports it, and an update pull request takes it

### Requirement: Package.swift pins a published archive

The `binaryTarget` in `Package.swift` SHALL name the `capi-<hash>` prerelease of the current `capi/` inputs, with its checksum.
`xcframework:check` SHALL fail when it names another one.

#### Scenario: capi changed without a pin

- **WHEN** a pull request changes `capi/` but not the pin
- **THEN** `xcframework:check` fails and prints the command that fixes it

### Requirement: One version for every language

verctl SHALL release one `vX.Y.Z` tag for the Go module and the Swift package, from the version comment on the `module` line of `go.mod`.
The first release SHALL be `0.0.1`.

#### Scenario: The first release

- **WHEN** the first Version PR merges with a patch fragment
- **THEN** verctl tags `v0.0.1` and publishes its GitHub Release

### Requirement: A release tag sees a complete archive

A `vX.Y.Z` tag SHALL only point at a commit whose `Package.swift` names a complete `capi-<hash>` release.

#### Scenario: A Swift program adds a release

- **WHEN** a Swift program adds the package at `0.0.2`
- **THEN** SwiftPM downloads the pinned archive and its checksum matches

### Requirement: CI tests Go on Linux and Swift on macOS

CI SHALL run `go:verify` and `go:vuln` on Linux, and the Swift build and tests on macOS, for each pull request and merge group.
The C interface tests SHALL run on both.

#### Scenario: A Swift change

- **WHEN** a pull request changes `swift/`
- **THEN** the macOS job builds and tests the package

### Requirement: Unit tests use a fake GitHub

Unit tests SHALL run against a fake Actions service and a fake REST API, built on `httptest`.
A test SHALL fail when an exchange it expects never happens.

#### Scenario: A missing acquire

- **WHEN** a test expects an acquire call and the code makes none
- **THEN** the test fails and names the missing exchange

### Requirement: Contract tests replay recorded replies

Contract tests SHALL replay GitHub replies recorded in `testdata/contract/`.
The recordings SHALL come from a public test repository, with every token, key, config and private name scrubbed.

#### Scenario: A token in a recording

- **WHEN** a recording contains a string shaped like a token or a JIT config
- **THEN** the scrub check fails

### Requirement: The C interface has its own tests

Go tests SHALL drive the exported functions' Go side, and a C harness SHALL link the archive and call all five functions.
Swift tests SHALL run on macOS CI against the fake GitHub.

#### Scenario: Close during next in C

- **WHEN** the C harness closes a handle while another thread waits in `sc_next`
- **THEN** the wait returns the closed result

### Requirement: The live test never runs for forks

A live test against a real GitHub App SHALL run only on pushes to the default branch and on manual runs.
It SHALL run only with its secrets present.
It SHALL never run on a pull request from a fork.

#### Scenario: A fork's pull request

- **WHEN** a fork opens a pull request
- **THEN** no job gets the live test's secrets, and the live test does not run

### Requirement: actions/scaleset is pinned exactly

`go.mod` SHALL require one exact actions/scaleset release, and depguard SHALL allow it.
Each update SHALL land as its own pull request that passes the contract tests.

#### Scenario: A new upstream release

- **WHEN** actions/scaleset tags a new release
- **THEN** an update pull request moves the pin, and the contract tests decide it
