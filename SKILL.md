---
name: i3
description: Drive and configure the i3 window manager (X11) through i3-msg and the i3 IPC, plus the companion tools (i3-save-tree/append_layout, i3-nagbar, i3-input, i3-dump-log, i3bar/i3status, i3 -C). Covers reading the window tree with jq, targeting windows by criteria or con_id, moving windows/workspaces between workspaces and outputs, focus, marks, scratchpad, floating geometry, layouts, gaps, IPC event subscriptions, saving/restoring layouts, and editing/validating/reloading the i3 config safely. Includes a throwaway sandbox i3 (Xvfb or Xephyr) to test commands without touching the live desktop. Use when the user mentions i3, i3wm, i3-msg, i3 IPC, workspaces, tiling, "move this window to workspace/screen X", "which windows are open", scratchpad, marks, bindsym/keybindings or other i3 config, i3bar/i3status, or wants to script or automate their desktop arrangement under i3.
---

# i3

Verified against i3 4.23. Sway accepts the same command language through `swaymsg`, but the sandbox and the X11 tools below (xprop, xdotool, Xvfb) do not apply there.

Machine-specific facts (which output is where, the user's own scripts and bindings) belong in the project's CLAUDE.md or memory. Read those first when they exist; this skill stays generic.

## Live-session rules

Every `i3-msg` command hits the user's real desktop at once. Work in this order: read state, act on one precise target, read state again to verify.

- Target by `[con_id=N]` (from `get_tree`) once you know the window. Class/title criteria are for finding it. con_ids are memory addresses and get reused after a window closes: re-check the class before acting on a stored id, and use a mark for long-lived references.
- Prefer commands that leave the user's view alone. `[con_id=N] move container to workspace 5` does not follow the window, except that a window moved into the focused workspace while it is empty takes focus. `workspace X`, `focus`, `scratchpad show` and moving a visible workspace to another output all change what the user sees: say so or ask when they are mid-work.
- A new window always maps on the focused workspace and takes focus before you can move it: a visible flicker, and keystrokes typed at that moment land in it. Three ways around it: park a placeholder on the target workspace first (`launch_quiet` in the helpers), or config rules `assign [class="^X$"] "4"` (no focus change, marks window and workspace urgent) or `no_focus [class="^X$"]` (no focus, but still maps on the focused workspace).
- Ask before: `kill` (any criteria), moving many windows at once, `restart`, `i3lock`, editing the config. Never run `exit` (ends the X session).
- Test anything new or risky in the sandbox first (`scripts/i3-sandbox.sh`, below).
- Do not `pkill -f <pattern>` from a Bash tool call: the pattern also appears in the tool's own shell command line, so pkill can kill that shell. Get the pid (`pgrep -af '[n]ame'`, bracket trick) and `kill <pid>`.
- Redirect every background launch in a tool call (`prog >/dev/null 2>&1 &`): a background process holding the call's stdout makes the call hang until it exits.

## i3-msg behaviour that bites

- Reply is a JSON array, one object per command: `{"success":true}` or `{"success":false,"error":"..."}` (`"parse_error":true` for syntax). Exit code 2 if any command failed; errors also go to stderr as `ERROR:` lines. `-q` hides stdout only.
- `,` keeps the criteria for the next command, `;` resets them: `[con_id=N] floating enable, move position center; workspace 2`. Commands after a failed one still run.
- Criteria values are PCRE, case-sensitive, and match substrings: `[class="Term"]` also hits `TermX`. Anchor them: `[class="^Term$"]`. `(?i)` makes one case-insensitive. There is no negation key; use a lookahead: `[class="^TermX$" title="^(?!scratch$)"]`.
- Criteria that match nothing usually return success and do nothing: `kill`, `floating`, `resize`, `layout`, `border`, `sticky`, `fullscreen`, `title_format`, `move scratchpad`, `move left`, `move position`, `move window to mark`. Only `move ... to workspace`, `move ... to output` (error text "No output matched"), `focus`, `mark` and `swap` report an error; `scratchpad show` gives `success:false` with no text. Always verify with the tree.
- `workspace`, `mode`, `reload`, `restart` and `exit` ignore criteria: `[con_id=999] workspace 7` switches the user to 7 even though nothing matched.
- The parser only knows double quotes. `;` and `,` split commands even inside single quotes, so `exec sh -c 'a; b'` runs `sh -c 'a` and then fails. Wrap the whole payload: `exec --no-startup-id "sh -c 'a; b'"`. An unquoted workspace name runs to the next `;` or `,`, so `move container to workspace 3: mail` works but `rename workspace 3: mail to x` does not: double-quote names with spaces every time.
- `exec` starts the program from i3, with i3's environment and working directory, not the caller's. A variable set in your shell is not seen. Put values in the command string, or launch from the shell and then move the window (`launch_to_ws` in the helpers).
- New windows appear asynchronously. To find yours, diff against the X window ids (`.window`) that existed before launch, not the class alone (an older window of the same class matches) and not con_ids (a window swallowed by a placeholder keeps the placeholder's con_id). Parallel launches of one class still cross: match `_NET_WM_PID` against the launched pid, as `launch_to_ws` does.
- `i3-msg reload` returns success even when the config is broken (i3 shows a nagbar; the next good reload closes it). `i3 -C -c FILE` exits 1 on an unknown directive but 0 on other errors (e.g. a malformed `set_from_resource`): grep its output for `ERROR` instead of trusting the exit code. Neither one checks the command text inside `bindsym` or `for_window` lines: see Config changes.
- `subscribe` without `-m` returns after one event. Subscribing to `tick` returns immediately with `{"first":true}`. `-m` prints no acknowledgement, so start a subscription before the action you want to catch. Always wrap subscriptions in `timeout`; a `| head -n1` pipeline only ends at i3-msg's next write or the timeout (`wait_new_window` in the helpers returns at once).
- Socket: `$I3SOCK`, else the X root window; `i3 --get-socketpath` prints it. `-s PATH` overrides.

## Reading state

```bash
T() { i3-msg -t get_tree; }
# real client windows (append_layout placeholders have .window but no class)
W='recurse(.nodes[]?, .floating_nodes[]?) | select(.window_properties.class?)'

T | jq -r "$W | select(.focused) | \"\(.id) \(.window_properties.class) \(.name)\""   # focused window
i3-msg -t get_workspaces | jq -r '.[] | select(.focused).name'                       # focused workspace
i3-msg -t get_outputs | jq -r '.[] | select(.active) | "\(.name) \(.current_workspace) \(.rect.x),\(.rect.y) \(.rect.width)x\(.rect.height)"'

# every window with its workspace and output
T | jq -r 'recurse(.nodes[]?) | select(.type=="workspace") as $ws | $ws
  | recurse(.nodes[]?, .floating_nodes[]?) | select(.window_properties.class?)
  | "\($ws.name)\t\(.output)\t\(.id)\t\(.window_properties.class)\t\(.name)"'

# con_ids by exact class, excluding one title (jq == is exact and case-sensitive, like i3)
T | jq -r "$W | select(.window_properties.class == \"firefox\" and .name != \"Library\") | .id"
```

Tree facts:
- Floating windows live in `floating_nodes`, not `nodes`; recurse into both. Each sits inside a `floating_con` wrapper that carries `scratchpad_state` and the floating rect.
- Hidden scratchpad windows are under the workspace `__i3_scratch` (output `__i3`). A shown one sits on a normal workspace: detect every scratchpad window by its wrapper's `scratchpad_state != "none"`.
- `scratchpad_state` `fresh`: the first `scratchpad show` resizes it to 50% x 75% of the output, centered. `changed`: its geometry is kept. So float and size a window before `move scratchpad`.
- Floating `resize set` honours the client's size increments (an xterm asked for 800x500 gets 796x494). Check the `floating_con` `.rect`; `window_rect` is stale for windows on hidden workspaces.
- `.id` is the con_id (use with `[con_id=]`). `.window` is the X11 window id (use with `[id=]`, xprop, xdotool).
- `.output` is set on every node; the workspace is not, hence the `as $ws` walk above.

Field list, event types and more jq: [references/tree-and-events.md](references/tree-and-events.md).

## Common actions

```bash
i3-msg '[con_id=N] move container to workspace "2"'          # send, stay where you are
i3-msg '[con_id=N] move container to workspace "2"; workspace "2"'   # send and follow
i3-msg '[con_id=N] move container to output right'            # relative to N's output, wraps at the edge
i3-msg '[con_id=N] focus'                                     # jumps to its workspace
i3-msg 'workspace number 3'                                   # matches "3: mail"
i3-msg 'rename workspace "3: mail" to "3: inbox"'
i3-msg '[con_id=N] move workspace to output HDMI-1'           # N's workspace; see focus note below
i3-msg '[con_id=N] floating enable, resize set 900 600, move position center'
i3-msg '[con_id=N] mark --add notes'; i3-msg '[con_mark="^notes$"] focus'   # marks are unique
i3-msg '[con_id=N] move scratchpad'; i3-msg '[con_id=N] scratchpad show'  # show again = hide
i3-msg '[con_id=A] swap container with con_id B'
i3-msg '[con_id=N] move window to mark notes'
i3-msg 'gaps inner all set 8'                                 # current|all, set|plus|minus|toggle
```

`move workspace to output`: a hidden workspace stays hidden and focus does not move; a visible one stays visible on the new output and takes focus, even when that output is not the focused one. The old output shows another workspace (a new numbered one if none is left). Criteria can name the workspace itself (`[con_id=<workspace id>]`), empty ones included.

`resize` on a tiled window needs a sibling in the split, otherwise it fails. Full command grammar: [references/commands.md](references/commands.md). Multi-monitor details and layout save/restore: [references/layouts-and-outputs.md](references/layouts-and-outputs.md).

## Helpers

`scripts/i3-helpers.sh` is sourceable (bash, jq, xprop). Each function is tested on the sandbox:

- `launch_to_ws WS CLASS CMD...`: launch, wait for that process's own window, move it to WS, refocus the previous window (about 50 ms of flicker). Prints the con_id.
- `launch_quiet WS CLASS CMD...`: same result with no focus change, via a placeholder parked on WS.
- `wait_new_window CLASS [SECS]`: return as soon as a new window of CLASS maps.
- `swap_ws OUT1 OUT2`: swap the workspaces visible on two outputs, focus restored.
- `output_neighbours`: each output's left and right neighbour, from the rects.
- `focus_watch SECS`: log focus changes with their workspace.

Programs that hand the launch to a running instance (firefox, gnome-terminal) never produce a window from the launched pid: `launch_to_ws` times out on them. Use `launch_quiet` (class-based) or a config rule instead.

## Config changes

1. Find the file: `i3-msg -t get_version | jq -r '.loaded_config_file_name, .included_config_file_names[]'`.
2. Back up (`cp config "config.bak-$(date +%F-%H%M%S)"`), then edit the smallest thing possible.
3. Validate the file: `i3 -C -c FILE 2>&1 | grep -i error` must print nothing.
4. Validate every new `bindsym` / `for_window` body. Use `,` only inside them: after a `;` the next command applies to whatever window had focus, not the matched one. Dry-run the body in the sandbox: `$SB msg "[con_id=1] BODY" | jq -e 'any(.[]; .parse_error)'` prints `true` when the body is broken (a typo like `resize sett` passes `i3 -C`, reload and the nagbar, and only shows in the i3 log). Sandbox only: commands that ignore criteria (`workspace`, `mode`) run for real.
5. `i3-msg reload` applies config changes and keeps windows in place. `restart` re-executes i3 in place (layout kept); use it after an i3 upgrade. Check for a config-error nagbar after either: `pgrep -af '[i]3-nagbar' | grep -F "$CONFIG"` (the nagbar's arguments contain the config path, which tells a sandbox nagbar from a live one).

`i3-msg -t get_config` prints the config as loaded; `-r` returns JSON that also lists included files. `workspace 5 output HDMI-1` in the config pins where workspace 5 is created; reload does not move a workspace 5 that already exists.

## Other tools

- `i3-save-tree --workspace N > ws.json` then `i3-msg 'workspace N; append_layout /abs/ws.json'`: placeholders that swallow new matching windows. Uncomment only the `class` (or `instance`) line of each swallow and drop its trailing comma. Details, preflight check and cleanup: [references/layouts-and-outputs.md](references/layouts-and-outputs.md).
- `i3-nagbar -t warning -m 'text' -B 'Label' 'shell cmd'`: a bar with buttons on the user's screen.
- `i3-input -F 'rename workspace to "%s"' -P 'Name: '`: grabs the keyboard and waits for the user to type. Only on request.
- `i3-dump-log`: needs `i3-msg 'shmlog on'` (or `--shmlog-size`) first; `debuglog on` adds detail.
- `i3bar` / `i3status`: control with `bar mode dock|hide|invisible|toggle` and `bar hidden_state hide|show|toggle`.
- `i3-sensible-terminal`, `i3-dmenu-desktop`: launchers. `i3lock` locks the user out: only on request.
- `xprop -id <window>` / `xdotool getactivewindow` give X window ids for `[id=]`.

## Sandbox

`scripts/i3-sandbox.sh` runs a separate i3 on a virtual X display with its own socket. Calls are stateless, so they work from separate tool calls:

```bash
SB=<this skill's folder>/scripts/i3-sandbox.sh   # e.g. ~/.claude/skills/i3/scripts/i3-sandbox.sh
$SB start --outputs 2          # Xvfb, outputs fake-0 and fake-1; --visible uses Xephyr
id=$($SB spawn Foo "foo title" 3)   # dummy xterm, class Foo, moved to ws 3 after mapping; prints con_id
$SB msg "[con_id=$id] floating enable"
$SB msg -t get_tree | jq ...
$SB run bash -c ". ${SB%/*}/i3-helpers.sh; launch_quiet 4 Bar xterm -class Bar"   # helpers on the sandbox
$SB run xdotool key super+n              # press a key: tests a bindsym end to end
$SB run xdotool set_window --urgency 1 <x-window-id>   # make a window urgent
$SB log; $SB stop
```

Plain `i3-msg` in the same shell still talks to the live session (`$I3SOCK`). Always go through `$SB msg` / `$SB run` for sandbox work. `start` wipes the state dir and ignores options while a sandbox runs (stop first). Parallel agents need separate `I3_SANDBOX_DIR`s. Needs Xvfb (or Xephyr), xterm and jq.
