package main

import (
	"fmt"
	"regexp"
	"slices"
	"strings"
)

// toolInput は Bash ツールの入力。sandbox の指定は公式ドキュメントに無いが、hook には届く（2026-11 に実機で確認）。
type toolInput struct {
	Command        string   `json:"command"`
	Unsandboxed    bool     `json:"dangerouslyDisableSandbox"`
	AllowedDomains []string `json:"allowed_domains"`
}

type options struct {
	agent            string
	cwd              string
	home             string
	git              func(dir string, args ...string) (string, error)
	writableGitRoots []string // この下のリポジトリは sandbox から .git/config に書ける
	managedDir       string
	sandbox          sandboxSettings
}

// sandboxed は、このコマンドが sandbox 内で動くかどうか。
func sandboxed(in toolInput, o options) bool {
	return !in.Unsandboxed && !o.sandbox.disabled
}

type verdict struct {
	rule   string
	reason string
}

type rule struct {
	id     string
	agents []string
	check  func(s *script, in toolInput, o options) string
}

var rules = []rule{
	{"op", []string{"claude", "codex"}, checkOp},
	{"inline-interpreter", []string{"claude", "codex"}, checkInlineInterpreter},
	{"rg-replace-flag", []string{"claude", "codex"}, checkRgReplaceFlag},
	{"excluded-compound", []string{"claude"}, checkExcludedCompound},
	{"excluded-tmpdir", []string{"claude"}, checkExcludedTmpdir},
	{"process-substitution", []string{"claude"}, checkProcessSubstitution},
	{"mktemp-default-dir", []string{"claude"}, checkMktemp},
	{"aws-unsandboxed", []string{"claude"}, checkAwsUnsandboxed},
	{"go-install-gobin", []string{"claude"}, checkGoInstall},
	{"git-config-write", []string{"claude"}, checkGitConfigWrite},
	{"git-protected-tree", []string{"claude"}, checkGitProtectedTree},
}

func evaluate(in toolInput, o options) verdict {
	s := parse(in.Command)
	if o.agent == "claude" {
		o.sandbox = loadSandboxSettings(o)
	}
	for _, r := range rules {
		if !slices.Contains(r.agents, o.agent) {
			continue
		}
		if reason := r.check(s, in, o); reason != "" {
			return verdict{rule: r.id, reason: "[agent-bash-guard: " + r.id + "] " + reason}
		}
	}
	return verdict{}
}

func checkOp(s *script, _ toolInput, _ options) string {
	for _, c := range s.cmds {
		if name, _ := c.program(); name == "op" {
			return "1Password CLI（op）は組織の指示で使いません。秘密情報が要るときは、利用者に自分のターミナルで op を実行してもらうよう案内し、値をチャットに貼らせないでください。"
		}
	}
	return ""
}

var pythonRe = regexp.MustCompile(`^python[0-9.]*$`)

const inlineInterpreterReason = "新しく書くコードに Python・Node・Ruby・Perl は使いません（インラインのコードも新しく書くコードです）。" +
	"jq・rg・CLI のパイプで済むならシェルで書き、JSON の加工や分岐が要るなら、標準ライブラリだけの .go を scratchpad（無ければ $TMPDIR）に書いて go run で動かしてください。" +
	"ファイルとして置かれた既存スクリプトの実行（python3 scripts/x.py、uv run など）はかまいません。" +
	"利用者やスキルが言語を指定しているときは、コードをファイルに書いてから実行してください。"

func checkInlineInterpreter(s *script, _ toolInput, _ options) string {
	if slices.ContainsFunc(s.cmds, inlineCode) {
		return inlineInterpreterReason
	}
	return ""
}

// flagKind は、インタプリタのオプション 1 語が何を意味するか。
type flagKind int

const (
	flagPlain     flagKind = iota
	flagCode               // 次の語か残りの文字がプログラム本体
	flagModule             // python -m: 既存のモジュールを動かす
	flagValueNext          // 次の語がこのオプションの値
)

// interpreterFlag は、1 語のオプションを 1 文字ずつ読んで種類を決める。
// codeLetters はプログラム本体を取る文字、restLetters は残りの文字を値として取る文字（nextLetters は末尾なら次の語を取る）。
func interpreterFlag(a, codeLetters, restLetters, nextLetters string) flagKind {
	runes := []rune(a[1:])
	for i, r := range runes {
		switch {
		case strings.ContainsRune(codeLetters, r):
			return flagCode
		case strings.ContainsRune(restLetters, r):
			if i == len(runes)-1 && strings.ContainsRune(nextLetters, r) {
				return flagValueNext
			}
			return flagPlain
		case r >= '0' && r <= '9':
		case !isIdentStart(r):
			return flagPlain
		}
	}
	return flagPlain
}

func classifyFlag(lang, a string) flagKind {
	if strings.HasPrefix(a, "--") {
		switch {
		case lang == "node" && (slices.Contains([]string{"--eval", "--print"}, a) || strings.HasPrefix(a, "--eval=") || strings.HasPrefix(a, "--print=")):
			return flagCode
		case lang == "node" && slices.Contains([]string{"--require", "--import", "--loader", "--conditions"}, a):
			return flagValueNext
		}
		return flagPlain
	}
	switch lang {
	case "python":
		if strings.HasPrefix(a, "-m") {
			return flagModule
		}
		return interpreterFlag(a, "c", "WXm", "WX")
	case "node":
		return interpreterFlag(a, "ep", "rC", "rC")
	case "ruby":
		return interpreterFlag(a, "e", "IrCEFKTWx0", "IrCEF")
	case "perl":
		return interpreterFlag(a, "eE", "IMmixCdD", "I")
	}
	return flagPlain
}

// inlineCode は、ファイルではなくコマンド行や標準入力でプログラムを渡しているかどうか。
func inlineCode(c *simpleCmd) bool {
	name, args := c.program()
	lang := ""
	switch {
	case pythonRe.MatchString(name):
		lang = "python"
	case name == "node" || name == "nodejs":
		lang = "node"
	case name == "ruby" || name == "perl":
		lang = name
	default:
		return false
	}
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "-":
			return true
		case a == "--":
			return i+1 >= len(args) && c.stdinFed()
		case !strings.HasPrefix(a, "-"):
			return false
		}
		switch classifyFlag(lang, a) {
		case flagCode:
			return true
		case flagModule:
			return false
		case flagValueNext:
			i++
		}
	}
	onlyInfoFlags := len(args) > 0 && !slices.ContainsFunc(args, func(a string) bool {
		return !slices.Contains([]string{"--version", "-V", "-v", "--help", "-h"}, a)
	})
	return !onlyInfoFlags && c.stdinFed()
}

func isShortCluster(a string) bool {
	if len(a) < 2 || a[0] != '-' || a[1] == '-' {
		return false
	}
	for _, r := range a[1:] {
		if !isIdentStart(r) || r == '_' {
			return false
		}
	}
	return true
}

// rgValueLetters は、rg の短いオプションのうち値を取るもの。クラスタの中でこれより後ろの文字は値になる。
const rgValueLetters = "efgtTABCmMjEdr"

func checkRgReplaceFlag(s *script, _ toolInput, _ options) string {
	for _, c := range s.cmds {
		name, args := c.program()
		if name != "rg" {
			continue
		}
		for i := 0; i < len(args); i++ {
			a := args[i]
			if a == "--" {
				break
			}
			if !isShortCluster(a) {
				continue
			}
			letters := a[1:]
			for j, r := range letters {
				if !strings.ContainsRune(rgValueLetters, r) {
					continue
				}
				// -or '$1' のように r が末尾なら、次の語が置換文字列になる正しい書き方なので止めない。
				if r == 'r' && j < len(letters)-1 {
					return fmt.Sprintf("rg の -r は再帰ではなく --replace（置換）です。rg は既定で再帰検索するので、%s ではなく r を除いた形（-n・-l・-i など）にしてください。", a)
				}
				if j == len(letters)-1 {
					i++
				}
				break
			}
		}
	}
	return ""
}

// excludedCommand は settings.json の sandbox.excludedCommands に載せたコマンドかどうか。
// 一致すれば、表示名と、一致を崩す書き方（git -C など）をしているかを返す。
func excludedCommand(c *simpleCmd) (label string, breaker string) {
	name, args, _ := c.command()
	base := c.baseName()
	if name != base {
		breaker = "絶対パスや相対パスでの呼び出し"
	}
	if prog, progArgs := c.program(); prog != base && prog != "" {
		base, args = prog, progArgs
		breaker = "xargs・sudo などの起動役の内側"
	}
	switch base {
	case "gh", "skill-cross-review", "skill-review-state", "skill-aws-reach":
		return base, breaker
	case "git":
		sub, global := gitSubcommand(args)
		if sub != "commit" && sub != "push" && sub != "fetch" {
			return "", ""
		}
		if global {
			breaker = "git -C などのサブコマンドより前のオプション"
		}
		return "git " + sub, breaker
	}
	return "", ""
}

// gitSubcommand はサブコマンド名と、その前にオプションがあったかを返す。
func gitSubcommand(args []string) (sub string, hadGlobal bool) {
	for i := 0; i < len(args); i++ {
		a := args[i]
		if !strings.HasPrefix(a, "-") {
			return a, hadGlobal
		}
		hadGlobal = true
		if a == "-C" || a == "-c" || a == "--git-dir" || a == "--work-tree" || a == "--namespace" {
			i++
		}
	}
	return "", hadGlobal
}

// ownBreakers は、そのコマンド自身の書き方のうち、excludedCommands への一致を崩すものを挙げる。
func ownBreakers(c *simpleCmd, breaker string) []string {
	var why []string
	if breaker != "" {
		why = append(why, breaker)
	}
	if c.depth > 0 {
		why = append(why, "$(...)・bash -c などの内側")
	}
	if _, _, env := c.command(); env {
		why = append(why, "環境変数の前置")
	}
	for _, r := range c.redirects {
		if !r.dupsFD() {
			why = append(why, "2>&1 以外のリダイレクト（"+r.op+r.target+"。/dev/null も含む）")
			break
		}
	}
	return why
}

// exclusionBreakers は、excludedCommands への一致を崩して sandbox 内で動かしてしまう書き方を挙げる。
// 除外コマンドどうしを &&・;・|| でつないだだけなら、全体が sandbox の外で動く（2026-11 に実機で確認）。
func exclusionBreakers(s *script, c *simpleCmd, breaker string) []string {
	why := ownBreakers(c, breaker)
	if s.cmdSubst || s.procSubst {
		why = append(why, "$(...) や <(...)")
	}
	if s.background {
		why = append(why, "& によるバックグラウンド実行")
	}
	for _, other := range s.cmds {
		if other == c || other.depth > 0 {
			continue
		}
		label, b := excludedCommand(other)
		if label == "" || len(ownBreakers(other, b)) > 0 {
			why = append(why, "パイプ・&&・;・ループなどでの除外コマンド以外との組み合わせ")
			break
		}
	}
	return why
}

func checkExcludedCompound(s *script, in toolInput, o options) string {
	if o.sandbox.disabled {
		return ""
	}
	for _, c := range s.cmds {
		label, breaker := excludedCommand(c)
		if label == "" {
			continue
		}
		if in.Unsandboxed {
			if label != "gh" {
				continue
			}
			return "gh を dangerouslyDisableSandbox で動かすと auto mode に Safety Bypass として拒否されます（単独の gh は sandbox.excludedCommands で、もともと sandbox の外で動きます）。dangerouslyDisableSandbox を外してください。" + excludedFix(label)
		}
		why := exclusionBreakers(s, c, breaker)
		if len(why) == 0 {
			continue
		}
		blocker := sandboxBlocker(label, s, c, in, o)
		if blocker == "" {
			continue
		}
		return fmt.Sprintf("%s は単独のコマンドのときだけ sandbox の外で動きます（sandbox.excludedCommands）。このコマンドは %s を含むので sandbox 内で動き、%s。%s",
			label, strings.Join(why, "・"), blocker, excludedFix(label))
	}
	return ""
}

// sandboxBlocker は、除外に一致しないまま sandbox 内で動いたときに失敗する理由を返す。成功するなら空を返す。
// 判定に要る情報が取れないときも、止めすぎないよう空を返す。
func sandboxBlocker(label string, s *script, c *simpleCmd, in toolInput, o options) string {
	domains := append(append([]string{}, in.AllowedDomains...), o.sandbox.domains...)
	switch label {
	case "gh":
		switch ghNetwork(c) {
		case ghOffline:
			return ""
		case ghOtherHosts:
			return "ログや成果物は api.github.com 以外のホストから取るので失敗します"
		}
		if hostAllowed("api.github.com", "443", domains) {
			return ""
		}
		return "この sandbox の通信許可に api.github.com が無いので失敗します"
	case "skill-review-state":
		if hostAllowed("api.github.com", "443", domains) {
			return ""
		}
		return "この sandbox の通信許可に api.github.com が無いので失敗します"
	case "git push", "git fetch":
		dir := cmdDir(s, c, o)
		if dir == "" {
			return ""
		}
		host, port := pushFetchHost(dir, c, o)
		if host == "" || hostAllowed(host, port, domains) {
			return ""
		}
		return "この sandbox の通信許可に " + host + ":" + port + " が無いので失敗します"
	case "git commit":
		dir := cmdDir(s, c, o)
		if dir == "" || signingDisabled(c) {
			return ""
		}
		if v, _ := o.git(dir, "config", "--get", "commit.gpgsign"); v != "true" {
			return ""
		}
		return "コミット署名のエージェントのソケットに sandbox からつながらず失敗します"
	}
	return "sandbox 内では必要な通信やコマンドが拒否されて失敗します"
}

type ghNeed int

const (
	ghAPI        ghNeed = iota // api.github.com に届けば動く
	ghOffline                  // 通信しない（--help・completion など）
	ghOtherHosts               // ログや成果物を別ホストから取る
)

func ghNetwork(c *simpleCmd) ghNeed {
	_, args := c.program()
	if slices.ContainsFunc(args, func(a string) bool { return a == "--help" || a == "-h" || a == "--version" }) {
		return ghOffline
	}
	pos := positionals(args, nil)
	if len(pos) == 0 {
		return ghOffline
	}
	switch {
	case slices.Contains([]string{"help", "version", "completion"}, pos[0]):
		return ghOffline
	case pos[0] == "config" && len(pos) > 1 && (pos[1] == "get" || pos[1] == "list"):
		return ghOffline
	case pos[0] == "run" && len(pos) > 1 && pos[1] == "download",
		pos[0] == "release" && len(pos) > 1 && pos[1] == "download",
		pos[0] == "run" && slices.ContainsFunc(args, func(a string) bool { return strings.HasPrefix(a, "--log") }):
		return ghOtherHosts
	}
	return ghAPI
}

// signingDisabled は、git -c commit.gpgsign=false や --no-gpg-sign で署名を切ったコミットかどうか。
func signingDisabled(c *simpleCmd) bool {
	_, args := c.program()
	for i, a := range args {
		if a == "--no-gpg-sign" || (a == "-c" && i+1 < len(args) && strings.EqualFold(args[i+1], "commit.gpgsign=false")) {
			return true
		}
	}
	return false
}

// cmdDir は、直前の cd と -C を反映して、そのコマンドが動くディレクトリを返す。分からなければ空を返す。
func cmdDir(s *script, target *simpleCmd, o options) string {
	dir := o.cwd
	for _, c := range s.cmds {
		if c == target {
			break
		}
		if name, args, _ := c.command(); c.depth == 0 && name == "cd" {
			if len(args) == 1 {
				dir = resolveDir(dir, args[0], o.home)
			} else {
				dir = ""
			}
		}
	}
	_, args, _ := target.command()
	for i := 0; i < len(args) && strings.HasPrefix(args[i], "-"); i++ {
		switch args[i] {
		case "-C":
			if i+1 < len(args) {
				dir = resolveDir(dir, args[i+1], o.home)
			} else {
				dir = ""
			}
			i++
		case "-c", "--git-dir", "--work-tree", "--namespace":
			i++
		}
	}
	return dir
}

// pushFetchHost は git push / fetch の接続先を、引数のリモート名か URL、無ければ upstream のリモートから求める。
func pushFetchHost(dir string, c *simpleCmd, o options) (host, port string) {
	_, args, _ := c.command()
	rest := args
	for i, a := range args {
		if a == "push" || a == "fetch" {
			rest = args[i+1:]
			break
		}
	}
	pos := positionals(rest, map[string]bool{"-o": true, "--push-option": true, "--depth": true, "--repo": true, "-j": true, "--jobs": true})
	remote := ""
	if len(pos) > 0 {
		remote = pos[0]
	} else if up, err := o.git(dir, "rev-parse", "--abbrev-ref", "@{u}"); err == nil {
		remote, _, _ = strings.Cut(up, "/")
	} else {
		remote = "origin"
	}
	if strings.ContainsAny(remote, ":/") {
		return remoteHost(remote)
	}
	u, err := o.git(dir, "remote", "get-url", remote)
	if err != nil {
		return "", ""
	}
	return remoteHost(u)
}

func excludedFix(label string) string {
	common := "1 件ずつ別の Bash 呼び出しにしてください（2>&1 と \\ の行継続はそのままでかまいません）。cd や git -C は使わず、cwd のまま実行します。"
	switch {
	case label == "gh":
		return common + "絞り込みは gh 自身の --jq・-q・--limit で行い、別リポジトリは --repo で指定します。パイプがどうしても要るときは、Bash の allowed_domains に api.github.com を宣言して sandbox 内で実行してください。gh run view --log・gh run download・gh release download は別ホストから取るので、必ず単独で実行し、絞り込みは長い出力が保存されたファイルに別の呼び出しで rg をかけます。dangerouslyDisableSandbox では再試行しません。"
	case label == "git commit":
		return common + "git add は別の呼び出しに分け、メッセージは sandbox 内で書いたファイルを -F <展開済みの絶対パス> で渡します（$(...) や環境変数の前置で author や日付を渡さず、--author・--date を使います）。"
	case strings.HasPrefix(label, "git "):
		return common + "結果の絞り込みが要るなら、出力を受け取ってから別の呼び出しで行います。"
	default:
		return common + "JSON の絞り込みは、出力を受け取ってから別の呼び出しで jq にかけます。"
	}
}

func checkExcludedTmpdir(s *script, in toolInput, o options) string {
	if o.sandbox.disabled {
		return ""
	}
	for _, c := range s.cmds {
		label, breaker := excludedCommand(c)
		if label == "" || !c.hasVar("TMPDIR") {
			continue
		}
		if !in.Unsandboxed && len(exclusionBreakers(s, c, breaker)) > 0 {
			continue
		}
		return label + " は sandbox の外で動き、外では $TMPDIR が別の場所（/var/folders/...）を指します。sandbox 内で作ったファイルを渡すときは、sandbox 内で echo \"$TMPDIR\" して得た絶対パスをリテラルで書いてください。gh pr edit --body-file のように本文を丸ごと置き換える操作は、成功が返っても中身が違うことがあるので、先に旧本文を保存し、実行後に読み戻して照合します。"
	}
	return ""
}

func checkProcessSubstitution(s *script, in toolInput, o options) string {
	if !s.procSubst || !sandboxed(in, o) {
		return ""
	}
	return "sandbox 内のプロセス置換 <(...) は、/dev/fd を許可しても Operation not permitted で失敗します（設定では直りません）。中間結果を $TMPDIR のファイルに書いてから渡してください。"
}

func checkMktemp(s *script, in toolInput, o options) string {
	if !sandboxed(in, o) {
		return ""
	}
	for _, c := range s.cmds {
		if c.baseName() != "mktemp" {
			continue
		}
		_, args, _ := c.command()
		hasTemplate, usesT, dryRun := false, false, false
		for i := 0; i < len(args); i++ {
			a := args[i]
			switch {
			case isShortCluster(a) && strings.Contains(a, "u"):
				dryRun = true
			case a == "-p" || a == "--tmpdir" || strings.HasPrefix(a, "--tmpdir="):
				hasTemplate = true
				if a == "-p" {
					i++
				}
			case isShortCluster(a) && strings.Contains(a, "t"):
				usesT = true
				i++
			case strings.HasPrefix(a, "-"):
			default:
				hasTemplate = true
			}
		}
		if !dryRun && (usesT || !hasTemplate) {
			return "macOS の mktemp は、テンプレートを渡さないときと -t のとき、TMPDIR を使わず /var/folders に作るので sandbox から書けません。mktemp -d \"${TMPDIR:-/tmp}/<名前>.XXXXXX\" の形で書いてください。"
		}
	}
	return ""
}

func checkAwsUnsandboxed(s *script, in toolInput, _ options) string {
	if !in.Unsandboxed {
		return ""
	}
	for _, c := range s.cmds {
		if name, _ := c.program(); name == "aws" {
			return "aws を dangerouslyDisableSandbox で動かしません。分類器に拒否されると、しばらく読み取りの Bash まで止まります（sandbox 内では SSO キャッシュに書けず、ECS などの API はプロキシで拒否されます。rds-data と logs は sandbox 内でも通ります）。" +
				"読み取りは、describe・list・Logs Insights だけのスクリプトを scratchpad に書き、中身の要約を添えて利用者に ! で実行してもらいます。本番への書き込みは、復唱と事前チェックまでを行い、コマンドそのものを渡します。"
		}
	}
	return ""
}

func checkGoInstall(s *script, in toolInput, o options) string {
	if !sandboxed(in, o) {
		return ""
	}
	gobinSet := false
	for _, c := range s.cmds {
		for _, a := range c.assigns {
			gobinSet = gobinSet || strings.HasPrefix(a, "GOBIN=")
		}
		if name, args, _ := c.command(); name == "export" || name == "env" {
			for _, a := range args {
				gobinSet = gobinSet || strings.HasPrefix(a, "GOBIN=")
			}
		}
	}
	for _, c := range s.cmds {
		if name, args, _ := c.command(); name == "go" && len(args) > 0 && args[0] == "install" && !gobinSet {
			return "sandbox からは ~/go/bin に書けません（PATH で /usr/bin より前にあり、置いたものが sandbox の外で ssh などの代わりに動くので外しています）。GOBIN=\"$TMPDIR/bin\" go install ... のように一時ディレクトリへ向けてください。"
		}
	}
	return ""
}
