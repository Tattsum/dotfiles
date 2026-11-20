package main

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// fakeGit は、コミット署名が有効で、origin が GitHub の SSH、web が HTTPS を指すリポジトリとして答える。
func fakeGit(signed bool) func(string, ...string) (string, error) {
	return func(_ string, args ...string) (string, error) {
		switch strings.Join(args, " ") {
		case "config --get commit.gpgsign":
			if signed {
				return "true", nil
			}
			return "false", nil
		case "remote get-url origin":
			return "git@github.com:o/r.git", nil
		case "remote get-url web":
			return "https://github.com/o/r.git", nil
		case "rev-parse --abbrev-ref @{u}":
			return "origin/main", nil
		}
		return "", errors.New("not faked: " + strings.Join(args, " "))
	}
}

func TestEvaluate(t *testing.T) {
	cases := []struct {
		name        string
		agent       string
		command     string
		unsandboxed bool
		allowed     []string
		settings    string // cwd の .claude/settings.local.json
		unsigned    bool
		want        string
	}{
		// op
		{name: "op を止める", command: "op read op://vault/item/field", want: "op"},
		{name: "&& の後ろの op も止める", command: "cd x && op item get y", want: "op"},
		{name: "Codex でも op を止める", agent: "codex", command: "op whoami", want: "op"},
		{name: "引用符の中の op は止めない", command: "echo 'op read'", want: ""},
		{name: "op で始まる別コマンドは止めない", command: "opx run", want: ""},

		// インラインのインタプリタ
		{name: "python -c を止める", command: "python3 -c 'print(1)'", want: "inline-interpreter"},
		{name: "ヒアドキュメントで渡す python を止める", command: "python3 - <<'EOF'\nprint(1)\nEOF", want: "inline-interpreter"},
		{name: "標準入力のヒアドキュメントだけの python を止める", command: "python3 <<EOF\nprint(1)\nEOF", want: "inline-interpreter"},
		{name: "パイプの先の python -c を止める", command: "cat x.json | python3 -c 'import json'", want: "inline-interpreter"},
		{name: "node -e を止める", command: "node -e 'console.log(1)'", want: "inline-interpreter"},
		{name: "perl -pe を止める", command: "perl -pe 's/a/b/' f.txt", want: "inline-interpreter"},
		{name: "perl -lane を止める", command: "perl -lane 'print $F[0]' f.txt", want: "inline-interpreter"},
		{name: "ruby -e を止める", command: "ruby -e 'p 1'", want: "inline-interpreter"},
		{name: "絶対パスの python -c を止める", command: "/usr/bin/python3 -c 'x'", want: "inline-interpreter"},
		{name: "zsh -lc の中の python -c を止める", command: "/bin/zsh -lc \"python3 -c 'print(1)'\"", want: "inline-interpreter"},
		{name: "Codex でもインラインの python を止める", agent: "codex", command: "python3 -c 'print(1)'", want: "inline-interpreter"},
		{name: "python -m は止めない", command: "echo '{}' | python3 -m json.tool", want: ""},
		{name: "スクリプトファイルの python は止めない", command: "python3 scripts/lint.py --json a.md", want: ""},
		{name: "uv run は止めない", command: "uv run skills/src/natural-japanese/scripts/lint.py a.md", want: ""},
		{name: "node のスクリプトファイルは止めない", command: "node scripts/build.js", want: ""},
		{name: "--version は止めない", command: "node --version", want: ""},
		{name: "perl のスクリプトファイルは止めない", command: "perl -w script.pl", want: ""},
		{name: "引用符の中の python -c は止めない", command: "echo 'python3 -c x'", want: ""},
		{name: "ruby -Itest でのテストファイルの実行は止めない", command: "ruby -Itest test/foo_test.rb", want: ""},
		{name: "ruby -rset でのスクリプトファイルの実行は止めない", command: "ruby -rset script.rb", want: ""},
		{name: "perl -MEnglish でのスクリプトファイルの実行は止めない", command: "perl -MEnglish script.pl", want: ""},
		{name: "python3 -mjson.tool は止めない", command: "cat f.json | python3 -mjson.tool", want: ""},
		{name: "perl -0777pe を止める", command: "perl -0777pe 's/a/b/' f.txt", want: "inline-interpreter"},
		{name: "-c に続けて書いた python のコードを止める", command: "python3 -c'print(1)'", want: "inline-interpreter"},
		{name: "python3 -Ic を止める", command: "python3 -Ic 'print(1)'", want: "inline-interpreter"},
		{name: "uv run python -c を止める", command: "uv run python -c 'print(1)'", want: "inline-interpreter"},
		{name: "npx node -e を止める", command: "npx node -e 'console.log(1)'", want: "inline-interpreter"},
		{name: "nice python3 -c を止める", command: "nice python3 -c 'print(1)'", want: "inline-interpreter"},
		{name: "eval の中の python -c を止める", command: "eval \"python3 -c 'print(1)'\"", want: "inline-interpreter"},
		{name: "xargs の先の op を止める", command: "echo x | xargs op read", want: "op"},
		{name: "uv run のスクリプトファイルは止めない", command: "uv run python scripts/lint.py", want: ""},

		// rg の -r
		{name: "rg -rn を止める", command: "rg -rn foo src", want: "rg-replace-flag"},
		{name: "rg -nri を止める", command: "rg -nri foo", want: "rg-replace-flag"},
		{name: "Codex でも rg -rn を止める", agent: "codex", command: "rg -rl foo", want: "rg-replace-flag"},
		{name: "rg -n は止めない", command: "rg -n foo", want: ""},
		{name: "r が末尾の -or は置換の正しい書き方なので止めない", command: "rg -or '$1' 'x(\\d)'", want: ""},
		{name: "rg -r と置換文字列は止めない", command: "rg -r '$1' 'a(b)'", want: ""},
		{name: "-e の値の -rn は止めない", command: "rg -e -rn file", want: ""},
		{name: "-t に続けた型名の r は止めない", command: "rg -trust foo", want: ""},
		{name: "-e に続けたパターンの r は止めない", command: "rg -erro f.txt", want: ""},
		{name: "xargs の先の rg -rn を止める", command: "fd -e go | xargs rg -rn foo", want: "rg-replace-flag"},

		// sandbox 除外コマンドの複合
		{name: "単独の gh は止めない", command: "gh pr view 1", want: ""},
		{name: "--jq の中の | は止めない", command: "gh pr view 1 --json title --jq '.title | ascii_downcase'", want: ""},
		{name: "gh の 2>&1 は止めない", command: "gh pr list 2>&1", want: ""},
		{name: "gh の行継続は止めない", command: "gh api repos/o/r/pulls \\\n  --jq '.[].number'", want: ""},
		{name: "gh のパイプを止める", command: "gh pr view 1 | head", want: "excluded-compound"},
		{name: "gh の 2>/dev/null を止める", command: "gh pr view 1 2>/dev/null", want: "excluded-compound"},
		{name: "gh のファイルへのリダイレクトを止める", command: "gh pr view 1 > out.txt", want: "excluded-compound"},
		{name: "gh の環境変数の前置を止める", command: "GH_PAGER= gh pr view 1", want: "excluded-compound"},
		{name: "cd と組み合わせた gh を止める", command: "cd repo && gh pr view 1", want: "excluded-compound"},
		{name: "ループの中の gh を止める", command: "for n in 1 2; do gh pr view $n; done", want: "excluded-compound"},
		{name: "$(gh ...) を止める", command: "echo $(gh pr view 1)", want: "excluded-compound"},
		{name: "bash -c の中の gh を止める", command: "bash -c 'gh pr view 1'", want: "excluded-compound"},
		{name: "絶対パスの gh を止める", command: "/opt/homebrew/bin/gh pr view 1", want: "excluded-compound"},
		{name: "allowed_domains に api.github.com があれば gh のパイプは止めない", command: "gh pr view 1 | head", allowed: []string{"api.github.com"}, want: ""},
		{name: "sandbox 外でも gh のパイプは止める", command: "gh pr view 1 | head", unsandboxed: true, want: "excluded-compound"},
		{name: "skill-review-state のパイプを止める", command: "skill-review-state 12 | jq .", want: "excluded-compound"},
		{name: "単独の git commit -F は止めない", command: "git commit -F /tmp/claude-502/msg.txt", want: ""},
		{name: "git add && git commit を止める", command: "git add a && git commit -F /tmp/claude-502/msg.txt", want: "excluded-compound"},
		{name: "git commit -m \"$(cat <<EOF)\" を止める", command: "git commit -m \"$(cat <<'EOF'\nfix | a && b\nEOF\n)\"", want: "excluded-compound"},
		{name: "git -C の commit を止める", command: "git -C /repo commit -F /m", want: "excluded-compound"},
		{name: "git push のパイプを止める", command: "git push origin main 2>&1 | tail -3", want: "excluded-compound"},
		{name: "sandbox 外の git add && git commit は止めない", command: "git add a && git commit -F /m", unsandboxed: true, want: ""},
		{name: "引用符の中の gh | は止めない", command: "rg 'gh pr view | head' notes.md", want: ""},
		{name: "コメントの中の gh は止めない", command: "ls # gh pr view | head", want: ""},
		{name: "gh どうしの && は全体が sandbox の外で動くので止めない", command: "gh pr view 1 && gh pr view 2 --jq .title", want: ""},
		{name: "除外コマンドどうしの ; と || は止めない", command: "git fetch origin main; gh pr view 1 || gh pr list 2>&1", want: ""},
		{name: "gh どうしでも片方にリダイレクトがあれば止める", command: "gh pr view 1 && gh pr view 2 > out.txt", want: "excluded-compound"},
		{name: "gh と echo の && を止める", command: "gh pr view 1 && echo ok", want: "excluded-compound"},
		{name: "Codex では gh のパイプを止めない", agent: "codex", command: "gh pr view 1 | head", want: ""},
		{name: "プロジェクトの WebFetch 許可で api.github.com に届くなら gh のパイプは止めない", command: "gh pr view 1 | head",
			settings: `{"permissions":{"allow":["WebFetch(domain:api.github.com)"]}}`, want: ""},
		{name: "プロジェクトの sandbox 通信許可で api.github.com に届くなら gh のパイプは止めない", command: "gh pr view 1 | head",
			settings: `{"sandbox":{"network":{"allowedDomains":["*.github.com"]}}}`, want: ""},
		{name: "allowed_domains に github.com:22 があれば SSH の git push のパイプは止めない", command: "git push origin main 2>&1 | tail -3",
			allowed: []string{"github.com:22"}, want: ""},
		{name: "ポートの無い github.com の許可なら git push のパイプは止めない", command: "git push origin main | tail -3",
			settings: `{"permissions":{"allow":["WebFetch(domain:github.com)"]}}`, want: ""},
		{name: "HTTPS のリモートに 22 番だけの許可では git push のパイプを止める", command: "git push web main 2>&1 | tail -3",
			allowed: []string{"github.com:22"}, want: "excluded-compound"},
		{name: "upstream のリモートへの git fetch の && を止める", command: "git fetch && git status", want: "excluded-compound"},
		{name: "署名しないリポジトリの git add && git commit は止めない", command: "git add a && git commit -F /m", unsigned: true, want: ""},
		{name: "skill-cross-review のパイプは通信許可にかかわらず止める", command: "skill-cross-review --base main | jq .",
			allowed: []string{"api.github.com"}, want: "excluded-compound"},
		{name: "sandbox を無効にしたプロジェクトでは gh のパイプを止めない", command: "gh pr view 1 | head",
			settings: `{"sandbox":{"enabled":false}}`, want: ""},
		{name: "通信しない gh --help のパイプは止めない", command: "gh pr create --help | head -30", want: ""},
		{name: "通信しない gh --version のパイプは止めない", command: "gh --version | head -1", want: ""},
		{name: "通信しない gh completion のパイプは止めない", command: "gh completion -s zsh | head", want: ""},
		{name: "api.github.com を許可しても gh run view --log のパイプは止める", command: "gh run view 1 --log | rg error",
			allowed: []string{"api.github.com"}, want: "excluded-compound"},
		{name: "単独の gh でも sandbox 外の指定は止める", command: "gh pr list", unsandboxed: true, want: "excluded-compound"},
		{name: "xargs の先の gh を止める", command: "echo 1 | xargs gh pr view", want: "excluded-compound"},
		{name: "署名を切った git -c commit.gpgsign=false commit は止めない", command: "git -c commit.gpgsign=false commit -m x", want: ""},
		{name: "--no-gpg-sign の git add && git commit は止めない", command: "git add a && git commit --no-gpg-sign -F /m", want: ""},

		// sandbox 除外コマンドに渡す $TMPDIR
		{name: "gh に $TMPDIR を渡すのを止める", command: "gh pr edit 1 --body-file \"$TMPDIR/body.md\"", want: "excluded-tmpdir"},
		{name: "git commit に ${TMPDIR} を渡すのを止める", command: "git commit -F \"${TMPDIR}/msg\"", want: "excluded-tmpdir"},
		{name: "gh に絶対パスを渡すのは止めない", command: "gh pr edit 1 --body-file /tmp/claude-502/body.md", want: ""},
		{name: "単一引用符の $TMPDIR は展開されないので止めない", command: "gh pr edit 1 --body-file '$TMPDIR/x'", want: ""},
		{name: "除外コマンド以外の $TMPDIR は止めない", command: "cat \"$TMPDIR/x\"", want: ""},

		// プロセス置換
		{name: "<(...) を止める", command: "diff <(sort a) <(sort b)", want: "process-substitution"},
		{name: "sandbox 外の <(...) は止めない", command: "diff <(sort a) <(sort b)", unsandboxed: true, want: ""},
		{name: "sandbox を無効にしたプロジェクトでは <(...) を止めない", command: "diff <(sort a) <(sort b)",
			settings: `{"sandbox":{"enabled":false}}`, want: ""},
		{name: "Codex では <(...) を止めない", agent: "codex", command: "diff <(sort a) <(sort b)", want: ""},
		{name: "引用符の中の <( は止めない", command: "echo '<(x)'", want: ""},
		{name: "ヒアドキュメントの本文の <( は止めない", command: "cat <<'EOF'\ndiff <(a) <(b)\nEOF", want: ""},

		// mktemp
		{name: "引数なしの mktemp -d を止める", command: "mktemp -d", want: "mktemp-default-dir"},
		{name: "引数なしの mktemp を止める", command: "mktemp", want: "mktemp-default-dir"},
		{name: "mktemp -t を止める", command: "mktemp -t foo", want: "mktemp-default-dir"},
		{name: "$(mktemp -d) を止める", command: "d=$(mktemp -d)", want: "mktemp-default-dir"},
		{name: "テンプレート付きの mktemp -d は止めない", command: "mktemp -d \"${TMPDIR:-/tmp}/x.XXXXXX\"", want: ""},
		{name: "sandbox 外の mktemp -d は止めない", command: "mktemp -d", unsandboxed: true, want: ""},
		{name: "ファイルを作らない mktemp -u は止めない", command: "mktemp -u -t foo", want: ""},

		// aws
		{name: "sandbox 内の aws は止めない", command: "aws sts get-caller-identity", want: ""},
		{name: "sandbox 外の aws を止める", command: "aws ecs list-clusters", unsandboxed: true, want: "aws-unsandboxed"},

		// go install
		{name: "GOBIN なしの go install を止める", command: "go install golang.org/x/tools/cmd/stringer@latest", want: "go-install-gobin"},
		{name: "GOBIN を前置した go install は止めない", command: "GOBIN=\"$TMPDIR/bin\" go install x@latest", want: ""},
		{name: "export GOBIN した go install は止めない", command: "export GOBIN=/tmp/claude-502/bin; go install x@latest", want: ""},
		{name: "sandbox 外の go install は止めない", command: "go install x@latest", unsandboxed: true, want: ""},
		{name: "go build は止めない", command: "go build ./...", want: ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			agent := tc.agent
			if agent == "" {
				agent = "claude"
			}
			cwd := t.TempDir()
			if tc.settings != "" {
				if err := os.MkdirAll(filepath.Join(cwd, ".claude"), 0o755); err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(filepath.Join(cwd, ".claude", "settings.local.json"), []byte(tc.settings), 0o644); err != nil {
					t.Fatal(err)
				}
			}
			in := toolInput{Command: tc.command, Unsandboxed: tc.unsandboxed, AllowedDomains: tc.allowed}
			got := evaluate(in, options{agent: agent, cwd: cwd, home: t.TempDir(), git: fakeGit(!tc.unsigned), managedDir: t.TempDir()})
			if got.rule != tc.want {
				t.Errorf("rule = %q, want %q (reason: %s)", got.rule, tc.want, got.reason)
			}
		})
	}
}
