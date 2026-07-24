# Idioms And Type Safety Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: Type Safety

Review `any` usage, unknown/generics, and validation of external data.

- Avoid `any`. Prefer `unknown` + narrowing, generics, or an explicit type. `any` disables checking and silently propagates.
- External data (API responses, `localStorage`, URL params, `postMessage`) is untyped at runtime. Validate it (e.g. `zod` / `io-ts` / a manual guard) before trusting the static type; a bare `as ResponseType` cast is a lie the compiler cannot check.
- Avoid non-null assertions (`!`) and unchecked casts (`as`) used to silence the compiler; they move failures to runtime. Narrow instead.
- Do not weaken types to make an error disappear (widening to `any`, adding `?` everywhere); fix the underlying shape.
- A cast also suppresses detection of *future* type changes: code that casts around a union keeps compiling when a new variant is added. Prefer validation, `as const`, or a shape that forces a type error on the missing case (e.g. an exhaustive `switch` whose default assigns to `never`). A cast that exists so a new variant will not break the build is a defect.
- Do not mark a prop/parameter optional (`?`) or give it a default when the caller always supplies it. Use a required `T | undefined` union so a forgotten argument is a compile error instead of a silent `undefined`.
- Flag fallbacks that paper over a missing value — `?? ""`, `?? 'default'`, default parameters. An empty or absent value is often the bug itself; the fallback hides it. Surface the absence (fail fast, or type it `T | undefined`) rather than defaulting.

Report only type choices that let malformed data or `undefined` reach code that assumes otherwise.

## Focus B: Type Organization And Idioms

Review shared type definitions, discriminated unions, and TypeScript idioms.

- Domain objects and API contracts should have named types kept in a shared location (`types/`, `@/types`) rather than duplicated inline; duplicated shapes drift.
- Model mutually exclusive states as a discriminated union rather than several optional booleans that allow impossible combinations (e.g. `loading && error && data` all set).
- Use `readonly` / `as const` for values that must not mutate, and prefer precise literal/enum types over bare `string`/`number` where the set is known.
- Follow the project's existing conventions for `interface` vs `type`, import style, and file layout instead of introducing a new pattern.
- Use `Number.isNaN()` for `number`-typed values, not the global `isNaN()`, which coerces its argument and returns `true` for non-numeric strings.
- Use stable IDs — not display names — as keys, option values, and map keys. Display names collide (a user can name a field literally `URL`) and change, silently breaking lookups.
- In i18n'd UIs, keep translation keys identical across locales (same key set, same namespace) and keep sentence-ending punctuation consistent per locale; reuse an existing message key instead of adding a near-duplicate. A key present in one locale but missing in another is a defect.

Report only concrete type-organization risks that cause drift or allow invalid states, not subjective style.

## Focus C: Styling And Markup Discipline

Review design-system adherence, spacing ownership, and accessible markup.

- Do not use arbitrary/ad-hoc values for spacing, size, or color (Tailwind arbitrary values like `bottom-5` / `m-3`, raw `style=`/inline CSS, ad-hoc shared style files). Reference the design system's tokens/scale (spacing and color variables) or a shared style definition so visuals stay consistent and themeable.
- A reusable component should not carry external margin (`mt-2` etc.). Outer spacing is the parent/layout's responsibility; a component that pushes on its surroundings cannot be placed freely.
- Prefer design-system components over raw markup for inputs, buttons, labels, and fields; override only the specific bit that must differ (e.g. a selected style), not the whole element.
- Use semantic HTML and framework primitives for accessibility: `<button>` / `role="button"` for clickable elements (not a clickable `<div>`), the router's link component (`next/link` etc.) for navigation instead of `onClick`, and never nest an `<a>` inside a `<button>`. Decorative images take `alt=""`.

Report only concrete design-system/consistency/accessibility regressions visible in the changed code, deferring project-specific token names to the repo's existing usage.
