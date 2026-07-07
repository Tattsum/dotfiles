---
name: dotfiles-conflict-resolve
description: git のコンフリクト（merge / rebase / cherry-pick / revert / stash pop）を安全に解消するとき。操作種別を判定して ours/theirs を具体ブランチ名に翻訳し、退避線を確保してからハンク単位で解消する。機械的な一括採用はせず、意味判断が要る衝突・読み切れない衝突は人へエスカレーションする。マーカー除去確認＋テストで意味的コンフリクトを検出するまで「解決」と報告しない。「コンフリクトを解消して」「マージ衝突を直して」「rebase が衝突した」等で発動。
allowed-tools: [Bash, Read, Edit, Grep, Glob, Skill]
---

## 目的

git のコンフリクトを **データを失わず・論理を壊さず** 解消する。解消まで踏み込んで編集するが、機械的な一括採用と意味的コンフリクトの見逃しを構造的に防ぐ。

## スコープ（やること / やらないこと）

- **やる**: 状態把握 → 退避線の確保 → 方向の翻訳 → 衝突の可視化 → ハンク単位の解消 → マーカー除去確認 → `git add` まで。
- **やらない（委譲・確認）**:
  - `--continue` / `commit` / `push` は実行しない。`dotfiles-commit-push` の責務（保護ブランチ保護・秘密情報チェック・4要素コミット規約）に委譲し、必ず人の確認を取る。
  - `--abort` は退避手段として案内するだけ。進行中の解消を破棄する破壊操作なので、ユーザーの明示指示があるまで実行しない。
  - lint / format / test の実行は `dotfiles-lint-and-test` に委譲する。
- **禁止事項（ガードレール）**:
  - 片側を機械的に丸ごと採用しない（`git checkout --ours/--theirs` の一括適用でもう片方の変更を消さない）。丸ごと採用は「片側が明確に不要と根拠を持って言える」場合に限る。
  - lockfile / 生成物（`package-lock.json` / `yarn.lock` / `go.sum` / `Gemfile.lock` / snapshot / 生成コード / minified 出力等）を手でマージしない。片側を採用してから再生成する。
  - マーカーが消えただけで「解決」と報告しない（意味的コンフリクトを見逃す）。テストが通るまで解決扱いにしない。
  - 両側の意図が読み切れない衝突を推測で埋めない。衝突箇所と両側の意図を提示して人の判断を仰ぐ。

## 手順

### 1. 状態把握（操作種別と対象の特定）

`git status` の冒頭で **どの操作の途中か** を判定する。これが後段の ours/theirs の意味を決める。

- merge → `You have unmerged paths` / `.git/MERGE_HEAD`
- rebase → `interactive rebase in progress` / `.git/rebase-merge` or `.git/rebase-apply`
- cherry-pick → `.git/CHERRY_PICK_HEAD`
- revert → `.git/REVERT_HEAD`
- stash pop → 特別な in-progress 状態にならない（HEAD は動かない）。**衝突しても stash エントリは自動 drop されず残る**点に注意。

未解決ファイルを列挙する。

```bash
git status
git diff --name-only --diff-filter=U   # 未マージ（U）のみ列挙
git ls-files -u                        # stage 1=base / 2=ours / 3=theirs（欠けている stage で衝突の型が読める）
```

### 2. 退避線の確保（先に「戻れる」ことを保証する）

解消に手を付ける前に、事故時に戻れる状態を確認・案内する。**「戻せる」ことを保証してから編集に入る。**

- 中止で開始前へ完全に戻せる: `git merge --abort` / `git rebase --abort` / `git cherry-pick --abort` / `git revert --abort`（実行はユーザー明示指示時のみ）。
- `ORIG_HEAD` に開始前 HEAD が保存されている（後続操作で上書きされ得るので過信しない）。
- 堅い保険としてバックアップブランチを案内する: `git branch backup/before-<op>`。
- `git reflog` で見た目上消えたコミットも復元可能。
- **stash pop の衝突には `--abort` が無い**。pop 前へ戻すには手動 reset が要るが、stash エントリは残っているので復元できる旨を明示する。

### 3. 方向の翻訳（ours/theirs を具体ブランチ名に）

**ours/theirs の意味は merge と rebase で逆転する。** その時点の具体ブランチ名に翻訳して提示してから採用系の判断をする。

- **merge 中**: `ours` = 現在チェックアウト中のブランチ（HEAD）／`theirs` = マージしてくる相手。
- **rebase 中**: `ours` = rebase 先（onto / upstream）／`theirs` = 今 replay 中の自分のコミット。**merge と逆**。
- **cherry-pick / revert**: rebase と同様に「適用先が ours」。

### 4. 衝突の可視化（base を見る）

base を見ると「ours と theirs がそれぞれ base から何を変えたか」が分かり、**両者の変更を捨てて base に戻す誤り** を防げる。

- **ユーザーの global 設定は書き換えない。** 必要なファイルだけ base 付きで再表示する。

```bash
git checkout --conflict=zdiff3 <file>   # そのファイルの衝突を base 付き（zdiff3）で書き戻す。設定は汚さない
```

- マーカーの意味: `<<<<<<<`〜`=======` が **ours**、`=======`〜`>>>>>>>` が **theirs**、`|||||||`〜`=======` が **base（共通祖先）**。

### 5. 解消（ハンク単位で統合）

- 両側の意図を読み、**ハンク単位・行単位で統合**する。`<<<<<<<` `=======` `>>>>>>>` `|||||||` のマーカー行はすべて除去する。
- lockfile / 生成物は手編集せず、片側を採用してから再生成する（例: `git checkout --theirs package-lock.json && npm install`、`go.sum` は `go mod tidy`）。
- 読み切れない衝突・ドメイン判断が要る衝突は、埋めずに人へエスカレーションする。

### 6. 検証（マーカー除去 → テスト）

順序を固定する: **マーカー全除去確認 → ビルド/テスト**。

```bash
# 追跡ファイルに残存マーカーが無いか（|||||||（base）も対象。=== は正当な区切りで出るので中身を必ず確認）
git grep -nE '^(<<<<<<<|=======|>>>>>>>|\|\|\|\|\|\|\|)'
git diff --name-only --diff-filter=U   # 空になっていること（未解決ゼロ）を再確認
```

- マーカーが消えても解消が正しいとは限らない（**意味的コンフリクト**: シグネチャ変更 × 呼び出し追加、定数変更 × 依存ロジック追加など、テキスト上は衝突しないが論理が壊れる）。
- ビルド / lint / test を回して裏を取る。実行は `dotfiles-lint-and-test` に委譲する。**テストが通るまで「解決」と報告しない。**

### 7. 確定（add まで。以降は委譲）

- 解消済みファイルを `git add <file>` する（ここまではこのスキルが実行してよい）。
- `--continue` / `commit` / `push` はこのスキルでは行わない。`dotfiles-commit-push` に委譲し、人の確認を取る。

## 繰り返す衝突

同じ衝突を何度も解く（長命ブランチの繰り返し rebase 等）なら `git config rerere.enabled true`（rerere）を **提案** する。rerere は index を変更しないので、自動再適用されても内容を `git diff` で目視し `git add` は人が行う前提。global 設定の自動有効化はしない。

## エスカレーション

非対話環境では `git mergetool`（3-way GUI）は起動できない。複雑・大規模な衝突、両側の意図が読み切れない衝突は、衝突箇所と両側の意図を整理して人へ渡し、テキスト編集 or mergetool での判断を仰ぐ。
