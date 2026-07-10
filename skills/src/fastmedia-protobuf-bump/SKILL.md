---
name: fastmedia-protobuf-bump
description: fastmedia の consumer リポジトリで protobuf 依存（Go は protobuf-go / JS は protobuf-js）のバージョン・ハッシュを更新するとき。多くは PR で master をマージ＋コンフリクト解消したあと、指定の向き先（ブランチ名 / コミットハッシュ / 別ブランチと同じ向き先 / 最新）に protobuf を追従させる。「protobuf-go を更新して」「protobuf-js のハッシュを XXX に更新して」「go get -u protobuf-go して」「pfdev-review65 の向き先に合わせて」等で発動。commit/push・コンフリクト解消・PR 作成は既存スキルへ委譲する。
---

## 概要

fastmedia の consumer リポジトリで、社内 protobuf 生成物への依存を更新する。2 系統ある。

| 系統 | 対象 consumer（例） | 依存の在り処 | 更新方法 |
|------|---------------------|--------------|----------|
| Go   | atami / kurobe / yappli-mcp | `go.mod` の `github.com/fastmedia/protobuf-go`（pseudo-version） | `go get -u ...@<ref>` |
| JS   | cms | `package.json` の `"protobuf-js": "git+...#<hash>"` | ハッシュ書き換え + `pnpm install` |

「PR で master をマージ → コンフリクト解消 → protobuf を指定の向き先に更新 → 検証 → commit/push」が典型フロー。このスキルは **protobuf 更新の中核**だけを担い、周辺は既存スキルへ委譲する。

## Step 0: 向き先（ref / hash）を確定する

更新の指定方法は 4 通り。ユーザー指示から必ずどれかに確定してから着手する。曖昧なら質問する。

- **明示ハッシュ**: 「protobuf-js のハッシュを `f97bc99...` に」→ その値を使う
- **ブランチ名**: 「`@deploy/pfdev-review65`」「`@feat/CX-1213`」→ そのブランチ
- **別ブランチと同じ向き先**: 「pfdev-review65 のままで」「先程と同じ向き先で」→ 参照先の現在の向き先を調べて合わせる（下記「向き先の確認」）
- **最新 / 既定**: 「go get -u protobuf-go して」だけ → ブランチ未指定（既定ブランチ / latest）

### 向き先の確認（Go）

現在の向き先: `go.mod` の `github.com/fastmedia/protobuf-go v0.0.0-<timestamp>-<commit>` の commit 部分。
別ブランチに合わせる場合は、そのブランチの `go.mod` の同行を読み、同じ commit を指す ref を使う。

### 向き先の確認（JS）

現在の向き先: `package.json` の `"protobuf-js": "git+https://github.com/fastmedia/protobuf-js.git#<hash>"` の `#` 以降。

## Step 1（任意・指示があれば先に）: master マージとコンフリクト解消

「master をマージしつつ」「Conflict を解消して」が伴う場合は、protobuf 更新より**先に**マージ・コンフリクト解消を済ませる。この作業自体はこのスキルの責務外なので、通常のコンフリクト解消手順で対応し、解消後に Step 2 へ進む。

## Step 2: Go 側の更新（protobuf-go）

対象リポジトリに応じて選ぶ。

1. **atami**（`make update-pb` がある）:
   - ブランチ指定あり: `make update-pb BRANCH=<ref>`
   - 既定ブランチで良い: `make update-pb`
2. **汎用（Makefile ターゲットが無い consumer）**:
   - `go get -u github.com/fastmedia/protobuf-go@<ref>`（`<ref>` はブランチ名 / コミット / `latest`）
   - 続けて `go mod tidy`
   - `go.mod` と `go.sum` が更新される

> 各リポジトリの Makefile を先に確認し、`update-pb` 相当のターゲットがあればそれを優先する（車輪の再開発をしない）。

## Step 3: JS 側の更新（protobuf-js / cms 等）

1. `package.json` の該当行のハッシュを差し替える:
   `"protobuf-js": "git+https://github.com/fastmedia/protobuf-js.git#<新hash>"`
2. ロックファイルを同期する: **`pnpm install`**（cms は pnpm。`npm install` は使わない）
   - `pnpm-lock.yaml` の specifier / version / resolution の 3 箇所が新ハッシュに更新されることを確認する
   - `--frozen-lockfile` は付けない（ロックを更新する目的のため）

> package.json だけ書き換えてロックファイルを更新し忘れると CI で落ちる。必ず `pnpm install` まで実施する。

## Step 4: 検証

- Go: `go build ./...` または該当リポジトリの標準テスト/lint（`dotfiles-lint-and-test` に委譲してよい）
- JS: 型生成・ビルドが通るか（`pnpm install` 後、リポジトリ標準の型チェック/ビルド）
- 更新差分が `go.mod`/`go.sum` または `package.json`/`pnpm-lock.yaml` に閉じているか（意図しない変更が混ざっていないか）を確認する

## Step 5: commit / push / PR

- commit & push は **`dotfiles-commit-push`** に委譲（コミットメッセージ規約もそちらで担保）
- PR 新規作成が必要なら **`dotfiles-pr-create`** に委譲

## 注意

- ref を勝手に推測しない。「別ブランチと同じ向き先」指示のときは必ず参照元の実 commit / hash を読んでから合わせる。
- 複数ブランチ・複数リポジトリへ横断で反映する依頼が多い。対象（リポジトリ × ブランチ）を最初に列挙し、取りこぼしが無いか確認してから着手する。
- protobuf-go / protobuf-js の**どちらを対象外にするか**の指示（「protobuf-js のハッシュは対象外」等）を見落とさない。
