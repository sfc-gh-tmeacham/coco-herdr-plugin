#!/usr/bin/env bash
# Report Cortex Code lifecycle state to Herdr.
# Does nothing outside a Herdr pane. Never fails the CoCo turn.
# Shipped by the "herdr" CoCo plugin. Invoked via ${CLAUDE_PLUGIN_ROOT}.
set -u

# Guard: act only inside a Herdr-managed pane.
[ "${HERDR_ENV:-}" = "1" ]   || exit 0
[ -n "${HERDR_PANE_ID:-}" ]  || exit 0
[ -n "${HERDR_BIN_PATH:-}" ] || exit 0
[ -x "${HERDR_BIN_PATH}" ]   || exit 0

SOURCE="custom:coco"
AGENT="coco"

# Monotonic sequence per pane. Herdr ignores a report whose --seq is not
# greater than the last one accepted for the same --source, and it keeps
# that value for the life of the server. A per-session counter that restarts
# at 1 is therefore ignored by every session after the first in a pane.
# Use a millisecond timestamp, bumped past the stored value if the clock
# has not advanced, so the sequence rises across sessions and restarts.
SEQ_DIR="${TMPDIR:-/tmp}/herdr-coco"
# The log can hold prompt text, so create the directory private to this user.
[ -d "$SEQ_DIR" ] || (umask 077; mkdir -p "$SEQ_DIR") 2>/dev/null || true
SEQ_FILE="$SEQ_DIR/seq.$HERDR_PANE_ID"
LAST=$(cat "$SEQ_FILE" 2>/dev/null || echo 0)
NOW=$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)
if [ "$NOW" -gt "$LAST" ] 2>/dev/null; then SEQ=$NOW; else SEQ=$(( LAST + 1 )); fi
printf '%s' "$SEQ" > "$SEQ_FILE" 2>/dev/null || true

PAYLOAD=$(cat 2>/dev/null || true)

# One Python call parses the payload and emits the four fields NUL-separated.
# Python does the parsing. The shell never evaluates payload text.
{ IFS= read -r -d '' EVENT; IFS= read -r -d '' SESSION_ID; IFS= read -r -d '' TOOL_NAME; IFS= read -r -d '' MESSAGE; } < <(
  printf '%s' "$PAYLOAD" | python3 -c '
import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
def f(k):
    v = d.get(k)
    if isinstance(v, (dict, list)):
        v = json.dumps(v)
    return "" if v is None else str(v)
sys.stdout.write("\0".join(f(k) for k in ("hook_event_name","session_id","tool_name","message")) + "\0")
' 2>/dev/null ) || true

[ -n "$EVENT" ] || EVENT="${1:-}"

# Per-pane event log for troubleshooting ($herdr:doctor reads it).
LOG_FILE="$SEQ_DIR/events.$HERDR_PANE_ID.log"
printf '%s %s tool=%s [plugin]\n' "$(date '+%H:%M:%S')" "$EVENT" "$TOOL_NAME" >> "$LOG_FILE" 2>/dev/null || true
[ "$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)" -gt 400 ] && tail -n 200 "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null && mv "$LOG_FILE.tmp" "$LOG_FILE" 2>/dev/null

herdr_call() {
  # Runs Herdr and records a failure in the log so $herdr:doctor can see it.
  # The exit code is never propagated.
  local rc=0
  "$HERDR_BIN_PATH" "$@" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 0 ] && return 0
  printf '%s   herdr %s failed rc=%s\n' "$(date '+%H:%M:%S')" "$2" "$rc" >> "$LOG_FILE" 2>/dev/null || true
}

report() {
  # $1 = state, $2 = optional message
  local state="$1" msg="${2:-}"
  local args=( pane report-agent "$HERDR_PANE_ID"
               --source "$SOURCE" --agent "$AGENT"
               --state "$state" --seq "$SEQ" )
  [ -n "$SESSION_ID" ] && args+=( --agent-session-id "$SESSION_ID" )
  # $msg can contain tool output. It is always one quoted argv element.
  [ -n "$msg" ] && args+=( --message "$msg" )
  herdr_call "${args[@]}"
}

case "$EVENT" in
  SessionStart)                            report idle ;;
  UserPromptSubmit|PreToolUse|PostToolUse) report working ;;
  PermissionRequest)
      # Fires when CoCo asks permission to run a tool.
      report blocked "${TOOL_NAME:-awaiting approval}" ;;
  Notification)
      # Fires when CoCo asks the user a question (ask_user_question), which
      # PermissionRequest does not cover. Log the first 200 chars of the
      # message so a non-question notification can be identified later. The
      # message can contain prompt text, so it is not sent to Herdr.
      printf '%s   Notification message: %.200s\n' "$(date '+%H:%M:%S')" "$MESSAGE" >> "$LOG_FILE" 2>/dev/null || true
      report blocked "awaiting input" ;;
  Stop)                                    report idle ;;
  SessionEnd)
      # release-agent drops this source's authority for the pane. Herdr
      # applies the same --seq rule as report-agent: a value not above the
      # last accepted one is ignored.
      herdr_call pane release-agent "$HERDR_PANE_ID" \
        --source "$SOURCE" --agent "$AGENT" --seq "$SEQ" ;;
  *) : ;;
esac

exit 0   # never block a CoCo turn
