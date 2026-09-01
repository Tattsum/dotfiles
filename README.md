dotfiles 管理用リポジトリです。

## セットアップ手順

- **初回 / マシン変更時**
  - このリポジトリを任意の場所に clone します（例：`~/workspace/dotfiles`）
  - リポジトリ直下で以下を実行します：
    - `chmod +x ./install.sh`
    - `./install.sh`

## `install.sh` の方針

- `DOTFILES_DIR` からホームディレクトリ配下へ **シンボリックリンクを張る** ことで設定を一元管理します。
- 共通関数 `link_file <src> <dest>` を使ってリンクを作成します。
  - 例：`link_file "$DOTFILES_DIR/zsh/.zshrc" "$HOME/.zshrc"`

## 設定を追加したいとき

- 例：`zsh` の設定を管理したい場合
  - `zsh/.zshrc` をこのリポジトリに追加
  - `install.sh` に以下のようなブロックを追記：
    - `echo ""`
    - `echo "------------------------------"`
    - `echo "🐚 zsh の設定をリンクします..." `
    - `echo "------------------------------"`
    - `link_file "$DOTFILES_DIR/zsh/.zshrc" "$HOME/.zshrc"`

この README と `install.sh` をベースに、必要な設定を少しずつ追加していく想定です。

## ターミナル IDE 環境（zellij + helix + yazi）

zellij をベースにしたターミナル IDE 環境を管理しています。

- `zellij/config.kdl` — zellij のデフォルトレイアウトを `ide` に設定
- `zellij/layouts/ide.kdl` — Editor / Implement / Review ペインからなる IDE レイアウト
- `helix/config.toml` — helix のキーマップ（`C-y` で yazi をフローティング起動）
- `helix/yazi-picker.sh` — yazi で選択したファイルを helix で開くためのスクリプト
- `bin/ide` — プロジェクト選択 → zellij セッション attach を行う起動スクリプト（`~/.local/bin/ide` にリンク）

これらは `install.sh` 実行時に `~/.config/zellij`・`~/.config/helix`・`~/.local/bin` 配下へシンボリックリンクされます。
`bin/ide` を使うには `~/.local/bin` が `PATH` に含まれている必要があります。

## その他のツール設定

- `git/.gitignore_global` — git のグローバル除外設定（`.gitconfig` の `core.excludesfile` が参照）
- `kitty/` — kitty ターミナルの設定一式（`kitty.conf`・テーマ・スクリプト）。`~/.config/kitty/` 配下へ個別にリンク
- `zed/settings.json` — Zed エディタの個人設定
- `gh/config.yml` — GitHub CLI の設定。**注意**: `gh` は設定変更時にこのファイルを置き換えることがあり、その際 symlink が解除される。気づいたら `./install.sh` を再実行する

## Homebrew パッケージ（Brewfile）

- `brew/Brewfile` に formula・cask・tap を記録しています（`brew bundle dump` で生成）。
- `install.sh` 実行時、`brew` があれば `brew bundle install` で未導入のものをまとめてインストールします（冪等）。
- **パッケージを追加・削除したら Brewfile を更新する**:
  ```sh
  brew bundle dump --force --file=brew/Brewfile
  ```
  `dump` は `installed_on_request` なもの（自分で明示 install したもの）を拾います。検証用に一時的に
  入れたものも残るため、**commit 前に `git diff` を必ずレビューする**こと。`tap` 行には `trusted: true`
  が付くので、サードパーティ tap の信頼宣言をリポジトリに焼き込む点も意識して承認します。
- 不要になったパッケージを Brewfile に揃えて削除したい場合（Brewfile に無いものをアンインストール）:
  ```sh
  brew bundle cleanup --file=brew/Brewfile        # 削除対象の確認（既定は dry-run）
  brew bundle cleanup --force --file=brew/Brewfile  # 実行
  ```
  **自動化しないこと。** Brewfile は削除判断の根拠にできる精度ではなく、依存として入っただけの
  ものまで削除対象に挙がります。
- 充足チェックには `--no-upgrade` を付けます。既定の `brew bundle check` は outdated も未充足として
  扱うため、ChatGPT のようにアプリ自身が更新する cask があると**恒久的に失敗**します:
  ```sh
  brew bundle check --no-upgrade --file=brew/Brewfile
  ```
  なお `check` は Brewfile 記載物の導入有無しか見ません。**実機にあって Brewfile に無いもの（余剰）は
  検出できない**ので、ドリフト確認は `dump` して `git diff` を見る手順で行います。

## launchd の定期ジョブ

`launchd/` 配下の plist を `~/Library/LaunchAgents/` へ配置し、`bin/install-launchagent` で登録します。
`install.sh` からも最後に呼ばれますが、失敗しても他の設定適用は巻き添えにしません。

| ラベル | 内容 | スケジュール |
|---|---|---|
| `com.tatsuma.kano.brew-maintenance` | `brew update` → `upgrade` → `cleanup`（`bin/brew-maintenance`） | 毎日 10:30 |
| `com.tatsuma.prompt-pattern-analysis` | プロンプト履歴のパターン抽出（`claude/prompt-patterns/run-analysis.sh`） | 毎日 11:00 / 19:00 |

```sh
./bin/install-launchagent                                    # 全 plist を登録し直す
./bin/install-launchagent com.tatsuma.kano.brew-maintenance  # ラベル指定
launchctl kickstart -k gui/$(id -u)/<label>                  # 即時実行
launchctl print gui/$(id -u)/<label>                         # 状態確認
launchctl bootout gui/$(id -u)/<label>                       # 停止
```

運用上の注意:

- plist は **symlink ではなく実体をコピー**します。launchd は bootstrap 時に内容をキャッシュするため、
  リンク先を編集しても反映されません。**plist を編集したら必ず `install-launchagent` を叩き直す**こと。
- plist は `$HOME` や `~` を展開しません（誤ったパスを書いても無言で失敗します）。パスは `/bin/zsh -c`
  経由でシェルに展開させ、ログの宛先はスクリプト側のリダイレクトに寄せています。
- `launchctl enable` は自動実行しません。システム設定 → ログイン項目でジョブを意図的にオフにした場合、
  `install.sh` の再実行で黙って再有効化されるのを避けるためです。過去に無効化していて `bootstrap` が
  失敗する場合のみ、案内に従って手動で `launchctl enable` してください。
- brew のジョブは**実行中のアプリを終了させません**（`HOMEBREW_NO_UPGRADE_QUIT_CASKS`）。また
  自己更新する cask には触れません（`HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS`）。
- ログは `~/Library/Logs/brew-maintenance.log`。スクリプトが追記の前に直近 30 実行分へ切り詰めます
  （`KEEP_RUNS` 環境変数で変更可）。旧形式のログは `brew-maintenance.log.legacy` に退避してあります。

## プロンプトパターン解析（prompt-pattern-scan）

`~/.claude/history.jsonl` から繰り返し作業パターンを抽出し、スキル化候補をレポートする仕組みです。

- `skills/src/prompt-pattern-scan/SKILL.md` — 手動起動用の skill
- `claude/prompt-patterns/ANALYSIS_PROMPT.md` — 解析ロジック本体（skill と日次バッチが共有）
- `claude/prompt-patterns/run-analysis.sh` — 日次バッチのランナー
- `launchd/com.tatsuma.prompt-pattern-analysis.plist` — スケジュール定義

**生成物はこのリポジトリで管理しません。** `state.json` / `report-latest.md` /
`classification-rules.json` は履歴の派生物で固有名詞を含み得るため、`~/.claude/prompt-patterns/` に
置いたまま `.gitignore` で除外しています（このリポジトリは public です）。

## Claude Code / Cursor / Codex の運用ルールと Skills

- 常時適用する運用ルールの正本は `claude/CLAUDE.md` です。
  - Claude Code: `~/.claude/CLAUDE.md`
  - Codex: `~/.codex/AGENTS.md`
- Skills の正本は `skills/src/` です。`./install.sh` により次へ同じ内容を symlink します。
  - `~/.claude/skills/`
  - `~/.cursor/skills/`
  - `~/.agents/skills/`（Codex）
- このリポジトリ自身では、ルートの `AGENTS.md` が同じ運用ルールを Codex に適用します。

### Cursor / Codex Skills（リポジトリ配布）

- **汎用 `.cursorrules`**
  - `cursor/.cursorrules` を用意しています。
  - 各リポジトリに入れたい場合は、そのリポジトリ直下へコピーして使ってください。
- **汎用 Skills**
  - `skills/` 配下に共通 Agent Skill の雛形を置いています。
  - 任意のリポジトリへ展開する例:
    - `make -C skills install TARGET=/path/to/repo`
  - `.cursor/skills/` と `.agents/skills/`（Codex）の両方へコピーされます。
