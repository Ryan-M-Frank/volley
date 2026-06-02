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

  local qpath; qpath=$(printf %q "$prompt_file")
  tmux new-session -d -s "$session" "cat ${qpath} | codex exec; exec bash"

  echo "tmux:${session}"
}
