#!/usr/bin/env bash
# Claude Code main statusLine.
# 表示: <Model> [1M] · think:<effort> · ctx <pct>% · $<cost>
# ctx% のみ閾値で色分け (〜50 緑 / 〜80 黄 / 80+ 赤)。他は単色。
set -euo pipefail

input=$(cat)

# 1 回の jaq 呼び出しで必要な値を 1 行ずつ抽出（起動コスト最小化）。
# 改行区切り + mapfile で空フィールド（effort 未設定等）を保持する。
mapfile -t vals < <(printf '%s' "$input" | jaq -r '
  (.model.display_name // "Claude"),
  (.model.id // ""),
  (.context_window.context_window_size // 0),
  (.context_window.used_percentage // 0),
  (.effort.level // ""),
  (.cost.total_cost_usd // 0)
')
model_name=${vals[0]:-Claude}
model_id=${vals[1]:-}
ctx_size=${vals[2]:-0}
used_pct=${vals[3]:-0}
effort=${vals[4]:-}
cost=${vals[5]:-0}

# --- モデル: 表示名 + コンテキスト種別 (1M) ---
# 判定: ctx 窓が 1,000,000 か、id に 1m を含むか。
model_seg="$model_name"
shopt -s nocasematch
if [[ "$ctx_size" == "1000000" || "$model_id" == *"1m"* ]]; then
  model_seg="$model_name 1M"
fi
shopt -u nocasematch

# --- 思考レベル ---
think_seg=""
if [[ -n "$effort" ]]; then
  think_seg=" · think:${effort}"
fi

# --- コンテキスト使用率（色分け） ---
pct_int=${used_pct%.*}
[[ -z "$pct_int" || ! "$pct_int" =~ ^[0-9]+$ ]] && pct_int=0
if   (( pct_int < 50 )); then color=$'\033[32m'   # green
elif (( pct_int < 80 )); then color=$'\033[33m'   # yellow
else                          color=$'\033[31m'   # red
fi
reset=$'\033[0m'
ctx_seg=" · ${color}ctx ${pct_int}%${reset}"

# --- コスト ---
cost_seg=$(printf ' · $%.2f' "$cost")

printf '%s%s%s%s' "$model_seg" "$think_seg" "$ctx_seg" "$cost_seg"
