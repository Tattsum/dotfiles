// agent-bash-guard は、Claude Code と Codex の PreToolUse hook として Bash コマンドを実行前に検査し、
// sandbox で必ず失敗する書き方や使わないと決めたコマンドを、直し方を添えて拒否する。
//
// 使い方: agent-bash-guard [--agent claude|codex] < hook の入力 JSON
package main

import (
	"context"
	"encoding/json"
	"flag"
	"os"
	"os/exec"
	"strings"
	"time"
)

func main() {
	// 壊れたときに Bash を止めるより、素通りさせる（hook は補助で、最後の砦ではない）。
	defer func() { _ = recover() }()

	agent := flag.String("agent", "claude", "当てる規則の組（claude か codex）")
	flag.Parse()

	var in struct {
		ToolName  string    `json:"tool_name"`
		Cwd       string    `json:"cwd"`
		ToolInput toolInput `json:"tool_input"`
	}
	if err := json.NewDecoder(os.Stdin).Decode(&in); err != nil || in.ToolName != "Bash" {
		return
	}
	home, _ := os.UserHomeDir()
	v := evaluate(in.ToolInput, options{
		agent: *agent, cwd: in.Cwd, home: home, git: runGit,
		writableGitRoots: defaultWritableGitRoots(), managedDir: managedSettingsDir,
	})
	if v.rule == "" {
		return
	}
	_ = json.NewEncoder(os.Stdout).Encode(map[string]any{
		"hookSpecificOutput": map[string]any{
			"hookEventName":            "PreToolUse",
			"permissionDecision":       "deny",
			"permissionDecisionReason": v.reason,
		},
	})
}

func runGit(dir string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "git", append([]string{"-C", dir}, args...)...)
	cmd.Env = append(os.Environ(), "GIT_OPTIONAL_LOCKS=0")
	out, err := cmd.Output()
	return strings.TrimSpace(string(out)), err
}
