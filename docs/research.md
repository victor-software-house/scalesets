# Research

The question: how should one implementation reach Go programs and Swift programs, with room for more languages?
This survey of 14 repositories, made on 2026-11-22, sorts them into three shapes.

## Shape A: one repository, a binding per folder

| Repository | Core | Swift |
|:--|:--|:--|
| [signalapp/libsignal](https://github.com/signalapp/libsignal) | Rust at the root | `Package.swift` at the root, sources in `swift/` |
| [tailscale/libtailscale](https://github.com/tailscale/libtailscale) | Go at the root, a C archive | an Xcode project in `swift/`, with no root `Package.swift` |

One tag versions every language, and a change to the core and its bindings lands in one pull request.

## Shape B: a core repository and a thin Swift repository

| Core | Swift wrapper |
|:--|:--|
| [matrix-org/matrix-rust-sdk](https://github.com/matrix-org/matrix-rust-sdk) | [`matrix-org/matrix-rust-components-swift`](https://github.com/matrix-org/matrix-rust-components-swift) |
| [bitwarden/sdk-internal](https://github.com/bitwarden/sdk-internal) | [bitwarden/sdk-swift](https://github.com/bitwarden/sdk-swift) |
| [mozilla/application-services](https://github.com/mozilla/application-services) | [mozilla/rust-components-swift](https://github.com/mozilla/rust-components-swift) |

Each wrapper repository commits generated Swift and the binary's checksum on every core release.
Two release lines must stay in step.

## Shape C: a repository per language

[apple/pkl-go](https://github.com/apple/pkl-go) and [apple/pkl-swift](https://github.com/apple/pkl-swift), the 1Password SDKs, and [temporalio/sdk-core](https://github.com/temporalio/sdk-core) keep one repository per language.
Each language either reimplements the logic or wraps a shared core through its own build.

## Tools that were ruled out

1. gomobile generates an Objective-C API, with no async functions and no typed errors in Swift.
2. uniffi generates idiomatic bindings, but only for Rust.

## Result

Shape A fits: Go stays at the root, the C archive sits in `capi/`, and each binding gets its own folder.
SwiftPM reads only a root `Package.swift`, which libsignal shows working beside another language's build.
[swift-onepassword](https://github.com/victor-software-house/swift-onepassword) already proves the Go side: a C archive with JSON calls, shipped as an XCFramework release asset.
