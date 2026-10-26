Scriptname MAE_Live extends Quest
{During an OStim scene with the player, tells a running Mantella conversation
when the scene moves to a new act and when someone climaxes, then asks Mantella
for an event-only turn so the partner reacts without the player speaking.
The event-only turn needs the patched Mantella backend (mantella_event_turn);
without it the lines simply wait for the player's next reply. On its own quest
so the rest of the bridge works without OStim.}

Actor Property PlayerRef Auto
; 1 = send live scene lines.
GlobalVariable Property MAE_LiveSceneLines Auto
; Minimum real seconds between event turns; climaxes may come sooner (a third of it).
GlobalVariable Property MAE_LiveSceneCooldown Auto
; Bystander remarks on climaxes; see MAE_Bystander.
MAE_Bystander Property Bystander Auto
; Chance (0-1) to speak when a partner reaches a new excitement band; also the climax coin flip.
GlobalVariable Property MAE_TalkBandChance Auto
; Minimum real seconds between spoken scene reactions.
GlobalVariable Property MAE_TalkGap Auto
; 1 = forward NPCs may talk dirty.
GlobalVariable Property MAE_DirtyTalk Auto
; 1 = test mode: act as if a Mantella conversation is running and waiting, and log lines and turns instead of sending them.
GlobalVariable Property MAE_TestMode Auto

string Property EVENT_TURN = "mantella_event_turn" AutoReadOnly

; Set from Mantella's own HTTP replies: true while Mantella waits for the player.
bool awaitingPlayer = false
float lastTurnTime = -1000.0
string lastActs = ""
; Position changes come fast; only report one every SCENE_LINE_GAP seconds.
float lastSceneLineTime = -1000.0
float Property SCENE_LINE_GAP = 20.0 AutoReadOnly

; The player's current scene, for the end-of-scene summary, pace and excitement lines.
int sceneThread = -1
float sceneStart
string scenePartners
string[] sceneActs
Actor[] sceneActors
int[] climaxCounts
; Highest excitement band each partner was reported in since her last climax (0 = none yet).
int[] bandSaid
int lastSpeed = -1
string lastSpeedScene = ""
float lastSpeedLineTime = -1000.0
; The pace word last told to Mantella: a speed change inside the same band (slow, steady, fast) is not news.
string lastPaceWord = ""
; Excitement bands (OStim 0-100): warming up, into it, close. Nothing in a scene's first seconds.
float Property BAND_WARM = 30.0 AutoReadOnly
float Property BAND_INTO = 50.0 AutoReadOnly
float Property BAND_CLOSE = 75.0 AutoReadOnly
float Property QUIET_START = 30.0 AutoReadOnly
float Property EXCITEMENT_POLL = 3.0 AutoReadOnly
float Property SPEED_LINE_GAP = 8.0 AutoReadOnly
; OStim undresses and redresses everyone, which Mantella would report item by item. Its outfit tracking is muted
; from the player's scene start until this many seconds after the scene ends (the redress).
float Property UNMUTE_DELAY = 10.0 AutoReadOnly
string Property KEY_MUTED = "MAE_TrackingMuted" AutoReadOnly
string Property KEY_SAVED = "MAE_SavedTracking" AutoReadOnly
bool unmutePending = false

Event OnInit()
	Register()
EndEvent

Function Register()
	RegisterForModEvent("ostim_thread_scenechanged", "OnSceneChanged")
	RegisterForModEvent("ostim_actor_orgasm", "OnOrgasm")
	RegisterForModEvent("ostim_thread_end", "OnThreadEnd")
	RegisterForModEvent("ostim_thread_speedchanged", "OnSpeedChanged")
	RegisterForModEvent("SKSE_HTTP_OnHttpReplyReceived", "OnMantellaReply")
	RegisterForModEvent("MantellaConversation_Ended", "OnConversationEnded")
	RegisterForModEvent("ostim_prestart", "OnPreStart")
	RegisterForMenu("Loading Menu")
EndFunction

; The player's scene is about to start (before the undress): mute Mantella's outfit tracking.
Event OnPreStart(string asEventName, string asArg, float afNum, Form akSender)
	MuteOutfitTracking()
EndEvent

; A save quit mid-scene comes back muted: restore the tracking once the player is not in a scene.
Event OnMenuClose(string asMenuName)
	If StorageUtil.GetIntValue(None, KEY_MUTED, 0) == 1 && !OActor.IsInOStim(PlayerRef)
		RestoreOutfitTracking()
	EndIf
EndEvent

; Saves and switches off Mantella's equip/unequip and item added/removed tracking, for the player and NPCs.
Function MuteOutfitTracking()
	unmutePending = false
	If StorageUtil.GetIntValue(None, KEY_MUTED, 0) == 1
		Return
	EndIf
	MantellaRepository repo = Game.GetFormFromFile(0x000D62, "Mantella.esp") as MantellaRepository
	If !repo
		Return
	EndIf
	StorageUtil.IntListClear(None, KEY_SAVED)
	StorageUtil.IntListAdd(None, KEY_SAVED, repo.playerTrackingOnObjectEquipped as int)
	StorageUtil.IntListAdd(None, KEY_SAVED, repo.playerTrackingOnObjectUnequipped as int)
	StorageUtil.IntListAdd(None, KEY_SAVED, repo.playerTrackingOnItemAdded as int)
	StorageUtil.IntListAdd(None, KEY_SAVED, repo.playerTrackingOnItemRemoved as int)
	StorageUtil.IntListAdd(None, KEY_SAVED, repo.targetTrackingOnObjectEquipped as int)
	StorageUtil.IntListAdd(None, KEY_SAVED, repo.targetTrackingOnObjectUnequipped as int)
	StorageUtil.IntListAdd(None, KEY_SAVED, repo.targetTrackingItemAdded as int)
	StorageUtil.IntListAdd(None, KEY_SAVED, repo.targetTrackingItemRemoved as int)
	StorageUtil.SetIntValue(None, KEY_MUTED, 1)
	repo.playerTrackingOnObjectEquipped = false
	repo.playerTrackingOnObjectUnequipped = false
	repo.playerTrackingOnItemAdded = false
	repo.playerTrackingOnItemRemoved = false
	repo.targetTrackingOnObjectEquipped = false
	repo.targetTrackingOnObjectUnequipped = false
	repo.targetTrackingItemAdded = false
	repo.targetTrackingItemRemoved = false
	TestLog("MUTE|outfit tracking off")
EndFunction

; Puts back what MuteOutfitTracking saved.
Function RestoreOutfitTracking()
	unmutePending = false
	If StorageUtil.GetIntValue(None, KEY_MUTED, 0) != 1 || StorageUtil.IntListCount(None, KEY_SAVED) < 8
		StorageUtil.UnsetIntValue(None, KEY_MUTED)
		Return
	EndIf
	MantellaRepository repo = Game.GetFormFromFile(0x000D62, "Mantella.esp") as MantellaRepository
	If !repo
		Return
	EndIf
	repo.playerTrackingOnObjectEquipped = StorageUtil.IntListGet(None, KEY_SAVED, 0) == 1
	repo.playerTrackingOnObjectUnequipped = StorageUtil.IntListGet(None, KEY_SAVED, 1) == 1
	repo.playerTrackingOnItemAdded = StorageUtil.IntListGet(None, KEY_SAVED, 2) == 1
	repo.playerTrackingOnItemRemoved = StorageUtil.IntListGet(None, KEY_SAVED, 3) == 1
	repo.targetTrackingOnObjectEquipped = StorageUtil.IntListGet(None, KEY_SAVED, 4) == 1
	repo.targetTrackingOnObjectUnequipped = StorageUtil.IntListGet(None, KEY_SAVED, 5) == 1
	repo.targetTrackingItemAdded = StorageUtil.IntListGet(None, KEY_SAVED, 6) == 1
	repo.targetTrackingItemRemoved = StorageUtil.IntListGet(None, KEY_SAVED, 7) == 1
	StorageUtil.UnsetIntValue(None, KEY_MUTED)
	TestLog("MUTE|outfit tracking restored")
EndFunction

Function TestLog(string asLine)
	If MAE_TestMode.GetValueInt() == 1
		MAE_Text.TestLog(asLine)
	EndIf
EndFunction

Event OnMantellaReply(int aiHandle)
	awaitingPlayer = SKSE_HTTP.getString(aiHandle, "mantella_reply_type", "") == "mantella_player_talk"
EndEvent

Event OnConversationEnded()
	awaitingPlayer = false
EndEvent

Event OnThreadEnd(string asEventName, string asArg, float afThreadID, Form akSender)
	lastActs = ""
	If (afThreadID as int) == sceneThread
		sceneThread = -1
		SendSummary()
	EndIf
	If StorageUtil.GetIntValue(None, KEY_MUTED, 0) == 1 && !OActor.IsInOStim(PlayerRef)
		unmutePending = true
		RegisterForSingleUpdate(UNMUTE_DELAY)
	EndIf
EndEvent

; ---------------------------------------------------------------------------
; Scene events
; ---------------------------------------------------------------------------

Event OnSceneChanged(string asEventName, string asArg, float afThreadID, Form akSender)
	int threadID = afThreadID as int
	string partners = Partners(threadID)
	If partners == ""
		Return
	EndIf
	If threadID != sceneThread
		BeginScene(threadID, partners)
	EndIf
	string sceneID = OThread.GetScene(threadID)
	If sceneID == "" || OMetadata.IsTransition(sceneID)
		Return
	EndIf
	NoteActs(sceneID)
	string acts = SexualActs(sceneID)
	If acts == "" || acts == lastActs
		Return
	EndIf
	bool first = lastActs == ""
	float now = Utility.GetCurrentRealTime()
	If !first && now - lastSceneLineTime < SCENE_LINE_GAP
		; Skipped; lastActs stays, so the next change reports the newest acts.
		Return
	EndIf
	lastSceneLineTime = now
	lastActs = acts
	string line
	If first
		line = WithPlayer(partners) + " have started: " + acts + "."
	Else
		line = WithPlayer(partners) + " have moved on to " + acts + "."
	EndIf
	SendLine(line, MAE_LiveSceneCooldown.GetValue())
EndEvent

Event OnOrgasm(string asEventName, string asSceneID, float afThreadID, Form akSender)
	int threadID = afThreadID as int
	string partners = Partners(threadID)
	If partners == ""
		Return
	EndIf
	Actor climaxed = akSender as Actor
	If !climaxed
		Return
	EndIf
	If threadID == sceneThread
		int slot = SceneSlot(climaxed)
		If slot >= 0
			climaxCounts[slot] = climaxCounts[slot] + 1
			bandSaid[slot] = 0
		EndIf
	EndIf
	string who = climaxed.GetDisplayName()
	If climaxed == PlayerRef
		who = "The player"
	EndIf
	; The climax is always told; whether anyone speaks right away is a coin flip.
	SendLine(who + " just climaxed.", MAE_TalkGap.GetValue(), BystanderLine(threadID, partners), MAE_TalkBandChance.GetValue())
EndEvent

; A remark from a conversation member watching the scene, or "".
string Function BystanderLine(int aiThreadID, string asPartners)
	If !Bystander
		; Saves from before this property existed.
		Bystander = Game.GetFormFromFile(0x000821, "Mantella - Adult Expansion - OStim.esp") as MAE_Bystander
		If !Bystander
			Return ""
		EndIf
	EndIf
	Actor[] candidates = Bystander.Candidates(OThread.GetActors(aiThreadID))
	int i = 0
	While i < candidates.Length
		If candidates[i] && OActor.IsInOStim(candidates[i])
			candidates[i] = None
		EndIf
		i += 1
	EndWhile
	Return Bystander.CommentLine(candidates, asPartners)
EndFunction

; ---------------------------------------------------------------------------
; Scene tracking: pace, excitement and the end-of-scene summary
; ---------------------------------------------------------------------------

Function BeginScene(int aiThreadID, string asPartners)
	; Saves made before the pace event existed never ran OnInit again.
	Register()
	MuteOutfitTracking()
	sceneThread = aiThreadID
	sceneStart = Utility.GetCurrentRealTime()
	scenePartners = asPartners
	sceneActs = new string[16]
	sceneActors = new Actor[6]
	climaxCounts = new int[6]
	bandSaid = new int[6]
	lastSpeed = -1
	lastSpeedScene = ""
	lastPaceWord = ""
	Actor[] actors = OThread.GetActors(aiThreadID)
	int i = 0
	While i < actors.Length && i < sceneActors.Length
		sceneActors[i] = actors[i]
		i += 1
	EndWhile
	RegisterForSingleUpdate(EXCITEMENT_POLL)
EndFunction

; Slot of an actor in the current scene, adding them if they joined late; -1 if full.
int Function SceneSlot(Actor akActor)
	int i = sceneActors.Find(akActor)
	If i < 0
		i = sceneActors.Find(None)
		If i >= 0
			sceneActors[i] = akActor
		EndIf
	EndIf
	Return i
EndFunction

; Remembers every sexual act of the scene for the summary, without repeats.
Function NoteActs(string asSceneID)
	int[] actions = OMetadata.FindActionsSuperloadCSVv2(asSceneID, AnyActionTag = "sexual")
	int i = 0
	While i < actions.Length
		string act = MAE_Text.SceneActName(OMetadata.GetActionType(asSceneID, actions[i]))
		If act != "" && sceneActs.Find(act) < 0
			int free = sceneActs.Find("")
			If free >= 0
				sceneActs[free] = act
			EndIf
		EndIf
		i += 1
	EndWhile
EndFunction

; The thread's speed event also fires on scene changes; only a new speed in the
; same scene is reported. Queued without asking for a turn: it rides along with
; the next one.
Event OnSpeedChanged(string asEventName, string asArg, float afThreadID, Form akSender)
	int threadID = afThreadID as int
	If threadID != sceneThread
		Return
	EndIf
	string sceneID = OThread.GetScene(threadID)
	int speed = OThread.GetSpeed(threadID)
	If sceneID != lastSpeedScene || lastSpeed < 0
		lastSpeedScene = sceneID
		lastSpeed = speed
		Return
	EndIf
	If speed == lastSpeed
		Return
	EndIf
	bool faster = speed > lastSpeed
	lastSpeed = speed
	float now = Utility.GetCurrentRealTime()
	If now - lastSpeedLineTime < SPEED_LINE_GAP || !ConversationRunning()
		Return
	EndIf
	string pace = PaceWord(speed, OMetadata.GetMaxSpeed(sceneID))
	If pace == lastPaceWord
		Return
	EndIf
	lastPaceWord = pace
	lastSpeedLineTime = now
	string change = "The pace slows down"
	If faster
		change = "The pace picks up"
	EndIf
	AddEvent(change + "; it is now " + pace + ".")
EndEvent

string Function PaceWord(int aiSpeed, int aiMaxSpeed)
	If aiSpeed <= 0
		Return "very slow"
	ElseIf aiMaxSpeed > 0 && aiSpeed >= aiMaxSpeed
		Return "as fast as it goes"
	EndIf
	float ratio = (aiSpeed as float) / (aiMaxSpeed as float)
	If ratio <= 0.34
		Return "slow and gentle"
	ElseIf ratio <= 0.67
		Return "steady"
	EndIf
	Return "fast"
EndFunction

; Polls the partners' OStim excitement while the player's scene runs.
Event OnUpdate()
	If unmutePending && !OActor.IsInOStim(PlayerRef)
		RestoreOutfitTracking()
	EndIf
	If sceneThread < 0 || !OThread.IsRunning(sceneThread)
		Return
	EndIf
	int i = 0
	While i < sceneActors.Length
		Actor partner = sceneActors[i]
		If partner && partner != PlayerRef
			int band = Band(OActor.GetExcitement(partner))
			If band > bandSaid[i]
				bandSaid[i] = band
				; Each new band gets one roll; quiet at the very start of the scene.
				If Utility.GetCurrentRealTime() - sceneStart >= QUIET_START && Utility.RandomFloat(0.0, 1.0) < MAE_TalkBandChance.GetValue()
					SendLine(BandLine(partner, band), MAE_TalkGap.GetValue())
				EndIf
			EndIf
		EndIf
		i += 1
	EndWhile
	RegisterForSingleUpdate(EXCITEMENT_POLL)
EndEvent

int Function Band(float afExcitement)
	If afExcitement >= BAND_CLOSE
		Return 3
	ElseIf afExcitement >= BAND_INTO
		Return 2
	ElseIf afExcitement >= BAND_WARM
		Return 1
	EndIf
	Return 0
EndFunction

string Function BandLine(Actor akPartner, int aiBand)
	string name = akPartner.GetDisplayName()
	string howFar = " is warming up and starting to enjoy it"
	If aiBand == 2
		howFar = " is really into it now"
	ElseIf aiBand == 3
		howFar = " is close to climax"
	EndIf
	Return name + howFar + "; " + name + " reacts out loud in a sentence or two, " + StyleHint(akPartner) + "."
EndFunction

; How she sounds, from the OSL Aroused Bridge's temperament (reserved / bold / forward).
string Function StyleHint(Actor akPartner)
	int tier = 0
	Quest osla = Game.GetFormFromFile(0x000800, "Mantella - OSL Aroused Bridge.esp") as Quest
	MantellaOSLA_Main bridge = osla as MantellaOSLA_Main
	If bridge
		tier = bridge.GetTier(akPartner)
	EndIf
	If tier == 2 && MAE_DirtyTalk.GetValueInt() == 1
		Return "talking dirty"
	ElseIf tier >= 1
		Return "openly excited and saying what feels good"
	EndIf
	Return "breathless, only a few words, a little shy"
EndFunction

; One clean line for Mantella's memory once the player's scene is over, so the
; conversation summary keeps the gist instead of dozens of live lines.
Function SendSummary()
	If scenePartners == "" || !ConversationRunning()
		Return
	EndIf
	AddEvent(SummaryLine())
EndFunction

string Function SummaryLine()
	string line = WithPlayer(scenePartners) + " finished having sex"
	Location here = PlayerRef.GetCurrentLocation()
	If here && here.GetName() != ""
		line += " in " + here.GetName()
	EndIf
	int minutes = Math.Floor((Utility.GetCurrentRealTime() - sceneStart) / 60.0 + 0.5)
	If minutes >= 1
		line += " after about " + minutes + " minute"
		If minutes > 1
			line += "s"
		EndIf
	EndIf
	line += "."
	string acts = ""
	int count = sceneActs.Find("")
	If count < 0
		count = sceneActs.Length
	EndIf
	int i = 0
	While i < count
		acts = MAE_Text.ListAdd(acts, sceneActs[i], i == count - 1 && count > 1)
		i += 1
	EndWhile
	If acts != ""
		line += " They did " + acts + "."
	EndIf
	int climaxed = 0
	i = 0
	While i < sceneActors.Length
		If sceneActors[i] && climaxCounts[i] > 0
			climaxed += 1
		EndIf
		i += 1
	EndWhile
	string climaxes = ""
	int named = 0
	i = 0
	While i < sceneActors.Length
		If sceneActors[i] && climaxCounts[i] > 0
			string who = sceneActors[i].GetDisplayName()
			If sceneActors[i] == PlayerRef
				who = "the player"
			EndIf
			string times = climaxCounts[i] + " times"
			If climaxCounts[i] == 1
				times = "once"
			EndIf
			named += 1
			climaxes = MAE_Text.ListAdd(climaxes, who + " " + times, named == climaxed && climaxed > 1)
		EndIf
		i += 1
	EndWhile
	If climaxes != ""
		line += " Climaxes: " + climaxes + "."
	EndIf
	Return line
EndFunction

; Testing without OStim: fakes a finished scene with akPartner and returns its summary.
string Function TestSummary(Actor akPartner, int aiPartnerClimaxes, int aiPlayerClimaxes, float afMinutes, string asActsCSV)
	scenePartners = akPartner.GetDisplayName()
	sceneStart = Utility.GetCurrentRealTime() - afMinutes * 60.0
	sceneActs = new string[16]
	string[] acts = PapyrusUtil.StringSplit(asActsCSV, ",")
	int i = 0
	While i < acts.Length && i < sceneActs.Length
		sceneActs[i] = acts[i]
		i += 1
	EndWhile
	sceneActors = new Actor[6]
	climaxCounts = new int[6]
	bandSaid = new int[6]
	sceneActors[0] = PlayerRef
	sceneActors[1] = akPartner
	climaxCounts[0] = aiPlayerClimaxes
	climaxCounts[1] = aiPartnerClimaxes
	Return SummaryLine()
EndFunction

bool Function ConversationRunning()
	If MAE_TestMode.GetValueInt() == 1
		Return true
	EndIf
	MantellaConversation conversation = Game.GetFormFromFile(0x03D41A, "Mantella.esp") as MantellaConversation
	Return conversation && conversation.IsRunning()
EndFunction

; "Vega and the player"; with two partners "Vega, Nyri and the player" (Partners joins the last name with "and").
string Function WithPlayer(string asPartners)
	int last = StringUtil.Find(asPartners, " and ")
	If last < 0
		Return asPartners + " and the player"
	EndIf
	Return StringUtil.Substring(asPartners, 0, last) + ", " + StringUtil.Substring(asPartners, last + 5) + " and the player"
EndFunction

; Names of the non-player actors in a thread the player is part of, or "".
string Function Partners(int aiThreadID)
	If MAE_LiveSceneLines.GetValueInt() != 1
		Return ""
	EndIf
	Actor[] actors = OThread.GetActors(aiThreadID)
	If !actors || actors.Find(PlayerRef) < 0
		Return ""
	EndIf
	int count = 0
	int i = 0
	While i < actors.Length
		If actors[i] && actors[i] != PlayerRef
			count += 1
		EndIf
		i += 1
	EndWhile
	string list = ""
	int named = 0
	i = 0
	While i < actors.Length
		If actors[i] && actors[i] != PlayerRef
			named += 1
			list = MAE_Text.ListAdd(list, actors[i].GetDisplayName(), named == count && count > 1)
		EndIf
		i += 1
	EndWhile
	Return list
EndFunction

; The scene's sexual acts in plain words, without repeats.
string Function SexualActs(string asSceneID)
	int[] actions = OMetadata.FindActionsSuperloadCSVv2(asSceneID, AnyActionTag = "sexual")
	string[] seen = new string[8]
	int count = 0
	int i = 0
	While i < actions.Length && count < seen.Length
		string act = MAE_Text.SceneActName(OMetadata.GetActionType(asSceneID, actions[i]))
		If act != "" && seen.Find(act) < 0
			seen[count] = act
			count += 1
		EndIf
		i += 1
	EndWhile
	string list = ""
	i = 0
	While i < count
		list = MAE_Text.ListAdd(list, seen[i], i == count - 1 && count > 1)
		i += 1
	EndWhile
	Return list
EndFunction

; ---------------------------------------------------------------------------
; Sending
; ---------------------------------------------------------------------------

; Queues the line (and asExtra after it) as in-game events, then asks for an
; event-only turn when Mantella is waiting for the player, nobody is talking and
; the cooldown is over.
Function SendLine(string asLine, float afCooldown, string asExtra = "", float afTurnChance = 1.0)
	If MAE_TestMode.GetValueInt() == 1
		AddEvent(asLine)
		If asExtra != ""
			AddEvent(asExtra)
		EndIf
		float t = Utility.GetCurrentRealTime()
		If t - lastTurnTime >= afCooldown && Utility.RandomFloat(0.0, 1.0) < afTurnChance
			lastTurnTime = t
			MAE_Text.TestLog("TURN|requested")
		Else
			MAE_Text.TestLog("TURN|skipped")
		EndIf
		Return
	EndIf
	MantellaConversation conversation = Game.GetFormFromFile(0x03D41A, "Mantella.esp") as MantellaConversation
	If !conversation || !conversation.IsRunning()
		Return
	EndIf
	AddEvent(asLine)
	If asExtra != ""
		AddEvent(asExtra)
	EndIf
	float now = Utility.GetCurrentRealTime()
	If !awaitingPlayer || conversation.GetIsTalking() || now - lastTurnTime < afCooldown || Utility.RandomFloat(0.0, 1.0) >= afTurnChance
		Return
	EndIf
	; Let Mantella take the queued event before the turn reads it.
	Utility.Wait(0.5)
	If !awaitingPlayer
		Return
	EndIf
	awaitingPlayer = false
	lastTurnTime = now
	conversation.AddExtraRequestAction(EVENT_TURN)
	conversation.RequestContinueConversation(true)
	; RequestContinueConversation(true) leaves Mantella expecting an action result;
	; clear that so the next real action does not wait for it.
	int done = ModEvent.Create("Mantella_ActionResponseCompleted")
	If done
		ModEvent.PushString(done, EVENT_TURN)
		ModEvent.Send(done)
	EndIf
EndFunction

Function AddEvent(string asLine)
	If MAE_TestMode.GetValueInt() == 1
		MAE_Text.TestLog("EVENT|" + asLine)
		Return
	EndIf
	int handle = ModEvent.Create("MantellaAddEvent")
	If handle
		ModEvent.PushString(handle, asLine)
		ModEvent.Send(handle)
	EndIf
EndFunction
