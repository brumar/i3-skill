# i3 command grammar (i3 4.23)

Contents: criteria · windows (focus, move, swap, resize, floating, layout, marks, scratchpad, appearance) · workspaces · outputs · session and debug · bar and gaps.

The command keywords i3 4.23 accepts (from its own parse error): `move exec exit restart reload shmlog debuglog border layout append_layout workspace focus kill open fullscreen sticky split floating mark unmark resize rename nop scratchpad swap title_format title_window_icon mode bar gaps`.

## Criteria

`[key="value" key2="value2"] command` (all keys must match). Values are PCRE regexes, substring match unless anchored.

- `class`, `instance`, `window_role`, `title`, `machine`, `con_mark`, `workspace` (regex)
- `id` (X11 window id), `con_id` (i3 container id, from get_tree)
- `window_type`: normal dialog utility toolbar splash menu dropdown_menu popup_menu tooltip notification
- `urgent`: latest|oldest (aliases newest last recent first)
- `floating_from` / `tiling_from`: auto|user
- `all`, `floating`, `tiling` (no value)
- `__focused__` as value for class, instance, window_role, title, workspace, con_id: `[workspace=__focused__]`

A command with criteria applies to every match. `,` carries the criteria to the next command, `;` drops them. `workspace`, `mode`, `reload`, `restart` and `exit` ignore criteria and always run.

## Windows

```
focus left|right|down|up
focus parent|child|floating|tiling|mode_toggle
focus next|prev [sibling]
<criteria> focus
<criteria> focus workspace          # focus the workspace of the match, not the window

move left|right|down|up [<n> [px|ppt]]
move position <x> [px|ppt] <y> [px|ppt]
move [absolute] position center
move position mouse
move [--no-auto-back-and-forth] [window|container] [to] workspace <name>
move [--no-auto-back-and-forth] [window|container] [to] workspace number <n>
move [window|container] [to] workspace prev|next|current
move window|container to mark <mark>
move container to output left|right|down|up|current|primary|nonprimary|next|<out1> [out2...]
  (direction = relative to the window's own output, wraps at the edge)
move scratchpad

swap container with id|con_id|mark <arg>

resize grow|shrink up|down|left|right|width|height [<px> px [or <ppt> ppt]]
resize set [width] <w> [px|ppt] [height] <h> [px|ppt]     # 0 = leave that axis
  (tiled: needs a sibling in the split; floating: any size)

floating enable|disable|toggle
fullscreen enable|disable|toggle [global]
sticky enable|disable|toggle        # floating window shown on every workspace of its output

split vertical|horizontal|toggle    # also v|h|t
layout default|tabbed|stacking|splitv|splith
layout toggle [split|all]
layout toggle <l1> <l2> [...]

mark [--add|--replace] [--toggle] <name>   # a mark lives on one container only
unmark [<name>]                     # no name = remove all marks

kill [window|client]                # client = every window of that X client
border normal|pixel [<n>] | none | toggle [<n>]
title_format <fmt>                  # %title %class %instance %machine, Pango markup allowed
title_window_icon yes|no|toggle
title_window_icon padding|toggle <px>

scratchpad show                     # cycles scratchpad windows; on a shown one, hides it
<criteria> scratchpad show          # show that specific one
```

## Workspaces

```
workspace [--no-auto-back-and-forth] <name>
workspace [--no-auto-back-and-forth] number <n>   # "3" matches "3: mail"; creates "3" if none
workspace next|prev|next_on_output|prev_on_output
workspace back_and_forth
rename workspace <old> to <new>
rename workspace to <new>           # the focused one
move workspace to output left|right|down|up|current|primary|nonprimary|next|<out1> [out2...]
<criteria> move workspace to output <out>   # moves the match's workspace (criteria may name the
                                            # workspace con itself). Hidden: stays hidden. Visible:
                                            # stays visible on <out> and takes focus.
append_layout /absolute/path.json   # into the focused workspace
```

An empty workspace disappears when you leave it. Workspace numbers come from the leading digits of the name (`num` field; -1 if none).

## Outputs

```
focus output left|right|down|up|current|primary|nonprimary|next|<name> [<name2>...]
```

Output names: `i3-msg -t get_outputs | jq -r '.[] | select(.active).name'`. After an xrandr change i3 picks up outputs on its own; workspaces of a removed output move to a remaining one.

## Session and debug

```
exec [--no-startup-id] <cmd>        # double-quote cmd if it contains ; or ,
reload                              # re-read config; success even if broken
restart                             # re-exec i3 in place, layout kept
exit                                # ends the session: never from an agent
mode <name>                         # binding mode, "default" to leave
nop [<comment>]                     # no-op; a bound key running it emits a binding event,
                                    # i3-msg nop emits nothing
shmlog <bytes> | on|off|toggle
debuglog on|off|toggle
```

## Bar and gaps

```
bar mode dock|hide|invisible|toggle [<bar_id>]
bar hidden_state hide|show|toggle [<bar_id>]
gaps inner current|all set|plus|minus|toggle <px>
gaps outer|horizontal|vertical|top|right|bottom|left current|all set|plus|minus|toggle <px>
```

Gaps commands exist since 4.22 (merged from i3-gaps). Bar ids: `i3-msg -t get_bar_config`.
