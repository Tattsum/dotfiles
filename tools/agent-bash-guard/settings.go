package main

import (
	"encoding/json"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// sandboxSettings は Claude Code の settings から読んだ、sandbox の有効・無効と sandbox 内から届くホスト。
type sandboxSettings struct {
	disabled bool
	domains  []string
}

var webFetchDomainRe = regexp.MustCompile(`^WebFetch\(domain:([^)]+)\)$`)

const managedSettingsDir = "/Library/Application Support/ClaudeCode"

// loadSandboxSettings は、ユーザー・プロジェクト・ローカル・組織管理の順に settings を重ねる。
// permissions.allow の WebFetch(domain:X) も sandbox の通信許可に合流するので、ホストとして数える。
func loadSandboxSettings(o options) sandboxSettings {
	files := []string{filepath.Join(o.home, ".claude", "settings.json")}
	roots := []string{}
	if o.cwd != "" {
		roots = append(roots, o.cwd)
		if top, err := o.git(o.cwd, "rev-parse", "--show-toplevel"); err == nil && top != o.cwd {
			roots = append(roots, top)
		}
	}
	for _, r := range roots {
		files = append(files, filepath.Join(r, ".claude", "settings.json"), filepath.Join(r, ".claude", "settings.local.json"))
	}
	files = append(files, filepath.Join(o.managedDir, "managed-settings.json"))
	if extra, err := filepath.Glob(filepath.Join(o.managedDir, "managed-settings.d", "*.json")); err == nil {
		files = append(files, extra...)
	}

	var s sandboxSettings
	for _, f := range files {
		b, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		var cfg struct {
			Permissions struct {
				Allow []string `json:"allow"`
			} `json:"permissions"`
			Sandbox struct {
				Enabled *bool `json:"enabled"`
				Network struct {
					AllowedDomains []string `json:"allowedDomains"`
				} `json:"network"`
			} `json:"sandbox"`
		}
		if json.Unmarshal(b, &cfg) != nil {
			continue
		}
		if cfg.Sandbox.Enabled != nil {
			s.disabled = !*cfg.Sandbox.Enabled
		}
		s.domains = append(s.domains, cfg.Sandbox.Network.AllowedDomains...)
		for _, a := range cfg.Permissions.Allow {
			if m := webFetchDomainRe.FindStringSubmatch(a); m != nil {
				s.domains = append(s.domains, m[1])
			}
		}
	}
	return s
}

// hostAllowed は、host:port が許可リストのどれかに当たるか。ポートの無い項目はどのポートにも当たる。
func hostAllowed(host, port string, domains []string) bool {
	for _, d := range domains {
		dhost, dport, hasPort := strings.Cut(d, ":")
		if hasPort && dport != port {
			continue
		}
		if dhost == host || (strings.HasPrefix(dhost, "*.") && strings.HasSuffix(host, dhost[1:])) {
			return true
		}
	}
	return false
}

// remoteHost は git のリモート URL から接続先のホストとポートを取り出す。ローカルのパスなら空を返す。
func remoteHost(rawURL string) (host, port string) {
	if u, err := url.Parse(rawURL); err == nil && u.Host != "" {
		port = u.Port()
		if port == "" {
			port = map[string]string{"https": "443", "http": "80", "ssh": "22", "git": "9418"}[u.Scheme]
		}
		return u.Hostname(), port
	}
	// scp 形式（git@github.com:owner/repo.git）
	if at, rest, ok := strings.Cut(rawURL, ":"); ok && !strings.Contains(at, "/") && !strings.HasPrefix(rest, "//") {
		if _, h, found := strings.Cut(at, "@"); found {
			return h, "22"
		}
		return at, "22"
	}
	return "", ""
}
