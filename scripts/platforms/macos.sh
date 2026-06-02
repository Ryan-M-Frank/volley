#!/usr/bin/env bash
# macOS handler for scripts/spawn-codex.sh. Sourced by the dispatcher; exposes
# spawn_macos(). Opens a new terminal window (iTerm2 if running/installed, else
# Terminal.app) running `codex exec` with the prompt streamed via stdin.

spawn_macos() {
  local prompt_file="$1" title="$2"

  command -v osascript >/dev/null || {
    echo "ERROR: osascript not found - spawn_macos requires macOS. Set VOLLEY_PLATFORM=tmux for the universal fallback." >&2
    return 127
  }

  local qpath; qpath=$(printf %q "$prompt_file")
  local inner="cat ${qpath} | codex exec"

  if osascript -e 'tell application "System Events" to (name of processes) contains "iTerm2"' 2>/dev/null | grep -qi true \
     || [ -d "/Applications/iTerm.app" ]; then
    osascript >/dev/null 2>&1 <<OSA || { echo "ERROR: failed to launch iTerm2" >&2; return 1; }
tell application "iTerm"
  set newWindow to (create window with default profile)
  tell current session of newWindow
    set name to "${title}"
    write text "${inner}"
  end tell
end tell
OSA
  else
    osascript >/dev/null 2>&1 <<OSA || { echo "ERROR: failed to launch Terminal.app" >&2; return 1; }
tell application "Terminal"
  do script "${inner}"
  activate
end tell
OSA
  fi

  echo "macos:${title}"
}
