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
    local token="${actor}:${pid}:$(date -u +%Y-%m-%dT%H:%M:%SZ)"
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
