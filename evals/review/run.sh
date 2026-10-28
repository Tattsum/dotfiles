#!/usr/bin/env bash

# レビュースキルの評価ケースを claude -p で回し、score.go で採点する。
#
# claude を起動するので利用枠（API キーなら従量課金）を消費する。Claude Code の sandbox の中から起動すると sandbox が
# 入れ子になって動かないので、ターミナル（または Claude Code の `!`）から実行する。
#
# Usage:
#   evals/review/run.sh --max-budget-usd <usd> [--case <name>[/defect|/clean]] [--runs <n>]
#
# 環境変数で上書きできるもの:
#   REVIEW_EVALS_MODEL            既定 claude-opus-5-5
#   REVIEW_EVALS_EFFORT           既定 xhigh
#   REVIEW_EVALS_PERMISSION_MODE  既定 auto
#   REVIEW_EVALS_OUT              結果の置き場。既定 evals/review/results

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
CASES_DIR="$SCRIPT_DIR/cases"

usage() {
  sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

budget=""
case_filter=""
runs=1
while [ $# -gt 0 ]; do
  case "$1" in
    --max-budget-usd) budget="${2:-}"; shift 2 ;;
    --case)           case_filter="${2:-}"; shift 2 ;;
    --runs)           runs="${2:-}"; shift 2 ;;
    -h|--help)        usage ;;
    *) echo "不明な引数: $1" >&2; usage ;;
  esac
done

# 既定値を持たせない: 1 回の費用を測るまでは、回す人が毎回決める。
if [ -z "$budget" ]; then
  echo "--max-budget-usd は必須（claude の 1 回の実行ごとの上限）" >&2
  exit 2
fi
case "$runs" in
  ''|*[!0-9]*|0) echo "--runs は 1 以上の整数" >&2; exit 2 ;;
esac

for cmd in claude git jq go; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd が見つかりません" >&2; exit 2; }
done

model="${REVIEW_EVALS_MODEL:-claude-opus-5-5}"
effort="${REVIEW_EVALS_EFFORT:-xhigh}"
permission_mode="${REVIEW_EVALS_PERMISSION_MODE:-auto}"
settings='{"ultracode": false}'
out_root="${REVIEW_EVALS_OUT:-$SCRIPT_DIR/results}/$(date +%Y%m%d-%H%M%S)"
# リポジトリの中に作らない: このリポジトリのメモリ（足した観点）が読まれ、答えを教えた状態でレビューさせてしまう。
fixture_root="${TMPDIR:-/tmp}/review-evals"
claude_version="$(claude --version 2>/dev/null || echo unknown)"
dotfiles_rev="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
dotfiles_dirty="$(git -C "$REPO_ROOT" status --porcelain -- skills agents claude | wc -l | tr -d ' ')"
enabled_plugins="$(jq -c '[.enabledPlugins // {} | to_entries[] | select(.value) | .key]' "$HOME/.claude/settings.json" 2>/dev/null || echo null)"

# 親のセッション変数だけを外す（一覧は bin/skill-cross-review と同じ）: `!` から起動すると入れ子のセッションとして親に繋がりにいく。
scrub=(-u CLAUDE_CODE_EFFORT_LEVEL)
for name in $(compgen -e); do
  case "$name" in
    CLAUDECODE|CLAUDE_PID|CLAUDE_EFFORT|CLAUDE_TMPDIR|CLAUDE_PLUGIN_DATA|CLAUDE_PLUGIN_ROOT) ;;
    CLAUDE_CODE_SESSION_ID|CLAUDE_CODE_SESSION_ATTENDED|CLAUDE_CODE_CHILD_SESSION) ;;
    CLAUDE_CODE_ENTRYPOINT|CLAUDE_CODE_EXECPATH|CLAUDE_CODE_TMPDIR|CLAUDE_CODE_MESSAGING_*) ;;
    CODEX_THREAD_ID|CODEX_SESSION_ID|CODEX_SANDBOX|CODEX_SANDBOX_*|CODEX_COMPANION_*) ;;
    *) continue ;;
  esac
  scrub+=(-u "$name")
done

# パス・ブランチ名・コミットメッセージにケース名や defect / clean を出さない: レビュー担当から見え、答えになる。
build_fixture() {
  local case_dir="$1" variant="$2" dest="$3"
  rm -rf "$dest"
  mkdir -p "$dest"
  g() {
    git -C "$dest" -c user.name=developer -c user.email=developer@example.com \
      -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@" >/dev/null
  }
  g init -q -b main
  cp -R "$case_dir/base/." "$dest/"
  g add -A
  g commit -q -m "Initial import"
  g switch -q -c feature
  cp -R "$case_dir/$variant/." "$dest/"
  g add -A
  g commit -q -m "Update"
}

run_one() {
  local case_dir="$1" variant="$2" run="$3"
  local name focus fixture out
  name="$(basename "$case_dir")"
  focus="$(jq -r .focus "$case_dir/case.json")"
  fixture="$fixture_root/$(printf '%s' "$name/$variant" | git hash-object --stdin | cut -c1-8)"
  out="$out_root/$name/$variant/run-$run"
  mkdir -p "$out"
  build_fixture "$case_dir" "$variant" "$fixture"

  jq -n \
    --arg case "$name" --arg variant "$variant" --argjson run "$run" --arg focus "$focus" \
    --arg model "$model" --arg effort "$effort" --arg permission_mode "$permission_mode" \
    --argjson settings "$settings" --arg budget "$budget" --arg claude_version "$claude_version" \
    --arg dotfiles_rev "$dotfiles_rev" --argjson dotfiles_dirty_files "$dotfiles_dirty" \
    --argjson enabled_plugins "$enabled_plugins" --arg fixture "$fixture" \
    --arg subagent_model "${CLAUDE_CODE_SUBAGENT_MODEL:-from user settings}" \
    '{case: $case, variant: $variant, run: $run, focus: $focus, fixture: $fixture, model: $model,
      effort: $effort, permission_mode: $permission_mode, settings: $settings, advisor: "disabled",
      auto_memory: "disabled", prompt_history: "skipped",
      max_budget_usd: $budget, claude_version: $claude_version, dotfiles_rev: $dotfiles_rev,
      dotfiles_dirty_files: $dotfiles_dirty_files, enabled_plugins: $enabled_plugins,
      subagent_model: $subagent_model}' >"$out/meta.json"

  echo "== $name/$variant run $run (focus=$focus)" >&2
  set +e
  (
    cd "$fixture" &&
      env "${scrub[@]}" CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1 CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 \
        CLAUDE_CODE_SKIP_PROMPT_HISTORY=1 \
        claude -p "/dotfiles-code-review --focus=$focus --base=main" \
        --model "$model" --effort "$effort" --settings "$settings" \
        --permission-mode "$permission_mode" --output-format json \
        --no-session-persistence --max-budget-usd "$budget"
  ) >"$out/claude.json" 2>"$out/claude.stderr"
  local status=$?
  set -e
  echo "$status" >"$out/claude.exit"

  (cd "$SCRIPT_DIR" && go run score.go -case "$case_dir/case.json" -variant "$variant" -output "$out/claude.json") >"$out/score.json"
  jq -r '"   pass=\(.pass) cost_usd=\(.cost_usd) \((.reasons // []) | join(" / "))"' "$out/score.json" >&2
}

selected=0
for case_dir in "$CASES_DIR"/*/; do
  case_dir="${case_dir%/}"
  name="$(basename "$case_dir")"
  for variant in defect clean; do
    if [ -n "$case_filter" ] && [ "$case_filter" != "$name" ] && [ "$case_filter" != "$name/$variant" ]; then
      continue
    fi
    selected=$((selected + 1))
    for run in $(seq 1 "$runs"); do
      run_one "$case_dir" "$variant" "$run"
    done
  done
done

if [ "$selected" -eq 0 ]; then
  echo "該当するケースがありません: $case_filter" >&2
  exit 2
fi

(cd "$SCRIPT_DIR" && go run score.go summary "$out_root")
echo "結果: $out_root" >&2
