#!/usr/bin/env bash
# Unit tests for scripts/spawn-codex.sh (dispatcher logic).
#
# Verifies that the dispatcher selects the right platform handler for each
# VOLLEY_PLATFORM override, passes through the prompt path and title, and
# errors cleanly on missing handlers / missing prompt files. Stubs the
# platform handlers so no real terminal is opened.
#
# Usage: bash tests/test-spawn-codex.sh

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${ROOT}/scripts/spawn-codex.sh"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

PASS=0
FAIL=0
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }

# Fake prompt file so the dispatcher's path-existence check passes.
PROMPT="$TMPDIR/prompt.txt"
echo "test prompt" > "$PROMPT"

# Sandbox: copy the real dispatcher into a temp dir alongside stub platform
# handlers. The dispatcher resolves its handler dir from $(dirname "$0"), so
# this isolates dispatch from the real handlers entirely.
SANDBOX="$TMPDIR/sandbox"
mkdir -p "$SANDBOX/platforms"
cp "$SCRIPT" "$SANDBOX/spawn-codex.sh"
# spawn-codex.sh sources lib.sh from its own dir (for model/effort flag building),
# so the isolation sandbox must carry a copy too.
cp "$ROOT/scripts/lib.sh" "$SANDBOX/lib.sh"

for pf in windows macos linux tmux; do
  cat > "$SANDBOX/platforms/$pf.sh" <<EOF
spawn_${pf}() {
  echo "HANDLER=${pf}"
  echo "ARG1=\$1"
  echo "ARG2=\$2"
}
EOF
done

# Test 1: VOLLEY_PLATFORM=windows routes to spawn_windows + passes args
out=$(VOLLEY_PLATFORM=windows bash "$SANDBOX/spawn-codex.sh" "$PROMPT" "my-title" 2>&1)
echo "$out" | grep -q "^HANDLER=windows$" || fail "windows dispatch (out: $out)"
echo "$out" | grep -q "^ARG1=$PROMPT$" || fail "windows dispatch passes prompt path"
echo "$out" | grep -q "^ARG2=my-title$" || fail "windows dispatch passes title"
pass "VOLLEY_PLATFORM=windows dispatches to spawn_windows with both args"

# Test 2: VOLLEY_PLATFORM=macos routes to spawn_macos
out=$(VOLLEY_PLATFORM=macos bash "$SANDBOX/spawn-codex.sh" "$PROMPT" 2>&1)
echo "$out" | grep -q "^HANDLER=macos$" || fail "macos dispatch (out: $out)"
pass "VOLLEY_PLATFORM=macos dispatches to spawn_macos"

# Test 3: VOLLEY_PLATFORM=linux routes to spawn_linux
out=$(VOLLEY_PLATFORM=linux bash "$SANDBOX/spawn-codex.sh" "$PROMPT" 2>&1)
echo "$out" | grep -q "^HANDLER=linux$" || fail "linux dispatch (out: $out)"
pass "VOLLEY_PLATFORM=linux dispatches to spawn_linux"

# Test 4: VOLLEY_PLATFORM=tmux routes to spawn_tmux
out=$(VOLLEY_PLATFORM=tmux bash "$SANDBOX/spawn-codex.sh" "$PROMPT" 2>&1)
echo "$out" | grep -q "^HANDLER=tmux$" || fail "tmux dispatch (out: $out)"
pass "VOLLEY_PLATFORM=tmux dispatches to spawn_tmux"

# Test 5: Unknown platform exits non-zero with clear message
if out=$(VOLLEY_PLATFORM=nonexistent bash "$SANDBOX/spawn-codex.sh" "$PROMPT" 2>&1); then
  fail "nonexistent platform should exit non-zero (got: $out)"
else
  echo "$out" | grep -q "no handler for platform" || fail "nonexistent platform error message (got: $out)"
  pass "VOLLEY_PLATFORM=nonexistent exits with clear error"
fi

# Test 6: Missing prompt file exits non-zero with clear message
if out=$(VOLLEY_PLATFORM=windows bash "$SANDBOX/spawn-codex.sh" "$TMPDIR/missing.txt" 2>&1); then
  fail "missing prompt file should exit non-zero (got: $out)"
else
  echo "$out" | grep -q "prompt file not found" || fail "missing prompt error message (got: $out)"
  pass "missing prompt file exits with clear error"
fi

# Test 7: Default title is "volley:codex" when not supplied
out=$(VOLLEY_PLATFORM=windows bash "$SANDBOX/spawn-codex.sh" "$PROMPT" 2>&1)
echo "$out" | grep -q "^ARG2=volley:codex$" || fail "default title should be 'volley:codex' (out: $out)"
pass "default title is volley:codex"

# Test 8: VOLLEY_PLATFORM=unsupported (the detect_platform sentinel) exits 2
if out=$(VOLLEY_PLATFORM=unsupported bash "$SANDBOX/spawn-codex.sh" "$PROMPT" 2>&1); then
  fail "'unsupported' platform should exit non-zero (got: $out)"
else
  echo "$out" | grep -q "unsupported platform" || fail "'unsupported' error message (got: $out)"
  pass "VOLLEY_PLATFORM=unsupported exits with clear error"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
