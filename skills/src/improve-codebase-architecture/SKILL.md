---
name: improve-codebase-architecture
description: Find deepening opportunities in a codebase, informed by the domain language in CONTEXT.md and the decisions in docs/adr/. Writes a self-contained HTML report to the OS temp dir, shows the path for the user to open manually, and (during grilling) asks for confirmation before updating CONTEXT.md or creating ADRs. Use when the user wants to improve architecture, find refactoring opportunities, consolidate tightly-coupled modules, or make a codebase more testable and AI-navigable.
allowed-tools:
  - Read
  - Write
  - Bash
  - Agent
---

# Improve Codebase Architecture

Surface architectural friction and propose **deepening opportunities** — refactors that turn shallow modules into deep ones. The aim is testability and AI-navigability.

## Glossary

Use these terms exactly in every suggestion. Consistent language is the point — don't drift into "component," "service," "API," or "boundary." Full definitions in [LANGUAGE.md](LANGUAGE.md).

- **Module** — anything with an interface and an implementation (function, class, package, slice).
- **Interface** — everything a caller must know to use the module: types, invariants, error modes, ordering, config. Not just the type signature.
- **Implementation** — the code inside.
- **Depth** — leverage at the interface: a lot of behaviour behind a small interface. **Deep** = high leverage. **Shallow** = interface nearly as complex as the implementation.
- **Seam** — where an interface lives; a place behaviour can be altered without editing in place. (Use this, not "boundary.")
- **Adapter** — a concrete thing satisfying an interface at a seam.
- **Leverage** — what callers get from depth.
- **Locality** — what maintainers get from depth: change, bugs, knowledge concentrated in one place.

Key principles (see [LANGUAGE.md](LANGUAGE.md) for the full list):

- **Deletion test**: imagine deleting the module. If complexity vanishes, it was a pass-through. If complexity reappears across N callers, it was earning its keep.
- **The interface is the test surface.**
- **One adapter = hypothetical seam. Two adapters = real seam.**

This skill is _informed_ by the project's domain model. The domain language gives names to good seams; ADRs record decisions the skill should not re-litigate.

## Process

This skill runs as an **orchestrator**. The two heavy, self-contained concerns — scanning the codebase and authoring the HTML report — are each delegated to a dedicated subagent that returns a compact result. Only the interactive grilling stays in the main context. This keeps the full codebase scan and the HTML scaffold out of the main context and keeps each concern isolated.

Before dispatching anything, read (in the main context) the project's domain glossary (`CONTEXT.md`) and any ADRs in the area being touched. These are small, orient the whole run, and must be passed to both subagents so candidates use domain vocabulary and skip ADR-settled decisions.

### 1. Explore — delegated to `Explore` subagent(s)

Dispatch one or more `Explore` subagents (scope each to source directories such as `src/`, `lib/`, or equivalent — never scan secrets, build artefacts, or config outside those roots). Hand each subagent the glossary/ADR context and the deepening criteria below. Tell it to explore organically — not by rigid heuristics — and to report only friction it can back with evidence:

- Where does understanding one concept require bouncing between many small modules?
- Where are modules **shallow** — interface nearly as complex as the implementation?
- Where have pure functions been extracted just for testability, but the real bugs hide in how they're called (no **locality**)?
- Where do tightly-coupled modules leak across their seams?
- Which parts of the codebase are untested, or hard to test through their current interface?

Require each subagent to apply the **deletion test** to anything it flags as shallow (would deleting it concentrate complexity, or just move it? — "concentrates" is the signal) and to return a **compact candidate list**, not raw file dumps. Each candidate carries: **Files** (involved modules), **Problem** (the friction), **Deletion-test result** (concentrates vs. just-moves, with reasoning), and **Suspected depth gain** (what gets deeper and why).

The orchestrator merges and dedupes candidates across subagents. Do NOT author the report or propose interfaces here.

### 2. Author the HTML report — delegated to a separate subagent

Dispatch a single report-authoring subagent. Give it the merged candidate list, the `CONTEXT.md` domain vocabulary, the [LANGUAGE.md](LANGUAGE.md) architecture vocabulary, and [HTML-REPORT.md](HTML-REPORT.md) (the full scaffold). Isolating this in its own subagent is what keeps the large HTML/Tailwind/Mermaid authoring instructions out of the main context. Instruct the subagent to:

- Write a self-contained HTML file to the OS temp directory so nothing lands in the repo. Resolve the temp dir from `$TMPDIR`, falling back to `/tmp` (or `%TEMP%` on Windows), and write to `<tmpdir>/architecture-review-<timestamp>.html` so each run gets a fresh file.
- Render one card per candidate — **Files / Problem / Solution / Benefits / Before-After diagram / Recommendation strength** (`Strong` / `Worth exploring` / `Speculative`, as a badge) — using Tailwind for layout and Mermaid for graph-shaped relationships (call graphs, dependencies, sequences) mixed with hand-built CSS/SVG for more editorial visuals. Be visual; every candidate gets a before/after.
- Express **Benefits** in terms of locality and leverage, and how tests would improve. Do NOT propose interfaces.
- Use `CONTEXT.md` vocabulary for the domain and [LANGUAGE.md](LANGUAGE.md) vocabulary for the architecture: "the Order intake module," not "the FooBarHandler" and not "the Order service."
- Flag **ADR conflicts** only when the friction is real enough to warrant revisiting the ADR, as a clear warning callout (_"contradicts ADR-0007 — but worth reopening because…"_). Don't enumerate every refactor an ADR forbids.
- End with a **Top recommendation** section, then return **only the absolute path** of the written file plus the Top recommendation. It must NOT run `open`, `xdg-open`, or `start`.

The orchestrator then tells the user the absolute path, asks them to open it manually (never auto-open), and asks: "Which of these would you like to explore?"

### 3. Grilling loop — main context (interactive)

This stays in the main context because it is an interactive back-and-forth with the user; do not delegate it. Once the user picks a candidate, drop into a grilling conversation. Walk the design tree with them — constraints, dependencies, the shape of the deepened module, what sits behind the seam, what tests survive.

Side effects happen inline as decisions crystallize, but **always ask the user before writing to any file**:

- **Naming a deepened module after a concept not in `CONTEXT.md`?** Ask: _"Add '[term]' to CONTEXT.md? (y/n)"_ — only write if the user confirms. Same discipline as `/grill-with-docs` (see [CONTEXT-FORMAT.md](../grill-with-docs/CONTEXT-FORMAT.md)). Create the file lazily if it doesn't exist, again only after confirmation.
- **Sharpening a fuzzy term during the conversation?** Propose the update and show the diff — write only after user confirmation.
- **User rejects the candidate with a load-bearing reason?** Offer an ADR, framed as: _"Want me to record this as an ADR so future architecture reviews don't re-suggest it?"_ — create the file only if the user accepts. Only offer when the reason would actually be needed by a future explorer to avoid re-suggesting the same thing — skip ephemeral reasons ("not worth it right now") and self-evident ones. See [ADR-FORMAT.md](../grill-with-docs/ADR-FORMAT.md).
- **Want to explore alternative interfaces for the deepened module?** See [INTERFACE-DESIGN.md](INTERFACE-DESIGN.md).
