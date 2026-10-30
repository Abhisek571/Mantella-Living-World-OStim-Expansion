Mantella Living World - OStim Expansion
Version 1.0.0 by itsPigeon2000

Mantella NPCs who live through OStim scenes with you: scenes that flow on their own from your animation packs, partners who react and talk, bystanders who comment, favourite positions that are remembered.

Requirements
- Mantella Living World - Integration Hub
- Mantella - Direct AI Connect (stock Mantella lacks the event-only turn this module needs)
- Mantella 0.14, with Advanced Actions turned on (Actions tab of Mantella's settings) for the position and rating actions
- OStim Standalone and at least one animation pack
- OSL Aroused
- Papyrus MessageBox - SKSE NG
- PapyrusUtil SE and SKSE
- Actions For Mantella - Expanded Sex Actions, one file in the Files tab of Mantella - Community Resources (https://www.nexusmods.com/skyrimspecialedition/mods/174770), for the sex, undress and redress actions; without it they do nothing. Not the older Actions for Mantella for Mantella 0.13
- Python 3 (the py launcher), to build the flows (Mod Organizer 2 or Vortex)
- Optional: Mantella Living World - Arousal (satisfied judgement, temperament styling, "close" standing)

Before you start
1. Mantella 0.14: install it and check that a normal conversation works.
2. Mantella - Direct AI Connect: install it below Mantella in MO2 and run its Setup Backend.cmd once (needs Python 3.11). Without it the stock Mantella.exe runs and Living World does nothing.
3. Mantella Living World - Integration Hub, then the modules you want.
4. API key: your LLM service's key stays in GPT_SECRET_KEY.txt in the Mantella mod folder (in MO2, right-click Mantella, Open in Explorer). A key for another service goes in the file named on the Direct AI Connect page, next to it.
5. Open Mantella's settings page (http://localhost:4999/ui in your browser, only while Mantella is running), go to the Actions tab and turn on Advanced Actions. Many Living World actions (bribe, persuade, marriage steps, positions, map marks and others) only work with it, and it needs a model that supports tool calling.
6. Nothing happens? Living World Main Status in Mantella's settings page lists what is missing.

Installation
1. Install the hub, then this module. It replaces five action files of Actions For Mantella - Expanded Sex Actions (from Mantella - Community Resources), so it must win over that mod: in MO2 place it below that mod in the left pane; in Vortex set it to load after that mod when Vortex shows the file conflict.
2. Close the game and run Build Flows.cmd (needs Python 3 once). MO2: in this mod's folder, tools\Mantella Living World - OStim Expansion. Vortex: deploy first, then in the game's Data folder (from Vortex's Open menu), tools\Mantella Living World - OStim Expansion.
3. MO2: enable the new mod "Mantella Living World - OStim Expansion - Flows". Vortex: Build Flows makes Documents\Mantella Living World\Mantella Living World - OStim Expansion - Flows.zip; install it with Install From File, enable it and deploy.
4. Run Build Flows again whenever you add or remove animation packs (in Vortex, install the new zip over the old one).

Notes
- Settings: OStim's MCM, page "Living World".
- Flows work only in your own two-person scenes with an opposite-sex partner. Big-guy, femdom, futa and aggressive sets, and sets such as tied, choke, sleeping or slave, are left out.
- Each stage runs about 25 seconds. A chain holds on its last position until the finish or a climax.
- Change Position works only during sex with you. Rating favourite positions is asked once, of close partners.
- The game warns at launch when flows are not built.
- Bystanders are people in the conversation who are not in the scene. They may comment after a climax.
- Quiet outfits mutes Mantella's undress and redress events during any OStim scene.
- "Live scene lines" in the MCM turns off all live scene lines. Shy, openly excited or dirty styling needs the Arousal module.
- The sex, group sex, undress and redress actions are offered only to NPCs close to you. That needs Mantella - Direct AI Connect and the MO2 order above; otherwise they are offered to every NPC.

Credits
- Mantella by Art from the Machine and contributors (AGPL-3.0)
- SKSE team
- PapyrusUtil SE by exiledviper and meh321
- OStim Standalone by Kannonfodder and VersuchDrei
- The animation authors whose packs the flows are built from
- OSL Aroused by ozooma10
- Papyrus MessageBox - SKSE NG by mrowrpurr

License
GNU Affero General Public License v3.0 (see LICENSE.txt). Script sources are included in Scripts\Source.
Source code: https://github.com/Abhisek571/Mantella-Living-World-OStim-Expansion
