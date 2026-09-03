---
name: doctor
description: "Diagnose why Cortex Code's status is missing or wrong in the Herdr sidebar. Checks the Herdr environment, the hook event log, and what Herdr reports for this pane, then explains any mismatch. Triggers: herdr doctor, herdr status wrong, coco not showing in herdr, herdr shows blocked, herdr shows working, no coco row in herdr, herdr yellow dot, herdr agent list empty, check herdr integration."
---

# Herdr Doctor

Diagnose the Cortex Code to Herdr status link. Do not change any files. Report
findings and a fix.

## How the link works

1. Herdr starts the pane with `HERDR_ENV=1`, `HERDR_PANE_ID`, `HERDR_BIN_PATH`.
2. On each hook event, CoCo runs the plugin script for the current platform:
   `scripts/herdr-coco-state.sh` on macOS and Linux, `scripts/herdr-coco-state.ps1`
   on Windows.
3. The script appends one line to the event log and calls
   `herdr pane report-agent <pane> --source custom:coco --agent coco`.
   - macOS/Linux log: `${TMPDIR:-/tmp}/herdr-coco/events.<pane>.log`
   - Windows log: `%TEMP%\herdr-coco\events.<pane>.log`, where `:` in the pane
     ID is replaced by `_` (for example `events.w1_p1.log`).
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

Run each check with `bash` on macOS and Linux, or with PowerShell on Windows.
Stop at the first failing check and report it.

### 1. Am I inside Herdr?

```bash
echo "HERDR_ENV=${HERDR_ENV:-unset} HERDR_PANE_ID=${HERDR_PANE_ID:-unset} HERDR_BIN_PATH=${HERDR_BIN_PATH:-unset}"
```

```powershell
"HERDR_ENV=$env:HERDR_ENV HERDR_PANE_ID=$env:HERDR_PANE_ID HERDR_BIN_PATH=$env:HERDR_BIN_PATH"
```

If any value is `unset` or empty: this CoCo session was not started inside a Herdr pane.
The script exits silently by design. Fix: start `cortex` from a shell inside a
Herdr pane. Stop here.

### 2. Is the plugin script present and executable?

Find the plugin root first. It is the `Path:` line for `herdr` in:

```bash
cortex plugin list
```

Then check the script under that root (`<root>` below):

```bash
ls -l "<root>/scripts/herdr-coco-state.sh"
```

```powershell
Get-Item "<root>\scripts\herdr-coco-state.ps1"
```

If missing or (on macOS/Linux) not executable: the plugin copy is damaged. Fix:
`cortex plugin update herdr`, which re-fetches the files with their modes from
git. Do not `chmod` the managed copy; the next update overwrites it.

### 3. Are hooks firing?

```bash
tail -20 "${TMPDIR:-/tmp}/herdr-coco/events.${HERDR_PANE_ID}.log"
```

```powershell
Get-Content "$env:TEMP\herdr-coco\events.$($env:HERDR_PANE_ID -replace ':','_').log" -Tail 20
```

If the file does not exist: no hook has run in this pane. Either the plugin is
disabled (`cortex plugin list`), or CoCo was started before the plugin was
installed. Hook configuration is read once at session start. Fix: enable the
plugin, then restart CoCo.

If the file exists but the last line is old: the session may be idle. That is
normal.

### 4. What does Herdr believe?

```bash
"$HERDR_BIN_PATH" agent list
"$HERDR_BIN_PATH" pane get "$HERDR_PANE_ID"
```

```powershell
& $env:HERDR_BIN_PATH agent list
& $env:HERDR_BIN_PATH pane get $env:HERDR_PANE_ID
```

Compare the `agent_status` with the last event in the log:

| Last event | Expected status |
| --- | --- |
| `SessionStart`, `Stop` | `idle` or `done` |
| `UserPromptSubmit`, `PreToolUse`, `PostToolUse` | `working` |
| `PermissionRequest`, `Notification` | `blocked` |
| `SessionEnd` | no `agent` key; pane absent from `agent list` |

Also scan the log for lines of the form `herdr report-agent failed rc=N`. They
mean the hook ran and the binary launched, but Herdr rejected the call (or the
binary is not runnable, `rc=-1` or `rc=126/127`). Check `herdr status` and
compare the server version with the tested Herdr version in the README. The
`report-agent` flag surface is version-sensitive.

### 5. Interpret a mismatch

**Hooks fire, but no `agent` key and `agent_status: unknown`.** Herdr rejected
the reports as stale. Check the sequence:

```bash
cat "${TMPDIR:-/tmp}/herdr-coco/seq.${HERDR_PANE_ID}"
```

```powershell
Get-Content "$env:TEMP\herdr-coco\seq.$($env:HERDR_PANE_ID -replace ':','_')"
```

The value should be a 13-digit millisecond timestamp. If it is a small integer,
an old copy of the script is running. Fix: confirm `hooks.json` points at the
plugin script.

**Status is `blocked` but CoCo is visibly working.** Look for a `Notification`
line in the log followed by its `Notification message:` line. If it was not
preceded by `PreToolUse tool=ask_user_question`, that notification was not a
question. Report the message text. Do not remove `Notification` from the mapping;
it is the only event that fires when CoCo asks the user a question.

**Status is `working` but CoCo is asking a question.** The `Notification` hook
did not fire or is not configured. Check the plugin `hooks/hooks.json` contains
a `Notification` entry.

**Permission message says `awaiting approval` instead of a tool name, or a log
line reads `Notification message: # python3 absent`.** On macOS/Linux the hook
is running its `grep` fallback because `python3` is not on `PATH`. State
reporting still works. Install `python3` for full payload parsing.

**Two rows for the same pane, or status flickers.** Two hook configurations are
reporting. Check for another hooks file (for example `~/.snowflake/cortex/hooks.json`)
that also references `herdr-coco-state`. Fix: remove the duplicate entries.

**Windows: hooks never fire.** CoCo runs the hook as
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File <script>.ps1`. Check that
`powershell.exe` is on `PATH` and that `$env:HERDR_BIN_PATH` points at an existing
`herdr.exe`.

**`herdr agent explain` returns `agent_explain_unavailable`.** Expected. That
command reports which screen-detection rule matched the pane text. Herdr has no
detection manifest for `cortex`, and a pane with a `custom:coco` report is not
screen-detected at all, so there is nothing to explain. Use `agent list`,
`pane get`, or the event log in step 3.

## Report format

State each check as PASS or FAIL with the observed value. End with one fix, or
"no fault found" and the current status.
