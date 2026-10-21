# Observability Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: Log Context And Coverage

Review structured log context and coverage of failure paths.

- Structured logs should carry investigation fields (target entity id, tenant id, operation name) so a request or target can be traced afterward.
- Failures, unreached branches, and empty results (e.g. a lookup that found nothing) should be logged so the cause is recoverable. Do not log only the happy path while returning the abnormal case silently.
- Logs without any identifier (a bare "failed to process") make incidents untraceable. Each log on a failure path should let you tell which target and which request it came from.

Do not review error wrapping, secret exposure, or log levels in this block; those belong to Focus B.

## Focus B: Error Wrapping, Secrets, And Levels

Review error wrapping vs. duplicated logging, secret exposure, and log-level consistency.

- Errors should not be swallowed; wrap with context using `fmt.Errorf("...: %w", err)` so callers retain `errors.Is`/`errors.As` matching.
- Logging and error propagation responsibilities should not overlap. If a shared middleware logs returned errors, do not also `log` the same error at the call site (duplicate, noisy logs).
- Secrets (tokens, passwords, personal data) must not appear in logs or error messages.
- Log level should match severity: do not log expected input errors at error level (it pollutes monitoring), and do not drop serious failures to info/debug.

Do not review log-context fields or failure-path coverage in this block; those belong to Focus A.
