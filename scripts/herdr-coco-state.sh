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
# The log can hold prompt text, so keep the directory private to this user.
mkdir -p "$SEQ_DIR" 2>/dev/null || true
chmod 700 "$SEQ_DIR" 2>/dev/null || true
SEQ_FILE="$SEQ_DIR/seq.$HERDR_PANE_ID"
LAST=$(cat "$SEQ_FILE" 2>/dev/null || echo 0)
NOW=$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)
if [ "$NOW" -gt "$LAST" ] 2>/dev/null; then SEQ=$NOW; else SEQ=$(( LAST + 1 )); fi
printf '%s' "$SEQ" > "$SEQ_FILE" 2>/dev/null || true

PAYLOAD=$(cat 2>/dev/null || true)

json_field() {
  # $1 = field name. Python does the parsing. The shell never evaluates it.
  printf '%s' "$PAYLOAD" | python3 -c '
import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
v = d.get(sys.argv[1])
if isinstance(v, (dict, list)):
    v = json.dumps(v)
if v is not None:
    sys.stdout.write(str(v))
' "$1" 2>/dev/null
}

EVENT=$(json_field hook_event_name)
[ -n "$EVENT" ] || EVENT="${1:-}"
SESSION_ID=$(json_field session_id)

# Per-pane event log for troubleshooting ($herdr:doctor reads it).
LOG_FILE="$SEQ_DIR/events.$HERDR_PANE_ID.log"
printf '%s %s tool=%s [plugin]\n' "$(date '+%H:%M:%S')" "$EVENT" "$(json_field tool_name)" >> "$LOG_FILE" 2>/dev/null || true
[ "$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)" -gt 400 ] && tail -n 200 "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null && mv "$LOG_FILE.tmp" "$LOG_FILE" 2>/dev/null

report() {
  # $1 = state, $2 = optional message
  local state="$1" msg="${2:-}"
  local args=( pane report-agent "$HERDR_PANE_ID"
               --source "$SOURCE" --agent "$AGENT"
               --state "$state" --seq "$SEQ" )
  [ -n "$SESSION_ID" ] && args+=( --agent-session-id "$SESSION_ID" )
  # $msg can contain tool output. It is always one quoted argv element.
  [ -n "$msg" ] && args+=( --message "$msg" )
  "$HERDR_BIN_PATH" "${args[@]}" >/dev/null 2>&1 || true
}

case "$EVENT" in
  SessionStart)                            report idle ;;
  UserPromptSubmit|PreToolUse|PostToolUse) report working ;;
  PermissionRequest)
      # Fires when CoCo asks permission to run a tool.
      MSG=$(json_field tool_name)
      report blocked "${MSG:-awaiting approval}" ;;
  Notification)
      # Fires when CoCo asks the user a question (ask_user_question), which
      # PermissionRequest does not cover. Log the first 200 chars of the
      # message so a non-question notification can be identified later. The
      # message can contain prompt text, so it is not sent to Herdr.
      printf '%s   Notification message: %.200s\n' "$(date '+%H:%M:%S')" "$(json_field message)" >> "$LOG_FILE" 2>/dev/null || true
      report blocked "awaiting input" ;;
  Stop)                                    report idle ;;
  SessionEnd)
      # release-agent drops this source's authority for the pane. Herdr
      # applies the same --seq rule as report-agent: a value not above the
      # last accepted one is ignored.
      "$HERDR_BIN_PATH" pane release-agent "$HERDR_PANE_ID" \
        --source "$SOURCE" --agent "$AGENT" --seq "$SEQ" >/dev/null 2>&1 || true ;;
  *) : ;;
esac

exit 0   # never block a CoCo turn
