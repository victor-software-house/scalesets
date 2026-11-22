# Tasks

## 1. Foundation

- [ ] 1.1 Require actions/scaleset v0.5.0 in `go.mod`, which raises the `go` line to 1.27.3, and allow it and `google/uuid` in depguard's `deps` rule.
  Verify: `mise run go:verify` passes, and `go list -m github.com/actions/scaleset` prints v0.5.0.
- [ ] 1.2 Add `Config`, `App`, `AppKey`, `Credential`, `AppKeyFromPEM` and `AppKeyFromFile`, with redaction on every print path.
  Verify: a test logs each type through `slog` and `fmt` and finds no key or config byte.
- [ ] 1.3 Add the sentinel errors, `*RateLimitError` and `*APIError`, and the mapping from upstream errors.
  Verify: a table test maps each upstream error and HTTP status to its sentinel.
- [ ] 1.4 Add `internal/fakegithub`, which serves the Actions service and the REST API and fails a test on an unmet exchange.
  Verify: a test that skips an expected call fails and names it.
- [ ] 1.5 Add `Connect`, the JWT provider, installation tokens for REST, and the runner group lookup.
  Verify: tests against the fake cover a good sign-in, a 401, a rate limit and a missing group.

## 2. Scale sets

- [ ] 2.1 Add the set name rule, `Ensure`, `Sets` and `Delete` with the name guard.
  Verify: tests cover reuse, creation, a label update, a foreign set and a guarded delete.
- [ ] 2.2 Add `SetMaxRunners` and send the value with each poll.
  Verify: a test reads the capacity header the fake receives after a change.
- [ ] 2.3 Document the set API in Go doc comments, with an `Example` for `Ensure`.
  Verify: `go test` runs the example, and `go doc` shows each exported name.

## 3. Listener

- [ ] 3.1 Add `Listen` around upstream's listener, with the initial update, acquisition and conversion to `Update`.
  Verify: tests cover the initial update, two offered jobs and a repeated acquire.
- [ ] 3.2 Add the reconnect loop, backoff, rate limit waits, auth exit and the session conflict wait.
  Verify: `synctest` tests check each wait and the `ErrSessionConflict` exit.
- [ ] 3.3 Add the handler error path, one listener per set, and `Close`.
  Verify: tests show a redelivered message, `ErrListening` and `ErrClosed`.

## 4. Runners

- [ ] 4.1 Add the runner name rule, `JIT`, `RemoveRunner`, `Runner` and `Runners`.
  Verify: tests cover a foreign name, `ErrRunnerExists`, a busy runner and an absent runner.
- [ ] 4.2 Add `ConfirmJob` over the run's jobs, across attempts.
  Verify: tests cover a match, no match and a missing Actions permission.
- [ ] 4.3 Add `JobCompletion` and `FailJob` over the run service's job completion call.
  Verify: a test reads the request the fake receives: path, token and failed conclusion.
- [ ] 4.4 Write the restart steps in the package doc.
  Verify: an `Example` runs the steps against the fake after a simulated crash.

## 5. Contract and live tests

- [ ] 5.1 Record replies from a public test repository into `testdata/contract/`, and add the scrub test.
  Verify: the scrub test fails on a planted token and passes on the recordings.
- [ ] 5.2 Add contract tests that replay the recordings through the library.
  Verify: `mise run go:verify` runs them on Linux CI.
- [ ] 5.3 Add `live.yml` and a `test:live` task, on pushes to `main` and dispatch only.
  Verify: jactionlint and the workflow policy pass, and a dispatched run passes.
- [ ] 5.4 Answer each open question of the design from the recordings and the live run.
  Verify: design.md lists the answer and its evidence under each question.

## 6. First release

- [ ] 6.1 Add a patch fragment and merge the Version PR.
  Verify: verctl tags `v0.0.1`, and `go get` of that version builds in a scratch module.

## 7. C interface

- [ ] 7.1 Add `capi/` as a main package with the five exports, the handle table, the queues, panic recovery and the error codes.
  Verify: Go tests cover each code, `busy`, close during next, and a panic.
- [ ] 7.2 Add the C harness, and run it on Linux in the go-module job.
  Verify: CI runs the harness, and it passes.

## 8. Swift package component

- [ ] 8.1 Add the swift-package entry with `copier update --defaults --data 'components=[{path: ., project: go-module}, {path: ., project: swift-package}]'`.
  Verify: the Template check passes, and `ci.yml` has a macOS job.
- [ ] 8.2 Render the swift-package component at `.` into `.copier-answers.swift-package.yml`, with `go_xcframework` in its pieces, `xcframework_dir=capi`, `xcframework_module=CScaleSets` and `repository=victor-software-house/scalesets`.
  Verify: the Template check passes, and `xcframework.yml` exists.
- [ ] 8.3 Publish the first `capi-<hash>` prerelease, and run the C harness on macOS.
  Verify: `xcframework.yml` creates the release with its zip and checksum, and the harness passes.

## 9. Swift binding

- [ ] 9.1 Add `Package.swift` with the `CScaleSets` binary target, and pin it with `xcframework:pin`.
  Verify: `xcframework:check` passes, and `swift build` resolves the archive.
- [ ] 9.2 Add the `ScaleSets` actor, the stream threads, the typed errors and the redacted credential types in `swift/`.
  Verify: the build passes in Swift 6 mode with warnings as errors.
- [ ] 9.3 Add Swift tests against the fake server binary.
  Verify: the macOS CI job runs them, and they pass.
- [ ] 9.4 Document the Swift API in the README.
  Verify: the README sample compiles in a test target.

## 10. Swift release

- [ ] 10.1 Add a patch fragment and merge the Version PR.
  Verify: verctl tags the patch, and a scratch Swift package resolves it at that exact version.

## Workflow follow-up

- Archive the change once every task above passes, and fill each spec's purpose.
