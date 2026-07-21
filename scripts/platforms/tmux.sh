#!/usr/bin/env bash
# tmux handler for scripts/spawn-codex.sh - the universal/headless fallback.
# Sourced by the dispatcher; exposes spawn_tmux(). Runs `codex exec` inside a
# detached tmux session with the prompt streamed via stdin (same argv-avoiding
# rationale as the other handlers). Liveness is the CODEX-STARTED handshake,
# not the session name echoed here.

spawn_tmux() {
  local prompt_file="$1" title="$2"

  command -v tmux >/dev/null || {
    echo "ERROR: tmux not found in PATH. Install tmux, or set VOLLEY_PLATFORM to a desktop handler (windows/macos/linux)." >&2
    return 127
  }

  local session="volley_${title//[^a-zA-Z0-9_-]/_}"

  local prompt_abs repo_root
  prompt_abs=$(cd "$(dirname "$prompt_file")" && pwd)/$(basename "$prompt_file")
  repo_root=$(pwd)
  local qpath qrepo
  qpath=$(printf %q "$prompt_abs")
  qrepo=$(printf %q "$repo_root")
  # VOLLEY_CODEX_FLAGS (optional): validated `-m`/`-c model_reasoning_effort=`
  # tokens from the dispatcher. Bare identifiers only, so unquoted is safe.
  tmux new-session -d -s "$session" "cat ${qpath} | codex exec ${VOLLEY_CODEX_FLAGS:-} --sandbox ${VOLLEY_CODEX_SANDBOX:-workspace-write} -C ${qrepo} -c approval_policy=never; exec bash"

  echo "tmux:${session}"
}
