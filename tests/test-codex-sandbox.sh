#!/usr/bin/env bash
# Regression for the sandbox + approval-policy + cwd bug: every spawned
# `codex exec` must carry --sandbox, -c approval_policy=never, and -C.
#
# NOTE: CI can only do static grep checks here. A real end-to-end Codex launch
# (verifying the terminal actually opens and Codex runs) requires a manual run
# on each platform — grep cannot prove a live invocation.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0; pass(){ echo "PASS: $1"; PASS=$((PASS+1)); }; fail(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# (1) Every platform handler's codex exec line must carry ALL three required flags:
#     --sandbox, approval_policy=never, and -C.
# Strip comment lines (lines where first non-whitespace char is #) before checking.
for h in "$ROOT"/scripts/platforms/*.sh; do
  name=$(basename "$h")
  code_lines=$(grep -nE 'codex exec' "$h" | grep -vE ':[[:space:]]*#')
  if [ -z "$code_lines" ]; then
    fail "${name}: no 'codex exec' line found"
    continue
  fi
  if ! printf '%s\n' "$code_lines" | grep -q -- '--sandbox'; then
    fail "${name}: codex exec missing --sandbox"
  elif ! printf '%s\n' "$code_lines" | grep -q 'approval_policy=never'; then
    fail "${name}: codex exec missing -c approval_policy=never"
  elif ! printf '%s\n' "$code_lines" | grep -q -- ' -C '; then
    fail "${name}: codex exec missing -C repo-root"
  else
    pass "${name}: codex exec carries --sandbox, approval_policy=never, and -C"
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
