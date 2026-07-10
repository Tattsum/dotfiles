# Architecture Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: Component Responsibility

Review whether each component has a single, clear responsibility.

- A component should do one thing. Data fetching, business rules (branching/filtering/calculation), and presentation should not all live in one large component.
- Prefer separating a Container (data/state wiring) from a Presentational component (render only from props) when a component mixes both concerns and that mix makes it hard to test or reuse.
- Business logic should move out of components into composables (Vue) / custom hooks (React) / plain modules when it is not a rendering concern, so it can be unit-tested without mounting the component.
- Data-shaping for the view (formatting, aggregation) should not be scattered across the template/JSX; centralize it where it can stay consistent.

Report only responsibility leaks visible in the changed code that make the component harder to test, reuse, or reason about.

## Focus B: Props And Reuse

Review Props design, prop drilling, and reusable UI/logic extraction.

- Props should not be bloated. When a component takes many loosely related props, split it or group related props into a typed object.
- Avoid deep prop drilling; when the same prop is threaded through several layers only to reach a leaf, prefer context/provide-inject/a store, but only where the sharing is genuine (do not reach for global state for local concerns).
- Repeated UI and repeated logic should be extracted into a shared component or composable/hook once duplication is concrete, not speculatively.
- New components should follow the existing directory/naming conventions of the project rather than introducing a parallel structure.

Report only concrete maintainability risks, not speculative abstraction.
