#!/usr/bin/env bash

# evals/review/run.sh の配線（fixture・claude への引数と環境変数・採点・集計）を、偽の claude で固定する。
# 本物を呼ぶと利用枠を消費し、レビュー本文も実行ごとに変わって検証の軸にならない。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
RUN="$REPO_ROOT/evals/review/run.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/review-evals-run-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

FAKE_BIN="$TEST_ROOT/fakes"
export CALL_LOG="$TEST_ROOT/calls.log"
mkdir -p "$FAKE_BIN" "$TEST_ROOT/tmp"

command cat >"$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  echo "0.0.0 (fake)"
  exit 0
fi
{
  printf 'cwd %s\n' "$PWD"
  printf 'branch %s\n' "$(git rev-parse --abbrev-ref HEAD)"
  printf 'subjects %s\n' "$(git log --format=%s | tr '\n' '|')"
  printf 'args%s\n' "$(printf ' [%s]' "$@")"
  printf 'env ADVISOR_OFF=%s MEMORY_OFF=%s HISTORY_SKIP=%s EFFORT_ENV=%s CLAUDECODE=%s SESSION=%s\n' \
    "${CLAUDE_CODE_DISABLE_ADVISOR_TOOL-unset}" "${CLAUDE_CODE_DISABLE_AUTO_MEMORY-unset}" \
    "${CLAUDE_CODE_SKIP_PROMPT_HISTORY-unset}" "${CLAUDE_CODE_EFFORT_LEVEL-unset}" "${CLAUDECODE-unset}" \
    "${CLAUDE_CODE_SESSION_ID-unset}"
  printf 'diff %s\n' "$(git diff --name-only main...HEAD | tr '\n' ' ')"
} >>"$CALL_LOG"
if grep -q requireAdmin app/admin/drafts/page.tsx; then
  review='観点別カウント: ts/security: 0件, 横断: 未実行 (合計0件) → 重複統合0件 → 反証取り下げ0件 → リスト0件\n## 🔴 Must（必ず修正）\n全観点でレビューの指摘はありません\n'
else
  review='観点別カウント: ts/security: 1件, 横断: 未実行 (合計1件) → 重複統合0件 → 反証取り下げ0件 → リスト1件\n## 🟡 Should（できれば修正）\n- [app/admin/drafts/page.tsx:6] (ts/security) 管理者の確認が layout にしか無い → page でも確かめる\n'
fi
jq -n --arg result "$(printf "$review")" '{type: "result", subtype: "success", is_error: false, result: $result, total_cost_usd: 0.25}'
EOF
chmod +x "$FAKE_BIN/claude"

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

# 親の Claude Code のセッション変数が立った状態（`!` からの起動）を再現する。
run_evals() {
  PATH="$FAKE_BIN:$PATH" TMPDIR="$TEST_ROOT/tmp" REVIEW_EVALS_OUT="$TEST_ROOT/out" \
    CLAUDE_CODE_EFFORT_LEVEL=low CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=parent-session "$RUN" "$@"
}

# 予算を指定しないと、claude を起動せずに止まる。
: >"$CALL_LOG"
set +e
run_evals --case layout-authz >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 2 ] || fail "--max-budget-usd 無しは exit 2 のはず（実際: $status）"
[ ! -s "$CALL_LOG" ] || fail "--max-budget-usd 無しで claude が起動された"

# 存在しないケースを指定すると止まる。
set +e
run_evals --max-budget-usd 1 --case no-such-case >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 2 ] || fail "存在しないケースは exit 2 のはず（実際: $status）"

# 1 ケースの defect と clean を回し、採点と集計まで通る。
: >"$CALL_LOG"
run_evals --max-budget-usd 1 --case layout-authz >"$TEST_ROOT/summary.txt" 2>"$TEST_ROOT/stderr.txt" ||
  fail "run.sh が失敗した: $(command cat "$TEST_ROOT/stderr.txt")"

[ "$(grep -c '^cwd ' "$CALL_LOG")" -eq 2 ] || fail "claude は defect と clean の 2 回呼ばれるはず"
[ "$(grep '^cwd ' "$CALL_LOG" | sort -u | wc -l | tr -d ' ')" -eq 2 ] || fail "defect と clean は別の fixture で回るはず"
grep '^cwd ' "$CALL_LOG" | grep -qv "^cwd $TEST_ROOT/tmp/review-evals/" && fail "fixture が \$TMPDIR/review-evals の外にある"
grep -E '^(cwd|branch|subjects) ' "$CALL_LOG" | grep -qiE 'defect|clean|layout-authz' &&
  fail "fixture のパス・ブランチ名・コミットメッセージから答えが読める: $(grep -E '^(cwd|branch|subjects) ' "$CALL_LOG" | tr '\n' ' ')"
[ "$(grep -c '^branch feature$' "$CALL_LOG")" -eq 2 ] || fail "head のブランチ名が feature になっていない"
[ "$(grep -c '^diff app/admin/drafts/page.tsx $' "$CALL_LOG")" -eq 2 ] || fail "fixture の差分が head の重ね書きだけになっていない"

args_line="$(grep -m1 '^args' "$CALL_LOG")"
for want in '[-p] [/dotfiles-code-review --focus=security --base=main]' '[--model] [claude-opus-5-5]' \
  '[--effort] [xhigh]' '[--settings] [{"ultracode": false}]' '[--permission-mode] [auto]' \
  '[--output-format] [json]' '[--no-session-persistence]' '[--max-budget-usd] [1]'; do
  case "$args_line" in
    *"$want"*) ;;
    *) fail "claude の引数に $want が無い: $args_line" ;;
  esac
done
[ "$(grep -c '^env ADVISOR_OFF=1 MEMORY_OFF=1 HISTORY_SKIP=1 EFFORT_ENV=unset CLAUDECODE=unset SESSION=unset$' "$CALL_LOG")" -eq 2 ] ||
  fail "advisor・自動のメモリ・履歴を切り、effort と親のセッションの環境変数を外していない: $(grep '^env' "$CALL_LOG" | head -1)"

out_dir="$(find "$TEST_ROOT/out" -mindepth 1 -maxdepth 1 -type d | head -1)"
for variant in defect clean; do
  score="$out_dir/layout-authz/$variant/run-1/score.json"
  meta="$out_dir/layout-authz/$variant/run-1/meta.json"
  [ "$(jq -r .pass "$score" 2>/dev/null)" = "true" ] || fail "$variant の採点が pass になっていない: $(command cat "$score" 2>/dev/null)"
  [ "$(jq -r '.advisor + " " + (has("enabled_plugins") | tostring)' "$meta" 2>/dev/null)" = "disabled true" ] ||
    fail "$variant の meta.json に設定が記録されていない"
done
[ "$(jq 'map(.passes) | add' "$out_dir/summary.json" 2>/dev/null)" = "2" ] || fail "summary.json の合格数が 2 になっていない"
grep -q 'total cost_usd: 0.50' "$TEST_ROOT/summary.txt" || fail "集計の費用が合っていない: $(command cat "$TEST_ROOT/summary.txt")"

if [ "$failures" -ne 0 ]; then
  echo "$failures 件失敗" >&2
  exit 1
fi
echo "ok"
