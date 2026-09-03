#!/usr/bin/env bash
# Stub tests for both hook scripts. Runs each script against a fake herdr that
# records argv, then checks the calls, the event log, and the seq file.
# Usage: bash tests/run.sh          (pwsh is needed for the .ps1 checks)
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
check() { if [ "$1" = "$2" ]; then echo "PASS $3"; else echo "FAIL $3: got [$1] want [$2]"; fail=1; fi; }
INJ='x; rm -rf / && echo $(whoami) `id` | cat'

kinds="sh"
if command -v pwsh >/dev/null 2>&1; then kinds="sh ps1"; else echo "SKIP ps1 (pwsh not installed)"; fi

for kind in $kinds; do
  T=$(mktemp -d); STUB="$T/stub.sh"; ARGV="$T/argv.log"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do printf "%%s\\n" "$a"; done >> %s\nprintf -- "--\\n" >> %s\n[ -f %s/fail ] && exit 3\nexit 0\n' "$ARGV" "$ARGV" "$T" > "$STUB"; chmod +x "$STUB"
  export TMPDIR="$T"
  run() { # $1 payload, $2 label, $3 optional extra env
    if [ "$kind" = sh ]; then printf '%s' "$1" | env HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HERDR_BIN_PATH="$STUB" ${3:-} bash "$R/scripts/herdr-coco-state.sh"
    else printf '%s' "$1" | env HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HERDR_BIN_PATH="$STUB" ${3:-} pwsh -NoProfile -File "$R/scripts/herdr-coco-state.ps1"; fi
    check "$?" "0" "$kind: exit 0 ($2)"
  }
  echo "== $kind"

  # No-op guard: no HERDR_* vars, nothing written.
  if [ "$kind" = sh ]; then printf '{"hook_event_name":"Stop"}' | bash "$R/scripts/herdr-coco-state.sh"; else printf '{"hook_event_name":"Stop"}' | pwsh -NoProfile -File "$R/scripts/herdr-coco-state.ps1"; fi
  check "$?" "0" "$kind: exit 0 outside Herdr"
  check "$(ls "$T" | grep -c herdr-coco)" "0" "$kind: no files written outside Herdr"

  run '{"hook_event_name":"SessionStart","session_id":"s1"}' SessionStart
  run '{"hook_event_name":"UserPromptSubmit","session_id":"s1"}' UserPromptSubmit
  run '{"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"bash","tool_input":{"command":"ls"}}' PreToolUse
  run '{"hook_event_name":"PostToolUse","session_id":"s1","tool_name":"bash"}' PostToolUse
  run '{"hook_event_name":"PermissionRequest","session_id":"s1","tool_name":"edit"}' PermissionRequest
  run "{\"hook_event_name\":\"Notification\",\"session_id\":\"s1\",\"message\":\"$INJ\"}" Notification
  run 'garbage' garbage
  touch "$T/fail"
  run '{"hook_event_name":"Stop","session_id":"s1"}' Stop-failing
  rm "$T/fail"
  run '{"hook_event_name":"SessionEnd","session_id":"s1"}' SessionEnd

  if [ "$kind" = sh ]; then LOG="$T/herdr-coco/events.w1:p1.log"; SEQF="$T/herdr-coco/seq.w1:p1"; else LOG="$T/herdr-coco/events.w1_p1.log"; SEQF="$T/herdr-coco/seq.w1_p1"; fi
  states=$(grep -A1 -x -- '--state' "$ARGV" | grep -vx -e '--state' -e '--' | tr '\n' ' ')
  check "$states" "idle working working working blocked blocked idle " "$kind: state sequence"
  check "$(grep -c '^s1$' "$ARGV")" "7" "$kind: session id on every report"
  check "$(grep -c '^edit$' "$ARGV")" "1" "$kind: tool name as permission message"
  check "$(grep -c '^awaiting input$' "$ARGV")" "1" "$kind: fixed phrase as notification message"
  check "$(grep -c 'whoami' "$ARGV")" "0" "$kind: prompt text not sent to Herdr"
  check "$(grep -c '^w1:p1$' "$ARGV")" "8" "$kind: pane id verbatim"
  check "$(grep -c '^release-agent$' "$ARGV")" "1" "$kind: release-agent sent once"
  seqs=$(grep -A1 -x -- '--seq' "$ARGV" | grep -vx -e '--seq' -e '--')
  prev=0; mono=yes; for s in $seqs; do [ "$s" -gt "$prev" ] || mono=no; prev=$s; done
  check "$mono" "yes" "$kind: seq strictly increasing"
  check "${#prev}" "13" "$kind: seq is a 13-digit ms timestamp"
  check "$(grep -c ' \[plugin\]$' "$LOG")" "9" "$kind: one log line per event"
  check "$(grep -c 'PreToolUse tool=bash' "$LOG")" "1" "$kind: tool name logged"
  check "$(grep -c 'Notification message: x; rm -rf' "$LOG")" "1" "$kind: notification message logged"
  check "$(grep -c 'herdr report-agent failed rc=3' "$LOG")" "1" "$kind: failed herdr call logged"
  echo 9999999999999 > "$SEQF"
  run '{"hook_event_name":"Stop"}' clock-stall
  check "$(cat "$SEQF")" "10000000000000" "$kind: seq bumped past stored value"
  if [ "$kind" = sh ]; then
    check "$(stat -f %Lp "$T/herdr-coco" 2>/dev/null || stat -c %a "$T/herdr-coco")" "700" "sh: log dir mode 700"
    # No python3 on PATH: script must still exit 0 and fall back to $1 for the event.
    mkdir -p "$T/bin"; for b in bash cat date wc tail mv mkdir; do ln -s "$(command -v $b)" "$T/bin/$b"; done
    : > "$ARGV"
    printf '{"hook_event_name":"Stop"}' | env HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HERDR_BIN_PATH="$STUB" PATH="$T/bin" "$T/bin/bash" "$R/scripts/herdr-coco-state.sh" Stop
    check "$?" "0" "sh: exit 0 without python3"
    check "$(grep -c '^idle$' "$ARGV")" "1" "sh: falls back to argv event without python3"
  fi
  rm -rf "$T"
done
[ $fail = 0 ] && echo "ALL PASS" || { echo "SOME FAIL"; exit 1; }
