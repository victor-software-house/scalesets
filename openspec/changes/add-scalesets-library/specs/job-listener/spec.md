# Spec Delta

## Purpose

Listens for a scale set's jobs through a message session, and takes every job GitHub offers.
The consumer gets one update per message, across reconnects.

## ADDED Requirements

### Requirement: Listen runs until its context ends

`Set.Listen(ctx, Handler)` SHALL open a message session with `Config.Owner` as its owner, and poll it until `ctx` ends.
It SHALL then close the session and return `context.Cause(ctx)`.

#### Scenario: The consumer stops

- **WHEN** the consumer cancels the context of a running `Listen`
- **THEN** `Listen` deletes its session and returns the cancel cause

### Requirement: The first update carries the session's statistics

Each new session SHALL start with one `Update` whose `MessageID` is `InitialMessage`, -1, with the session's statistics and no jobs.

#### Scenario: A session opens

- **WHEN** `Listen` opens a session on a set with 3 assigned jobs
- **THEN** the handler gets an `Update` with `MessageID` -1 and `Statistics.Assigned` 3

### Requirement: The library acquires every offered job

Before the handler sees a message, the library SHALL pass every `JobAvailable` request ID in it to the acquire call.
`Update.Available` SHALL list the offered jobs, and `Update.Acquired` the request IDs GitHub reports as acquired.

#### Scenario: Two jobs are offered

- **WHEN** a message offers jobs 11 and 12, and GitHub acquires both
- **THEN** the handler gets both in `Available`, and `Acquired` is `[11, 12]`

### Requirement: Acquisition tolerates repeats

The library SHALL treat a repeated acquire of a request ID as a success with no new job.
A redelivered message SHALL lead to one more acquire call and no error.

#### Scenario: A message comes back

- **WHEN** a message that offered job 11 comes back after a reconnect
- **THEN** the library acquires 11 again, and the handler gets the message again with no error

### Requirement: A handler error leaves the message unacked

When the handler returns an error, the library SHALL not ack the message, SHALL log the error at Warn, and SHALL reconnect.
The message SHALL come back to the handler.

#### Scenario: The handler fails once

- **WHEN** the handler returns an error for message 7
- **THEN** `Listen` reconnects, and the handler gets message 7 again

### Requirement: One handler call at a time per set

The library SHALL never call one set's handler while that handler runs.
Handlers of different sets MAY run at the same time.

#### Scenario: Two sets listen

- **WHEN** two sets listen and each gets a message
- **THEN** each handler runs once, and neither runs twice at once

### Requirement: One listener per set per client

A second `Listen` on a set that this client already listens on SHALL return an error that matches `ErrListening` at once.

#### Scenario: Listen twice

- **WHEN** a consumer calls `Listen` on a set while its first `Listen` runs
- **THEN** the second call returns an error that matches `ErrListening`

### Requirement: Failed polls reconnect with backoff

After a failed poll, the library SHALL delete the session, wait, and open a new one.
The wait SHALL start at 1 second, double up to 60 seconds, vary by 20 percent, and reset after a good poll.

#### Scenario: GitHub answers 503 three times

- **WHEN** three polls in a row fail with 503
- **THEN** `Listen` waits about 1, 2 and 4 seconds between new sessions, and keeps running

### Requirement: Rate limits set the wait

When GitHub refuses a call for its rate limit, the library SHALL wait `RetryAfter` before the next session.
With no hint, it SHALL wait at least 60 seconds.

#### Scenario: Retry-After is 30 seconds

- **WHEN** a poll fails with a rate limit and `Retry-After: 30`
- **THEN** `Listen` opens the next session no sooner than 30 seconds later

### Requirement: Refused credentials end Listen

`Listen` SHALL return an error that matches `ErrAuth` when GitHub refuses the App's credentials, and SHALL not retry.

#### Scenario: The App is suspended

- **WHEN** a new session request gets 401 after the admin token refresh
- **THEN** `Listen` returns an error that matches `ErrAuth`

### Requirement: A session conflict waits, then fails

When GitHub refuses a new session because another session exists, the library SHALL retry with the backoff for `Config.ConflictWait`, 5 minutes by default.
It SHALL then return an error that matches `ErrSessionConflict`.

#### Scenario: A crashed process left a session

- **WHEN** a session from a crashed process expires within `ConflictWait`
- **THEN** `Listen` opens its session and runs

#### Scenario: Another process still listens

- **WHEN** another process keeps its session past `ConflictWait`
- **THEN** `Listen` returns an error that matches `ErrSessionConflict`

### Requirement: Tokens refresh without the consumer

The library SHALL renew the admin token and the message queue token itself.
An expired token SHALL never reach the consumer as an error.

#### Scenario: The queue token expires

- **WHEN** a poll gets 401 for an expired queue token
- **THEN** the library refreshes it and polls again, and the handler sees nothing

### Requirement: Close ends every listener

`Client.Close(ctx)` SHALL stop every `Listen` of the client and delete its sessions within `ctx`.
Each `Listen` SHALL return an error that matches `ErrClosed`, and every later call SHALL too.

#### Scenario: Close with two listeners

- **WHEN** two sets listen and the consumer calls `Close`
- **THEN** both `Listen` calls return `ErrClosed`, and both sessions are gone
