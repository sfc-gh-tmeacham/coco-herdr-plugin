---
name: doctor
description: "Diagnose why Cortex Code's status is missing or wrong in the Herdr sidebar. Checks the Herdr environment, the hook event log, and what Herdr reports for this pane, then explains any mismatch. Triggers: herdr doctor, herdr status wrong, coco not showing in herdr, herdr shows blocked, herdr shows working, no coco row in herdr, herdr yellow dot, herdr agent list empty, check herdr integration."
---

# Herdr Doctor

Diagnose the Cortex Code to Herdr status link. Do not change any files. Report
findings and a fix.

## How the link works

1. Herdr starts the pane with `HERDR_ENV=1`, `HERDR_PANE_ID`, `HERDR_BIN_PATH`.
2. On each hook event, `${CLAUDE_PLUGIN_ROOT}/scripts/herdr-coco-state.sh` runs.
3. The script appends one line to `${TMPDIR:-/tmp}/herdr-coco/events.<pane>.log`
   and calls `herdr pane report-agent <pane> --source custom:coco --agent coco`.
4. Herdr accepts the report only if `--seq` is higher than the last one it
   accepted for that pane and source.

Event to state mapping:

| Hook event | State sent |
| --- | --- |
| `SessionStart`, `Stop` | `idle` (Herdr shows `done` after unseen work) |
| `UserPromptSubmit`, `PreToolUse`, `PostToolUse` | `working` |
| `PermissionRequest` (tool approval) | `blocked` |
| `Notification` (question to the user) | `blocked` |
| `SessionEnd` | authority released, row removed |

## Steps

Run each check with `bash`. Stop at the first failing check and report it.

### 1. Am I inside Herdr?

```bash
echo "HERDR_ENV=${HERDR_ENV:-unset} HERDR_PANE_ID=${HERDR_PANE_ID:-unset} HERDR_BIN_PATH=${HERDR_BIN_PATH:-unset}"
```

If any value is `unset`: this CoCo session was not started inside a Herdr pane.
The script exits silently by design. Fix: start `cortex` from a shell inside a
Herdr pane. Stop here.

### 2. Is the plugin script present and executable?

```bash
ls -l "${CLAUDE_PLUGIN_ROOT:-$HOME/.snowflake/cortex/plugins/herdr}/scripts/herdr-coco-state.sh"
```

If missing or not executable: the plugin is not installed correctly. Fix:
`chmod +x` the file, or reinstall the plugin.

### 3. Are hooks firing?

```bash
tail -20 "${TMPDIR:-/tmp}/herdr-coco/events.${HERDR_PANE_ID}.log"
```

If the file does not exist: no hook has run in this pane. Either the plugin is
disabled in Agent Settings > Plugins, or CoCo was started before the plugin was
installed. Hook configuration is read once at session start. Fix: enable the
plugin, then restart CoCo.

If the file exists but the last line is old: the session may be idle. That is
normal.

### 4. What does Herdr believe?

```bash
"$HERDR_BIN_PATH" agent list
"$HERDR_BIN_PATH" pane get "$HERDR_PANE_ID"
```

Compare the `agent_status` with the last event in the log:

| Last event | Expected status |
| --- | --- |
| `SessionStart`, `Stop` | `idle` or `done` |
| `UserPromptSubmit`, `PreToolUse`, `PostToolUse` | `working` |
| `PermissionRequest`, `Notification` | `blocked` |
| `SessionEnd` | no `agent` key; pane absent from `agent list` |

### 5. Interpret a mismatch

**Hooks fire, but no `agent` key and `agent_status: unknown`.** Herdr rejected
the reports as stale. Check the sequence:

```bash
cat "${TMPDIR:-/tmp}/herdr-coco/seq.${HERDR_PANE_ID}"
```

The value should be a 13-digit millisecond timestamp. If it is a small integer,
an old copy of the script is running. Fix: confirm `hooks.json` points at the
plugin script, not an older user-level copy.

**Status is `blocked` but CoCo is visibly working.** Look for a `Notification`
line in the log with its payload. If it was not preceded by
`PreToolUse tool=ask_user_question`, that notification was not a question.
Report the payload. Do not remove `Notification` from the mapping; it is the only
event that fires when CoCo asks the user a question.

**Status is `working` but CoCo is asking a question.** The `Notification` hook
did not fire or is not configured. Check the plugin `hooks/hooks.json` contains
a `Notification` entry.

**Two rows for the same pane, or status flickers.** Two hook configurations are
reporting. Check for a user-level `~/.snowflake/cortex/hooks.json` that also
references `herdr-coco-state.sh`. Fix: remove the duplicate entries.

**`herdr agent explain` returns `agent_explain_unavailable`.** Expected. That
command describes screen-detection state only. CoCo reports through a custom
integration, which has no detection state. Use `agent list` or `pane get`.

## Report format

State each check as PASS or FAIL with the observed value. End with one fix, or
"no fault found" and the current status.
