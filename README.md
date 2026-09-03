# coco-herdr-plugin

## What these tools are

**[Herdr](https://herdr.dev/docs/)** is a terminal multiplexer for coding agents.

A terminal multiplexer runs many terminal sessions inside one window and keeps them alive in a
background process. You split the window into panes, put a different program in each, and switch
between them. If you close the window, the programs keep running, and you can reconnect later from
the same machine or over SSH. `tmux` and `screen` are the classic examples. The value for coding
agents: one agent per pane, all visible at once, none of them lost when your laptop sleeps or your
connection drops.

Herdr adds agent awareness on top of that. You run each agent in its own pane. Its primary benefits:

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
| `hooks/hooks.json` + `scripts/herdr-coco-state.sh` (macOS, Linux) / `scripts/herdr-coco-state.ps1` (Windows) | Reports CoCo's live state to Herdr: `idle`, `working`, `blocked`, `done`. The CoCo pane appears in the Herdr sidebar and in `herdr agent list` as agent `coco`. |
| `skills/control` | Herdr's own agent-control skill (`herdr --skill`), bundled unchanged, so a CoCo session can inspect and drive other Herdr panes. Invoke with `$coco-herdr-plugin:control`. |
| `skills/doctor` | Diagnoses a missing or wrong status. Checks the environment, the hook event log, and what Herdr reports, then names the fix. Invoke with `$coco-herdr-plugin:doctor`. |

## Quick start

Before you start, install [Herdr](https://herdr.dev/docs/install/) and the
[CoCo CLI](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code-cli). This plugin does
not install either one.

1. Install the plugin:

   ```bash
   cortex plugin install sfc-gh-tmeacham/coco-herdr-plugin
   ```

2. Confirm that `coco-herdr-plugin` is listed and active:

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
- [CoCo CLI](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code-cli) v1.1.76 or later (tested on 1.1.79)
- macOS or Linux: `bash`. `python3` on `PATH` is recommended but not required. With it, the hook
  parses the payload as JSON. Without it, a `grep`-based fallback reads the event name, session ID,
  and tool name; the free-text message is not parsed.
- Windows (native): Windows PowerShell 5.1 or PowerShell 7. The hook runs as a `.ps1` script.
  See [Herdr on Windows](https://herdr.dev/docs/windows-beta/) and the
  [CoCo CLI Windows install](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code-cli#windows-native).
  The Windows path is verified against a stub only, not on a Windows machine. See
  [Verification status](#verification-status).
- WSL works as Linux.

## Install

There are two sources: GitHub, and the Snowflake Skills & Plugins catalog inside your account.

### From GitHub

```bash
cortex plugin install sfc-gh-tmeacham/coco-herdr-plugin
```

This clones the repository into `~/.snowflake/cortex/plugins/` and registers it in
`registry.json` there. Confirm with `cortex plugin list`. To get a later version, run
`cortex plugin update coco-herdr-plugin`.

### From the Snowflake catalog

If someone in your Snowflake account has shared this plugin to the
[Skills & Plugins catalog](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code-plugins),
you can install it from there. Every shared plugin has a catalog URI of the form
`snow://skill_catalog/<DB>.<SCHEMA>.COCO_HERDR_PLUGIN`, where `<DB>` and `<SCHEMA>` belong to the person who
shared it (for example `USER$<NAME>.SKILL_SHARING`). Any of these paths works:

- **Ask CoCo.** In a CoCo session, say `find the herdr plugin in the catalog`. CoCo has a bundled
  skill that searches the catalog, confirms the match, and installs it.
- **CoCo CLI.** Search, then install by catalog URI. The catalog is per Snowflake account, so
  add `-c <connection>` if your default connection points at a different account:

  ```bash
  cortex plugin find herdr -c <connection>
  cortex plugin install snow://skill_catalog/<DB>.<SCHEMA>.COCO_HERDR_PLUGIN -c <connection>
  ```

- **Snowsight.** Open **AI & ML > Skills & Plugins**, find `COCO_HERDR_PLUGIN`, and copy its catalog URI.
  Paste the URI into a CoCo session, or into **Agent Settings > Plugins** in CoCo Desktop.

A catalog install tracks the catalog entry, not GitHub. When the sharer publishes a new version, pull
it with:

```bash
cortex plugin update coco-herdr-plugin -c <connection>
```

### Local development

To work on the plugin without installing it, clone the repository and start CoCo with
`cortex --plugin-dir <path-to-clone>`.

### After any install

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

### Skills

The plugin adds two skills to every CoCo session. Both work only inside a Herdr pane. Type the
skill name in the CoCo prompt to load it, or list all skills with `/skill list`.

**`$coco-herdr-plugin:control`** is Herdr's own agent-control skill, the text that `herdr --skill` prints,
bundled unchanged. It teaches CoCo the `herdr` CLI so it can split panes, run commands in them,
start and prompt other agents, read their output, and wait for them to finish. CoCo loads it on its
own when a prompt mentions Herdr. Example prompts:

> $coco-herdr-plugin:control split a pane to the right and run the test suite there. Tell me when it finishes.

> use Herdr to start a Codex agent in a new pane and ask it to review the current diff

> $coco-herdr-plugin:control list every agent that is blocked and show me what each one is waiting for

**`$coco-herdr-plugin:doctor`** diagnoses the status link between CoCo and Herdr. It checks the `HERDR_*`
environment, the plugin script, the per-pane event log, and what Herdr reports for the pane, then
states each check as PASS or FAIL and names one fix. Use it when the sidebar shows no `coco` row,
or a state that does not match what CoCo is doing:

> $coco-herdr-plugin:doctor

> $coco-herdr-plugin:doctor Herdr says working but CoCo is waiting for me

## How it works

Herdr injects `HERDR_ENV=1`, `HERDR_PANE_ID`, and `HERDR_BIN_PATH` into every pane it manages. CoCo
runs the plugin's hook script on each lifecycle event and passes the event as JSON on stdin. Each
hook entry in `hooks/hooks.json` carries a `platform` list, so CoCo runs `herdr-coco-state.sh` on
macOS and Linux and `herdr-coco-state.ps1` on Windows. Both scripts map the event to a Herdr state
and call:

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
  ignored. The scripts use a millisecond timestamp.
- **`Notification` is required.** When CoCo asks the user a question (`ask_user_question`), only
  `Notification` fires; `PermissionRequest` does not. Removing `Notification` makes a waiting CoCo
  look `working`.

## Safety

- The scripts exit immediately unless all three `HERDR_*` variables are present. Outside Herdr they
  are no-ops.
- They call `"$HERDR_BIN_PATH"` directly, never a `herdr` found on `PATH`.
- Hook payload text (which can contain tool output) is parsed as JSON (by Python on macOS and
  Linux when available, by `ConvertFrom-Json` on Windows) and passed to Herdr as a single argument.
  Values that reach the Herdr command line (session ID, tool name) are limited to
  `[A-Za-z0-9_.:-]` and may not start with `-`, so payload text cannot add an option. An injection
  payload was tested and stayed inert.
- Only the tool name or a fixed phrase is sent to Herdr as the `--message`. Prompt text from a
  `Notification` is never sent. The event log keeps at most 200 characters of it, and the log
  directory is created with mode `700` on macOS and Linux.
- They always exit 0. A Herdr outage cannot block a CoCo turn.

## Troubleshooting

Run `$coco-herdr-plugin:doctor` inside the CoCo session. It reads the per-pane event log at
`${TMPDIR:-/tmp}/herdr-coco/events.<pane>.log` (Windows: `%TEMP%\herdr-coco\events.<pane>.log`,
with `:` in the pane ID replaced by `_`) and compares it with Herdr's view. A line of the form
`herdr report-agent failed rc=N` in that log means the hook ran but the Herdr call did not succeed;
check `herdr status` and the Herdr version.

`herdr agent explain <pane>` returns `agent_explain_unavailable` for CoCo panes. That is expected.
The command reports which screen-detection rule matched the pane text. Herdr has no detection
manifest for `cortex`, and once this plugin reports through `custom:coco`, Herdr stops running screen
rules for the pane. There is no rule or evidence to explain. Use `herdr agent list`, `herdr pane get
<pane>`, or the plugin's event log instead.

## What this does not do

These need a change to Herdr's Rust source and are out of scope:

- `herdr agent start --kind cortex`
- `herdr integration install cortex`
- Automatic resume of CoCo sessions after `herdr server stop`. Use `cortex resume --last` in a new
  pane instead.

## Verification status

Stub tests live in `tests/run.sh` and run both scripts against a fake `herdr`. Run them with
`bash tests/run.sh` (needs `pwsh` for the Windows script). Live claims below were checked on
macOS with Herdr 0.8.2 and CoCo CLI 1.1.79.

| Claim | Status |
| --- | --- |
| Script produces correct `report-agent` calls for every event | Verified by `tests/run.sh` |
| Herdr accepts the calls and updates the pane | Verified against a live Herdr 0.8.2 server |
| `idle`, `working`, `blocked` (permission), `blocked` (question), `Stop` from a real CoCo session | Verified |
| Two CoCo panes reporting independently | Verified |
| Row removed on real `/exit` | Verified |
| Persistence across closing the Herdr client | Verified |
| Windows hook (`herdr-coco-state.ps1`) produces correct calls for every event | Verified by `tests/run.sh` with PowerShell 7 on macOS |
| Windows hook on a native Windows install of Herdr and CoCo | Not yet tested |

## License

Apache-2.0. Herdr is Apache-2.0; `skills/control/SKILL.md` reproduces Herdr's bundled skill text.

## Disclaimer

This is a personal, community project. It is not an official Snowflake product and Snowflake does
not support, endorse, or maintain it. It is not affiliated with Herdr, Inc. The software is provided
"as is", without warranty of any kind, express or implied. Use it at your own risk. Test it in a
non-production environment before you depend on it. Snowflake, Cortex Code, and Herdr are trademarks
of their respective owners.
