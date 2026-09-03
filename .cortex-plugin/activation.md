# Herdr integration (disabled)

This plugin reports Cortex Code's live state (`idle`, `working`, `blocked`, `done`) to
[Herdr](https://herdr.dev/docs/), the terminal multiplexer for coding agents, so a CoCo pane
shows up in the Herdr sidebar and in `herdr agent list` as agent `coco`. It also bundles
`$herdr:control` (drive other Herdr panes) and `$herdr:doctor` (troubleshoot the status link).

The plugin is currently disabled. To enable it:

```bash
cortex plugin enable herdr
```

Then start a new `cortex` session inside a Herdr pane, or run `/plugin reload` in this one.
