#!/usr/bin/env bash
# Run one read-only Codex review turn via `codex exec` and capture its session id.
#
# Why this exists: Codex 0.156 removed `codex mcp-server`, which Volley's bundled MCP bridge used.
# Every review (/volley:review-plan, /volley:review-pr, the /volley:setup smoke test) now goes through
# this script instead. It keeps the v0.2 guarantees: read-only sandbox, validated model/effort tokens,
# repo-rooted cwd, and continuity through a saved session id (`codex exec resume <id>`).
#
# Usage:
#   bash scripts/codex-exec.sh --prompt-file <file> --out <file> [--cwd <repo root>]
#                              [--model <m|inherit>] [--effort <e|inherit>] [--resume <session-id>]
#
# Prints, as its last lines:
#   SESSION_ID=<uuid>            (empty if Codex reported none)
#   CONTINUITY=fresh | resumed | fallback:resume-failed | fallback:invalid-session-id
# The --json event stream of the attempt that produced the review is saved to "<out>.events.jsonl".
#
# Exit codes: 0 ok; 2 usage/config error (Codex not called); 3 Codex succeeded but wrote no review;
# otherwise Codex's own exit code. VOLLEY_CODEX_BIN overrides the codex binary (tests use a fake).

set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

usage_error() { echo "ERROR: $*" >&2; exit 2; }

prompt="" out="" cwd="" model="" effort="" resume=""
while [ $# -gt 0 ]; do
  case "$1" in
    --prompt-file|--out|--cwd|--model|--effort|--resume)
      [ $# -ge 2 ] || usage_error "$1 needs a value"
      case "$1" in
        --prompt-file) prompt=$2 ;;
        --out)         out=$2 ;;
        --cwd)         cwd=$2 ;;
        --model)       model=$2 ;;
        --effort)      effort=$2 ;;
        --resume)      resume=$2 ;;
      esac
      shift 2 ;;
    *) usage_error "unknown argument: $1" ;;
  esac
done

# Resolve paths against the caller's directory once, before anything changes directory.
abspath() {
  case "$1" in
    /*|[A-Za-z]:[\\/]*) printf '%s' "$1" ;;
    *) printf '%s/%s' "$PWD" "$1" ;;
  esac
}

[ -n "$prompt" ] && [ -f "$prompt" ] || usage_error "--prompt-file missing or not found: ${prompt:-<none>}"
[ -n "$out" ] || usage_error "--out is required"
prompt=$(abspath "$prompt")
out=$(abspath "$out")
if [ -z "$cwd" ]; then cwd=$(volley_repo_root) || true; fi
[ -n "$cwd" ] && [ -d "$cwd" ] || usage_error "--cwd missing and not inside a git repo"

# Model/effort go in as separate, validated argv entries (never a word-split string).
model_args=()
if ! volley_is_inherit "$model"; then
  volley_validate_token "$model" "model" || exit 2
  model_args+=(-m "$model")
fi
if ! volley_is_inherit "$effort"; then
  volley_validate_token "$effort" "reasoningEffort" || exit 2
  model_args+=(-c "model_reasoning_effort=$effort")
fi

bin="${VOLLEY_CODEX_BIN:-codex}"
events="${out}.events.jsonl"
mkdir -p "$(dirname "$out")" || usage_error "cannot create the output directory for $out"
# A review from an earlier run must never be mistaken for this run's output.
rm -f "$out" "$events" || usage_error "cannot remove the previous review at $out"

attempt_out="${out}.attempt"
attempt_events="${events}.attempt"
# Scratch files never outlive the script, whatever path it exits by (they can hold repo excerpts).
trap 'rm -f "$attempt_out" "$attempt_events"' EXIT
# Note: model_args is expanded as ${model_args[@]+"${model_args[@]}"} because bash 3.2 (macOS)
# treats "${arr[@]}" of an EMPTY array as unbound under set -u.

# Each attempt writes to its own scratch files; only a successful, non-empty attempt is published.
run_fresh() {
  rm -f "$attempt_out" "$attempt_events"
  "$bin" exec ${model_args[@]+"${model_args[@]}"} --sandbox read-only -C "$cwd" --json -o "$attempt_out" - \
    < "$prompt" > "$attempt_events"
}
run_resume() {
  rm -f "$attempt_out" "$attempt_events"
  # `exec resume` accepts neither --sandbox nor -C: read-only is enforced through config, and the
  # `cd` is load-bearing - Codex finds the saved session by filtering on the current directory.
  ( cd "$cwd" && "$bin" exec resume ${model_args[@]+"${model_args[@]}"} -c 'sandbox_mode="read-only"' --json \
      -o "$attempt_out" "$resume" - < "$prompt" > "$attempt_events" )
}
publish() {
  [ -s "$attempt_out" ] || return 1
  mv -f "$attempt_out" "$out" && mv -f "$attempt_events" "$events"
}
fresh_or_die() {
  run_fresh; local rc=$?
  if [ "$rc" -ne 0 ]; then
    rm -f "$attempt_out"
    echo "ERROR: codex exec failed (exit $rc)" >&2; exit "$rc"
  fi
}

uuid_re='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
continuity="fresh"
if [ -n "$resume" ]; then
  if [[ $resume =~ $uuid_re ]]; then
    if run_resume && [ -s "$attempt_out" ]; then
      continuity="resumed"
    else
      echo "WARN: resuming session $resume failed; starting a fresh session (context comes from files)." >&2
      continuity="fallback:resume-failed"
      fresh_or_die
    fi
  else
    echo "WARN: saved session id is not a UUID; ignoring it and starting fresh." >&2
    continuity="fallback:invalid-session-id"
    fresh_or_die
  fi
else
  fresh_or_die
fi

if ! publish; then
  rm -f "$attempt_out" "$attempt_events"
  echo "ERROR: Codex finished but wrote no review to $out" >&2
  exit 3
fi

sid=$(volley_session_id_from_jsonl "$events" 2>/dev/null) || sid=""
[ -n "$sid" ] || echo "WARN: no session id in Codex output; the next review will start fresh." >&2
echo "SESSION_ID=$sid"
echo "CONTINUITY=$continuity"
