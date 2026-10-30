#!/usr/bin/env bash
# Launches the test game on screen 2, loads the test save, checks the setup reminder only shows once the
# player is in the world, then runs run-tests.sh. Leaves the game running; the caller closes it.
# usage: bash full-run.sh <launcher .bat> <save name> <partner form> <bystander form>
set -u
MO2=${MO2:?set MO2 to your Mod Organizer 2 instance folder}
HERE=$(cd "$(dirname "$0")" && pwd)
db() { bash "$MO2/tools/devbench-cli.sh" "$@" 2>&1; }
cmd.exe //c start "" explorer.exe "$(cygpath -w "$1")"
for i in $(seq 1 100); do db alive | grep -q 'no response' || break; sleep 6; done
echo "devbench up"; sleep 10
db exec "load $2" >/dev/null
# Skyrim warns that some content of the save is missing: Yes (index 0) continues the load, No cancels it.
for i in $(seq 1 60); do
  db tool menu '{"action":"describe"}' | grep -q 'not present' && { db tool menu '{"action":"accept","index":0}' >/dev/null; echo "accepted missing-content warning"; }
  db state | grep -q '"playerLoaded": true' && break; sleep 3
done
# Watch the menus until the reminder (a message box) shows; note what else was open at that moment.
for i in $(seq 1 150); do
  m=$(db tool menu '{"action":"list"}' | tr -d '\n ')
  if echo "$m" | grep -q '"messageBoxOpen":true'; then
    loaded=$(db state | grep -o '"playerLoaded": [a-z]*')
    echo "reminder shown with: $loaded"
    echo "$m" | grep -q '"HUDMenu"' && echo "reminder shown in the world: ok" || echo "REMINDER WITHOUT HUD (menu or loading screen)"
    db tool menu '{"action":"describe"}' | grep bodyText | head -c 120; echo
    db tool menu '{"action":"accept","index":1}' >/dev/null   # Later
    break
  fi
  sleep 2
done
sleep 5
# any other pop-up (e.g. a flow-build note): OK it
for k in 1 2 3; do db tool menu '{"action":"describe"}' | grep -q '"messageBoxOpen": true' || break; db tool menu '{"action":"accept","index":0}' >/dev/null; sleep 3; done
bash "$HERE/run-tests.sh" "$3" "$4"
