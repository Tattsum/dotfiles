# State Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: State Scope And Management

Review where state lives and whether global state is used appropriately.

- Keep state as local as the usage allows. Do not promote state to a global store (Redux/Zustand/Pinia/Vuex) when only one component subtree reads it; global state that only one place uses adds coupling and re-render surface for no benefit.
- Do not duplicate server data into global state when a data-fetching layer (React Query / SWR / Nuxt `useAsyncData` etc.) already owns it; two sources of truth drift.
- Derived values should be computed (memo/`computed`/selector) from source state, not stored as a second copy that must be kept in sync manually.
- Do not mutate state directly where the framework expects immutable updates (React) or reactive APIs (Vue `ref`/`reactive`); direct mutation skips updates.
- When a component is reused under a stable `key` without remounting (rendered for a different row/item, or a dialog reopened for a different target), local `useState` from the previous target leaks in. Reset or re-initialize state on identity change (key by the id, or initialize inside the open/id-change path) — otherwise one element's value is written into another's. A module-scope atom has the same problem: it outlives the context it describes (the previous project's page number carries over) unless it is reset on identity change.
- State that must survive going back, a reload, or a shared link belongs in the URL or a persisted store, not component state; an effect that clears it on mount defeats that store. When a change stops writing the selection to the URL, check that links that used to restore it still do.
- Mount an overlay that opens purely from shared state (a URL `?modal=` param, a global atom) exactly once. Rendering it in both a parent and a child opens two instances at once: a doubled backdrop, two form states, competing focus traps.

Report only concrete risks: duplicated/out-of-sync state, over-broad global state, leaked cross-instance state, or updates the framework will miss.

## Focus B: Effects And Async

Review effect dependencies, cleanup, and async handling.

- `useEffect` / `watch` dependency lists must include every reactive value the effect reads. Missing deps cause stale closures; unnecessary deps cause extra runs. Do not silence the linter with an eslint-disable instead of fixing deps.
- Effects that subscribe, set timers, or start requests must clean up (return a cleanup / `onUnmounted` / `AbortController`) to avoid leaks and setState-after-unmount.
- Guard against race conditions when an async result may resolve after inputs changed or the component unmounted (ignore stale responses via an abort flag or `AbortController`).
- A late async cleanup must release only what its own run created. An unconditional `stopStream()` / `srcObject = null` that finishes after a close-and-reopen clears the newer instance's shared resource; guard with a generation token or an identity check.
- Async data flows should handle loading and error states, not only the success path; an unhandled rejection or missing error branch leaves the UI stuck. Do not drop a loading indicator because it is hard to notice on a fast local connection: on a slow network the user sees nothing until the data arrives.
- Do not `await` a function that returns `void` (a data-fetching wrapper, a callback-style API). The `await` resolves immediately, so the next line runs before the refetch finishes and acts on stale state (e.g. selecting a just-created item that is not in the list yet). Check the callee's return type, and return and await the real promise.
- Never call an `onChange` / parent-mutating callback from inside `useEffect` / `watch`. That mutates parent state without an explicit user action and creates surprising update loops; derive the value, or update it on the real event.
- Do not pass objects, `dayjs` instances, or other non-primitive/incidental values into a data-fetching cache key (SWR / React Query key). The key *is* the cache identity, so a per-render or non-primitive key defeats caching (constant refetch). Reduce keys to stable primitives, and keep impure calls (`dayjs()`, `Date.now()`) out of render and out of the key.

Report only concrete correctness risks: stale/missing deps, leaks, races, unhandled async errors, effect-triggered mutations, or cache keys that defeat caching.
