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
    ├── dotfiles-plan-first/SKILL.md            # 実装着手前の標準WF（issue/Jira起点可・調査→技術選定→検証→grill-me合意→実装→lint/test）
    ├── dotfiles-atlassian-investigate/SKILL.md # Jira/Confluence の URL 起点で調査し回答草案まで（読み取り専用・投稿しない）
    ├── dotfiles-commit-push/SKILL.md           # 秘密情報チェック + コミット規約を強制して commit / push
    ├── dotfiles-pr-create/SKILL.md             # push 済みブランチから PR を作成（既定 draft, base 自動判定）
    ├── dotfiles-lint-and-test/SKILL.md         # リポジトリ標準の lint / format / test を特定して実行
    ├── dotfiles-conflict-resolve/SKILL.md      # git コンフリクトを安全に解消（操作種別判定→退避線→解消→検証、add まで）
    ├── dotfiles-php-laravel-lint-test/SKILL.md # PHP/Laravel の lint / 静的解析 / test を実行
    ├── dotfiles-security-performance/SKILL.md  # 設計・実装時の軽量チェック（セキュリティは3つの問い＋原則、詳細は review-web-security）+ パフォーマンス
    ├── dotfiles-review-and-act/                # PR レビュー → 所有者で分岐（自分=改修 / 他人=インライン投稿）
    │   ├── SKILL.md
    │   └── references/
    │       └── cross-review.md                 # 別エージェント（Codex ⇄ Claude Code）の公式レビューをセカンドオピニオンとして取り込む手順（4オーケストレーター共通）
    ├── dotfiles-go-review/SKILL.md             # Go レビューのオーケストレーター（7観点=23サブエージェントを並列起動）
    ├── dotfiles-php-laravel-review/SKILL.md    # PHP/Laravel レビューのオーケストレーター（6観点=20サブエージェントを並列起動）
    ├── dotfiles-ts-review/SKILL.md             # TS/Vue/React レビューのオーケストレーター（6観点=20サブエージェントを並列起動）
    ├── review-web-security/                    # Web セキュリティ（言語横断・書籍準拠）。3オーケストレーターの security 観点の正本
    │   ├── SKILL.md
    │   └── references/
    │       ├── focus-blocks.md                 # コード用 8 focus（インジェクション〜情報露出・ログ・本番設定）
    │       ├── focus-blocks-supply-chain.md    # 配備・サプライチェーン（Dockerfile / CI / lock があるときだけ起動）
    │       ├── owasp-masvs.md                 # OWASP MASVS 索引との対応・出典・モバイルへの適用境界
    │       ├── must-verification.md            # security の Must 候補を 1 体で反証する契約
    │       ├── output-discipline.md            # Source→Sink・確認できなかった範囲・到達性・2 軸の重要度の出力規律
    │       └── sinks-go.md / sinks-php.md / sinks-ts.md  # 言語別 Sink 表
    ├── review-go-architecture/                 # Go: アーキテクチャ / レイヤー責務（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-go-idioms/                       # Go: イディオム / 型安全 / 命名（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-go-storage/                      # Go: DB / クエリ性能 / 外部I/O（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-go-test/                         # Go: テスト戦略 / テスト品質（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-go-observability/                # Go: ログ / 観測性 / 調査可能性（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-go-grpc/                         # Go: gRPC / Protobuf スキーマ・後方互換（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-php-architecture/                # PHP: レイヤー責務 / 設計（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-php-idioms/                      # PHP: イディオム / 型安全 / 命名（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-php-storage/                     # PHP: DB / クエリ性能（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-php-test/                        # PHP: テスト命名・構造 / 品質（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-php-observability/               # PHP: ログ / 観測性 / 調査可能性（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-ts-architecture/                 # TS: コンポーネント責務 / Container-Presentational（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-ts-idioms/                       # TS: 型安全 / 型定義 / styling・a11y / コード衛生（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-ts-state/                        # TS: 状態管理スコープ / effects・非同期（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-ts-performance/                  # TS: 再レンダリング / ロード・計算コスト（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-ts-test/                         # TS: テスト戦略 / テスト品質（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-reachability/                    # 差分が触れる入口・リソースの到達性（IaC＋任意でライブ）を返す。security 観点と review-and-act が利用
    │   ├── SKILL.md
    │   └── references/iac-signals.md
    ├── review-iac/                             # IaC: Terraform/jsonnet の module 境界・ライフサイクル / 命名規約（単体観点）
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── review-skill-security/                  # 外部 Skill をインストール前にセキュリティ静的解析
    │   ├── SKILL.md
    │   └── references/focus-blocks.md
    ├── prompt-pattern-scan/SKILL.md            # プロンプト履歴から繰り返し作業を抽出しスキル化候補を出す
    ├── grill-me/SKILL.md                       # 設計・計画を bounded なラウンドで問い詰める（明示起動、または plan-first の合意フェーズから）
    └── dotfiles-nippo/SKILL.md                 # ログ・議事録・Jira/Confluence/Slack/GitHub から本人の作業に絞って日報を生成
```

## コマンド

- `make -C skills list`
- `make -C skills install TARGET=<path-to-repo-root>` — 他リポジトリの `.cursor/skills/` と `.agents/skills/` へコピー
- `./install.sh` — `~/.claude/skills/`、`~/.cursor/skills/`、`~/.agents/skills/` へ symlink（グローバル利用の正本）

グローバル配置は symlink なので、`src/` を編集した時点で反映される。`skill-*` スクリプトも
`install.sh` が `~/.local/bin/` へリンクするため、SKILL.md からはコマンド名で呼べる。

### skill-aws-reach（到達性のライブ裏取り）

`review-reachability` が AWS の到達性メタデータ（LB・SG・サブネット・CloudFront・API Gateway など）を読むための、許可した Describe/Get だけを呼ぶラッパー。

- `SKILL_AWS_REACH_PROFILE` に宣言するのは、[SecurityAudit](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/SecurityAudit.html) 相当のメタデータ専用ロールのプロファイルに限る。ラッパーはロールの権限を検証できないため、ロールの用意は利用者の責任
- 未設定なら AWS を呼ばず IaC のみで判定する
- 値（プロファイル・リージョン・許可アカウント）は公開リポに書かず、ハブリポの `settings.local.json` の `env` などで渡す
