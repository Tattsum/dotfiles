#!/usr/bin/env bash

# skill-session-digest の集約結果を fixture で固定する。実ログ（~/.claude・~/.cursor・
# ~/.codex）は日々変わるうえ社内固有名を含むため、テスト入力には使わない。
#
# mktemp を使うので、書き込み先を制限したサンドボックス下では実行できない。
# 「Operation not permitted」で落ちた場合はテストの不具合ではなく実行環境の制約。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
DIGEST="$REPO_ROOT/bin/skill-session-digest"
FIXTURE_ROOT="$(mktemp -d -t skill-session-digest-test)"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

CLAUDE_ROOT="$FIXTURE_ROOT/claude"
CURSOR_ROOT="$FIXTURE_ROOT/cursor"
CODEX_ROOT="$FIXTURE_ROOT/codex"
CURSOR_DB="$FIXTURE_ROOT/state.vscdb"
CURSOR_MISMATCH_DB="$FIXTURE_ROOT/mismatch-state.vscdb"
PROJECT_ROOT="/Users/example/work/sample-project"

mkdir -p "$CLAUDE_ROOT/project" \
  "$CURSOR_ROOT/sample/agent-transcripts/cursor-session/subagents" \
  "$CODEX_ROOT/2026/09/01"

command cat > "$CLAUDE_ROOT/project/claude-session.jsonl" <<'JSONL'
{"type":"ai-title","sessionId":"claude-session","aiTitle":"Claude fixture"}
{"type":"user","timestamp":"2026-09-01T00:00:00.000Z","isSidechain":false,"userType":"external","cwd":"/Users/example/work/sample-project","gitBranch":"main","sessionId":"claude-session","message":{"content":"Claude prompt"}}
{"type":"assistant","timestamp":"2026-09-01T00:01:00.000Z","cwd":"/Users/example/work/sample-project","sessionId":"claude-session","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/Users/example/work/sample-project/claude.txt"}}]}}
JSONL

command cat > "$CLAUDE_ROOT/project/agent-hidden.jsonl" <<'JSONL'
{"type":"user","timestamp":"2026-09-01T00:00:00.000Z","isSidechain":false,"userType":"external","cwd":"/Users/example/work/sample-project","sessionId":"hidden","message":{"content":"Hidden Claude prompt"}}
JSONL

command cat > "$CURSOR_ROOT/sample/agent-transcripts/cursor-session/cursor-session.jsonl" <<'JSONL'
{"role":"user","message":{"content":[{"type":"text","text":"Cursor prompt"}]}}
{"role":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/Users/example/work/sample-project/cursor.txt"}}]}}
JSONL
touch -t 202609010915 "$CURSOR_ROOT/sample/agent-transcripts/cursor-session/cursor-session.jsonl"

command cat > "$CURSOR_ROOT/sample/agent-transcripts/cursor-session/subagents/hidden.jsonl" <<'JSONL'
{"role":"user","message":{"content":[{"type":"text","text":"Hidden Cursor prompt"}]}}
JSONL

cursor_epoch="$(( $(date -j -f '%Y-%m-%d %H:%M:%S %z' '2026-09-01 09:15:00 +0900' '+%s') * 1000 ))"
cursor_value="$(jq -nc --arg cwd "$PROJECT_ROOT" \
  '{name: "Cursor fixture", workspaceIdentifier: {uri: {fsPath: $cwd}}}')"
sqlite3 "$CURSOR_DB" 'CREATE TABLE composerHeaders (composerId TEXT PRIMARY KEY, workspaceId TEXT, createdAt INTEGER, lastUpdatedAt INTEGER, isArchived INTEGER, isSubagent INTEGER, recency INTEGER, checkpointAt INTEGER, value TEXT);'
sqlite3 "$CURSOR_DB" "INSERT INTO composerHeaders (composerId, createdAt, lastUpdatedAt, isSubagent, value) VALUES ('cursor-session', $cursor_epoch, $cursor_epoch, 0, '$cursor_value');"
command cp "$CURSOR_DB" "$CURSOR_MISMATCH_DB"
sqlite3 "$CURSOR_MISMATCH_DB" "UPDATE composerHeaders SET composerId = 'different-session';"

command cat > "$CODEX_ROOT/2026/09/01/rollout-main.jsonl" <<'JSONL'
{"timestamp":"2026-09-01T00:30:00.000Z","type":"session_meta","payload":{"id":"codex-session","cwd":"/Users/example/work/sample-project","source":"cli","git":{"branch":"main"}}}
{"timestamp":"2026-09-01T00:30:00.000Z","type":"event_msg","payload":{"type":"user_message","message":"Codex prompt"}}
{"timestamp":"2026-09-01T00:31:00.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\"cmd\":\"git status\"}"}}
{"timestamp":"2026-09-01T00:32:00.000Z","type":"response_item","payload":{"type":"custom_tool_call","name":"apply_patch","input":"*** Begin Patch\n*** Update File: /Users/example/work/sample-project/codex.txt\n*** End Patch"}}
JSONL

command cat > "$CODEX_ROOT/2026/09/01/rollout-subagent.jsonl" <<'JSONL'
{"timestamp":"2026-09-01T00:30:00.000Z","type":"session_meta","payload":{"id":"codex-subagent","cwd":"/Users/example/work/sample-project","source":{"subagent":{}},"parent_thread_id":"parent","agent_path":"/root/helper","git":{"branch":"main"}}}
{"timestamp":"2026-09-01T00:30:00.000Z","type":"event_msg","payload":{"type":"user_message","message":"Hidden Codex prompt"}}
JSONL

output="$($DIGEST 2026-09-01 --source all \
  --claude-root "$CLAUDE_ROOT" \
  --cursor-root "$CURSOR_ROOT" --cursor-state-db "$CURSOR_DB" \
  --codex-root "$CODEX_ROOT")"

jq -e '
  .meta.schema_version == 2
  and .meta.sources_resolved == ["claude", "cursor", "codex"]
  and .stats.prompts_total == 3
  and .stats.prompts_kept == 3
  and .stats.sessions == 3
  and .stats.tool_calls == 4
  and .stats.projects == 1
  and .stats.by_hour == {"09": 2}
  and .projects[0].sources == ["claude", "codex", "cursor"]
  and .projects[0].time_precision == ["event", "session"]
  and (.projects[0].files_touched | sort) == [
    "/Users/example/work/sample-project/claude.txt",
    "/Users/example/work/sample-project/codex.txt",
    "/Users/example/work/sample-project/cursor.txt"
  ]
  and ([.projects[0].prompts[].text] | sort) == ["Claude prompt", "Codex prompt", "Cursor prompt"]
  and .projects[0].span == {"from": "09:00", "to": "09:32"}
  and .projects[0].span_low_precision == {"from": "09:15", "to": "09:15"}
  and ([.meta.source_stats[] | {source, records}] | sort_by(.source))
      == [{"source": "claude", "records": 2},
          {"source": "codex", "records": 3},
          {"source": "cursor", "records": 2}]
' <<< "$output" >/dev/null

codex_only="$($DIGEST 2026-09-01 --source codex --codex-root "$CODEX_ROOT")"
jq -e '
  .meta.sources_resolved == ["codex"]
  and .stats.prompts_kept == 1
  and .projects[0].sources == ["codex"]
' <<< "$codex_only" >/dev/null

cursor_fallback="$($DIGEST 2026-09-01 --source cursor \
  --cursor-root "$CURSOR_ROOT" --cursor-state-db "$FIXTURE_ROOT/missing-state.vscdb")"
jq -e '
  .stats.prompts_kept == 1
  and .projects[0].time_precision == ["file"]
  and .stats.by_hour == {}
  and (.meta.warnings | any(contains("Cursor metadata DB not found")))
' <<< "$cursor_fallback" >/dev/null

cursor_mismatch="$($DIGEST 2026-09-01 --source cursor \
  --cursor-root "$CURSOR_ROOT" --cursor-state-db "$CURSOR_MISMATCH_DB")"
jq -e '
  .stats.prompts_kept == 1
  and .projects[0].time_precision == ["file"]
  and .stats.by_hour == {}
  and (.meta.warnings | any(contains("Cursor metadata did not match 1 transcript")))
' <<< "$cursor_mismatch" >/dev/null

broken_db="$FIXTURE_ROOT/broken-state.vscdb"
command cp "$CURSOR_DB" "$broken_db"
sqlite3 "$broken_db" 'UPDATE composerHeaders SET createdAt = NULL, lastUpdatedAt = NULL;'
broken_meta="$($DIGEST 2026-09-01 --source all \
  --claude-root "$CLAUDE_ROOT" \
  --cursor-root "$CURSOR_ROOT" --cursor-state-db "$broken_db" \
  --codex-root "$CODEX_ROOT")"
jq -e '
  .meta.sources_resolved == ["claude", "cursor", "codex"]
  and .stats.prompts_kept == 3
  and ([.projects[] | select(.sources == ["cursor"]) | .time_precision] == [["file"]])
  and (.meta.warnings | any(contains("Cursor metadata did not match 1 transcript")))
' <<< "$broken_meta" >/dev/null

partial="$($DIGEST 2026-09-01 --source all \
  --claude-root "$CLAUDE_ROOT" \
  --cursor-root "$FIXTURE_ROOT/missing-cursor" --cursor-state-db "$CURSOR_DB" \
  --codex-root "$CODEX_ROOT")"
jq -e '
  .meta.sources_resolved == ["claude", "codex"]
  and (.meta.warnings | any(contains("Cursor log root not found")))
  and .stats.prompts_kept == 2
' <<< "$partial" >/dev/null

mkdir -p "$CODEX_ROOT/2026/08/15"
command cat > "$CODEX_ROOT/2026/08/15/rollout-nometa.jsonl" <<'JSONL'
{"timestamp":"2026-09-01T00:30:00.000Z","type":"event_msg","payload":{"type":"user_message","message":"orphan"}}
JSONL
touch -t 202609011200 "$CODEX_ROOT/2026/08/15/rollout-nometa.jsonl"
silent="$($DIGEST 2026-09-01 --source codex --codex-root "$CODEX_ROOT/2026/08")"
jq -e '
  .stats.prompts_kept == 0
  and (.meta.warnings | any(contains("0 件しか抽出できなかった")))
' <<< "$silent" >/dev/null

touch -t 202608151200 "$CODEX_ROOT/2026/08/15/rollout-nometa.jsonl"
quiet="$($DIGEST 2026-09-01 --source codex --codex-root "$CODEX_ROOT/2026/08")"
jq -e '.stats.prompts_kept == 0 and .meta.warnings == []' <<< "$quiet" >/dev/null

off_day_cursor="$FIXTURE_ROOT/cursor-offday"
mkdir -p "$off_day_cursor/sample/agent-transcripts/old-session"
command cat > "$off_day_cursor/sample/agent-transcripts/old-session/old-session.jsonl" <<'JSONL'
{"role":"user","message":{"content":[{"type":"text","text":"last month"}]}}
JSONL
touch -t 202608011000 "$off_day_cursor/sample/agent-transcripts/old-session/old-session.jsonl"
off_day_out="$($DIGEST 2026-09-01 --source cursor \
  --cursor-root "$off_day_cursor" --cursor-state-db "$FIXTURE_ROOT/missing-state.vscdb")"
jq -e '
  .stats.prompts_kept == 0
  and .projects == []
  and ([.meta.source_stats[].records] == [0])
  and ((.meta.warnings | any(contains("0 件しか抽出できなかった"))) | not)
  and ((.meta.warnings | any(contains("did not match"))) | not)
' <<< "$off_day_out" >/dev/null

if "$DIGEST" 2026-09-01 --source cursor --cursor-root "$FIXTURE_ROOT/missing-cursor" >/dev/null 2>&1; then
  echo "missing selected source should fail" >&2
  exit 1
fi

echo "skill-session-digest tests passed"
