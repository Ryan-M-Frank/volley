#!/usr/bin/env bash
# Unit tests for the v0.2 continuity + model-selection helpers in scripts/lib.sh
# and for model/effort flag pass-through in the spawner (via a stubbed tmux run).
# No live model calls - everything here is deterministic and offline.
# Usage: bash tests/test-continuity.sh

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/scripts/lib.sh"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# shellcheck source=/dev/null
. "$LIB"

PASS=0
FAIL=0
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }

# ── volley_is_inherit ─────────────────────────────────────────────────────
volley_is_inherit ""        && pass "is_inherit: empty is inherit"        || fail "is_inherit empty"
volley_is_inherit inherit   && pass "is_inherit: literal 'inherit'"       || fail "is_inherit literal"
volley_is_inherit gpt-5.6-sol && fail "is_inherit: concrete model" \
                              || pass "is_inherit: concrete model is NOT inherit"

# ── volley_validate_token ─────────────────────────────────────────────────
volley_validate_token "gpt-5.6-sol" model 2>/dev/null && pass "validate: good model token" || fail "validate good model"
volley_validate_token "high" effort 2>/dev/null        && pass "validate: good effort token" || fail "validate good effort"
for bad in 'a b' 'a;rm' 'a$(x)' 'a`x`' 'a|b' 'a&b' "a'b" 'a"b' '../x' 'a>b'; do
  if volley_validate_token "$bad" model 2>/dev/null; then
    fail "validate should REJECT unsafe token: [$bad]"
  fi
done
pass "validate: rejects every unsafe/metachar token"

# ── volley_codex_flags ────────────────────────────────────────────────────
[ "$(volley_codex_flags inherit inherit)" = "" ] \
  && pass "flags: inherit+inherit => empty" || fail "flags inherit/inherit not empty: [$(volley_codex_flags inherit inherit)]"
[ "$(volley_codex_flags '' '')" = "" ] \
  && pass "flags: empty+empty => empty" || fail "flags empty/empty not empty"
[ "$(volley_codex_flags gpt-5.6-sol inherit)" = "-m gpt-5.6-sol" ] \
  && pass "flags: model only" || fail "flags model only: [$(volley_codex_flags gpt-5.6-sol inherit)]"
[ "$(volley_codex_flags inherit high)" = "-c model_reasoning_effort=high" ] \
  && pass "flags: effort only" || fail "flags effort only: [$(volley_codex_flags inherit high)]"
[ "$(volley_codex_flags gpt-5.6-sol high)" = "-m gpt-5.6-sol -c model_reasoning_effort=high" ] \
  && pass "flags: model + effort" || fail "flags model+effort: [$(volley_codex_flags gpt-5.6-sol high)]"
# a bad token must make the whole build fail (fail-closed, no silent drop)
if volley_codex_flags 'evil;rm -rf' high >/dev/null 2>&1; then
  fail "flags: unsafe model should fail-closed"
else
  pass "flags: unsafe model fails closed"
fi

# ── repo identity guard ───────────────────────────────────────────────────
# Build a throwaway git repo so the helpers have something real to read.
GITREPO="$TMPDIR/repo"
mkdir -p "$GITREPO"
( cd "$GITREPO" && git init -q && git remote add origin https://github.com/example/project.git )
LIVE_ROOT=$(volley_repo_root "$GITREPO")
LIVE_REMOTE=$(volley_repo_remote "$GITREPO")
[ -n "$LIVE_ROOT" ] && pass "repo_root: resolves a real repo" || fail "repo_root empty"
[ "$LIVE_REMOTE" = "https://github.com/example/project.git" ] && pass "repo_remote: reads origin" || fail "repo_remote: [$LIVE_REMOTE]"

volley_repo_identity_matches "$LIVE_ROOT" "$LIVE_REMOTE" "$GITREPO" \
  && pass "identity: exact match passes" || fail "identity exact match"
# Windows-style backslash root must still match (separator normalization)
volley_repo_identity_matches "${LIVE_ROOT//\//\\}" "$LIVE_REMOTE" "$GITREPO" \
  && pass "identity: backslash root normalizes and matches" || fail "identity backslash normalize"
# A copied local.json from another project must NOT match
if volley_repo_identity_matches "/some/other/root" "$LIVE_REMOTE" "$GITREPO" 2>/dev/null; then
  fail "identity: mismatched root should NOT match (cross-project resume guard)"
else
  pass "identity: mismatched root is rejected"
fi
# Same root but different remote => reject
if volley_repo_identity_matches "$LIVE_ROOT" "https://github.com/other/thing.git" "$GITREPO" 2>/dev/null; then
  fail "identity: mismatched remote should NOT match"
else
  pass "identity: mismatched remote is rejected"
fi

# ── session id capture from JSONL ─────────────────────────────────────────
JSONL="$TMPDIR/run.jsonl"
cat > "$JSONL" <<'EOF'
{"type":"other_event","payload":{"foo":"bar"}}
{"timestamp":"2026-07-21T17:29:05.204Z","type":"session_meta","payload":{"session_id":"019f85ee-6a41-7c61-8319-264fa58fc39b","cwd":"C:\\git\\volley"}}
{"type":"message","content":"hello"}
{"type":"session_meta","payload":{"session_id":"00000000-0000-0000-0000-000000000000"}}
EOF
SID=$(volley_session_id_from_jsonl "$JSONL")
[ "$SID" = "019f85ee-6a41-7c61-8319-264fa58fc39b" ] \
  && pass "session capture: extracts FIRST session_id" || fail "session capture got: [$SID]"
if volley_session_id_from_jsonl "$TMPDIR/none.jsonl" 2>/dev/null; then
  fail "session capture: missing file should fail"
else
  pass "session capture: missing file fails cleanly"
fi
echo '{"type":"noise"}' > "$TMPDIR/noid.jsonl"
if volley_session_id_from_jsonl "$TMPDIR/noid.jsonl" 2>/dev/null; then
  fail "session capture: no-id stream should fail"
else
  pass "session capture: no-id stream fails cleanly"
fi

# ── model/effort pass-through through the spawner (tmux stub) ─────────────
# Confirms VOLLEY_CODEX_FLAGS reach the codex command line intact and quoted-safe.
if command -v tmux >/dev/null 2>&1; then
  BIN="$TMPDIR/bin"; mkdir -p "$BIN"
  # Stub codex: record its argv so we can assert the flags arrived.
  cat > "$BIN/codex" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$TMPDIR/codex-argv.txt"
cat > /dev/null
EOF
  chmod +x "$BIN/codex"
  PROMPT="$TMPDIR/prompt.txt"; echo "hi" > "$PROMPT"
  # Unique title so this never collides with test-platform-handlers.sh's
  # "volley:codex" session, and kill our session afterward so we leave nothing
  # running for the next test file.
  TMUX_TITLE="volley:cont-flagtest"
  TMUX_SESSION="volley_${TMUX_TITLE//[^a-zA-Z0-9_-]/_}"
  trap 'tmux kill-session -t "$TMUX_SESSION" 2>/dev/null; rm -rf "$TMPDIR"' EXIT
  (
    . "$ROOT/scripts/platforms/tmux.sh"
    PATH="$BIN:$PATH" VOLLEY_CODEX_FLAGS="-m gpt-5.6-sol -c model_reasoning_effort=high" \
      spawn_tmux "$PROMPT" "$TMUX_TITLE" >/dev/null
  )
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$TMPDIR/codex-argv.txt" ] && break; sleep 0.3; done
  ARGV=$(cat "$TMPDIR/codex-argv.txt" 2>/dev/null || echo "")
  echo "$ARGV" | grep -q -- "-m gpt-5.6-sol" && echo "$ARGV" | grep -q -- "model_reasoning_effort=high" \
    && pass "spawn: model+effort flags reach codex exec argv" \
    || fail "spawn: flags missing from argv (got: $ARGV)"
else
  echo "SKIP: tmux not installed - flag pass-through test skipped"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
