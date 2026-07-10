# Go Idioms Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: Type Safety

Review pointer/value usage, optional/nil representation, and errors.

- Use pointers for mutable structs and constructor returns unless the type is an immutable value object.
- Primitive optional values may use pointers such as `*string`; optional structs should use the project-specific optional wrapper type.
- Do not model nil separately when zero value and nil have the same business meaning.
- If a value cannot be nil, avoid nil checks that imply it can be. If it can be nil, make that explicit in the type.
- Do not branch on error strings. Use sentinel errors or custom error types with `errors.Is` / `errors.As`.

Report only type choices that affect correctness, readability, or API contracts.

## Focus B: Naming And Function Design

Review naming, responsibility, receiver methods, and package-level API shape.

- Function names must match behavior. Use names like `resolve` or `load` when logic includes more than simple fetch/get behavior.
- `buildXxx` should build from inputs; it should not also fetch data. `getXxx` should not hide transformation or filtering.
- Helpers used only by a handler/usecase instance should usually be receiver methods; package functions are for shared package behavior.
- Use `Get` when not found is an error and `Find` when absence is non-error optional behavior. Use `List` for collections.
- Keep repository interfaces simple; avoid `Exists` or overly specific update/create methods when `Get`/`Find`/`Create`/`Update` covers the contract.
- Define repeated string literals as constants, but avoid constants for one-off values that are clearer inline.
- Keep variables in the narrowest practical scope.
- Align new file names with their primary type where possible.
- Package-scope names should read clearly as `package.Name`, not just within the local file.
- Information-placement split (see CLAUDE.md 情報配置の四分割原則): code carries HOW via naming/structure, comments carry WHY-NOT. Flag comments that restate HOW/WHAT the code already shows through names; a comment should justify a rejected alternative, trade-off, or gotcha, not narrate the code.

Report only naming or API shape issues that mislead readers or expand contracts unnecessarily.

## Focus C: Code Hygiene

Review unused code, duplicate logs, unnecessary data fetches, and slice initialization.

- Remove functions, constants, variables, and parameters made unused by the change.
- Avoid `log.Errorf` at call sites that also return the error when middleware already logs returned errors.
- Check feature flags or conditions before fetching data that may not be needed.
- When the final size is known, initialize slices with capacity: `make([]T, 0, len(items))`. Avoid unexplained capacity formulas such as `len(x)*2`.
- Do not repeat loop-invariant conversions or computations inside loops (e.g. `string(enumValue)` that yields the same result every iteration); hoist them to a constant or precompute outside the loop.

Report only concrete waste, noise, or future maintenance risk.
