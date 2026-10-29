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
