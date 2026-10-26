#!/usr/bin/env bash
# Crash isolation: repeats the stop -> quick restart cycle that crashed OStim, first with the OStim Expansion
# switched off in game (flows, live lines, bystanders), then switched on.
# usage: bash stress.sh <partner form> <cycles per phase>
set -u
NGVO=D:/Modlists/NGVO
V="{\"form\":\"$1\"}"; N=${2:-6}
db() { bash "$NGVO/tools/devbench-cli.sh" "$@" 2>&1; }
call() { db call "$@" | py -3 -I -c "import json,sys
try:
    d=json.load(sys.stdin); print(d.get('returned') if d.get('called') else 'ERROR')
except Exception: print('ERROR')"; }
t() { call MAE_Test "$1" "${2:-[]}"; }
alive() { db alive | grep -qE 'RUNNING|NOT ADVANCING'; }
in_scene() { [ "$(call OActor GetThreadID '[{"form":"0x14"}]')" != "-1" ]; }
say() { echo "$(date +%H:%M:%S) $1"; db notify "$1" >/dev/null; }

phase() {  # phase <name> <0|1>
  db exec "set MAE_FlowsEnabled to $2" >/dev/null; db exec "set MAE_LiveSceneLines to $2" >/dev/null
  db exec "set MAE_BystanderComments to $2" >/dev/null
  t Begin "[\"stress-$1\"]" >/dev/null
  for ((c = 1; c <= N; c++)); do
    say "$1 cycle $c/$N: start"
    t Start "[$V]" >/dev/null
    local w=0; until in_scene; do sleep 3; w=$((w + 3)); alive || { say "GAME DOWN while starting ($1 $c)"; return 1; }; [ $w -ge 200 ] && break; done
    say "$1 cycle $c: in scene after ${w}s"; sleep 13
    t Stop >/dev/null; sleep 4      # the gap that crashed: restart 4 s after the stop
    alive || { say "GAME DOWN after stop ($1 $c)"; return 1; }
  done
  say "$1 phase survived $N cycles"
}

db exec "set GameHour to 12" >/dev/null
t Setup '[true]' >/dev/null
phase off 0 && phase on 1
echo "exit $?"
