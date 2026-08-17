# IaC Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: Module Boundaries And Lifecycle

Review how resources are grouped into modules and whether lifecycle boundaries are respected.

- Split modules along lifecycle boundaries. Resources whose create/update/destroy cadence differs — e.g. a long-lived ECS service vs. a Secrets Manager secret whose value is seeded manually before the service can first start — should not sit in one coarse module. Mixing lifecycles forces unrelated resources to apply/destroy together and breaks bootstrap ordering.
- Resources that require an out-of-band or one-time step (manual secret seeding, DNS delegation, account bootstrap) belong in their own module — and often their own PR — so the ordering dependency is explicit rather than hidden inside a monolithic apply.
- Keep a module cohesive around a single concern. A module that contains everything for a product is a smell; prefer several focused modules composed together.
- Do not let `count`/`for_each` depend on values that are unknown until apply (e.g. a resource ARN produced in the same apply). Plan fails with `Invalid count argument` and forces a staged `-target` apply. Gate on a plan-time-known boolean variable and use the ARN only where it is consumed (e.g. `policy_arn`).
- Add `depends_on` for ordering dependencies that do not appear in the reference graph. Resources that only reference each other's ARNs can be created in parallel with a policy attachment, so operations that validate permissions at creation (e.g. `CreateEventSourceMapping`) fail intermittently. Make the hidden edge explicit.
- Do not define a value that must stay in sync across modules with a `default` in more than one place; a missing hand-off then does not surface as a plan error and the copies silently drift. Hold the single source in the environment/composition layer and pass it down. An output that only echoes an input back creates a false dependency edge — avoid it.

Report only grouping/lifecycle issues that create apply-ordering, blast-radius, or bootstrap problems, not stylistic preferences.

## Focus B: Naming And Convention Consistency

Review naming of modules, resources, environments, and subdomains against existing conventions.

- Follow the existing naming conventions for modules, resources, and environments rather than inventing a new pattern. The product name alone is a poor module name — prefer a `<product>-<role>` shape that reads clearly when the module is composed with others.
- Environment/resource identifiers (subdomains, service names) should match the established convention used by sibling products or admin surfaces (e.g. `web`, `contents`) rather than a one-off; a divergent name should carry justification.
- Leave auto-generatable names to the tooling where the project relies on it; introduce explicit names only where the convention, composition clarity, or a platform limit requires it.
- Flag declared-but-unused config: a `data` source that nothing references, or a `variable` received and then dropped (e.g. `var.tags` accepted but never `merge`d into resource tags). Unused declarations mislead readers about what actually influences the plan.
- Expose values that operational procedures need in `outputs`. When a runbook is CLI-based but the function name or queue URL is not output, operators must fish them out of the console each time; surface them so the documented procedure is runnable as written.

Report only naming choices that break consistency with the repo's established conventions or make composition unclear.

## Focus C: Security, Explicit Settings, And Operational Signals

Review least-privilege, security-relevant defaults, and whether alarms actually fire on the condition they name.

- Scope cloud permissions to the resources and actions actually used. An IAM policy on a whole bucket (`arn:.../*`) when the code only touches a prefix (`webhooks/*`) lets the execution role reach other tenants' objects; grant the prefix. Drop actions the implementation never calls (e.g. `s3:ListBucket` when it only `GetObject`s).
- Make security-relevant settings explicit instead of relying on the provider default. An unspecified `sqs_managed_sse_enabled`, log retention, or `memory_size` is unreadable — a reviewer cannot tell "considered and chosen" from "forgotten". Set them explicitly, and align them with sibling resources (e.g. 30-day retention where the rest of the stack uses 30, not the 7-day default).
- Verify alarm metrics match the condition being watched. A gauge vs. counter mixup produces alarms that never fire or stick in ALARM: redrive-moved messages are not counted in `NumberOfMessagesSent`, so an alarm on it never triggers; `ApproximateNumberOfMessagesVisible` is a backlog gauge, so an alarm on it stays in ALARM while the backlog persists and suppresses re-notification for other spikes.

Report only concrete least-privilege, insecure-default, or alarm-correctness risks visible from the changed IaC.
