# skills（汎用）

複数リポジトリで使い回せる **Claude Code / Cursor / Codex Skill** の雛形です。

## 方針

- **`src/<skill-id>/SKILL.md`** を編集の正本にする
- 各リポジトリに展開する場合は、対象リポジトリ側の `.cursor/skills/<skill-id>/` と `.agents/skills/<skill-id>/` にコピーする
- 機密情報（トークン等）は skill に含めない（必要なら環境変数名だけを書く）

## レイアウト

`src/` 配下が編集の正本。各スキルは `SKILL.md` を持ち、重い詳細は `references/`（または同階層の補助 `.md`）に退避して必要時のみ読み込ませる。

```
skills/
├── README.md
├── Makefile
└── src/
    ├── dotfiles-plan-first/SKILL.md            # 実装着手前の標準WF（issue/Jira起点可・調査→技術選定→検証→/grill-me合意→実装→lint/test）
    ├── dotfiles-atlassian-investigate/SKILL.md # Jira/Confluence の URL 起点で調査し回答草案まで（読み取り専用・投稿しない）
    ├── dotfiles-commit-push/SKILL.md           # 秘密情報チェック + コミット規約を強制して commit / push
    ├── dotfiles-pr-create/SKILL.md             # push 済みブランチから PR を作成（既定 draft, base 自動判定）
    ├── dotfiles-lint-and-test/SKILL.md         # リポジトリ標準の lint / format / test を特定して実行
    ├── dotfiles-conflict-resolve/SKILL.md      # git コンフリクトを安全に解消（操作種別判定→退避線→解消→検証、add まで）
    ├── dotfiles-php-laravel-lint-test/SKILL.md # PHP/Laravel の lint / 静的解析 / test を実行
    ├── dotfiles-security-performance/SKILL.md  # セキュリティ + パフォーマンスを Must/Should/Nice で指摘
    ├── dotfiles-go-review/SKILL.md             # Go レビューのオーケストレーター（4観点=10サブエージェントを並列起動）
    ├── dotfiles-php-laravel-review/SKILL.md    # PHP/Laravel レビューのオーケストレーター（5観点を並列起動）
    ├── review-go-architecture/                 # Go: アーキテクチャ / レイヤー責務（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-go-idioms/                        # Go: イディオム / 型安全 / 命名（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-go-storage/                       # Go: DB / クエリ性能 / 外部I/O（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-go-test/                          # Go: テスト戦略 / テスト品質（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-php-architecture/                 # PHP: レイヤー責務 / 設計（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-php-idioms/                        # PHP: イディオム / 型安全 / 命名（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-php-storage/                       # PHP: DB / クエリ性能（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-php-test/                          # PHP: テスト命名・構造 / 品質（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-php-security/                      # PHP: インジェクション / 認可 / 機微情報（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-iac/                               # IaC: Terraform/jsonnet の module 境界・ライフサイクル / 命名規約（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-skill-security/                    # 外部 Skill をインストール前にセキュリティ静的解析
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── improve-codebase-architecture/           # 深掘り候補を発見→HTMLレポート→grilling（オーケストレーター）
    │   ├── SKILL.md
    │   ├── LANGUAGE.md
    │   ├── HTML-REPORT.md
    │   ├── DEEPENING.md
    │   └── INTERFACE-DESIGN.md
    ├── devin-task-triage/SKILL.md              # 開発タスクを Devin 送り / ここで処理 に振り分け
    ├── prompt-pattern-scan/SKILL.md            # プロンプト履歴から繰り返し作業を抽出しスキル化候補を出す
    └── dotfiles-nippo/SKILL.md                 # セッションログから日報を生成（内省は書かず問いだけ残す）
```

## コマンド

- `make -C skills list`
- `make -C skills install TARGET=<path-to-repo-root>` — 他リポジトリの `.cursor/skills/` と `.agents/skills/` へコピー
- `./install.sh` — `~/.claude/skills/`、`~/.cursor/skills/`、`~/.agents/skills/` へ symlink（グローバル利用の正本）

グローバル配置は symlink なので、`src/` を編集した時点で反映される。`skill-*` スクリプトも
`install.sh` が `~/.local/bin/` へリンクするため、SKILL.md からはコマンド名で呼べる。
