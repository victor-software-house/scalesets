# scalesets

## Layout

- The Go module at the root is the library, and the only implementation of the scale-set logic.
- `capi/` builds the library as a C archive with a few exported functions that take and return JSON.
  The Go side frees what it allocates.
- Each language binding is a folder over `capi/`, such as `swift/`.
  A binding adds no scale-set logic of its own.
- `Package.swift` stays at the root, because SwiftPM reads a package from the root of its repository.

## Checks

- `mise run go:verify` is the gate the pull request's CI runs: lint, tidy, fix, tests and the repository checks.
- `mise run check:repo` runs the repository checks alone, among them the prose, Markdown, TOML, typos, workflow and OpenSpec lints.
- The git hooks run the cheap checks on commit and push; `mise install` installs them.
- The shared template renders most of this setup.
  Change a rendered file through a template update, never by hand.

## Changes

- The design and its decisions live in OpenSpec changes under `openspec/`, each with a proposal, a design, spec deltas and tasks.
- `docs/research.md` surveys how other projects ship one core to several languages.
- Nothing generated is committed: the C archive and the XCFramework are built by tasks and published as release assets.
- One version covers the Go module and every binding, tagged `vX.Y.Z`.
  A pull request that changes behaviour adds a verctl fragment under `.changeset/`.
- The repository is public.
  Its files, commits and pull requests name and link only public repositories.
  A program that uses the library is a consumer, never named.
