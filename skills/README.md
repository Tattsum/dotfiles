# skills（汎用）

複数リポジトリで使い回せる **Cursor Agent Skill** の雛形です。

## 方針

- **`src/<skill-id>/SKILL.md`** を編集の正本にする
- 各リポジトリに展開する場合は、対象リポジトリ側の `.cursor/skills/<skill-id>/` にコピーする
- 機密情報（トークン等）は skill に含めない（必要なら環境変数名だけを書く）

## レイアウト

```
skills/
├── README.md
├── Makefile
└── src/
    ├── dotfiles-commit-push/SKILL.md
    ├── dotfiles-go-backend-review/SKILL.md     # Go レビューの軽量・単発版（サブエージェント無し）
    ├── dotfiles-go-review/SKILL.md             # Go レビューのオーケストレーター（4観点=10サブエージェントを並列起動）
    ├── dotfiles-lint-and-test/SKILL.md
    ├── dotfiles-php-laravel-lint-test/SKILL.md
    ├── dotfiles-php-laravel-review/SKILL.md   # PHP/Laravel レビューのオーケストレーター（5観点を並列起動）
    ├── dotfiles-security-performance/SKILL.md
    ├── review-go-architecture/
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-go-idioms/
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-go-storage/
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-go-test/
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-php-architecture/
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-php-idioms/
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-php-storage/
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-php-test/
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-php-security/
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    └── devin-task-triage/SKILL.md
```

## コマンド

- `make -C skills list`
- `make -C skills install TARGET=<path-to-repo-root>`
- `make -C skills install-global` — `~/.claude/skills/` に全スキルをコピー（Claude Code グローバル利用）

