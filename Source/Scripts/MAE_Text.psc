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

; In no state to agree to anything now: dead, gone, asleep, unconscious, bleeding out, paralysed, knocked down,
; fighting or already in a scene.
bool Function CannotConsent(Actor akActor) Global
	If !akActor || akActor.IsDead() || akActor.IsDisabled()
		Return true
	EndIf
	Return akActor.GetSleepState() >= 3 || akActor.IsUnconscious() || akActor.IsBleedingOut() || akActor.GetActorValue("Paralysis") > 0 \
			|| PO3_SKSEFunctions.GetActorKnockState(akActor) != 0 || akActor.IsInCombat() || OActor.IsInOStim(akActor)
EndFunction

; The player can agree: not fighting, and not a werewolf or a vampire lord.
bool Function PlayerCanConsent() Global
	Actor player = Game.GetPlayer()
	If player.IsInCombat()
		Return false
	EndIf
	Race playerRace = player.GetRace()
	Race werewolf = Game.GetFormFromFile(0x0CDD84, "Skyrim.esm") as Race
	Race vampireLord = Game.GetFormFromFile(0x00283A, "Dawnguard.esm") as Race
	Return !playerRace || (playerRace != werewolf && (!vampireLord || playerRace != vampireLord))
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
