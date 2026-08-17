# Architecture Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: Layer Responsibility

Review handler/usecase/entity responsibility boundaries.

- Handler maps protobuf and entities. It must not contain business logic such as branching, filtering, or calculation.
- Usecase composes business logic. It must not directly depend on protobuf types or perform transport mapping.
- Entity owns domain behavior. Domain rules should move into entity/value objects when they are not orchestration concerns.
- Define a sentinel error in the layer where it originates. An error raised by usecase processing (e.g. `ErrProposalAlreadyProcessed`) belongs in the usecase layer, not in a lower layer that does not produce it; the definition site should match where the condition actually arises.
- Keep each usecase in its own file rather than packing several distinct usecases into one. Co-locating unrelated usecases blurs the responsibility boundary and grows a file that changes for many reasons.

Report only responsibility leaks that are visible in the changed code.

## Focus B: Domain Placement And External Boundaries

Review domain ownership, anti-corruption boundaries, and semantic service calls.

- Domain knowledge belongs to the package that owns the concept. Do not put another domain's switch, filtering, or field-name knowledge in the caller package.
- External API concepts and response types should be mapped in infrastructure before usecase/entity code sees them.
- Call the method that matches the intent. For example, existence checks should prefer direct get/find semantics over list-and-count/filter patterns when available.
- An operation's side-effects and cleanup belong inside that operation, not scattered across callers. If disabling an account must also delete related records, encapsulate that in the disable operation rather than making every caller remember the follow-up. Consume/delete a work item after the operation succeeds, not before it runs.
- Do not exhaustively validate a value set owned by an external system. When another system (e.g. an IdP's role list) can add valid values without notice, an allowlist that enumerates the currently-known values rejects future-legitimate inputs and becomes a liability. Map/pass through what you receive rather than gatekeeping against a set you do not control.

Report only issues where the current location or call choice makes future changes harder or misrepresents intent.

## Focus C: Design Quality

Review YAGNI, impossible branches, reuse, SRP, and shared filtering.

- Application-layer code should avoid unused parameters, impossible branches, or future-only branches. Schema and API contracts may justify future-facing extensibility because changing them is more expensive.
- Do not add defensive checks for states already guaranteed upstream; they imply the state can happen.
- Prefer existing utilities, services, or domain helpers over duplicating similar behavior.
- Split functions with multiple responsibilities into clearer units.
- Shared filtering or conversion logic should be centralized when two user-visible results must stay consistent.
- Model polymorphic domain variants as an interface (or sum type), expressing each variant's distinct data at the type level. Do not flatten differing variants into one struct whose optional fields are only meaningful for some kinds; which kind carries which data should be visible in the type, not enforced by convention.
- Do not special-case a single variant in control flow (an `if kind == X` / `IsEvent` branch that diverges from how sibling variants are handled) unless the divergence is justified; handle variants uniformly through the shared abstraction.
- Avoid an indirection layer that carries no value: if a platform/native endpoint (e.g. a provider's REST API) can be called directly, question the extra wrapper/hop rather than adding one (YAGNI).

Report only concrete maintainability or correctness risks, not broad style preferences.
