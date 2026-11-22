# scalesets

## Layout

- The Go module at the root is the library, and the only implementation of the scale-set logic.
- `capi/` builds the library as a C archive with a few exported functions that take and return JSON.
  The Go side frees what it allocates.
- Each language binding is a folder over `capi/`, such as `swift/`.
  A binding adds no scale-set logic of its own.
- `Package.swift` stays at the root, because SwiftPM reads a package from the root of its repository.

## Changes

- The design and its decisions live in `docs/design.md`; the survey of other repositories behind it lives in `docs/research.md`.
- Nothing generated is committed: the C archive and the XCFramework are built by tasks and published as release assets.
- One version covers the Go module and every binding, tagged `vX.Y.Z`.
