#!/usr/bin/env bash
# Throwaway i3 instance in a virtual X server, for testing i3 commands without
# touching the user's live session. Each call is independent: no env to export.
#
#   i3-sandbox.sh start [--visible] [--outputs N]  start Xvfb (or Xephyr) + i3
#   i3-sandbox.sh run CMD [ARGS...]                run CMD with DISPLAY/I3SOCK of the sandbox
#   i3-sandbox.sh msg [i3-msg args...]             shortcut for: run i3-msg ...
#   i3-sandbox.sh spawn CLASS [TITLE] [WS]         open a dummy window (xterm), wait for it,
#                                                  print its con_id; WS = move it there (it maps
#                                                  on the focused workspace first, like any window)
#   i3-sandbox.sh status | env | log | stop
#
# --outputs N uses i3's fake-outputs: N side-by-side 1280x800 outputs named fake-0..fake-(N-1).
# State lives in $I3_SANDBOX_DIR (default $XDG_RUNTIME_DIR/i3-sandbox or /tmp/i3-sandbox-$UID),
# wiped at each start. Parallel agents: give each its own I3_SANDBOX_DIR.
set -euo pipefail

DIR=${I3_SANDBOX_DIR:-${XDG_RUNTIME_DIR:-/tmp}/i3-sandbox}
[ -n "${XDG_RUNTIME_DIR:-}" ] || DIR=${I3_SANDBOX_DIR:-/tmp/i3-sandbox-$UID}
SOCK=$DIR/ipc.sock

die() { echo "i3-sandbox: $*" >&2; exit 1; }
alive() { [ -f "$DIR/$1.pid" ] && kill -0 "$(cat "$DIR/$1.pid")" 2>/dev/null; }
display() { cat "$DIR/display" 2>/dev/null || die "not running (run: $0 start)"; }

in_sandbox() {
  alive i3 || die "not running (run: $0 start)"
  DISPLAY=$(display) I3SOCK=$SOCK "$@"
}

start() {
  local visible=0 outputs=1
  while [ $# -gt 0 ]; do
    case $1 in
      --visible) visible=1 ;;
      --outputs) outputs=$2; shift ;;
      *) die "unknown option $1" ;;
    esac
    shift
  done
  if alive i3; then
    echo "already running on $(display), socket $SOCK (options ignored: stop first to change them)"
    return
  fi
  command -v i3 >/dev/null || die "i3 not installed"
  # Fresh state dir each start (no leftovers), but only wipe a dir this script created.
  if [ -d "$DIR" ] && [ -n "$(ls -A "$DIR")" ] && [ ! -e "$DIR/.i3-sandbox" ]; then
    die "$DIR is not empty and has no .i3-sandbox marker: refusing to wipe it"
  fi
  rm -rf "$DIR"
  mkdir -p "$DIR"
  : >"$DIR/.i3-sandbox"

  local n=90
  while [ -e /tmp/.X11-unix/X$n ] || [ -e /tmp/.X$n-lock ]; do n=$((n + 1)); done
  local d=":$n" w=$((1280 * outputs))
  if [ $visible = 1 ]; then
    command -v Xephyr >/dev/null || die "Xephyr not installed (needed for --visible)"
    Xephyr "$d" -screen "${w}x800" -nolisten tcp >"$DIR/x.log" 2>&1 &
  else
    command -v Xvfb >/dev/null || die "Xvfb not installed (try --visible with Xephyr)"
    Xvfb "$d" -screen 0 "${w}x800x24" -nolisten tcp >"$DIR/x.log" 2>&1 &
  fi
  echo $! >"$DIR/x.pid"
  echo "$d" >"$DIR/display"
  for _ in $(seq 50); do [ -e /tmp/.X11-unix/X$n ] && break; sleep 0.1; done
  [ -e /tmp/.X11-unix/X$n ] || die "X server did not start, see $DIR/x.log"

  local fake="" i
  for ((i = 0; i < outputs; i++)); do fake="$fake${fake:+,}1280x800+$((1280 * i))+0"; done
  cat >"$DIR/config" <<EOF
# i3 config file (v4)
# sandbox config written by i3-sandbox.sh
font pango:monospace 8
ipc-socket $SOCK
fake-outputs $fake
focus_follows_mouse no
EOF
  rm -f "$SOCK"
  # Drop I3SOCK so nothing inherited points at the live session.
  env -u I3SOCK DISPLAY="$d" i3 -c "$DIR/config" >"$DIR/i3.log" 2>&1 &
  echo $! >"$DIR/i3.pid"
  for _ in $(seq 50); do [ -S "$SOCK" ] && i3-msg -s "$SOCK" -t get_version >/dev/null 2>&1 && break; sleep 0.1; done
  i3-msg -s "$SOCK" -t get_version >/dev/null 2>&1 || die "i3 did not start, see $DIR/i3.log"
  echo "i3 sandbox up: DISPLAY=$d I3SOCK=$SOCK outputs=$outputs"
}

spawn() {
  local class=${1:?usage: spawn CLASS [TITLE] [WS]} title=${2:-$1} ws=${3:-}
  command -v xterm >/dev/null || die "xterm not installed (needed for dummy windows)"
  # X window ids that exist before launching, so a same-class window is never mistaken for the
  # new one. Not con_ids: a window swallowed by an append_layout placeholder keeps its con_id.
  local before
  before=$(in_sandbox i3-msg -t get_tree | jq -c '[recurse(.nodes[]?, .floating_nodes[]?) | .window | values]')
  # setsid so the window outlives this shell; the sandbox stop kills the X server anyway.
  in_sandbox setsid xterm -class "$class" -name "${class,,}" -T "$title" -e sleep 1d >/dev/null 2>&1 &
  local id=""
  for _ in $(seq 50); do
    id=$(in_sandbox i3-msg -t get_tree | jq -r --arg c "$class" --argjson before "$before" '
      [recurse(.nodes[]?, .floating_nodes[]?)
       | select(.window_properties.class? == $c and (.window as $w | $before | index($w) | not))
       | .id] | first // empty')
    [ -n "$id" ] && break
    sleep 0.1
  done
  [ -n "$id" ] || die "window $class did not appear"
  [ -z "$ws" ] || in_sandbox i3-msg -q "[con_id=$id] move container to workspace $ws"
  echo "$id"
}

stop() {
  local p
  for p in i3 x; do
    if alive $p; then kill "$(cat "$DIR/$p.pid")" 2>/dev/null || true; fi
    rm -f "$DIR/$p.pid"
  done
  rm -f "$SOCK" "$DIR/display"
  echo "i3 sandbox stopped"
}

cmd=${1:-status}
shift || true
case $cmd in
  start) start "$@" ;;
  run) in_sandbox "$@" ;;
  msg) in_sandbox i3-msg "$@" ;;
  spawn) spawn "$@" ;;
  env) echo "DISPLAY=$(display) I3SOCK=$SOCK" ;;
  log) cat "$DIR/i3.log" ;;
  status) if alive i3; then echo "running: DISPLAY=$(display) I3SOCK=$SOCK"; else echo "not running"; fi ;;
  stop) stop ;;
  *) die "unknown command $cmd (start|run|msg|spawn|env|log|status|stop)" ;;
esac
