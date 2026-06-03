#!/usr/bin/env bash
# Spawn a visible terminal running `codex exec` against a prompt file.
#
# Cross-platform dispatcher. Each platform handler lives at
# scripts/platforms/<platform>.sh and exposes a single function
# `spawn_<platform>(prompt_file, title)` that opens its native terminal
# (or tmux fallback) and streams the prompt to `codex exec` via stdin.
#
# Why stdin (not argv): plan files exceed CreateProcess's ~32K argv limit
# on Windows, and they'll keep growing. File-streamed input sidesteps argv
# length entirely on every platform - future-proof against larger plans.
#
# `codex exec` reads from stdin when no positional prompt is given. It is
# non-interactive but streams progress to the terminal, which is what the
# visible-implementer pattern wants - the user reads along, doesn't type.
#
# Liveness: this script echoes a PID/session identifier. It is INFORMATIONAL
# ONLY. The authoritative liveness signal is the .volley/CODEX-STARTED-<NONCE>
# handshake file Codex creates as its first action - /volley:implement polls
# for that before flipping the STATE lock.
#
# Usage: bash scripts/spawn-codex.sh <prompt-file> [<tab-title>]
# Env overrides:
#   VOLLEY_PLATFORM=<windows|macos|linux|tmux>   force a specific handler
#                                                 (bypasses uname detection;
#                                                 also how tests stub it)

set -euo pipefail

PROMPT_FILE="${1:?prompt file path required}"
TITLE="${2:-volley:codex}"

# Sandbox mode for the spawned `codex exec`. workspace-write lets Codex write the
# handshake marker, progress log, STATE file, and source (all under the repo root)
# while confining writes to the workspace. Override to danger-full-access when a
# task needs network (uncached package restore), or read-only for a dry run.
: "${VOLLEY_CODEX_SANDBOX:=workspace-write}"
case "$VOLLEY_CODEX_SANDBOX" in
  read-only|workspace-write|danger-full-access) ;;
  *) echo "ERROR: VOLLEY_CODEX_SANDBOX must be read-only|workspace-write|danger-full-access (got '$VOLLEY_CODEX_SANDBOX')" >&2; exit 2 ;;
esac
export VOLLEY_CODEX_SANDBOX

[ -f "$PROMPT_FILE" ] || { echo "ERROR: prompt file not found: $PROMPT_FILE" >&2; exit 1; }

VOLLEY_DIR="$(cd "$(dirname "$0")" && pwd)"

detect_platform() {
  case "$(uname -s)" in
    Darwin*) echo macos ;;
    Linux*)
      # WSL: presents as Linux but route to the Windows handler so wt is
      # the host-visible window.
      if grep -qi microsoft /proc/version 2>/dev/null; then
        echo windows
      else
        echo linux
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *) echo unsupported ;;
  esac
}

PLATFORM="${VOLLEY_PLATFORM:-$(detect_platform)}"

if [ "$PLATFORM" = "unsupported" ]; then
  echo "ERROR: unsupported platform '$(uname -s)'. Set VOLLEY_PLATFORM=tmux for the universal tmux fallback." >&2
  exit 2
fi

HANDLER_FILE="${VOLLEY_DIR}/platforms/${PLATFORM}.sh"
if [ ! -f "$HANDLER_FILE" ]; then
  available=$(ls "${VOLLEY_DIR}/platforms" 2>/dev/null | tr '\n' ' ')
  echo "ERROR: no handler for platform '$PLATFORM' (expected $HANDLER_FILE). Available: ${available:-none}" >&2
  exit 3
fi

# shellcheck source=/dev/null
. "$HANDLER_FILE"

"spawn_${PLATFORM}" "$PROMPT_FILE" "$TITLE"
