Scriptname MAE_Test Hidden
{Test harness for Mantella Living World - OStim Expansion, called over DevBench. Test builds only, never released.
Fakes what Mantella would send (conversation members, actions) and drives OStim, and marks each step in the
test log so test\validate.py can check the scripts' decisions against the rules.}

MAE_Flows Function Flows() Global
	Return Game.GetFormFromFile(0x000822, "Mantella Living World - OStim Expansion.esp") as MAE_Flows
EndFunction

GlobalVariable Function Setting(int aiFormID) Global
	Return Game.GetFormFromFile(aiFormID, "Mantella Living World - OStim Expansion.esp") as GlobalVariable
EndFunction

Function Mark(string asLine) Global
	MAE_Text.TestLog("TEST|" + asLine)
EndFunction

; Test mode on or off; on also empties the log.
Function Setup(bool abOn) Global
	If abOn
		MiscUtil.WriteToFile("Data/SKSE/Plugins/MantellaAdultExpansion/test.log", "", false, false)
		Setting(0x000811).SetValue(1.0)
		Mark("setup|finish=" + Setting(0x000806).GetValue())
	Else
		Setting(0x000811).SetValue(0.0)
	EndIf
EndFunction

; Marks the start of a scenario in the log.
Function Begin(string asName) Global
	Mark("begin|" + asName)
EndFunction

int Function Start(Actor akPartner) Global
	Actor[] actors = new Actor[2]
	actors[0] = Game.GetPlayer()
	actors[1] = akPartner
	int thread = OThread.QuickStart(actors)
	Mark("start|" + akPartner.GetDisplayName() + "|thread=" + thread)
	Return thread
EndFunction

; A three-person scene: the player and two partners.
int Function StartGroup(Actor akFirst, Actor akSecond) Global
	Actor[] actors = new Actor[3]
	actors[0] = Game.GetPlayer()
	actors[1] = akFirst
	actors[2] = akSecond
	int thread = OThread.QuickStart(actors)
	Mark("start group|" + akFirst.GetDisplayName() + "+" + akSecond.GetDisplayName() + "|thread=" + thread)
	Return thread
EndFunction

; Real Mantella: the player casts Mantella's conversation spell on akNpc (starts a conversation, or adds her to
; the running one), as the player would.
Function Talk(Actor akNpc) Global
	Spell mantella = Game.GetFormFromFile(0x0022EF, "Mantella.esp") as Spell
	Mark("talk|" + akNpc.GetDisplayName() + "|spell=" + (mantella != None))
	If mantella
		mantella.Cast(Game.GetPlayer(), akNpc)
	EndIf
EndFunction

; Actors in the player's scene, for checking a group start.
string Function SceneActors() Global
	int thread = OActor.GetThreadID(Game.GetPlayer())
	If thread < 0
		Return "no scene"
	EndIf
	Actor[] actors = OThread.GetActors(thread)
	string list = "thread=" + thread + " scene=" + OThread.GetScene(thread) + " actors="
	int i = 0
	While i < actors.Length
		list += actors[i].GetDisplayName() + ","
		i += 1
	EndWhile
	Return list
EndFunction

Function Stop() Global
	int thread = OActor.GetThreadID(Game.GetPlayer())
	Mark("stop|thread=" + thread)
	If thread >= 0
		OThread.Stop(thread)
	EndIf
EndFunction

; Mantella: akNpc joined the conversation.
Function Join(Actor akNpc) Global
	Mark("join|" + akNpc.GetDisplayName())
	int handle = ModEvent.Create("MantellaConversation_NPC_Added")
	If handle
		ModEvent.PushForm(handle, akNpc)
		ModEvent.Send(handle)
	EndIf
EndFunction

; Mantella: the conversation ended.
Function EndConversation() Global
	Mark("conversation ended")
	int handle = ModEvent.Create("MantellaConversation_Ended")
	If handle
		ModEvent.Send(handle)
	EndIf
EndFunction

; Mantella action with one string argument, as Mantella would call it.
Function Action(string asAction, Actor akSpeaker, string asKey, string asValue) Global
	Mark("action|" + asAction + "|" + asKey + "=" + asValue)
	int args = SKSE_HTTP.createDictionary()
	SKSE_HTTP.setString(args, asKey, asValue)
	int handle = ModEvent.Create("MantellaConversation_Advanced_Action_" + asAction)
	If handle
		ModEvent.PushForm(handle, akSpeaker)
		ModEvent.PushForm(handle, None)
		ModEvent.PushInt(handle, args)
		ModEvent.Send(handle)
	EndIf
EndFunction

Function Rate(Actor akNpc, string asPositions) Global
	Action("mantella_mae_rate_positions", akNpc, "positions", asPositions)
EndFunction

Function ChangePosition(Actor akNpc, string asPosition) Global
	Action("mantella_mae_change_position", akNpc, "position", asPosition)
EndFunction

; The player picks another scene by hand.
Function Navigate(string asSceneID) Global
	int thread = OActor.GetThreadID(Game.GetPlayer())
	Mark("navigate|" + asSceneID)
	OThread.WarpTo(thread, asSceneID, false)
EndFunction

Function Excite(Actor akActor, float afValue) Global
	Mark("excite|" + akActor.GetDisplayName() + "|" + afValue)
	OActor.SetExcitement(akActor, afValue)
EndFunction

Function Climax(Actor akActor) Global
	Mark("climax|" + akActor.GetDisplayName())
	OActor.Climax(akActor, true)
EndFunction

; Rolls the next set now.
Function Advance() Global
	Mark("advance")
	Flows().TestAdvance()
EndFunction

; Sets the OSL bridge's satisfied flag the flow reads after her climax (1 = satisfied, 0 = wants more).
Function Satisfied(Actor akNpc, int aiValue) Global
	Mark("satisfied|" + akNpc.GetDisplayName() + "|" + aiValue)
	StorageUtil.SetIntValue(akNpc, "MantellaOSLA_Satisfied", aiValue)
	StorageUtil.SetIntValue(akNpc, "MantellaOSLA_Overwhelmed", 0)
EndFunction

; Clears what the mod learned about akNpc: favourites, rating, last scene.
Function Forget(Actor akNpc) Global
	Mark("forget|" + akNpc.GetDisplayName())
	int count = JsonUtil.StringListCount("MantellaAdultExpansion/flows.json", "poses")
	int i = 0
	While i < count
		StorageUtil.UnsetIntValue(akNpc, "MAE_PoseScore_" + i)
		i += 1
	EndWhile
	StorageUtil.UnsetIntValue(akNpc, "MAE_PosesRated")
	StorageUtil.UnsetStringValue(akNpc, "MAE_LastScenePoses")
EndFunction

string Function Status() Global
	Return Flows().TestState()
EndFunction

; Mantella's outfit tracking switches and the hub's quiet reasons (MLW_Hub.TestState).
string Function Tracking() Global
	MLW_Hub hub = Game.GetFormFromFile(0x000820, "Mantella Living World - Integration Hub.esp") as MLW_Hub
	If !hub
		Return "no hub"
	EndIf
	Return hub.TestState()
EndFunction

; Real Mantella: asks for an event-only turn now (as MAE_Live does), so queued in-game events are sent.
Function EventTurn() Global
	MantellaConversation conversation = Game.GetFormFromFile(0x03D41A, "Mantella.esp") as MantellaConversation
	Mark("event turn|running=" + (conversation && conversation.IsRunning()))
	If conversation && conversation.IsRunning()
		conversation.AddExtraRequestAction("mantella_event_turn")
		conversation.RequestContinueConversation(true)
		int done = ModEvent.Create("Mantella_ActionResponseCompleted")
		If done
			ModEvent.PushString(done, "mantella_event_turn")
			ModEvent.Send(done)
		EndIf
	EndIf
EndFunction

; Real Mantella: sends a line as if the player typed it in the running conversation.
Function Say(string asText) Global
	MantellaConversation conversation = Game.GetFormFromFile(0x03D41A, "Mantella.esp") as MantellaConversation
	Mark("say|running=" + (conversation && conversation.IsRunning()) + "|" + asText)
	If conversation && conversation.IsRunning()
		conversation.sendRequestForPlayerInput(asText, true)
	EndIf
EndFunction
