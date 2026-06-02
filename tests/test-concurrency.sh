#!/usr/bin/env bash
# Verifies: when STATE has ACTIVE=codex, an attempt by Claude to act is refused.
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR"
mkdir -p .volley
. "$REPO_ROOT/scripts/lib.sh"

PASS=0; FAIL=0
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }

# Set STATE so Codex appears active.
volley_state_write .volley/STATE codex implement-test 99999

# Claude attempts to act - assert_active claude should refuse.
if volley_state_assert_active .volley/STATE claude 2>/dev/null; then
  fail "claude should have been refused while codex is active"
else
  pass "claude refused while codex active"
fi

# Now flip STATE - Claude should be allowed.
volley_state_write .volley/STATE claude idle 0
if volley_state_assert_active .volley/STATE claude 2>/dev/null; then
  pass "claude allowed after lock flipped"
else
  fail "claude should have been allowed after flip"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
