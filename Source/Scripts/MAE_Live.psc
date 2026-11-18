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
; OStim undresses and redresses everyone, which Mantella would report item by item: the Integration Hub keeps
; Mantella quiet about outfits from the player's scene start until its quiet time after the scene ends.
string Property HUB_PLUGIN = "Mantella Living World - Integration Hub.esp" AutoReadOnly
string Property QUIET_REASON = "ostim" AutoReadOnly
; A scene that ended with no Mantella talk running (live test 12: two scenes with Gerdur before any talk began) is kept
; on each partner, "<game time>|<summary line>", and told to the next talk she joins. At most MAX_PENDING per partner.
string Property KEY_PENDING = "MAE_PendingScenes" AutoReadOnly
; Past MAX_PENDING the oldest is not lost: it is counted here and told as "and N earlier times".
string Property KEY_PENDING_EARLIER = "MAE_PendingScenesEarlier" AutoReadOnly
int Property MAX_PENDING = 3 AutoReadOnly
; With the Integration Hub a kept scene is sent at every talk the partner joins until the Hub has stored it in a memory
; (it lists "<name>|<scene time>" here); a talk that ends early no longer loses it (live test 16). Without the Hub it is
; sent once, as before.
string Property ACK_PATH = "MantellaLivingWorld/scene_ack.json" AutoReadOnly

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
	RegisterForModEvent("MLW_ReportRequest", "OnReportRequest")
	RegisterForModEvent("MantellaConversation_NPC_Added", "OnNpcAdded")
	RegisterForMenu("Loading Menu")
EndFunction

; A partner joins a talk: the scenes she had with the player while no talk was running are told now, oldest first,
; with how long ago. Kept while a child is in the talk (nothing about a scene reaches it).
Event OnNpcAdded(Form akActor)
	If StorageUtil.GetIntValue(None, "MLW_TimingOn", 0) == 1  ; speed testing (off by default): one stage-time row
		MiscUtil.WriteToFile("Data/SKSE/Plugins/StorageUtilData/MantellaLivingWorld/timing_game.csv", StorageUtil.GetIntValue(None, "MLW_TimingTalk", 0) + "," + Utility.GetCurrentRealTime() + ",MAE_Live,OnNpcAdded_start,\n", true, false)
	EndIf
	; the children around this talk are watched from now on (a far child is taken out of it before the next request)
	MAE_Npc children = Game.GetFormFromFile(0x000827, "Mantella Living World - OStim Expansion.esp") as MAE_Npc
	If children
		children.Watch()
	EndIf
	Actor npc = akActor as Actor
	If !npc || npc == PlayerRef || StorageUtil.StringListCount(npc, KEY_PENDING) == 0 || MAE_Text.MinorInTalk() || !MAE_Text.PlayerInTalk()
		Return  ; kept for her next talk with the player (never told to a radiant talk between NPCs)
	EndIf
	int earlier = StorageUtil.GetIntValue(npc, KEY_PENDING_EARLIER, 0)
	If earlier > 0
		AddEvent("Earlier still, with no conversation going on: " + npc.GetDisplayName() + " and the player had " + earlier + " more scene(s) together before these.")
		StorageUtil.UnsetIntValue(npc, KEY_PENDING_EARLIER)
	EndIf
	bool hub = Game.IsPluginInstalled(HUB_PLUGIN)
	If hub
		DropStored(npc)
		If StorageUtil.StringListCount(npc, KEY_PENDING) == 0
			Return
		EndIf
	EndIf
	float now = Utility.GetCurrentGameTime()
	int i = 0
	While i < StorageUtil.StringListCount(npc, KEY_PENDING)
		string entry = StorageUtil.StringListGet(npc, KEY_PENDING, i)
		int bar = StringUtil.Find(entry, "|")
		If bar > 0
			; {t=<game time>} lets the Integration Hub date the scene and pair it with the dialogue before it (taken out there)
			AddEvent("Earlier (" + AgoText(now - (StringUtil.Substring(entry, 0, bar) as float)) + "), with no conversation going on: " + StringUtil.Substring(entry, bar + 1) + " {t=" + StringUtil.Substring(entry, 0, bar) + "}")
		EndIf
		i += 1
	EndWhile
	If !hub
		StorageUtil.StringListClear(npc, KEY_PENDING)
	EndIf
	If StorageUtil.GetIntValue(None, "MLW_TimingOn", 0) == 1  ; speed testing (off by default): one stage-time row
		MiscUtil.WriteToFile("Data/SKSE/Plugins/StorageUtilData/MantellaLivingWorld/timing_game.csv", StorageUtil.GetIntValue(None, "MLW_TimingTalk", 0) + "," + Utility.GetCurrentRealTime() + ",MAE_Live,OnNpcAdded_end,\n", true, false)
	EndIf
EndEvent

; The kept scenes of this partner that the Integration Hub has stored: no longer sent.
Function DropStored(Actor akNpc)
	JsonUtil.Unload(ACK_PATH, false)  ; the Hub writes the file outside the game: read it fresh
	string name = akNpc.GetDisplayName()
	int i = StorageUtil.StringListCount(akNpc, KEY_PENDING)
	While i > 0
		i -= 1
		string entry = StorageUtil.StringListGet(akNpc, KEY_PENDING, i)
		int bar = StringUtil.Find(entry, "|")
		If bar > 0 && JsonUtil.StringListFind(ACK_PATH, "stored", name + "|" + StringUtil.Substring(entry, 0, bar)) >= 0
			StorageUtil.StringListRemoveAt(akNpc, KEY_PENDING, i)
		EndIf
	EndWhile
EndFunction

; "less than an hour ago", "about 3 hours ago", "2 days ago" for a span of game days.
string Function AgoText(float afDays)
	If afDays < 0.0
		afDays = 0.0
	EndIf
	int hours = Math.Floor(afDays * 24.0 + 0.5)
	If hours < 1
		Return "less than an hour ago"
	ElseIf hours < 24
		If hours == 1
			Return "about an hour ago"
		EndIf
		Return "about " + hours + " hours ago"
	EndIf
	int days = Math.Floor(afDays + 0.5)
	If days <= 1
		Return "a day ago"
	EndIf
	Return days + " days ago"
EndFunction

; The summary of a scene that ended with no talk running, kept on each partner for her next talk.
Function KeepForLater(string asLine)
	string entry = Utility.GetCurrentGameTime() + "|" + asLine
	int i = 0
	While i < sceneActors.Length
		Actor partner = sceneActors[i]
		If partner && partner != PlayerRef && !MAE_Text.IsChildActor(partner)
			StorageUtil.StringListAdd(partner, KEY_PENDING, entry)
			While StorageUtil.StringListCount(partner, KEY_PENDING) > MAX_PENDING
				StorageUtil.StringListRemoveAt(partner, KEY_PENDING, 0)
				StorageUtil.AdjustIntValue(partner, KEY_PENDING_EARLIER, 1)  ; counted, never silently lost
			EndWhile
		EndIf
		i += 1
	EndWhile
	TestLog("KEPT|" + asLine)
EndFunction

; The player's scene is about to start (before the undress): quiet Mantella about outfits.
Event OnPreStart(string asEventName, string asArg, float afNum, Form akSender)
	QuietOutfits()
EndEvent

; A save quit mid-scene comes back quiet: end it once the player is not in a scene.
Event OnMenuClose(string asMenuName)
	If OActor.IsInOStim(PlayerRef)
		Return
	EndIf
	; A scene saved mid-way never sends its end event: forget it, or a new scene with the same thread id is not seen as new.
	sceneThread = -1
	MLW_Hub hub = Hub()
	If hub
		hub.Unquiet(QUIET_REASON)
	EndIf
EndEvent

; The hub's troubleshooting report asks every module for its state.
Event OnReportRequest()
	MLW_Hub hub = Hub()
	If !hub
		Return
	EndIf
	int thread = OActor.GetThreadID(PlayerRef)
	string sceneId = "none"
	If thread >= 0
		sceneId = OThread.GetScene(thread)
	EndIf
	MAE_Flows flows = Game.GetFormFromFile(0x000822, "Mantella Living World - OStim Expansion.esp") as MAE_Flows
	hub.ReportAdd("ostim", "player thread=" + thread + " scene=" + sceneId + " live lines=" + MAE_LiveSceneLines.GetValueInt())
	If flows
		hub.ReportAdd("ostim", "flows built=" + flows.Built() + " sets=" + JsonUtil.GetIntValue("MantellaAdultExpansion/flows.json", "setCount") + " packs=" + JsonUtil.GetIntValue("MantellaAdultExpansion/flows.json", "packCount"))
	EndIf
EndEvent

MLW_Hub Function Hub()
	Return Game.GetFormFromFile(0x000820, HUB_PLUGIN) as MLW_Hub
EndFunction

; Asks the hub for quiet while the player's scene undresses and redresses everyone (hub setting "During scenes").
Function QuietOutfits()
	MLW_Hub hub = Hub()
	GlobalVariable duringScenes = Game.GetFormFromFile(0x000808, HUB_PLUGIN) as GlobalVariable
	If hub && (!duringScenes || duringScenes.GetValueInt() == 1)
		hub.Quiet(QUIET_REASON)
		TestLog("MUTE|outfit tracking off")
	EndIf
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
	If (afThreadID as int) == sceneThread
		lastActs = ""
		sceneThread = -1
		SendSummary()
	EndIf
	MLW_Hub hub = Hub()
	If hub
		hub.Log("ostim", "scene end, thread " + (afThreadID as int))
	EndIf
	If hub && !OActor.IsInOStim(PlayerRef)
		; The redress happens after the scene ends: the hub's quiet time covers it.
		GlobalVariable seconds = Game.GetFormFromFile(0x000801, HUB_PLUGIN) as GlobalVariable
		float delay = 10.0
		If seconds
			delay = seconds.GetValue()
		EndIf
		hub.Unquiet(QUIET_REASON, delay)
	EndIf
EndEvent

; ---------------------------------------------------------------------------
; Scene events
; ---------------------------------------------------------------------------

Event OnSceneChanged(string asEventName, string asArg, float afThreadID, Form akSender)
	int threadID = afThreadID as int
	string partners = Partners(threadID)
	If partners == ""
		DropChildScene(threadID)
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
	If !first && Elapsed(lastSceneLineTime, now) < SCENE_LINE_GAP
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
		DropChildScene(threadID)
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

; A child added to the tracked scene after it began: forgotten, so no pace, excitement or end-of-scene line follows.
Function DropChildScene(int aiThreadID)
	If aiThreadID == sceneThread && MAE_Text.ChildInThread(aiThreadID)
		TestLog("CHILD|scene " + aiThreadID + " forgotten")
		sceneThread = -1
		scenePartners = ""
		lastActs = ""
	EndIf
EndFunction

; A remark from a conversation member watching the scene, or "".
string Function BystanderLine(int aiThreadID, string asPartners)
	If !Bystander
		; Saves from before this property existed.
		Bystander = Game.GetFormFromFile(0x000821, "Mantella Living World - OStim Expansion.esp") as MAE_Bystander
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
	QuietOutfits()
	MLW_Hub hub = Hub()
	If hub
		hub.Log("ostim", "scene start, thread " + aiThreadID + ", with " + asPartners)
	EndIf
	sceneThread = aiThreadID
	sceneStart = Utility.GetCurrentRealTime()
	scenePartners = asPartners
	lastActs = ""
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
		If actors[i] != PlayerRef
			RequestTier(actors[i])
		EndIf
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
	If Elapsed(lastSpeedLineTime, now) < SPEED_LINE_GAP || !ConversationRunning()
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

; How she sounds, from the Arousal module's temperament (reserved / bold / forward). The Arousal module is optional,
; so its script is never named here: it answers MLW_TierRequest by writing MLW_Tier (temperament + 1) on the actor.
; The scene start asks; band lines come at least QUIET_START seconds later, and each one asks again for the next.
string Function StyleHint(Actor akPartner)
	int tier = 0
	If ArousalLoaded()
		tier = StorageUtil.GetIntValue(akPartner, "MLW_Tier", 1) - 1
		RequestTier(akPartner)
	EndIf
	If tier == 2 && MAE_DirtyTalk.GetValueInt() == 1
		Return "talking dirty"
	ElseIf tier >= 1
		Return "openly excited and saying what feels good"
	EndIf
	Return "breathless, only a few words, a little shy"
EndFunction

bool Function ArousalLoaded()
	Return Game.GetModByName("Mantella Living World - Arousal.esp") != 255 || Game.GetLightModByName("Mantella Living World - Arousal.esp") != 65535
EndFunction

Function RequestTier(Actor akActor)
	If !akActor || !ArousalLoaded()
		Return
	EndIf
	int handle = ModEvent.Create("MLW_TierRequest")
	If handle
		ModEvent.PushForm(handle, akActor)
		ModEvent.Send(handle)
	EndIf
EndFunction

; Seconds since a real-time stamp. Real time restarts at 0 on every launch, so a stamp from an earlier launch is ahead
; of now: it counts as long ago instead of blocking for as long as that launch ran.
float Function Elapsed(float afStamp, float afNow)
	If afStamp > afNow
		Return 100000.0
	EndIf
	Return afNow - afStamp
EndFunction

; One clean line for Mantella's memory once the player's scene is over, so the
; conversation summary keeps the gist instead of dozens of live lines.
Function SendSummary()
	If scenePartners == ""
		Return
	EndIf
	string line = SummaryLine()
	If sceneActs[0] == "" && NoClimax()
		; A dance, a cuddle or a scene stopped in its intro: no sex for Mantella to remember.
		line = WithPlayer(scenePartners) + " finished a scene together; nothing sexual happened."
	EndIf
	; no talk with the player (none, or a radiant one between NPCs), or a child in it: her next talk is told (OnNpcAdded)
	If !ConversationRunning() || MAE_Text.MinorInTalk()
		KeepForLater(line)
		Return
	EndIf
	; told at once with a turn of its own when Mantella waits for the player (live test 18: it only went out with the
	; player's next line, behind the scene's out-of-date lines, which the Hub now drops)
	SendLine(line, 0.0)
EndFunction

; True when nobody in the scene climaxed.
bool Function NoClimax()
	int i = 0
	While i < climaxCounts.Length
		If climaxCounts[i] > 0
			Return false
		EndIf
		i += 1
	EndWhile
	Return true
EndFunction

string Function SummaryLine()
	string line = WithPlayer(scenePartners) + " finished having sex"
	Location here = PlayerRef.GetCurrentLocation()
	If here && here.GetName() != ""
		line += " in " + here.GetName()
	EndIf
	int minutes = Math.Floor((Utility.GetCurrentRealTime() - sceneStart) / 60.0 + 0.5)
	; whole words: Papyrus keeps one copy of strings that differ only in case, so a lone "s" came out as "S" (live test 17)
	If minutes > 1
		line += " after about " + minutes + " minutes"
	ElseIf minutes == 1
		line += " after about 1 minute"
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

; A talk the player is in: a radiant talk between NPCs nearby never hears about the player's scene.
bool Function ConversationRunning()
	If MAE_TestMode.GetValueInt() == 1
		Return true
	EndIf
	Return MAE_Text.PlayerInTalk()
EndFunction

; "Mjoll and the player"; with two partners "Mjoll, Aela and the player" (Partners joins the last name with "and").
string Function WithPlayer(string asPartners)
	int last = StringUtil.Find(asPartners, " and ")
	If last < 0
		Return asPartners + " and the player"
	EndIf
	Return StringUtil.Substring(asPartners, 0, last) + ", " + StringUtil.Substring(asPartners, last + 5) + " and the player"
EndFunction

; Names of the non-player actors in a thread the player is part of, or "". "" for an affection thread: it is not
; tracked as a scene, so no live lines and no "finished having sex" summary (MAE_Affection tells Mantella itself).
string Function Partners(int aiThreadID)
	If MAE_LiveSceneLines.GetValueInt() != 1 || MAE_Text.IsAffectionThread(aiThreadID)
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
			If MAE_Text.IsChildActor(actors[i])
				Return ""  ; no line about a scene with a child in it, and no tracking of it
			EndIf
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
		If Elapsed(lastTurnTime, t) >= afCooldown && Utility.RandomFloat(0.0, 1.0) < afTurnChance
			lastTurnTime = t
			MAE_Text.TestLog("TURN|requested")
		Else
			MAE_Text.TestLog("TURN|skipped")
		EndIf
		Return
	EndIf
	MantellaConversation conversation = Game.GetFormFromFile(0x03D41A, "Mantella.esp") as MantellaConversation
	; Nothing about a scene reaches a conversation with a child in it, or one the player is not in.
	If !conversation || !conversation.IsRunning() || MAE_Text.MinorInTalk() || !MAE_Text.PlayerInTalk()
		Return
	EndIf
	AddEvent(asLine)
	If asExtra != ""
		AddEvent(asExtra)
	EndIf
	float now = Utility.GetCurrentRealTime()
	If !awaitingPlayer || conversation.GetIsTalking() || Elapsed(lastTurnTime, now) < afCooldown || Utility.RandomFloat(0.0, 1.0) >= afTurnChance
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
	; RequestContinueConversation(true) waits (up to 5 s) for an action result, then re-arms that wait for the next
	; action. Answer it first: sent after the call, it would cancel the next real action's wait instead.
	int done = ModEvent.Create("Mantella_ActionResponseCompleted")
	If done
		ModEvent.PushString(done, EVENT_TURN)
		ModEvent.Send(done)
	EndIf
	conversation.RequestContinueConversation(true)
EndFunction

Function AddEvent(string asLine)
	If MAE_TestMode.GetValueInt() == 1
		MAE_Text.TestLog("EVENT|" + asLine)
		Return
	EndIf
	If MAE_Text.MinorInTalk()
		Return
	EndIf
	int handle = ModEvent.Create("MantellaAddEvent")
	If handle
		ModEvent.PushString(handle, asLine)
		ModEvent.Send(handle)
	EndIf
EndFunction
