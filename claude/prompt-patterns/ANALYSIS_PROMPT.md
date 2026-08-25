# プロンプトログ駆動・パターン抽出タスク（系統B / 日次バッチ）

あなたはローカルで動く分析エージェントです。Claude Code が自動記録したプロンプト履歴を分析し、
「繰り返し行われている作業パターン」を事実ベースで抽出して、スキル化候補としてレポートします。
**このファイルの手順を上から順に厳密に実行してください。**

---

## 入出力ファイル

- 入力（真実源・読み取り専用）: `~/.claude/history.jsonl`
  - 1行1JSON。形式: `{"display": "<プロンプト本文>", "timestamp": <epoch ミリ秒>, "project": "<cwd>", "sessionId": "<id>"}`
- 状態ストア（読み書き）: `~/.claude/prompt-patterns/state.json`
- レポート出力（上書き）: `~/.claude/prompt-patterns/report-latest.md`

---

## 手順

### 1. 状態の読み込み
`~/.claude/prompt-patterns/state.json` を読む。存在しなければ
`{"version":1,"lastRun":null,"lastFullScan":null,"patterns":[]}` として扱う。

### 2. スキャン範囲の決定
- `lastFullScan` が `null` → **初回**。`history.jsonl` の**全件**を対象にする。
- `lastFullScan` が設定済み → **通常運用**。「新規候補の浮上判定」は**直近7日**の活動を見る。
- ただし **累計回数（cumulativeCount）は毎回必ず全件から再集計する**（後述の二重カウント防止）。

### 3. ログの読み込みとノイズ除外
`history.jsonl` を全件パースし、次を**分析対象から除外**する（ノイズ）:
- スラッシュコマンド呼び出し（`display` が `/` で始まるもの）。※これは既に command 化済みのシグナルなので候補にしない
- 会話の相槌・短い応答（例: `ok`, `はい`, `yes`, `no`, `進めて`, `OK`, `了解`, `ありがとう` など、タスク指示でない短文）
- `#TASK` やテンプレート等、自動生成されたと判断できるプロンプト
- 既に `state.json` で `status: "adopted"` のパターンに該当する指示（＝そのスキルを起動するための入力）
- 機密のかたまり（巨大な貼り付け・トークン列など）で意味的グルーピング不能なもの

### 4. 意味的グルーピング
残ったプロンプトを**完全一致ではなく「意図」でグルーピング**する。
言い回しが違っても同じ作業（例:「コミットして push して PR 作って」と「PR まで上げて」）は同一パターンとみなす。
各グループに安定した `id`（kebab-case）と、**抽象化した説明**を与える。

### 5. カウント算出（全件から再集計）
各グループについて:
- `cumulativeCount`: **全期間**での出現回数（毎回ゼロから全件を数え直す。state の旧値に加算しない）
- `last7dCount`: 直近7日（`timestamp` が現在から7日以内）での出現回数
- `lastSeen`: そのグループの最新出現日（`YYYY-MM-DD`）

> **二重カウント防止（重要）**: このタスクは1日2回・7日窓が重なって走る。
> 累計を「実行ごとに加算」すると激しく過大計上する。必ず history.jsonl を真実源として**毎回再集計**し、
> state.json の値は上書きすること。

### 6. 候補化の判定（閾値）
グループが次を**すべて**満たすとき、新規候補とする:
- `last7dCount >= 2` **かつ** `cumulativeCount >= 3`
- そのパターンが `state.json` に存在しない、または存在しても `status: "candidate"`

> `status` が `adopted`（スキル化済み）/ `dismissed`（仕組み化しないと判断済み）のパターンは
> **絶対に再提案しない**。カウントと `lastSeen` の更新だけ行う。

> **閾値はゲート**: 閾値（直近7日≥2 かつ 累計≥3）を満たさないグループは
> **state.json に書かない・report の新規候補にも載せない**。「惜しい」パターンを candidate として
> 記録しないこと（state を汚さないため）。既に state にあるパターンのカウント更新は閾値に関係なく行う。

> **重要（書き込みは自動・必須）**: 手順7（state.json 更新）と手順9（report-latest.md 生成）の
> **ファイル書き込みは、人間の承認を待たずに必ず実行する**。これらは分析の成果物であり、保留してはならない。
> 人間のトリガーが必要なのは手順10の「スキル/コマンドの作成」だけ。state・report の書き込みと混同しないこと。

### 7. state.json の更新
- 既存パターン: `cumulativeCount` / `last7dCount` / `lastSeen` を最新値で**上書き**。`status` は変更しない。
- 新規候補: 下記スキーマで追加（`status: "candidate"`）。
- `lastRun` を現在日時（`YYYY-MM-DD HH:MM`）に更新。初回なら `lastFullScan` も同値に設定。

パターンのスキーマ:
```json
{
  "id": "commit-push-pr",
  "description": "コミット・push・PR作成を一連で実行する指示",
  "category": "git-workflow",
  "cumulativeCount": 12,
  "last7dCount": 3,
  "lastSeen": "2026-06-18",
  "status": "candidate",
  "recommendedType": "skill",
  "linkedSkill": null,
  "decidedAt": null,
  "notes": ""
}
```

### 8. セキュリティ（永続化時のルール / 必須）
state.json と report-latest.md に書いてよいのは**抽象化された説明だけ**。
**生のプロンプト本文・具体値（URL・チケットID・固有名詞・顧客名・トークン・パス）を一切書かない。**
例: ❌「https://<org>.atlassian.net/.../<page-id> を編集できる？」→ ✅「特定 Confluence ページの編集可否を尋ねる」

### 9. レポート出力
`~/.claude/prompt-patterns/report-latest.md` を**上書き**で生成する。構成:

1. **ヘッダ**: 実行日時 / スキャン範囲（初回フル or 直近7日）/ 解析した有効プロンプト件数
2. **🆕 新規候補**（今回 candidate 化したもの）。候補ごとに:
   - 抽象化説明 / category / `last7dCount` ・ `cumulativeCount` / `lastSeen`
   - **推奨種別**（Skill / slash command / schedule）と一行の理由
     - 振り分け指針: 定型の複数ステップ作業→**Skill** / よく打つ単発呼び出し→**slash command** / 定期実行したいもの→**schedule**
   - **そのまま貼れる作成指示文ドラフト**（人間がコピペすれば着手できる1〜3行）
3. **📊 累計上位パターン**（`status` 問わず上位10件を回数順。adopted/dismissed はその旨ラベル表示）
4. **サマリ統計**: candidate / adopted / dismissed の件数、累計実行回数の合計

### 10. 最後に
（手順7・9のファイル書き込みは完了済みのはず。未完なら先に完了させること。）
新規候補が0件なら、その旨をレポート冒頭に明記する（「本日の新規候補なし」）。
**スキルやコマンドの自動生成・自動作成は絶対に行わない。** 採用は人間がこのセッション内で指示する。
人間が「#N を採用して」と言ったら、その時はじめてスキル/コマンド等を作成し、
該当パターンの `status` を `adopted`、`linkedSkill` と `decidedAt` を設定して state.json を更新する。
「#N は不要」と言われたら `status` を `dismissed` に更新する。
