---
name: devin-task-triage
description: >-
  Triage a development task to decide whether it should run as a Devin cloud
  session or be handled directly here, then prepare it for whichever path wins.
  Use this skill whenever the user brings a dev/eng task and is deciding where
  to do it, mentions Devin, ACU usage, Devin budget/cost, "should I use Devin
  for this", task routing, scoping a task for Devin, or wants to investigate a
  Jira ticket / Confluence page before acting. Trigger it even when the user
  doesn't say the word "triage" — any time a task could plausibly go to Devin,
  run this first. The goal is to keep Devin for work that produces a merged PR
  and handle investigation/Q&A/scoping here, which both lowers Devin spend and
  raises Devin's PR conversion rate.
---

# Devin Task Triage

Decide, per task, whether to spend a Devin cloud session or handle it here, and
then set the task up to succeed on whichever path is chosen.

## Why this matters

Devin cloud sessions are billed by session size and are only worth it when the
output is a **merged PR (a code change)**. Investigation, Q&A, spec-reading, and
scoping consume the meter without producing a PR. Two effects compound when you
route correctly:

1. **Lower spend** — non-PR work stops burning Devin sessions.
2. **Higher PR conversion** — doing the investigation and scoping *here first*
   means the Devin session starts with a clear, PR-ready brief, so it needs
   fewer sessions per merged PR (less rework / fewer follow-up sessions).

So this is not cost-shifting; pre-work here makes the eventual Devin session
more efficient too.

## Step 1 — Classify the task

Ask one question: **is the intended deliverable a PR / code change?**

- **Yes → Devin-bound.** Go to Step 3 (prepare a Devin Session Brief).
- **No / not yet → handle here.** Go to Step 2.

Tasks that are *not yet* PR-bound (e.g. "why is PROJ-1234 failing?", "what's the
right approach for X?") almost always start as "handle here", then graduate to
Devin-bound once the change is understood. Don't open a Devin session to figure
out *what* to do — only to *do* it.

## Step 2 — Handle it here

Pick the right source. **DeepWiki is repository-only** — it answers questions
about code repos, not Confluence/Jira. Route accordingly:

| Task type | Where |
|---|---|
| Understanding a code repo / "how does X work in repo Y" | DeepWiki (free, inside Devin) or here |
| Jira ticket root-cause, Confluence spec/decision reading | Atlassian connector **here** (NOT DeepWiki) |
| Planning, approach selection, scoping, trade-off discussion | Here |
| Quick code Q&A not needing a PR | Here or DeepWiki |

For Atlassian investigation, use the connected Atlassian/Jira/Confluence tool to
pull the ticket or page, then summarize: what's going on, what the root cause or
requirement is, and what change (if any) is needed. If a code change falls out
of it, the task has now graduated → continue to Step 3.

If no Atlassian connector is available in the current surface, say so and
suggest connecting one rather than spinning up a Devin session just to read a
ticket.

## Step 3 — Prepare the Devin Session Brief

Only reach here when the deliverable is a PR. Produce this brief so the session
converts in one shot. Fill every field; carry over the findings from Step 2 so
Devin doesn't re-investigate.

```
## Devin Session Brief
Goal (one PR-sized outcome): <the single merged PR this session should produce>
Repo / base branch:          <repo>, base <branch>
Linked ticket / doc:         <Jira key and/or Confluence link>
Context (already gathered):  <paste the Step 2 findings — root cause, decisions>
Scope — in:                  <files / areas to change>
Scope — out (do NOT touch):  <guardrails to prevent wandering>
Acceptance criteria:         <how we know it's done; tests/checks that must pass>
Constraints:                 <conventions, libraries, supply-chain / security notes>
Deliverable:                 open a PR titled "<title>" linking <ticket>
```

Then run the pre-flight checklist before launching:

- One PR-sized goal only. If it's two PRs, make two briefs / two sessions.
- Scope-out guardrails are filled in (this is what curbs runaway sessions).
- Acceptance criteria are objectively checkable.
- Context from Step 2 is pasted in, not left for Devin to rediscover.
- Prefer several independently-scoped parallel sessions over one sprawling one.

## Cost hygiene (mention when relevant)

- Keep the per-message on-demand cap low (e.g. a few dollars) so a single
  message can't run away on the meter.
- Reuse Devin Knowledge / Playbooks for recurring code tasks so each session
  doesn't relearn the codebase.
- Review monthly: cost per merged PR and PR-conversion rate (sessions that
  produced a merged PR ÷ total sessions). If conversion drops below ~50%, too
  much non-PR work is leaking onto Devin — rebalance back to Step 2.

## Output format

Always end the triage with a one-line verdict so the user can act immediately:

- `→ Handle here` (and then do Step 2), or
- `→ Devin-bound` (and then present the filled Session Brief).

**Example 1:**
Input: "Why does the api-gateway Sentry timeout keep firing?"
Output: `→ Handle here` — pull the Sentry/Jira context via the Atlassian
connector, find root cause, then decide if a fix PR is warranted.

**Example 2:**
Input: "Migrate the my-app repo's lint+test to GitHub Actions."
Output: `→ Devin-bound` — deliver a filled Session Brief (repo, scope-in =
workflow files, scope-out = app code, acceptance = CI green on a draft PR).
