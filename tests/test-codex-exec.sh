#!/usr/bin/env bash
# Unit tests for scripts/codex-exec.sh, the transport every Codex review goes through since
# Codex 0.156 removed `codex mcp-server`. Uses tests/fakes/codex, so no live model calls.
# Usage: bash tests/test-codex-exec.sh

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT/scripts/codex-exec.sh"
FAKE="$ROOT/tests/fakes/codex"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }

# A repo whose path contains a space, like the real plugin cache and C:\Users\Ryan Frank.
REPO="$TMP/my repo"
mkdir -p "$REPO" && ( cd "$REPO" && git init -q )
PROMPT="$TMP/prompt.md"
printf 'Review this plan.\nLine two.\n' > "$PROMPT"
SID_GOOD="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

# Run the helper against the fake. Sets $OUT_TEXT, $RC, $CALLS and a fresh $FD per run.
run() {
  FD="$TMP/fake.$RANDOM$RANDOM"; mkdir -p "$FD"
  OUTFILE="$REPO/.volley/REVIEW out.md"
  mkdir -p "$REPO/.volley" && echo "STALE REVIEW FROM AN EARLIER RUN" > "$OUTFILE"
  OUT_TEXT=$(FAKE_CODEX_DIR="$FD" VOLLEY_CODEX_BIN="$FAKE" bash "$HELPER" "$@" 2>"$FD/stderr")
  RC=$?
  CALLS=$(cat "$FD/calls" 2>/dev/null || echo 0)
}
has_arg() { grep -qxF -- "$2" "$FD/args.$1"; }
# True if args file $1 contains the consecutive pair "$2" "$3".
has_pair() { awk -v a="$2" -v b="$3" 'prev==a && $0==b {f=1} {prev=$0} END {exit !f}' "$FD/args.$1"; }

# ── fresh review: read-only, json, output file, cwd, model + effort, prompt on stdin ─────────
run --prompt-file "$PROMPT" --out "$REPO/.volley/REVIEW out.md" --cwd "$REPO" --model gpt-6-astra --effort high
[ "$RC" -eq 0 ] && pass "fresh: exit 0" || fail "fresh: exit $RC ($(cat "$FD/stderr"))"
[ "$CALLS" = "1" ] && pass "fresh: one codex call" || fail "fresh: $CALLS calls"
[ "$(sed -n 1p "$FD/args.1")" = "exec" ] && pass "fresh: subcommand is exec" || fail "fresh: first arg $(sed -n 1p "$FD/args.1")"
has_pair 1 --sandbox read-only && pass "fresh: --sandbox read-only" || fail "fresh: missing --sandbox read-only"
has_arg 1 --json && pass "fresh: --json" || fail "fresh: missing --json"
has_pair 1 -o "$REPO/.volley/REVIEW out.md.attempt" && pass "fresh: -o <out>.attempt scratch file (path with space kept whole)" || fail "fresh: -o pair wrong"
[ ! -e "$REPO/.volley/REVIEW out.md.attempt" ] && pass "fresh: scratch file published, none left behind" || fail "fresh: scratch file left behind"
has_pair 1 -C "$REPO" && pass "fresh: -C <repo root>" || fail "fresh: -C pair wrong"
has_pair 1 -m gpt-6-astra && pass "fresh: -m model" || fail "fresh: missing -m gpt-6-astra"
has_pair 1 -c model_reasoning_effort=high && pass "fresh: effort flag" || fail "fresh: missing effort"
[ "$(tail -n1 "$FD/args.1")" = "-" ] && pass "fresh: prompt read from stdin (-)" || fail "fresh: last arg not -"
cmp -s "$PROMPT" "$FD/stdin.1" && pass "fresh: stdin is the prompt file" || fail "fresh: stdin differs from prompt"
[ "$(cat "$REPO/.volley/REVIEW out.md")" = "REVIEW BODY" ] && pass "fresh: review written to --out" || fail "fresh: out file wrong"
echo "$OUT_TEXT" | grep -qx "SESSION_ID=11111111-2222-3333-4444-555555555555" && pass "fresh: prints SESSION_ID" || fail "fresh: SESSION_ID missing: $OUT_TEXT"
echo "$OUT_TEXT" | grep -qx "CONTINUITY=fresh" && pass "fresh: CONTINUITY=fresh" || fail "fresh: continuity line: $OUT_TEXT"
[ -s "$REPO/.volley/REVIEW out.md.events.jsonl" ] && pass "fresh: event stream saved next to output" || fail "fresh: events file missing"

# ── inherit: no model / effort flags at all ─────────────────────────────────────────────────
run --prompt-file "$PROMPT" --out "$REPO/.volley/REVIEW out.md" --cwd "$REPO" --model inherit --effort inherit
has_arg 1 -m && fail "inherit: -m should be omitted" || pass "inherit: no -m"
grep -q model_reasoning_effort "$FD/args.1" && fail "inherit: effort should be omitted" || pass "inherit: no effort flag"

# ── resume: exec resume <id>, read-only via config (resume has no --sandbox/-C), run from repo ─
run --prompt-file "$PROMPT" --out "$REPO/.volley/REVIEW out.md" --cwd "$REPO" --model gpt-6-astra --effort high --resume "$SID_GOOD"
[ "$RC" -eq 0 ] && pass "resume: exit 0" || fail "resume: exit $RC"
[ "$(sed -n 1p "$FD/args.1")" = "exec" ] && [ "$(sed -n 2p "$FD/args.1")" = "resume" ] && pass "resume: exec resume" || fail "resume: not exec resume"
has_pair 1 -c 'sandbox_mode="read-only"' && pass "resume: read-only enforced via -c sandbox_mode" || fail "resume: sandbox_mode override missing"
has_arg 1 --sandbox && fail "resume: --sandbox is not accepted by exec resume" || pass "resume: no --sandbox flag"
has_arg 1 -C && fail "resume: -C is not accepted by exec resume" || pass "resume: no -C flag"
has_pair 1 "$SID_GOOD" - && pass "resume: session id then - (stdin prompt)" || fail "resume: id/stdin order wrong"
[ "$(cat "$FD/pwd.1")" = "$(cd "$REPO" && pwd)" ] && pass "resume: runs from the repo root" || fail "resume: cwd $(cat "$FD/pwd.1")"
echo "$OUT_TEXT" | grep -qx "CONTINUITY=resumed" && pass "resume: CONTINUITY=resumed" || fail "resume: continuity line: $OUT_TEXT"

# ── resume that fails falls back to one fresh run, and says so ──────────────────────────────
FAKE_CODEX_FAIL_RESUME=1 run --prompt-file "$PROMPT" --out "$REPO/.volley/REVIEW out.md" --cwd "$REPO" --resume "$SID_GOOD"
[ "$RC" -eq 0 ] && pass "fallback: exit 0" || fail "fallback: exit $RC"
[ "$CALLS" = "2" ] && pass "fallback: resume then one fresh call" || fail "fallback: $CALLS calls"
[ "$(sed -n 2p "$FD/args.2")" != "resume" ] && has_pair 2 --sandbox read-only && pass "fallback: second call is a fresh read-only exec" || fail "fallback: second call wrong"
echo "$OUT_TEXT" | grep -qx "CONTINUITY=fallback:resume-failed" && pass "fallback: reported" || fail "fallback: continuity line: $OUT_TEXT"

# ── a malformed session id is never passed to codex ─────────────────────────────────────────
run --prompt-file "$PROMPT" --out "$REPO/.volley/REVIEW out.md" --cwd "$REPO" --resume 'abc;rm -rf /'
[ "$CALLS" = "1" ] && [ "$(sed -n 2p "$FD/args.1")" != "resume" ] && pass "bad id: no resume attempted" || fail "bad id: resume attempted"
echo "$OUT_TEXT" | grep -qx "CONTINUITY=fallback:invalid-session-id" && pass "bad id: reported" || fail "bad id: continuity line: $OUT_TEXT"

# ── unsafe model token: refuse before calling codex ─────────────────────────────────────────
run --prompt-file "$PROMPT" --out "$REPO/.volley/REVIEW out.md" --cwd "$REPO" --model 'evil;rm -rf ~'
[ "$RC" -eq 2 ] && [ "$CALLS" = "0" ] && pass "unsafe model: exit 2, codex never called" || fail "unsafe model: rc=$RC calls=$CALLS"

# ── codex failure propagates its exit code ──────────────────────────────────────────────────
FAKE_CODEX_EXIT=7 run --prompt-file "$PROMPT" --out "$REPO/.volley/REVIEW out.md" --cwd "$REPO"
[ "$RC" -eq 7 ] && pass "codex failure: exit code propagated" || fail "codex failure: rc=$RC"
ls "$REPO/.volley/"*.attempt >/dev/null 2>&1 && fail "codex failure: scratch files left behind" || pass "codex failure: no scratch files left"

# ── codex succeeded but wrote no review: that is an error, not a silent empty review ────────
FAKE_CODEX_NO_OUT=1 run --prompt-file "$PROMPT" --out "$REPO/.volley/REVIEW out.md" --cwd "$REPO"
[ "$RC" -eq 3 ] && pass "empty output: exit 3" || fail "empty output: rc=$RC"
ls "$REPO/.volley/"*.attempt >/dev/null 2>&1 && fail "empty output: scratch files left behind" || pass "empty output: no scratch files left"

# ── usage errors ────────────────────────────────────────────────────────────────────────────
run --prompt-file "$TMP/missing.md" --out "$REPO/.volley/REVIEW out.md" --cwd "$REPO"
[ "$RC" -eq 2 ] && [ "$CALLS" = "0" ] && pass "missing prompt file: exit 2" || fail "missing prompt: rc=$RC calls=$CALLS"
run --prompt-file "$PROMPT" --cwd "$REPO"
[ "$RC" -eq 2 ] && pass "missing --out: exit 2" || fail "missing --out: rc=$RC"

# ── multiline / leading-dash tokens must not smuggle extra codex arguments (sandbox bypass) ─
run --prompt-file "$PROMPT" --out "$REPO/.volley/REVIEW out.md" --cwd "$REPO" --effort $'high
--config
sandbox_mode="danger-full-access"'
[ "$RC" -eq 2 ] && [ "$CALLS" = "0" ] && pass "multiline effort: rejected, codex never called" || fail "multiline effort: rc=$RC calls=$CALLS"
run --prompt-file "$PROMPT" --out "$REPO/.volley/REVIEW out.md" --cwd "$REPO" --model $'gpt-6-astra
--dangerously-bypass-approvals-and-sandbox'
[ "$RC" -eq 2 ] && [ "$CALLS" = "0" ] && pass "multiline model: rejected, codex never called" || fail "multiline model: rc=$RC calls=$CALLS"
run --prompt-file "$PROMPT" --out "$REPO/.volley/REVIEW out.md" --cwd "$REPO" --model --dangerously-bypass-approvals-and-sandbox
[ "$RC" -eq 2 ] && [ "$CALLS" = "0" ] && pass "leading-dash model: rejected" || fail "leading-dash model: rc=$RC calls=$CALLS"
run --prompt-file "$PROMPT" --out "$REPO/.volley/REVIEW out.md" --cwd "$REPO" --resume $'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
x'
[ "$(sed -n 2p "$FD/args.1")" != "resume" ] && pass "multiline session id: not resumed" || fail "multiline session id: resumed"

# ── a trailing option without a value is a usage error, not an endless loop ─────────────────
# Portable stand-in for GNU timeout (macOS has none): 124 if still running after ~10 s.
FD="$TMP/fake.trailing"; mkdir -p "$FD"
FAKE_CODEX_DIR="$FD" VOLLEY_CODEX_BIN="$FAKE" bash "$HELPER" --prompt-file "$PROMPT" --out >/dev/null 2>&1 &
pid=$!; i=0
while kill -0 "$pid" 2>/dev/null && [ $i -lt 50 ]; do sleep 0.2; i=$((i+1)); done
if kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; rc=124; else wait "$pid"; rc=$?; fi
[ "$rc" -eq 2 ] && pass "trailing option: exit 2" || fail "trailing option: rc=$rc (124 means it hung)"

# ── a resume that writes a partial review and then fails must never be reported as the review ─
FAKE_CODEX_PARTIAL_RESUME=1 FAKE_CODEX_NO_OUT=1 run --prompt-file "$PROMPT" --out "$REPO/.volley/REVIEW out.md" --cwd "$REPO" --resume "$SID_GOOD"
[ "$RC" -eq 3 ] && pass "partial resume + empty fresh: exit 3" || fail "partial resume: rc=$RC"
grep -q "PARTIAL FROM FAILED RESUME" "$REPO/.volley/REVIEW out.md" 2>/dev/null && fail "partial resume: partial text left as the review" || pass "partial resume: partial text not published"

# ── a stale review from an earlier run is never mistaken for this run's output ───────────────
FAKE_CODEX_NO_OUT=1 run --prompt-file "$PROMPT" --out "$REPO/.volley/REVIEW out.md" --cwd "$REPO"
[ "$RC" -eq 3 ] && [ ! -e "$REPO/.volley/REVIEW out.md" ] && pass "stale output: removed, exit 3" || fail "stale output: rc=$RC"

# ── relative paths keep their meaning when resume changes into --cwd ─────────────────────────
SUB="$TMP/elsewhere"; mkdir -p "$SUB"
printf 'Prompt in the caller dir.
' > "$SUB/rel-prompt.md"
printf 'WRONG prompt in the repo root.
' > "$REPO/rel-prompt.md"
FD="$TMP/fake.rel"; mkdir -p "$FD"
( cd "$SUB" && FAKE_CODEX_DIR="$FD" VOLLEY_CODEX_BIN="$FAKE" bash "$HELPER" --prompt-file rel-prompt.md --out rel-out.md --cwd "$REPO" --resume "$SID_GOOD" >/dev/null 2>&1 )
rc=$?
[ "$rc" -eq 0 ] && pass "relative paths: exit 0" || fail "relative paths: rc=$rc"
cmp -s "$SUB/rel-prompt.md" "$FD/stdin.1" && pass "relative paths: caller's prompt was sent" || fail "relative paths: wrong prompt sent"
[ -s "$SUB/rel-out.md" ] && [ ! -e "$REPO/rel-out.md" ] && pass "relative paths: review written beside the caller" || fail "relative paths: output landed in the wrong place"

echo ""
echo "codex-exec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
