# coco-herdr-plugin

## What these tools are

**[Herdr](https://herdr.dev/docs/)** is a terminal multiplexer for coding agents. You run each agent in its
own pane. Its primary benefits:

- **Agents keep running.** Herdr is a background server that owns the terminals. Close the client,
  the lid, or the network connection, and the agents continue. You can attach again later.
- **You see who is stuck.** A sidebar shows the live state of every pane: `idle`, `working`,
  `blocked`, or `done`. You do not need to check each pane to find the one that waits on you.
- **Agents can drive it.** The `herdr` CLI and socket API let an agent split panes, start other
  agents, send them prompts, and wait until they are blocked.

**[Cortex Code](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code)** (CoCo) is
Snowflake's agentic coding assistant. The
[`cortex` CLI](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code-cli) runs it in a
terminal. Its primary benefits:

- **It works on files and data in one session.** It reads and edits files, runs shell commands, and
  runs SQL against a Snowflake account.
- **It knows Snowflake.** Bundled skills cover Snowflake features such as semantic views, dynamic
  tables, Streamlit, and Cortex Agents, so requests use the correct native tooling.
- **It is extensible.** Plugins add skills, hooks, subagents, and MCP servers to a session. This
  plugin is one example.

## What this plugin does

Herdr does not recognize `cortex` as an agent. A CoCo pane appears in Herdr with no label and no
state. This plugin closes that gap from the CoCo side, with **no changes to Herdr's source code**.
It reports CoCo's state to Herdr through a hook, and it bundles two skills.

| Component | What it does |
| --- | --- |
| `hooks/hooks.json` + `scripts/herdr-coco-state.sh` | Reports CoCo's live state to Herdr: `idle`, `working`, `blocked`, `done`. The CoCo pane appears in the Herdr sidebar and in `herdr agent list` as agent `coco`. |
| `skills/control` | Herdr's own agent-control skill (`herdr --skill`), bundled unchanged, so a CoCo session can inspect and drive other Herdr panes. Invoke with `$herdr:control`. |
| `skills/doctor` | Diagnoses a missing or wrong status. Checks the environment, the hook event log, and what Herdr reports, then names the fix. Invoke with `$herdr:doctor`. |

## Quick start

Before you start, install [Herdr](https://herdr.dev/docs/install/) and the
[CoCo CLI](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code-cli). This plugin does
not install either one.

1. Install the plugin:

   ```bash
   cortex plugin install sfc-gh-tmeacham/coco-herdr-plugin
   ```

2. Confirm that `herdr` is listed and active:

   ```bash
   cortex plugin list
   ```

3. Start Herdr, then start a new CoCo session in a Herdr pane:

   ```bash
   cortex
   ```

4. From any other shell, confirm that Herdr sees the pane as agent `coco`:

   ```bash
   herdr agent list
   ```

See [Requirements](#requirements) and [Install](#install) for details and edge cases.

**Fun tip.** To get an idea of what Herdr can do, start `cortex` in a Herdr pane, then give CoCo
this prompt:

> use Herdr to split 10 other panes that make my computer look like some scifi hacker terminal from the movies

## Requirements

The plugin does not install Herdr or the CoCo CLI. It only adds a hook and two skills to a CoCo
session. You must install both tools first:

- [Herdr](https://herdr.dev/docs/install/) 0.8.2 (tested; the `report-agent` CLI surface is version-sensitive)
- [CoCo CLI](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code-cli) v1.1.76 or later (tested on 1.1.78)
- macOS or Linux. `python3` on `PATH`.
- Windows is not supported. Herdr uses a named pipe there and the script is POSIX shell.

## Install

Install from GitHub with the CoCo CLI:

```bash
cortex plugin install sfc-gh-tmeacham/coco-herdr-plugin
```

This clones the repository into `~/.snowflake/cortex/plugins/` and registers it in
`registry.json` there. Confirm with `cortex plugin list`. To get a later version, run
`cortex plugin update herdr`.

To work on the plugin locally without installing it, clone the repository and start CoCo with
`cortex --plugin-dir <path-to-clone>`.

Hook configuration is read once, when a CoCo session starts. A CoCo session that is already running
does not see a new plugin. Start a **new** `cortex` session inside a Herdr pane after installing, or
run `/plugin reload` in the running session.

## Use

Start Herdr from any terminal. This starts the background server if it is not running, and attaches
the client:

```bash
herdr
```

Then, in a Herdr pane:

```bash
cortex
```

That is all. From any other shell:

```bash
herdr agent list
```

| CoCo is | Herdr shows |
| --- | --- |
| Waiting for your first prompt | `idle` |
| Thinking or running tools | `working` |
| Asking permission to run a tool | `blocked` |
| Asking you a question | `blocked` |
| Finished a turn you have not looked at yet | `done` |
| Exited | Row removed |

### Shut down Herdr

Herdr runs as a background server. Closing the client window does not stop it. There are two ways
to leave:

- **Detach.** Press `ctrl+b q` in the Herdr client. The server, the panes, and every CoCo session
  in them keep running. Run `herdr` again to attach.
- **Stop the server.** From any shell:

  ```bash
  herdr server stop
  ```

  This ends every pane process, including running CoCo sessions. Herdr saves the layout
  (workspaces, tabs, panes, directories) and restores it as new shells on the next start. It does
  not resume CoCo sessions, because Herdr has no native `cortex` integration. Run
  `cortex resume --last` in the restored pane instead.

To check whether a server is running, use `herdr status`.

## How it works

Herdr injects `HERDR_ENV=1`, `HERDR_PANE_ID`, and `HERDR_BIN_PATH` into every pane it manages. CoCo
runs the plugin's hook script on each lifecycle event and passes the event as JSON on stdin. The
script maps the event to a Herdr state and calls:

```
herdr pane report-agent <pane> --source custom:coco --agent coco --state <state> --seq <n>
```

Herdr treats a reporting custom integration as the single authority for that pane and stops screen
detection for it. This is a documented Herdr escape hatch, not a workaround.

Event mapping:

| CoCo hook event | Herdr state |
| --- | --- |
| `SessionStart`, `Stop` | `idle` |
| `UserPromptSubmit`, `PreToolUse`, `PostToolUse` | `working` |
| `PermissionRequest` | `blocked` |
| `Notification` | `blocked` |
| `SessionEnd` | `release-agent` |

Two details matter and were both found by live testing:

- **Sequence numbers must rise across sessions.** Herdr remembers the highest `--seq` per pane for
  the life of its server. A counter that restarts at 1 for each new CoCo session is silently
  ignored. The script uses a millisecond timestamp.
- **`Notification` is required.** When CoCo asks the user a question (`ask_user_question`), only
  `Notification` fires; `PermissionRequest` does not. Removing `Notification` makes a waiting CoCo
  look `working`.

## Safety

- The script exits immediately unless all three `HERDR_*` variables are present. Outside Herdr it
  is a no-op.
- It calls `"$HERDR_BIN_PATH"` directly, never a `herdr` found on `PATH`.
- Hook payload text (which can contain tool output) is parsed by Python and passed to Herdr as a
  single quoted argument. An injection payload was tested and stayed inert.
- It always exits 0. A Herdr outage cannot block a CoCo turn.

## Troubleshooting

Run `$herdr:doctor` inside the CoCo session. It reads the per-pane event log at
`${TMPDIR:-/tmp}/herdr-coco/events.<pane>.log` and compares it with Herdr's view.

`herdr agent explain <pane>` returns `agent_explain_unavailable` for CoCo panes. That is expected:
the command describes screen-detection state, and a custom integration has none.

## What this does not do

These need a change to Herdr's Rust source and are out of scope:

- `herdr agent start --kind cortex`
- `herdr integration install cortex`
- Automatic resume of CoCo sessions after `herdr server stop`. Use `cortex resume --last` in a new
  pane instead.

## Verification status

| Claim | Status |
| --- | --- |
| Script produces correct `report-agent` calls for every event | Verified against a stub |
| Herdr accepts the calls and updates the pane | Verified against a live Herdr 0.8.2 server |
| `idle`, `working`, `blocked` (permission), `blocked` (question), `Stop` from a real CoCo session | Verified |
| Two CoCo panes reporting independently | Verified |
| Row removed on real `/exit` | Verified by hand-driven `SessionEnd`; not yet from a real exit |
| Persistence across closing the Herdr client | Verified |
| Plugin-packaged hook fires | Not yet tested |

## License

Apache-2.0. Herdr is Apache-2.0; `skills/control/SKILL.md` reproduces Herdr's bundled skill text.

## Disclaimer

This is a personal, community project. It is not an official Snowflake product and Snowflake does
not support, endorse, or maintain it. It is not affiliated with Herdr, Inc. The software is provided
"as is", without warranty of any kind, express or implied. Use it at your own risk. Test it in a
non-production environment before you depend on it. Snowflake, Cortex Code, and Herdr are trademarks
of their respective owners.
