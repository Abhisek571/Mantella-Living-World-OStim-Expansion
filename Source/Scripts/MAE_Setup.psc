Scriptname MAE_Setup extends Quest
{Hotkey pop-ups and reminders. Aim at an NPC and press the hotkey to set her temperament (Auto, Reserved, Bold,
Forward); press it with nobody aimed at to run the manual setup. Once per game launch it reminds about a setup
that was never run and about scene flows that are not built yet, and it confirms a new flow build once. The
switches and sliders live on the "Adult Expansion" page of OStim's MCM (SKSE\Plugins\OStim\settings).
Temperament overrides are read by the OSL Aroused Bridge (MantellaOSLA_Main.GetTier).}

Actor Property PlayerRef Auto
MAE_Flows Property Flows Auto
GlobalVariable Property MAE_FlowsEnabled Auto
; DirectX scan code of the hotkey (0 = off).
GlobalVariable Property MAE_Hotkey Auto
; 0 Auto, 1 Reserved, 2 Bold, 3 Forward: the temperament of NPCs without their own override.
GlobalVariable Property MAE_TemperDefault Auto
; What Auto judges lust from: 0 Mantella's appetite rating (OSL values until rated), 1 OSL Aroused values only.
GlobalVariable Property MAE_TemperSource Auto
GlobalVariable Property MAE_SetupReminder Auto
GlobalVariable Property MAE_SetupDone Auto

string Property KEY_OVERRIDE = "MAE_TemperOverride" AutoReadOnly
string Property CATALOGUE = "MantellaAdultExpansion/flows.json" AutoReadOnly
string Property KEY_SEEN_BUILD = "MAE_SeenFlowBuild" AutoReadOnly

int registeredKey = 0
float lastRealTime = 0.0
float lastReminders = 0.0

Event OnInit()
	RegisterForMenu("Loading Menu")
	RegisterForSingleUpdate(5.0)
	; First start on an existing save: its loading screen is already over, so remind now.
	lastRealTime = Utility.GetCurrentRealTime()
	Utility.Wait(8.0)
	Reminders()
EndEvent

; Keeps the hotkey registration in step with the MCM setting.
Event OnUpdate()
	int wanted = MAE_Hotkey.GetValueInt()
	If wanted != registeredKey
		If registeredKey > 0
			UnregisterForKey(registeredKey)
		EndIf
		If wanted > 0
			RegisterForKey(wanted)
		EndIf
		registeredKey = wanted
	EndIf
	RegisterForSingleUpdate(10.0)
EndEvent

; A save finished loading. Real time starts again from zero when the game is relaunched, so reminders run
; once per launch rather than on every reload.
Event OnMenuClose(string asMenuName)
	float now = Utility.GetCurrentRealTime()
	bool newLaunch = now < lastRealTime || lastRealTime == 0.0
	lastRealTime = now
	If !newLaunch
		Return
	EndIf
	RegisterForSingleUpdate(1.0)
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
	If MAE_SetupReminder.GetValueInt() == 1 && MAE_SetupDone.GetValueInt() != 1
		string pick = SkyMessage.Show("Adult Expansion: setup hasn't been run yet.\n\nIt sets everyone's default temperament (how shy or forward NPCs are). You can also run it later: press the Adult Expansion hotkey while aiming at nobody.", "Run setup now", "Later", "Don't remind me")
		If pick == "Run setup now"
			RunSetup()
		ElseIf pick == "Don't remind me"
			MAE_SetupReminder.SetValueInt(0)
		EndIf
	EndIf
	If MAE_FlowsEnabled.GetValueInt() == 1
		If !Flows.Built()
			SkyMessage.Show("Scene flows aren't built yet: run the flow generator first.\n\nClose the game, run \"Build Flows.cmd\" (Mantella - Adult Expansion - OStim tools folder), enable \"Mantella - Adult Expansion - OStim - Flows\" in MO2, then start the game again.", "OK")
		Else
			int built = JsonUtil.GetIntValue(CATALOGUE, "packCount") * 10000 + JsonUtil.GetIntValue(CATALOGUE, "setCount")
			If StorageUtil.GetIntValue(None, KEY_SEEN_BUILD, 0) != built
				StorageUtil.SetIntValue(None, KEY_SEEN_BUILD, built)
				SkyMessage.Show("Flows built: " + JsonUtil.GetIntValue(CATALOGUE, "setCount") + " animation sets from " + JsonUtil.GetIntValue(CATALOGUE, "packCount") + " packs.", "OK")
			EndIf
		EndIf
	EndIf
EndFunction

; ---------------------------------------------------------------------------
; Hotkey
; ---------------------------------------------------------------------------

Event OnKeyDown(int aiKeyCode)
	If aiKeyCode != registeredKey || Utility.IsInMenuMode() || UI.IsTextInputEnabled()
		Return
	EndIf
	Actor target = Game.GetCurrentCrosshairRef() as Actor
	If target && target != PlayerRef && !target.IsDead()
		PickTemperament(target)
	Else
		RunSetup()
	EndIf
EndEvent

Function PickTemperament(Actor akActor)
	string name = akActor.GetDisplayName()
	int current = StorageUtil.GetIntValue(akActor, KEY_OVERRIDE, 0)
	string now = TierName(TierOf(akActor))
	If current == 0
		now += " (Auto)"
	Else
		now += " (set by you)"
	EndIf
	int pick = SkyMessage.Show("Temperament for " + name + "\nNow: " + now + "\n\nReserved never asks the player for sex, Bold asks at peak but accepts no, Forward is the most insistent. Auto works it out from her lust and closeness to you.", \
			"Auto", "Reserved (shy)", "Bold (asks)", "Forward (insistent)", "Cancel", getIndex = true) as int
	If pick >= 0 && pick <= 3
		StorageUtil.SetIntValue(akActor, KEY_OVERRIDE, pick)
		Debug.Notification(name + ": " + TierName(TierOf(akActor)))
	EndIf
EndFunction

; ---------------------------------------------------------------------------
; Manual setup
; ---------------------------------------------------------------------------

Function RunSetup()
	int def = SkyMessage.Show("Adult Expansion setup (1/2)\n\nDefault temperament for everyone without their own setting:", \
			"Auto (recommended)", "Reserved (shy)", "Bold (asks)", "Forward (insistent)", "Cancel", getIndex = true) as int
	If def < 0 || def > 3
		Return
	EndIf
	int source = SkyMessage.Show("Adult Expansion setup (2/2)\n\nWhen temperament is Auto, judge how lustful an NPC is from:", \
			"Mantella's appetite rating", "OSL Aroused values only", "Cancel", getIndex = true) as int
	If source < 0 || source > 1
		Return
	EndIf
	MAE_TemperDefault.SetValueInt(def)
	MAE_TemperSource.SetValueInt(source)
	MAE_SetupDone.SetValueInt(1)
	SkyMessage.Show(Results(), "OK")
EndFunction

; Followers nearby and every NPC with a Mantella appetite rating, with the temperament each now has.
string Function Results()
	Form[] rated = StorageUtil.debug_AllIntObjs()
	Actor[] nearby = MiscUtil.ScanCellNPCs(PlayerRef, 3000.0)
	Faction followers = Game.GetFormFromFile(0x0005C84E, "Skyrim.esm") as Faction ; CurrentFollowerFaction
	Actor[] people = new Actor[64]
	int n = 0
	int i = 0
	While i < rated.Length && n < people.Length
		Actor a = rated[i] as Actor
		If a && StorageUtil.HasIntValue(a, "MantellaOSLA_Appetite") && people.Find(a) < 0
			people[n] = a
			n += 1
		EndIf
		i += 1
	EndWhile
	i = 0
	While i < nearby.Length && n < people.Length
		Actor a = nearby[i]
		If a && a != PlayerRef && a.IsInFaction(followers) && people.Find(a) < 0
			people[n] = a
			n += 1
		EndIf
		i += 1
	EndWhile
	int[] counts = new int[3]
	string list = ""
	i = 0
	While i < n
		int tier = TierOf(people[i])
		counts[tier] = counts[tier] + 1
		If i < 18
			list += "\n" + people[i].GetDisplayName() + ": " + TierName(tier)
		EndIf
		i += 1
	EndWhile
	If n > 18
		list += "\n... and " + (n - 18) + " more"
	EndIf
	Return "Setup done: " + n + " NPCs set (" + counts[2] + " forward, " + counts[1] + " bold, " + counts[0] + " reserved)." + list + "\n\nChange anyone: aim at them and press the hotkey."
EndFunction

; The OSL Aroused Bridge decides the tier (it reads the overrides and defaults set here); reserved without it.
int Function TierOf(Actor akActor)
	MantellaOSLA_Main bridge = Game.GetFormFromFile(0x000800, "Mantella - OSL Aroused Bridge.esp") as MantellaOSLA_Main
	If bridge
		Return bridge.GetTier(akActor)
	EndIf
	int override = StorageUtil.GetIntValue(akActor, KEY_OVERRIDE, 0)
	If override > 0
		Return override - 1
	EndIf
	Return 0
EndFunction

string Function TierName(int aiTier)
	If aiTier == 2
		Return "forward"
	ElseIf aiTier == 1
		Return "bold"
	EndIf
	Return "reserved"
EndFunction
