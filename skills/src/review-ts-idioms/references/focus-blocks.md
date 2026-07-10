# Idioms And Type Safety Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: Type Safety

Review `any` usage, unknown/generics, and validation of external data.

- Avoid `any`. Prefer `unknown` + narrowing, generics, or an explicit type. `any` disables checking and silently propagates.
- External data (API responses, `localStorage`, URL params, `postMessage`) is untyped at runtime. Validate it (e.g. `zod` / `io-ts` / a manual guard) before trusting the static type; a bare `as ResponseType` cast is a lie the compiler cannot check.
- Avoid non-null assertions (`!`) and unchecked casts (`as`) used to silence the compiler; they move failures to runtime. Narrow instead.
- Do not weaken types to make an error disappear (widening to `any`, adding `?` everywhere); fix the underlying shape.

Report only type choices that let malformed data or `undefined` reach code that assumes otherwise.

## Focus B: Type Organization And Idioms

Review shared type definitions, discriminated unions, and TypeScript idioms.

- Domain objects and API contracts should have named types kept in a shared location (`types/`, `@/types`) rather than duplicated inline; duplicated shapes drift.
- Model mutually exclusive states as a discriminated union rather than several optional booleans that allow impossible combinations (e.g. `loading && error && data` all set).
- Use `readonly` / `as const` for values that must not mutate, and prefer precise literal/enum types over bare `string`/`number` where the set is known.
- Follow the project's existing conventions for `interface` vs `type`, import style, and file layout instead of introducing a new pattern.

Report only concrete type-organization risks that cause drift or allow invalid states, not subjective style.
