# Spec Delta

## Purpose

Exposes the Go library to other languages through a few C functions that take and return JSON, so each binding stays a thin layer.

## ADDED Requirements

### Requirement: Five exported functions

The archive SHALL export `sc_open(config)`, `sc_call(handle, request)`, `sc_next(handle, set, timeout_ms)`, `sc_close(handle)` and `sc_free(reply)`.
`config`, `request` and `set` SHALL be UTF-8 C strings, `handle` a `uint64_t`, and `timeout_ms` an `int32_t`.

#### Scenario: Open and close

- **WHEN** a host calls `sc_open` with a valid config, then `sc_close` with the handle from the reply
- **THEN** each call returns, and the host frees each reply with `sc_free`

### Requirement: The archive owns its replies

Each reply SHALL be a string the archive allocates, and the host SHALL free it once with `sc_free`.
The archive SHALL copy every input before it returns, and SHALL zero a reply's bytes in `sc_free` before it frees them.

#### Scenario: A reply with a config

- **WHEN** the host frees a `jit` reply with `sc_free`
- **THEN** the archive overwrites the reply with zeros, then frees it

### Requirement: Calls are safe from any thread

Each function SHALL be safe to call from any thread, and `sc_call` from many threads at once.
Only one `sc_next` per set and handle SHALL wait at a time; a second SHALL get the error code `busy`.

#### Scenario: Two waits on one set

- **WHEN** two threads call `sc_next` for one set at once
- **THEN** one waits, and the other gets an error reply with the code `busy`

### Requirement: A Go panic becomes an error reply

Each exported function SHALL recover a Go panic and return an error reply with the code `internal`.
A panic SHALL never end the host process.

#### Scenario: A bug panics

- **WHEN** a call panics inside the archive
- **THEN** the host gets an error reply with the code `internal`, and keeps running

### Requirement: Every message has a schema version

Every config, request and reply SHALL have the integer field `v`, now 1.
A change that only adds fields SHALL keep `v`, and each side SHALL ignore fields it does not know.
A host that sends a `v` the archive lacks SHALL get the code `unsupported_version`.

#### Scenario: A newer host

- **WHEN** a host sends a request with `v` 2 to an archive that knows only 1
- **THEN** the reply has the error code `unsupported_version`

### Requirement: Replies have a result or an error

A reply SHALL have either `result` or `error`, never both.
`error` SHALL have a `code` and a `message`; `sc_open`'s result SHALL have the `handle`.

#### Scenario: A runner is busy

- **WHEN** a `remove` request names a busy runner
- **THEN** the reply is `{"v":1,"error":{"code":"runner_busy","message":"…"}}`

### Requirement: Fields follow the Go API

A request SHALL have `method`, `set` when the method acts on a set, and the Go call's other parameters as lower camel case fields.
A result SHALL be the Go return value in the same form, with a `Credential` as base64 text.

#### Scenario: A jit request

- **WHEN** a host sends `{"v":1,"method":"jit","set":"ci-linux","runner":"ci-linux-ab12"}`
- **THEN** the result is `{"runnerName":"ci-linux-ab12","runnerId":7,"config":"<base64>"}`

### Requirement: The open config mirrors Config

The `sc_open` config SHALL have `organization`, `runnerGroup`, `prefix`, `owner`, `conflictWaitMs`, `logLevel`, `app` and `sets`.
`app` SHALL have `clientId`, `installationId` and `privateKey` as PEM text, and each entry of `sets` a `Spec`.
The archive SHALL write its logs to standard error as JSON lines at `logLevel`.

#### Scenario: Open with two sets

- **WHEN** a host opens with `"sets":[{"name":"ci-linux","labels":["ci-linux"],"maxRunners":4},{"name":"ci-mac","maxRunners":2}]`
- **THEN** the archive ensures both sets, and the result has the `handle`

### Requirement: An update mirrors Update

An update SHALL have `set`, `messageId`, `statistics`, `available`, `assigned`, `started`, `completed` and `acquired`.
Each job SHALL have `requestId`, `runId`, `jobId`, `repository`, `workflowRef`, `name`, `labels`, `runner`, `runnerId`, `result`, `queued`, `assigned` and `finished`, with times in RFC 3339.

#### Scenario: A job starts

- **WHEN** runner `ci-linux-ab12` starts request 11
- **THEN** the update's `started` has a job with `"requestId":11` and `"runner":"ci-linux-ab12"`

### Requirement: Error codes form a closed set

`code` SHALL be one of `bad_request`, `unsupported_version`, `unknown_handle`, `closed`, `busy`, `invalid_config`, `invalid_name` and `name_guard`.
The rest are `not_found`, `runner_exists`, `runner_busy`, `listening`, `auth`, `rate_limited`, `session_conflict`, `network`, `github` and `internal`.
Each Go error SHALL map to one code.

#### Scenario: A refused key

- **WHEN** `sc_open` gets a key that GitHub refuses
- **THEN** the reply has the error code `auth`

### Requirement: Requests name one method

A request SHALL name one method: `capacity`, `listen`, `stop`, `jit`, `remove`, `runner`, `runners`, `confirm`, `fail`, `sets` or `delete`.
An unknown method SHALL get the code `bad_request`.

#### Scenario: A typo in the method

- **WHEN** a request names the method `jitt`
- **THEN** the reply has the error code `bad_request`

### Requirement: next returns one update, a timeout, or closed

`sc_next` SHALL wait up to `timeout_ms` for the set's next update.
It SHALL return `{"v":1,"result":{"update":…}}`, `{"v":1,"result":{"timeout":true}}` or `{"v":1,"result":{"closed":true}}`.

#### Scenario: Nothing arrives

- **WHEN** no update arrives within `timeout_ms`
- **THEN** `sc_next` returns the timeout result

### Requirement: Close wakes a waiting next

`sc_close` SHALL cancel the handle's work, and a waiting `sc_next` SHALL return the closed result within 100 milliseconds.
Later calls on the handle SHALL get the code `closed`, and `sc_close` SHALL do nothing a second time.

#### Scenario: Close during a wait

- **WHEN** a thread waits in `sc_next` and another calls `sc_close`
- **THEN** the wait returns the closed result within 100 milliseconds

### Requirement: Handles are never reused

Each `sc_open` SHALL return a new handle, and a closed handle SHALL never name another client.

#### Scenario: A stale handle

- **WHEN** a host calls `sc_call` with a handle it closed
- **THEN** the reply has the error code `closed`

### Requirement: Slow readers slow the listener

The archive SHALL queue at most 16 updates per set.
When the queue is full, the listener SHALL wait to ack until `sc_next` takes one.

#### Scenario: The host stops reading

- **WHEN** the host leaves 16 updates of a set unread
- **THEN** the set's listener acks no further message until the host reads one
