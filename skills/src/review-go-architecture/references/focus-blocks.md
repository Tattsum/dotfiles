# Architecture Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: Layer Responsibility

Review handler/usecase/entity responsibility boundaries.

- Handler maps protobuf and entities. It must not contain business logic such as branching, filtering, or calculation.
- Usecase composes business logic. It must not directly depend on protobuf types or perform transport mapping.
- Entity owns domain behavior. Domain rules should move into entity/value objects when they are not orchestration concerns.

Report only responsibility leaks that are visible in the changed code.

## Focus B: Domain Placement And External Boundaries

Review domain ownership, anti-corruption boundaries, and semantic service calls.

- Domain knowledge belongs to the package that owns the concept. Do not put another domain's switch, filtering, or field-name knowledge in the caller package.
- External API concepts and response types should be mapped in infrastructure before usecase/entity code sees them.
- Call the method that matches the intent. For example, existence checks should prefer direct get/find semantics over list-and-count/filter patterns when available.

Report only issues where the current location or call choice makes future changes harder or misrepresents intent.

## Focus C: Design Quality

Review YAGNI, impossible branches, reuse, SRP, and shared filtering.

- Application-layer code should avoid unused parameters, impossible branches, or future-only branches. Schema and API contracts may justify future-facing extensibility because changing them is more expensive.
- Do not add defensive checks for states already guaranteed upstream; they imply the state can happen.
- Prefer existing utilities, services, or domain helpers over duplicating similar behavior.
- Split functions with multiple responsibilities into clearer units.
- Shared filtering or conversion logic should be centralized when two user-visible results must stay consistent.

Report only concrete maintainability or correctness risks, not broad style preferences.
