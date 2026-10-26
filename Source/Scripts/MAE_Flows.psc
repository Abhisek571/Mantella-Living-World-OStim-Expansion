Scriptname MAE_Flows extends Quest
{Builds the player's two-person OStim scenes live, one animation set at a time (sets come from tools\flowgen.py).
A scene opens soft in one pack; each time a set has played through, the next set of that pack is rolled: the
current position's natural next moves (weighted by how often packs make that move), or the same position again
with a different set, with her favourite positions likelier and the ones from her last scene a bit less likely.
Intensity never drops, furniture and theme never change, any position at most twice per chain, 4 sets per chain.
The pack's finish scene waits for the man's excitement; if she climaxes but is not satisfied, a new chain starts.
Steps back for good once the player navigates by hand. test\simulate.py runs the same rules offline.
On its own quest: SKSE keeps one mod event registration per object.}

Actor Property PlayerRef Auto
GlobalVariable Property MAE_FlowsEnabled Auto
; OStim excitement (0-100) at which the pack's finish scene starts.
GlobalVariable Property MAE_FlowFinishExcitement Auto
MAE_Positions Property Positions Auto
; 1 = corner messages when a set starts or a position is requested.
GlobalVariable Property MAE_NotifyScene Auto
; 1 = log every decision to the test log (MAE_Text.TestLog).
GlobalVariable Property MAE_TestMode Auto

string Property CATALOGUE = "MantellaAdultExpansion/flows.json" AutoReadOnly
float Property POLL = 2.0 AutoReadOnly
int Property CHAIN_SETS = 4 AutoReadOnly
int Property MAX_POSE_PER_CHAIN = 2 AutoReadOnly
float Property W_REPEAT = 3.0 AutoReadOnly
float Property W_REPEAT_FAV = 3.0 AutoReadOnly
float Property W_UNNATURAL = 0.5 AutoReadOnly
float Property FAV_MULT = 3.0 AutoReadOnly
float Property RECENT_MULT = 0.5 AutoReadOnly
float Property RANK_JUMP_MULT = 0.5 AutoReadOnly
; OSL arousal still at or above this after her climax = not satisfied (when the Arousal module is missing).
float Property SATISFIED_AROUSAL = 30.0 AutoReadOnly
float Property SATISFIED_CHECK_DELAY = 4.0 AutoReadOnly
string Property KEY_LAST_POSES = "MAE_LastScenePoses" AutoReadOnly

int sceneThread = -1
Actor partner
int curSet = -1
; The last set of the current chain (not a finish): what the next set and the finish are rolled from.
int chainSet = -1
float setStart
float setLength
int chainSets
int[] poseCount
string usedSets = ","
string scenePoses = ","
string[] setScenes
; The set before: OStim can still report one of its scenes just after the next set starts.
string[] prevScenes
bool finishPlayed
; No finish fit the current set: don't search again until the next set.
bool finishSearched
bool climaxPending
float climaxAt
; The player navigated by hand: nothing automatic touches this scene any more.
bool playerControl = false
string[] favourites
string recentPoses

Event OnInit()
	Register()
EndEvent

Function Register()
	RegisterForModEvent("ostim_thread_start", "OnThreadStart")
	RegisterForModEvent("ostim_thread_scenechanged", "OnSceneChanged")
	RegisterForModEvent("ostim_actor_orgasm", "OnOrgasm")
	RegisterForModEvent("ostim_thread_end", "OnThreadEnd")
EndFunction

bool Function Built()
	Return JsonUtil.JsonExists(CATALOGUE) && JsonUtil.GetIntValue(CATALOGUE, "setCount") > 0
EndFunction

; ---------------------------------------------------------------------------
; OStim events
; ---------------------------------------------------------------------------

Event OnThreadStart(string asEventName, string asArg, float afThreadID, Form akSender)
	int threadID = afThreadID as int
	If MAE_FlowsEnabled.GetValueInt() != 1
		Return
	EndIf
	Actor other = PartnerOf(threadID)
	If !other
		Return
	EndIf
	If !Built()
		Debug.Notification("Scene flows aren't built yet: run the flow generator first.")
		Return
	EndIf
	BeginScene(threadID, other)
	; Let OStim settle into its own start scene first.
	Utility.Wait(2.0)
	If OThread.IsRunning(threadID) && sceneThread == threadID && curSet < 0
		PlaySet(PickOpener(), "opener")
	EndIf
EndEvent

Function BeginScene(int aiThreadID, Actor akPartner)
	sceneThread = aiThreadID
	partner = akPartner
	curSet = -1
	chainSet = -1
	setScenes = new string[1]
	prevScenes = new string[1]
	chainSets = 0
	poseCount = Utility.CreateIntArray(JsonUtil.GetIntValue(CATALOGUE, "poseCount"))
	usedSets = ","
	scenePoses = ","
	playerControl = false
	finishPlayed = false
	climaxPending = false
	favourites = new string[3]
	If Positions
		favourites = Positions.Favourites(akPartner)
	EndIf
	recentPoses = StorageUtil.GetStringValue(akPartner, KEY_LAST_POSES, ",")
EndFunction

Event OnSceneChanged(string asEventName, string asArg, float afThreadID, Form akSender)
	If (afThreadID as int) != sceneThread || curSet < 0 || playerControl
		Return
	EndIf
	string sceneID = OThread.GetScene(sceneThread)
	If sceneID == "" || OMetadata.IsTransition(sceneID)
		Return
	EndIf
	If setScenes.Find(sceneID) < 0 && (!prevScenes || prevScenes.Find(sceneID) < 0)
		; The player navigated somewhere else: hand the scene back to them.
		playerControl = true
		Log("TAKEOVER|" + sceneID)
	EndIf
EndEvent

Event OnOrgasm(string asEventName, string asSceneID, float afThreadID, Form akSender)
	If (afThreadID as int) == sceneThread && (akSender as Actor) == partner && !playerControl && curSet >= 0
		climaxPending = true
		climaxAt = Utility.GetCurrentRealTime()
		Log("CLIMAX|" + partner.GetDisplayName() + "|pose=" + JsonUtil.IntListGet(CATALOGUE, "setPose", curSet))
	EndIf
EndEvent

Event OnThreadEnd(string asEventName, string asArg, float afThreadID, Form akSender)
	If (afThreadID as int) == sceneThread
		If partner && scenePoses != ","
			StorageUtil.SetStringValue(partner, KEY_LAST_POSES, scenePoses)
		EndIf
		Log("END|" + scenePoses)
		sceneThread = -1
		curSet = -1
		partner = None
	EndIf
EndEvent

Event OnUpdate()
	If sceneThread < 0 || !OThread.IsRunning(sceneThread) || playerControl || curSet < 0
		Return
	EndIf
	float now = Utility.GetCurrentRealTime()
	; Finish scenes are the man's climax (cumshot, facial, ...), so they wait for his excitement.
	If !finishPlayed && !finishSearched && OActor.GetExcitement(FinishActor()) >= MAE_FlowFinishExcitement.GetValue()
		int fin = PickFinish()
		If fin >= 0
			finishPlayed = true
			PlaySet(fin, "finish")
		Else
			; OStim's own climax still comes; the set just carries on.
			finishSearched = true
			Log("HOLD|no finish set fits")
		EndIf
	EndIf
	If climaxPending && now - climaxAt >= SATISFIED_CHECK_DELAY
		climaxPending = false
		If NotSatisfied(partner)
			; A new chain from the same pack, free to restart at oral/manual intensity.
			chainSets = 0
			poseCount = Utility.CreateIntArray(poseCount.Length)
			finishPlayed = false
			PlaySet(PickNext(1), "new chain")
		EndIf
	ElseIf !finishPlayed && now - setStart >= setLength && chainSets < CHAIN_SETS
		int nextSet = PickNext(-1)
		If nextSet >= 0
			PlaySet(nextSet, "next")
		Else
			chainSets = CHAIN_SETS ; nothing fits: hold here until the finish or a climax
			Log("HOLD|no fitting set")
		EndIf
	EndIf
	RegisterForSingleUpdate(POLL)
EndEvent

; ---------------------------------------------------------------------------
; Rolling
; ---------------------------------------------------------------------------

; A pack first (every pack with a fitting opener equally likely), then a soft opener in it; sex openers only
; when no pack has a soft one. Openers the pack can move on from come first; dead ends only when nothing else
; fits. -1 if nothing fits.
int Function PickOpener()
	int pick = PickOpenerFrom(true)
	If pick < 0
		pick = PickOpenerFrom(false)
	EndIf
	Return pick
EndFunction

int Function PickOpenerFrom(bool abCanGo)
	string furn = FurnitureFamily(OThread.GetFurnitureType(sceneThread))
	int packCount = JsonUtil.GetIntValue(CATALOGUE, "packCount")
	int maxRank = 1
	While maxRank <= 2
		int[] packs = Utility.CreateIntArray(packCount)
		int found = 0
		int p = 0
		While p < packCount
			If HasOpener(p, maxRank, furn, abCanGo)
				packs[found] = p
				found += 1
			EndIf
			p += 1
		EndWhile
		If found > 0
			int pack = packs[Utility.RandomInt(0, found - 1)]
			int start = JsonUtil.IntListGet(CATALOGUE, "packStart", pack)
			int count = JsonUtil.IntListGet(CATALOGUE, "packSetCount", pack)
			float[] weights = Utility.CreateFloatArray(count)
			int i = 0
			While i < count
				If OpenerFits(start + i, maxRank, furn, abCanGo)
					weights[i] = PoseBias(JsonUtil.IntListGet(CATALOGUE, "setPose", start + i), 1.0)
				EndIf
				i += 1
			EndWhile
			int pick = Roll(weights)
			If pick >= 0
				Return start + pick
			EndIf
		EndIf
		maxRank += 1
	EndWhile
	Return -1
EndFunction

bool Function HasOpener(int aiPack, int aiMaxRank, string asFurniture, bool abCanGo)
	int start = JsonUtil.IntListGet(CATALOGUE, "packStart", aiPack)
	int count = JsonUtil.IntListGet(CATALOGUE, "packSetCount", aiPack)
	int i = 0
	While i < count
		If OpenerFits(start + i, aiMaxRank, asFurniture, abCanGo)
			Return true
		EndIf
		i += 1
	EndWhile
	Return false
EndFunction

bool Function OpenerFits(int aiSet, int aiMaxRank, string asFurniture, bool abCanGo)
	If abCanGo && JsonUtil.IntListGet(CATALOGUE, "setCanGo", aiSet) != 1
		Return false
	EndIf
	Return JsonUtil.IntListGet(CATALOGUE, "setRank", aiSet) <= aiMaxRank && JsonUtil.IntListGet(CATALOGUE, "setStageCount", aiSet) >= 2 \
			&& JsonUtil.StringListGet(CATALOGUE, "setFurniture", aiSet) == asFurniture && ThemeAllowed(JsonUtil.StringListGet(CATALOGUE, "setTheme", aiSet))
EndFunction

; The next set of the current pack. aiMinRank >= 0 replaces "never below the current intensity" (new chain).
int Function PickNext(int aiMinRank)
	int pack = JsonUtil.IntListGet(CATALOGUE, "setPack", chainSet)
	int start = JsonUtil.IntListGet(CATALOGUE, "packStart", pack)
	int count = JsonUtil.IntListGet(CATALOGUE, "packSetCount", pack)
	int curPose = JsonUtil.IntListGet(CATALOGUE, "setPose", chainSet)
	int curRank = JsonUtil.IntListGet(CATALOGUE, "setRank", chainSet)
	int minRank = curRank
	If aiMinRank >= 0
		minRank = aiMinRank
	EndIf
	string furn = JsonUtil.StringListGet(CATALOGUE, "setFurniture", chainSet)
	string theme = JsonUtil.StringListGet(CATALOGUE, "setTheme", chainSet)
	int poses = poseCount.Length
	float wmax = 1.0
	int b = 0
	While b < poses
		float wb = JsonUtil.IntListGet(CATALOGUE, "moveWeight", curPose * poses + b) as float
		If wb > wmax
			wmax = wb
		EndIf
		b += 1
	EndWhile
	float[] weights = Utility.CreateFloatArray(count)
	int i = 0
	While i < count
		int s = start + i
		int rank = JsonUtil.IntListGet(CATALOGUE, "setRank", s)
		int pose = JsonUtil.IntListGet(CATALOGUE, "setPose", s)
		If rank < 3 && rank >= minRank && !Used(s) && poseCount[pose] < MAX_POSE_PER_CHAIN \
				&& JsonUtil.StringListGet(CATALOGUE, "setFurniture", s) == furn && JsonUtil.StringListGet(CATALOGUE, "setTheme", s) == theme
			float w
			If pose == curPose
				; same position, different set; a favourite gets a flat bonus instead of the multiplier
				w = W_REPEAT
				If IsFavourite(pose)
					w += W_REPEAT_FAV
				EndIf
				w = RecentBias(pose, w)
			Else
				float move = JsonUtil.IntListGet(CATALOGUE, "moveWeight", curPose * poses + pose) as float
				If move > 0.0
					w = 1.0 + 9.0 * move / wmax
				Else
					w = W_UNNATURAL
				EndIf
				w = PoseBias(pose, w)
			EndIf
			If rank - curRank > 1
				w *= RANK_JUMP_MULT
			EndIf
			weights[i] = w
		EndIf
		i += 1
	EndWhile
	int pick = Roll(weights)
	If pick < 0
		Return -1
	EndIf
	Return start + pick
EndFunction

; The pack's finish set: same furniture and theme, the current position or one of its natural next moves;
; from another pack when this one has none that fits.
int Function PickFinish()
	int pack = JsonUtil.IntListGet(CATALOGUE, "setPack", chainSet)
	int start = JsonUtil.IntListGet(CATALOGUE, "packStart", pack)
	int count = JsonUtil.IntListGet(CATALOGUE, "packSetCount", pack)
	int curPose = JsonUtil.IntListGet(CATALOGUE, "setPose", chainSet)
	int poses = poseCount.Length
	string furn = JsonUtil.StringListGet(CATALOGUE, "setFurniture", chainSet)
	string theme = JsonUtil.StringListGet(CATALOGUE, "setTheme", chainSet)
	float[] weights = Utility.CreateFloatArray(count)
	int i = 0
	While i < count
		int s = start + i
		int pose = JsonUtil.IntListGet(CATALOGUE, "setPose", s)
		If JsonUtil.IntListGet(CATALOGUE, "setRank", s) == 3 && JsonUtil.StringListGet(CATALOGUE, "setFurniture", s) == furn \
				&& JsonUtil.StringListGet(CATALOGUE, "setTheme", s) == theme
			If pose == curPose
				weights[i] = 3.0
			ElseIf JsonUtil.IntListGet(CATALOGUE, "moveWeight", curPose * poses + pose) > 0
				weights[i] = 1.0
			EndIf
		EndIf
		i += 1
	EndWhile
	int pick = Roll(weights)
	If pick >= 0
		Return start + pick
	EndIf
	; Most packs have no finish set: borrow one from another pack, same furniture, an allowed theme.
	int total = JsonUtil.IntListCount(CATALOGUE, "finishSets")
	If total <= 0
		Return -1
	EndIf
	weights = Utility.CreateFloatArray(total)
	i = 0
	While i < total
		int s = JsonUtil.IntListGet(CATALOGUE, "finishSets", i)
		int pose = JsonUtil.IntListGet(CATALOGUE, "setPose", s)
		If JsonUtil.StringListGet(CATALOGUE, "setFurniture", s) == furn && ThemeAllowed(JsonUtil.StringListGet(CATALOGUE, "setTheme", s))
			If pose == curPose
				weights[i] = 3.0
			ElseIf JsonUtil.IntListGet(CATALOGUE, "moveWeight", curPose * poses + pose) > 0
				weights[i] = 1.0
			EndIf
		EndIf
		i += 1
	EndWhile
	pick = Roll(weights)
	If pick < 0
		Return -1
	EndIf
	Return JsonUtil.IntListGet(CATALOGUE, "finishSets", pick)
EndFunction

; Index of a weighted random pick (weights <= 0 never picked); -1 if all are zero.
int Function Roll(float[] afWeights)
	float total = 0.0
	int i = 0
	While i < afWeights.Length
		If afWeights[i] > 0.0
			total += afWeights[i]
		EndIf
		i += 1
	EndWhile
	If total <= 0.0
		Return -1
	EndIf
	float r = Utility.RandomFloat(0.0, total)
	i = 0
	While i < afWeights.Length
		If afWeights[i] > 0.0
			r -= afWeights[i]
			If r <= 0.0
				Return i
			EndIf
		EndIf
		i += 1
	EndWhile
	Return afWeights.Length - 1
EndFunction

; Her favourites raise a position's weight, positions from her last scene with the player lower it a little.
float Function PoseBias(int aiPose, float afWeight)
	If IsFavourite(aiPose)
		afWeight *= FAV_MULT
	EndIf
	Return RecentBias(aiPose, afWeight)
EndFunction

float Function RecentBias(int aiPose, float afWeight)
	If StringUtil.Find(recentPoses, "," + aiPose + ",") >= 0
		Return afWeight * RECENT_MULT
	EndIf
	Return afWeight
EndFunction

bool Function IsFavourite(int aiPose)
	If !favourites
		Return false
	EndIf
	Return favourites.Find(JsonUtil.StringListGet(CATALOGUE, "poses", aiPose)) >= 0
EndFunction

Function PlaySet(int aiSet, string asWhy)
	If aiSet < 0 || sceneThread < 0
		Log("HOLD|" + asWhy + " found nothing")
		Return
	EndIf
	curSet = aiSet
	finishSearched = false
	int pose = JsonUtil.IntListGet(CATALOGUE, "setPose", aiSet)
	If asWhy != "finish"
		chainSet = aiSet
		chainSets += 1
		poseCount[pose] = poseCount[pose] + 1
		usedSets += aiSet + ","
	EndIf
	If StringUtil.Find(scenePoses, "," + pose + ",") < 0
		scenePoses += pose + ","
	EndIf
	prevScenes = setScenes
	setScenes = PapyrusUtil.StringSplit(JsonUtil.StringListGet(CATALOGUE, "setStages", aiSet), ",")
	setStart = Utility.GetCurrentRealTime()
	setLength = JsonUtil.IntListGet(CATALOGUE, "setStageCount", aiSet) * JsonUtil.GetIntValue(CATALOGUE, "stageSeconds")
	If OThread.IsInAutoMode(sceneThread)
		OThread.StopAutoMode(sceneThread)
	EndIf
	OThread.PlaySequence(sceneThread, JsonUtil.StringListGet(CATALOGUE, "setSeq", aiSet), false, true)
	string label = JsonUtil.StringListGet(CATALOGUE, "setLabel", aiSet)
	Log("SET|" + asWhy + "|" + aiSet + "|pack=" + JsonUtil.IntListGet(CATALOGUE, "setPack", aiSet) + "|pose=" + pose + "|rank=" + JsonUtil.IntListGet(CATALOGUE, "setRank", aiSet) \
			+ "|furn=" + JsonUtil.StringListGet(CATALOGUE, "setFurniture", aiSet) + "|theme=" + JsonUtil.StringListGet(CATALOGUE, "setTheme", aiSet) + "|chain=" + chainSets + "|" + label)
	If MAE_NotifyScene.GetValueInt() == 1
		Debug.Notification(label + " (" + JsonUtil.StringListGet(CATALOGUE, "poses", pose) + ")")
	EndIf
	RegisterForSingleUpdate(POLL)
EndFunction

bool Function Used(int aiSet)
	Return StringUtil.Find(usedSets, "," + aiSet + ",") >= 0
EndFunction

; ---------------------------------------------------------------------------
; Position requests (Mantella "ChangePosition")
; ---------------------------------------------------------------------------

; Plays a set in asPose with the scene's furniture and an allowed theme, from the current pack when it has one,
; otherwise from any pack. Counts as the next set of the chain. False if nothing fits.
bool Function PlayPose(string asPose)
	int threadID = OActor.GetThreadID(PlayerRef)
	If threadID < 0 || !OThread.IsRunning(threadID) || !Built()
		Return false
	EndIf
	int pose = JsonUtil.StringListFind(CATALOGUE, "poses", asPose)
	If pose < 0
		Return false
	EndIf
	If threadID != sceneThread
		Actor other = PartnerOf(threadID)
		If !other
			Return false
		EndIf
		BeginScene(threadID, other)
	EndIf
	string furn = FurnitureFamily(OThread.GetFurnitureType(threadID))
	int pack = -1
	If chainSet >= 0
		pack = JsonUtil.IntListGet(CATALOGUE, "setPack", chainSet)
	EndIf
	int s = FindSet(pose, pack, furn)
	If s < 0
		s = FindSet(pose, -1, furn)
	EndIf
	If s < 0
		Log("REQUEST|" + asPose + "|none fits")
		Return false
	EndIf
	playerControl = false
	finishPlayed = false
	Log("REQUEST|" + asPose)
	PlaySet(s, "request")
	Return true
EndFunction

; A random unused, non-finish set in aiPose with that furniture and an allowed theme, from aiPack when >= 0.
int Function FindSet(int aiPose, int aiPack, string asFurniture)
	int start = 0
	int count = JsonUtil.GetIntValue(CATALOGUE, "setCount")
	If aiPack >= 0
		start = JsonUtil.IntListGet(CATALOGUE, "packStart", aiPack)
		count = JsonUtil.IntListGet(CATALOGUE, "packSetCount", aiPack)
	EndIf
	float[] weights = Utility.CreateFloatArray(count)
	int i = 0
	While i < count
		int s = start + i
		If JsonUtil.IntListGet(CATALOGUE, "setPose", s) == aiPose && JsonUtil.IntListGet(CATALOGUE, "setRank", s) < 3 && !Used(s) \
				&& JsonUtil.StringListGet(CATALOGUE, "setFurniture", s) == asFurniture && ThemeAllowed(JsonUtil.StringListGet(CATALOGUE, "setTheme", s))
			weights[i] = 1.0
		EndIf
		i += 1
	EndWhile
	int pick = Roll(weights)
	If pick < 0
		Return -1
	EndIf
	Return start + pick
EndFunction

; ---------------------------------------------------------------------------
; Helpers
; ---------------------------------------------------------------------------

; The non-player actor of a two-person thread with the player, opposite sex; None otherwise.
Actor Function PartnerOf(int aiThreadID)
	Actor[] actors = OThread.GetActors(aiThreadID)
	If !actors || actors.Length != 2 || actors.Find(PlayerRef) < 0
		Return None
	EndIf
	Actor other = actors[0]
	If other == PlayerRef
		other = actors[1]
	EndIf
	If !other || other.GetActorBase().GetSex() == PlayerRef.GetActorBase().GetSex()
		Return None
	EndIf
	Return other
EndFunction

; The man of the pair: whoever a finish scene is for.
Actor Function FinishActor()
	If PlayerRef.GetActorBase().GetSex() == 0
		Return PlayerRef
	EndIf
	Return partner
EndFunction

; The Arousal module's own satisfied / overwhelmed flags when it is installed; otherwise her arousal.
bool Function NotSatisfied(Actor akPartner)
	If Game.GetModByName("Mantella Living World - Arousal.esp") != 255
		Return StorageUtil.GetIntValue(akPartner, "MantellaOSLA_Satisfied", 0) != 1 && StorageUtil.GetIntValue(akPartner, "MantellaOSLA_Overwhelmed", 0) != 1
	EndIf
	Return OSLArousedNative.GetArousalNoSideEffects(akPartner) >= SATISFIED_AROUSAL
EndFunction

; Default themes: normal-size actors, no femdom or futa, neutral or romantic mood.
bool Function ThemeAllowed(string asTheme)
	Return asTheme == "normal|-|-|neutral" || asTheme == "normal|-|-|romantic"
EndFunction

; Same mapping as furniture_family() in tools\flowgen.py.
string Function FurnitureFamily(string asType)
	If asType == ""
		Return "none"
	ElseIf StringUtil.Find(asType, "bed") >= 0
		Return "bed"
	ElseIf StringUtil.Find(asType, "alchemy") >= 0
		Return "alchemytable"
	ElseIf StringUtil.Find(asType, "enchant") >= 0
		Return "enchantingtable"
	ElseIf StringUtil.Find(asType, "table") >= 0 || StringUtil.Find(asType, "counter") >= 0
		Return "table"
	ElseIf StringUtil.Find(asType, "wardrobe") >= 0
		Return "wardrobe"
	EndIf
	Return asType
EndFunction

Function Log(string asLine)
	If MAE_TestMode.GetValueInt() == 1
		MAE_Text.TestLog("FLOW|" + asLine)
	EndIf
EndFunction

; ---------------------------------------------------------------------------
; Testing
; ---------------------------------------------------------------------------

string Function TestState()
	string label = ""
	If curSet >= 0
		label = JsonUtil.StringListGet(CATALOGUE, "setLabel", curSet)
	EndIf
	Return "thread=" + sceneThread + " set=" + curSet + " (" + label + ") chain=" + chainSets + " scene=" + OThread.GetScene(sceneThread) \
			+ " finishPlayed=" + finishPlayed + " playerControl=" + playerControl + " poses=" + scenePoses
EndFunction

; Rolls the next set now instead of waiting for the current one to play through (fast tests).
Function TestAdvance()
	setStart = 0.0
	RegisterForSingleUpdate(0.1)
EndFunction
