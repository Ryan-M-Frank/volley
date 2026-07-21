#!/usr/bin/env bash
# Volley shared bash helpers.
# Source this file from scripts and skills that need to read/write .volley/STATE.
# All functions take an explicit STATE file path so tests can use temp dirs.

# Atomically write a STATE file with the four canonical keys.
# Usage: volley_state_write <path> <active> <task> <pid>
volley_state_write() {
  local path=$1 active=$2 task=$3 pid=$4
  local tmp="${path}.tmp.$$"
  {
    echo "ACTIVE=${active}"
    echo "TASK=${task}"
    echo "SINCE=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "PID=${pid}"
  } > "$tmp"
  mv -f "$tmp" "$path"
}

# Get one key from a STATE file.
# Usage: volley_state_get <path> <key>
volley_state_get() {
  local path=$1 key=$2
  [ -f "$path" ] || { echo "ERROR: STATE file not found: $path" >&2; return 2; }
  local line
  line=$(grep -m1 "^${key}=" "$path") || { echo "ERROR: key $key missing in $path" >&2; return 3; }
  echo "${line#*=}"
}

# Exit non-zero with a clear message if STATE's ACTIVE != expected actor.
# Usage: volley_state_assert_active <path> <expected>
volley_state_assert_active() {
  local path=$1 expected=$2
  local active
  active=$(volley_state_get "$path" ACTIVE) || return 4
  if [ "$active" != "$expected" ]; then
    echo "REFUSED: STATE says ACTIVE=$active but '$expected' tried to act." >&2
    echo "Run /volley:status to inspect, /volley:unlock to clear if stale." >&2
    return 1
  fi
  return 0
}

# Print age of the lock in whole seconds (now - SINCE).
# Usage: volley_state_lock_age <path>
volley_state_lock_age() {
  local path=$1
  local since
  since=$(volley_state_get "$path" SINCE) || return 4
  local since_epoch now_epoch
  since_epoch=$(date -u -d "$since" +%s 2>/dev/null) || since_epoch=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$since" +%s 2>/dev/null) || return 5
  now_epoch=$(date -u +%s)
  echo $(( now_epoch - since_epoch ))
}

# Check if a PID is still running. Returns 0 if alive, non-zero otherwise.
# PID 0 always returns non-zero.
# Usage: volley_state_pid_alive <pid>
volley_state_pid_alive() {
  local pid=$1
  [ -z "$pid" ] && return 1
  [ "$pid" = "0" ] && return 1
  if command -v ps >/dev/null 2>&1; then
    ps -p "$pid" >/dev/null 2>&1
  else
    # Windows fallback via tasklist
    tasklist /FI "PID eq $pid" 2>/dev/null | grep -q "$pid"
  fi
}

# Atomically acquire the repo lock. Echoes an owner token and returns 0 on
# success; returns 1 if the lock is already held by someone else. mkdir is
# atomic on POSIX + Windows filesystems, so exactly one concurrent caller wins.
# Usage: token=$(volley_lock_acquire <statedir> <actor> <task> <pid>) || handle-held
volley_lock_acquire() {
  local dir=$1 actor=$2 task=$3 pid=$4
  local lockd="${dir}/lock.d"
  if mkdir "$lockd" 2>/dev/null; then
    local token; token="${actor}:${pid}:$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '%s\n' "$token" > "${lockd}/owner"
    volley_state_write "${dir}/STATE" "$actor" "$task" "$pid"
    printf '%s\n' "$token"
    return 0
  fi
  return 1
}

# Release the lock ONLY if the caller's token matches the recorded owner
# (so a stale-clear can never delete a different, freshly-acquired lock).
# Usage: volley_lock_release <statedir> <token>
volley_lock_release() {
  local dir=$1 token=$2
  local lockd="${dir}/lock.d"
  [ -d "$lockd" ] || return 0
  local owner
  owner=$(cat "${lockd}/owner" 2>/dev/null)
  if [ "$owner" = "$token" ]; then
    rm -rf "$lockd"
    return 0
  fi
  return 1
}

# Render a Next-step block. Required at the end of every /volley:* command output.
# Usage: volley_next_step <next-command> <reason>
# For multi-option, call volley_next_step_options instead.
volley_next_step() {
  local cmd=$1 reason=$2
  echo ""
  echo "─── Next step ───"
  echo "Run: $cmd"
  echo "Why: $reason"
}

# Render a Next-step block with multiple options.
# Usage: volley_next_step_options "labelA|cmdA|whyA" "labelB|cmdB|whyB" ...
volley_next_step_options() {
  echo ""
  echo "─── Next step ───"
  for opt in "$@"; do
    IFS='|' read -r label cmd why <<< "$opt"
    echo "$label: $cmd  - $why"
  done
}

# Render a Next-step block for terminal states (no further action).
volley_next_step_done() {
  local message=$1
  echo ""
  echo "─── Next step ───"
  echo "None - $message"
}

# ─────────────────────────────────────────────────────────────────────────
# Continuity + model-selection helpers (v0.2)
#
# Config is parsed by the host (Claude), which reads JSON natively - these
# bash helpers only ever receive already-extracted SCALARS (a model name, a
# reasoning level, a stored root/remote). That is deliberate: it keeps a JSON
# parser (jq) off the runtime dependency list. See volley-continuity-review.md
# findings F5/F7.
# ─────────────────────────────────────────────────────────────────────────

# Safe token charset for any value interpolated into a codex command line.
# Model names and reasoning levels are bare identifiers; anything outside this
# set is rejected so untrusted config can never inject shell or argv.
VOLLEY_TOKEN_RE='^[A-Za-z0-9._-]+$'

# Return 0 if the value means "use Codex's own default" (unset or "inherit").
# Usage: volley_is_inherit "$model"
volley_is_inherit() {
  local v="${1:-}"
  [ -z "$v" ] || [ "$v" = "inherit" ]
}

# Validate a model/effort token against VOLLEY_TOKEN_RE.
# Returns non-zero with a clear message on bad input; echoes nothing.
# Usage: volley_validate_token "$value" "model"
volley_validate_token() {
  local value=$1 name=$2
  if ! printf '%s' "$value" | grep -Eq "$VOLLEY_TOKEN_RE"; then
    echo "ERROR: $name '$value' is not a bare identifier ([A-Za-z0-9._-]); refusing to interpolate into a codex command." >&2
    return 1
  fi
  return 0
}

# Build the codex model/effort flag fragment for `codex exec` / the MCP config.
# "inherit"/empty => that flag is omitted (Codex uses its own default).
# Only validated tokens are emitted, so literal insertion into a command
# string is safe on every platform (no spaces/quotes possible).
# Echoes e.g.:  -m gpt-5.6-sol -c model_reasoning_effort=high
# Usage: flags=$(volley_codex_flags "$model" "$effort") || handle-error
volley_codex_flags() {
  local model="${1:-}" effort="${2:-}"
  local out=""
  if ! volley_is_inherit "$model"; then
    volley_validate_token "$model" "model" || return 1
    out="-m $model"
  fi
  if ! volley_is_inherit "$effort"; then
    volley_validate_token "$effort" "reasoningEffort" || return 1
    out="${out:+$out }-c model_reasoning_effort=$effort"
  fi
  printf '%s' "$out"
}

# Canonical git root for a directory (default: cwd). Empty + non-zero if the
# directory is not inside a git repo.
# Usage: root=$(volley_repo_root [dir])
volley_repo_root() {
  local dir="${1:-.}"
  git -C "$dir" rev-parse --show-toplevel 2>/dev/null
}

# Origin remote URL for a directory (default: cwd). Empty if no origin remote.
# Usage: remote=$(volley_repo_remote [dir])
volley_repo_remote() {
  local dir="${1:-.}"
  git -C "$dir" remote get-url origin 2>/dev/null
}

# Guard against cross-project resume: does stored repo identity match the live
# repo? A copied or stale local.json from another checkout must NOT be able to
# resume this repo's (or another repo's) session. Path separators are
# normalized so C:\git\x and C:/git/x compare equal on Windows.
# Remote is compared only when BOTH sides have one (a fresh local clone with no
# origin should still match on root).
# Usage: volley_repo_identity_matches <stored_root> <stored_remote> [dir]
# Returns 0 on match, non-zero on mismatch.
volley_repo_identity_matches() {
  local stored_root=$1 stored_remote=$2 dir="${3:-.}"
  local live_root live_remote
  live_root=$(volley_repo_root "$dir") || return 1
  [ -n "$live_root" ] || return 1
  live_remote=$(volley_repo_remote "$dir")
  local sr="${stored_root//\\//}" lr="${live_root//\\//}"
  [ "$sr" = "$lr" ] || return 1
  if [ -n "$stored_remote" ] && [ -n "$live_remote" ]; then
    [ "$stored_remote" = "$live_remote" ] || return 1
  fi
  return 0
}

# Extract a session/thread id (UUID) from a codex `exec --json` JSONL stream
# or file. Reads the first event that carries an id - Codex emits it in the
# session_meta / session_configured event. Pure grep/sed, no jq.
# Usage: sid=$(volley_session_id_from_jsonl <file>) || handle-error
volley_session_id_from_jsonl() {
  local file=$1
  [ -f "$file" ] || { echo "ERROR: jsonl file not found: $file" >&2; return 2; }
  local id
  id=$(grep -oE '"(session_id|thread_id|threadId|conversationId)":"[0-9a-fA-F-]{36}"' "$file" \
         | head -1 \
         | sed -E 's/.*:"([0-9a-fA-F-]{36})".*/\1/')
  [ -n "$id" ] || { echo "ERROR: no session/thread id found in $file" >&2; return 3; }
  printf '%s' "$id"
}
