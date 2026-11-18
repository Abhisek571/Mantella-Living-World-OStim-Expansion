Scriptname MAE_Text Hidden
{Shared wording helpers for the OStim Expansion scripts, and the test log.}

; Appends a timestamped line to Data/SKSE/Plugins/MantellaAdultExpansion/test.log (lands in MO2's overwrite).
; Callers only log when MAE_TestMode is 1.
Function TestLog(string asLine) Global
	MiscUtil.WriteToFile("Data/SKSE/Plugins/MantellaAdultExpansion/test.log", Utility.GetCurrentRealTime() + "|" + asLine + "\n", true, false)
EndFunction

; Children never take part in anything this mod does. Some mods clear the child flag, so the race is checked too.
bool Function IsChildActor(Actor akActor) Global
	If !akActor
		Return false
	ElseIf akActor.IsChild()
		Return true
	EndIf
	Race actorRace = akActor.GetRace()
	Return actorRace && StringUtil.Find(MiscUtil.GetRaceEditorID(actorRace), "Child") >= 0
EndFunction

; A child is among the OStim thread's actors.
bool Function ChildInThread(int aiThreadID) Global
	Actor[] actors = OThread.GetActors(aiThreadID)
	int i = 0
	While i < actors.Length
		If IsChildActor(actors[i])
			Return true
		EndIf
		i += 1
	EndWhile
	Return false
EndFunction

; In no state to agree to anything now: dead, gone, asleep, unconscious, bleeding out, paralysed, knocked down,
; fighting, riding or already in a scene.
bool Function CannotConsent(Actor akActor) Global
	If !akActor || akActor.IsDead() || akActor.IsDisabled()
		Return true
	EndIf
	Return akActor.GetSleepState() >= 3 || akActor.IsUnconscious() || akActor.IsBleedingOut() || akActor.GetActorValue("Paralysis") > 0 \
			|| PO3_SKSEFunctions.GetActorKnockState(akActor) != 0 || akActor.IsInCombat() || akActor.IsOnMount() || OActor.IsInOStim(akActor)
EndFunction

; The player can agree: not fighting, not riding, and not a werewolf or a vampire lord.
bool Function PlayerCanConsent() Global
	Actor player = Game.GetPlayer()
	If player.IsInCombat() || player.IsOnMount()
		Return false
	EndIf
	Race playerRace = player.GetRace()
	Race werewolf = Game.GetFormFromFile(0x0CDD84, "Skyrim.esm") as Race
	Race vampireLord = Game.GetFormFromFile(0x00283A, "Dawnguard.esm") as Race
	Return !playerRace || (playerRace != werewolf && (!vampireLord || playerRace != vampireLord))
EndFunction

; The player is in Mantella's running conversation (radiant talks between NPCs get no scene lines).
bool Function PlayerInTalk() Global
	MantellaConversation talk = Game.GetFormFromFile(0x03D41A, "Mantella.esp") as MantellaConversation
	Return talk && talk.IsRunning() && talk.IsPlayerInConversation()
EndFunction

; This actor is in Mantella's running conversation now (a missed Ended event leaves stale state otherwise).
bool Function InTalk(Actor akActor) Global
	MantellaConversation talk = Game.GetFormFromFile(0x03D41A, "Mantella.esp") as MantellaConversation
	If !akActor || !talk || !talk.IsRunning()
		Return false
	EndIf
	int i = talk.CountActorsInConversation()
	While i > 0
		i -= 1
		If talk.GetActorInConversationByIndex(i) == akActor
			Return true
		EndIf
	EndWhile
	Return false
EndFunction

; A child is somewhere in the running Mantella conversation.
bool Function MinorInTalk() Global
	MantellaConversation conversation = Game.GetFormFromFile(0x03D41A, "Mantella.esp") as MantellaConversation
	If !conversation
		Return false
	EndIf
	int count = conversation.CountActorsInConversation()
	int i = 0
	While i < count
		If IsChildActor(conversation.GetActorInConversationByIndex(i))
			Return true
		EndIf
		i += 1
	EndWhile
	Return false
EndFunction

; Child safety settings (SKSE\Plugins\StorageUtilData\MantellaAdultExpansion\child_settings.json, edited by hand):
; child_far_distance  game units beyond which a child in the talk counts as far away (default 1024, about 15 m)
; child_hidden_distance  beyond this, a child neither seeing nor seen by the player counts as far too (behind a wall
;                     or a door; default 384, 0 = never by sight alone)
; child_near_distance  children not in the talk within this of the player are named to the model (default 2048)
string Function ChildSettings() Global
	Return "MantellaAdultExpansion/child_settings.json"
EndFunction

float Function ChildSetting(string asKey, float afDefault, float afMin) Global
	float value = JsonUtil.GetFloatValue(ChildSettings(), asKey, afDefault)
	If value < afMin
		Return afMin
	EndIf
	Return value
EndFunction

; A child in the talk who is not physically with the player: not loaded, in another interior cell (another room or
; building), farther than child_far_distance, or past child_hidden_distance with neither of them in sight of the other.
bool Function ChildFar(Actor akChild) Global
	Actor player = Game.GetPlayer()
	If !akChild || !akChild.Is3DLoaded()
		Return true
	EndIf
	Cell here = player.GetParentCell()
	Cell there = akChild.GetParentCell()
	If here != there && ((here && here.IsInterior()) || (there && there.IsInterior()))
		Return true
	EndIf
	float distance = akChild.GetDistance(player)
	If distance > ChildSetting("child_far_distance", 1024.0, 128.0)
		Return true
	EndIf
	float hidden = ChildSetting("child_hidden_distance", 384.0, 0.0)
	Return hidden > 0.0 && distance > hidden && !akChild.HasLOS(player) && !player.HasLOS(akChild)
EndFunction

; Every child in the running talk who is far away (ChildFar) is taken out of it, so the next request to Mantella no
; longer has them: a child who is not there neither blocks nor hears anything. Only in a talk with the player and at
; least one adult NPC besides (a talk with only a child in it is left to Mantella). Returns how many were taken out.
int Function RemoveFarChildren() Global
	MantellaConversation talk = Game.GetFormFromFile(0x03D41A, "Mantella.esp") as MantellaConversation
	If !talk || !talk.IsRunning() || !talk.IsPlayerInConversation()
		Return 0
	EndIf
	Actor player = Game.GetPlayer()
	int count = talk.CountActorsInConversation()
	Actor[] far = PapyrusUtil.ActorArray(count)
	int found = 0
	bool adult = false
	int i = 0
	While i < count
		Actor member = talk.GetActorInConversationByIndex(i)
		If member && member != player
			If !IsChildActor(member)
				adult = true
			ElseIf ChildFar(member)
				far[found] = member
				found += 1
			EndIf
		EndIf
		i += 1
	EndWhile
	If found == 0 || !adult
		Return 0
	EndIf
	far = PapyrusUtil.ResizeActorArray(far, found)
	talk.RemoveActorsFromConversation(far)
	Return found
EndFunction

; A name from a Mantella action as a member of the running conversation, never someone merely nearby; the player
; also by "player". None when nobody in the talk has that name.
Actor Function TalkActor(MantellaConversation akConversation, string asName) Global
	If !akConversation || asName == ""
		Return None
	EndIf
	Actor found = akConversation.GetActorInConversation(asName)
	If !found && (asName == "player" || asName == "the player")
		Return Game.GetPlayer()
	EndIf
	Return found
EndFunction

; A short affection scene (MAE_Affection), not sex: flows, live lines and favourites skip it.
bool Function IsAffectionThread(int aiThreadID) Global
	Return OThread.HasMetadata(aiThreadID, "mlw_affection")
EndFunction

string Function KeySceneEnded() Global
	Return "MAE_SceneEndedAt"
EndFunction

; Real seconds since an OStim thread last ended. Real time restarts at 0 on every launch, so a stamp from an earlier
; launch counts as long ago.
float Function SecondsSinceSceneEnd() Global
	float now = Utility.GetCurrentRealTime()
	float ended = StorageUtil.GetFloatValue(None, KeySceneEnded(), -1000.0)
	If ended > now
		Return 100000.0
	EndIf
	Return now - ended
EndFunction

; OStim 7.5.1 can crash in its undress callback when a scene starts seconds after the last one ended with the same actor.
Function WaitAfterScene() Global
	float left = 5.0 - SecondsSinceSceneEnd()
	If left > 0.0
		Utility.Wait(left)
	EndIf
EndFunction

; "a", "a, b", then " and c" for the last of several.
string Function ListAdd(string asList, string asItem, bool abLast) Global
	If asList == ""
		Return asItem
	ElseIf abLast
		Return asList + " and " + asItem
	EndIf
	Return asList + ", " + asItem
EndFunction

; OStim action types as habits ("what she does most"); unknown ones pass through.
string Function ActName(string asAction) Global
	If asAction == "vaginalsex"
		Return "vaginal sex"
	ElseIf asAction == "analsex"
		Return "anal sex"
	ElseIf asAction == "blowjob"
		Return "giving blowjobs"
	ElseIf asAction == "deepthroating"
		Return "deepthroating"
	ElseIf asAction == "cunnilingus" || asAction == "vulvaleating" || asAction == "vulvallicking"
		Return "oral on a woman"
	ElseIf asAction == "handjob"
		Return "handjobs"
	ElseIf asAction == "boobjob"
		Return "titjobs"
	ElseIf asAction == "footjob"
		Return "footjobs"
	ElseIf asAction == "thighjob"
		Return "thighjobs"
	ElseIf asAction == "rimjob" || asAction == "anallicking"
		Return "rimming"
	ElseIf asAction == "kissing" || asAction == "frenchkissing"
		Return "kissing"
	ElseIf asAction == "kissingneck"
		Return "kissing necks"
	ElseIf asAction == "cuddling" || asAction == "hugging" || asAction == "spooning"
		Return "cuddling"
	ElseIf asAction == "vaginalfingering"
		Return "fingering"
	ElseIf asAction == "analfingering"
		Return "anal fingering"
	ElseIf asAction == "tribbing"
		Return "tribbing"
	ElseIf asAction == "spanking"
		Return "spanking"
	ElseIf asAction == "choking"
		Return "choking"
	ElseIf asAction == "pullinghair"
		Return "hair pulling"
	ElseIf asAction == "suckingnipple" || asAction == "lickingnipple"
		Return "nipple play"
	ElseIf asAction == "gropingbreast" || asAction == "gropingbutt"
		Return "groping"
	ElseIf asAction == "femalemasturbation" || asAction == "malemasturbation" || asAction == "masturbation" || asAction == "fingerinmouthmasturbation"
		Return "masturbating"
	ElseIf asAction == "penilelicking" || asAction == "lickingpenis"
		Return "licking cock"
	ElseIf asAction == "testicularlicking" || asAction == "lickingtesticles"
		Return "licking balls"
	ElseIf asAction == "vulvalrubbing" || asAction == "rubbingclitoris"
		Return "rubbing pussy"
	ElseIf asAction == "anilingus"
		Return "rimming"
	ElseIf asAction == "buttjob"
		Return "buttjobs"
	ElseIf asAction == "vampirebite" || asAction == "vampirebiting"
		Return "biting"
	EndIf
	Return asAction
EndFunction

; OStim action types as what is happening right now; unknown ones pass through.
string Function SceneActName(string asAction) Global
	If asAction == "vaginalsex"
		Return "vaginal sex"
	ElseIf asAction == "analsex"
		Return "anal sex"
	ElseIf asAction == "blowjob"
		Return "a blowjob"
	ElseIf asAction == "deepthroating"
		Return "deepthroating"
	ElseIf asAction == "cunnilingus" || asAction == "vulvaleating" || asAction == "vulvallicking"
		Return "cunnilingus"
	ElseIf asAction == "handjob"
		Return "a handjob"
	ElseIf asAction == "boobjob"
		Return "a titjob"
	ElseIf asAction == "footjob"
		Return "a footjob"
	ElseIf asAction == "thighjob"
		Return "a thighjob"
	ElseIf asAction == "rimjob" || asAction == "anallicking"
		Return "rimming"
	ElseIf asAction == "vaginalfingering"
		Return "fingering"
	ElseIf asAction == "analfingering"
		Return "anal fingering"
	ElseIf asAction == "tribbing"
		Return "tribbing"
	ElseIf asAction == "femalemasturbation" || asAction == "malemasturbation" || asAction == "masturbation" || asAction == "fingerinmouthmasturbation"
		Return "masturbation"
	ElseIf asAction == "penilelicking" || asAction == "lickingpenis"
		Return "cock licking"
	ElseIf asAction == "testicularlicking" || asAction == "lickingtesticles"
		Return "ball licking"
	ElseIf asAction == "vulvalrubbing" || asAction == "rubbingclitoris"
		Return "pussy rubbing"
	ElseIf asAction == "anilingus"
		Return "rimming"
	ElseIf asAction == "deepthroat"
		Return "deepthroating"
	ElseIf asAction == "buttjob"
		Return "a buttjob"
	ElseIf asAction == "tailjob"
		Return "a tailjob"
	ElseIf asAction == "analfisting"
		Return "anal fisting"
	ElseIf asAction == "vaginalfisting"
		Return "fisting"
	ElseIf asAction == "analtoying"
		Return "anal toy play"
	ElseIf asAction == "vaginaltoying"
		Return "toy play"
	ElseIf asAction == "oraltoying"
		Return "sucking a toy"
	ElseIf asAction == "oralfingering"
		Return "sucking fingers"
	ElseIf asAction == "analtailsex"
		Return "anal tail play"
	ElseIf asAction == "vaginaltailsex"
		Return "tail sex"
	ElseIf asAction == "breastsmothering"
		Return "smothering with breasts"
	ElseIf asAction == "buttsmothering"
		Return "facesitting"
	ElseIf asAction == "breastsliding" || asAction == "breastslapping"
		Return "breast play"
	ElseIf asAction == "rubbingpenisagainstface"
		Return "a cock rubbed on a face"
	ElseIf asAction == "grindingpenis"
		Return "grinding on a cock"
	ElseIf asAction == "grindingthigh"
		Return "grinding on a thigh"
	ElseIf asAction == "grindingfoot"
		Return "grinding on a foot"
	ElseIf asAction == "grindingobject"
		Return "grinding"
	ElseIf asAction == "gropingtesticles"
		Return "ball groping"
	ElseIf asAction == "suckingnipples" || asAction == "lickingnipples"
		Return "nipple play"
	ElseIf asAction == "lickingvagina"
		Return "cunnilingus"
	ElseIf asAction == "facial" || asAction == "ejaculation_on_face"
		Return "a facial"
	ElseIf asAction == "internalclimax"
		Return "a creampie"
	ElseIf asAction == "cumonchest" || asAction == "ejaculation_on_chest" || asAction == "cumonbelly" || asAction == "cumonbutt" || asAction == "ejaculation_on_butt" || asAction == "cumonvulva" || asAction == "ejaculation_on_vulva" || asAction == "ejaculation_on_hands"
		Return "a cumshot"
	ElseIf asAction == "mounting"
		Return "mounting"
	EndIf
	Return ActName(asAction)
EndFunction
