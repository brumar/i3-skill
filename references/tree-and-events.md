# i3 IPC: replies, tree fields, events, jq recipes (i3 4.23)

Contents: message types · node fields · get_workspaces / get_outputs · events · jq recipes.

## Message types (`i3-msg -t <type>`)

`command` (default), `get_workspaces`, `get_outputs`, `get_tree`, `get_marks`, `get_bar_config [id]`, `get_binding_modes`, `get_binding_state`, `get_version`, `get_config`, `send_tick [payload]`, `subscribe '["event", ...]'` (`-m` to keep listening).

## Tree node fields (`get_tree`)

Node `type`: `root` > `output` (incl. the hidden `__i3`) > `con` (content area; outputs also hold `dockarea` nodes for bars) > `workspace` > `con` / `floating_con`.

| field | meaning |
|---|---|
| `id` | con_id, use with `[con_id=]`; a memory address, reused after a window closes |
| `window` | X11 window id or null. Also set on append_layout placeholders |
| `window_properties` | `class`, `instance`, `title`, `window_role`, `machine`, `transient_for`; no `class` on placeholders |
| `name` | window title (or workspace / output name) |
| `type` | see above |
| `output` | output name, on every node |
| `num` | workspace number (workspace nodes only) |
| `focused` | true on exactly one node |
| `focus` | child ids in focus order (first = most recently focused) |
| `nodes`, `floating_nodes` | children; recurse into both |
| `layout` | splith splitv stacked tabbed dockarea output |
| `orientation` | horizontal vertical none |
| `percent` | share of the parent split (0-1) |
| `rect` | absolute geometry incl. decoration; `window_rect` relative client area (stale on hidden workspaces); `deco_rect` title bar; `geometry` the size the client asked for |
| `floating` | auto_off auto_on user_off user_on |
| `fullscreen_mode` | 0 none, 1 output, 2 global |
| `scratchpad_state` | none fresh changed, on the `floating_con` wrapper. `fresh`: next show forces 50% x 75% of the output; `changed`: geometry kept |
| `sticky`, `urgent`, `marks` | as named |
| `swallows` | criteria of a placeholder; empty on normal windows |
| `gaps` | per-workspace gaps (workspace nodes); global gaps do not show here |
| `window_type` | normal, dialog, ..., `unknown` when the client sets none |

## get_workspaces / get_outputs

- Workspace: `id name num output focused visible urgent rect`. `visible` = shown on its output; `focused` = the one with input focus.
- Output: `name active primary current_workspace rect`. Inactive outputs have `current_workspace: null`.

## Events (`subscribe`)

| event | `change` values / payload |
|---|---|
| `workspace` | focus init empty urgent rename reload restored move; `current`, `old` |
| `window` | new close focus title fullscreen_mode move floating urgent mark; `container` |
| `output` | unspecified (an output was added, removed or changed) |
| `mode` | binding mode name in `change` |
| `binding` | run; `binding.command`, `binding.symbol` |
| `barconfig_update` | new bar config |
| `shutdown` | restart exit |
| `tick` | `payload`; first event after subscribing has `first: true` |

Event notes:
- `-m` prints no acknowledgement: start the subscription before the action you want to catch.
- To stop at the first matching event, read from an fd and kill i3-msg (`wait_new_window` in `scripts/i3-helpers.sh`). A `| head -n1` pipeline only returns at i3-msg's next write or at the timeout.
- `window` focus events carry no workspace: a watcher needs a tree lookup per event (`focus_watch` in the helpers), which can lag behind fast changes. Focusing an empty workspace emits no window event.
- `mode` arrives before the `binding` event of the same key press. `binding` carries `command`, `symbol`, `mods`, `event_state_mask`.
- In the sandbox, `xdotool key ...` produces real binding events and `xdotool set_window --urgency 1 <xwin>` produces urgent events.

Watch workspace switches live: `timeout 60 i3-msg -t subscribe -m '["workspace"]' | jq -r --unbuffered 'select(.change=="focus") | .current.name'`.

## jq recipes

```bash
T() { i3-msg -t get_tree; }

# windows of one workspace
T | jq -r --arg ws "2" 'recurse(.nodes[]?) | select(.type=="workspace" and .name==$ws)
  | recurse(.nodes[]?, .floating_nodes[]?) | select(.window_properties.class?) | "\(.id) \(.name)"'

# scratchpad windows, hidden or shown
T | jq -r 'recurse(.nodes[]?, .floating_nodes[]?) | select(.type=="floating_con" and .scratchpad_state!="none")
  | "\(.nodes[0].id) \(.scratchpad_state) \(if .output=="__i3" then "hidden" else "shown" end) \(.nodes[0].name)"'

# floating windows with geometry
T | jq -r 'recurse(.nodes[]?, .floating_nodes[]?) | select(.type=="floating_con")
  | "\(.nodes[0].id) \(.nodes[0].name) \(.rect.width)x\(.rect.height)+\(.rect.x)+\(.rect.y)"'

# count windows per class
T | jq -r '[recurse(.nodes[]?, .floating_nodes[]?) | select(.window_properties.class?) | .window_properties.class]
  | group_by(.) | map("\(length) \(.[0])") | .[]'

# workspace of a con_id
T | jq -r --argjson id 94371234 'recurse(.nodes[]?) | select(.type=="workspace") as $ws
  | $ws | recurse(.nodes[]?, .floating_nodes[]?) | select(.id==$id) | $ws.name'

# urgent windows
T | jq -r 'recurse(.nodes[]?, .floating_nodes[]?) | select(.urgent and .window_properties.class?) | "\(.id) \(.name)"'
```
