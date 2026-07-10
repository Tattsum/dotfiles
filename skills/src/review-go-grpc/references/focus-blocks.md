# gRPC / Protobuf Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: Schema Design And Backward Compatibility

Review protobuf schema design, field numbering, and wire/backward compatibility.

- Field names and types should follow the naming convention (`snake_case`, intent-revealing names). Avoid unnecessary `oneof` or over-nested message structures.
- Do not reuse or collide field numbers with existing fields; a reused number breaks existing clients decoding old data. New fields must take fresh numbers.
- Do not add a new required-in-practice field or remove/renumber an existing field on a message that already has clients; that is a breaking change. Prefer adding `optional` fields.
- Choose `repeated` vs `map` by what the collection naturally is; do not model a keyed lookup as parallel `repeated` lists.
- Treat `optional` semantics correctly: distinguish "unset" from the zero value when the caller needs to tell them apart, and do not rely on presence for a field declared without it.

Report only schema choices that break clients, misrepresent the data shape, or make future evolution harder.

## Focus B: Status Codes, Errors, And API Boundary

Review gRPC status-code choice, error details, retryability, and domain-layer leakage.

- Status codes should match the semantic case: `NotFound`, `InvalidArgument`, `AlreadyExists`, `PermissionDenied`, etc. Do not collapse everything into `Internal` / `Unknown`.
- The status-code conversion belongs at the handler layer. Returning `status.Error(codes.XXX, ...)` from usecase/repository couples domain logic to gRPC and blocks reuse from CLI/batch callers.
- When using error `details`, the structure should be something clients can act on programmatically, not a free-form string.
- Retryable and non-retryable errors should be distinguishable by their status code so clients retry only what is safe.
- Request/Response messages must not leak domain/entity types directly; map at the handler boundary. Leave reasonable (not over-predicted) room for future extension.

Report only concrete issues where the status code, error shape, or message boundary misleads clients or leaks the domain layer.
