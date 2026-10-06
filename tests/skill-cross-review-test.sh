#!/usr/bin/env bash

# skill-cross-review の入出力契約を、偽の codex / claude で固定する。本物を呼ぶと
# 課金と外部送信が起きるうえ、レビュー本文が実行ごとに変わり検証の軸にならない。
#
# mktemp を使うので、書き込み先を制限したサンドボックス下では $TMPDIR 以外に作れない。
# 「Operation not permitted」で落ちた場合はテストの不具合ではなく実行環境の制約。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
CROSS_REVIEW="$REPO_ROOT/bin/skill-cross-review"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/skill-cross-review-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

# 「相手のコマンドが無い」ケースを作るため、PATH は実機の PATH を使わず必要なツールだけを並べる。
TOOLS_BIN="$TEST_ROOT/tools"
FAKE_BIN="$TEST_ROOT/fakes"
WORK_REPO="$TEST_ROOT/repo"
export CALL_LOG="$TEST_ROOT/calls.log"
mkdir -p "$TOOLS_BIN" "$FAKE_BIN" "$WORK_REPO"

for tool in bash git jq perl env mktemp rm cat tail sleep; do
  ln -s "$(command -v "$tool")" "$TOOLS_BIN/$tool"
done

for agent in codex claude; do
  command cat >"$FAKE_BIN/$agent" <<'EOF'
#!/usr/bin/env bash
agent="${0##*/}"
# 2 つのレビューが並列に走るので、行が混ざらないよう 1 回の write で追記する。
args="$(printf ' [%s]' "$@")"
printf '%s%s\nenv %s CLAUDECODE=%s CLAUDE_CODE_SESSION_ID=%s CODEX_THREAD_ID=%s CODEX_HOME=%s DEPTH=%s\n' \
  "$agent" "$args" "$agent" "${CLAUDECODE-unset}" "${CLAUDE_CODE_SESSION_ID-unset}" \
  "${CODEX_THREAD_ID-unset}" "${CODEX_HOME-unset}" "${SKILL_CROSS_REVIEW_DEPTH-unset}" >>"$CALL_LOG"
case "${FAKE_MODE:-ok}:$*" in
  fail:*) echo "auth required" >&2; exit 1 ;;
  hang:*) printf '%s\n' "$$" >"$CALL_LOG.pid"; sleep 30 ;;
  fail-security:*/security-review*) echo "security-review unavailable" >&2; exit 1 ;;
  *) printf '%s finding: a.txt:1\n' "$agent" ;;
esac
EOF
  chmod +x "$FAKE_BIN/$agent"
done

git_q() { git -C "$WORK_REPO" -c user.name=test -c user.email=test@example.com \
  -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@" >/dev/null 2>&1; }
git_q init -b main
printf 'base\n' >"$WORK_REPO/a.txt"
git_q add a.txt
git_q commit -m base
git_q switch -c feature
printf 'change\n' >>"$WORK_REPO/a.txt"
git_q commit -am change

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

# 呼び出し元エージェントの環境変数を立てた状態で実行する（相手側へ漏れないことを見るため）。
run() {
  local path="$1"; shift
  (cd "$WORK_REPO" && env PATH="$path" CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=parent \
    CODEX_THREAD_ID=parent CODEX_HOME=keep "$@")
}
FULL_PATH="$FAKE_BIN:$TOOLS_BIN"

expect_json() {
  local name="$1" json="$2" filter="$3"
  printf '%s' "$json" | jq -e "$filter" >/dev/null || fail "$name: $filter が成り立たない: $json"
}

# --- 引数不正は exit 2 ---
for args in "" "--from foo --base main" "--from claude" "--from claude --base main --timeout abc" \
  "--from claude --base main --timeout 0" "--from claude --base main --unknown"; do
  code=0
  # shellcheck disable=SC2086
  run "$FULL_PATH" "$CROSS_REVIEW" $args >/dev/null 2>&1 || code=$?
  [ "$code" -eq 2 ] || fail "引数不正 '$args' は exit 2 のはずが $code"
done

# --- Claude Code から: codex review を read-only で呼び、自分の環境変数を渡さない ---
: >"$CALL_LOG"
out="$(run "$FULL_PATH" "$CROSS_REVIEW" --from claude --base main)"
expect_json from-claude "$out" '.status == "ok" and .reviewer == "codex" and .base == "main"'
expect_json from-claude "$out" '[.reviews[].name] == ["codex-review"]'
expect_json from-claude "$out" '.reviews[0].status == "ok" and (.reviews[0].output | contains("codex finding"))'
rg -qF 'codex [review] [-c] [sandbox_mode="read-only"] [-c] [approval_policy="never"]' "$CALL_LOG" \
  || fail "from-claude: codex review を read-only で起動していない: $(command cat "$CALL_LOG")"
rg -qF 'main...HEAD' "$CALL_LOG" || fail "from-claude: 比較範囲 main...HEAD を指示していない"
rg -qF 'env codex CLAUDECODE=unset CLAUDE_CODE_SESSION_ID=unset CODEX_THREAD_ID=unset CODEX_HOME=keep DEPTH=1' "$CALL_LOG" \
  || fail "from-claude: セッション変数の除去・利用者設定の保持・深さガードのいずれかが崩れている: $(command cat "$CALL_LOG")"

# --- Codex から: /code-review と /security-review を書き込み禁止で呼び、Codex の環境変数を渡さない ---
: >"$CALL_LOG"
out="$(run "$FULL_PATH" "$CROSS_REVIEW" --from codex --base main)"
expect_json from-codex "$out" '.status == "ok" and .reviewer == "claude"'
expect_json from-codex "$out" '[.reviews[].name] == ["code-review", "security-review"]'
expect_json from-codex "$out" '[.reviews[].status] == ["ok", "ok"]'
rg -qF 'claude [/code-review high main...HEAD] [-p]' "$CALL_LOG" \
  || fail "from-codex: /code-review を base 範囲とレベル明示で呼んでいない: $(command cat "$CALL_LOG")"
rg -qF 'claude [/security-review] [-p]' "$CALL_LOG" || fail "from-codex: /security-review を呼んでいない"
[ "$(rg -cF '[--permission-mode] [dontAsk]' "$CALL_LOG")" -eq 2 ] || fail "from-codex: dontAsk でない起動がある"
[ "$(rg -cF '[--disallowedTools] [Edit] [Write] [NotebookEdit]' "$CALL_LOG")" -eq 2 ] \
  || fail "from-codex: 書き込み系ツールを禁止していない起動がある"
[ "$(rg -cF '[{"disableAllHooks":true}] [--strict-mcp-config]' "$CALL_LOG")" -eq 2 ] \
  || fail "from-codex: hooks か MCP を止めていない起動がある"
rg -qF '[--safe-mode]' "$CALL_LOG" && fail "from-codex: --safe-mode は /code-review を無効化するので付けない"
rg -qF -e '[Bash(rg *)]' -e '[Bash(fd *)]' "$CALL_LOG" && fail "from-codex: rg --pre / fd -x で任意コマンドを実行できる許可が残っている"
[ "$(rg -cF "[Bash(git * --output*)] [Bash(git grep *-O*)] [Bash(git grep *--open-files-in-pager*)] [--allowedTools]" "$CALL_LOG")" -eq 2 ] \
  || fail "from-codex: git の書き出し・外部起動オプションを拒否していない起動がある"
[ "$(rg -cF 'env claude CLAUDECODE=unset CLAUDE_CODE_SESSION_ID=unset CODEX_THREAD_ID=unset CODEX_HOME=keep DEPTH=1' "$CALL_LOG")" -eq 2 ] \
  || fail "from-codex: セッション変数の除去・利用者設定の保持・深さガードのいずれかが崩れている: $(command cat "$CALL_LOG")"

# --- 入れ子（セカンドオピニオンの中からの呼び出し）は相手を呼ばずに skipped ---
: >"$CALL_LOG"
out="$(run "$FULL_PATH" env SKILL_CROSS_REVIEW_DEPTH=1 "$CROSS_REVIEW" --from codex --base main)"
expect_json nested "$out" '.status == "skipped"'
[ ! -s "$CALL_LOG" ] || fail "nested: 入れ子なのに相手を呼んでいる"

# --- 相手のコマンドが無い・相手が失敗・タイムアウトは failed（exit 0 のまま） ---
out="$(run "$TOOLS_BIN" "$CROSS_REVIEW" --from claude --base main)"
expect_json missing "$out" '.status == "failed" and (.reason | contains("codex コマンドが見つかりません"))'

out="$(run "$FULL_PATH" env FAKE_MODE=fail "$CROSS_REVIEW" --from claude --base main)"
expect_json reviewer-fails "$out" '.status == "failed" and .reviews[0].status == "failed"'
expect_json reviewer-fails "$out" '.reviews[0].output | contains("auth required")'

rm -f "$CALL_LOG.pid"
out="$(run "$FULL_PATH" env FAKE_MODE=hang "$CROSS_REVIEW" --from claude --base main --timeout 1)"
expect_json timeout "$out" '.status == "failed" and (.reviews[0].output | contains("タイムアウト"))'
kill -0 "$(command cat "$CALL_LOG.pid")" 2>/dev/null && fail "timeout: 時間切れ後も相手のプロセスが残っている"

# --- 外側から止められたら相手のプロセスも止まる（残ると時間制限なしで利用枠を使い続ける） ---
# 外側の kill を再現するため、スクリプトを独立したプロセスグループで起動してグループごと止める。
rm -f "$CALL_LOG.pid"
perl -e 'chdir shift; setpgrp(0, 0); exec @ARGV' "$WORK_REPO" env PATH="$FULL_PATH" FAKE_MODE=hang \
  "$CROSS_REVIEW" --from claude --base main --timeout 600 >/dev/null 2>&1 &
outer=$!
for _ in $(seq 50); do [ -s "$CALL_LOG.pid" ] && break; sleep 0.1; done
if [ -s "$CALL_LOG.pid" ]; then
  kill -TERM -- "-$outer"
  wait "$outer" 2>/dev/null || true
  sleep 3
  kill -0 "$(command cat "$CALL_LOG.pid")" 2>/dev/null && fail "external-kill: 外側の停止後も相手のプロセスが残っている"
else
  fail "external-kill: 相手のプロセスが起動しなかった"
  kill -KILL -- "-$outer" 2>/dev/null || true
fi

# --- 片方だけ失敗したら ok のまま、失敗した方だけ failed ---
out="$(run "$FULL_PATH" env FAKE_MODE=fail-security "$CROSS_REVIEW" --from codex --base main)"
expect_json partial "$out" '.status == "ok" and ([.reviews[].status] == ["ok", "failed"])'

# --- 差分なし・base 不在 ---
out="$(run "$FULL_PATH" "$CROSS_REVIEW" --from claude --base HEAD)"
expect_json no-diff "$out" '.status == "skipped"'
out="$(run "$FULL_PATH" "$CROSS_REVIEW" --from claude --base no-such-branch)"
expect_json unknown-base "$out" '.status == "failed" and (.reason | contains("no-such-branch"))'

if [ "$failures" -gt 0 ]; then
  echo "$failures 件失敗" >&2
  exit 1
fi
echo "ok: skill-cross-review"
