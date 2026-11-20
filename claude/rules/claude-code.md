# Claude Code 固有の指示

Claude Code の sandbox を前提にした運用。全エージェント共通の指示は `~/.claude/CLAUDE.md`（dotfiles の `agents/AGENTS.md`）にある。sandbox の中で必ず失敗するコマンドの書き方（除外コマンドの複合実行、`$TMPDIR` の受け渡し、`<(...)`、書き込み禁止パスに触れる git 操作、sandbox 外での `aws` など）は、PreToolUse hook（dotfiles の `tools/agent-bash-guard`）が理由と直し方を添えて止めるので、ここには書かない。

- 本番への書き込み（AWS の `run-task` など）は自分で実行しない。復唱と事前チェックまでを行い、コマンドそのものを利用者に渡して `!` で実行してもらう。
- sandbox の通信許可（settings の `sandbox.network.allowedDomains` や `WebFetch(domain:…)`）は自分から足さない。要るホストはその Bash 呼び出しの `allowed_domains` で宣言し、都度の審査を受ける（crates の `build.rs` のように、取得したコードがビルド時に動くものがある）。
- git の切り替えや取り込みが sandbox 内で途中で止まったら（禁止パスだけ更新されず、HEAD・index・作業ツリーが食い違う。exit 0 や `D<TAB>path` の羅列だけで終わることもある）、`git status` で利用者の編集が混ざっていないかを確かめ、混ざっていれば別名のコピーに退避する。そのうえで sandbox 外で `git checkout -f <ブランチ名>`（pull・merge なら `git checkout -f HEAD` のあとにやり直す）で揃える。追跡外のファイルの `git clean` は利用者に任せる。
