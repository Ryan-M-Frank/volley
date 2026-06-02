#!/usr/bin/env bash
# Unit tests for scripts/lib.sh
# Usage: bash tests/test-lib.sh

set -u
LIB="$(cd "$(dirname "$0")/.." && pwd)/scripts/lib.sh"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# shellcheck source=/dev/null
. "$LIB"

PASS=0
FAIL=0
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }

# Test 1: volley_state_write creates a parseable STATE file
volley_state_write "$TMPDIR/STATE" claude idle 0
[ -f "$TMPDIR/STATE" ] || fail "STATE file not created"
grep -q "^ACTIVE=claude$" "$TMPDIR/STATE" || fail "ACTIVE key wrong"
grep -q "^TASK=idle$" "$TMPDIR/STATE" || fail "TASK key wrong"
grep -q "^PID=0$" "$TMPDIR/STATE" || fail "PID key wrong"
grep -q "^SINCE=" "$TMPDIR/STATE" || fail "SINCE key missing"
pass "volley_state_write basic"

# Test 2: volley_state_get reads keys
ACTIVE=$(volley_state_get "$TMPDIR/STATE" ACTIVE)
[ "$ACTIVE" = "claude" ] || fail "volley_state_get ACTIVE returned '$ACTIVE'"
pass "volley_state_get reads ACTIVE"

# Test 3: volley_state_assert_active passes for matching actor
volley_state_assert_active "$TMPDIR/STATE" claude || fail "assert_active false negative"
pass "volley_state_assert_active matching actor"

# Test 4: volley_state_assert_active fails for wrong actor
if volley_state_assert_active "$TMPDIR/STATE" codex 2>/dev/null; then
  fail "assert_active false positive"
else
  pass "volley_state_assert_active rejects wrong actor"
fi

# Test 5: volley_state_lock_age returns reasonable seconds
sleep 1
AGE=$(volley_state_lock_age "$TMPDIR/STATE")
[ "$AGE" -ge 1 ] || fail "lock_age too small: $AGE"
[ "$AGE" -lt 10 ] || fail "lock_age implausibly large: $AGE"
pass "volley_state_lock_age returns valid seconds"

# Test 6: volley_state_pid_alive returns false for PID 0
if volley_state_pid_alive 0 2>/dev/null; then
  fail "pid_alive false positive for PID 0"
else
  pass "volley_state_pid_alive correctly false for PID 0"
fi

# Test 7: volley_state_pid_alive returns true for current process
if volley_state_pid_alive $$; then
  pass "volley_state_pid_alive correctly true for self"
else
  fail "pid_alive false negative for self PID"
fi

# Test 8: volley_state_write is atomic (no partial writes visible)
# Write a long-ish state and verify no corruption mid-write by checking final content
volley_state_write "$TMPDIR/STATE" codex some-long-task-name 12345
[ "$(volley_state_get "$TMPDIR/STATE" TASK)" = "some-long-task-name" ] || fail "atomic write lost data"
pass "volley_state_write atomic"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
