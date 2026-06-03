#!/usr/bin/env bash
# Regression for the read-only-sandbox bug: spawned `codex exec` must always pass -s.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0; pass(){ echo "PASS: $1"; PASS=$((PASS+1)); }; fail(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# (1) No platform handler may invoke a BARE `codex exec` (must be followed by -s).
# Strip comment lines (lines where first non-whitespace char is #) before checking.
for h in "$ROOT"/scripts/platforms/*.sh; do
  if grep -nE 'codex exec' "$h" | grep -vE ':[[:space:]]*#' | grep -qvE 'codex exec -s'; then
    fail "$(basename "$h"): bare 'codex exec' without -s"
  else
    pass "$(basename "$h"): codex exec carries -s"
  fi
done

# (2) dispatcher defaults VOLLEY_CODEX_SANDBOX to workspace-write.
grep -q 'VOLLEY_CODEX_SANDBOX:=workspace-write' "$ROOT/scripts/spawn-codex.sh" \
  && pass "dispatcher defaults to workspace-write" || fail "no workspace-write default"

# (3) dispatcher rejects an invalid sandbox value (fails fast, exit 2).
if VOLLEY_CODEX_SANDBOX=bogus bash "$ROOT/scripts/spawn-codex.sh" /tmp/nope.txt 2>&1 | grep -q 'VOLLEY_CODEX_SANDBOX must be'; then
  pass "dispatcher rejects invalid sandbox value"
else
  fail "dispatcher should reject invalid sandbox value"
fi

echo ""; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
