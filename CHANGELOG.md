# Changelog

Every change to Mantella Living World - OStim Expansion. The Nexus page lists only the main changes for each version.

## Unreleased

### New
- A child in the talk who is far from you (another room or building, farther than about 15 m, or out of sight past about 5 m) is taken out of the talk by the game before your next line goes out: checked every 3 seconds while you talk, when Mantella's text box opens and before every scene action. A child close by still blocks every scene. Distances in SKSE\Plugins\StorageUtilData\MantellaAdultExpansion\child_settings.json.
- ChildLeaves action: a child in the talk leaves it when you or an adult send them away. Offered only while a child is in the talk.
- Children near you but not in the talk are told to the Integration Hub, which adds one cautionary line; nothing is blocked.
- The NPC decides: the sex, group sex and sex between NPCs actions carry the NPC's own decision (accept or decline) and a short reason. A decline starts nothing; it shows on screen, is told back to the NPCs in the talk and is remembered with the talk. A no between two NPCs names the other person only when they are an adult in the conversation. Accept goes on as before, Yes/No box included. Works with the Integration Hub's Intimacy setting: NPC decides (the default) offers the scene to every adult; Lovers only keeps the old rule.

### Changed
- Direct AI Connect's Setup Backend.cmd now builds the flows too when this module is installed. Build Flows.cmd stays, for after you add or remove animation packs.
- Change position and rate favourite positions are offered only while that NPC is in an OStim scene (kisses, hugs and dances do not count), instead of with every talk. The NPC's file says so: set when a scene starts, cleared when it ends, and checked again after a load, at a talk's end and whenever someone joins a talk, so it cannot stay on. Needs an Integration Hub that knows this; with an older Hub these two actions are not offered at all.
- Shorter descriptions for the Affection, ChangePosition, RateFavoritePositions, Undress and Redress actions (less text sent to the model on every reply; same rules). The sex actions are unchanged.

### Fixed
- The scene box names the system and what each answer does: "OStim scene: <name> wants to have sex with you now", with Yes, Skip and No explained.
- The end-of-scene line is told at once with a turn of its own when Mantella waits for you, instead of with your next line.
- Scene lines, climax lines and the end-of-scene summary go only to a talk the player is in: a radiant talk between NPCs nearby no longer hears them, and the summary is kept for the partner's next talk instead.
- A child who joins the talk while the Yes/No/Skip box is open hears nothing about the scene, whatever the player answers.
- An accepted sex action that starts nothing (nobody named is intimate with the player, the box is already open, the player is in another scene) now tells the talk so, and a group scene that starts with fewer people names who takes part.
- The day an NPC accepted a scene is marked only when the scene really starts or is skipped, not on a No or a failed start.
- Affection scenes are never started from a radiant talk the player is not in.
- SexWithNPC sent twice in a row no longer reports a failed start while the first scene runs.
- The list of affection kinds is worked out again after an update that changes affection.json.
- A scene decision other than accept ("no", "refuse") is now a decline. Before, only the exact word decline counted as no.
- Rating favourite positions with no position name that matches is asked again at the next scene (up to three times), instead of leaving the favourites empty for good.
- SexWithNPC is between two NPCs only; its text no longer offers the player as the target (SexWithPlayer is for that).
- A child who joins the talk while an affection scene is still starting (the walk together can take 45 seconds) now ends it at once, with no line about it in the talk; the end line is not told either while a child is in the talk.
- An NPC naming a child in Undress, Redress or SexWithNPC no longer puts a line about the child into the talk; the action is just refused.
- Any OStim scene with a child in it is stopped as soon as it starts, whoever started it (for example someone added in OStim's own actor picker).
- Only the player's partner in the scene can change its position; someone else in the talk asking for a position change is ignored.
- Less stutter when someone joins a talk: the affection kinds come from a cache without copying OStim's whole scene list each time, and chairs are only looked for when a chair kind is installed.
- Scene, climax, pace and end-of-scene lines are never sent for an OStim scene with a child in it, including a child added after the scene began.
- Nobody riding a horse can agree to a scene, and no scene starts while the player is mounted.
- Bystander remarks during a scene come only from people still in the talk, not from someone who already left it.
- Build Flows names the Mod Organizer 2 profile it reads (the one last selected in Mod Organizer 2) and how to pick another. A copy that is not enabled in that profile builds nothing (Direct AI Connect's setup then uses an enabled copy).
- A scene with the player that ends while no Mantella conversation is running (started from another mod's dialogue, for example) is no longer forgotten: each partner is told about it, with how long ago, when she next joins a talk. More than three such scenes are not lost: the oldest are counted and told as more scenes before these.
- A wary stranger is no longer told which affection (a kiss, a hug, a dance) they could share with you right now; only NPCs close to you, Always willing ones, or someone who said yes to a scene with you today are.
- A scene that ended with no conversation going on now comes with its game time, so the Integration Hub dates it and places it after the dialogue that led to it.
- Rating favourite positions now says plainly that the choice is never spoken; the reply carries on with the scene.
- With the Integration Hub, a scene that ended with no conversation going on is kept until the Hub has stored it, and sent again at each talk until then; a talk that ended early no longer loses it. Without the Hub it is sent once, as before.
- A scene longer than a minute was described as lasting "minuteS".
- Undress never leaves an NPC unable to dress: anyone still undressed is dressed again when the talk or the scene ends, and after a load.
- A talk between NPCs no longer hears about the player's scenes or favourite positions, and kept scenes wait for the player's own talk.
- The affection kinds an NPC can share are worked out once per pair of sexes and scene library, not for every NPC who joins.

## 1.2.0 (2026-11-09)

### New
- Affection actions: a couple dance with any NPC you can talk to; kiss, hug, hold hands, cuddle and head pat for close NPCs; lap dance and solo dance for intimate ones.
- Undress, redress and sex actions need the "intimate" check and the NPC's agreement. Radiant talks between NPCs get none of them.
- The five action files that replace the Community Resources actions now have their own descriptions.
- Consent and child checks run before every affection scene, and again when a running scene is changed.

### Fixed
- Changing a running affection scene skipped the consent and child checks.
- Event lines said "The Player" instead of your name.
- A position swap no longer doubles lines.
- Ask, live, positions and flow fixes.

## 1.1.0 (2026-11-01)
- Ask first: a box asks Yes, No or Skip before an NPC starts a scene with you. Skip fades to black, half an hour passes, and it counts as done. Lover's Ledger and favourite positions do not count a skipped scene. Turn it off with "Ask before a scene" in the MCM.
- Your control: OStim's scene menu stays usable during a flow. Pick a scene and the flow steps back for that scene.
- The sex actions fire on a clear yes in conversation, not only on an event saying sex is starting.
- No need to run Build Flows again.

## 1.0.1 (2026-11-01)
- Build Flows finds Mod Organizer 2 when its mods folder is set elsewhere, including global instances. If it still can't, it asks for the folder.
- Build Flows handles any profile name, such as one with brackets.
- Build Flows says when it failed instead of printing Done. With no animation packs it stops and keeps your old flows.

## 1.0.0 (2026-10-30)
- First release. Requires Mantella Living World - Integration Hub and OStim Standalone. Build Flows works with Mod Organizer 2 and Vortex.
