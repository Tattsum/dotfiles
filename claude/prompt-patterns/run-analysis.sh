#!/bin/zsh
# プロンプトログ駆動・パターン抽出 日次バッチ（系統B）
# launchd から 11:00 / 19:00 に起動される。ヘッドレス claude で ANALYSIS_PROMPT.md を実行する。

set -u

# launchd は最小 PATH で起動するため、claude(homebrew) を明示的に通す
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

CLAUDE_DIR="$HOME/.claude"
WORK_DIR="$CLAUDE_DIR/prompt-patterns"
LOG="$WORK_DIR/run.log"

# 実行時刻を記録（launchd の StandardOut とは別に、開始/終了が追える簡易ログ）
echo "===== run start: $(date '+%Y-%m-%d %H:%M:%S') =====" >> "$LOG"

# cwd を ~/.claude にすることで history.jsonl と prompt-patterns/ の両方を許可範囲に含める。
# --allowedTools に列挙したツールのみ無人で許可（未列挙ツールは print モードで自動拒否され、ハングしない）。
# --model sonnet: 1日2回・全件再集計のコストを抑えるため。分類精度を上げたい場合は opus に変更可。
cd "$CLAUDE_DIR" || { echo "cd failed" >> "$LOG"; exit 1; }

# プロンプトは stdin で渡す。--allowedTools が可変長引数のため、末尾に位置引数で
# プロンプトを置くと飲み込まれてしまう（→ 位置引数では渡さない）。
PROMPT="$WORK_DIR/ANALYSIS_PROMPT.md を読み、そこに書かれた手順を上から厳密に実行してください。最後に実行サマリ（解析件数・新規候補件数）を1行で報告してください。"

# acceptEdits: 無人実行なので state.json / report-latest.md への書き込みを承認待ちにしない。
# Bash は acceptEdits 対象外のため allowedTools で別途許可（未列挙ツールは print で自動拒否）。
print -r -- "$PROMPT" | claude --print \
  --model sonnet \
  --permission-mode acceptEdits \
  --allowedTools Read Write Edit Bash \
  >> "$LOG" 2>&1

echo "===== run end:   $(date '+%Y-%m-%d %H:%M:%S') (exit=$?) =====" >> "$LOG"
