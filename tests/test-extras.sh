#!/usr/bin/env bash
# Extra guards: (1) sourcing works from a path containing a space (the real
# ${CLAUDE_PLUGIN_ROOT} lives under "C:\Users\Ryan Frank\..."); (2) every skill
# has valid name+description frontmatter; (3) STATE writes are idempotent and
# never clobber an existing HANDOFF.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
pass(){ echo "PASS: $1"; PASS=$((PASS+1)); }
fail(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# (1) path-with-spaces: copy lib into "a dir/with space" and source via that path
SPACED="$TMP/a dir/with space"
mkdir -p "$SPACED/scripts"
cp "$ROOT/scripts/lib.sh" "$SPACED/scripts/lib.sh"
if ( . "$SPACED/scripts/lib.sh" && volley_state_write "$TMP/STATE" claude idle 0 ) >/dev/null 2>&1 \
   && grep -q 'ACTIVE=claude' "$TMP/STATE"; then
  pass "lib.sh sources and runs from a path containing spaces"
else
  fail "lib.sh broke when sourced from a spaced path"
fi

# (2) skill frontmatter: each SKILL.md opens with --- and has name: + description:
for d in "$ROOT"/skills/*/; do
  s="$d/SKILL.md"; name=$(basename "$d")
  head -1 "$s" | grep -q '^---$' || { fail "$name: no frontmatter fence"; continue; }
  awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$s" | grep -q '^name:' \
    && awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$s" | grep -q '^description:' \
    && pass "$name: frontmatter has name + description" \
    || fail "$name: frontmatter missing name or description"
done

# (3) idempotent STATE write: writing twice yields identical content excluding
# the volatile SINCE= timestamp (volley_state_write always stamps SINCE with
# the current UTC time, so two successive writes intentionally differ there).
. "$ROOT/scripts/lib.sh"
volley_state_write "$TMP/S2" claude idle 0; a=$(grep -v '^SINCE=' "$TMP/S2")
volley_state_write "$TMP/S2" claude idle 0; b=$(grep -v '^SINCE=' "$TMP/S2")
[ "$a" = "$b" ] && pass "volley_state_write is idempotent (excluding SINCE)" || fail "volley_state_write not idempotent"

echo ""; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ] && exit 0 || exit 1
