# Spec Delta

## Purpose

Lets a Swift program use the Go library through the C interface.
The binding uses Swift types, Swift concurrency and typed errors, and adds no protocol logic.

## ADDED Requirements

### Requirement: ScaleSets is an actor

The binding SHALL expose `public actor ScaleSets`, opened with `init(configuration:) async throws(ScaleSetsError)` and closed with `close() async`.
Every public type it takes or returns SHALL be `Sendable`.

#### Scenario: Open and close

- **WHEN** a program opens `ScaleSets` with a valid configuration and later calls `close()`
- **THEN** both calls return, and every stream of the instance ends

### Requirement: The package meets Swift 6 strict concurrency

The package SHALL build in the Swift 6 language mode with complete concurrency checks and warnings as errors.
Only the type that owns the C handle MAY be `@unchecked Sendable`, with the reason in a comment.

#### Scenario: A CI build

- **WHEN** CI builds the package on macOS
- **THEN** the build reports no concurrency diagnostic

### Requirement: The floor is macOS 26

`Package.swift` SHALL declare `swift-tools-version: 6.4` and `platforms: [.macOS(.v26)]`.

#### Scenario: An older deployment target

- **WHEN** a program with a macOS 15 deployment target adds the package
- **THEN** SwiftPM refuses the dependency

### Requirement: Blocking calls stay off the cooperative pool

The binding SHALL call `sc_next` and `sc_call` only on threads it owns, never on a Swift concurrency executor.
Each listening set SHALL get one such thread for its `sc_next` loop.

#### Scenario: Ten sets listen

- **WHEN** a program listens on ten sets
- **THEN** ten binding threads wait in `sc_next`, and no task on the cooperative pool blocks

### Requirement: Each set has an update stream

`updates(for:)` SHALL return an `AsyncThrowingStream<Update, any Error>` that starts the set's listener.
The stream SHALL end normally on `close()`, and with a `ScaleSetsError` when the listener stops on an error.

#### Scenario: The App is refused

- **WHEN** the listener of a set stops with `auth`
- **THEN** the set's stream ends with `ScaleSetsError.auth`

### Requirement: Ending a stream stops its listener

When the consumer ends a stream, or cancels the task that reads it, the binding SHALL stop that set's listener and its thread.
A later `updates(for:)` SHALL start a new listener.

#### Scenario: The reading task is cancelled

- **WHEN** the task that reads the `ci-linux` stream is cancelled
- **THEN** the binding sends `stop` for `ci-linux`, and its thread ends

### Requirement: Streams pass back pressure on

The binding SHALL buffer at most 16 updates per stream.
When the buffer is full, the set's thread SHALL wait before its next `sc_next`.

#### Scenario: A slow reader

- **WHEN** a program leaves 16 updates of one set unread
- **THEN** that set's thread stops calling `sc_next`, and other sets keep flowing

### Requirement: Methods map one to one

The binding SHALL offer `setMaxRunners(_:for:)`, `runnerConfig(set:name:)`, `removeRunner(_:from:)`, `runner(named:in:)`, `runners(in:)`, `confirmJob(repository:runID:runner:)`, `failJob(_:in:)`, `sets()` and `delete(set:)`.
Each SHALL send one request and decode one reply, with no other logic.

#### Scenario: A runner config

- **WHEN** a program calls `runnerConfig(set: "ci-linux", name: "ci-linux-ab12")`
- **THEN** the binding sends one `jit` request and returns its decoded result

### Requirement: Errors are typed

Each method SHALL throw `ScaleSetsError`, with one case per C error code.
A case SHALL carry the reply's message.

#### Scenario: A busy runner

- **WHEN** `removeRunner` gets the code `runner_busy`
- **THEN** it throws `ScaleSetsError.runnerBusy` with the message

### Requirement: Swift keeps credentials out of sight

`AppKey`, `RunnerConfig` and `JobCompletion` SHALL print as redacted through `description`, `debugDescription` and reflection.
They SHALL not be `Codable`.
The binding SHALL zero its own copy of the bytes it sends after the call.

#### Scenario: A program prints a config

- **WHEN** a program prints a `RunnerConfig` with `print` and `dump`
- **THEN** each output contains `redacted` and no byte of the config
