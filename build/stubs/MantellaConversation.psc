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

int Function CountActorsInConversation()
EndFunction
Actor Function GetActorInConversationByIndex(int indexOfActor)
EndFunction
