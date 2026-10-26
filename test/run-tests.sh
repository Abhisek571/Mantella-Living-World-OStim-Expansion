#!/usr/bin/env bash
# Drives the in-game test scenarios over DevBench (game running, test build loaded), then validates the log.
# usage: bash run-tests.sh <partner form> <bystander form>     e.g. 0xFE1DD821 0xA2C94
set -u
NGVO=D:/Modlists/NGVO
HERE=$(cd "$(dirname "$0")" && pwd)
LOG="$NGVO/overwrite/SKSE/Plugins/MantellaAdultExpansion/test.log"
CAT="$NGVO/mods/Mantella Living World - OStim Expansion - Flows (test)/SKSE/Plugins/StorageUtilData/MantellaAdultExpansion/flows.json"
# One driver at a time: two runs at once interleave their scenes and the log.
LOCK="$NGVO/overwrite/SKSE/Plugins/MantellaAdultExpansion/run.lock"
mkdir -p "$(dirname "$LOCK")"; mkdir "$LOCK" 2>/dev/null || { echo "another test run is going (remove $LOCK if not)"; exit 3; }
trap 'rmdir "$LOCK"' EXIT
V="{\"form\":\"$1\"}"; B="{\"form\":\"$2\"}"; P='{"form":"0x14"}'

call() { bash "$NGVO/tools/devbench-cli.sh" call "$@" 2>&1 | py -3 -I -c "import json,sys
try:
    d=json.load(sys.stdin); print(d.get('returned') if d.get('called') else 'ERROR '+str(d))
except Exception: print('ERROR no reply')"; }
t() { call MAE_Test "$1" "${2:-[]}"; }
con() { bash "$NGVO/tools/devbench-cli.sh" exec "$1" >/dev/null 2>&1; }
note() { bash "$NGVO/tools/devbench-cli.sh" notify "$1" >/dev/null 2>&1; echo "== $1"; }
wait_for() {  # wait_for <pattern> <seconds>: until MAE_Test.Status matches
  local i; for ((i = 0; i < $2; i += 3)); do t Status | grep -qE "$1" && return 0; close_pickers; sleep 3; done
  echo "   timeout waiting for $1: $(t Status)"; return 1
}
# OStim's partner/furniture pickers (UIExtensions list menus) can open on a scene start; closing one picks
# nothing extra, so the scene starts with just the partner.
close_pickers() {
  bash "$NGVO/tools/devbench-cli.sh" tool menu '{"action":"list"}' 2>/dev/null | grep -q '"CustomMenu"' || return 0
  echo "   closed a picker menu"; bash "$NGVO/tools/devbench-cli.sh" tool menu '{"action":"close","name":"CustomMenu"}' >/dev/null 2>&1
}
player_thread() { call OActor GetThreadID '[{"form":"0x14"}]'; }
scene() {  # starts a scene and waits for the opener set (OStim can take minutes to start one)
  t Start "[$V]" >/dev/null; wait_for 'set=[0-9]' 200
}
end_scene() {  # stops the scene and waits until OStim has really let go before anything else starts
  t Stop >/dev/null
  local i; for ((i = 0; i < 60; i += 2)); do [ "$(player_thread)" = "-1" ] && break; sleep 2; done
  wait_for 'thread=-1' 30; sleep 10
}

con "set GameHour to 12"
t Setup '[true]' >/dev/null
t EndConversation >/dev/null   # nobody left over in the fake conversation from an earlier run

note "1/9 unrated: she joins, nothing rated yet"
t Begin '["unrated"]'; t Forget "[$V]"; t Join "[$V]"; sleep 3

note "2/9 flow: opener then three rolled sets"
t Begin '["flow"]'; scene
for k in 1 2 3; do t Advance >/dev/null; sleep 5; done
t Begin '["summary"]'; end_scene

note "3/9 finish: man at 95 excitement"
t Begin '["finish"]'; scene; t Excite "[$P,95.0]"; wait_for 'finishPlayed=TRUE|finishPlayed=True|finishPlayed=true' 30; end_scene

note "4/9 climax, not satisfied: new chain"
t Begin '["climax-more"]'; scene; t Climax "[$V]"; sleep 1.5; t Satisfied "[$V,0]"; sleep 14; end_scene

note "5/9 climax, satisfied: no new chain"
t Begin '["climax-satisfied"]'; scene; t Climax "[$V]"; sleep 1.5; t Satisfied "[$V,1]"; sleep 14; end_scene

note "6/9 takeover: player picks a scene"
t Begin '["takeover"]'; scene; t Navigate '["leitocowgirl-1"]'; sleep 4; t Advance >/dev/null; sleep 6; end_scene

note "7/9 position requests"
t Begin '["request"]'; scene; t ChangePosition "[$V,\"cowgirl\"]"; sleep 6
t Begin '["request-bad"]'; t ChangePosition "[$V,\"upside down on the ceiling\"]"; sleep 4; end_scene

note "8/9 favourites: rating, then she joins"
t Begin '["favourites"]'; t Rate "[$V,\"cowgirl, missionary, doggystyle\"]"; sleep 2; t Join "[$V]"; sleep 3

note "9/9 bystander comment on her climax"
con "set MAE_BystanderChance to 1"
t Begin '["bystander"]'; t EndConversation >/dev/null; sleep 1; t Join "[$B]"; sleep 2; scene; t Climax "[$V]"; sleep 1.5; t Satisfied "[$V,1]"; sleep 8; end_scene
con "set MAE_BystanderChance to 0.25"

t Begin '["done"]'
note "tests finished"
echo; py -3 -I "$HERE/validate.py" "$LOG" "$CAT"
