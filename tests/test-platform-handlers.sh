#!/usr/bin/env bash
# Tests for the platform handlers. The tmux handler is fully exercised (CI can
# run a headless tmux server). macos/linux desktop handlers are smoke-checked
# for "errors cleanly when no terminal is available" only - real GUI launch is
# community-tested.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR=$(mktemp -d); trap 'rm -rf "$TMPDIR"' EXIT
PASS=0; FAIL=0
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }

PROMPT="$TMPDIR/prompt.txt"; echo "hello from plan" > "$PROMPT"

# --- tmux handler ---
if command -v tmux >/dev/null 2>&1; then
  BIN="$TMPDIR/bin"; mkdir -p "$BIN"
  cat > "$BIN/codex" <<EOF
#!/usr/bin/env bash
cat > "$TMPDIR/codex-received.txt"
EOF
  chmod +x "$BIN/codex"

  ( . "$ROOT/scripts/platforms/tmux.sh"
    PATH="$BIN:$PATH" spawn_tmux "$PROMPT" "volley:codex" >/dev/null )
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$TMPDIR/codex-received.txt" ] && break; sleep 0.3; done
  grep -q "hello from plan" "$TMPDIR/codex-received.txt" 2>/dev/null \
    && pass "spawn_tmux streams the prompt file to codex via stdin" \
    || fail "spawn_tmux did not stream prompt (got: $(cat "$TMPDIR/codex-received.txt" 2>/dev/null))"
else
  echo "SKIP: tmux not installed - tmux handler test skipped"
fi

# --- missing-terminal clean error (run handlers with an empty PATH) ---
# Guarded so the suite passes incrementally as each handler lands (Tasks 4-6).
for h in macos linux tmux; do
  [ -f "$ROOT/scripts/platforms/$h.sh" ] || { echo "SKIP: $h.sh not present yet"; continue; }
  ( . "$ROOT/scripts/platforms/$h.sh"
    PATH="/nonexistent" "spawn_$h" "$PROMPT" "t" ) >/dev/null 2>&1
  rc=$?
  [ "$rc" -ne 0 ] && pass "spawn_$h returns non-zero when its terminal is absent" \
                  || fail "spawn_$h should fail when terminal absent (rc=$rc)"
done

echo ""; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
