Scriptname MAE_Positions extends Quest
{Favourite positions per NPC and the "Change position" Mantella action. Favourites come from a one-time rating
from her personality (Mantella action) plus what she does with the player: every new position in a scene with
the player scores 1, a climax in it scores 3. Her top positions are told to Mantella when she joins a
conversation and make flows with them likelier. On its own quest: SKSE keeps one mod event registration per object.}

Actor Property PlayerRef Auto
MAE_Flows Property Flows Auto

string Property CATALOGUE = "MantellaAdultExpansion/flows.json" AutoReadOnly
string Property ACTION_RATE = "mantella_mae_rate_positions" AutoReadOnly
string Property ACTION_CHANGE = "mantella_mae_change_position" AutoReadOnly
string Property KEY_SCORE = "MAE_PoseScore_" AutoReadOnly
string Property KEY_RATED = "MAE_PosesRated" AutoReadOnly
int Property SCORE_SCENE = 1 AutoReadOnly
int Property SCORE_CLIMAX = 3 AutoReadOnly
int Property SCORE_RATED = 5 AutoReadOnly
int Property TOP = 3 AutoReadOnly

int lastPose = -1

Event OnInit()
	Register()
EndEvent

Function Register()
	RegisterForModEvent("ostim_thread_scenechanged", "OnSceneChanged")
	RegisterForModEvent("ostim_actor_orgasm", "OnOrgasm")
	RegisterForModEvent("ostim_thread_end", "OnThreadEnd")
	RegisterForModEvent("MantellaConversation_NPC_Added", "OnNpcAdded")
	RegisterForModEvent("MantellaConversation_Advanced_Action_" + ACTION_RATE, "OnRateAdvanced")
	RegisterForModEvent("MantellaConversation_Advanced_Action_" + ACTION_CHANGE, "OnChangeAdvanced")
EndFunction

; ---------------------------------------------------------------------------
; Learning from scenes
; ---------------------------------------------------------------------------

Event OnSceneChanged(string asEventName, string asSceneID, float afThreadID, Form akSender)
	Actor partner = Flows.PartnerOf(afThreadID as int)
	If !partner
		Return
	EndIf
	int pose = PoseOf(asSceneID)
	If pose >= 0 && pose != lastPose
		lastPose = pose
		StorageUtil.AdjustIntValue(partner, KEY_SCORE + pose, SCORE_SCENE)
	EndIf
EndEvent

Event OnOrgasm(string asEventName, string asSceneID, float afThreadID, Form akSender)
	Actor climaxed = akSender as Actor
	If !climaxed || climaxed == PlayerRef || Flows.PartnerOf(afThreadID as int) != climaxed
		Return
	EndIf
	int pose = PoseOf(OThread.GetScene(afThreadID as int))
	If pose >= 0
		StorageUtil.AdjustIntValue(climaxed, KEY_SCORE + pose, SCORE_CLIMAX)
	EndIf
EndEvent

Event OnThreadEnd(string asEventName, string asArg, float afThreadID, Form akSender)
	lastPose = -1
EndEvent

; Pose index (into the catalogue's "poses") of a scene, or -1.
int Function PoseOf(string asSceneID)
	If asSceneID == ""
		Return -1
	EndIf
	int i = JsonUtil.StringListFind(CATALOGUE, "sceneId", asSceneID)
	If i < 0
		Return -1
	EndIf
	Return JsonUtil.IntListGet(CATALOGUE, "scenePose", i)
EndFunction

; ---------------------------------------------------------------------------
; Favourites
; ---------------------------------------------------------------------------

; Up to TOP favourite position names, best first; empty when nothing is known yet.
string[] Function Favourites(Actor akActor)
	string[] result = new string[3]
	int count = JsonUtil.StringListCount(CATALOGUE, "poses")
	int[] picked = new int[3]
	int n = 0
	While n < TOP
		int best = -1
		int bestScore = 0
		int i = 0
		While i < count
			int score = StorageUtil.GetIntValue(akActor, KEY_SCORE + i, 0)
			If score > bestScore && (n < 1 || picked[0] != i) && (n < 2 || picked[1] != i)
				best = i
				bestScore = score
			EndIf
			i += 1
		EndWhile
		If best < 0
			Return result
		EndIf
		picked[n] = best
		result[n] = JsonUtil.StringListGet(CATALOGUE, "poses", best)
		n += 1
	EndWhile
	Return result
EndFunction

string Function FavouritesLine(Actor akActor)
	string[] fav = Favourites(akActor)
	int count = fav.Find("")
	If count < 0
		count = fav.Length
	EndIf
	If count == 0
		Return ""
	EndIf
	string list = ""
	int i = 0
	While i < count
		list = MAE_Text.ListAdd(list, fav[i], i == count - 1 && count > 1)
		i += 1
	EndWhile
	Return akActor.GetDisplayName() + "'s favourite sex positions: " + list + "."
EndFunction

Event OnNpcAdded(Form akActor)
	Actor npc = akActor as Actor
	If !npc || npc == PlayerRef || !Flows.Built()
		Return
	EndIf
	string line = FavouritesLine(npc)
	If line == "" && StorageUtil.GetIntValue(npc, KEY_RATED, 0) == 0
		line = npc.GetDisplayName() + "'s favourite sex positions have not been rated yet."
	EndIf
	If line != ""
		AddMantellaEvent(line)
	EndIf
EndEvent

; Mantella's one-time rating from her personality: up to three position names, comma separated.
Event OnRateAdvanced(Form akSpeaker, Form akConversation, int aiArguments)
	Actor npc = akSpeaker as Actor
	If !npc || npc == PlayerRef || StorageUtil.GetIntValue(npc, KEY_RATED, 0) == 1
		Return
	EndIf
	string[] names = PapyrusUtil.StringSplit(SKSE_HTTP.getString(aiArguments, "positions", ""), ",")
	int i = 0
	While i < names.Length && i < TOP
		int pose = JsonUtil.StringListFind(CATALOGUE, "poses", Trim(names[i]))
		If pose >= 0
			StorageUtil.AdjustIntValue(npc, KEY_SCORE + pose, SCORE_RATED)
		EndIf
		i += 1
	EndWhile
	StorageUtil.SetIntValue(npc, KEY_RATED, 1)
EndEvent

; ---------------------------------------------------------------------------
; Change position
; ---------------------------------------------------------------------------

; She agreed to a different position: the flow script plays a matching set.
Event OnChangeAdvanced(Form akSpeaker, Form akConversation, int aiArguments)
	string pose = Trim(SKSE_HTTP.getString(aiArguments, "position", ""))
	If pose == ""
		Return
	EndIf
	If !Flows.PlayPose(pose)
		AddMantellaEvent("There is no way to do " + pose + " here right now, so they carry on as they were.")
		If Flows.MAE_NotifyScene.GetValueInt() == 1
			Debug.Notification("No " + pose + " animation fits here")
		EndIf
	EndIf
EndEvent

; ---------------------------------------------------------------------------

string Function Trim(string asText)
	int start = 0
	int stop = StringUtil.GetLength(asText)
	While start < stop && StringUtil.GetNthChar(asText, start) == " "
		start += 1
	EndWhile
	While stop > start && StringUtil.GetNthChar(asText, stop - 1) == " "
		stop -= 1
	EndWhile
	Return StringUtil.Substring(asText, start, stop - start)
EndFunction

Function AddMantellaEvent(string asLine)
	If Flows.MAE_TestMode.GetValueInt() == 1
		MAE_Text.TestLog("EVENT|" + asLine)
		Return
	EndIf
	int handle = ModEvent.Create("MantellaAddEvent")
	If handle
		ModEvent.PushString(handle, asLine)
		ModEvent.Send(handle)
	EndIf
EndFunction

; Testing: favourites as text.
string Function TestFavourites(Actor akActor)
	Return FavouritesLine(akActor) + " rated=" + StorageUtil.GetIntValue(akActor, KEY_RATED, 0)
EndFunction
