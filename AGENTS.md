# AGENTS.md

Rules for anyone changing this plugin, human or agent. The README covers install and use. This file covers what the code depends on that is not obvious from reading it.

## Herdr and Cortex facts

These were verified in a live Herdr pane. Any new claim about Herdr or Cortex behaviour must be verified the same way before code relies on it. The stub suite cannot prove it: 0.2.3 passed the `.sh` suite while assuming Herdr clears a row when the process exits.

- Herdr keeps a hook-reported row until `pane release-agent`. It does not clear the row when the Cortex process exits.
- Herdr ignores a `report-agent` or `release-agent` whose `--seq` is not above the last value it accepted for that source, and keeps that value for the life of the server. Seq is therefore a millisecond timestamp, not a per-session counter.
- `SessionEnd` fires when Cortex exits and on an in-process session switch such as `/new`, where `SessionStart` follows (0 to 9 seconds later in the logs so far). It does not fire at the end of a turn. `Stop` does.
- The hook's parent process (`$PPID`) is the `cortex` process, a direct child of the pane shell.

## Hook contract

- Exit 0 on every path. A hook must never fail or block a CoCo turn.
- Outside Herdr, exit 0 and write nothing unless `HERDR_ENV`, `HERDR_PANE_ID`, and `HERDR_BIN_PATH` are all set.
- Call `"$HERDR_BIN_PATH"`, never a `herdr` found on `PATH`.
- Values passed to Herdr on the command line (session ID, tool name) must match `[A-Za-z0-9_.:-]` and must not start with `-`. Prompt and `Notification` text is never sent to Herdr. `tests/run.sh` checks both.
- Every wait is bounded: the seq lock (about 2 s), the watcher (24 h), and the deferred release call (killed after about 10 s).
- Finish well inside the 5 s timeout in `hooks/hooks.json`.
- Anything left running after the hook returns must not hold the hook's stdin, stdout, or stderr.
- `scripts/herdr-coco-state.sh` must run on macOS `/bin/bash` 3.2 with no new dependencies. If the common path gains an external command, add it to the restricted-PATH bin list in `tests/run.sh`.
- Hooks run as `bash "<script>"` because catalog installs drop file modes (see `skills/doctor/SKILL.md`). Do not rely on the executable bit.

## Keep both scripts in step

Every behaviour change goes into both `scripts/herdr-coco-state.sh` and `scripts/herdr-coco-state.ps1`. The `.ps1` has only been run under pwsh on macOS. A PR that changes it should say it is untested on native Windows.

## Seq and release invariants

- Seq allocation (read, compute, write) happens under the per-pane lock (`<seq file>.lock`), and the write is atomic (temp file, then rename). The lock is best-effort: a hook that waits about 2 s takes it over or continues, so it never blocks.
- `SessionEnd` reports `idle` at seq S and stores S+1 in the seq file under the same lock hold. A detached watcher (`<script> __watch <pid> <seq>`) sends `release-agent` at S+1 once the parent process has exited. The tests find and clean up watchers by that argv form, so changing it means changing `tests/run.sh`.
- The watcher exits without releasing when the seq file is missing or holds a value above S+1. Any later hook event therefore cancels the pending release.
- No watcher starts when the parent PID is unresolved or 1.

## Testing

- Run `bash tests/run.sh` and expect `ALL PASS`. It runs the `.sh` under each of `/bin/bash`, `/opt/homebrew/bin/bash`, `/usr/local/bin/bash`, and `/usr/bin/bash` that exists, and the `.ps1` under pwsh. Without pwsh it prints `SKIP ps1` and can still report `ALL PASS`, so install pwsh before trusting the result for a `.ps1` change.
- Write new tests first and show they fail against the current code.
- For a fix to a race or other guard, also show the test fails with the guard disabled.
- Behaviour that depends on Herdr or Cortex needs a live check in a Herdr pane as well.

## Change checklist

- Bump `version` in `.cortex-plugin/plugin.json` when a change to `scripts/`, `hooks/`, or `skills/` alters behaviour, so installs can tell the versions apart.
- When event handling changes, update the README event-mapping table and both tables in `skills/doctor/SKILL.md` together.
- Edit the repository, not the installed copy under `~/.snowflake/cortex/plugins/`. To try a change without installing, run `cortex --plugin-dir <path-to-clone>`.

## Commits and pull requests

- Commit subject in the imperative mood. When a body is needed, wrap it and explain why.
- A PR states the problem, the fix, and how the fix was verified, including what was not verified.
