---
name: grill-me
description: 計画・設計を、決定事項の依存関係に沿って1問ずつ問い詰め、共通理解に達するまで掘り下げる。各問は推奨を先頭に置いた2〜3択で、Claude Code では AskUserQuestion、Codex では Plan モードの request_user_input で選ばせ、どちらも使えないときは推奨を含めた平文の1問にする。ユーザーが「grill して」「この計画を詰めて」などと明示的に求めたとき、または dotfiles-plan-first の合意形成フェーズ（Phase 4）から呼ぶ。それ以外の会話では自分から起動しない。
---

Interview the user until you reach a shared understanding. Map this as a
**design tree**: every decision branches into the decisions that depend on it.

The **frontier** is every decision whose prerequisites are already settled:
the questions you can ask without guessing at answers that have not been given.
Ask **one question at a time**. From the frontier, pick the decision that
unblocks the most other decisions, or the one that costs the most if it goes
wrong. Ask it as described in [Asking a question](#asking-a-question), and wait
for the answer before you pick the next one. Each answer reshapes the tree, so
recompute the frontier after every answer.

Finding facts is the agent's job, not the user's. Explore the codebase directly
when it can answer a question. Between two questions, use no more than two
subagents for independent investigations and respect the environment's
concurrency limit. Do not ask the user for facts available from the workspace
or tools.

The session is done when the frontier is empty. Do not act on the plan until the
user confirms that shared understanding has been reached. After fifteen
questions, summarize the settled and unresolved branches and ask whether to
continue before asking another one.

## Asking a question

Every question in this skill needs the user's answer. Do not settle it yourself
with an assumption, even when the environment's instructions prefer assumptions
or say to go with the recommended option when no answer comes back. Ask from
the main conversation only: subagents cannot reach the user.

### Content

- Before the question, write at most three short lines of context: what you
  found and why this decision matters now. The question dialog may hide them,
  so the question and its options must be understandable on their own.
- `question`: one sentence. Word it so that choosing the first option accepts
  your recommendation.
- `header`: 12 characters or fewer.
- `options`: two or three mutually exclusive choices. Put your recommendation
  first and end its label with `(Recommended)`. Each label is one to five
  words, and each description is one sentence on the effect or trade-off of
  choosing it. Do not add an "Other" option: both tools add a free-text answer
  automatically. If more than three choices are plausible, offer the strongest
  ones and leave the rest to the free-text answer, or split the decision.

### Which way to ask

1. **`AskUserQuestion` is available (Claude Code)**: call it with exactly one
   question and `multiSelect: false`. This skill relies on the tool, so ask
   even when the session is in auto mode.
2. **`request_user_input` is available and its description lists your current
   mode (Codex)**: call it with exactly one question, and give the question a
   snake_case `id`. In Default mode the tool can be listed while its
   description says it is only available in Plan mode. Calling it then fails,
   so treat that as case 3.
3. **No question tool can be used** (Codex Default mode, `codex exec`,
   `claude -p`, or a host without such a tool): ask in plain text. Write one
   sentence that proposes your recommendation so that "yes" accepts it, and
   name the main alternative in prose. Do not list numbered or bulleted
   choices, because Codex Default mode forbids multiple-choice questions
   written as text. On Codex, add this line once per session: 「Shift+Tab か
   /plan で Plan モードに切り替えると、選択式で答えられます。」 Then end your
   turn.

```markdown
❓ **<header>**: <one or two sentences of context>.
<recommendation> で進めてよいですか？
<main alternative> にしたい場合や別の案があれば、そう書いてください。
```

If the tool returns no answer or the user dismisses the dialog, ask the same
question once in plain text as in case 3 and end your turn. Do not move on to
the next question.

## Upstream

Adapted from `mattpocock/skills` at commit
`6654f6b60cd9d5be8b54c6fafe44346dabeb3b76` (the `grill-me` entry point and the
`grilling` skill it delegated to, merged into one) with bounded subagent usage.
Upstream asks the whole frontier in one round of numbered questions. This
version asks one question at a time through the host's question tool, so the
user answers by selecting an option. The rule that one answer accepts the
recommendation comes from upstream commit `95249b0` ("word questions so yes
accepts the recommendation"). Model invocation is allowed so that
`dotfiles-plan-first` can call it during its agreement phase.
