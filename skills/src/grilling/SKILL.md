---
name: grilling
description: >-
  Stress-test a plan, decision, or idea when the user explicitly asks to be
  grilled, interviewed about a design, or have a plan challenged.
---

Interview the user until you reach a shared understanding. Map this as a
**design tree**: every decision branches into the decisions that depend on it.

Work the tree in **rounds**. The **frontier** is every decision whose
prerequisites are already settled: the questions you can ask without guessing
at answers that have not been given. Ask at most five frontier questions in one
round, number each question, and provide your recommended answer. Carry the
remaining frontier into the next round.

Format a round like this:

```markdown
❓ **Q1** - **<question title>**: <question body and choices>

➡️ <recommended answer>

---

❓ **Q2** - **<question title>**: <question body and choices>

➡️ <recommended answer>
```

Each answer reshapes the tree: settled decisions push the frontier outward and
unblock questions that depend on them. Recompute the frontier after every
round. A question whose answer depends on an open question belongs to a later
round.

Finding facts is the agent's job, not the user's. Explore the codebase directly
when it can answer a question. For independent investigations, use no more than
two subagents per round and respect the environment's concurrency limit. Do not
ask the user for facts available from the workspace or tools.

The session is done when the frontier is empty. Do not act on the plan until the
user confirms that shared understanding has been reached. After six rounds,
summarize the settled and unresolved branches and ask whether to continue
before starting another round.

## Upstream

Adapted from `mattpocock/skills` at commit
`6654f6b60cd9d5be8b54c6fafe44346dabeb3b76` with bounded rounds, questions,
and subagent usage.
