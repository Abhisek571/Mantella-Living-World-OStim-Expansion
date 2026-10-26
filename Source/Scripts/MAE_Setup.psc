Scriptname MAE_Setup extends Quest
{Flow notices, once per game launch: scene flows not built yet (a message box, since it needs action), and a new
flow build confirmed once with a corner notification. Temperament,
the hotkey and the setup live in the Integration Hub (MLW_Setup); the OStim switches live on the "Living World"
page of OStim's MCM (SKSE\Plugins\OStim\settings).}

Actor Property PlayerRef Auto
MAE_Flows Property Flows Auto
GlobalVariable Property MAE_FlowsEnabled Auto

string Property CATALOGUE = "MantellaAdultExpansion/flows.json" AutoReadOnly
string Property KEY_SEEN_BUILD = "MAE_SeenFlowBuild" AutoReadOnly

float lastRealTime = 0.0
float lastReminders = 0.0

Event OnInit()
	RegisterForMenu("Loading Menu")
	; First start on an existing save: its loading screen is already over, so remind now.
	lastRealTime = Utility.GetCurrentRealTime()
	Utility.Wait(8.0)
	Reminders()
EndEvent

; A save finished loading. Real time starts again from zero when the game is relaunched, so notices show
; once per launch rather than on every reload.
Event OnMenuClose(string asMenuName)
	float now = Utility.GetCurrentRealTime()
	bool newLaunch = now < lastRealTime || lastRealTime == 0.0
	lastRealTime = now
	If !newLaunch
		Return
	EndIf
	Utility.Wait(3.0)
	Reminders()
EndEvent

Function Reminders()
	; The first start on an existing save can reach here from both OnInit and the loading screen.
	float now = Utility.GetCurrentRealTime()
	If lastReminders > 0.0 && now >= lastReminders && now - lastReminders < 60.0
		Return
	EndIf
	lastReminders = now
	; Never over the main menu or a loading screen: wait until the player is in the world.
	int tries = 0
	While (Utility.IsInMenuMode() || !PlayerRef.Is3DLoaded()) && tries < 120
		Utility.WaitMenuMode(1.0)
		tries += 1
	EndWhile
	If MAE_FlowsEnabled.GetValueInt() != 1
		Return
	EndIf
	If !Flows.Built()
		SkyMessage.Show("Scene flows aren't built yet.\n\nClose the game, run \"Build Flows\" (in the OStim Expansion's tools folder), enable \"Mantella Living World - OStim Expansion - Flows\" in your mod manager, then start the game again.", "OK")
	Else
		int built = JsonUtil.GetIntValue(CATALOGUE, "packCount") * 10000 + JsonUtil.GetIntValue(CATALOGUE, "setCount")
		If StorageUtil.GetIntValue(None, KEY_SEEN_BUILD, 0) != built
			StorageUtil.SetIntValue(None, KEY_SEEN_BUILD, built)
			Debug.Notification("Living World: flows built, " + JsonUtil.GetIntValue(CATALOGUE, "setCount") + " animation sets from " + JsonUtil.GetIntValue(CATALOGUE, "packCount") + " packs")
		EndIf
	EndIf
EndFunction
