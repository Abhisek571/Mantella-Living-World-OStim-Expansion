#!/usr/bin/env bash
# Drives the affection scenarios over DevBench (game running, test build loaded), then validates the log.
# Timings land in the log as AFFECT|TIMING lines and are printed at the end.
# usage: bash affection-test.sh <partner form> <second npc form> [seconds, default 20] [kinds, default all] [yes]
#        e.g. bash affection-test.sh 0xFE1DD821 0xA2C94 20 "kiss hug dance"
# The partner should be of the other sex than the player (most lists are for a man and a woman); stand near a free
# chair for lap_dance and solo_dance. "yes" as the fifth argument also runs the growth into a real sex scene.
set -u
MO2=${MO2:?set MO2 to your Mod Organizer 2 instance folder}
HERE=$(cd "$(dirname "$0")" && pwd)
LOG="$MO2/overwrite/SKSE/Plugins/MantellaAdultExpansion/test.log"
CAT="$MO2/mods/Mantella Living World - OStim Expansion - Flows (test)/SKSE/Plugins/StorageUtilData/MantellaAdultExpansion/flows.json"
V="{\"form\":\"$1\"}"; B="{\"form\":\"$2\"}"; P='{"form":"0x14"}'
SECONDS_SHORT=${3:-20}
KINDS=${4:-"kiss neck_kiss hand_kiss hold_hands hug cuddle head_pat dance lap_dance solo_dance"}
RUN_YES=${5:-}
# One driver at a time: two runs at once interleave their scenes and the log.
LOCK="$MO2/overwrite/SKSE/Plugins/MantellaAdultExpansion/run.lock"
mkdir -p "$(dirname "$LOCK")"; mkdir "$LOCK" 2>/dev/null || { echo "another test run is going (remove $LOCK if not)"; exit 3; }

call() { bash "$MO2/tools/devbench-cli.sh" call "$@" 2>&1 | py -3 -I -c "import json,sys
try:
    d=json.load(sys.stdin); print(d.get('returned') if d.get('called') else 'ERROR '+str(d))
except Exception: print('ERROR no reply')"; }
t() { call MAE_Test "$1" "${2:-[]}"; }
con() { bash "$MO2/tools/devbench-cli.sh" exec "$1" >/dev/null 2>&1; }
note() { bash "$MO2/tools/devbench-cli.sh" notify "$1" >/dev/null 2>&1; echo "== $1"; }
restore() { t AffectionSeconds '[0.0]' >/dev/null; t AskAnswer '[""]' >/dev/null; t Setup '[false]' >/dev/null; rmdir "$LOCK"; }
trap restore EXIT
# A start with a named scene must not open OStim's picker: logged as a failure and closed so the run can go on.
check_picker() {
  bash "$MO2/tools/devbench-cli.sh" tool menu '{"action":"list"}' 2>/dev/null | grep -q '"CustomMenu"' || return 0
  echo "   PICKER OPENED"; t Mark '["picker opened"]' >/dev/null
  bash "$MO2/tools/devbench-cli.sh" tool menu '{"action":"close","name":"CustomMenu"}' >/dev/null 2>&1
}
wait_state() {  # wait_state <pattern> <seconds>: until MAE_Test.AffectionState matches
  local i; for ((i = 0; i < $2; i += 3)); do t AffectionState | grep -qE "$1" && return 0; check_picker; sleep 3; done
  echo "   timeout waiting for $1: $(t AffectionState)"; return 1
}
IDLE='starting=(FALSE|False|false) started=(FALSE|False|false) .*thread=-1'
wait_started() { wait_state "started=(TRUE|True|true)|$IDLE" 240; }   # idle again: it was refused
wait_ended() {  # no affection state left and OStim has let go of the player
  wait_state "$IDLE" "$1" || return 1
  local i; for ((i = 0; i < 60; i += 2)); do [ "$(call OActor GetThreadID "[$P]")" = "-1" ] && return 0; sleep 2; done
  echo "   the player is still in a thread"; return 1
}
show() { echo "   state: $(t AffectionState)"; echo "   worn: player=$(t Worn "[$P]") partner=$(t Worn "[$V]")"; }
asked() {  # waits for the Ask First answer after a growth
  local i; for ((i = 0; i < 60; i += 3)); do grep -aq 'ASK|ANSWER' "$LOG" && return 0; sleep 3; done; echo "   no answer logged"; return 1
}

con "set GameHour to 12"
t Setup '[true]' >/dev/null
t EndConversation >/dev/null   # nobody left over in the fake conversation from an earlier run
t AffectionSeconds "[$SECONDS_SHORT.0]" >/dev/null

note "gate: she joins, her file lists the kinds that work here"
t Begin '["affection-gate"]'; t Join "[$V]"; sleep 4
echo "   gate=$(t AffectionGate "[$V]") kinds: $(t AffectionKinds "[$V]")"

note "start: no box, no picker, listed scene, clothes stay on, nothing else takes over"
t Begin '["affection-start"]'
show; t Affection "[$V,\"kiss\"]"; wait_started; sleep 3; show
echo "   actors: $(t SceneActors)"; echo "   flows: $(t Status)"

note "guards while it runs: position change and a second NPC refused"
t Begin '["affection-guards"]'
t ChangePosition "[$V,\"cowgirl\"]"; sleep 2
t Affection "[$B,\"kiss\"]"; sleep 2; show

note "same furniture: kiss to hug warps, the time starts over"
t Begin '["affection-switch"]'
t Affection "[$V,\"hug\"]"; sleep 4; show

note "other furniture: hug to lap_dance ends this one, waits the gap, starts on a chair"
t Begin '["affection-restart"]'
t Affection "[$V,\"lap_dance\"]"; sleep 3; wait_started; sleep 3; show

note "the timer ends it: one line, a score event, no sex summary"
t Begin '["affection-end"]'
wait_ended $((SECONDS_SHORT + 40)); show

for kind in $KINDS; do
  note "kind $kind"
  t Begin "[\"affection-kind:$kind\"]"
  t Affection "[$V,\"$kind\"]"; sleep 2; wait_started; sleep 3; show
  wait_ended $((SECONDS_SHORT + 40))
done

note "who: npc and player for neck_kiss and head_pat"
for kind in neck_kiss head_pat; do
  for who in npc player; do
    t Begin "[\"affection-who-$who:$kind\"]"
    t AffectionWho "[$V,\"$kind\",\"$who\"]"; sleep 2; wait_started; sleep 3; show
    wait_ended $((SECONDS_SHORT + 40))
  done
done

note "growth, answer No: the kiss ends, she needs a moment, the box after the gap, a not-now line"
t Begin '["affection-grow-no"]'
t Affection "[$V,\"kiss\"]"; wait_started; sleep 3
t AskScene "[$V,\"No\"]"; wait_ended 40; asked; sleep 3

note "growth, answer Skip: the fade counts as done"
t Begin '["affection-grow-skip"]'
t Affection "[$V,\"kiss\"]"; wait_started; sleep 3
t AskScene "[$V,\"Skip\"]"; wait_ended 40; sleep 15

if [ "$RUN_YES" = "yes" ]; then
  note "growth, answer Yes: a normal sex scene starts (then stopped)"
  t Begin '["affection-grow-yes"]'
  t Affection "[$V,\"kiss\"]"; wait_started; sleep 3
  t AskScene "[$V,\"Yes\"]"; wait_ended 40
  for i in $(seq 1 80); do t Status | grep -qE 'set=[0-9]' && break; check_picker; sleep 3; done
  echo "   flows: $(t Status)"; t Stop >/dev/null; sleep 15
fi

note "the talk ends during it: stopped, no end line"
t Begin '["affection-talk-ended"]'
t Affection "[$V,\"kiss\"]"; wait_started; sleep 3
t EndConversation; wait_ended 40; sleep 8

note "the talk ends while they walk together: stopped as soon as it starts, no lines, no score"
t Begin '["affection-talk-ended-early"]'
t Join "[$V]"; sleep 2
t Affection "[$V,\"kiss\"]"; sleep 2
t EndConversation; wait_ended 240; sleep 8

note "a kind with no listed scene: nothing starts, Mantella hears it"
t Begin '["affection-no-scene"]'
t Affection "[$V,\"no such kind\"]"; sleep 3; show
t Leave "[$V]" >/dev/null

t Begin '["done"]'
note "tests finished"
echo; grep -a 'AFFECT|TIMING\|AFFECT|CALL\|AFFECT|GATE\|ASK|AFTER' "$LOG"
echo; py -3 -I "$HERE/validate.py" "$LOG" "$CAT"
