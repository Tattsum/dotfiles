# Test Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: Test Strategy And Behavior

Review what is tested and how tests reach into components.

- Test observable behavior, not implementation detail. Query by role/text/label (Testing Library, Vue Test Utils) and assert what the user sees, rather than asserting internal state, private methods, or component instance internals.
- Logic-bearing units (composables/hooks, reducers/stores, pure helpers with branching or calculation) should have tests. Trivial pure-presentational components and one-line passthroughs do not each need a test.
- Prefer testing a composable/hook or module directly over mounting a whole component just to exercise its logic; mount when the interaction/render is the thing under test.
- Do not assert on snapshot blobs as the only check for behavior; large snapshots pass through real regressions and rot.

Report only concrete gaps or misdirected tests, not a demand for blanket coverage.

## Focus B: Test Quality

Review assertions, async handling, mocking, and false-negative risk.

- Prefer concrete expected values over `toBeTruthy`/`toBeDefined`/length-only checks that pass on wrong data.
- Avoid zero/empty expected values (`0`, `""`, `false`, `null`, `undefined`) that are indistinguishable from missing initialization; use distinctive values like `42` / `"test_value"`.
- Async UI must be awaited properly (`findBy*`, `waitFor`, `await nextTick`) instead of `getBy*` immediately after an async action, which is flaky or asserts the pre-update DOM.
- Mock only true external boundaries (network, timers, browser APIs). Do not mock the component/composable under test or internal modules; that tests the mock, not the code.
- Include boundary and error cases (empty list, loading, failed request, max/min inputs), not only the happy path.
- Reset shared mocks/handlers between tests so state does not leak and cause order-dependent passes.

Report only concrete quality risks that let a bug pass or make the test flaky.
