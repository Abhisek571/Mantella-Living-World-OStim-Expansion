Scriptname MAE_Ask extends Quest
{Mantella's sex and group sex actions with the player land here: a box asks the player Yes, No or Skip before
anything starts. Skip fades to black, lets time pass and records the scene as done: Mantella hears it, arousal and
climax counts move. Nothing goes through OStim's climax event, since other mods react to that one with effects
meant for a running scene, so Lover's Ledger and favourite positions don't count a skipped scene.
On its own quest: SKSE keeps one mod event registration per object.}

Actor Property PlayerRef Auto
MAE_Positions Property Positions Auto
; 1 = the box; 0 = scenes start straight away.
GlobalVariable Property MAE_AskBeforeScene Auto
GlobalVariable Property MAE_TestMode Auto

string Property ACTION_SEX = "mantella_mlw_sex" AutoReadOnly
string Property ACTION_GROUP = "mantella_mlw_sex_group" AutoReadOnly
; Same limit as the group action: the player and four NPCs.
int Property MAX_NPCS = 4 AutoReadOnly
float Property SKIP_HOURS = 0.5 AutoReadOnly
; OSL Aroused's default change for a climax.
float Property SKIP_AROUSAL_CHANGE = -50.0 AutoReadOnly
float Property SKIP_BLACK_SECONDS = 2.0 AutoReadOnly
; A box left open longer than this no longer blocks a new request (a save made with one open).
float Property ASK_TIMEOUT = 120.0 AutoReadOnly

bool asking = false
float askedAt = 0.0
; Testing: answers instead of the box when set.
string testAnswer = ""

Event OnInit()
	RegisterForModEvent("MantellaConversation_Advanced_Action_" + ACTION_SEX, "OnSexAdvanced")
	RegisterForModEvent("MantellaConversation_Advanced_Action_" + ACTION_GROUP, "OnGroupAdvanced")
EndEvent

Event OnSexAdvanced(Form akSpeaker, Form akConversation, int aiArguments)
	Actor[] npcs = Resolve(akSpeaker, akConversation, aiArguments, 1)
	If npcs.Length == 1
		Request(npcs)
	EndIf
EndEvent

Event OnGroupAdvanced(Form akSpeaker, Form akConversation, int aiArguments)
	Actor[] npcs = Resolve(akSpeaker, akConversation, aiArguments, MAX_NPCS)
	If npcs.Length >= 2
		Request(npcs)
	EndIf
EndEvent

; The action's "source" names as actors, up to aiMax and without the player or doubles; the speaker when none resolves.
Actor[] Function Resolve(Form akSpeaker, Form akConversation, int aiArguments, int aiMax)
	MantellaConversation conversation = akConversation as MantellaConversation
	string[] names = SKSE_HTTP.getStringArray(aiArguments, "source")
	Actor[] found = PapyrusUtil.ActorArray(aiMax)
	int count = 0
	int i = 0
	While conversation && names && i < names.Length && count < aiMax
		Actor npc = conversation.GetActorByName(names[i])
		If npc && npc != PlayerRef && found.Find(npc) < 0
			found[count] = npc
			count += 1
		EndIf
		i += 1
	EndWhile
	If count == 0 && (akSpeaker as Actor) && (akSpeaker as Actor) != PlayerRef
		found[0] = akSpeaker as Actor
		count = 1
	EndIf
	Return PapyrusUtil.ResizeActorArray(found, count)
EndFunction

Function Request(Actor[] akNpcs)
	float now = Utility.GetCurrentRealTime()
	If asking && now >= askedAt && now - askedAt < ASK_TIMEOUT
		Return
	EndIf
	If OActor.IsInOStim(PlayerRef)
		Return
	EndIf
	int i = 0
	While i < akNpcs.Length
		If MAE_Text.IsChildActor(akNpcs[i]) || OActor.IsInOStim(akNpcs[i])
			Return
		EndIf
		i += 1
	EndWhile
	asking = true
	askedAt = now
	string answer = "Yes"
	If MAE_AskBeforeScene.GetValueInt() == 1
		answer = Ask(akNpcs)
	EndIf
	asking = false
	Log("ANSWER|" + answer + "|" + Names(akNpcs))
	If answer == "Yes"
		Actor[] actors = PapyrusUtil.ActorArray(akNpcs.Length + 1)
		actors[0] = PlayerRef
		i = 0
		While i < akNpcs.Length
			actors[i + 1] = akNpcs[i]
			i += 1
		EndWhile
		OThread.QuickStart(actors)
	ElseIf answer == "Skip"
		Skip(akNpcs)
	Else
		Positions.AddMantellaEvent(Names(akNpcs) + " wanted to start having sex with the player, but the player said no for now.")
	EndIf
EndFunction

; No Skip in combat: time should not jump with enemies around.
string Function Ask(Actor[] akNpcs)
	If testAnswer != ""
		Return testAnswer
	EndIf
	string text = Names(akNpcs) + " want to start a scene with you."
	If akNpcs.Length == 1
		text = Names(akNpcs) + " wants to start a scene with you."
	EndIf
	If PlayerRef.IsInCombat()
		Return SkyMessage.Show(text, "Yes", "No")
	EndIf
	Return SkyMessage.Show(text, "Yes", "No", "Skip")
EndFunction

Function Skip(Actor[] akNpcs)
	; The same calls OStim's own fade makes: fade out, then hold the black until faded back.
	Game.FadeOutGame(true, true, 0.0, 1.0)
	Utility.Wait(0.7)
	Game.FadeOutGame(false, true, 99.0, 99.0)
	(Game.GetForm(0x38) as GlobalVariable).Mod(SKIP_HOURS)
	Satisfy(PlayerRef)
	int i = 0
	While i < akNpcs.Length
		Satisfy(akNpcs[i])
		; The Arousal module's tally, the same keys MAE_Flows reads; it flips its satisfied flag on its next check.
		StorageUtil.AdjustFloatValue(akNpcs[i], "MantellaOSLA_Climaxes", 1.0)
		StorageUtil.SetFloatValue(akNpcs[i], "MantellaOSLA_ClimaxTime", Utility.GetCurrentGameTime())
		i += 1
	EndWhile
	Utility.Wait(SKIP_BLACK_SECONDS)
	Game.FadeOutGame(false, true, 0.0, 1.0)
	string line = Names(akNpcs) + " and the player finished having sex"
	Location here = PlayerRef.GetCurrentLocation()
	If here && here.GetName() != ""
		line += " in " + here.GetName()
	EndIf
	Positions.AddMantellaEvent(line + ".")
EndFunction

; What OSL Aroused does for an OStim climax.
Function Satisfy(Actor akActor)
	OSLArousedNative.RegisterActorOrgasm(akActor)
	OSLArousedNative.ModifyArousal(akActor, SKIP_AROUSAL_CHANGE)
EndFunction

string Function Names(Actor[] akNpcs)
	string list = ""
	int i = 0
	While i < akNpcs.Length
		list = MAE_Text.ListAdd(list, akNpcs[i].GetDisplayName(), i == akNpcs.Length - 1 && i > 0)
		i += 1
	EndWhile
	Return list
EndFunction

Function Log(string asLine)
	If MAE_TestMode.GetValueInt() == 1
		MAE_Text.TestLog("ASK|" + asLine)
	EndIf
EndFunction

; ---------------------------------------------------------------------------
; Testing
; ---------------------------------------------------------------------------

; "Yes", "No" or "Skip" answers every request; "" shows the real box.
Function TestAnswerWith(string asAnswer)
	testAnswer = asAnswer
EndFunction
