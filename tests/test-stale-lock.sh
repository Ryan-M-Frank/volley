#!/usr/bin/env bash
# Verifies the stale-lock detection logic /volley:status uses.
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR" || exit 1
mkdir -p .volley
. "$REPO_ROOT/scripts/lib.sh"

PASS=0; FAIL=0
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }

# Scenario 1: ACTIVE=codex with a known-dead PID. Spawn a child that exits
# immediately and wait for it - after the wait returns, $DEAD_PID is reaped
# and (modulo PID-reuse races, which are vanishingly rare on a quick test)
# guaranteed to test as not-alive. This avoids relying on a hard-coded PID
# like 99999, which is not actually guaranteed dead on real systems.
bash -c 'exit 0' &
DEAD_PID=$!
wait "$DEAD_PID" 2>/dev/null || true
volley_state_write .volley/STATE codex implement-test "$DEAD_PID"

ACTIVE=$(volley_state_get .volley/STATE ACTIVE)
PID=$(volley_state_get .volley/STATE PID)
if [ "$ACTIVE" = "codex" ] && ! volley_state_pid_alive "$PID" 2>/dev/null; then
  pass "stale lock detected (codex active, PID dead)"
else
  fail "stale lock not detected when it should be"
fi

# Scenario 2: ACTIVE=codex with a definitely-alive PID (use $$ - this test process)
volley_state_write .volley/STATE codex implement-test "$$"
PID=$(volley_state_get .volley/STATE PID)
if volley_state_pid_alive "$PID"; then
  pass "live lock correctly detected (PID alive)"
else
  fail "live PID should have been detected as alive"
fi

# Scenario 3: After unlock simulation (write claude/idle), system is recovered
volley_state_write .volley/STATE claude idle 0
ACTIVE=$(volley_state_get .volley/STATE ACTIVE)
[ "$ACTIVE" = "claude" ] && pass "unlock recovery works" || fail "unlock did not reset ACTIVE"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
