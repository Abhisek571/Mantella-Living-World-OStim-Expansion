Scriptname MAE_Npc extends Quest
{Mantella's Undress, Redress and SexWithNPC actions land here. Every named NPC is checked on its own: it must be in
the conversation (never someone merely nearby), not a child, close enough to the player (intimate for Undress and
SexWithNPC, close for Redress) and able to agree right now. Nothing happens while a child is in the conversation.
SexWithNPC with the player as the target goes to the Ask First box like the sex action. Undress keeps what it took
off on the NPC, and Redress puts exactly that back on.
On its own quest: SKSE keeps one mod event registration per object.}

Actor Property PlayerRef Auto
MAE_Ask Property Ask Auto
MAE_Positions Property Positions Auto
GlobalVariable Property MAE_TestMode Auto

string Property ACTION_UNDRESS = "mantella_mlw_undress" AutoReadOnly
string Property ACTION_REDRESS = "mantella_mlw_redress" AutoReadOnly
string Property ACTION_SEX_NPC = "mantella_mlw_sex_npc" AutoReadOnly
; StorageUtil form list on the NPC: what Undress took off.
string Property KEY_UNDRESSED = "MAE_Undressed" AutoReadOnly
; StorageUtil form list on this quest: everyone Undress took clothes from, until Redress puts them back.
string Property KEY_UNDRESSED_ACTORS = "MAE_UndressedActors" AutoReadOnly
int Property NEED_CLOSE = 1 AutoReadOnly
int Property NEED_INTIMATE = 2 AutoReadOnly

Event OnInit()
	RegisterForModEvent("MantellaConversation_Advanced_Action_" + ACTION_UNDRESS, "OnUndressAdvanced")
	RegisterForModEvent("MantellaConversation_Advanced_Action_" + ACTION_REDRESS, "OnRedressAdvanced")
	RegisterForModEvent("MantellaConversation_Advanced_Action_" + ACTION_SEX_NPC, "OnSexNpcAdvanced")
EndEvent

Event OnUndressAdvanced(Form akSpeaker, Form akConversation, int aiArguments)
	If MinorPresent()
		Return
	EndIf
	MantellaConversation conversation = akConversation as MantellaConversation
	string[] names = Sources(akSpeaker, aiArguments)
	int i = 0
	While conversation && i < names.Length
		Actor npc = Allowed(conversation, names[i], akSpeaker, NEED_INTIMATE)
		If npc
			Undress(npc)
		EndIf
		i += 1
	EndWhile
EndEvent

Event OnRedressAdvanced(Form akSpeaker, Form akConversation, int aiArguments)
	MantellaConversation conversation = akConversation as MantellaConversation
	string[] names = Sources(akSpeaker, aiArguments)
	int i = 0
	While conversation && i < names.Length
		Actor npc = Allowed(conversation, names[i], akSpeaker, NEED_CLOSE)
		If npc
			Redress(npc)
		EndIf
		i += 1
	EndWhile
EndEvent

Event OnSexNpcAdvanced(Form akSpeaker, Form akConversation, int aiArguments)
	If MinorPresent()
		Return
	EndIf
	MantellaConversation conversation = akConversation as MantellaConversation
	string[] names = Sources(akSpeaker, aiArguments)
	If !conversation || names.Length == 0
		Return
	EndIf
	string targetName = SKSE_HTTP.getString(aiArguments, "target", "")
	Actor target = MAE_Text.TalkActor(conversation, targetName)
	; The NPC's own no (the action's decision): nothing starts, and the player and the talk hear why. The target is
	; named only when it is checked like an accept's: an adult in the conversation (its game name, never the model's
	; text). Anyone else (a child, someone not in the talk, a misspelling) is not named.
	string what = "sex"
	If target == PlayerRef || targetName == ""
		what = "sex with the player"
	ElseIf target && !MAE_Text.IsChildActor(target)
		what = "sex with " + target.GetDisplayName()
	EndIf
	If Ask.Declined(akSpeaker, akConversation, aiArguments, 1, what)
		Return
	EndIf
	Actor source = Allowed(conversation, names[0], akSpeaker, NEED_INTIMATE)
	If !source
		Return
	EndIf
	If target == PlayerRef
		; With the player it is the sex action: the Ask First box decides.
		Actor[] npcs = new Actor[1]
		npcs[0] = source
		Log("SEX NPC|" + source.GetDisplayName() + "|the player: to the box")
		Ask.Request(npcs)
		Return
	EndIf
	If !target
		Log("REFUSED|" + targetName + " is not in the conversation")
		Positions.AddMantellaEvent("Nothing happens: " + targetName + " is not part of this conversation.")
		Return
	ElseIf target == source
		Return
	EndIf
	target = Allowed(conversation, targetName, akSpeaker, NEED_INTIMATE)
	If !target
		Return
	EndIf
	MAE_Text.WaitAfterScene()
	; Someone may have started a scene, joined or fallen asleep meanwhile.
	If MAE_Text.CannotConsent(source) || MAE_Text.CannotConsent(target) || MAE_Text.MinorInTalk()
		Log("REFUSED|changed during the wait")
		Positions.AddMantellaEvent("Nothing starts: this is no moment for it.")
		Return
	EndIf
	Actor[] actors = new Actor[2]
	actors[0] = source
	actors[1] = target
	If OThread.QuickStart(actors) < 0
		; the same action twice in a row: the first one's scene is running, so this one has nothing to report
		If OActor.IsInOStim(source) && OActor.IsInOStim(target)
			Log("SKIPPED|already in a scene")
			Return
		EndIf
		Log("FAILED|QuickStart")
		Positions.AddMantellaEvent("The scene could not start, so " + source.GetDisplayName() + " and " + target.GetDisplayName() + " carry on as they were.")
	Else
		Log("SEX NPC|" + source.GetDisplayName() + "|" + target.GetDisplayName())
	EndIf
EndEvent

; The action's "source" names; the speaker's name when the action named nobody.
string[] Function Sources(Form akSpeaker, int aiArguments)
	string[] names = SKSE_HTTP.getStringArray(aiArguments, "source")
	If names && names.Length > 0
		Return names
	EndIf
	names = new string[1]
	If akSpeaker as Actor
		names[0] = (akSpeaker as Actor).GetDisplayName()
	EndIf
	Return names
EndFunction

; True (and Mantella hears why) while a child is in the conversation.
bool Function MinorPresent()
	If !MAE_Text.MinorInTalk()
		Return false
	EndIf
	Log("REFUSED|a child is in the conversation")
	Positions.AddMantellaEvent("Nothing happens while a child is in the conversation.")
	Return true
EndFunction

; The named conversation member when every check passes; otherwise None, and Mantella hears why.
Actor Function Allowed(MantellaConversation akConversation, string asName, Form akSpeaker, int aiNeed)
	Actor npc = MAE_Text.TalkActor(akConversation, asName)
	If !npc || npc == PlayerRef
		Log("REFUSED|" + asName + " is not an NPC in the conversation")
		Return None
	EndIf
	string name = npc.GetDisplayName()
	If MAE_Text.IsChildActor(npc)
		string speaker = "Nobody"
		If akSpeaker as Actor
			speaker = (akSpeaker as Actor).GetDisplayName()
		EndIf
		Log("REFUSED|" + name + " is a child")
		Positions.AddMantellaEvent(speaker + " will not do that to a child.")
		Return None
	EndIf
	MLW_Channel channel = Ask.Channel()
	If !channel || (aiNeed == NEED_INTIMATE && channel.IntimateValue(npc) <= 0) || (aiNeed == NEED_CLOSE && channel.CloseValue(npc) <= 0)
		Log("REFUSED|" + name + " is not that close")
		Positions.AddMantellaEvent("Nothing happens: " + name + " is not that close to the player.")
		Return None
	EndIf
	If MAE_Text.CannotConsent(npc)
		Log("REFUSED|" + name + " cannot agree now")
		Positions.AddMantellaEvent(name + " is in no state for that right now.")
		Return None
	EndIf
	Return npc
EndFunction

; Takes off every playable piece worn in the 32 body slots and keeps it on the NPC for Redress.
Function Undress(Actor akNpc)
	RegisterCleanup()
	StorageUtil.FormListAdd(self, KEY_UNDRESSED_ACTORS, akNpc, false)
	int slot = 0
	int count = 0
	While slot < 32
		Form worn = akNpc.GetWornForm(Math.LeftShift(1, slot))
		If worn && worn.IsPlayable() && StorageUtil.FormListFind(akNpc, KEY_UNDRESSED, worn) < 0
			StorageUtil.FormListAdd(akNpc, KEY_UNDRESSED, worn, false)
			akNpc.UnequipItem(worn, false, true)  ; never blocked from dressing again
			count += 1
		EndIf
		slot += 1
	EndWhile
	Log("UNDRESS|" + akNpc.GetDisplayName() + "|" + count)
EndFunction

; Puts back on what Undress took off, as far as the NPC still has it.
Function Redress(Actor akNpc)
	int count = StorageUtil.FormListCount(akNpc, KEY_UNDRESSED)
	int i = 0
	While i < count
		Form item = StorageUtil.FormListGet(akNpc, KEY_UNDRESSED, i)
		If item && akNpc.GetItemCount(item) > 0
			akNpc.EquipItem(item, false, true)
		EndIf
		i += 1
	EndWhile
	StorageUtil.FormListClear(akNpc, KEY_UNDRESSED)
	StorageUtil.FormListRemove(self, KEY_UNDRESSED_ACTORS, akNpc, true)
	Log("REDRESS|" + akNpc.GetDisplayName() + "|" + count)
EndFunction

; Nobody is left undressed: when the talk ends (unless they are in a scene), when a scene ends (unless they are still
; in the talk), and after a load (everyone, left from an earlier session). Registered by the first Undress, so saves
; made before this existed get it too.
Function RegisterCleanup()
	RegisterForModEvent("MantellaConversation_Ended", "OnTalkEnded")
	RegisterForModEvent("ostim_thread_end", "OnSceneEnded")
	RegisterForMenu("Loading Menu")
EndFunction

Event OnTalkEnded()
	RedressLeftovers(true, false)
EndEvent

Event OnSceneEnded(string asEventName, string asArg, float afThreadID, Form akSender)
	RedressLeftovers(false, true)
EndEvent

Event OnMenuClose(string asMenuName)  ; Loading Menu: a door keeps a running talk or scene; a loaded save has neither
	RedressLeftovers(true, true)
EndEvent

Function RedressLeftovers(bool abSkipInScene, bool abSkipInTalk)
	int i = StorageUtil.FormListCount(self, KEY_UNDRESSED_ACTORS)
	While i > 0
		i -= 1
		Actor npc = StorageUtil.FormListGet(self, KEY_UNDRESSED_ACTORS, i) as Actor
		If !npc
			StorageUtil.FormListRemoveAt(self, KEY_UNDRESSED_ACTORS, i)
		ElseIf !(abSkipInScene && OActor.IsInOStim(npc)) && !(abSkipInTalk && MAE_Text.InTalk(npc))
			Redress(npc)
		EndIf
	EndWhile
EndFunction

Function Log(string asLine)
	If MAE_TestMode.GetValueInt() == 1
		MAE_Text.TestLog("NPC|" + asLine)
	EndIf
EndFunction
