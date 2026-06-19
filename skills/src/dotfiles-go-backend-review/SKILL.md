---
name: dotfiles-go-backend-review
description: Go バックエンドの差分を、サブエージェントを使わず main 1コンテキストでざっと一括レビューする軽量・単発版。Clean Architecture・gRPC の複数観点を1回で確認し、コードは修正せず重要度別の指摘リストを報告する。「Go を軽くレビュー」「Go をざっと見て」等で発動。観点ごとにサブエージェントを並列起動して網羅的に見たいときは dotfiles-go-review（オーケストレーター）、個別観点だけなら review-go-* を使う。
---

## 目的

Go バックエンド（handler / usecase / entity・domain / infrastructure のレイヤー構成）の差分を、**複数観点で漏れなくレビュー**する。コードの修正は行わず、指摘リストの報告に徹する。

## 方針

- 比較元ブランチ（デフォルト `origin/master`、なければ `origin/main`）との差分をレビュー対象にする
- diff の `@@` 行番号ではなく、**実ファイルを読んだ上での行番号**で指摘する
- 観点ごとに独立して見て、最後に統合した指摘リストにまとめる
- 詳細なチェック項目は `claude/CLAUDE.md` の「バックエンド（Go + Clean Architecture + gRPC）追加レビュー観点」を正本とする

## ワークフロー

1. `git diff <base>...HEAD --stat` で対象を確認（差分がなければ「対象なし」と報告して終了）
2. 変更された Go / SQL マイグレーションファイルを特定する
3. 各ファイルを読み、正確な行番号を把握する
4. 下記の観点ごとにレビューする
5. 結果を統合し、重要度別に出力する

## レビュー観点

- **レイヤー境界・責務**: handler にビジネスロジックを混ぜない。usecase/entity が転送層の型（protobuf 等）に依存しない。ドメイン知識は所属 package に置く。腐敗防止層で外部 API 型を内部に持ち込まない。gRPC ステータスへの変換は handler 層
- **コード設計・YAGNI**: application 層は今必要なコードのみ。スキーマ/API 定義は変更コストが高いので拡張余地を許容。通り得ない防御的コードを書かない。既存処理を再利用。SRP で分離
- **不要コード**: 使われない関数/const/引数を残さない。`return err` 箇所での重複ログを避ける。フラグ確認後にデータ取得する
- **Go イディオム・型安全性**: struct は pointer（value object は値型）。nil 表現は `*T`。早期 return 後の else を避ける。エラーは `errors.Is`/`As` で判定。slice は cap を意識
- **命名・関数設計**: 関数名と実処理を一致させる。Get（error あり）/ Find（optional 返し）/ List（複数返し）の規約。ファイル名とメイン型名を揃える。repository の関数はシンプルに
- **DB 設計**: 可変長文字列は `VARCHAR(255)`、固定長は `CHAR`。status は ENUM/CHECK 検討。`ON DELETE CASCADE` を避け app 側で削除。`utf8mb4` + 適切な COLLATE。IN 句の空 slice ガード。時刻は `DATETIME`
- **パフォーマンス・堅牢性**: retry は exponential backoff。N+1 を避け一括取得。WHERE/JOIN にインデックス。URL は `url.Parse`/`QueryEscape`。タイミング依存の不整合を防御
- **テスト戦略**: repository は実 DB アクセスのテスト。API には integration test。ロジックを持つ関数に unit test。state 依存テストに `t.Parallel()` を使わない
- **テスト品質**: 偽陰性/偽陽性を排除する。テストデータにゼロ値や本番定数を使わず具体値・リテラルを使う。`assert.NotNil` だけで済ませず具体値で検証。境界値を意識

## 出力フォーマット

重要度別に、`[ファイルパス:行番号]` 付きで指摘する。

```
## 🔴 Must（必ず修正）
- [path:line] 問題 → 修正案

## 🟡 Should（できれば修正）
- [path:line] 問題 → 修正案

## 🟢 Nice to have（提案）
- [path:line] 提案
```

各観点で指摘がなければ「該当なし」と明記する。
