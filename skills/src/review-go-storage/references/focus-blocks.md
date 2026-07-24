# Storage Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: DB Schema Design

Review migrations and table design.

- Use `VARCHAR(255)` for non-fixed external or application strings; fixed immutable values such as UUIDs may use fixed-width types.
- Match new table names to existing same-kind tables such as examination or snapshot tables.
- For lifecycle status columns, consider `ENUM` or `CHECK` constraints when the value set is meaningful and stable enough.
- Do not mix different lifecycle or business concepts in one table when a `type` column changes the meaning of other columns.
- Avoid `ON DELETE CASCADE`; prefer explicit application-level deletion so behavior remains visible in code.
- Do not set misleading `DEFAULT` values for fields always written by application code. Use `NOT NULL` when null is not valid; JSON array columns should default to `[]`.
- Use `utf8mb4`. Choose collation by use case: `utf8mb4_0900_ai_ci` when dakuten/handakuten distinction is unnecessary, `utf8mb4_unicode_ci` when multilingual comparison matters, otherwise `utf8mb4_general_ci`. Avoid `utf8mb4_bin` unless case-sensitive comparison is required.
- Use `DATETIME` for time columns. Define audit timestamps as:

```sql
`created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
`updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
```

Report only schema choices that create correctness, migration, or maintenance risk.

## Focus B: Query Performance And Indexing

Review SQL read efficiency: indexes, N+1, filter pushdown, and cache.

- Ensure new `WHERE` and `JOIN` patterns are covered by appropriate indexes. Check composite index order against cardinality and filter usage.
- Avoid N+1 DB queries or external API calls in loops; prefer batch fetches such as `ListByIDs`.
- When the store can apply filter conditions, push filtering into the query instead of fetching all rows and filtering in application code (e.g. use DynamoDB `FilterExpression` to narrow on the store side and avoid wasting read capacity).
- Guard empty slices before constructing SQL `IN` clauses.
- Cache TTL should be the minimum duration that delivers the intended benefit; avoid long TTLs that can hide stale data.

Report only concrete read-path performance risks visible from changed Go or SQL code.

## Focus C: Write Integrity, Concurrency, And External I/O Robustness

Review how writes, concurrency, and external calls behave under failure and contention.

- External API and retryable DB calls should use exponential backoff, not fixed-interval retry. Prefer existing retry libraries when the project already uses them.
- Parse URLs with the `net/url` package instead of string splitting when query strings, fragments, or multiple patterns are possible.
- Escape external values inserted into URL query parameters with `url.QueryEscape` or structured query APIs.
- Protect multi-source reads from timing inconsistencies with transactions or explicit existence checks when needed.
- Do not rely on implicit DB lock semantics (e.g. MySQL gap locks) for concurrency correctness. When only one process may proceed at a time, take an explicit lock — a dedicated lock table/row selected `FOR UPDATE` — so the mutual exclusion is visible and intentional.
- Persist progress incrementally for long or multi-step work, and on error save the steps completed up to the failure point rather than losing partial progress; keep history/audit state detailed enough to reconstruct what ran.
- Control processing order via explicit data (e.g. a `scheduled_at` column) rather than relying on queue FIFO ordering, and pass an idempotency key through enqueue paths so a redelivery does not double-execute.
- Bulk writes should be atomic; splitting into chunks to dodge a transaction size limit (e.g. Firestore's commit-size cap) sacrifices atomicity — make that trade-off deliberate, not accidental.

Report only concrete write-integrity, concurrency, or external-I/O risks visible from changed Go or SQL code.
