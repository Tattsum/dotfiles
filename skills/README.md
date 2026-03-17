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
    ├── dotfiles-lint-and-test/SKILL.md
    └── dotfiles-security-performance/SKILL.md
```

## コマンド

- `make -C skills list`
- `make -C skills install TARGET=<path-to-repo-root>`

