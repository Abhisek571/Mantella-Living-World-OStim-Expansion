# Mantella Living World - OStim Expansion

Mantella NPCs who live through OStim scenes with you. A module of [Mantella Living World - Integration Hub](https://github.com/Abhisek571/Mantella-Living-World-Hub).

| Feature | What it does |
|---|---|
| Scene flows | Your own animation packs are built into chains of positions. A scene moves on by itself, about 25 seconds per stage, and holds on the last position until the finish or a climax. Only your two-person scenes with an opposite-sex partner. Big-guy, femdom, futa and aggressive sets, and sets such as tied, choke, sleeping or slave, are left out |
| Scene talk | Your partner reacts and talks as the scene goes, and can ask for a change of position (only during sex with you). Talk chance and the gap between spoken lines are set in the MCM. The "Live scene lines" toggle turns off all live scene lines. Shy, openly excited or dirty styling needs the Arousal module |
| Favourite positions | Each close partner is asked once to rate positions from her personality, then up to three favourites are kept from your scenes and told to Mantella when she joins a conversation. Favourites are picked more often |
| Bystanders | After a climax, people in the conversation who are not in the scene may comment. Nobody in any OStim scene can |
| Quiet outfits | Mantella's undress and redress events are muted during any OStim scene |
| Close NPCs only | The sex, group sex, undress and redress actions are offered only to NPCs who are close to you, as the Hub decides |

Requires: [Mantella Living World - Integration Hub](https://github.com/Abhisek571/Mantella-Living-World-Hub), [Mantella - Direct AI Connect](https://github.com/Abhisek571/Mantella-Direct-AI-Connect) (stock Mantella lacks the event-only turn this module needs), [Mantella](https://www.nexusmods.com/skyrimspecialedition/mods/98631) 0.14, Mantella's Advanced Actions turned on (Actions tab of Mantella's settings) for the position and rating actions, [OStim Standalone](https://www.nexusmods.com/skyrimspecialedition/mods/98163) with at least one animation pack, [OSL Aroused](https://www.nexusmods.com/skyrimspecialedition/mods/65454), [Papyrus MessageBox - SKSE NG](https://www.nexusmods.com/skyrimspecialedition/mods/83578), PapyrusUtil SE, SKSE, Actions For Mantella and Mantella Community Resources - ostim (for the sex, undress and redress actions). Optional: [Mantella Living World - Arousal](https://github.com/Abhisek571/Mantella-Living-World-Arousal), which gives the satisfied judgement (a new round starts after her climax if she is not satisfied), temperament styling and the "close" standing.

Build the flows: close the game and run `tools/Mantella Living World - OStim Expansion/Build Flows.cmd` once after installing and after changing animation packs. It needs Python 3 (the `py` launcher) and Mod Organizer 2 (Vortex is not supported). The game warns at launch when flows are not built. Settings: OStim's MCM, page "Living World".

Build: the Hub's `tools/build.py --only ostim`. In-game tests: `bash test/run-tests.sh` (DevBench).

License: GNU AGPL-3.0.
