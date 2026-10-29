Scriptname MAE_Bystander extends Quest
{Lets Mantella conversation members who are not in the player's OStim scene
make an occasional remark from the side. MAE_Live asks for a line on each
climax; every bystander rolls a chance that grows with her OSL Aroused arousal.
No OStim types here, so the logic loads and can be tested without OStim. On its
own quest: SKSE keeps one mod event registration per object.}

Actor Property PlayerRef Auto
; 1 = bystanders may comment.
GlobalVariable Property MAE_BystanderComments Auto
; Chance per climax at arousal 0, and the extra chance added at arousal 100.
GlobalVariable Property MAE_BystanderChance Auto
GlobalVariable Property MAE_BystanderArousalChance Auto

; A bystander stays quiet for this many climaxes after her own remark. The
; average gap between remarks is MIN_CLIMAX_GAP + 1 / chance.
int Property MIN_CLIMAX_GAP = 1 AutoReadOnly

Actor[] talkers
; Scene climaxes seen since this talker last commented.
int[] sinceComment

Event OnInit()
	ResetTalkers()
	RegisterForModEvent("MantellaConversation_NPC_Added", "OnNpcAdded")
	RegisterForModEvent("MantellaConversation_NPC_Removed", "OnNpcRemoved")
	RegisterForModEvent("MantellaConversation_Ended", "OnConversationEnded")
EndEvent

Event OnNpcAdded(Form akActor)
	Actor npc = akActor as Actor
	If !npc || npc == PlayerRef || MAE_Text.IsChildActor(npc)
		Return
	EndIf
	If !talkers
		ResetTalkers()
	EndIf
	If talkers.Find(npc) >= 0
		Return
	EndIf
	int i = talkers.Find(None)
	If i >= 0
		talkers[i] = npc
		sinceComment[i] = MIN_CLIMAX_GAP
	EndIf
EndEvent

Event OnNpcRemoved(Form akActor)
	int i = talkers.Find(akActor as Actor)
	If i >= 0
		talkers[i] = None
	EndIf
EndEvent

; Mod events arrive in no fixed order, so nothing resets on conversation start.
Event OnConversationEnded()
	ResetTalkers()
EndEvent

Function ResetTalkers()
	talkers = new Actor[20]
	sinceComment = new int[20]
EndFunction

; Talkers who are not in asSceneActors, for MAE_Live to drop anyone busy
; in another scene before CommentLine.
Actor[] Function Candidates(Actor[] akSceneActors)
	Actor[] result = new Actor[20]
	If !talkers || MAE_BystanderComments.GetValueInt() != 1
		Return result
	EndIf
	int n = 0
	int i = 0
	While i < talkers.Length
		Actor npc = talkers[i]
		If npc && akSceneActors.Find(npc) < 0 && !npc.IsDead() && !MAE_Text.IsChildActor(npc)
			result[n] = npc
			n += 1
		EndIf
		i += 1
	EndWhile
	Return result
EndFunction

; Called once per climax in the player's scene. Counts the climax for every
; candidate, then gives at most one of them a remark. Returns the event line,
; or "". afRoll >= 0 replaces the random roll (testing).
string Function CommentLine(Actor[] akCandidates, string asPartners, float afRoll = -1.0)
	Actor chosen = None
	int i = 0
	While i < akCandidates.Length
		Actor npc = akCandidates[i]
		int slot = talkers.Find(npc)
		If npc && slot >= 0
			sinceComment[slot] = sinceComment[slot] + 1
			If !chosen && sinceComment[slot] > MIN_CLIMAX_GAP
				float roll = afRoll
				If roll < 0.0
					roll = Utility.RandomFloat(0.0, 1.0)
				EndIf
				If roll < Chance(npc)
					chosen = npc
					sinceComment[slot] = 0
				EndIf
			EndIf
		EndIf
		i += 1
	EndWhile
	If !chosen
		Return ""
	EndIf
	string name = chosen.GetDisplayName()
	string their = "his"
	If chosen.GetActorBase().GetSex() == 1
		their = "her"
	EndIf
	Return name + " is in the conversation but not in the scene, watching from the side and waiting " + their + " turn. After " + asPartners + " reacts, " + name + " makes one short, offhand remark, then lets them carry on."
EndFunction

; 0.25 at arousal 0 to 0.50 at arousal 100 by default: with the one-climax gap,
; a remark about every 5 climaxes when calm and every 3 at peak.
float Function Chance(Actor akActor)
	float arousal = OSLArousedNative.GetArousalNoSideEffects(akActor)
	If arousal < 0.0
		arousal = 0.0
	ElseIf arousal > 100.0
		arousal = 100.0
	EndIf
	Return MAE_BystanderChance.GetValue() + MAE_BystanderArousalChance.GetValue() * arousal / 100.0
EndFunction

; Testing: CommentLine with akSceneActor as the only scene member and a fixed roll.
string Function TestComment(Actor akSceneActor, float afRoll)
	Actor[] sceneActors = new Actor[2]
	sceneActors[0] = PlayerRef
	sceneActors[1] = akSceneActor
	Return CommentLine(Candidates(sceneActors), akSceneActor.GetDisplayName(), afRoll)
EndFunction
