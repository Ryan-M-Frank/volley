#!/usr/bin/env bash
# E2E test for /volley:setup. Simulates the file-creation steps the skill runs.
# Does NOT test the MCP smoke-test step (requires a live Claude Code session).
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR" || exit 1
mkdir -p scripts/templates
cp "$REPO_ROOT/scripts/lib.sh" scripts/lib.sh
cp "$REPO_ROOT/scripts/templates/HANDOFF.md" scripts/templates/HANDOFF.md
cp "$REPO_ROOT/scripts/templates/gitignore" scripts/templates/gitignore

PASS=0
FAIL=0
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }

# Simulate the /volley:setup steps that touch the filesystem.

# Step: scaffold .volley/
mkdir -p .volley
cp scripts/templates/HANDOFF.md .volley/HANDOFF.md
cp scripts/templates/gitignore .volley/.gitignore

# Step: write initial STATE
. scripts/lib.sh
volley_state_write .volley/STATE claude idle 0

# NOTE: setup no longer writes a project .mcp.json - Codex MCP is bundled in
# the plugin. Assertions below cover only the scaffolding that still happens.

# Assertions
[ -f .volley/HANDOFF.md ] && pass "HANDOFF.md created" || fail "HANDOFF.md missing"
[ -f .volley/.gitignore ] && pass ".gitignore created" || fail ".gitignore missing"
[ -f .volley/STATE ] && pass "STATE created" || fail "STATE missing"
grep -q "^ACTIVE=claude$" .volley/STATE && pass "STATE initialised correctly" || fail "STATE bad"
[ ! -f .mcp.json ] && pass "no project .mcp.json written (bundled in plugin)" || fail "unexpected .mcp.json created"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
