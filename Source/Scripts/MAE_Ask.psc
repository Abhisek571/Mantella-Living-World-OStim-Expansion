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
; Testing: answers instead of the box when set, and only while MAE_TestMode is 1.
string testAnswer = ""
; The Hub could not be read: said once in the Papyrus log.
bool warnedNoHub = false

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

; The action's "source" names as conversation members, up to aiMax and without the player, doubles or anyone not
; intimate with the player; the speaker when none resolves and the speaker is intimate.
Actor[] Function Resolve(Form akSpeaker, Form akConversation, int aiArguments, int aiMax)
	MantellaConversation conversation = akConversation as MantellaConversation
	string[] names = SKSE_HTTP.getStringArray(aiArguments, "source")
	Actor[] found = PapyrusUtil.ActorArray(aiMax)
	int count = 0
	int i = 0
	While conversation && names && i < names.Length && count < aiMax
		Actor npc = MAE_Text.TalkActor(conversation, names[i])
		If npc && npc != PlayerRef && found.Find(npc) < 0 && IsIntimate(npc)
			found[count] = npc
			count += 1
		EndIf
		i += 1
	EndWhile
	If count == 0 && (akSpeaker as Actor) && (akSpeaker as Actor) != PlayerRef && IsIntimate(akSpeaker as Actor)
		found[0] = akSpeaker as Actor
		count = 1
	EndIf
	Return PapyrusUtil.ResizeActorArray(found, count)
EndFunction

; Close to the player as the Hub decides (the standing that offers affection); false when the Hub can't be read.
bool Function IsClose(Actor akNpc)
	MLW_Channel channel = Channel()
	Return channel && channel.CloseValue(akNpc) > 0
EndFunction

; Intimate with the player as the Hub decides (the standing that offers the sex actions); false when the Hub can't
; be read, so a renamed or merged Hub plugin never lets everyone through.
bool Function IsIntimate(Actor akNpc)
	MLW_Channel channel = Channel()
	Return channel && channel.IntimateValue(akNpc) > 0
EndFunction

MLW_Channel Function Channel()
	MLW_Channel channel = Game.GetFormFromFile(0x000823, "Mantella Living World - Integration Hub.esp") as MLW_Channel
	If !channel && !warnedNoHub
		warnedNoHub = true
		Debug.Trace("Mantella Living World - OStim Expansion: the Integration Hub can't be read, so no scene starts.")
	EndIf
	Return channel
EndFunction

; abAfterAffection: the request came during an affection scene, which has ended (MAE_Affection.Grow).
; One request at a time from its first check to the start: two at once could both start a scene.
Function Request(Actor[] akNpcs, bool abAfterAffection = false)
	float now = Utility.GetCurrentRealTime()
	If asking && now >= askedAt && now - askedAt < ASK_TIMEOUT
		Return
	EndIf
	asking = true
	askedAt = now
	RequestScene(akNpcs, abAfterAffection)
	If askedAt == now
		asking = false
	EndIf
EndFunction

; MAE_Affection holds its own requests back while this is true.
bool Function Asking()
	float now = Utility.GetCurrentRealTime()
	Return asking && now >= askedAt && now - askedAt < ASK_TIMEOUT
EndFunction

Function RequestScene(Actor[] akNpcs, bool abAfterAffection)
	MAE_Affection affection = Game.GetFormFromFile(0x000826, "Mantella Living World - OStim Expansion.esp") as MAE_Affection
	If OActor.IsInOStim(PlayerRef) || (affection && affection.Busy())
		; During an affection scene with her (or while it is starting) the request goes on once that scene has ended.
		If akNpcs.Length == 1 && affection && affection.Grow(akNpcs[0])
			Log("GROW|" + Names(akNpcs))
		EndIf
		Return
	EndIf
	If MAE_Text.MinorInTalk()
		Log("REFUSED|a child is in the conversation")
		Positions.AddMantellaEvent(Names(akNpcs) + " will not start anything with a child in the conversation.")
		Return
	EndIf
	int i = 0
	While i < akNpcs.Length
		If MAE_Text.IsChildActor(akNpcs[i]) || MAE_Text.CannotConsent(akNpcs[i])
			Log("REFUSED|" + akNpcs[i].GetDisplayName() + " cannot agree now")
			Positions.AddMantellaEvent(akNpcs[i].GetDisplayName() + " is in no state for that right now.")
			Return
		EndIf
		i += 1
	EndWhile
	If !MAE_Text.PlayerCanConsent()
		Log("REFUSED|the player cannot agree now")
		Positions.AddMantellaEvent("Nothing starts: this is no moment for it.")
		Return
	EndIf
	string answer = "Yes"
	If MAE_AskBeforeScene.GetValueInt() == 1
		answer = Ask(akNpcs)
	EndIf
	Log("ANSWER|" + answer + "|" + Names(akNpcs))
	If answer == "Yes"
		Actor[] actors = PapyrusUtil.ActorArray(akNpcs.Length + 1)
		actors[0] = PlayerRef
		i = 0
		While i < akNpcs.Length
			actors[i + 1] = akNpcs[i]
			i += 1
		EndWhile
		MAE_Text.WaitAfterScene()
		; The player may have started a scene meanwhile, or the box stayed open past ASK_TIMEOUT.
		If OActor.IsInOStim(PlayerRef) || (affection && affection.Busy())
			Log("REFUSED|someone is in a scene")
			Return
		EndIf
		i = 0
		While i < akNpcs.Length
			If MAE_Text.CannotConsent(akNpcs[i])
				Log("REFUSED|" + akNpcs[i].GetDisplayName() + " cannot agree now")
				Positions.AddMantellaEvent(akNpcs[i].GetDisplayName() + " is in no state for that right now.")
				Return
			EndIf
			i += 1
		EndWhile
		If MAE_Text.MinorInTalk() || !MAE_Text.PlayerCanConsent()
			Log("REFUSED|a child joined or the player cannot agree now")
			Positions.AddMantellaEvent("Nothing starts: this is no moment for it.")
			Return
		EndIf
		If OThread.QuickStart(actors) < 0
			Log("FAILED|QuickStart")
			Positions.AddMantellaEvent("The scene could not start, so " + Names(akNpcs) + " and the player carry on as they were.")
		ElseIf abAfterAffection
			Positions.AddMantellaEvent(Names(akNpcs) + " is ready now, and they start having sex.")
		EndIf
	ElseIf answer == "Skip"
		Skip(akNpcs)
	Else
		Positions.AddMantellaEvent(Names(akNpcs) + " wanted to start having sex with the player, but the player said no for now.")
	EndIf
EndFunction

; MAE_Affection: the affection scene with akNpc has ended and the restart gap is over.
Function RequestAfterAffection(Actor akNpc)
	Actor[] npcs = new Actor[1]
	npcs[0] = akNpc
	Log("AFTER AFFECTION|" + akNpc.GetDisplayName() + "|sinceEnd=" + MAE_Text.SecondsSinceSceneEnd())
	Request(npcs, true)
EndFunction

; No Skip in combat: time should not jump with enemies around.
string Function Ask(Actor[] akNpcs)
	If testAnswer != ""
		If MAE_TestMode.GetValueInt() == 1
			Return testAnswer
		EndIf
		; A test that ended without clearing it: never answer for the player outside test mode.
		testAnswer = ""
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
		; The Arousal module adds it to its tally (draining it first) and flips its satisfied flag on its next check.
		; Nobody listens without the Arousal module.
		int handle = ModEvent.Create("MLW_AddClimaxes")
		If handle
			ModEvent.PushForm(handle, akNpcs[i])
			ModEvent.PushInt(handle, 1)
			ModEvent.Send(handle)
		EndIf
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
