package main

import (
	"fmt"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
)

// simpleCmd は、パイプ・&&・; などで区切られた 1 つのコマンド。
type simpleCmd struct {
	assigns   []string // コマンド名より前の VAR=value
	words     []string // 引用符を外した語。展開は $NAME や $(...) の形で残す
	vars      []string // 単一引用符の外で参照した変数名
	redirects []redirect
	depth     int  // $(...)・<(...)・バッククォート・bash -c の中なら 1 以上
	piped     bool // 標準入力が直前のコマンドからのパイプ
}

type redirect struct {
	op     string
	target string
}

// dupsFD は 2>&1 のような fd の付け替えかどうか。ファイルを開くリダイレクトとは区別する。
func (r redirect) dupsFD() bool {
	if r.op != ">&" && r.op != "<&" {
		return false
	}
	return r.target == "-" || isDigits(r.target)
}

func (r redirect) feedsStdin() bool {
	return r.op == "<<" || r.op == "<<-" || r.op == "<<<"
}

// script は 1 回の Bash 呼び出しに渡されたコマンド文字列全体。
type script struct {
	cmds       []*simpleCmd
	topLevel   int
	background bool
	cmdSubst   bool
	procSubst  bool
}

// wrappers はコマンド名の前に付いても、実際に動くコマンドを変えない語。
var wrappers = map[string]bool{
	"!": true, "{": true, "}": true, "do": true, "then": true, "else": true,
	"elif": true, "if": true, "while": true, "until": true, "time": true,
	"exec": true, "command": true, "builtin": true, "nohup": true,
}

var assignmentRe = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*\+?=`)

// command は、予約語や env などの前置きを除いたコマンド名と引数を返す。
// env で付けた環境変数は assigns と同じく前置きとして扱う。
func (c *simpleCmd) command() (name string, args []string, envPrefixed bool) {
	words := c.words
	for len(words) > 0 {
		w := words[0]
		switch {
		case wrappers[w]:
			words = words[1:]
		case w == "env":
			words = words[1:]
			for len(words) > 0 && (assignmentRe.MatchString(words[0]) || strings.HasPrefix(words[0], "-")) {
				envPrefixed = true
				words = words[1:]
			}
		default:
			return w, words[1:], envPrefixed || len(c.assigns) > 0
		}
	}
	return "", nil, envPrefixed || len(c.assigns) > 0
}

// baseName は絶対パスや相対パスで呼んだコマンドの名前部分。
func (c *simpleCmd) baseName() string {
	name, _, _ := c.command()
	return filepath.Base(name)
}

// program は、timeout・nice・xargs・sudo・uv run・npx などの起動役を外した、実際に動くプログラムの名前（パスを除く）と引数。
func (c *simpleCmd) program() (string, []string) {
	name, args, _ := c.command()
	for {
		switch filepath.Base(name) {
		case "timeout", "gtimeout":
			args = skipOpts(args, map[string]bool{"-s": true, "--signal": true, "-k": true, "--kill-after": true})
			if len(args) > 0 {
				args = args[1:]
			}
		case "nice":
			args = skipOpts(args, map[string]bool{"-n": true, "--adjustment": true})
		case "xargs":
			args = skipOpts(args, map[string]bool{"-I": true, "-n": true, "-L": true, "-P": true, "-d": true, "-E": true, "-s": true, "-a": true, "-J": true, "-R": true, "-S": true})
		case "sudo":
			args = skipOpts(args, map[string]bool{"-u": true, "-g": true, "-C": true, "-D": true, "-h": true, "-p": true, "-U": true, "-r": true, "-t": true})
		case "stdbuf":
			args = skipOpts(args, nil)
		case "uv", "poetry", "pipenv", "pdm", "rye":
			if len(args) == 0 || args[0] != "run" {
				return filepath.Base(name), args
			}
			args = skipOpts(args[1:], map[string]bool{"--with": true, "-w": true, "--python": true, "-p": true, "--directory": true, "--project": true, "--env-file": true, "--package": true, "--extra": true, "--group": true})
		case "uvx", "npx", "pnpx", "bunx":
			args = skipOpts(args, map[string]bool{"--from": true, "--with": true, "--python": true, "-p": true, "--package": true})
		default:
			return filepath.Base(name), args
		}
		if len(args) == 0 {
			return "", nil
		}
		name, args = args[0], args[1:]
	}
}

func skipOpts(args []string, valueFlags map[string]bool) []string {
	for len(args) > 0 && strings.HasPrefix(args[0], "-") && args[0] != "-" {
		if args[0] == "--" {
			return args[1:]
		}
		if valueFlags[args[0]] && len(args) > 1 {
			args = args[2:]
			continue
		}
		args = args[1:]
	}
	return args
}

func (c *simpleCmd) hasVar(name string) bool {
	return slices.Contains(c.vars, name)
}

func (c *simpleCmd) stdinFed() bool {
	if c.piped {
		return true
	}
	for _, r := range c.redirects {
		if r.feedsStdin() || r.op == "<" {
			return true
		}
	}
	return false
}

func parse(command string) *script {
	p := &parser{src: []rune(command), out: &script{}}
	p.parseList(0, 0)
	p.expandShellC()
	return p.out
}

type heredoc struct {
	delim string
	strip bool
}

type parser struct {
	src      []rune
	pos      int
	out      *script
	heredocs []heredoc
}

func (p *parser) peek(offset int) rune {
	if p.pos+offset < len(p.src) {
		return p.src[p.pos+offset]
	}
	return 0
}

// listState は parseList 1 回分の組み立て途中の状態。
type listState struct {
	p       *parser
	depth   int
	cur     *simpleCmd
	word    strings.Builder
	inWord  bool
	pending *redirect
}

func (s *listState) endWord() {
	if !s.inWord {
		return
	}
	w := s.word.String()
	s.word.Reset()
	s.inWord = false
	if s.pending != nil {
		s.pending.target = w
		s.cur.redirects = append(s.cur.redirects, *s.pending)
		if s.pending.op == "<<" || s.pending.op == "<<-" {
			s.p.heredocs = append(s.p.heredocs, heredoc{delim: w, strip: s.pending.op == "<<-"})
		}
		s.pending = nil
		return
	}
	if len(s.cur.words) == 0 && assignmentRe.MatchString(w) {
		s.cur.assigns = append(s.cur.assigns, w)
		return
	}
	s.cur.words = append(s.cur.words, w)
}

func (s *listState) endCmd() {
	s.endWord()
	c := s.cur
	if len(c.words) > 0 || len(c.assigns) > 0 || len(c.redirects) > 0 {
		s.p.out.cmds = append(s.p.out.cmds, c)
		if s.depth == 0 {
			s.p.out.topLevel++
		}
	}
	s.cur = &simpleCmd{depth: s.depth}
}

func (s *listState) add(r rune) {
	s.word.WriteRune(r)
	s.inWord = true
}

// parseList は closer（0 なら入力の終わり）までのコマンド列を読む。
func (p *parser) parseList(depth int, closer rune) {
	s := &listState{p: p, depth: depth, cur: &simpleCmd{depth: depth}}
	subshells := 0
	for p.pos < len(p.src) {
		c := p.src[p.pos]
		if closer != 0 && c == closer && subshells == 0 {
			p.pos++
			s.endCmd()
			return
		}
		switch {
		case c == ' ' || c == '\t':
			s.endWord()
			p.pos++
		case c == '\n':
			s.endCmd()
			p.pos++
			p.skipHeredocs()
		case c == '\\':
			if p.peek(1) == '\n' {
				p.pos += 2
				continue
			}
			if p.pos+1 < len(p.src) {
				s.add(p.src[p.pos+1])
				p.pos += 2
			} else {
				p.pos++
			}
		case c == '\'':
			s.inWord = true
			p.pos++
			for p.pos < len(p.src) && p.src[p.pos] != '\'' {
				s.word.WriteRune(p.src[p.pos])
				p.pos++
			}
			p.pos++
		case c == '"':
			s.inWord = true
			p.readDouble(s)
		case c == '$':
			s.inWord = true
			p.readDollar(s)
		case c == '`':
			s.inWord = true
			p.out.cmdSubst = true
			p.pos++
			p.parseList(depth+1, '`')
			s.word.WriteString("`...`")
		case c == '#' && !s.inWord:
			for p.pos < len(p.src) && p.src[p.pos] != '\n' {
				p.pos++
			}
		case (c == '<' || c == '>') && p.peek(1) == '(':
			p.out.procSubst = true
			p.pos += 2
			p.parseList(depth+1, ')')
			s.word.WriteRune(c)
			s.word.WriteString("(...)")
			s.inWord = true
		case c == '<' || c == '>':
			if s.inWord && isDigits(s.word.String()) {
				s.word.Reset()
				s.inWord = false
			} else {
				s.endWord()
			}
			op := p.readRedirectOp()
			s.pending = &redirect{op: op}
		case c == '&':
			switch p.peek(1) {
			case '&':
				s.endCmd()
				p.pos += 2
			case '>':
				s.endWord()
				if p.peek(2) == '>' {
					s.pending = &redirect{op: "&>>"}
					p.pos += 3
				} else {
					s.pending = &redirect{op: "&>"}
					p.pos += 2
				}
			default:
				s.endCmd()
				if depth == 0 {
					p.out.background = true
				}
				p.pos++
			}
		case c == '|':
			if p.peek(1) == '|' {
				s.endCmd()
				p.pos += 2
				continue
			}
			s.endCmd()
			s.cur.piped = true
			if p.peek(1) == '&' {
				p.pos += 2
			} else {
				p.pos++
			}
		case c == ';':
			s.endCmd()
			p.pos++
		case c == '(' && !s.inWord && len(s.cur.words) == 0:
			subshells++
			s.endCmd()
			p.pos++
		case c == ')' && subshells > 0:
			subshells--
			s.endCmd()
			p.pos++
		default:
			s.add(c)
			p.pos++
		}
	}
	s.endCmd()
}

func (p *parser) readRedirectOp() string {
	for _, op := range []string{"<<<", "<<-", "<<", "<>", "<&", ">>", ">|", ">&", "<", ">"} {
		if strings.HasPrefix(string(p.src[p.pos:min(p.pos+len(op), len(p.src))]), op) {
			p.pos += len(op)
			return op
		}
	}
	p.pos++
	return string(p.src[p.pos-1])
}

func (p *parser) readDouble(s *listState) {
	p.pos++
	for p.pos < len(p.src) {
		c := p.src[p.pos]
		switch {
		case c == '"':
			p.pos++
			return
		case c == '\\' && strings.ContainsRune("$`\"\\\n", p.peek(1)):
			if p.peek(1) != '\n' {
				s.word.WriteRune(p.peek(1))
			}
			p.pos += 2
		case c == '$':
			p.readDollar(s)
		case c == '`':
			p.out.cmdSubst = true
			p.pos++
			p.parseList(s.depth+1, '`')
			s.word.WriteString("`...`")
		default:
			s.word.WriteRune(c)
			p.pos++
		}
	}
}

func (p *parser) readDollar(s *listState) {
	next := p.peek(1)
	switch {
	case next == '(' && p.peek(2) == '(':
		start := p.pos
		p.pos++
		level := 0
		for p.pos < len(p.src) {
			switch p.src[p.pos] {
			case '(':
				level++
			case ')':
				level--
			}
			p.pos++
			if level == 0 {
				break
			}
		}
		s.word.WriteString(string(p.src[start:p.pos]))
	case next == '(':
		p.out.cmdSubst = true
		p.pos += 2
		p.parseList(s.depth+1, ')')
		s.word.WriteString("$(...)")
	case next == '{':
		p.pos += 2
		name := p.readIdent()
		if name != "" {
			s.cur.vars = append(s.cur.vars, name)
		}
		level := 1
		var rest strings.Builder
		for p.pos < len(p.src) && level > 0 {
			switch p.src[p.pos] {
			case '{':
				level++
			case '}':
				level--
			}
			if level > 0 {
				rest.WriteRune(p.src[p.pos])
			}
			p.pos++
		}
		fmt.Fprintf(&s.word, "${%s%s}", name, rest.String())
	case next == '\'':
		p.pos += 2
		for p.pos < len(p.src) && p.src[p.pos] != '\'' {
			if p.src[p.pos] == '\\' && p.pos+1 < len(p.src) {
				p.pos++
			}
			s.word.WriteRune(p.src[p.pos])
			p.pos++
		}
		p.pos++
	case isIdentStart(next):
		p.pos++
		name := p.readIdent()
		s.cur.vars = append(s.cur.vars, name)
		s.word.WriteRune('$')
		s.word.WriteString(name)
	case next != 0 && strings.ContainsRune("?$!#*@-0123456789", next):
		s.word.WriteRune('$')
		s.word.WriteRune(next)
		p.pos += 2
	default:
		s.word.WriteRune('$')
		p.pos++
	}
}

func (p *parser) readIdent() string {
	start := p.pos
	for p.pos < len(p.src) && (isIdentStart(p.src[p.pos]) || (p.src[p.pos] >= '0' && p.src[p.pos] <= '9')) {
		p.pos++
	}
	return string(p.src[start:p.pos])
}

// skipHeredocs は改行の直後に呼び、保留中のヒアドキュメントの本文を読み飛ばす。
func (p *parser) skipHeredocs() {
	for _, h := range p.heredocs {
		for p.pos < len(p.src) {
			end := p.pos
			for end < len(p.src) && p.src[end] != '\n' {
				end++
			}
			line := string(p.src[p.pos:end])
			p.pos = min(end+1, len(p.src))
			if h.strip {
				line = strings.TrimLeft(line, "\t")
			}
			if line == h.delim {
				break
			}
		}
	}
	p.heredocs = nil
}

var shells = map[string]bool{"sh": true, "bash": true, "zsh": true, "dash": true}

// expandShellC は bash -c '...' と eval の中身も 1 段深いコマンドとして読む。
func (p *parser) expandShellC() {
	for i := 0; i < len(p.out.cmds); i++ {
		c := p.out.cmds[i]
		_, args, _ := c.command()
		inner := ""
		switch {
		case c.baseName() == "eval":
			inner = strings.Join(args, " ")
		case shells[c.baseName()]:
			for j, a := range args {
				if strings.HasPrefix(a, "-") && !strings.HasPrefix(a, "--") && strings.ContainsRune(a, 'c') && j+1 < len(args) {
					inner = args[j+1]
					break
				}
			}
		}
		if inner == "" {
			continue
		}
		nested := parse(inner)
		for _, ic := range nested.cmds {
			ic.depth += c.depth + 1
			p.out.cmds = append(p.out.cmds, ic)
		}
		p.out.cmdSubst = p.out.cmdSubst || nested.cmdSubst
		p.out.procSubst = p.out.procSubst || nested.procSubst
	}
}

func isIdentStart(r rune) bool {
	return r == '_' || (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z')
}

func isDigits(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}
