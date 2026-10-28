# Storage Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: Schema, Migration, And Stored Data Rules

Review server-side TypeScript that defines or migrates stored data: ORM schema, migration code, import and backfill scripts. `.sql` files are reviewed by the Go storage owner.

- Make a provisional application-side duplicate check cover the same unit as the final unique constraint: the same table, tenant, and the states that occupy the key. A check that compares drafts against published rows, when the constraint only collides drafts with drafts, rejects valid input; a narrower check lets violations through until the index is created.
- Do not persist a column that can be derived from another column and must be kept in sync by hand (a `retryable` flag implied by `status`). Fold it into the state so that impossible combinations cannot be written. DB-generated columns and snapshots kept as history are fine.
- Check JSON null versus SQL NULL, and what DB functions return for them, against the real engine and version, not only the application-side normalization (e.g. MySQL 8.0 `JSON_UNQUOTE(JSON_EXTRACT(...))` yields the string `'null'` for a JSON null). Keep the application-side comparison and any detection SQL on the same rule.
- Migration and bulk-registration code must not create a duplicate of a record that may already exist in the target environment (an organization that is already registered, for example). Check that it looks up the existing key (upsert or existence check) before inserting, rather than assuming the fixture's empty state.

Report only schema, migration, or stored-data risks visible in the changed code.

## Focus B: Query Performance, Indexing, And Read Failures

Review read efficiency and how read failures are told apart.

- Cover new `WHERE` / `JOIN` / `ORDER BY` patterns with an index, and order composite indexes by selectivity and filter usage. Judge from the SQL the ORM actually generates and the expected row counts, not from the call site alone.
- Avoid N+1: a query or external API call inside a loop, or a lazily loaded relation read per item, should be a batch fetch (`IN` list, eager loading, a join).
- Guard empty arrays before building an `IN` clause. Depending on the query builder, an empty list raises an error, emits invalid SQL, or matches nothing or everything.
- Keep 'not found' separate from read and validation failures. A store that throws a generic `Error` for a missing record forces callers to treat absence as a server error (500) or to swallow real failures as absence (404); give not-found its own result or error type.

Report only concrete read-path risks visible in the changed code.

## Focus C: Write Integrity, Failure Handling, And Recovery

Review how writes, background work, and external calls behave under failure and contention.

- Retry a DB or external call only when repeating it is safe (idempotent, or protected by an idempotency key), and use exponential backoff rather than a fixed interval. Prefer the retry helper the project already uses.
- Do not rely on implicit lock behavior (gap locks, isolation-level side effects) for mutual exclusion. Where only one process may proceed, take a lock that is visible in the code, such as `SELECT ... FOR UPDATE` on a dedicated row. Do not add locks where nothing needs mutual exclusion.
- Bulk writes that must stand or fall together should be atomic. Splitting them into chunks to get under a size limit gives up atomicity; make that trade-off deliberate and recoverable (this does not require a single transaction for every batch).
- Every intermediate state (`pending`, `retrying`) must be able to reach a terminal state. Record a failure that is observable synchronously (a failed enqueue or send) as failed at once, with its cause. Keep a time-out rule only as a safety net for failures nobody can observe (a crashed worker), and do not present a time-out as a confirmed failure.
- Decide per record whether it is required. When later decisions or the operator's screen read the record (an execution log, a migration marker), a failed write must fail the operation or stop the side effect it records; swallowing it leaves 'done but not recorded', or a state the next attempt misreads (classified as already handled forever, with no repair path). Values that only assist (a stored message ID) may fail soft. For every swallowed write, trace what the next attempt sees and how a wrong state is left.
- When a synchronous call becomes asynchronous (queue, background job, fire-and-forget), the caller no longer sees its errors, so the old error handling does not carry over. Check where a failure now goes (retry, dead-letter queue, a recorded failed state) and who recovers it.
- When the main work is not idempotent, do not run a follow-up step, such as reporting a result, inside the same time-out and redelivery unit as that work. If the report is slow or fails, the platform times the unit out or redelivers it and re-runs work that had already succeeded. Give the report its own queue or retry unit so that its failure cannot re-trigger the main work.

Report only concrete write-integrity, failure-handling, or recovery risks visible in the changed code.
