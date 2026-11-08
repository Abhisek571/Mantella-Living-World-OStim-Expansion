Scriptname MAE_Affection extends Quest
{Short affection with the player from a Mantella action, with no box first: kisses, holding hands, hugs, cuddles,
head pats and dances. Scenes come only from the lists in StorageUtilData\MantellaAdultExpansion\affection.json, never
from tags, and naming the scene skips OStim's picker. Lists are per pair (any, _mf, _ff, _mm), and who does it is read
from the scene's action, so "he kisses her neck" and "she kisses his" both work. The thread carries the metadata
mlw_affection (MAE_Text.IsAffectionThread), so flows, live lines and favourites leave it alone. Nothing undresses,
nobody navigates, and this script's own timer ends it: OStim's SetDuration can't be extended or cancelled.
A sex request during it (MAE_Ask) ends it first, then the Ask First box comes after OStim's restart gap.
The kinds in stringList "intimate_kinds" (the lap dance and the dance from a chair) need the Hub's intimate standing:
for anyone else they are neither picked nor named in the fact.
On its own quest: SKSE keeps one mod event registration per object.}

Actor Property PlayerRef Auto
MAE_Positions Property Positions Auto
MAE_Ask Property Ask Auto
MAE_Live Property Live Auto
GlobalVariable Property MAE_TestMode Auto

string Property ACTION_AFFECTION = "mantella_mlw_affection" AutoReadOnly
string Property METADATA = "mlw_affection" AutoReadOnly
; stringList "kinds", and per kind: stringList <kind>, <kind>_mf, <kind>_ff, <kind>_mm (scenes for that pair);
; float <kind> (seconds); string who_<kind> (action types that tell who does it), furniture_<kind> (OStim furniture
; type it needs), name_<kind>, line_<kind> and end_<kind> ({a} does it, {b} is the other).
string Property LIST_FILE = "MantellaAdultExpansion/affection.json" AutoReadOnly
; The NPC's file the Hub's action filter reads ("lw_gate": "close+affection=1") and the fact the NPC is told.
string Property NPC_DIR = "MantellaLivingWorld/npc/" AutoReadOnly
string Property HUB_PLUGIN = "Mantella Living World - Integration Hub.esp" AutoReadOnly
; StorageUtil on the NPC: the kinds found when she joined the talk, for the fact; KEY_KINDS without the intimate kinds,
; KEY_KINDS_INTIMATE with them.
string Property KEY_KINDS = "MAE_AffectionKinds" AutoReadOnly
string Property KEY_KINDS_INTIMATE = "MAE_AffectionKindsIntimate" AutoReadOnly
float Property DEFAULT_SECONDS = 30.0 AutoReadOnly
; A start that never reached ostim_thread_start (actors walk together first, often 45 s) stops blocking after this.
float Property START_TIMEOUT = 240.0 AutoReadOnly
; How far from the player a free chair may be.
float Property FURNITURE_RADIUS = 1000.0 AutoReadOnly

bool starting = false
bool started = false
; The talk ended before the thread started: stop it as soon as it does.
bool stopOnStart = false
; No line about the end (the talk ended, or the sex request already told Mantella).
bool silentEnd = false
int thread = -1
Actor partner
; Who does it: the partner or the player.
Actor doer
string currentKind = ""
string currentFurniture = ""
float actionAt = 0.0
float startAt = 0.0
; After the end: "" nothing, "grow" the Ask First box, "kind" start nextKind.
string afterEnd = ""
string nextKind = ""
string nextWho = ""
; Set by PickScene: who does it in the scene it picked.
Actor pickedDoer
; Counts ended talks, so a wait can tell the talk ended meanwhile.
int talkEnds = 0
; Testing: replaces the listed seconds when above 0.
float testSeconds = 0.0
; One request at a time, from its first check to the start: two at once could both start a scene.
bool requesting = false
float requestAt = 0.0
int requestToken = 0
; When this scene's timer is due: an older timer that still fires is ignored.
float timerDue = 0.0
; One writer of the NPC file at a time (the join and a refresh came at the same moment and the older one won).
bool fileLock = false

Event OnInit()
	RegisterForModEvent("MantellaConversation_Advanced_Action_" + ACTION_AFFECTION, "OnAffectionAdvanced")
	RegisterForModEvent("MantellaConversation_NPC_Added", "OnNpcAdded")
	RegisterForModEvent("MantellaConversation_Ended", "OnConversationEnded")
	RegisterForModEvent("ostim_thread_start", "OnThreadStart")
	RegisterForModEvent("ostim_thread_end", "OnThreadEnd")
	RegisterForModEvent("MLW_RefreshNpc", "OnRefreshNpc")
	RegisterForMenu("Loading Menu")
EndEvent

; ---------------------------------------------------------------------------
; The action is offered only when a listed scene for this pair is installed
; ---------------------------------------------------------------------------

; Writes the gate and a fact naming the kinds that would work with her here (chairs counted as they are now).
Event OnNpcAdded(Form akActor)
	Actor npc = akActor as Actor
	If !npc || npc == PlayerRef
		Return
	EndIf
	If MAE_Text.IsChildActor(npc)
		StorageUtil.SetStringValue(npc, KEY_KINDS, "")
		StorageUtil.SetStringValue(npc, KEY_KINDS_INTIMATE, "")
	Else
		AvailableKinds(npc)
	EndIf
	; Also here: OnInit has already run on a save made before this event was added.
	RegisterForModEvent("MLW_RefreshNpc", "OnRefreshNpc")
	LockFile()
	string path = GateFile(npc)
	WriteFact(npc, path)
	JsonUtil.Save(path)
	fileLock = false
	Log("GATE|" + npc.GetDisplayName() + "|" + JsonUtil.GetIntValue(path, "affection", 0) + "|" + KindsFor(npc))
EndEvent

; Closeness may be set after the join (Arousal's own NPC_Added handler, then MLW_RefreshNpc): the fact follows it.
Event OnRefreshNpc(Form akActor)
	Actor npc = akActor as Actor
	If !npc || npc == PlayerRef
		Return
	EndIf
	LockFile()
	string path = GateFile(npc)
	If WriteFact(npc, path)
		JsonUtil.Save(path)
	EndIf
	fileLock = false
EndEvent

; Waits while another handler writes an NPC file (at most 5 s, so a lost handler can't block it for good).
Function LockFile()
	int tries = 0
	While fileLock && tries < 50
		Utility.Wait(0.1)
		tries += 1
	EndWhile
	fileLock = true
EndFunction

; The kinds for her standing now: with the intimate kinds only while she is intimate with the player.
string Function KindsFor(Actor akNpc)
	If Ask.IsIntimate(akNpc)
		Return StorageUtil.GetStringValue(akNpc, KEY_KINDS_INTIMATE, "")
	EndIf
	Return StorageUtil.GetStringValue(akNpc, KEY_KINDS, "")
EndFunction

; The gate and the fact follow her standing, which may change mid-talk; the fact goes only to close NPCs, like the
; action, and expires today. True when the file changed.
bool Function WriteFact(Actor akNpc, string asPath)
	string kinds = KindsFor(akNpc)
	bool changed = false
	If JsonUtil.GetIntValue(asPath, "affection", -1) != (kinds != "") as int
		JsonUtil.SetIntValue(asPath, "affection", (kinds != "") as int)
		changed = true
	EndIf
	string old = JsonUtil.GetStringValue(asPath, "fact_affection", "")
	string fact = ""
	If kinds != "" && Ask.IsClose(akNpc)
		int today = Utility.GetCurrentGameTime() as int
		fact = today + "|" + today + "|1|Affection you and the player could share right now: " + kinds + "."
	EndIf
	If fact == old
		Return changed
	ElseIf fact != ""
		JsonUtil.SetStringValue(asPath, "fact_affection", fact)
	Else
		JsonUtil.UnsetStringValue(asPath, "fact_affection")
	EndIf
	Return true
EndFunction

; The listed names of every kind with an installed scene for this pair, e.g. "a kiss, a hug and cuddling", stored on
; her as KEY_KINDS (without the intimate kinds) and KEY_KINDS_INTIMATE (with them); returns the one for her standing
; now. A kind with scenes for one of them only says who, e.g. "(only you do it)".
string Function AvailableKinds(Actor akNpc)
	string[] all = OLibrary.GetAllScenes()
	bool chair = false
	bool chairChecked = false
	int count = JsonUtil.StringListCount(LIST_FILE, "kinds")
	string[] names = new string[16]
	bool[] intimate = new bool[16]
	int found = 0
	int i = 0
	While i < count && found < names.Length
		string kind = JsonUtil.StringListGet(LIST_FILE, "kinds", i)
		bool fits = true
		If Furniture(kind) != ""
			If !chairChecked
				chair = FreeFurniture("chair") != None
				chairChecked = true
			EndIf
			fits = Furniture(kind) != "chair" || chair
		EndIf
		; Either of them doing it counts: with OStim's actor order some kinds have scenes only for one of them.
		If fits
			bool npcDoes = PickScene(kind, akNpc, "", "", all, true) != ""
			bool playerDoes = PickScene(kind, akNpc, "player", "", all, true) != ""
			If npcDoes || playerDoes
				names[found] = JsonUtil.GetStringValue(LIST_FILE, "name_" + kind, kind)
				If JsonUtil.GetStringValue(LIST_FILE, "who_" + kind, "") != ""
					If !playerDoes
						names[found] = names[found] + " (only you do it)"
					ElseIf !npcDoes
						names[found] = names[found] + " (only the player does it)"
					EndIf
				EndIf
				intimate[found] = IntimateKind(kind)
				found += 1
			EndIf
		EndIf
		i += 1
	EndWhile
	StorageUtil.SetStringValue(akNpc, KEY_KINDS, KindList(names, intimate, found, false))
	StorageUtil.SetStringValue(akNpc, KEY_KINDS_INTIMATE, KindList(names, intimate, found, true))
	Return KindsFor(akNpc)
EndFunction

; The first aiFound names as "a, b and c", the intimate ones only when abIntimate.
string Function KindList(string[] asNames, bool[] abIntimate, int aiFound, bool abWithIntimate)
	int last = -1
	int i = 0
	While i < aiFound
		If abWithIntimate || !abIntimate[i]
			last = i
		EndIf
		i += 1
	EndWhile
	string list = ""
	i = 0
	While i < aiFound
		If abWithIntimate || !abIntimate[i]
			list = MAE_Text.ListAdd(list, asNames[i], i == last && list != "")
		EndIf
		i += 1
	EndWhile
	Return list
EndFunction

; The base record's FormID as its last 6 hex digits, the name of the NPC's file (MLW_Channel.BaseId).
string Function GateFile(Actor akNpc)
	string digits = "0123456789ABCDEF"
	int value = akNpc.GetActorBase().GetFormID()
	string id = ""
	int i = 2
	While i < 8
		id += StringUtil.GetNthChar(digits, Math.LogicalAnd(Math.RightShift(value, 28 - i * 4), 15))
		i += 1
	EndWhile
	Return NPC_DIR + id + ".json"
EndFunction

; ---------------------------------------------------------------------------
; Scenes
; ---------------------------------------------------------------------------

; The pair in the order the thread gets it: with a starting scene OStim keeps the order it is given, so it is sorted
; first (a scene's man goes first).
Actor[] Function SortedPair(Actor akNpc)
	Actor[] actors = new Actor[2]
	actors[0] = PlayerRef
	actors[1] = akNpc
	Return OActorUtil.Sort(actors, OActorUtil.EmptyArray())
EndFunction

; A random installed scene of the kind for this pair, another than asCurrent if there is one; "" if none, and "" for
; an intimate kind unless she is intimate with the player (abAnyStanding: AvailableKinds lists both). For a kind
; with who_<kind>, asWho "player" or "npc" picks the scenes where that one does it ("" = the NPC). Sets pickedDoer.
string Function PickScene(string asKind, Actor akNpc, string asWho, string asCurrent = "", string[] asAll = None, bool abAnyStanding = false)
	If asKind == "" || (!abAnyStanding && IntimateKind(asKind) && !Ask.IsIntimate(akNpc))
		Return ""
	EndIf
	If !asAll
		asAll = OLibrary.GetAllScenes()
	EndIf
	Actor[] pair = SortedPair(akNpc)
	string pairKey = "_mf"
	If pair[0].GetLeveledActorBase().GetSex() == pair[1].GetLeveledActorBase().GetSex()
		pairKey = "_mm"
		If pair[0].GetLeveledActorBase().GetSex() == 1
			pairKey = "_ff"
		EndIf
	EndIf
	string[] found = new string[32]
	int count = AddInstalled(found, 0, asKind, asAll)
	count = AddInstalled(found, count, asKind + pairKey, asAll)
	string types = JsonUtil.GetStringValue(LIST_FILE, "who_" + asKind, "")
	Actor[] doers = new Actor[32]
	Actor wanted = akNpc
	If asWho == "player"
		wanted = PlayerRef
	EndIf
	int kept = 0
	int i = 0
	While i < count
		Actor who = akNpc
		If types != ""
			who = Doer(found[i], pair, types)
		EndIf
		If types == "" || who == wanted
			found[kept] = found[i]
			doers[kept] = who
			kept += 1
		EndIf
		i += 1
	EndWhile
	If kept == 0
		Return ""
	EndIf
	i = Utility.RandomInt(0, kept - 1)
	If kept > 1 && found[i] == asCurrent
		i = (i + 1) % kept
	EndIf
	pickedDoer = doers[i]
	Return found[i]
EndFunction

int Function AddInstalled(string[] asFound, int aiCount, string asKey, string[] asAll)
	int total = JsonUtil.StringListCount(LIST_FILE, asKey)
	int i = 0
	While i < total && aiCount < asFound.Length
		string sceneID = JsonUtil.StringListGet(LIST_FILE, asKey, i)
		If asAll.Find(sceneID) >= 0
			asFound[aiCount] = sceneID
			aiCount += 1
		EndIf
		i += 1
	EndWhile
	Return aiCount
EndFunction

; The actor of the scene's first action of those types, as placed in the sorted pair; None if it has none.
Actor Function Doer(string asScene, Actor[] akPair, string asTypes)
	int[] actions = OMetadata.FindActionsSuperloadCSVv2(asScene, Types = asTypes)
	If actions.Length == 0
		Return None
	EndIf
	int position = OMetadata.GetActionActor(asScene, actions[0])
	If position < 0 || position >= akPair.Length
		Return None
	EndIf
	Return akPair[position]
EndFunction

; A kind listed in "intimate_kinds": only with an NPC intimate with the player.
bool Function IntimateKind(string asKind)
	Return JsonUtil.StringListFind(LIST_FILE, "intimate_kinds", asKind) >= 0
EndFunction

string Function Furniture(string asKind)
	Return JsonUtil.GetStringValue(LIST_FILE, "furniture_" + asKind, "")
EndFunction

; The closest free furniture of exactly that type near the player (a bench counts as a chair to OStim, but its
; scenes are placed differently); None if there is none.
ObjectReference Function FreeFurniture(string asType)
	If asType == ""
		Return None
	EndIf
	ObjectReference[] found = OFurniture.FindFurniture(2, PlayerRef, FURNITURE_RADIUS)
	int i = 0
	While found && i < found.Length
		If found[i] && OFurniture.GetFurnitureType(found[i]) == asType
			Return found[i]
		EndIf
		i += 1
	EndWhile
	Return None
EndFunction

; ---------------------------------------------------------------------------
; The action
; ---------------------------------------------------------------------------

Event OnAffectionAdvanced(Form akSpeaker, Form akConversation, int aiArguments)
	string who = Positions.Trim(SKSE_HTTP.getString(aiArguments, "who", ""))
	If who != "player"
		who = ""
	EndIf
	string kind = Positions.Trim(SKSE_HTTP.getString(aiArguments, "kind", ""))
	; Mantella empties the talk before it sends its end, so an action that comes after the end is seen here.
	MantellaConversation conversation = akConversation as MantellaConversation
	If conversation && conversation.CountActorsInConversation() == 0
		Log("REFUSED|the talk has ended|" + kind)
		Return
	EndIf
	Request(akSpeaker as Actor, kind, who)
EndEvent

Function Request(Actor akNpc, string asKind, string asWho = "")
	; Counted first: a talk that ends from here on cancels the start.
	int ends = talkEnds
	float now = Utility.GetCurrentRealTime()
	If requesting && now >= requestAt && now - requestAt < START_TIMEOUT
		Log("REFUSED|still starting")
		Return
	EndIf
	requesting = true
	requestAt = now
	requestToken += 1
	int token = requestToken
	bool grow = RequestScene(akNpc, asKind, asWho, now, ends)
	If requestToken == token
		requesting = false
	EndIf
	If grow
		; A sex request came while this was starting: the Ask First box now that this request has let go.
		Ask.RequestAfterAffection(akNpc)
	EndIf
EndFunction

; True when a sex request came meanwhile and the Ask First box should follow.
bool Function RequestScene(Actor akNpc, string asKind, string asWho, float now, int ends)
	If !akNpc || akNpc == PlayerRef || MAE_Text.IsChildActor(akNpc)
		Log("REFUSED|no fitting speaker|" + asKind)
		Return false
	EndIf
	If !Ask.IsClose(akNpc)
		Log("REFUSED|not close|" + asKind)
		Return false
	EndIf
	; The Ask First box is open: its Yes would start a scene on top of this one.
	If Ask.Asking()
		Log("REFUSED|the box is open|" + asKind)
		Return false
	EndIf
	Log("ACTION|" + asKind + "|" + akNpc.GetDisplayName() + "|who=" + asWho)
	If starting && (now < actionAt || now - actionAt >= START_TIMEOUT)
		Forget()
	EndIf
	If starting
		Log("REFUSED|still starting")
		Return false
	ElseIf started && akNpc == partner && OThread.IsRunning(thread) && OThread.HasMetadata(thread, METADATA)
		Switch(asKind, asWho)
		Return false
	EndIf
	If OActor.IsInOStim(PlayerRef) || OActor.IsInOStim(akNpc)
		Log("REFUSED|someone is in a scene")
		Return false
	EndIf
	If MAE_Text.CannotConsent(akNpc) || !MAE_Text.PlayerCanConsent() || MAE_Text.MinorInTalk()
		Log("REFUSED|cannot agree now, or a child is in the conversation")
		NoScene(akNpc, asKind)
		Return false
	EndIf
	ObjectReference furnitureRef = None
	string furnitureType = Furniture(asKind)
	If furnitureType != ""
		furnitureRef = FreeFurniture(furnitureType)
		If !furnitureRef
			NoFurniture(akNpc, furnitureType)
			Return false
		EndIf
	EndIf
	string sceneID = PickScene(asKind, akNpc, asWho)
	If sceneID == ""
		NoSceneFor(akNpc, asKind, asWho)
		Return false
	EndIf
	starting = true
	started = false
	stopOnStart = false
	silentEnd = false
	afterEnd = ""
	thread = -1
	partner = akNpc
	doer = pickedDoer
	currentKind = asKind
	currentFurniture = furnitureType
	actionAt = now
	; No timer of this scene yet: one that fires before OnThreadStart sets it is an older one.
	timerDue = 1000000.0
	MAE_Text.WaitAfterScene()
	If talkEnds != ends
		; The talk ended during the wait: nothing starts.
		Log("STOP|talk ended before the call")
		Forget()
		Return false
	ElseIf !starting || partner != akNpc
		; Forgotten during the wait: a save was loaded.
		Log("STOP|forgotten before the call")
		Return false
	ElseIf stopOnStart
		; A sex request came during the wait (Grow): no affection scene, the Ask First box comes now.
		bool grow = afterEnd == "grow"
		Log("STOP|sex request before the call")
		Forget()
		Return grow
	ElseIf OActor.IsInOStim(PlayerRef) || OActor.IsInOStim(akNpc)
		; Another scene began during the wait.
		Log("REFUSED|someone is in a scene")
		Forget()
		Return false
	EndIf
	If furnitureType != ""
		; Someone may have sat down during the wait.
		furnitureRef = FreeFurniture(furnitureType)
		If !furnitureRef
			Forget()
			NoFurniture(akNpc, furnitureType)
			Return false
		EndIf
	EndIf
	Log("CALL|" + asKind + "|" + sceneID + "|furniture=" + furnitureType + "|sinceEnd=" + MAE_Text.SecondsSinceSceneEnd() + "|waited=" + (Utility.GetCurrentRealTime() - now))
	If !StartThread(sceneID, furnitureRef)
		If stopOnStart
			; The talk ended or a sex request came while the thread was being set up.
			bool grow = afterEnd == "grow"
			Log("STOP|ended before the call")
			Forget()
			Return grow
		EndIf
		Forget()
		NoScene(akNpc, asKind)
	EndIf
	Return false
EndFunction

bool Function StartThread(string asScene, ObjectReference akFurniture)
	int builder = OThreadBuilder.Create(SortedPair(partner))
	If builder < 0
		Log("FAILED|builder")
		Return false
	EndIf
	OThreadBuilder.SetStartingAnimation(builder, asScene)
	If akFurniture
		OThreadBuilder.SetFurniture(builder, akFurniture)
	Else
		OThreadBuilder.NoFurniture(builder)
	EndIf
	OThreadBuilder.NoPlayerControl(builder)
	OThreadBuilder.NoUndressing(builder)
	OThreadBuilder.NoPostDialogue(builder)
	OThreadBuilder.NoAutoMode(builder)
	OThreadBuilder.SetMetadataCSV(builder, METADATA)
	If stopOnStart
		OThreadBuilder.Cancel(builder)
		Return false
	EndIf
	thread = OThreadBuilder.Start(builder)
	If thread < 0
		Log("FAILED|start")
		Return false
	EndIf
	Return true
EndFunction

; A second call during the scene. Same furniture: warp to a listed scene and start the time over. Other furniture
; (or none where one is needed): end this one and start the new kind after OStim's restart gap.
Function Switch(string asKind, string asWho)
	int id = thread
	string current = OThread.GetScene(id)
	string furnitureType = Furniture(asKind)
	If furnitureType != currentFurniture
		If furnitureType != "" && !FreeFurniture(furnitureType)
			NoFurniture(partner, furnitureType)
			Return
		ElseIf PickScene(asKind, partner, asWho) == ""
			NoSceneFor(partner, asKind, asWho)
			Return
		EndIf
		Log("RESTART|" + currentKind + " to " + asKind)
		afterEnd = "kind"
		nextKind = asKind
		nextWho = asWho
		StopThread(id)
		Return
	EndIf
	string sceneID = PickScene(asKind, partner, asWho, current)
	; Read now: the next call lets other handlers run, and their PickScene sets it too.
	Actor picked = pickedDoer
	If sceneID == ""
		NoSceneFor(partner, asKind, asWho)
		Return
	EndIf
	If sceneID != current
		OThread.WarpTo(id, sceneID, false)
	EndIf
	If !started || thread != id
		; The scene ended meanwhile: nothing to tell.
		Log("SWITCH|ended meanwhile|" + asKind)
		Return
	EndIf
	If asKind != currentKind || picked != doer
		currentKind = asKind
		doer = picked
		Positions.AddMantellaEvent(Line("line_" + asKind))
	EndIf
	Log("SWITCH|" + asKind + "|" + current + " to " + sceneID)
	StartTimer(Seconds(asKind))
EndFunction

; Real time when the timer is due goes with it, so OnUpdate can tell this scene's timer from an older one.
Function StartTimer(float afSeconds)
	timerDue = Utility.GetCurrentRealTime() + afSeconds
	RegisterForSingleUpdate(afSeconds)
EndFunction

; Stamps the end before the stop: anything that starts next waits the restart gap even before the end event comes.
Function StopThread(int aiThread)
	StorageUtil.SetFloatValue(None, MAE_Text.KeySceneEnded(), Utility.GetCurrentRealTime())
	OThread.Stop(aiThread)
EndFunction

; Called by MAE_Ask for a sex request with this scene's partner: the scene ends, she asks for a moment, and the Ask
; First box comes after the end. False when it is not this scene's partner.
bool Function Grow(Actor akNpc)
	If !akNpc || akNpc != partner || !Busy()
		Return false
	EndIf
	afterEnd = "grow"
	silentEnd = true
	If starting
		stopOnStart = true
		Log("GROW|while starting")
		Return true
	EndIf
	string pronoun = "he"
	If akNpc.GetLeveledActorBase().GetSex() == 1
		pronoun = "she"
	EndIf
	Live.SendLine(akNpc.GetDisplayName() + " wants more than this and pulls back for a moment; " + akNpc.GetDisplayName() + " says " + pronoun + " needs a moment first.", 0.0)
	Log("GROW|" + currentKind)
	StopThread(thread)
	Return true
EndFunction

; True from the request until the scene has ended; a start that never arrived stops counting after START_TIMEOUT.
; MAE_Ask holds a sex request back meanwhile: before the thread exists the player is not in OStim yet.
bool Function Busy()
	float now = Utility.GetCurrentRealTime()
	If requesting && now >= requestAt && now - requestAt < START_TIMEOUT
		Return true
	EndIf
	Return started || (starting && now >= actionAt && now - actionAt < START_TIMEOUT)
EndFunction

Function NoScene(Actor akNpc, string asKind)
	Log("NO SCENE|" + asKind + "|" + akNpc.GetDisplayName())
	Positions.AddMantellaEvent("There is no way to do that here right now, so " + akNpc.GetDisplayName() + " and the player carry on as they were.")
EndFunction

; No scene for that kind this way round: when there is one the other way round, Mantella hears so.
Function NoSceneFor(Actor akNpc, string asKind, string asWho)
	string other = "player"
	If asWho == "player"
		other = ""
	EndIf
	If akNpc && JsonUtil.GetStringValue(LIST_FILE, "who_" + asKind, "") != "" && PickScene(asKind, akNpc, other) != ""
		Log("OTHER WAY|" + asKind + "|" + akNpc.GetDisplayName())
		If other == ""
			Positions.AddMantellaEvent("Only " + akNpc.GetDisplayName() + " can do that here, not the player, so they carry on as they were.")
		Else
			Positions.AddMantellaEvent("Only the player can do that here, not " + akNpc.GetDisplayName() + ", so they carry on as they were.")
		EndIf
		Return
	EndIf
	NoScene(akNpc, asKind)
EndFunction

Function NoFurniture(Actor akNpc, string asType)
	Log("NO FURNITURE|" + asType + "|" + akNpc.GetDisplayName())
	Positions.AddMantellaEvent("There is no free " + asType + " close by, so " + akNpc.GetDisplayName() + " and the player carry on as they were.")
EndFunction

; The kind's line with {a} (who does it) and {b} (the other).
string Function Line(string asKey)
	Actor other = partner
	If doer == partner
		other = PlayerRef
	EndIf
	string text = JsonUtil.GetStringValue(LIST_FILE, asKey, "{a} and {b} share a moment.")
	text = Swap(text, "{a}", NameOf(doer))
	text = Swap(text, "{b}", NameOf(other))
	If StringUtil.Find(text, "the player") == 0
		text = "The player" + StringUtil.Substring(text, 10)
	EndIf
	Return text
EndFunction

string Function NameOf(Actor akActor)
	If !akActor || akActor == PlayerRef
		Return "the player"
	EndIf
	Return akActor.GetDisplayName()
EndFunction

string Function Swap(string asText, string asToken, string asValue)
	int i = StringUtil.Find(asText, asToken)
	While i >= 0
		; Substring with a length of 0 returns the rest of the text, not "", so a token at the start or end is cut here
		string head = ""
		If i > 0
			head = StringUtil.Substring(asText, 0, i)
		EndIf
		string tail = ""
		int after = i + StringUtil.GetLength(asToken)
		If after < StringUtil.GetLength(asText)
			tail = StringUtil.Substring(asText, after)
		EndIf
		asText = head + asValue + tail
		i = StringUtil.Find(asText, asToken, i + StringUtil.GetLength(asValue))
	EndWhile
	Return asText
EndFunction

float Function Seconds(string asKind)
	If testSeconds > 0.0
		Return testSeconds
	EndIf
	Return JsonUtil.GetFloatValue(LIST_FILE, asKind, DEFAULT_SECONDS)
EndFunction

; ---------------------------------------------------------------------------
; The thread
; ---------------------------------------------------------------------------

Event OnThreadStart(string asEventName, string asArg, float afThreadID, Form akSender)
	int id = afThreadID as int
	If !OThread.HasMetadata(id, METADATA)
		Return
	EndIf
	thread = id
	starting = false
	started = true
	startAt = Utility.GetCurrentRealTime()
	Log("TIMING|start|" + currentKind + "|" + OThread.GetScene(id) + "|doer=" + NameOf(doer) + "|fromAction=" + (startAt - actionAt))
	If stopOnStart || !partner
		; !partner: forgotten after a load while the actors walked together.
		Log("STOP|ended before the start")
		StopThread(id)
		Return
	EndIf
	Positions.AddMantellaEvent(Line("line_" + currentKind))
	StartTimer(Seconds(currentKind))
EndEvent

; The metadata check keeps an old timer from ending a later scene that got the same thread id; timerDue one that
; fired just before this scene's own timer was set.
Event OnUpdate()
	int id = thread
	If started && Utility.GetCurrentRealTime() >= timerDue - 0.5 && OThread.IsRunning(id) && OThread.HasMetadata(id, METADATA)
		Log("TIMER|" + currentKind)
		StopThread(id)
	EndIf
EndEvent

; Every thread's end counts for the wait before the next start (MAE_Text.WaitAfterScene).
Event OnThreadEnd(string asEventName, string asArg, float afThreadID, Form akSender)
	float now = Utility.GetCurrentRealTime()
	StorageUtil.SetFloatValue(None, MAE_Text.KeySceneEnded(), now)
	If (afThreadID as int) != thread || (!starting && !started)
		Return
	EndIf
	Log("TIMING|end|" + currentKind + "|fromAction=" + (now - actionAt) + "|fromStart=" + (now - startAt))
	Actor npc = partner
	bool played = started && !stopOnStart && npc
	If played && !silentEnd
		Positions.AddMantellaEvent(Line("end_" + currentKind))
	EndIf
	string after = afterEnd
	string kind = nextKind
	string who = nextWho
	Forget()
	If played
		Score(npc)
	EndIf
	If !npc || after == ""
		Return
	EndIf
	int ends = talkEnds
	MAE_Text.WaitAfterScene()
	If talkEnds != ends
		; The talk ended during the wait: like an end before it, it cancels what was to come.
		Log("STOP|talk ended before " + after)
	ElseIf after == "grow"
		Ask.RequestAfterAffection(npc)
	ElseIf after == "kind"
		Request(npc, kind, who)
	EndIf
EndEvent

; For any module that keeps a score (MLWW_Facts.Score in World): a scene with the player counts as physical.
Function Score(Actor akNpc)
	int handle = ModEvent.Create("MLW_ScoreEvent")
	If handle
		ModEvent.PushForm(handle, akNpc)
		ModEvent.PushString(handle, "physical")
		ModEvent.PushFloat(handle, 1.0)
		ModEvent.Send(handle)
	EndIf
	Log("SCORE|" + akNpc.GetDisplayName() + "|physical")
EndFunction

Event OnConversationEnded()
	talkEnds += 1
	afterEnd = ""
	If starting
		stopOnStart = true
	ElseIf started && OThread.IsRunning(thread) && OThread.HasMetadata(thread, METADATA)
		silentEnd = true
		Log("STOP|talk ended")
		StopThread(thread)
	EndIf
EndEvent

; A scene saved mid-way never sends its end event.
Event OnMenuClose(string asMenuName)
	If (starting || started) && !OActor.IsInOStim(PlayerRef)
		Forget()
	EndIf
EndEvent

Function Forget()
	starting = false
	started = false
	stopOnStart = false
	silentEnd = false
	thread = -1
	partner = None
	doer = None
	currentKind = ""
	currentFurniture = ""
	afterEnd = ""
	nextKind = ""
	nextWho = ""
	timerDue = 0.0
	UnregisterForUpdate()
EndFunction

; Timing goes to the test log in test mode and to the Hub's debug log when that is on, so a real talk can be timed too.
Function Log(string asLine)
	If MAE_TestMode.GetValueInt() == 1
		MAE_Text.TestLog("AFFECT|" + asLine)
	EndIf
	MLW_Hub hub = Game.GetFormFromFile(0x000820, HUB_PLUGIN) as MLW_Hub
	If hub
		hub.Log("ostim", "affection " + Utility.GetCurrentRealTime() + " " + asLine)
	EndIf
EndFunction

; ---------------------------------------------------------------------------
; Testing
; ---------------------------------------------------------------------------

Function TestSeconds(float afSeconds)
	testSeconds = afSeconds
EndFunction

string Function TestState()
	string sceneID = ""
	If thread >= 0
		sceneID = OThread.GetScene(thread)
	EndIf
	Return "starting=" + starting + " started=" + started + " stopOnStart=" + stopOnStart + " thread=" + thread + " kind=" + currentKind \
			+ " doer=" + NameOf(doer) + " furniture=" + currentFurniture + " after=" + afterEnd + " scene=" + sceneID
EndFunction

; The gate the NPC's file holds; -1 if none was written.
int Function TestGate(Actor akNpc)
	Return JsonUtil.GetIntValue(GateFile(akNpc), "affection", -1)
EndFunction

; The kinds the gate would list for akNpc now.
string Function TestKinds(Actor akNpc)
	Return AvailableKinds(akNpc)
EndFunction
