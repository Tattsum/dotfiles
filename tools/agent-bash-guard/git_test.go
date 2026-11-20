package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

// setupRepo は、守られたパスを変えるブランチと変えないブランチを持つリポジトリと、
// settings.json をそのリポジトリ内へリンクした HOME を作る。
func setupRepo(t *testing.T) (repo, home string) {
	t.Helper()
	t.Setenv("GIT_CONFIG_GLOBAL", os.DevNull)
	t.Setenv("GIT_CONFIG_NOSYSTEM", "1")
	t.Setenv("GIT_AUTHOR_NAME", "t")
	t.Setenv("GIT_AUTHOR_EMAIL", "t@example.com")
	t.Setenv("GIT_COMMITTER_NAME", "t")
	t.Setenv("GIT_COMMITTER_EMAIL", "t@example.com")
	root := t.TempDir()
	repo = filepath.Join(root, "repo")
	home = filepath.Join(root, "home")
	git := func(args ...string) {
		t.Helper()
		if out, err := exec.Command("git", append([]string{"-C", repo}, args...)...).CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	write := func(rel, body string) {
		t.Helper()
		p := filepath.Join(repo, rel)
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.MkdirAll(repo, 0o755); err != nil {
		t.Fatal(err)
	}
	git("init", "-q", "-b", "main")
	write("a.txt", "a")
	write("b.txt", "b")
	write(".claude/settings.json", "{}")
	write("linked/settings.json", "{}")
	write("nested/.claude/settings.json", "{}")
	git("add", ".")
	git("commit", "-q", "-m", "init")
	for branch, file := range map[string]string{"touch-claude": ".claude/settings.json", "touch-linked": "linked/settings.json", "touch-nested": "nested/.claude/settings.json", "plain": "b.txt"} {
		git("switch", "-q", "-c", branch)
		write(file, "changed")
		git("commit", "-q", "-am", branch)
		git("switch", "-q", "main")
	}
	git("remote", "add", "origin", filepath.Join(root, "remote.git"))
	git("update-ref", "refs/remotes/origin/remote-only", "plain")
	git("branch", "--set-upstream-to=origin/remote-only", "plain")

	if err := os.MkdirAll(filepath.Join(home, ".claude"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(repo, "linked/settings.json"), filepath.Join(home, ".claude/settings.json")); err != nil {
		t.Fatal(err)
	}
	return repo, home
}

func TestGitRules(t *testing.T) {
	repo, home := setupRepo(t)
	if err := os.WriteFile(filepath.Join(repo, ".claude/settings.json"), []byte("edited"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(repo, "b.txt"), []byte("edited"), 0o644); err != nil {
		t.Fatal(err)
	}
	cases := []struct {
		name        string
		cwd         string
		command     string
		unsandboxed bool
		want        string
	}{
		{name: "守られたパスを変えるブランチへの switch を止める", command: "git switch touch-claude", want: "git-protected-tree"},
		{name: "settings.json のリンク先を変えるブランチへの checkout を止める", command: "git checkout touch-linked", want: "git-protected-tree"},
		{name: "守られたパスを変えるブランチの merge を止める", command: "git merge touch-claude", want: "git-protected-tree"},
		{name: "変更された守られたファイルを checkout -- で戻すのを止める", command: "git checkout -- .claude/settings.json", want: "git-protected-tree"},
		{name: "-C で指したリポジトリの switch も止める", cwd: "/", command: "git -C " + repo + " switch touch-claude", want: "git-protected-tree"},
		{name: "cd したリポジトリの switch も止める", cwd: "/", command: "cd " + repo + " && git switch touch-claude", want: "git-protected-tree"},
		{name: "守られたパスを変えないブランチへの switch は止めない", command: "git switch plain", want: ""},
		{name: "入れ子の .claude/ は守られていないので止めない", command: "git switch touch-nested", want: ""},
		{name: "祖先を取り込むだけの merge は何も書き換えないので止めない", command: "git merge main", want: ""},
		{name: "守られたパスを変えるブランチへの reset --hard を止める", command: "git reset --hard touch-claude", want: "git-protected-tree"},
		{name: "変更された守られたファイルを reset --hard で捨てるのを止める", command: "git reset --hard", want: "git-protected-tree"},
		{name: "reset --mixed は作業ツリーを書き換えないので止めない", command: "git reset touch-claude", want: ""},
		{name: "守られたパスを変えるブランチへの rebase を止める", command: "git rebase touch-claude", want: "git-protected-tree"},
		{name: "守られたファイルを restore --source で戻すのを止める", command: "git restore --source touch-claude -- .claude/settings.json", want: "git-protected-tree"},
		{name: "index だけの restore --staged は止めない", command: "git restore --staged .claude/settings.json", want: ""},
		{name: "守られたファイルを変えたコミットの cherry-pick を止める", command: "git cherry-pick touch-claude", want: "git-protected-tree"},
		{name: "cd $HOME 経由のディレクトリでも判定する", cwd: "/", command: "cd $HOME/../repo && git switch touch-claude", want: "git-protected-tree"},
		{name: "git remote set-head は .git/config に書かないので止めない", command: "git remote set-head origin main", want: ""},
		{name: "git config --type 付きの読み取りは止めない", command: "git config --type bool core.filemode", want: ""},
		{name: "起点なしの switch -c は止めない", command: "git switch -c fresh", want: ""},
		{name: "守られていないファイルの checkout -- は止めない", command: "git checkout -- b.txt", want: ""},
		{name: "upstream の無い pull は判定できないので止めない", command: "git pull", want: ""},
		{name: "sandbox 外の switch は止めない", command: "git switch touch-claude", unsandboxed: true, want: ""},
		{name: "追跡設定のあるブランチの git branch -d を止める", command: "git branch -d plain", want: "git-config-write"},
		{name: "追跡設定の無いブランチの git branch -D は .git/config に書かないので止めない", command: "git branch -D touch-linked", want: ""},
		{name: "リモート追跡ブランチを起点にした switch -c を止める", command: "git switch -c tracked origin/remote-only", want: "git-config-write"},
		{name: "リモートにだけあるブランチへの switch を止める", command: "git switch remote-only", want: "git-config-write"},
		{name: "git remote add を止める", command: "git remote add up https://example.com/x.git", want: "git-config-write"},
		{name: "git config の書き込みを止める", command: "git config user.name x", want: "git-config-write"},
		{name: "git config の読み取りは止めない", command: "git config --get user.name", want: ""},
		{name: "git config --global は止めない", command: "git config --global user.name x", want: ""},
		{name: "--no-track の switch -c は追跡設定を書かないので止めない", command: "git switch --no-track -c untracked origin/remote-only", want: ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			cwd := tc.cwd
			if cwd == "" {
				cwd = repo
			}
			in := toolInput{Command: tc.command, Unsandboxed: tc.unsandboxed}
			got := evaluate(in, options{agent: "claude", cwd: cwd, home: home, git: runGit, managedDir: t.TempDir()})
			if got.rule != tc.want {
				t.Errorf("rule = %q, want %q (reason: %s)", got.rule, tc.want, got.reason)
			}
		})
	}
}

func TestGitConfigWriteInTempRepo(t *testing.T) {
	repo, home := setupRepo(t)
	root, err := filepath.EvalSymlinks(filepath.Dir(repo))
	if err != nil {
		t.Fatal(err)
	}
	for _, command := range []string{"git branch -d plain", "git switch touch-claude"} {
		in := toolInput{Command: command}
		got := evaluate(in, options{agent: "claude", cwd: repo, home: home, git: runGit, managedDir: t.TempDir(), writableGitRoots: []string{root + "/"}})
		if got.rule != "" {
			t.Errorf("一時ディレクトリのリポジトリは sandbox から書けるので %q を止めない: rule = %q", command, got.rule)
		}
	}
}
