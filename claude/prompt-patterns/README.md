# プロンプトログ駆動・パターン抽出システム（launchd + ヘッドレス claude 版）

Claude Code が自動記録する `~/.claude/history.jsonl` を launchd が毎日2回ヘッドレス `claude` で分析し、
繰り返し作業パターンを事実ベースで抽出 → スキル化候補としてレポートする仕組み。
（参考: LayerX「プロンプトログ駆動」https://tech.layerx.co.jp/entry/prompt-log-driven-ai-workflow ／系統B のみ実装）

> Cowork は採用検討時に却下：サンドボックスが `~/.claude/` に到達できず history.jsonl を読めないため。
> ヘッドレス `claude -p` はサンドボックス外で全ファイルに到達できるため、こちらを採用。

## 2つの入口（ロジックは単一源）

分析ロジックは `ANALYSIS_PROMPT.md` 1ファイルに集約し、以下2経路が共有する:

1. **自動（launchd 日次バッチ）**: `run-analysis.sh` が `ANALYSIS_PROMPT.md` を**直接**ヘッドレス実行（毎日 11:00 / 19:00）
2. **手動（Skill）**: 任意セッションで「プロンプトログを分析して」等 → `prompt-pattern-scan` スキルが
   **サブエージェント1体に委譲**して `ANALYSIS_PROMPT.md` を実行（重い履歴読み込みをメイン会話から隔離）

> なぜ launchd 経路は Skill を経由しないのか: 無人バッチには「メイン会話のコンテキストを守る」目的が無く、
> サブエージェント隔離は不要。直接実行の方が単純で堅牢（YAGNI）。ロジックは両経路で同一なので二重メンテにならない。

## 構成ファイル

| ファイル | 役割 | 場所 |
|---------|------|------|
| `ANALYSIS_PROMPT.md` | 分析ロジック本体（単一源・両経路が共有） | `~/.claude/prompt-patterns/` |
| `state.json` | パターン状態ストア（candidate / adopted / dismissed） | `~/.claude/prompt-patterns/` |
| `report-latest.md` | 最新の分析レポート（毎回上書き。人間が読む） | `~/.claude/prompt-patterns/` |
| `run-analysis.sh` | launchd から起動される起動スクリプト（直接実行） | `~/.claude/prompt-patterns/` |
| `com.tatsuma.prompt-pattern-analysis.plist` | スケジュール定義（毎日 11:00 / 19:00） | `~/Library/LaunchAgents/` |
| `SKILL.md` | 手動入口（サブエージェント委譲＋採用フロー） | `~/.claude/skills/prompt-pattern-scan/` |
| `run.log` / `launchd.{out,err}.log` | 実行ログ | `~/.claude/prompt-patterns/` |

ロジック側（`ANALYSIS_PROMPT.md` / `run-analysis.sh` / `SKILL.md` / plist）は dotfiles で管理し、
`~/` 配下へは symlink または実体コピーで配置する。

**生成物（`state.json` / `report-latest.md` / `classification-rules.json` / 各ログ）は non-git。**
`history.jsonl` の派生物で固有名詞を含み得るうえ、dotfiles リポジトリは public なため、
`~/.claude/prompt-patterns/`（`700`・本人のみ）に置いたままにする。

> ⚠️ 生のプロンプト本文・具体値は永続化しない（抽象化説明のみ）。詳細は `ANALYSIS_PROMPT.md` 手順8。

## 仕組み

1. launchd が毎日 11:00 / 19:00 に `run-analysis.sh` を起動（Mac 起動中。スリープ中にミスした分は復帰後に launchd が遅延実行）
2. スクリプトが `claude --print --model sonnet` で `ANALYSIS_PROMPT.md` を実行
3. ヘッドレス claude が `history.jsonl` を分析 → `state.json` 更新 → `report-latest.md` 生成
4. 人間が `report-latest.md` を読み、採用するものを通常の Claude Code セッションで「report-latest.md の #N を採用して」と指示
   → その場でスキル/コマンド/schedule を作成し、state を `adopted` に更新（不要なら `dismissed`）

## 運用コマンド

```bash
# 手動で即実行（ドライラン）
~/.claude/prompt-patterns/run-analysis.sh

# launchd 経由で即実行（スケジュールと同じ経路で確認）
launchctl kickstart -k gui/$(id -u)/com.tatsuma.prompt-pattern-analysis

# 状態確認
launchctl print gui/$(id -u)/com.tatsuma.prompt-pattern-analysis | grep -iE "state|last exit"

# ログ確認
tail -f ~/.claude/prompt-patterns/run.log

# 停止 / 再登録
launchctl bootout gui/$(id -u)/com.tatsuma.prompt-pattern-analysis
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.tatsuma.prompt-pattern-analysis.plist
```

## 閾値・ルール（決定事項）

- 候補化: **直近7日で2回以上 かつ 累計3回以上**
- 累計は毎回 history.jsonl から再集計（1日2回・窓が重なるため加算しない＝二重カウント防止）
- 初回のみ全期間スキャン、以降は直近7日の活動で浮上判定
- `adopted` / `dismissed` は再提案しない
- スキルの自動生成はしない（採用は人間がセッション内で指示）

## ロジックの変更

分析内容を変えたいときは `ANALYSIS_PROMPT.md` を編集するだけ。
スクリプトや plist は「起動するだけ」の責務なので原則触らない。
モデルやコストを変えたいときは `run-analysis.sh` の `--model` を変更（既定 sonnet → opus 等）。
