#!/usr/bin/env bash
# Sourceable i3 helpers (bash, jq, xprop). They call plain i3-msg/xprop, so inside
#   i3-sandbox.sh run bash -c '. scripts/i3-helpers.sh; launch_quiet 4 Foo xterm -class Foo'
# they act on the sandbox, and outside it on the live session.
#
#   i3_str STR                       STR as a double-quoted i3 string (for names with spaces)
#   launch_to_ws WS CLASS CMD...     launch CMD, wait for ITS new window (PID ancestry), move it to WS,
#                                    refocus the previous window; prints con_id. Focus flickers ~50 ms.
#   launch_quiet WS CLASS CMD...     same, with no focus change: parks a placeholder on WS first.
#                                    CLASS is matched exactly. Prints con_id.
#   wait_new_window CLASS [SECS]     block until a new window of CLASS maps; prints its con_id
#   swap_ws OUT1 OUT2                swap the workspaces visible on two outputs, focus restored
#   output_neighbours                each active output with its left/right neighbour, from rects
#   focus_watch SECS                 print focus changes (time, workspace, title) for SECS seconds
#
# Programs that hand the request to an already running instance (firefox, gnome-terminal)
# never produce a window from the launched PID: launch_to_ws times out on them.

i3_str() { jq -rn --arg s "$1" '$s|@json'; }

_i3_focused_id() {
  i3-msg -t get_tree | jq -r 'first(recurse(.nodes[]?, .floating_nodes[]?) | select(.focused)) | .id'
}

launch_to_ws() {
  local ws=$1 class=$2 prev before pid con="" cand win p
  shift 2
  prev=$(_i3_focused_id)
  # X window ids, not con_ids: a swallowed window keeps its placeholder's con_id.
  before=$(i3-msg -t get_tree | jq -c '[recurse(.nodes[]?, .floating_nodes[]?) | .window | values]')
  setsid "$@" >/dev/null 2>&1 &
  pid=$!
  for _ in $(seq 100); do
    while read -r cand win; do
      p=$(xprop -id "$win" _NET_WM_PID 2>/dev/null | grep -o '[0-9]*$')
      while [ -n "$p" ] && [ "$p" -gt 1 ] && [ "$p" != "$pid" ]; do p=$(ps -o ppid= -p "$p" | tr -d ' '); done
      [ "$p" = "$pid" ] && { con=$cand; break; }
    done < <(i3-msg -t get_tree | jq -r --arg c "$class" --argjson b "$before" '
      recurse(.nodes[]?, .floating_nodes[]?)
      | select(.window_properties.class? == $c and (.window as $w | $b | index($w) | not))
      | "\(.id) \(.window)"')
    [ -n "$con" ] && break
    sleep 0.05
  done
  [ -n "$con" ] || { echo "launch_to_ws: no new $class window from pid $pid" >&2; return 1; }
  i3-msg -q "[con_id=$con] move container to workspace $(i3_str "$ws"); [con_id=$prev] focus"
  echo "$con"
}

launch_quiet() {
  local ws=$1 class=$2 re f before ph
  shift 2
  re="^$(printf '%s' "$class" | sed 's/[]\.*^$+?(){}|[]/\\&/g')\$"
  f=$(mktemp --suffix=.json)
  jq -n --arg re "$re" '{type: "con", swallows: [{class: $re}]}' >"$f"
  before=$(i3-msg -t get_tree | jq -c '[recurse(.nodes[]?, .floating_nodes[]?) | .id]')
  i3-msg -q "append_layout $f"
  rm -f "$f"
  ph=$(i3-msg -t get_tree | jq -r --arg re "$re" --argjson b "$before" '
    first(recurse(.nodes[]?, .floating_nodes[]?)
      | select(.swallows[0].class? == $re and (.id as $i | $b | index($i) | not))) | .id // empty')
  [ -n "$ph" ] || { echo "launch_quiet: placeholder not created" >&2; return 1; }
  i3-msg -q "[con_id=$ph] move container to workspace $(i3_str "$ws")"
  setsid "$@" >/dev/null 2>&1 &
  for _ in $(seq 100); do
    i3-msg -t get_tree | jq -e --argjson id "$ph" '
      any(recurse(.nodes[]?, .floating_nodes[]?); .id == $id and .window_properties.class?)' >/dev/null \
      && { echo "$ph"; return; }
    sleep 0.05
  done
  i3-msg -q "[con_id=$ph] kill"
  echo "launch_quiet: no $class window, placeholder removed" >&2
  return 1
}

wait_new_window() {
  local ev pid fd
  # Read events from an fd so we can return on the first match; a `| head -n1` pipeline
  # would only end when i3-msg writes again or the timeout fires.
  exec {fd}< <(exec timeout "${2:-5}" i3-msg -t subscribe -m '["window"]')
  pid=$!
  while IFS= read -r -u "$fd" ev; do
    jq -e --arg c "$1" '.change == "new" and .container.window_properties.class == $c' <<<"$ev" >/dev/null \
      && { jq -r .container.id <<<"$ev"; break; }
  done
  kill "$pid" 2>/dev/null
  exec {fd}<&-
}

swap_ws() {
  # An empty workspace is destroyed as soon as it stops being visible, so only non-empty ones
  # are moved; empty ones are re-created by name on the other output.
  local o1=$1 o2=$2 a b f wa wb ea eb cmd="" nb="--no-auto-back-and-forth"
  IFS=$'\t' read -r a b < <(i3-msg -t get_outputs | jq -r --arg o1 "$o1" --arg o2 "$o2" '
    [(.[] | select(.name == $o1).current_workspace), (.[] | select(.name == $o2).current_workspace)]
    | map(. // "") | @tsv')
  [ -n "$a" ] && [ -n "$b" ] || { echo "swap_ws: no visible workspace on $o1 or $o2" >&2; return 1; }
  f=$(i3-msg -t get_workspaces | jq -r '.[] | select(.focused).name')
  read -r wa ea < <(i3-msg -t get_tree | jq -r --arg n "$a" 'recurse(.nodes[]?)
    | select(.type == "workspace" and .name == $n) | "\(.id) \((.nodes + .floating_nodes) | length == 0)"')
  read -r wb eb < <(i3-msg -t get_tree | jq -r --arg n "$b" 'recurse(.nodes[]?)
    | select(.type == "workspace" and .name == $n) | "\(.id) \((.nodes + .floating_nodes) | length == 0)"')
  if [ "$ea" = true ] && [ "$eb" = true ]; then
    # both empty: swapping the names is the same as swapping the workspaces
    # (names starting with __ are reserved by i3)
    local tmp="swap-ws-tmp-$$"
    i3-msg -q "rename workspace $(i3_str "$a") to $tmp; rename workspace $(i3_str "$b") to $(i3_str "$a");
      rename workspace $tmp to $(i3_str "$b"); workspace $nb $(i3_str "$f")"
    return
  fi
  [ "$ea" = true ] || cmd+="[con_id=$wa] move workspace to output $o2; "
  [ "$eb" = true ] || cmd+="[con_id=$wb] move workspace to output $o1; "
  i3-msg -q "$cmd focus output $o1; workspace $nb $(i3_str "$b"); focus output $o2; workspace $nb $(i3_str "$a");
    workspace $nb $(i3_str "$f")"
}

output_neighbours() {
  i3-msg -t get_outputs | jq -r '[.[] | select(.active)] as $a | $a[] as $c
    | ([$a[] | select(.rect.x >= $c.rect.x + $c.rect.width and .rect.y < $c.rect.y + $c.rect.height
         and .rect.y + .rect.height > $c.rect.y)] | min_by(.rect.x) | .name // "-") as $r
    | ([$a[] | select(.rect.x + .rect.width <= $c.rect.x and .rect.y < $c.rect.y + $c.rect.height
         and .rect.y + .rect.height > $c.rect.y)] | max_by(.rect.x) | .name // "-") as $l
    | "\($c.name) left=\($l) right=\($r)"'
}

focus_watch() {
  # window focus events carry no workspace: one tree lookup per event (can lag behind fast changes)
  timeout "$1" i3-msg -t subscribe -m '["window"]' \
    | jq -r --unbuffered 'select(.change == "focus") | "\(.container.id)\t\(.container.name)"' \
    | while IFS=$'\t' read -r id title; do
        ws=$(i3-msg -t get_tree | jq -r --argjson id "$id" 'recurse(.nodes[]?) | select(.type == "workspace") as $w
             | $w | recurse(.nodes[]?, .floating_nodes[]?) | select(.id == $id) | $w.name')
        printf '%s\tws=%s\t%s\n' "$(date +%T.%3N)" "${ws:-?}" "$title"
      done
}
