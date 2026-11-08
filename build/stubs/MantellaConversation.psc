Scriptname MantellaConversation extends Quest hidden
; Compile stub: only what the bridge calls.
bool Function GetIsTalking()
EndFunction
Function AddExtraRequestAction(string extraAction)
EndFunction
function RequestContinueConversation(bool updateInGameEvents = false)
endFunction

Function sendRequestForPlayerInput(string playerInput, bool updateContext)
EndFunction

Actor Function GetActorByName(string actorName)
EndFunction
int Function CountActorsInConversation()
EndFunction
Actor Function GetActorInConversationByIndex(int indexOfActor)
EndFunction
Function RemoveActorsFromConversation(Actor[] actorsToRemove)
EndFunction
Actor Function GetActorInConversation(string actorName)
EndFunction
bool Function IsPlayerInConversation()
EndFunction
