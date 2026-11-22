# Proposal

## Why

A program that starts self-hosted runners needs GitHub's protocol for runner scale sets.
Each such program would write the sign-in, the sessions and the job flow again, in its own language.
scalesets writes them once, in Go, and lets Swift call the same code.

## What Changes

- A Go library at the repository root over [actions/scaleset][scaleset] v0.5.0.
  It owns GitHub App sign-in, the runner group, and scale sets with a name guard on delete.
- The library also owns sessions, the listener, job acquisition, statistics, just-in-time configs and runner removal.
- It finds a runner by name, confirms that a job ran on a runner, and fails the job of a lost runner.
- `capi/`: a C interface, built into a static archive that ships as an XCFramework.
- A Swift package in `swift/`, named by a root `Package.swift`, with no protocol logic of its own.
- One `vX.Y.Z` version for Go and Swift through verctl, first released as `0.0.1`.
- CI that tests Go on Linux and Swift on macOS, and a live test that needs secrets.
- This change replaces the first draft, `docs/design.md`.
  `docs/research.md` stays as the survey of repository shapes.

The consumer keeps its capacity budget, its sizes, how it starts runners, its spare runners and its restart policy.

## Capabilities

### New Capabilities

- `github-sign-in`: the configuration, the App key, the tokens and the permissions the library needs.
- `scale-sets`: the runner group, and how sets are made, reused, listed and deleted, with names and capacity.
- `job-listener`: sessions, the listener, reconnects, acquisition, updates and statistics.
- `runners`: just-in-time configs, removal, lookup, job confirmation, failure of a lost runner's job, and restart.
- `c-interface`: the exported C functions, memory, threads, the JSON schema and the error codes.
- `swift-binding`: the Swift actor, its streams, its errors and its handling of credentials.
- `build-and-release`: the layout, the template pieces, the version, CI and the tests.

### Modified Capabilities

None.

## Impact

- New Go packages at the root and in `capi/`, a Swift target in `swift/`, and a root `Package.swift`.
- A pinned dependency on actions/scaleset, which is MIT licensed.
- New workflows from the template: the go-module and swift-package jobs and `xcframework.yml`.
- A consumer that speaks the protocol itself moves to this library; [design.md](design.md) covers how.

[scaleset]: https://github.com/actions/scaleset/tree/af394d86c0d5024225238b0209043c70193bcfe6
