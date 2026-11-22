# Design

## Context

[proposal.md](proposal.md) states why scalesets exists.
[research.md](research.md) lists the upstream facts this design builds on, each with a pinned source link.
[docs/research.md](../../../docs/research.md) surveys how other projects ship one core to several languages.

## Goals / Non-Goals

**Goals:**

1. One Go implementation of the scale set protocol, used from Go and from Swift.
2. A Swift package that a program adds at an exact version, with no Go toolchain.
3. A C interface that a later binding can reuse as it is.

**Non-Goals:**

1. Capacity budgets, machine sizes, spare runners, starting runners and restart policy.
   The consumer owns them.
2. Enterprise and repository scale sets, GitHub Enterprise Server, and sign-in with a personal token.
3. A protocol port in Swift or Rust, and bindings other than Swift before one is needed.
4. State on disk.
   The library keeps everything in memory, and reads GitHub again after a restart.

## Decisions

### 1. The library wraps actions/scaleset

scalesets calls [actions/scaleset][scaleset] for every Actions service request.
It adds what the upstream client leaves to its caller: reconnects, name rules, removal by name, REST calls, and job failure.
A port of the protocol would drift from GitHub's own client.

### 2. The Go API

```go
func Connect(ctx context.Context, cfg Config) (*Client, error)
func AppKeyFromPEM(pem []byte) (AppKey, error)
func AppKeyFromFile(path string) (AppKey, error)

type Config struct {
    Organization, RunnerGroup, Prefix, Owner string
    App          App
    ConflictWait time.Duration // 0 means 5 minutes
    Logger       *slog.Logger  // nil discards
    HTTPClient   *http.Client  // nil uses the library's client
}
type App struct { ClientID string; InstallationID int64; Key AppKey }
type Client struct{ /* unexported */ }
type Set struct{ /* unexported */ }
type AppKey struct{ /* unexported */ }
type Credential struct{ /* unexported */ }
func (Credential) Reveal() []byte
func (*Credential) Wipe()

func (c *Client) Ensure(ctx context.Context, specs []Spec) ([]*Set, error)
func (c *Client) Sets(ctx context.Context) ([]SetInfo, error)
func (c *Client) Delete(ctx context.Context, name string) error
func (c *Client) ConfirmJob(ctx context.Context, repository string, runID int64, runner string) (bool, error)
func (c *Client) Close(ctx context.Context) error

type Spec struct { Name string; Labels []string; MaxRunners int }
type SetInfo struct { ID int; Name string; Labels []string; Statistics Statistics }

func (s *Set) ID() int
func (s *Set) Name() string
func (s *Set) SetMaxRunners(n int) error
func (s *Set) Listen(ctx context.Context, h Handler) error
func (s *Set) JIT(ctx context.Context, runner string) (JIT, error)
func (s *Set) RemoveRunner(ctx context.Context, runner string) error
func (s *Set) Runner(ctx context.Context, name string) (Runner, error)
func (s *Set) Runners(ctx context.Context) ([]Runner, error)
func (s *Set) FailJob(ctx context.Context, job JobCompletion) error

type Handler interface { Update(ctx context.Context, u Update) error }
type HandlerFunc func(ctx context.Context, u Update) error
func (f HandlerFunc) Update(ctx context.Context, u Update) error

type Update struct {
    Set        string
    MessageID  int // InitialMessage (-1) for a new session
    Statistics Statistics
    Available, Assigned, Started, Completed []Job
    Acquired   []int64
}
type Statistics struct { Available, Acquired, Assigned, Running, Registered, Busy, Idle int }
type Job struct {
    RequestID, RunID     int64
    JobID, Repository    string
    WorkflowRef, Name    string
    Labels               []string
    Runner               string // Started and Completed only
    RunnerID             int
    Result               string // Completed only
    Queued, Assigned, Finished time.Time
}
type JIT struct { RunnerName string; RunnerID int; Config Credential }
type Runner struct { ID, SetID int; Name string; Online, Busy bool }
type JobCompletion struct { RunServiceURL, PlanID, JobID string; Token Credential }

type RateLimitError struct { RetryAfter time.Duration; Err error }
type APIError struct { Status int; RequestID string; Err error }

const InitialMessage = -1
const MaxSetName, MaxRunnerName = 45, 64
```

`Update` copies the upstream message into the library's own types, so an upstream change stays inside scalesets.

### 3. Errors

The library returns these sentinels, matched with `errors.Is`:
`ErrInvalidConfig`, `ErrInvalidSpec`, `ErrInvalidName`, `ErrNameGuard`, `ErrNotFound`, `ErrRunnerExists`, `ErrRunnerBusy`, `ErrListening`, `ErrAuth`, `ErrRateLimited`, `ErrSessionConflict` and `ErrClosed`.

- `*RateLimitError` adds `RetryAfter`, and `*APIError` adds the HTTP status and GitHub's request ID.
- `ErrRunnerBusy` wraps upstream's `JobStillRunningError`, and `ErrNotFound` its `NotFoundError` or a nil result.
- A network failure or a timeout is never an `*APIError`, so a consumer can tell GitHub's answer from a lost connection.
- Each C error code maps to one sentinel; the `c-interface` spec lists them.

### 4. Context and concurrency

Every call takes a `context.Context` and stops when it ends.
`Listen` returns `context.Cause(ctx)`, so the consumer sees why it stopped.

- `*Client` and `*Set` are safe for concurrent use; `SetMaxRunners` is an atomic store.
- One `Listen` runs per set; each set has its own session and goroutine.
- A handler runs on its set's goroutine, one call at a time, and its return acks the message.
- `Close` cancels every listener, then deletes their sessions within the caller's context.

### 5. Sessions, reconnects and acquisition

Upstream's `Listener.Run` returns on the first failed poll ([research](research.md) 1.2).
scalesets wraps it in a loop:

1. Open a session.
2. Run the upstream listener with a `Scaler` that acquires, converts and calls the handler.
3. On an error, delete the session, wait, and go back to step 1.

The wait follows the `job-listener` spec: 1 to 60 seconds with jitter, or `RetryAfter`.
An auth error or the end of the context leaves the loop.

The `Scaler` acquires every offered job before the handler runs, as the upstream example does.
Each poll sends the set's capacity ([research](research.md) 1.5), and the consumer changes it through `SetMaxRunners`.
How GitHub uses that value is an open question below.

A 409 on a new session counts as a conflict, retried until `ConflictWait`.
That covers a session left by a crashed process, and still stops two live listeners.

### 6. Restart

The library keeps no state, so a restart is the same as a first start:

1. `Connect`, then `Ensure` with the same specs, which reuses each set by name.
2. `Runners` on each set, matched by name against the consumer's own machines.
3. `RemoveRunner` for each runner with no machine.
   For a busy one, `FailJob` with the stored `JobCompletion`, then `RemoveRunner`.
4. `Listen` on each set; the first update gives the current statistics.

### 7. Names and capacity

Set names start with `Config.Prefix`, so `Sets` and `Delete` touch only the consumer's sets.
A runner name is the set name and a suffix, so `Runners` can filter a group's runners by set.
The limits, 45 and 64 characters, are the library's own until contract tests confirm GitHub's.

Capacity is the value each poll sends as the set's most runners.
The consumer reads `Statistics.Assigned` against its own budget to decide how many runners to start.

### 8. Failing a lost runner's job

GitHub fails a lost runner's job only after a long timeout.
The operator rejected both that wait and a REST cancel (operator, 2026-11-22).
`FailJob` therefore makes the call a runner makes when its own worker dies ([research](research.md) 6).

The call needs the run service URL, the plan ID, the job ID and the job's token.
No scale set message has them, and only the runner host sees them at job start.

The consumer captures them there, stores them beside its own record of the runner, and passes them to `FailJob`.
How the host captures the plan ID is a question for the operator below.

### 9. Security

1. The App key lives in `AppKey`, in memory only.
   The library signs RS256 JWTs with the standard library and hands upstream a `JWTProvider`, so the PEM text never reaches upstream.
2. `Credential` wraps a JIT config and a job token.
   Every print path is redacted, and a test logs each type through `slog` and `fmt` and searches the output.
3. Go cannot promise that freed memory is cleared, so `Wipe` clears only the library's own copy.
4. The App needs organization Self-hosted runners read and write, repository Actions read, and Metadata read.
   The first covers scale sets, runner groups, registration tokens and runner listing.
   Actions read covers `ConfirmJob`.
5. Four tokens are in play, and the library handles each one in memory.
   The installation token comes from the App, and the admin token from a registration token, both through upstream.
   The message queue token belongs to a session, and the job token to one job.

### 10. The C interface

`capi/` follows [swift-onepassword's shim][shim]: a handle table, JSON in and out, and a free function.

- It adds `sc_next(handle, set, timeout_ms)`, because updates come from GitHub and need a pull.
- A set waits in its own `sc_next`, so one slow reader does not stall the others.
- Each handle has a context; `sc_close` cancels it, and every waiting `sc_next` selects on it.
- A per-set queue of 16 updates sits between the handler and `sc_next`.
  A full queue blocks the handler, so the message stays unacked and GitHub's queue absorbs the load.
- A JIT config crosses the boundary as a base64 string in the `jit` reply.
  `sc_free` zeroes the reply before it frees it, and the archive never logs replies.
- `v` versions the JSON schema.
  The Swift package and the archive ship in one release, so a mismatch means a broken build.

### 11. The Swift binding

`ScaleSets` is an actor that owns the handle.

- Each call runs `sc_call` on a binding thread and resumes through a checked continuation, so no cooperative thread blocks.
- Each `updates(for:)` starts a thread that loops on `sc_next` with a one second timeout, and yields into the stream.
- The stream buffers 16 updates.
  When it is full, the thread waits, and the wait reaches the Go queue and then GitHub.
- `ScaleSetsError` has one case per C code.
- `RunnerConfig` keeps the config as bytes that never print.
  The consumer hands it to the runner and drops it.

The floor is macOS 26 and Swift tools 6.4, the defaults for our Swift packages.

### 12. Repository and release

The template renders the build:

- the repository layer;
- a go-module component at `.`;
- a swift-package component at `.`, added once `capi/` exists;
- the `go_xcframework` piece on that component, with `xcframework_dir: capi` and `xcframework_module: CScaleSets`.

`xcframework.yml` publishes `capi-<hash>` prereleases, and `xcframework:pin` writes the URL and checksum into `Package.swift`.
verctl tags `vX.Y.Z` from `go.mod`, on a commit whose pin names a complete archive.
`0.0.1` ships the Go library, and the next patch adds `capi/` and Swift.

### 13. Testing

- The fake GitHub lives in `internal/fakegithub`, serves both APIs over `httptest`, and fails a test on an unmet exchange.
- Contract tests replay scrubbed recordings from a public test repository.
- A scrub test fails on token-shaped strings in `testdata/`.
- `capi/` has Go tests, and a C harness that CI builds and runs on Linux and macOS.
- Swift tests run on macOS CI against a fake server binary built from `internal/fakegithub`.
- `live.yml` runs on pushes to `main` and on dispatch, with an App in a test organization; forks never get its secrets.

### 14. The dependency

`go.mod` requires actions/scaleset v0.5.0, which is MIT licensed.
depguard allows only that module and `google/uuid`, whose type the session ID uses, so a new import needs a reviewed change.

Upstream's `go.mod` sets `go 1.27.3`, so the first require raises our `go` line to 1.27.3.
Go 1.27 turns on `encoding/json/v2` by default, and the lint config denies v1.
Each upstream release lands as one update pull request that the contract tests gate.

## Risks / Trade-offs

- [The scale set API is a preview and can change] → Pin upstream exactly, and record contract tests that fail on a changed reply.
- [Upstream's `go.mod` lists its tools, which enter our module graph] → govulncheck reads only linked code, and depguard limits our direct imports.
- [A blocked `sc_next` ties up a thread per set] → Sets are few, and `sc_close` frees them within 100 milliseconds.
- [A panic in the archive would end the host] → Every export recovers.
- [A stored job token is a credential at rest] → The consumer stores it like a JIT config, and deletes it when the job ends.
- [A slow handler delays acks] → That is the back pressure, so the consumer keeps handlers short.

## Migration Plan

A consumer that speaks the protocol itself moves in four steps:

1. Keep its set names under one prefix, so `Ensure` reuses its sets.
2. Stop its own listener before it starts `Listen`, or wait out `ConflictWait`.
3. Replace its session, acquire and JIT code with the library's calls.
4. Store a `JobCompletion` per busy runner, and call `FailJob` for a lost one.

Rollback is the reverse, since the library changes no state on GitHub that the old code cannot read.

## Questions for the operator

Each question names the current default and the requirement that changes if the answer flips.

1. Licence: AGPL-3.0, as our other public repositories use, or MIT, as upstream uses?
   No default; the repository has no licence yet, and pkg.go.dev shows no docs without one.
2. Scope: organization scale sets only, or also enterprise and repository ones?
   Default: organization only, from the `github-sign-in` configuration requirement.
3. Plan ID: how does the runner host capture the plan ID that `FailJob` needs?
   The monitor socket sends the job ID, token and URL but no plan ID.
   May the library add a monitor address to each JIT config it issues?
   No default; the `runners` requirement on `JobCompletion` stands either way.
4. Session conflict: wait `ConflictWait` and fail, or delete the other session and take over?
   Default: wait, from the `job-listener` conflict requirement.
5. Acquisition: take every offered job, or let the handler pick jobs?
   Default: take every job, from the `job-listener` acquisition requirement.
6. The live test: which GitHub App, test organization and public test repository does it use?
   No default; task 5.3 waits on it.
7. Release order: `0.0.1` with Go only, then Swift in the next patch, or wait for both?
   Default: Go first, from tasks 6.1 and 10.1.

## Open Questions

Recorded replies settle these, through the contract and live tests.

1. Does a second session on one set get a 409, and when does GitHub drop a lost session?
2. What does acquire return for a job it already acquired?
3. What are GitHub's real limits for set and runner names?
4. Does a message's `jobId` equal the job ID the run service takes?
5. How long does a job token live, and does it survive a host restart?
6. What JSON field names does `completejob` take, and what does it answer for a finished job?
7. Can `FailJob` end a job that was assigned but never started?
8. Does GitHub assign no more jobs than the capacity a poll sends?

[scaleset]: https://github.com/actions/scaleset/tree/af394d86c0d5024225238b0209043c70193bcfe6
[shim]: https://github.com/victor-software-house/swift-onepassword/blob/73286fb6c360e3dd1223af175ab31394553bfb41/core/shim.go
