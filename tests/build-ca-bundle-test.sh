#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/build-ca-bundle-test.XXXXXX")"
FAKE_BIN="$TEST_ROOT/bin"
FAKE_CAROOT="$TEST_ROOT/caroot"
SYSTEM_BUNDLE="/etc/ssl/cert.pem"
FAKE_MKCERT_ROOT='-----BEGIN CERTIFICATE-----
FAKE-MKCERT-ROOT
-----END CERTIFICATE-----'

trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$FAKE_BIN" "$FAKE_CAROOT"
printf '%s\n' "$FAKE_MKCERT_ROOT" >"$FAKE_CAROOT/rootCA.pem"
printf '%s\n' 'FAKE-PRIVATE-KEY' >"$FAKE_CAROOT/rootCA-key.pem"

cat >"$FAKE_BIN/mkcert" <<'MKCERT'
#!/usr/bin/env bash
[ "$1" = "-CAROOT" ] && printf '%s\n' "$FAKE_CAROOT"
MKCERT
chmod +x "$FAKE_BIN/mkcert"

system_cert_count="$(rg -c 'BEGIN CERTIFICATE' "$SYSTEM_BUNDLE")"

fail() {
  echo "$1" >&2
  exit 1
}

out="$TEST_ROOT/with-mkcert/ca-bundle.pem"
PATH="$FAKE_BIN:$PATH" FAKE_CAROOT="$FAKE_CAROOT" "$REPO_ROOT/bin/build-ca-bundle" "$out" >/dev/null
[ "$(rg -c 'BEGIN CERTIFICATE' "$out")" -eq $((system_cert_count + 1)) ] ||
  fail "with mkcert: bundle must hold every system root plus the mkcert root"
rg -qF 'FAKE-MKCERT-ROOT' "$out" || fail "with mkcert: mkcert root must be appended"
rg -qF 'FAKE-PRIVATE-KEY' "$out" && fail "with mkcert: mkcert private key must never be read"

out="$TEST_ROOT/without-mkcert/ca-bundle.pem"
PATH="/usr/bin:/bin" "$REPO_ROOT/bin/build-ca-bundle" "$out" >/dev/null
cmp -s "$SYSTEM_BUNDLE" "$out" || fail "without mkcert: bundle must equal the system bundle"

out="$TEST_ROOT/no-root-yet/ca-bundle.pem"
mkdir -p "$TEST_ROOT/empty-caroot"
PATH="$FAKE_BIN:$PATH" FAKE_CAROOT="$TEST_ROOT/empty-caroot" "$REPO_ROOT/bin/build-ca-bundle" "$out" >/dev/null
cmp -s "$SYSTEM_BUNDLE" "$out" || fail "mkcert without a root CA: bundle must equal the system bundle"

out="$TEST_ROOT/rebuild/ca-bundle.pem"
mkdir -p "$(dirname "$out")"
printf '%s\n' 'STALE-BUNDLE' >"$out"
PATH="/usr/bin:/bin" "$REPO_ROOT/bin/build-ca-bundle" "$out" >/dev/null
rg -qF 'STALE-BUNDLE' "$out" && fail "rebuild: stale bundle must be replaced"
[ -z "$(fd -H '^\.ca-bundle\.' "$(dirname "$out")")" ] || fail "rebuild: no temporary file may be left behind"

echo "build-ca-bundle tests passed"
