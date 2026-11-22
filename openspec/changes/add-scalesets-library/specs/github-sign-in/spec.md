# Spec Delta

## Purpose

Signs the library in to GitHub as a GitHub App for one organization, and keeps the App key safe.

## ADDED Requirements

### Requirement: Configuration names one organization and one App

`Connect(ctx, Config)` SHALL take the organization login and the App's client ID, installation ID and private key.
It SHALL also take the runner group, the set name prefix and the session owner.
It SHALL reject a `Config` with any of these missing, with `ErrInvalidConfig`, before any request.

#### Scenario: A field is missing

- **WHEN** a consumer calls `Connect` with no installation ID
- **THEN** `Connect` returns an error that matches `ErrInvalidConfig` and names the field
- **AND** no request reaches GitHub

### Requirement: The App key comes from bytes or a file

The library SHALL build an `AppKey` with `AppKeyFromPEM([]byte)` or `AppKeyFromFile(path)`.
Each SHALL copy the key, parse it as a PEM private key, and return `ErrInvalidConfig` when it does not parse.

#### Scenario: The file has no key

- **WHEN** `AppKeyFromFile` reads a file that is not a PEM private key
- **THEN** it returns an error that matches `ErrInvalidConfig`
- **AND** the error contains no byte of the file

### Requirement: The App key stays in memory and out of logs

The library SHALL keep the App key only in process memory and SHALL never write it to a file, a log or an error.
`AppKey` SHALL print as `AppKey(redacted)` through `String`, `GoString`, `LogValue`, `MarshalJSON` and `fmt` verbs.

#### Scenario: A consumer logs its configuration

- **WHEN** a consumer logs `Config` through `slog` and through `fmt.Sprintf("%+v")`
- **THEN** each output contains `AppKey(redacted)` and no line of the key

### Requirement: The library signs its own App tokens

The library SHALL sign each App JWT with its own copy of the key.
It SHALL pass the JWT to actions/scaleset through a `JWTProvider`, and never pass the key as a PEM string.
It SHALL mint installation tokens for its REST calls from the same key.

#### Scenario: A REST call needs a token

- **WHEN** the library calls a REST endpoint after its installation token expired
- **THEN** it mints a new installation token first, with no call from the consumer

### Requirement: Refused credentials end the call

The library SHALL return an error that matches `ErrAuth` when GitHub answers 401 or 403 to a sign-in or token request, except a rate limit.
It SHALL not retry such a call.

#### Scenario: The installation was removed

- **WHEN** GitHub answers 401 to the installation token request
- **THEN** `Connect` returns an error that matches `ErrAuth`

### Requirement: Rate limits report when to retry

The library SHALL return a `*RateLimitError` with `RetryAfter` when GitHub refuses a call for its rate limit.
`errors.Is(err, ErrRateLimited)` SHALL match it.

#### Scenario: A secondary rate limit

- **WHEN** GitHub answers 403 with a secondary rate limit message and `Retry-After: 60`
- **THEN** the call returns a `*RateLimitError` whose `RetryAfter` is 60 seconds

### Requirement: The App needs only the permissions the design lists

The library SHALL work with an App that has organization Self-hosted runners read and write, repository Actions read, and Metadata read.
It SHALL ask for no other permission.

#### Scenario: Job confirmation with Actions read

- **WHEN** the App has repository Actions read on the job's repository
- **THEN** `ConfirmJob` reads the run's jobs and returns its answer

#### Scenario: The Actions permission is missing

- **WHEN** the App lacks Actions read on the job's repository
- **THEN** `ConfirmJob` returns an error that matches `ErrAuth`

### Requirement: Logs go to the injected logger

The library SHALL log only through the `*slog.Logger` in `Config.Logger`, and discard logs when it is nil.
It SHALL log no token, key, just-in-time config or job token.

#### Scenario: A session opens

- **WHEN** a listener opens a session with a logger in `Config`
- **THEN** the logger gets one Info record with the set name and the session ID, and no token
