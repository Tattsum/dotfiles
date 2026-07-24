# IaC Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: Module Boundaries And Lifecycle

Review how resources are grouped into modules and whether lifecycle boundaries are respected.

- Split modules along lifecycle boundaries. Resources whose create/update/destroy cadence differs — e.g. a long-lived ECS service vs. a Secrets Manager secret whose value is seeded manually before the service can first start — should not sit in one coarse module. Mixing lifecycles forces unrelated resources to apply/destroy together and breaks bootstrap ordering.
- Resources that require an out-of-band or one-time step (manual secret seeding, DNS delegation, account bootstrap) belong in their own module — and often their own PR — so the ordering dependency is explicit rather than hidden inside a monolithic apply.
- Keep a module cohesive around a single concern. A module that contains everything for a product is a smell; prefer several focused modules composed together.

Report only grouping/lifecycle issues that create apply-ordering, blast-radius, or bootstrap problems, not stylistic preferences.

## Focus B: Naming And Convention Consistency

Review naming of modules, resources, environments, and subdomains against existing conventions.

- Follow the existing naming conventions for modules, resources, and environments rather than inventing a new pattern. The product name alone is a poor module name — prefer a `<product>-<role>` shape that reads clearly when the module is composed with others.
- Environment/resource identifiers (subdomains, service names) should match the established convention used by sibling products or admin surfaces (e.g. `web`, `contents`) rather than a one-off; a divergent name should carry justification.
- Leave auto-generatable names to the tooling where the project relies on it; introduce explicit names only where the convention, composition clarity, or a platform limit requires it.

Report only naming choices that break consistency with the repo's established conventions or make composition unclear.
