# Research

This file lists what the design takes from upstream source.
Each claim cites [actions/scaleset][scaleset] at v0.5.0, commit `af394d8`, or [actions/runner][runner] at commit `7e211dc`.
Claims that no source settles are marked as open, and the design lists them.

## 1. The listener

1. `Listener.Run` first passes a synthetic message with the session's statistics to `Scale` ([listener.go:126][run]).
   Its message ID is `-1` ([listener.go:99][initial]).
2. `Run` returns on the first `GetMessage` error ([listener.go:166][run-err]).
   It never reopens a session, so reconnect and backoff belong to scalesets.
3. A message is acked only after `Scale` returns nil.
   An error stops `Run`, and the message comes back when polling resumes ([listener.go:114][acked]).
   The ack itself ignores cancellation ([listener.go:177][ack]).
4. `Scale` is never called at the same time twice ([listener.go:121][scaler]).
5. `SetMaxRunners` is safe while `Run` runs ([listener.go:72][max]).
   Each poll sends the value in the `X-ScaleSetMaxCapacity` header ([session_client.go:163][header]).

## 2. Sessions and tokens

1. `Client.MessageSessionClient` creates a message session with an owner name ([client.go:735][session]).
   `Close` deletes it ([session_client.go:39][close]).
2. `GetMessage`, `DeleteMessage` and `AcquireJobs` refresh the message queue token once on a 401, then retry ([session_client.go:115][get], [session_client.go:260][acquire]).
3. The client refreshes its admin token by itself before it expires ([client.go:1083][admin]).
4. Each poll waits at most `MessagePollTimeout`, two minutes ([http_client.go:73][poll]).
5. A 409 reply becomes `ConflictError` ([errors.go:262][conflict]).
   No source shows that a second session on one scale set gets a 409, or when GitHub drops a lost session.
   Both are open.

## 3. Jobs

1. A program passes each `JobAvailable` it takes to `AcquireJobs`, or the job stays unassigned ([listener.go:114][acked]).
2. The upstream example acquires first, and states that acquiring an acquired job again does nothing ([scaler.go:33][example]).
   No test pins that, so it is open.
3. A job message has the request ID, the job ID as a string, the run ID and the repository.
   It also has the labels and the times ([types.go:47][base]).
   `JobStarted` and `JobCompleted` add the runner's name and ID, and `JobCompleted` adds the result ([types.go:30][started], [types.go:36][completed]).
4. The statistics count available, acquired, assigned and running jobs, and registered, busy and idle runners ([types.go:133][stats]).

## 4. Scale sets and runners

1. `GetRunnerScaleSet` finds a set by name in a runner group, and returns nil with no error when none exists ([client.go:431][getset]).
2. `CreateRunnerScaleSet`, `UpdateRunnerScaleSet`, `ListRunnerScaleSets` and `DeleteRunnerScaleSet` cover the rest ([client.go:576][create]).
3. `GenerateJitRunnerConfig` returns the runner's ID, name and an encoded config ([client.go:765][jit], [types.go:160][jitcfg]).
4. `GetRunnerByName` returns nil with no error when no runner has the name ([client.go:824][byname]).
5. `RemoveRunner` deletes by ID ([client.go:857][remove]).
   A busy runner yields `JobStillRunningError` ([errors.go:25][busy]).

## 5. Sign-in

1. `GitHubAppAuth` takes the client ID, the installation ID and the PEM key as a string ([client.go:117][appauth]).
2. `NewClientWithJWTProvider` takes a `JWTProvider` in place of a key ([jwt_provider.go:20][jwtp]).
   scalesets uses it to keep the key in its own type.

## 6. Job failure by the runner

The operator ruled out GitHub's lost-runner timeout and cancelling through the REST API (operator, 2026-11-22).
The runner's own path is the target.

1. When its worker dies, the runner listener calls `ForceFailJob`.
   That sends `CompleteJobAsync` with the plan ID, the job ID and `Failed` ([JobDispatcher.cs:1208][forcefail]).
2. The call goes to `completejob` on the run service ([RunServiceHttpClient.cs:123][complete]).
   The body has `PlanID`, `JobID` and `Conclusion` ([CompleteJobRequest.cs:10][request]).
3. It signs in with the job's own token, from the job message's system connection ([JobDispatcher.cs:1244][runserver]).
4. The runner gets the job message from `acquirejob` ([Runner.cs:753][getjob]).
   A second acquire of one job gets a 409 ([Runner.cs:758][again]).
   So the message most likely cannot be fetched again after the host is gone.
5. None of the plan ID, the run service URL or the job token is in a scale set message ([types.go:47][base]).
6. A runner can have a monitor address in its settings ([ConfigurationStore.cs:51][monitor-cfg]).
   At job start, it sends the job ID, the job token and the server URL to that socket ([JobNotification.cs:41][monitor]).
   It sends no plan ID.

So scalesets can make the call, but only the runner host sees what the call needs.
The consumer must capture it there and store it.

## 7. Dependencies

1. scaleset is MIT licensed ([LICENSE][license]).
2. Its root package and `listener` link only `golang-jwt/jwt/v5` and `google/uuid` beyond the standard library.
   Its `go.mod` also lists its tools and the example's Docker client, which enter the module graph ([go.mod][gomod]).

[scaleset]: https://github.com/actions/scaleset/tree/af394d86c0d5024225238b0209043c70193bcfe6
[runner]: https://github.com/actions/runner/tree/7e211dc69c347b78fc398e630e74facb11a13235
[run]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/listener/listener.go#L126
[initial]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/listener/listener.go#L99
[run-err]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/listener/listener.go#L166
[acked]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/listener/listener.go#L114
[ack]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/listener/listener.go#L177
[scaler]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/listener/listener.go#L121
[max]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/listener/listener.go#L72
[header]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/session_client.go#L163
[session]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/client.go#L735
[close]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/session_client.go#L39
[get]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/session_client.go#L115
[acquire]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/session_client.go#L260
[admin]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/client.go#L1083
[poll]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/http_client.go#L73
[conflict]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/errors.go#L262
[example]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/examples/dockerscaleset/scaler.go#L33
[base]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/types.go#L47
[started]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/types.go#L30
[completed]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/types.go#L36
[stats]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/types.go#L133
[getset]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/client.go#L431
[create]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/client.go#L576
[jit]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/client.go#L765
[jitcfg]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/types.go#L160
[byname]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/client.go#L824
[remove]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/client.go#L857
[busy]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/errors.go#L25
[appauth]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/client.go#L117
[jwtp]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/jwt_provider.go#L20
[license]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/LICENSE
[gomod]: https://github.com/actions/scaleset/blob/af394d86c0d5024225238b0209043c70193bcfe6/go.mod
[forcefail]: https://github.com/actions/runner/blob/7e211dc69c347b78fc398e630e74facb11a13235/src/Runner.Listener/JobDispatcher.cs#L1208
[complete]: https://github.com/actions/runner/blob/7e211dc69c347b78fc398e630e74facb11a13235/src/Sdk/RSWebApi/RunServiceHttpClient.cs#L123
[request]: https://github.com/actions/runner/blob/7e211dc69c347b78fc398e630e74facb11a13235/src/Sdk/RSWebApi/Contracts/CompleteJobRequest.cs#L10
[runserver]: https://github.com/actions/runner/blob/7e211dc69c347b78fc398e630e74facb11a13235/src/Runner.Listener/JobDispatcher.cs#L1244
[getjob]: https://github.com/actions/runner/blob/7e211dc69c347b78fc398e630e74facb11a13235/src/Runner.Listener/Runner.cs#L753
[again]: https://github.com/actions/runner/blob/7e211dc69c347b78fc398e630e74facb11a13235/src/Runner.Listener/Runner.cs#L758
[monitor]: https://github.com/actions/runner/blob/7e211dc69c347b78fc398e630e74facb11a13235/src/Runner.Common/JobNotification.cs#L41
[monitor-cfg]: https://github.com/actions/runner/blob/7e211dc69c347b78fc398e630e74facb11a13235/src/Runner.Common/ConfigurationStore.cs#L51
