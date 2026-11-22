# Spec Delta

## Purpose

Keeps the consumer's scale sets in one runner group, and each set's capacity.
It makes or reuses sets by name, lists them, and deletes them behind a name guard.

## ADDED Requirements

### Requirement: The runner group must exist

`Connect` SHALL look up `Config.RunnerGroup` by name and SHALL return an error that matches `ErrNotFound` when no group has that name.
The library SHALL never create or delete a runner group.

#### Scenario: The group is missing

- **WHEN** a consumer connects with a runner group name that the organization lacks
- **THEN** `Connect` returns an error that matches `ErrNotFound` and names the group

### Requirement: Set names follow one rule

A set name SHALL start with `Config.Prefix`, and SHALL use only lower case letters, digits and hyphens.
It SHALL be at most `MaxSetName` characters, 45.
The library SHALL reject any other name with `ErrInvalidName` before any request.

#### Scenario: A name with upper case letters

- **WHEN** `Ensure` gets a `Spec` named `ci-Linux`
- **THEN** it returns an error that matches `ErrInvalidName`
- **AND** no request reaches GitHub

### Requirement: Ensure makes or reuses each set

`Ensure(ctx, []Spec)` SHALL return one `*Set` per `Spec`, in order.
It SHALL reuse a set in the group with the same name and keep its ID.
It SHALL make the set when none has the name.

#### Scenario: The set exists from an earlier run

- **WHEN** `Ensure` gets a `Spec` whose name a set in the group already has
- **THEN** it returns a `*Set` with that set's ID, and makes no new set

#### Scenario: The set is new

- **WHEN** `Ensure` gets a `Spec` whose name no set in the group has
- **THEN** it makes the set in the group with the spec's labels and returns it

### Requirement: Ensure brings labels in line with the spec

When a reused set's labels differ from `Spec.Labels`, `Ensure` SHALL update the set's labels to the spec's.
A set SHALL always carry its own name as a label.

#### Scenario: A label was added

- **WHEN** a reused set has the labels `[ci-linux]` and the spec lists `[ci-linux, gpu]`
- **THEN** `Ensure` updates the set's labels to `[ci-linux, gpu]`

### Requirement: Ensure leaves other sets alone

`Ensure` SHALL never delete or change a set that is not in its argument.

#### Scenario: An older set stays

- **WHEN** the group has a set `ci-old` and `Ensure` gets only `ci-linux`
- **THEN** `ci-old` still exists after the call

### Requirement: Sets lists only the consumer's sets

`Sets(ctx)` SHALL return a `SetInfo` for each set in the group whose name starts with `Config.Prefix`, with its ID, name, labels and statistics.

#### Scenario: Another program's set shares the group

- **WHEN** the group has sets `ci-linux` and `other-mac`, and the prefix is `ci-`
- **THEN** `Sets` returns only `ci-linux`

### Requirement: Delete refuses names outside the prefix

`Delete(ctx, name)` SHALL return an error that matches `ErrNameGuard` when the name does not start with `Config.Prefix`, and SHALL send no request.
It SHALL return an error that matches `ErrNotFound` when no set in the group has the name.

#### Scenario: A name outside the prefix

- **WHEN** a consumer with the prefix `ci-` calls `Delete` with `other-mac`
- **THEN** `Delete` returns an error that matches `ErrNameGuard`
- **AND** no request reaches GitHub

### Requirement: Delete stops the client's own listener first

When the client listens on the set, `Delete` SHALL stop that listener and close its session before it deletes the set.

#### Scenario: Delete during Listen

- **WHEN** `Listen` runs on `ci-linux` and the consumer calls `Delete` on it
- **THEN** `Listen` returns an error that matches `ErrClosed`, and the set is gone

### Requirement: Capacity goes out with each poll

`Spec.MaxRunners` SHALL set a set's first capacity, and `Set.SetMaxRunners(n)` SHALL change it at any time.
The library SHALL send the current value with each poll, as the set's most runners.
A value below 0 or above 2147483647 SHALL return `ErrInvalidSpec`.

#### Scenario: Capacity drops while a poll waits

- **WHEN** a consumer calls `SetMaxRunners(2)` while a poll waits
- **THEN** the next poll sends 2

#### Scenario: A negative capacity

- **WHEN** a consumer calls `SetMaxRunners(-1)`
- **THEN** the call returns an error that matches `ErrInvalidSpec`, and the capacity stays as it was
