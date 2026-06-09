# Volley Configurable Roles (Separation of Duties) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make who performs each Volley role (planner, implementer, plan/code/pr reviewer) configurable per assistant, with separation of duties — no agent both produces and reviews a step, and review is a mandatory gate — enforced fail-closed.

**Architecture:** A `jq`-backed resolver (`scripts/volley-config.sh`) reads `.volley/config.json` against a built-in assistant registry (Claude + Codex, with adapter-declared capabilities), resolves each role to an assistant + transport, and validates fail-closed. Skills stop hardcoding roles and ask the resolver. An atomic lock (the v0.1.1 `mkdir` primitive, now wired into the claim path) plus snapshot-pinned reviews keep concurrency honest. A small `.volley/sod.json` tracks produced_by/reviewed_by so the workflow refuses to advance a step until a *different* agent reviews it.

**Tech Stack:** Bash (lib + resolver + skill helpers), `jq` (JSON parsing — single parser path), Markdown (skills/docs), the existing Codex MCP (`mcp__codex__codex`) + per-OS spawn handlers.

**Spec:** `docs/design/2026-06-02-volley-configurable-roles-design.md` (hardened via 2 Codex review rounds). Work happens in `C:\git\volley` (the public repo). Never reintroduce `duo`/`copair`. Every new `.sh` must pass `shellcheck -S warning` and the suite must stay green via `bash tests/run-all.sh`.

**Staging:** 6 phases, each independently shippable. Phase 1 is inert (config readable, behavior unchanged). Phase 3 is the first user-visible capability (route code review to Codex). Ship a point release at the end of any phase.

---

## File Structure

```
scripts/
  volley-config.sh        NEW — registry + resolver + validation (jq). Pure functions; no side effects beyond reads.
  lib.sh                  MODIFY — add snapshot + SoD helpers (lock primitives already shipped in v0.1.1).
skills/
  setup/SKILL.md          MODIFY — scaffold an explicit default config comment; doctor-style jq note
  doctor/SKILL.md         MODIFY — check jq present; print the role matrix
  status/SKILL.md         MODIFY — print the role matrix + SoD gate state
  review-code/SKILL.md    MODIFY — read code_reviewer; claude=local, codex=MCP-diff; snapshot-pinned; record reviewed_by
  review-plan/SKILL.md    MODIFY — read plan_reviewer; record reviewed_by
  review-pr/SKILL.md       MODIFY — read pr_reviewer; record reviewed_by
  implement/SKILL.md      MODIFY — read implementer; codex=spawn (today) / claude=inline mode; acquire lock; record produced_by; SoD gate before completion
tests/
  test-config.sh          NEW — resolver + validation + defaults
  test-sod.sh             NEW — SoD tracking + gate + fail-closed
  test-snapshot.sh        NEW — snapshot create/verify/invalidate
  (test-lock-race.sh already exists from v0.1.1)
docs/
  ROLES.md                NEW — the config + recommended setups
  ../README.md, ../SECURITY.md  MODIFY — the "separation of duties" headline + section
```

**Resolver contract (used by every later task — names are fixed here):**
- `volley_config_file` → echoes the config path (`.volley/config.json`).
- `volley_config_role <role>` → echoes the resolved assistant id for a role (handles `auto` + no-file defaults). Exit non-zero on unresolved.
- `volley_assistant_can <assistant> <role>` → exit 0 if that assistant's adapter supports that role.
- `volley_assistant_transport <assistant> <role>` → echoes `inline|mcp|terminal`.
- `volley_config_validate` → runs every fail-closed check; prints a clear error + exits non-zero if invalid; exits 0 if valid (or no file).
- `volley_config_matrix` → prints the `role: assistant (transport)` table.
- SoD: `volley_sod_record_produced <artifact> <assistant>`, `volley_sod_record_reviewed <artifact> <assistant>`, `volley_sod_assert_reviewed <artifact>` (exit non-zero if not reviewed by a different assistant).

---

## Phase 1 — Config foundation (inert; behavior unchanged)

### Task 1: Built-in registry + role resolution with defaults

**Files:** Create `scripts/volley-config.sh`; Test `tests/test-config.sh`

- [ ] **Step 1: Write the failing test** — `tests/test-config.sh`:
```bash
#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0; pass(){ echo "PASS: $1"; PASS=$((PASS+1)); }; fail(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }
# shellcheck disable=SC1090
. "$ROOT/scripts/volley-config.sh"

cd "$TMP"; mkdir -p .volley

# (1) No config file → v0.1 defaults
[ "$(volley_config_role planner)"       = claude ] && pass "default planner=claude"       || fail "default planner"
[ "$(volley_config_role implementer)"   = codex  ] && pass "default implementer=codex"     || fail "default implementer"
[ "$(volley_config_role plan_reviewer)" = codex  ] && pass "default plan_reviewer→codex"   || fail "default plan_reviewer ($(volley_config_role plan_reviewer))"
[ "$(volley_config_role code_reviewer)" = claude ] && pass "default code_reviewer→claude"  || fail "default code_reviewer ($(volley_config_role code_reviewer))"
[ "$(volley_config_role pr_reviewer)"   = claude ] && pass "default pr_reviewer→claude"    || fail "default pr_reviewer"

# (2) Explicit producers + auto reviewers
cat > .volley/config.json <<'JSON'
{ "version":1, "roles":{ "planner":"codex","implementer":"claude","plan_reviewer":"auto","code_reviewer":"auto","pr_reviewer":"auto" } }
JSON
[ "$(volley_config_role plan_reviewer)" = claude ] && pass "auto plan_reviewer ≠ codex producer" || fail "auto plan_reviewer"
[ "$(volley_config_role code_reviewer)" = codex  ] && pass "auto code_reviewer ≠ claude producer" || fail "auto code_reviewer"

echo ""; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run it, expect FAIL** — `bash tests/test-config.sh` → fails sourcing `volley-config.sh` (missing). Confirms the test drives the code.

- [ ] **Step 3: Implement `scripts/volley-config.sh`** (registry + resolver). Requires `jq`.
```bash
#!/usr/bin/env bash
# Volley role resolver. Reads .volley/config.json (if present) against a
# built-in assistant registry, resolves roles to assistants, validates SoD.
# Requires jq. Pure reads — no repo mutation.

volley_config_file() { echo ".volley/config.json"; }

# Built-in registry (v0.2 ships Claude + Codex). `kind` + the roles each can hold.
# claude runs inline; codex reviews via MCP, implements via terminal spawn.
_volley_registry_assistants() { echo "claude codex"; }
volley_assistant_can() {  # <assistant> <role>
  local a=$1 r=$2
  case "$a" in
    claude) case "$r" in plan|implement|review_plan|review_code|review_pr) return 0;; esac;;
    codex)  case "$r" in plan|implement|review_plan|review_code|review_pr) return 0;; esac;;
  esac
  return 1
}
volley_assistant_transport() {  # <assistant> <role>
  local a=$1 r=$2
  if [ "$a" = claude ]; then echo inline; return 0; fi
  case "$r" in implement) echo terminal;; *) echo mcp;; esac
}

# Default producers (reproduce v0.1 when no config file).
_volley_default_role() {  # <role>
  case "$1" in
    planner) echo claude;; implementer) echo codex;;
    plan_reviewer|code_reviewer|pr_reviewer) echo auto;;
  esac
}
# Which producer an artifact's reviewer must differ from.
_volley_producer_of_reviewer() {  # <reviewer-role>
  case "$1" in
    plan_reviewer) echo planner;;
    code_reviewer|pr_reviewer) echo implementer;;   # pr reviews the change → != implementer
  esac
}

# Read a raw role value from config (or default if no file / key absent).
_volley_raw_role() {  # <role>
  local role=$1 file; file=$(volley_config_file)
  if [ -f "$file" ]; then
    local v; v=$(jq -r --arg r "$role" '.roles[$r] // empty' "$file" 2>/dev/null)
    [ -n "$v" ] && { echo "$v"; return 0; }
  fi
  _volley_default_role "$role"
}

# Resolve a role to a concrete assistant (resolving "auto" to a different assistant than its producer).
volley_config_role() {  # <role>
  local role=$1 v; v=$(_volley_raw_role "$role")
  if [ "$v" != auto ]; then echo "$v"; return 0; fi
  # auto: pick the (single, at N=2) assistant that isn't the producer.
  local prod_role producer; prod_role=$(_volley_producer_of_reviewer "$role"); producer=$(volley_config_role "$prod_role")
  local a; for a in $(_volley_registry_assistants); do
    [ "$a" != "$producer" ] && { echo "$a"; return 0; }
  done
  return 1
}
```

- [ ] **Step 4: Run it, expect PASS** — `bash tests/test-config.sh` → `FAIL=0` (7 passes). On a box without `jq`, install it (`winget install jqlang.jq`) or note CI covers it; the no-file defaults don't need jq, the config-file cases do.

- [ ] **Step 5: Commit** — `git add scripts/volley-config.sh tests/test-config.sh && git commit -m "feat(roles): jq role resolver + built-in registry (defaults reproduce v0.1)"`

### Task 2: Fail-closed validation + role matrix

**Files:** Modify `scripts/volley-config.sh`; Test extend `tests/test-config.sh`

- [ ] **Step 1: Add failing assertions** to `tests/test-config.sh` (before the final summary):
```bash
# (3) Validation: SoD violation (reviewer pinned == producer) fails closed
cat > .volley/config.json <<'JSON'
{ "version":1, "roles":{ "planner":"claude","implementer":"codex","plan_reviewer":"codex","code_reviewer":"codex","pr_reviewer":"claude" } }
JSON
volley_config_validate >/dev/null 2>&1 && fail "SoD violation should fail validation" || pass "SoD violation fails closed (code_reviewer==implementer)"
# (4) Unknown assistant fails closed
cat > .volley/config.json <<'JSON'
{ "version":1, "roles":{ "planner":"claude","implementer":"gpt5","plan_reviewer":"auto","code_reviewer":"auto","pr_reviewer":"auto" } }
JSON
volley_config_validate >/dev/null 2>&1 && fail "unknown assistant should fail" || pass "unknown assistant fails closed"
# (5) Valid default passes
rm -f .volley/config.json
volley_config_validate >/dev/null 2>&1 && pass "no-file config validates" || fail "no-file should validate"
# (6) matrix prints all five roles
rm -f .volley/config.json
[ "$(volley_config_matrix | grep -c ':')" -ge 5 ] && pass "matrix lists ≥5 roles" || fail "matrix"
```

- [ ] **Step 2: Run, expect FAIL** — `bash tests/test-config.sh` → the new cases fail (functions undefined).

- [ ] **Step 3: Implement `volley_config_validate` + `volley_config_matrix`** in `scripts/volley-config.sh`:
```bash
volley_config_validate() {
  local file; file=$(volley_config_file)
  if [ -f "$file" ]; then
    jq -e . "$file" >/dev/null 2>&1 || { echo "ERROR: .volley/config.json is not valid JSON." >&2; return 2; }
    local ver; ver=$(jq -r '.version // 0' "$file"); [ "$ver" = 1 ] || { echo "ERROR: unsupported config version '$ver' (expected 1)." >&2; return 2; }
  fi
  local n; n=$(_volley_registry_assistants | wc -w)
  local role assistant
  for role in planner implementer plan_reviewer code_reviewer pr_reviewer; do
    # auto only valid at N==2 (Codex review #2)
    if [ "$(_volley_raw_role "$role")" = auto ] && [ "$n" -ne 2 ]; then
      echo "ERROR: role '$role' is 'auto' but the registry has $n assistants; pin it explicitly at N>=3." >&2; return 3
    fi
    assistant=$(volley_config_role "$role") || { echo "ERROR: cannot resolve role '$role'." >&2; return 3; }
    _volley_registry_assistants | tr ' ' '\n' | grep -qx "$assistant" || { echo "ERROR: role '$role' assigned to unknown assistant '$assistant'." >&2; return 3; }
    volley_assistant_can "$assistant" "${role%_reviewer}" 2>/dev/null || volley_assistant_can "$assistant" "review_${role%_reviewer}" 2>/dev/null || {
      # map role→capability: planner→plan, implementer→implement, *_reviewer→review_*
      :; }
  done
  # Separation of duties (clause 1): reviewer != producer
  [ "$(volley_config_role plan_reviewer)" != "$(volley_config_role planner)" ]     || { echo "ERROR: plan_reviewer == planner (separation of duties)." >&2; return 4; }
  [ "$(volley_config_role code_reviewer)" != "$(volley_config_role implementer)" ] || { echo "ERROR: code_reviewer == implementer (separation of duties)." >&2; return 4; }
  [ "$(volley_config_role pr_reviewer)"   != "$(volley_config_role implementer)" ] || { echo "ERROR: pr_reviewer == implementer (separation of duties)." >&2; return 4; }
  return 0
}
volley_config_matrix() {
  local role a t
  for role in planner implementer plan_reviewer code_reviewer pr_reviewer; do
    a=$(volley_config_role "$role" 2>/dev/null) || a="?"
    case "$role" in planner) t=$(volley_assistant_transport "$a" plan);; implementer) t=$(volley_assistant_transport "$a" implement);; *) t=$(volley_assistant_transport "$a" review_code);; esac
    printf '%-15s %s (%s)\n' "$role:" "$a" "$t"
  done
}
```
(Capability mapping note: roles map to capabilities as planner→`plan`, implementer→`implement`, `<x>_reviewer`→`review_<x>`. Implement a small `_volley_role_capability <role>` helper and use it in the `volley_assistant_can` check rather than the inline `${role%_reviewer}` shortcut above — make the check exact.)

- [ ] **Step 4: Run, expect PASS** — `bash tests/test-config.sh` → `FAIL=0`.

- [ ] **Step 5: shellcheck + commit** — `shellcheck -S warning scripts/volley-config.sh tests/test-config.sh` (fix any findings); `git add -A && git commit -m "feat(roles): fail-closed config validation + role matrix"`

### Task 3: Surface the matrix + jq check in doctor/status

**Files:** Modify `skills/doctor/SKILL.md`, `skills/status/SKILL.md`

- [ ] **Step 1:** In `skills/doctor/SKILL.md`, add a check after the existing asset check: source `volley-config.sh`, verify `command -v jq` (FAIL with `winget install jqlang.jq` hint if absent), run `volley_config_validate` (report PASS/FAIL with its error), and print `volley_config_matrix`. Exact snippet to insert:
```bash
. "${CLAUDE_PLUGIN_ROOT}/scripts/volley-config.sh"
command -v jq >/dev/null && echo "[PASS] jq present" || echo "[FAIL] jq missing — install: winget install jqlang.jq (or apt/brew install jq)"
volley_config_validate && echo "[PASS] role config valid" || echo "[FAIL] role config invalid (see error above)"
echo "[INFO] role matrix:"; volley_config_matrix
```
- [ ] **Step 2:** In `skills/status/SKILL.md`, add a step that prints `volley_config_matrix` (sourcing `volley-config.sh`) so status always shows who's assigned to what.
- [ ] **Step 3: Verify** — `grep -rniwE 'duo|copair' skills/doctor/SKILL.md skills/status/SKILL.md` → empty; `claude plugin validate ./` passes.
- [ ] **Step 4: Commit** — `git add skills/doctor/SKILL.md skills/status/SKILL.md && git commit -m "feat(roles): doctor/status surface jq + the live role matrix"`

---

## Phase 2 — Snapshot reviews + lock wiring

### Task 4: Snapshot helpers (precise capture, Codex review #2)

**Files:** Modify `scripts/lib.sh`; Test `tests/test-snapshot.sh`

- [ ] **Step 1: Write `tests/test-snapshot.sh`** — in a temp git repo: make a tracked edit + an untracked file, `volley_snapshot_create` → id; `volley_snapshot_verify id` → 0 (unchanged); modify a file; `volley_snapshot_verify id` → non-zero (moved). (Full test body mirrors the existing test files' PASS/FAIL structure; assert the three cases.)
- [ ] **Step 2: Run, expect FAIL** (functions missing).
- [ ] **Step 3: Implement in `scripts/lib.sh`:**
```bash
# Pin a precise snapshot of the working tree: tracked working+index changes via
# `git stash create` (a real commit object, not written to refs) PLUS a content
# hash of untracked files. Echoes an opaque snapshot id. (Codex review #2: a bare
# tree-hash misses staged/untracked/binary changes.)
volley_snapshot_create() {
  local stash untracked
  stash=$(git stash create 2>/dev/null || true); stash=${stash:-EMPTY}
  untracked=$(git ls-files --others --exclude-standard -z 2>/dev/null | sort -z \
              | xargs -0 -r sha1sum 2>/dev/null | sha1sum | cut -d' ' -f1)
  echo "${stash}:${untracked}"
}
# Verify the tree still matches a snapshot id. 0 if unchanged, non-zero if moved.
volley_snapshot_verify() {  # <snapshot-id>
  [ "$(volley_snapshot_create)" = "$1" ]
}
```
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: shellcheck + commit** — `git commit -m "feat(roles): precise snapshot pin for reviews (stash-create + untracked hash)"`

### Task 5: Wire atomic lock acquire into the implement claim

**Files:** Modify `skills/implement/SKILL.md` (step 9)

- [ ] **Step 1:** In `skills/implement/SKILL.md` **step 9** ("Flip STATE only after the handshake"), replace the bare `volley_state_write .volley/STATE codex implement-... 0` claim with an **atomic acquire** using the v0.1.1 primitive, falling back to a clear refusal if already held:
```bash
TOKEN=$(volley_lock_acquire .volley codex "implement-<derive-from-plan>" 0) || {
  echo "ERROR: lock already held — another Volley run is active. Run /volley:status." >&2; exit 1; }
# (volley_lock_acquire already writes STATE metadata; record the token for the watcher/teardown.)
echo "$TOKEN" > .volley/.lock-token
```
Update the surrounding prose: the lock is now held via `.volley/lock.d` (atomic); Codex's completion instruction (it writes `ACTIVE=claude` at the end) must ALSO remove `.volley/lock.d` to release — add that to the Codex prompt in **step 5** (the completion block at `<STATE_PATH_WIN>`): after writing `ACTIVE=claude`, `rmdir`/`rm -rf` the `lock.d` directory.
- [ ] **Step 2: Verify** the skill still reads coherently; `grep -n 'volley_lock_acquire\|lock.d' skills/implement/SKILL.md` shows the wiring; `claude plugin validate ./` passes.
- [ ] **Step 3:** Run `bash tests/run-all.sh` (no skill is executed by tests, but confirm nothing regressed) + `bash tests/test-lock-race.sh`.
- [ ] **Step 4: Commit** — `git commit -m "feat(roles): wire atomic lock acquire into implement claim (closes the live race)"`

---

## Phase 3 — Configurable code_reviewer (first user-visible slice)

### Task 6: `/volley:review-code` routes by `code_reviewer`

**Files:** Modify `skills/review-code/SKILL.md`

- [ ] **Step 1:** At the top of `skills/review-code/SKILL.md` steps, after the lock check, **resolve the reviewer**:
```bash
. "${CLAUDE_PLUGIN_ROOT}/scripts/volley-config.sh"
volley_config_validate || exit 1
REVIEWER=$(volley_config_role code_reviewer)
```
- [ ] **Step 2:** Branch on `$REVIEWER`:
  - `claude` → the existing local review path (Claude reads `git diff HEAD`), unchanged.
  - a backend (`codex`) → **snapshot-pin then MCP-review** (mirror `review-plan` steps 4-6): `SNAP=$(volley_snapshot_create)`; build a prompt embedding the diff + HANDOFF acceptance criteria; call `mcp__codex__codex` (`sandbox: read-only`, `approval-policy: never`); after the verdict, `volley_snapshot_verify "$SNAP" || { echo "Tree changed during review — re-running."; <re-run>; }`; write the verdict to `.volley/CODE-REVIEW.md`.
- [ ] **Step 3:** After a verdict is recorded (either path), record the reviewer for the SoD gate: `volley_sod_record_reviewed code "$REVIEWER"` (helper added in Phase 4 — until then this line is a no-op stub the executor adds in Task 8; sequence Task 8 before merging Phase 3 if shipping together).
- [ ] **Step 4: Verify** — residue clean; `claude plugin validate ./` passes; the skill documents both paths clearly.
- [ ] **Step 5: Commit** — `git commit -m "feat(roles): /volley:review-code routes to the configured reviewer (claude=local, codex=MCP, snapshot-pinned)"`

---

## Phase 4 — Separation-of-duties workflow gate

### Task 7: SoD tracking helpers

**Files:** Modify `scripts/lib.sh` (or a new `scripts/volley-sod.sh`); Test `tests/test-sod.sh`

- [ ] **Step 1: Write `tests/test-sod.sh`** — assert: record_produced(code, codex) then assert_reviewed(code) fails; record_reviewed(code, codex) then assert_reviewed still fails (same agent — SoD!); record_reviewed(code, claude) then assert_reviewed passes.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** a `.volley/sod.json` managed via jq:
```bash
_volley_sod_file() { echo ".volley/sod.json"; }
volley_sod_record_produced() {  # <artifact> <assistant>
  local f; f=$(_volley_sod_file); [ -f "$f" ] || echo '{}' > "$f"
  local t; t=$(mktemp); jq --arg a "$1" --arg by "$2" '.[$a] = {produced_by:$by, reviewed_by:null}' "$f" > "$t" && mv "$t" "$f"
}
volley_sod_record_reviewed() {  # <artifact> <assistant>
  local f; f=$(_volley_sod_file); [ -f "$f" ] || echo '{}' > "$f"
  local t; t=$(mktemp); jq --arg a "$1" --arg by "$2" '.[$a].reviewed_by = $by' "$f" > "$t" && mv "$t" "$f"
}
# Pass only if the artifact was reviewed by a DIFFERENT assistant than produced it.
volley_sod_assert_reviewed() {  # <artifact>
  local f; f=$(_volley_sod_file); [ -f "$f" ] || { echo "SoD: no record for '$1'." >&2; return 1; }
  local prod rev; prod=$(jq -r --arg a "$1" '.[$a].produced_by // empty' "$f"); rev=$(jq -r --arg a "$1" '.[$a].reviewed_by // empty' "$f")
  [ -n "$rev" ] || { echo "SoD: '$1' produced by $prod has NOT been reviewed — refusing to advance." >&2; return 1; }
  [ "$rev" != "$prod" ] || { echo "SoD: '$1' reviewed by its own producer ($prod) — refusing." >&2; return 1; }
  return 0
}
```
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: shellcheck + commit** — `git commit -m "feat(roles): separation-of-duties tracking (produced_by/reviewed_by gate)"`

### Task 8: Wire the gate into produce + review skills

**Files:** Modify `skills/implement/SKILL.md`, `skills/review-code/SKILL.md`, `skills/review-plan/SKILL.md`, `skills/review-pr/SKILL.md`

- [ ] **Step 1:** In `implement` step 9 (after acquiring the lock), `volley_sod_record_produced code "$(volley_config_role implementer)"`. In each review skill, after writing its verdict, `volley_sod_record_reviewed <artifact> "$REVIEWER"` (artifact = `plan`/`code`/`pr`).
- [ ] **Step 2:** In `implement`, add an **early gate** when the plan came from a producer that requires plan-review-first (optional for v0.2: at minimum, before the *completion* transition the workflow asserts `code` will be reviewed). Add to the `/volley:review-code` next-step logic: a "complete" action is only offered once `volley_sod_assert_reviewed code` passes.
- [ ] **Step 3: Verify** residue clean; `claude plugin validate ./` passes; `grep -n volley_sod skills/*/SKILL.md` shows the wiring across produce + 3 review skills.
- [ ] **Step 4: Commit** — `git commit -m "feat(roles): enforce the review gate across produce + review skills"`

---

## Phase 5 — Configurable implementer + inline Claude mode

### Task 9: `/volley:implement` routes by `implementer`; first-class inline mode

**Files:** Modify `skills/implement/SKILL.md`

- [ ] **Step 1:** After the lock check, resolve: `IMPLEMENTER=$(volley_config_role implementer)`.
- [ ] **Step 2:** Branch:
  - backend with `terminal` transport (`codex`) → the existing spawn path (steps 3-11), unchanged.
  - `claude` (transport `inline`) → **inline mode**: `volley_lock_acquire .volley claude "implement-<...>" $$` with **`mode=inline`** recorded (extend `volley_state_write`/the acquire to also stamp `mode`), `volley_sod_record_produced code claude`, then Claude makes the changes **in-session** (no spawn, no nonce handshake, no watcher), and on completion transitions the lock back to idle/awaiting-review. NO PID-liveness promise; an explicit "inline implement complete" marker; if interrupted, the stale-lock guard in `/volley:status` still applies.
- [ ] **Step 3:** The SoD gate is unchanged — inline-Claude-produced code must still be reviewed by a *different* assistant (the configured `code_reviewer`, which validation guarantees ≠ claude).
- [ ] **Step 4: Verify** residue clean; `claude plugin validate ./` passes; the skill clearly documents the two modes; `bash tests/run-all.sh` green.
- [ ] **Step 5: Commit** — `git commit -m "feat(roles): /volley:implement honors the implementer role + first-class inline Claude mode"`

---

## Phase 6 — Remaining roles, N≥3 readiness, docs

### Task 10: `plan_reviewer` + `pr_reviewer` routing

**Files:** Modify `skills/review-plan/SKILL.md`, `skills/review-pr/SKILL.md`

- [ ] **Step 1:** `review-plan`: resolve `plan_reviewer`; today it's always Codex-via-MCP — now if resolved to `claude`, do a local plan review instead. Record `volley_sod_record_reviewed plan "$REVIEWER"`.
- [ ] **Step 2:** `review-pr`: resolve `pr_reviewer` similarly; record reviewed. Producer of the PR artifact = `implementer` (Codex review #2).
- [ ] **Step 3: Verify** residue + validate; **Commit** — `git commit -m "feat(roles): configurable plan_reviewer + pr_reviewer"`

### Task 11: N≥3 config-only fixture test

**Files:** Test `tests/test-config.sh` (extend)

- [ ] **Step 1:** Add a fixture that injects a hypothetical 3rd assistant into `_volley_registry_assistants` (via an override hook or an env the resolver reads), a config that pins reviewers, and asserts: validation passes; `auto` at N=3 is rejected; assigning a role to the 3rd assistant resolves — with NO change to any skill or lock file. This proves the data model is N-ready.
- [ ] **Step 2: Run, expect PASS** (after adding a minimal registry-override seam to `volley-config.sh` — e.g. `VOLLEY_REGISTRY_OVERRIDE` env consulted by `_volley_registry_assistants`).
- [ ] **Step 3: shellcheck + commit** — `git commit -m "test(roles): N>=3 config-only readiness fixture"`

### Task 12: Docs — shout the principle

**Files:** Create `docs/ROLES.md`; Modify `README.md`, `SECURITY.md`

- [ ] **Step 1: `docs/ROLES.md`** — the config schema, every role, `auto` semantics, the recommended setups (default; "Codex reviews everything"; "Claude implements, Codex reviews"), and the SoD guarantee.
- [ ] **Step 2: `README.md`** — add to the hero one line: **"Separation of duties for AI agents — no agent reviews its own work."** Add a short "Roles" section linking `docs/ROLES.md`.
- [ ] **Step 3: `SECURITY.md`** — add a "Separation of Duties" section: framed as the audit-grade principle (no single actor controls a whole transaction), enforced fail-closed, the review-gate, what it does and does not guarantee.
- [ ] **Step 4: Verify** — `grep -nE 'separation of duties' README.md SECURITY.md docs/ROLES.md` present; residue clean; `claude plugin validate ./` passes.
- [ ] **Step 5: Commit** — `git commit -m "docs(roles): ROLES.md + separation-of-duties headline in README + SECURITY"`

### Task 13: Final gate + version bump

- [ ] **Step 1:** `bash tests/run-all.sh` → ALL TESTS PASSED (incl. config/sod/snapshot/lock-race). `shellcheck -S warning scripts/*.sh tests/*.sh` clean. `grep -rniwE 'duo|copair' . --exclude-dir=.git` empty. `claude plugin validate ./` passes.
- [ ] **Step 2:** Acceptance walk-through against the spec's 11 criteria (absent-config==v0.1; SoD clause-1 fail-closed; SoD clause-2 gate; all five roles assignable; inline implement reviewed by a different agent; codex-as-code-reviewer; lock race; snapshot invalidation; parser-present fail-closed; 3rd-adapter fixture; CI green).
- [ ] **Step 3:** Bump `.claude-plugin/plugin.json` + `marketplace.json` to `0.2.0`; commit; push `main`; tag `v0.2.0`; push tag.

---

## Notes for the executor
- **Work in `C:\git\volley` (the public repo).** Every phase is shippable; you may stop + point-release after any phase (bump version, tag).
- **`jq` is a hard dependency** for the resolver; the skills source `volley-config.sh` and call it. `doctor` checks `jq` is present and fails closed with an install hint.
- **Skill edits are surgical** — the implement skill's nonce/handshake/watcher choreography is load-bearing; insert role-resolution + lock-acquire + SoD-record at the specified steps, do NOT rewrite the flow. Read the existing skill before editing.
- **Separation of duties is the thesis** — validation must make a self-review *impossible to express*, and the gate must make a *missing* review block completion. Both are required; neither alone is enough.
- After Phase 6: update memory `volley-build-prepublish` to note v0.2 shipped + the roles feature.
