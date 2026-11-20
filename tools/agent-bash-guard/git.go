package main

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
)

// gitCall は最上位の git 呼び出し 1 つと、それが動くディレクトリ。
type gitCall struct {
	dir  string // 分からないときは空
	sub  string
	args []string
}

// gitCalls は、直前の cd と -C を反映したディレクトリ付きで git 呼び出しを返す。
func gitCalls(s *script, o options) []gitCall {
	dir := o.cwd
	var calls []gitCall
	for _, c := range s.cmds {
		if c.depth > 0 {
			continue
		}
		name, args, _ := c.command()
		if name == "cd" {
			if len(args) == 1 {
				dir = resolveDir(dir, args[0], o.home)
			} else {
				dir = ""
			}
			continue
		}
		if c.baseName() != "git" {
			continue
		}
		d := dir
		i := 0
		for ; i < len(args) && strings.HasPrefix(args[i], "-"); i++ {
			switch args[i] {
			case "-C":
				if i+1 < len(args) {
					d = resolveDir(d, args[i+1], o.home)
				} else {
					d = ""
				}
				i++
			case "-c", "--git-dir", "--work-tree", "--namespace":
				i++
			}
		}
		if i < len(args) {
			calls = append(calls, gitCall{dir: d, sub: args[i], args: args[i+1:]})
		}
	}
	return calls
}

// resolveDir は cd や -C の引数を絶対パスにする。~ と $HOME 以外の展開を含むときは分からないので空を返す。
func resolveDir(base, p, home string) string {
	for _, prefix := range []string{"~", "$HOME", "${HOME}"} {
		if p == prefix || strings.HasPrefix(p, prefix+"/") {
			p = filepath.Join(home, strings.TrimPrefix(p, prefix))
			break
		}
	}
	if strings.ContainsAny(p, "$`") {
		return ""
	}
	if filepath.IsAbs(p) {
		return filepath.Clean(p)
	}
	if base == "" {
		return ""
	}
	return filepath.Join(base, p)
}

// positionals はオプションとその値を除いた引数を返す。
func positionals(args []string, valueFlags map[string]bool) []string {
	var pos []string
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "--":
			return append(pos, args[i+1:]...)
		case valueFlags[a]:
			i++
		case strings.HasPrefix(a, "-"):
		default:
			pos = append(pos, a)
		}
	}
	return pos
}

type switchSpec struct {
	create   bool
	track    bool
	noTrack  bool
	target   string   // 切り替え先。create のときは起点で、空なら HEAD
	pathMode bool     // checkout -- <paths> のようにファイルだけを戻す
	paths    []string // pathMode のときの対象
}

func parseSwitch(g gitCall, o options) switchSpec {
	var sp switchSpec
	var pos []string
	for i := 0; i < len(g.args); i++ {
		a := g.args[i]
		switch {
		case a == "--":
			sp.pathMode = true
			sp.paths = append(sp.paths, g.args[i+1:]...)
			i = len(g.args)
		case slices.Contains([]string{"-c", "-C", "--create", "--force-create", "-b", "-B", "--orphan"}, a):
			sp.create = true
			i++
		case a == "-t" || a == "--track" || strings.HasPrefix(a, "--track="):
			sp.track = true
		case a == "--no-track":
			sp.noTrack = true
		case strings.HasPrefix(a, "-"):
		default:
			pos = append(pos, a)
		}
	}
	if len(pos) > 0 {
		sp.target = pos[0]
	}
	if sp.target == "-" {
		sp.target = "@{-1}"
	}
	if g.sub == "checkout" && !sp.create && !sp.pathMode && sp.target != "" {
		if !gitOK(o, g.dir, "rev-parse", "--verify", "--quiet", sp.target+"^{commit}") && remoteBranchFor(g, o, sp.target) == "" {
			sp.pathMode, sp.paths, sp.target = true, pos, ""
		} else if len(pos) > 1 {
			sp.pathMode, sp.paths = true, pos[1:]
		}
	}
	return sp
}

func gitOK(o options, dir string, args ...string) bool {
	_, err := o.git(dir, args...)
	return err == nil
}

// remoteBranchFor は、ローカルに無くリモートにだけある名前なら、そのリモート追跡ブランチを返す。
// git switch / checkout はこの場合に追跡ブランチを作り、.git/config に書く。
func remoteBranchFor(g gitCall, o options, name string) string {
	if strings.HasPrefix(name, "@") || gitOK(o, g.dir, "show-ref", "--verify", "--quiet", "refs/heads/"+name) {
		return ""
	}
	out, err := o.git(g.dir, "for-each-ref", "--format=%(refname:short)", "refs/remotes/*/"+name)
	if err != nil || out == "" {
		return ""
	}
	return strings.SplitN(out, "\n", 2)[0]
}

func isRemoteRef(g gitCall, o options, ref string) bool {
	out, err := o.git(g.dir, "remote")
	if err != nil {
		return false
	}
	for r := range strings.SplitSeq(out, "\n") {
		if r != "" && strings.HasPrefix(ref, r+"/") {
			return true
		}
	}
	return false
}

// defaultWritableGitRoots は、sandbox から .git/config に書けるリポジトリの置き場。
// 守られるのは作業中のリポジトリだけで、一時ディレクトリに clone したものは書ける（2026-11 に実機で確認）。
func defaultWritableGitRoots() []string {
	return []string{"/tmp/", "/private/tmp/", "/var/folders/", "/private/var/folders/", filepath.Clean(os.TempDir()) + "/"}
}

func under(path string, roots []string) bool {
	for _, r := range roots {
		if strings.HasPrefix(path+"/", r) {
			return true
		}
	}
	return false
}

func configWriteOp(g gitCall, o options) string {
	switch g.sub {
	case "branch":
		for _, a := range g.args {
			if slices.Contains([]string{"-u", "--unset-upstream", "--edit-description", "-t", "--track"}, a) || strings.HasPrefix(a, "--set-upstream-to") {
				return "git branch " + a
			}
		}
		// 削除・改名・複製は branch.<名前> の節があるときだけ .git/config を書き換える。
		for _, a := range g.args {
			if !slices.Contains([]string{"-d", "-D", "--delete", "-m", "-M", "--move", "-c", "-C", "--copy"}, a) {
				continue
			}
			names := positionals(g.args, nil)
			if len(names) <= 1 && a != "-d" && a != "-D" && a != "--delete" {
				if cur, err := o.git(g.dir, "rev-parse", "--abbrev-ref", "HEAD"); err == nil {
					names = append(names, cur)
				}
			}
			for _, n := range names {
				if gitOK(o, g.dir, "config", "--get-regexp", `^branch\.`+regexp.QuoteMeta(n)+`\.`) {
					return fmt.Sprintf("git branch %s（branch.%s の設定を書き換える）", a, n)
				}
			}
			return ""
		}
		if pos := positionals(g.args, nil); len(pos) == 2 && !slices.Contains(g.args, "--no-track") && isRemoteRef(g, o, pos[1]) {
			return "リモート追跡ブランチを起点にした git branch"
		}
	case "switch", "checkout":
		sp := parseSwitch(g, o)
		if sp.noTrack {
			return ""
		}
		if sp.create && (sp.track || (sp.target != "" && isRemoteRef(g, o, sp.target))) {
			return "リモート追跡ブランチを起点にした git " + g.sub + "（追跡設定を書く）"
		}
		if !sp.create && !sp.pathMode && sp.target != "" {
			if r := remoteBranchFor(g, o, sp.target); r != "" {
				return fmt.Sprintf("リモートにだけある %s への git %s（%s を追跡するブランチを作る）", sp.target, g.sub, r)
			}
		}
	case "remote":
		if len(g.args) > 0 && slices.Contains([]string{"add", "remove", "rm", "rename", "set-url", "set-branches"}, g.args[0]) {
			return "git remote " + g.args[0]
		}
	case "config":
		for _, a := range g.args {
			if slices.Contains([]string{"--global", "--system", "--file", "-f", "--get", "--get-all", "--get-regexp", "--list", "-l", "get", "list"}, a) {
				return ""
			}
		}
		valueFlags := map[string]bool{"--type": true, "--default": true, "--blob": true, "--comment": true, "--value": true}
		if len(positionals(g.args, valueFlags)) >= 2 || slices.ContainsFunc(g.args, func(a string) bool {
			return strings.HasPrefix(a, "--unset") || slices.Contains([]string{"--add", "--replace-all", "--remove-section", "--rename-section", "set", "unset"}, a)
		}) {
			return "git config での書き込み"
		}
	}
	return ""
}

func checkGitConfigWrite(s *script, in toolInput, o options) string {
	if !sandboxed(in, o) {
		return ""
	}
	for _, g := range gitCalls(s, o) {
		if g.dir == "" {
			continue
		}
		top, err := o.git(g.dir, "rev-parse", "--show-toplevel")
		if err != nil || under(top, o.writableGitRoots) {
			continue
		}
		if op := configWriteOp(g, o); op != "" {
			return op + " は .git/config に書きますが、sandbox からは作業中のリポジトリの .git/config に書けず、途中で失敗します（git branch -d は exit 128 でも ref だけ消え、branch.<名前>.* の設定が残ります）。" +
				"最初から dangerouslyDisableSandbox: true で実行してください。auto mode に拒否されたら、コマンドを示して利用者に ! で実行してもらいます。設定だけ残ったときは、sandbox 外で git config --remove-section branch.<名前> で消します。"
		}
	}
	return ""
}

// protectedRe は、作業中のリポジトリの直下で sandbox が守るパス。入れ子の .claude/ や別のリポジトリは守られない。
var protectedRe = regexp.MustCompile(`^(\.claude/|\.mcp\.json$)`)

// protectedFiles は、sandbox から書けないファイルを返す。project は、top が作業中のリポジトリかどうか。
// ~/.claude 配下で守られるのは settings と CLAUDE.md のリンク先だけで、rules や skills のリンク先は書ける（2026-11 に実機で確認）。
func protectedFiles(top string, files []string, home string, project bool) []string {
	var guarded []string
	for _, name := range []string{"settings.json", "settings.local.json", "CLAUDE.md"} {
		if real, err := filepath.EvalSymlinks(filepath.Join(home, ".claude", name)); err == nil {
			guarded = append(guarded, real)
		}
	}
	if real, err := filepath.EvalSymlinks(top); err == nil {
		top = real
	}
	var hits []string
	for _, f := range files {
		if f == "" {
			continue
		}
		if (project && protectedRe.MatchString(f)) || slices.Contains(guarded, filepath.Join(top, f)) {
			hits = append(hits, f)
		}
	}
	return hits
}

// touchedFiles は、その git 操作が作業ツリーで書き換えるファイルを返す。
func touchedFiles(g gitCall, o options) []string {
	lines := func(args ...string) []string {
		out, err := o.git(g.dir, args...)
		if err != nil || out == "" {
			return nil
		}
		return strings.Split(out, "\n")
	}
	diff := func(args ...string) []string {
		return lines(append([]string{"diff", "--name-only"}, args...)...)
	}
	// mergeInto は target を取り込むときに書き換わるファイル。HEAD 側だけの変更は書き換わらない。
	mergeInto := func(target string) []string {
		base, err := o.git(g.dir, "merge-base", "HEAD", target)
		if err != nil {
			return nil
		}
		return diff(base, target, "--")
	}
	inProgress := slices.ContainsFunc(g.args, func(a string) bool {
		return slices.Contains([]string{"--abort", "--continue", "--quit", "--skip", "--edit-todo"}, a)
	})
	switch g.sub {
	case "reset":
		if !slices.ContainsFunc(g.args, func(a string) bool { return a == "--hard" || a == "--merge" || a == "--keep" }) {
			return nil
		}
		target := "HEAD"
		if pos := positionals(g.args, nil); len(pos) > 0 {
			target = pos[0]
		}
		return append(diff("HEAD"), diff("HEAD", target, "--")...)
	case "rebase":
		if inProgress {
			return nil
		}
		target := "@{u}"
		for i, a := range g.args {
			if a == "--onto" && i+1 < len(g.args) {
				target = g.args[i+1]
			}
		}
		if pos := positionals(g.args, map[string]bool{"--onto": true, "-s": true, "--strategy": true, "-X": true, "--strategy-option": true, "-x": true, "--exec": true}); target == "@{u}" && len(pos) > 0 {
			target = pos[0]
		}
		return diff("HEAD", target, "--")
	case "restore":
		worktree := !slices.Contains(g.args, "--staged") && !slices.Contains(g.args, "-S") || slices.Contains(g.args, "--worktree") || slices.Contains(g.args, "-W")
		if !worktree {
			return nil
		}
		source := ""
		for i, a := range g.args {
			switch {
			case (a == "-s" || a == "--source") && i+1 < len(g.args):
				source = g.args[i+1]
			case strings.HasPrefix(a, "--source="):
				source = strings.TrimPrefix(a, "--source=")
			}
		}
		paths := positionals(g.args, map[string]bool{"-s": true, "--source": true})
		if source != "" {
			return diff(append([]string{source, "--"}, paths...)...)
		}
		return diff(append([]string{"--"}, paths...)...)
	case "stash":
		if len(g.args) == 0 || (g.args[0] != "pop" && g.args[0] != "apply") {
			return nil
		}
		ref := "stash@{0}"
		if pos := positionals(g.args[1:], nil); len(pos) > 0 {
			ref = pos[0]
		}
		return lines("stash", "show", "--name-only", ref)
	case "cherry-pick", "revert":
		if inProgress {
			return nil
		}
		var files []string
		for _, rev := range positionals(g.args, map[string]bool{"-m": true, "--mainline": true, "-s": true, "--strategy": true, "-X": true, "--strategy-option": true}) {
			if from, to, isRange := strings.Cut(rev, ".."); isRange {
				files = append(files, diff(from, strings.TrimPrefix(to, "."), "--")...)
				continue
			}
			files = append(files, lines("diff-tree", "--no-commit-id", "--name-only", "-r", rev)...)
		}
		return files
	case "switch", "checkout":
		sp := parseSwitch(g, o)
		if sp.pathMode {
			if sp.target != "" {
				return diff(append([]string{sp.target, "--"}, sp.paths...)...)
			}
			return diff(append([]string{"--"}, sp.paths...)...)
		}
		if sp.target == "" {
			return nil
		}
		if r := remoteBranchFor(g, o, sp.target); r != "" && !sp.create {
			return diff("HEAD", r, "--")
		}
		return diff("HEAD", sp.target, "--")
	case "pull":
		pos := positionals(g.args, map[string]bool{"-s": true, "--strategy": true, "-X": true, "--strategy-option": true, "--depth": true})
		target := "@{u}"
		if len(pos) >= 2 {
			target = pos[0] + "/" + pos[1]
		}
		if slices.ContainsFunc(g.args, func(a string) bool { return a == "-r" || strings.HasPrefix(a, "--rebase") && a != "--rebase=false" }) {
			return diff("HEAD", target, "--")
		}
		return mergeInto(target)
	case "merge":
		if inProgress {
			return nil
		}
		pos := positionals(g.args, map[string]bool{"-m": true, "-s": true, "-X": true, "-F": true, "--strategy": true, "--strategy-option": true, "--file": true})
		if len(pos) == 0 {
			return nil
		}
		return mergeInto(pos[0])
	}
	return nil
}

func checkGitProtectedTree(s *script, in toolInput, o options) string {
	if !sandboxed(in, o) {
		return ""
	}
	projectTop := ""
	if o.cwd != "" {
		projectTop, _ = o.git(o.cwd, "rev-parse", "--show-toplevel")
	}
	for _, g := range gitCalls(s, o) {
		if g.dir == "" {
			continue
		}
		top, err := o.git(g.dir, "rev-parse", "--show-toplevel")
		if err != nil || under(top, o.writableGitRoots) {
			continue
		}
		files := touchedFiles(g, o)
		if len(files) == 0 {
			continue
		}
		// cwd がリポジトリでないときは作業中のリポジトリを特定できないので、守られている側に倒す。
		hits := protectedFiles(top, slices.Compact(slices.Sorted(slices.Values(files))), o.home, projectTop == "" || top == projectTop)
		if len(hits) == 0 {
			continue
		}
		if len(hits) > 3 {
			hits = append(hits[:3], "ほか")
		}
		return fmt.Sprintf("git %s が書き換えるファイルに、sandbox から書けないパス（%s）が含まれます。sandbox 内では、そのファイルだけ更新できずに途中で止まり、HEAD・index・作業ツリーが食い違います（exit 0 で終わることもあります）。"+
			"最初から dangerouslyDisableSandbox: true で実行してください。auto mode に拒否されたら、コマンドを示して利用者に ! で実行してもらいます。", g.sub, strings.Join(hits, "、"))
	}
	return ""
}
