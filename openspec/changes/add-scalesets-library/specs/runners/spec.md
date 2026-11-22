# Spec Delta

## Purpose

Covers single runners: just-in-time configs, removal, lookup and job confirmation.
It also fails a lost runner's job, and supports recovery after a restart.

## ADDED Requirements

### Requirement: Runner names extend the set name

A runner name SHALL be the set name, a hyphen, and a suffix of lower case letters and digits.
It SHALL be at most `MaxRunnerName` characters, 64.
`JIT` SHALL reject any other name with `ErrInvalidName` before any request.

#### Scenario: A name from another set

- **WHEN** a consumer calls `JIT` on `ci-linux` with the name `ci-mac-ab12`
- **THEN** `JIT` returns an error that matches `ErrInvalidName`

### Requirement: JIT returns a credential

`Set.JIT(ctx, name)` SHALL return a `JIT` with the runner's name, its ID and its encoded config as a `Credential`.
The library SHALL keep no copy of the config after it returns.

#### Scenario: A new runner

- **WHEN** a consumer calls `JIT` with `ci-linux-ab12`
- **THEN** it gets a `JIT` whose `RunnerName` is `ci-linux-ab12`, with a nonzero `RunnerID`

### Requirement: Credentials never print

A `Credential` SHALL print as `Credential(redacted)` through `String`, `GoString`, `LogValue`, `MarshalJSON` and `fmt` verbs.
Only `Reveal()` SHALL return its bytes, as a copy, and `Wipe()` SHALL zero them.

#### Scenario: A consumer logs a JIT

- **WHEN** a consumer logs a `JIT` with `slog`
- **THEN** the record contains `Credential(redacted)` and no byte of the config

### Requirement: A taken name fails with ErrRunnerExists

`JIT` SHALL return an error that matches `ErrRunnerExists` when GitHub already has a runner with the name.

#### Scenario: A config for a live name

- **WHEN** a runner `ci-linux-ab12` is registered and the consumer calls `JIT` with that name again
- **THEN** `JIT` returns an error that matches `ErrRunnerExists`

### Requirement: RemoveRunner removes by name

`Set.RemoveRunner(ctx, name)` SHALL find the runner by name and remove it.
It SHALL succeed when GitHub lists no runner with the name.

#### Scenario: The runner is already gone

- **WHEN** a consumer removes `ci-linux-ab12`, and GitHub has no such runner
- **THEN** `RemoveRunner` returns nil

### Requirement: A busy runner is not removed

`RemoveRunner` SHALL return an error that matches `ErrRunnerBusy` when the runner runs a job, and leave it registered.

#### Scenario: Removal during a job

- **WHEN** a consumer removes a runner that runs a job
- **THEN** `RemoveRunner` returns an error that matches `ErrRunnerBusy`

### Requirement: Runner looks up one runner

`Set.Runner(ctx, name)` SHALL return the runner's ID, name and set ID, or an error that matches `ErrNotFound`.

#### Scenario: An unknown name

- **WHEN** a consumer looks up a name that GitHub lacks
- **THEN** `Runner` returns an error that matches `ErrNotFound`

### Requirement: Runners lists the set's runners

`Set.Runners(ctx)` SHALL return each runner of the group whose name starts with the set name and a hyphen.
Each entry SHALL have the runner's ID, name, status and busy flag.

#### Scenario: A restart finds an orphan

- **WHEN** GitHub lists `ci-linux-ab12`, and the consumer has no machine for it
- **THEN** `Runners` returns it, and the consumer can remove it

### Requirement: ConfirmJob checks the runner of a run's job

`Client.ConfirmJob(ctx, repository, runID, runnerName)` SHALL return true when a job of that run, in any attempt, ran on a runner with that name.
It SHALL return false when none did.

#### Scenario: A cache write from a known runner

- **WHEN** run 99 of `acme/app` has a job whose runner is `ci-linux-ab12`
- **THEN** `ConfirmJob(ctx, "acme/app", 99, "ci-linux-ab12")` returns true

#### Scenario: A cache write from a stranger

- **WHEN** no job of run 99 ran on `ci-linux-zz99`
- **THEN** `ConfirmJob` returns false

### Requirement: FailJob ends a lost runner's job as failed

`Set.FailJob(ctx, JobCompletion)` SHALL report the job as failed through the run service's job completion call, the call the runner makes itself.
It SHALL sign the call with the job's token from the `JobCompletion`.

#### Scenario: The host restarted mid-job

- **WHEN** a runner's host restarts during a job, and the consumer stored that job's `JobCompletion`
- **THEN** `FailJob` reports the job as failed
- **AND** the run moves on before GitHub's lost-runner timeout

### Requirement: No other path fails a lost job

The library SHALL not cancel a run through the REST API to end a lost runner's job.
It SHALL not wait for GitHub's lost-runner timeout in place of `FailJob`.

#### Scenario: No completion record

- **WHEN** a consumer has no `JobCompletion` for a lost runner's job
- **THEN** the library offers no fallback, and `FailJob` cannot be called for it

### Requirement: JobCompletion has the call's inputs

`JobCompletion` SHALL have the run service URL, the plan ID, the job ID and the job token as a `Credential`.
The consumer SHALL capture it on the runner host and store it; the library SHALL store nothing.

#### Scenario: A refused token

- **WHEN** the run service refuses the stored token
- **THEN** `FailJob` returns an error that matches `ErrAuth`

### Requirement: A restart starts from GitHub's view

After a restart, `Ensure` SHALL find the same sets by name, and `Runners` SHALL list the runners GitHub still has.
The library SHALL keep no state on disk between runs.

#### Scenario: The consumer crashed

- **WHEN** the consumer restarts and calls `Connect`, `Ensure` and `Runners`
- **THEN** it gets the same set IDs, and the runners it registered before the crash
