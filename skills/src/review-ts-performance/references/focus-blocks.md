# Performance Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: Render Performance

Review unnecessary re-renders and memoization.

- Avoid creating new object/array/function literals inline as props when they force a memoized child to re-render every time; hoist or memoize (`useCallback`/`useMemo`, `computed`) when the child is expensive or the value is a dependency.
- Do not over-memoize either: `useMemo`/`memo` on trivial cheap values adds overhead and noise. Apply it where a measured or clearly heavy render/compute justifies it.
- List rendering must use stable, identity-based `key`s (not array index when the list reorders/inserts); unstable keys cause remounts and state loss.
- Avoid deriving heavy values in the render path on every render; compute them from a memo/`computed` keyed on their inputs.
- In Vue, avoid heavy work inside templates/computed that re-runs on unrelated reactive changes; scope reactivity narrowly.

Report only re-render or recompute costs that are concrete given the changed code, not speculative micro-optimizations.

## Focus B: Load And Compute

Review main-thread cost, code splitting, and payload size.

- Heavy synchronous computation (large parsing, sorting, crypto, image work) on the main thread blocks interaction; move it off the render path (web worker, chunked work, server side) when the input can be large.
- Route- and component-level code that is not needed on first paint should be lazy-loaded / code-split (`dynamic import`, `defineAsyncComponent`, `next/dynamic`) rather than shipped in the initial bundle.
- Avoid importing a whole library for one helper when a tree-shakeable/subpath import exists; watch for large dependencies added for small needs.
- Long lists should be virtualized/paginated instead of rendering thousands of DOM nodes at once.
- Images/assets should use appropriate loading (lazy, sized, modern formats) when introduced in the diff.

Report only concrete load/compute costs visible in the changed code.
