#!/usr/bin/env bash
# Claude Code subagentStatusLine.
# 各サブエージェント行に: <label> · <tokens>k tok
# モデル/思考レベル/ctx% は per-task で正確に取れないため出さない。
# 出力は 1 行 1 JSON: {"id": "...", "content": "..."}
set -euo pipefail

cat | jaq -c '
  def fmt:
    if . >= 1000 then "\((. / 100 | floor) / 10)k"
    else "\(. | floor)"
    end;
  .tasks[]?
  | { id: .id,
      content: ((.name // .label // "agent")
                + " · "
                + ((.tokenCount // 0) | fmt)
                + " tok") }
'
