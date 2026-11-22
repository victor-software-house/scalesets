# Design

scalesets speaks GitHub's protocol for runner scale sets once, in Go, for every program that starts self-hosted runners.
The first two such programs run runners in Linux microVMs and in macOS sandboxes.

## Context

1. [actions/scaleset][scaleset] v0.5.0 is GitHub's Go client for runner scale sets.
   Its listener opens a message session, long-polls it, and calls `Scale` with each message.
2. A program that starts runners needs more than that client.
   It signs in as a GitHub App, keeps a runner group and its scale sets, and listens.
   It also issues just-in-time runner configs, removes lost runners, and confirms jobs before it trusts a cache write.
3. One of the two programs is written in Swift.
   A second implementation in Swift would drift from the Go one, so Swift must call the same code.
4. [swift-onepassword][swift-onepassword] already links a Go SDK into Swift: a C archive with a few JSON functions, shipped as an XCFramework release asset.

## Goals

1. One Go implementation of the protocol, used from Go and from Swift.
2. A Swift package that a program adds at an exact version, with no Go toolchain and nothing generated in either repository.
3. Room for more languages later, each a thin folder over the same C interface.

## Non-goals

1. Deciding how many runners fit, or starting them.
   The program that uses scalesets owns its machines.
2. A Swift or Rust port of the protocol.
3. Bindings other than Swift before someone needs one.

## Decisions

### 1. One repository, Go at the root

The repository follows [libsignal][libsignal]: the implementation at the root, `Package.swift` at the root, and the Swift sources in a folder.
SwiftPM reads a package only from the root of its repository, so a separate Swift repository would need a second release line.

[docs/research.md](research.md) contains the survey behind this choice.

```text
go.mod, *.go     the library, package scalesets
capi/            the C interface, built as a C archive
swift/           the Swift binding over capi/
Package.swift    names the XCFramework release asset
```

### 2. What the library covers

The library contains the parts that know GitHub and nothing about machines:

| Part | Does |
|:--|:--|
| Sign-in | GitHub App installation tokens and the runner group |
| Sets | Creates and reuses scale sets by name and labels; lists and deletes them, with a guard on names |
| Listening | Message sessions, the listener, job acquisition and token refresh |
| Runners | Just-in-time configs, and removing a runner by name |
| Confirmation | Confirms that a job of a run ran on a given runner |

The program keeps what is about its machines: its capacity budget and sizes, how it starts a runner, spare runners, and what it does after a restart.

### 3. The Go API

The library acquires every job it is offered and reports what happened.
A program sets each scale set's capacity and reacts to updates:

```go
c, err := scalesets.Connect(ctx, scalesets.Config{Org: "acme", App: app, Group: "runners"})
sets, err := c.Ensure(ctx, []scalesets.Spec{{Name: "runners-linux-8x16", Labels: labels}})
sets[0].SetCapacity(4)
err = sets[0].Listen(ctx, handler) // calls handler.Update with each message
jit, err := sets[0].JITConfig(ctx, "runners-linux-8x16-ab12")
err = sets[0].Remove(ctx, "runners-linux-8x16-ab12") // scalesets.ErrRunnerBusy while it runs a job
```

An `Update` carries the assigned and running job counts, and the runners whose jobs started or completed, with each result.
`Listen` reopens its session after a failure, and returns when its context ends.
`Remove` succeeds when GitHub lists the runner nowhere.

### 4. The C interface follows swift-onepassword

`capi/` exports the same shape as swift-onepassword's [`core/shim.go`][shim]: a handle, one call with a JSON request and a JSON reply, and a free function.
It adds one blocking function, because updates arrive from GitHub and need a pull:

| Function | Does |
|:--|:--|
| `sc_open(config)` | Connects, ensures the sets, and returns a handle or an error |
| `sc_call(handle, request)` | Runs `capacity`, `jit` or `remove` for one set |
| `sc_next(handle, timeout_ms)` | Waits for the next update of any set, or reports a timeout or a closed handle |
| `sc_close(handle)` | Ends every listener and session |
| `sc_free(text)` | Frees a reply that Go allocated |

Every reply is JSON with either a result or an error code and message.
A Go panic becomes an error reply.

### 5. The Swift API

| Need | Swift |
|:--|:--|
| Open | `try await ScaleSets(organization:app:group:sets:)` |
| Capacity | `try await scaleSets.setCapacity(_:for:)` |
| Updates | `scaleSets.updates(for:)`, an `AsyncThrowingStream<Update, Error>` |
| Runner config | `try await scaleSets.runnerConfig(set:name:)` |
| Remove | `try await scaleSets.remove(runner:from:)` |
| Close | `await scaleSets.close()` |

`ScaleSets` is an actor.
One thread calls `sc_next` in a loop and yields each update to the stream of its set.
Errors are typed Swift errors, and the binding adds no protocol logic of its own.

### 6. Releases

One `vX.Y.Z` tag versions the Go module and the Swift package together; the first release is `0.0.1`.
A release workflow builds `capi/` on macOS and publishes the XCFramework as a `capi-<hash>` prerelease.
`Package.swift` pins that asset's URL and checksum.

## Plan

1. This design, reviewed.
2. The Go library and its tests; release `0.0.1`.
3. `capi/` and the Swift binding; release the next patch.
4. The two programs move onto scalesets.

## Risks

1. A breaking change in actions/scaleset reaches every program that uses scalesets.
   The library pins it exactly, and each update is one change here.
2. `sc_next` blocks a thread while it waits.
   One thread serves every set, and `sc_close` wakes it.
3. A Go panic inside the C archive would end the host process.
   Every exported function recovers and replies with an error, as swift-onepassword's does.

[scaleset]: https://github.com/actions/scaleset/tree/v0.5.0
[swift-onepassword]: https://github.com/victor-software-house/swift-onepassword/blob/22033b1c2aaeec25c78fdd11570ec3e00036de79/README.md
[shim]: https://github.com/victor-software-house/swift-onepassword/blob/22033b1c2aaeec25c78fdd11570ec3e00036de79/core/shim.go
[libsignal]: https://github.com/signalapp/libsignal
