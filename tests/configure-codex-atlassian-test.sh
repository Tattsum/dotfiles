#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
FAKE_BIN="$TEST_ROOT/bin"
CALL_LOG="$TEST_ROOT/calls.log"
FAKE_STATE="$TEST_ROOT/state"

trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$FAKE_BIN"

cat >"$FAKE_BIN/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$CALL_LOG"

case "$FAKE_CODEX_MODE:$*" in
  same:"mcp get Atlassian --json")
    printf '%s\n' '{"name":"Atlassian","enabled":true,"transport":{"type":"streamable_http","url":"https://mcp.atlassian.com/v1/mcp","bearer_token_env_var":null,"http_headers":null,"env_http_headers":null,"http_headers_helper":null}}'
    ;;
  missing:"mcp get Atlassian --json") exit 1 ;;
  missing:"mcp list") exit 0 ;;
  missing:"mcp add Atlassian --url https://mcp.atlassian.com/v1/mcp") exit 0 ;;
  auth_failure:"mcp get Atlassian --json") exit 1 ;;
  auth_failure:"mcp list") exit 0 ;;
  auth_failure:"mcp add Atlassian --url https://mcp.atlassian.com/v1/mcp")
    : >"$FAKE_STATE"
    exit 1
    ;;
  auth_failure:"mcp get Atlassian") test -f "$FAKE_STATE" ;;
  drift:"mcp get Atlassian --json")
    printf '%s\n' '{"name":"Atlassian","enabled":true,"transport":{"type":"streamable_http","url":"https://example.invalid/mcp","bearer_token_env_var":null,"http_headers":null,"env_http_headers":null,"http_headers_helper":null}}'
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$FAKE_BIN/codex"

run_configure() {
  PATH="$FAKE_BIN:$PATH" CALL_LOG="$CALL_LOG" FAKE_STATE="$FAKE_STATE" FAKE_CODEX_MODE="$1" \
    "$REPO_ROOT/bin/configure-codex-atlassian"
}

: >"$CALL_LOG"
run_configure same >/dev/null
if rg -q '^mcp add ' "$CALL_LOG"; then
  echo "same: existing configuration must not be rewritten" >&2
  exit 1
fi

: >"$CALL_LOG"
run_configure missing >/dev/null
rg -q '^mcp add Atlassian --url https://mcp\.atlassian\.com/v1/mcp$' "$CALL_LOG"

: >"$CALL_LOG"
if run_configure auth_failure >"$TEST_ROOT/auth-failure.out" 2>&1; then
  echo "auth_failure: interrupted OAuth must be reported" >&2
  exit 1
fi
rg -q 'codex mcp login Atlassian' "$TEST_ROOT/auth-failure.out"

: >"$CALL_LOG"
if run_configure drift >/dev/null 2>&1; then
  echo "drift: mismatched configuration must fail" >&2
  exit 1
fi
if rg -q '^mcp add ' "$CALL_LOG"; then
  echo "drift: mismatched configuration must not be overwritten" >&2
  exit 1
fi

echo "configure-codex-atlassian tests passed"
