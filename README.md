# i3 skill for Claude Code

A skill that teaches Claude Code (and other agents that read `SKILL.md` skills) to drive and configure the [i3 window manager](https://i3wm.org) through `i3-msg` and the i3 IPC.

What it covers:

- reading the window tree with `jq` (windows, workspaces, outputs, scratchpad, marks)
- targeting windows safely (`con_id`, anchored criteria) and acting without stealing the user's focus
- moving windows and workspaces across workspaces and outputs, floating geometry, layouts, gaps
- IPC event subscriptions, layout save and restore (`i3-save-tree`, `append_layout`)
- editing, validating and reloading the config
- the `i3-msg` behaviours that trip agents up, each one checked against a real i3 4.23

It ships with two scripts:

- `scripts/i3-sandbox.sh` runs a throwaway i3 in a virtual X server (Xvfb, or Xephyr with `--visible`), with optional fake multi-monitor outputs. The agent can try commands there before touching your desktop.
- `scripts/i3-helpers.sh` holds tested bash functions: launch a program and send its window to a workspace without stealing focus, wait for a new window, swap the workspaces of two outputs, find output neighbours, watch focus changes.

## Install

```bash
npx skills add brumar/i3-skill
```

or copy this folder to `~/.claude/skills/i3/`.

Requirements: i3 4.22+ on X11, `jq`. For the sandbox: `Xvfb` (or `Xephyr`) and `xterm`.

## Safety

The skill tells the agent to read state before acting, to target one window by id, to ask before killing windows or editing the config, and never to run `exit`. Commands still run on your live session when the agent uses plain `i3-msg`: review what it proposes.

## License

MIT, see [LICENSE](LICENSE).
