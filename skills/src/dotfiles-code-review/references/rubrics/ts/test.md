# Test Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: Test Strategy And Behavior

Review what is tested and how tests reach into components.

- Test observable behavior, not implementation detail. Query by role/text/label (Testing Library, Vue Test Utils) and assert what the user sees, rather than asserting internal state, private methods, or component instance internals.
- Logic-bearing units (composables/hooks, reducers/stores, pure helpers with branching or calculation) should have tests. Trivial pure-presentational components and one-line passthroughs do not each need a test.
- Prefer testing a composable/hook or module directly over mounting a whole component just to exercise its logic; mount when the interaction/render is the thing under test.
- Do not assert on snapshot blobs as the only check for behavior; large snapshots pass through real regressions and rot.
- Verify the test actually reaches the code path it claims to exercise. Input that is rejected upstream (e.g. a 50KB payload bounced by Node's `maxHeaderSize` before the handler runs) never hits the app code, so the test asserts the platform, not the code. Confirm the handler/branch is entered (spy call count, an observable side effect) — a test that passes without executing the target is a false positive.

Report only concrete gaps or misdirected tests, not a demand for blanket coverage.

## Focus B: Test Quality

Review assertions, async handling, mocking, and false-negative risk.

- Prefer concrete expected values over `toBeTruthy`/`toBeDefined`/length-only checks that pass on wrong data.
- Avoid zero/empty expected values (`0`, `""`, `false`, `null`, `undefined`) that are indistinguishable from missing initialization; use distinctive values like `42` / `"test_value"`.
- Async UI must be awaited properly (`findBy*`, `waitFor`, `await nextTick`) instead of `getBy*` immediately after an async action, which is flaky or asserts the pre-update DOM.
- Mock only true external boundaries (network, timers, browser APIs). Do not mock the component/composable under test or internal modules; that tests the mock, not the code.
- Include boundary and error cases (empty list, loading, failed request, max/min inputs), not only the happy path.
- Reset shared mocks/handlers between tests so state does not leak and cause order-dependent passes.
- Assert the arguments a mock was called with (`toHaveBeenCalledWith`), not just that it resolved. A mock that resolves for any argument keeps every test green even when the code passes the wrong key (e.g. `getOrganizationById(account.uid)` with a mixed-up id), and only production hits the real mismatch.
- Keep `try`/`catch` in a test scoped so it cannot swallow an `AssertionError`. A broad `try` around the assertion turns a real failure into a silently caught error; narrow the `try` to the throwing call, or rethrow errors without an expected shape.

Report only concrete quality risks that let a bug pass or make the test flaky.
