# Test Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: Test Strategy

Review which tests should exist and how expensive test setup is structured.

- Integration tests have expensive setup. Share setup where practical instead of repeating it for each case; split assertions with `t.Run` or comments when that preserves readability.
- Do not use `t.Parallel()` for stateful tests that share DB setup or cleanup.
- Repository implementations such as `Get`, `Create`, `Update`, and `Delete` should usually have tests that hit the real DB, not only mocks. Place tests beside the implementation file.
- New API endpoints should have integration tests covering handler -> usecase -> repository behavior.
- Logic-bearing functions, especially entity/valueobject methods and utilities with branching, calculation, or transformation, should have unit tests. Trivial getters/setters and pure mapping can be covered indirectly.

Do not review assertion granularity, zero values, boundary values, or false-negative details in this block; those belong to Focus B.

## Focus B: Test Quality

Review assertion quality, false-negative risk, boundary coverage, and layer-appropriate checks.

- For DB-persisted values in integration test data, use literal values instead of production constants so constant regressions fail tests.
- Avoid default or zero values such as `0`, `""`, `false`, and `nil` in setup or expected values when they could mask missing initialization.
- Verify behavior appropriate to the tested layer. Handler/API tests should assert request/response behavior; unit tests should cover internal domain logic.
- Prefer concrete expected values over only `NotNil`, `NotEmpty`, or length assertions.
- Integration assertions should cover fields relevant to the method contract without asserting unrelated response details.
- API response format, filtering, sorting, and pagination rules should be visible in tests.
- Include boundary cases for pagination, date ranges, string length, empty lists, and upper limits where those boundaries matter.

Do not review whether a test file should exist in this block; that belongs to Focus A.
