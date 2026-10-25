# Layout save/restore and multiple outputs (i3 4.23)

Contents: i3-save-tree and append_layout · placeholders · restoring onto open windows · outputs and directions · pinning workspaces · swapping.

## i3-save-tree and append_layout

```bash
i3-save-tree --workspace 2 > ws2.raw.json          # or --output NAME
# keep only the class line of each swallow, without its trailing comma
sed -E 's#^(\s*)// ("class": "[^"]*"),$#\1\2#' ws2.raw.json > ws2.json
i3-msg 'workspace 2; append_layout /abs/path/ws2.json'
```

- The dump is several top-level JSON objects with `//` comments. append_layout accepts that as is; `jq` does not until the comments are stripped.
- Every swallow criterion is commented out. Uncomment `class` (or `instance`) only: titles change, and `machine` ties the file to one hostname. The last uncommented line of a block must lose its trailing comma.
- Error messages: a trailing comma gives "Could not parse ... as JSON"; a swallow left empty gives "parse error: client cancelled parse via callback return value".
- Preflight an edited dump (true = OK, false = an empty swallow, jq error = bad JSON):

```bash
grep -v '^[[:space:]]*//' ws2.json | jq -se '[.[] | .. | objects | select(has("swallows")) | .swallows[] | length > 0] | all'
```

- append_layout always targets the focused workspace. A file whose second object fails still leaves the first object's placeholders behind, while i3-msg reports failure.

## Placeholders

- A placeholder is a container with `.swallows` set, an X window drawn by i3 (`.window` non-null), and no `window_properties.class`. Filter real windows with `select(.window_properties.class?)`.
- It swallows the next new window matching its criteria, whatever workspace has focus, with no focus change and no urgency. The window keeps the placeholder's con_id.
- A workspace holding only placeholders survives being left, and keeps swallowing future windows. Remove a placeholder with `[con_id=P] kill`.
- Parking a placeholder on another workspace before launching a program is the way to open a window somewhere without the focus flicker (`launch_quiet` in `scripts/i3-helpers.sh`).

## Restoring onto windows that are already open

Placeholders only take windows that map after them. To push existing windows into a restored layout, unmap and remap each one (verified with xterm):

```bash
xdotool windowunmap --sync "$W"; xdotool windowmap --sync "$W"
```

Unmapping the focused window moves focus. A stale urgency hint comes back on remap.

## Outputs and directions

- Names: `i3-msg -t get_outputs | jq -r '.[] | select(.active).name'`. Geometry is in `.rect`; neighbours from rects: `output_neighbours` in the helpers.
- `move container to output left|right|up|down` is relative to the window's own output, not the focused one, and wraps: right from the rightmost output lands on the leftmost.
- `move workspace to output X`: a hidden workspace stays hidden, focus unchanged. A visible workspace stays visible on X and takes focus, even if X was not the focused output. The old output shows another workspace, or a new numbered one.
- After an xrandr change i3 picks up outputs on its own; workspaces of a removed output move to a remaining one.

## Pinning workspaces to outputs

Config line `workspace 5 output HDMI-1 eDP-1` (fallback order). It decides where workspace 5 is created, by `workspace 5` or by `move container to workspace 5`. A reload does not move a workspace 5 that already exists elsewhere: move it with `[con_id=<ws id>] move workspace to output HDMI-1`.

## Swapping the workspaces of two outputs

No single command. The trap: an empty workspace is destroyed as soon as it stops being visible, so moving the other workspace first deletes it, and the second move then fails with the misleading "No output matched". `swap_ws OUT1 OUT2` in the helpers moves only the non-empty workspaces (by con_id), re-creates empty ones by name on the other output, swaps names when both are empty, uses `workspace --no-auto-back-and-forth` (so `workspace_auto_back_and_forth` in the user's config cannot bounce), and keeps the same workspace focused. Tested on the four empty/non-empty combinations, with names containing spaces.
