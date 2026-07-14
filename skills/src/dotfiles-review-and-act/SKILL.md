---
name: dotfiles-review-and-act
description: PR をレビューし、その結果を PR 所有者で次アクションに振り分けるオーケストレーター。自分の PR なら指摘に沿って改修（Must は自動修正 / Should・Nice は提案）し commit/push は dotfiles-commit-push へ委譲、他人の PR なら PJ ルール（shields.io バッジ・全件インライン・--paginate 重複照合）でコメント投稿する。レビュー自体は言語別 dotfiles-*-review へ委譲する。「この PR をレビューして対応して」「PR をレビューしてコメントして」「レビューして直して」「PR レビューして」等で発動。所有者があいまいなら止めて確認する。
allowed-tools: [Bash, Read, Grep, Glob, Agent, Edit, Write, Skill]
---

# /dotfiles-review-and-act

PR をレビューし、**所有者で次アクションを振り分ける**エントリポイント。レビュー依頼のあとに毎回「コメントして／直して」と口頭指示する繰り返しを、1回の発火で完結させる。

- **自分の PR** → コメント投稿はしない。指摘に沿って**改修**する（Must は自動修正、Should/Nice は提案して確認）。commit/push は `dotfiles-commit-push` へ委譲。
- **他人の PR** → コード編集はしない。指摘を **PJ ルール**（下記「コメント投稿手順」）で**インライン投稿**する。

レビューそのものは再実装せず、言語別オーケストレーター（`dotfiles-go-review` / `dotfiles-php-laravel-review` / `dotfiles-ts-review`）へ委譲する。このスキルの責務は「所有者判定 → レビュー委譲 → 振り分け実行」に限る。

## Input

- 対象 PR: 引数に URL / 番号があればそれを使う。無ければ現在ブランチから解決する。
- `--base=<branch>`: optional。委譲先レビュースキルへそのまま渡す。

## Workflow

### 1. 対象 PR の解決と所有者判定

```bash
# 認証中の自分のアカウント
gh api user -q .login
# 対象 PR（引数指定が無ければ現在ブランチから解決）。base リポジトリ側で投稿するため base 情報も取る
gh pr view [<PR番号 or URL>] --json number,author,url,headRefName,baseRepository,isCrossRepository
```

- `author.login == 自分の login` → **自分 PR（改修モード）**
- 不一致 → **他人 PR（投稿モード）**

### 2. あいまい時は止めて確認（fail-safe・必須）

次のいずれかに当てはまり所有者を確信できないときは、**投稿もコード編集も行わず**、ユーザーに確認する。誤って他人 PR に push する／自分 PR にレビュー爆撃する事故（外向き・不可逆）を防ぐため、推測で進めない。

- 現在ブランチに対応する PR が見つからない
- 該当 PR が複数ある
- `gh` の API が失敗する / author を取得できない
- 引数の PR と現在ブランチが食い違う

確認の型: 「対象 PR が特定できませんでした。どの PR を対象にしますか？」「この PR は自分/他人のどちらとして扱いますか（改修 or 投稿）?」

### 3. レビュー実行（言語別 review-* へ委譲）

差分の変更ファイル拡張子から言語を判定し、対応するオーケストレーターを起動する。複数言語が混在する場合は該当する複数を起動する。

```bash
git diff --name-only <base>...HEAD
```

- `*.go` / `*.sql` / `*.proto` → `dotfiles-go-review`
- `*.php` → `dotfiles-php-laravel-review`
- `*.ts` / `*.tsx` / `*.vue` / `*.js` / `*.jsx` → `dotfiles-ts-review`

いずれの言語にも当たらない場合は、CLAUDE.md「基本観点」（レイヤー境界 / エラー処理 / 命名・可読性 / テスト / セキュリティ / パフォーマンス）でインラインレビューする。委譲先の出力（Must / Should / Nice の重要度別指摘リスト）を `<FINDINGS>` として保持する。

### 4. 所有者で振り分け

#### 4-A. 自分 PR（改修モード）

1. **Must（🔴 / must）**: 言語仕様・規約・明確なバグに基づく指摘を**コード編集で自動修正**する。修正の How はコードで表現し、なぞるコメントは足さない（四分割原則）。
2. **Should / Nice（🟡🟢 / imo・imho・nits 等）**: 判断が割れるため**自動修正しない**。修正案を提示し、採否をユーザーに確認する。
3. **コメント投稿はしない**。自分 PR に自作のレビューコメントを貼らない。
4. 改修後、**何を直したか**（対応した Must の一覧・見送った Should/Nice）を会話に要約提示する。
5. commit / push が必要になったら **`dotfiles-commit-push` に委譲**する（保護ブランチ回避・秘密情報チェック・コミット規約はそちらの責務）。このスキルは commit も push もしない。

#### 4-B. 他人 PR（投稿モード）

1. コードは編集しない。指摘を下記「コメント投稿手順」に厳密に従ってインライン投稿する。
2. 投稿後、要約（投稿件数・重要度別内訳）だけを会話に返す。

## コメント投稿手順（PJ ルール・投稿モードの正本）

> GitHub レビューコメントの投稿規則の**正本はこのセクション**。CLAUDE.md 本体はここへの pointer のみを持つ。

### バッジ（必須）

コメント先頭に**必ず shields.io バッジ（画像）**を付ける。太字テキスト（`**must**` など）は使わない。バッジ直後に半角スペースを空けて本文を続ける。

| ラベル | 意味 | バッジ Markdown |
|--------|------|-----------------|
| must | 必ず修正して欲しい | `![must](https://img.shields.io/badge/review-must-red.svg)` |
| want | 修正して欲しい | `![want](https://img.shields.io/badge/review-want-orange.svg)` |
| imo | 自分の意見では修正した方が良い（他の人もそうかも） | `![imo](https://img.shields.io/badge/review-imo-orange.svg)` |
| imho | 自分の意見では修正した方が良い（他の人は違うかも） | `![imho](https://img.shields.io/badge/review-imho-yellow.svg)` |
| nits | 些細だが直した方が良い | `![nits](https://img.shields.io/badge/review-nits-green.svg)` |
| info | アドバイス・共有（この PR での修正は求めない） | `![info](https://img.shields.io/badge/review-info-lightgrey.svg)` |
| ask | 単純な質問 | `![ask](https://img.shields.io/badge/review-ask-blue.svg)` |
| suggestion | 提案 | `![suggestion](https://img.shields.io/badge/review-suggestion-blue.svg)` |

例: `![must](https://img.shields.io/badge/review-must-red.svg) Controller に認可チェックが無い → policy を追加`

### 投稿前の準備（必須）

- **必ず既存コメントを `--paginate` で全件取得**してから投稿する（既定30件では自分の過去投稿を見落とし、再投稿で重複を生む）。件数が少なく感じても全件確認まで再投稿しない。
- **議論済み・指摘済み・「対応不要」と回答済みの内容は再提起しない**。同観点の別行はまとめて1件にする。
- 自己チェック: YAGNI（今必要な指摘のみ）／ 重複なし ／ 根拠あり（言語仕様・スタイルガイド・規約・具体的バグリスクのいずれか）。

### 投稿と照合（必須）

- **すべての指摘・提案・質問はコード行に紐づくインラインコメント**で行う（general comment に箇条書きで並べない）。例外は PR 要約など行に紐づけられない内容のみ。
- `POST /pulls/{pr}/reviews`（一括投稿）は無効行を無言でドロップし得る。送信後は `--paginate` で登録件数・行マッピングを照合し、欠落時は個別 `POST /pulls/{pr}/comments`（1件ずつ）で再投稿する。
- 最終確認は `path:line` + ラベル + ユニーク id で重複が無いか照合。重複は後発（created_at が新しい方）を `DELETE /pulls/comments/{id}` で削除する。

```bash
# ✅ 必須: 全件取得しユニーク id で数える
gh api repos/{owner}/{repo}/pulls/{pr}/comments --paginate --jq '.[].id' | sort -u | wc -l
```

## 委譲境界

- **レビュー**: `dotfiles-go-review` / `dotfiles-php-laravel-review` / `dotfiles-ts-review`（指摘のみ・投稿しない設計）。
- **commit / push**: `dotfiles-commit-push`（このスキルは行わない）。
- **PR 作成**: `dotfiles-pr-create`。
- **コンフリクト解消**: `dotfiles-conflict-resolve`。
