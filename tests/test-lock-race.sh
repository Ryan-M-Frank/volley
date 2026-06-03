#!/usr/bin/env bash
# Tests the atomic mkdir-based lock primitive in scripts/lib.sh.
# Verifies: exactly one winner in a concurrent acquire race, correct-token
# release, wrong-token refusal, and re-acquire after release.
set -u

# shellcheck disable=SC1090
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

. "${REPO_ROOT}/scripts/lib.sh"

PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# ---------------------------------------------------------------------------
# Test 1 - concurrent acquire race: exactly one winner out of N racers
# ---------------------------------------------------------------------------
RACE_DIR="${TMPDIR_BASE}/race"
mkdir -p "${RACE_DIR}"

RESULTS_DIR="${TMPDIR_BASE}/results"
mkdir -p "${RESULTS_DIR}"

N=20
for i in $(seq 1 "$N"); do
  (
    if token=$(volley_lock_acquire "${RACE_DIR}" "racer${i}" "test-task" "${i}"); then
      printf '%s\n' "$token" > "${RESULTS_DIR}/winner-${i}"
    else
      printf 'lost\n' > "${RESULTS_DIR}/loser-${i}"
    fi
  ) &
done
wait

WINNERS=0
for f in "${RESULTS_DIR}"/winner-*; do
  [ -f "$f" ] && WINNERS=$((WINNERS+1))
done

if [ "$WINNERS" -eq 1 ]; then
  pass "race: exactly 1 winner out of ${N} concurrent acquires"
else
  fail "race: expected 1 winner, got ${WINNERS} (out of ${N} racers)"
fi

# Capture the winning token for subsequent tests
WINNING_TOKEN=""
for f in "${RESULTS_DIR}"/winner-*; do
  [ -f "$f" ] && WINNING_TOKEN=$(cat "$f")
done

# ---------------------------------------------------------------------------
# Test 2 - release with WRONG token is refused and lock stays held
# ---------------------------------------------------------------------------
BAD_TOKEN="nobody:0:1970-01-01T00:00:00Z"
if volley_lock_release "${RACE_DIR}" "$BAD_TOKEN" 2>/dev/null; then
  fail "wrong-token release should return non-zero"
else
  pass "wrong-token release correctly refused"
fi

# Lock dir must still exist after wrong-token attempt
if [ -d "${RACE_DIR}/lock.d" ]; then
  pass "lock.d still present after wrong-token release attempt"
else
  fail "lock.d was removed despite wrong token"
fi

# ---------------------------------------------------------------------------
# Test 3 - release with CORRECT token removes the lock
# ---------------------------------------------------------------------------
if volley_lock_release "${RACE_DIR}" "$WINNING_TOKEN"; then
  pass "correct-token release succeeded"
else
  fail "correct-token release returned non-zero"
fi

if [ ! -d "${RACE_DIR}/lock.d" ]; then
  pass "lock.d removed after correct release"
else
  fail "lock.d still present after correct release"
fi

# ---------------------------------------------------------------------------
# Test 4 - fresh acquire succeeds after a real release
# ---------------------------------------------------------------------------
NEW_TOKEN=""
if NEW_TOKEN=$(volley_lock_acquire "${RACE_DIR}" "fresh-actor" "fresh-task" "42"); then
  pass "re-acquire after release succeeded"
else
  fail "re-acquire after release failed unexpectedly"
fi

# Confirm the new owner file reflects the new token
if [ -f "${RACE_DIR}/lock.d/owner" ]; then
  STORED=$(cat "${RACE_DIR}/lock.d/owner")
  if [ "$STORED" = "$NEW_TOKEN" ]; then
    pass "owner file matches new token"
  else
    fail "owner file '${STORED}' does not match new token '${NEW_TOKEN}'"
  fi
else
  fail "owner file missing after re-acquire"
fi

# Clean up new lock
volley_lock_release "${RACE_DIR}" "$NEW_TOKEN" >/dev/null

# ---------------------------------------------------------------------------
# Results
# ---------------------------------------------------------------------------
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
