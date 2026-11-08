# QoL

Quality-of-life features for WoW Forever, under one slash command: `/qol`.

## Features

### To-Do (`/qol todo`)

An on-screen to-do list.

- Drag the title bar to move the window anywhere. It remembers where you put it.
- Collapse it to a small title bar by clicking anywhere on the title bar (or the triangle). Click it again to expand. Dragging the title bar still moves the window.
- Resize it from the bottom-right corner.
- Use as many tabs as you like. Click `+` to add one, double-click a tab to rename it, and right-click a tab to rename or delete it.
- Click a task to edit it, tick it when it's done, or click `x` to delete it.
- `/qol todo clear` deletes every ticked task on the current tab.
- A built-in **Campfires** tab lists WoW Forever camp objects and how campfires work. It can't be renamed, deleted or given tasks.
- Lists are shared by all your characters. Each character remembers its own window position.

| Command | What it does |
| --- | --- |
| `/qol` | Show the window if it was closed, otherwise list commands |
| `/qol todo` | Show or hide the window |
| `/qol todo add <text>` | Add a task to the current tab |
| `/qol todo clear` | Delete ticked tasks on the current tab |
| `/qol todo tab <name or number>` | Switch tab |
| `/qol todo newtab <name>` | Create a tab |
| `/qol todo rename <name>` | Rename the current tab |
| `/qol todo collapse` / `expand` | Collapse or expand the window |
| `/qol todo lock` / `unlock` | Stop or allow moving and resizing |
| `/qol todo reset` | Move the window back to the centre |

### Fishing (`/qol fish`)

A built-in **Fishing** tab in the QoL window, next to Campfires.

- Shows the fishing pole you have equipped or in your bags.
- One button swaps your weapons for the pole. Press it again to put your main hand and off-hand back.
- Shows how long the lure on your pole has left.
- Lists the lures you carry (Shiny Bauble, Nightcrawlers, Aquadynamic Fish Lens, Bright Baubles, Flesh Eating Worm, Aquadynamic Fish Attractor) with how many you have. Click one to put it on your pole.
- **One-key fishing:** click **Set Key** on the tab (or `/qol fish key F`). With your pole on, press the key to cast and press it again when the bobber splashes to reel in. If your pole has no lure, the key puts your best one on first.
- While the pole is on, QoL turns on the game's interact key, sets sound effects to full and turns music and ambience off. Your own settings come back when you swap to your weapons.
- Swapping and lures don't work in combat. The lure buttons come back when the fight ends.

| Command | What it does |
| --- | --- |
| `/qol fish` | Swap to your fishing pole, or back to your weapons. Works in a macro too |
| `/qol fish tab` | Open the Fishing tab |
| `/qol fish key <key>` / `off` | Set or clear the one-key fishing key |
| `/qol fish autolure on` / `off` | Let the key put on your best lure first |
| `/qol fish settings on` / `off` | Interact key and fishing sound while the pole is on |
| `/qol fish debug` | Print what QoL sees (pole, weapons, bags) to help fix swap problems |

### Threat (`/qol threat`)

Shows your threat on the enemy you have targeted, as a small number just above the target frame and above the target's nameplate. Each has its own checkbox on the built-in **Misc** tab of the QoL window. The nameplate one needs nameplates turned on (V by default).

### Misc tab

A built-in tab in the QoL window with on/off switches and settings, in sections: **Threat** (target frame and nameplate %), **Pet health** (the warning, its parts and both levels; the parts dim when the warning is off), **Map** (zeppelin, boat and flight master pins), **Window** (how see-through the background is; the text and border stay solid) and **Action bar** (hide the gryphons on either end of the main action bar).

- A small face and your % to pull aggro: `100%` means you pull (or already have it). The face and number follow the game's threat colours: grey, yellow when you are close to pulling, orange, then red when the mob is on you. The face smiles while your threat is low, goes to a flat mouth when you are close (yellow and orange), and opens its mouth once the mob is on you.
- It reads the game's own threat API (`UnitDetailedThreatSituation`). If the client doesn't have it, QoL uses LibThreatClassic2 when another addon (such as Details! or ThreatClassic2) ships it. With neither, nothing is shown.
- It only shows on enemies you can attack, and only once the game reports threat for you on them.

| Command | What it does |
| --- | --- |
| `/qol threat` / `on` / `off` | Turn the threat number on the target frame on or off |
| `/qol threat plate on` / `off` | Turn the threat number above the target's nameplate on or off |
| `/qol threat unlock` / `lock` | Drag the number somewhere else (it stays relative to the target frame) |
| `/qol threat reset` | Put the number back above the target frame |
| `/qol threat raw on` / `off` | Show % of the tank's threat (you pull at 110% in melee, 130% at range) instead of % to pull |
| `/qol threat debug` | Print which threat API the game has and what it returns for your target |

To check by hand: `/dump UnitDetailedThreatSituation` prints `function` if the client has it. Then attack a mob, keep it targeted and run `/dump UnitDetailedThreatSituation("player", "target")`. It returns whether you are tanking, the threat status (0 to 3), your % to pull, your raw %, and your threat value.

### Pet Health (`/qol pet`)

Makes it obvious when your pet (hunter pet or warlock demon) is close to dying.

- **Warning** (35% health by default): a slow orange glow around the pet portrait.
- **Danger** (20% by default): the glow turns into a fast red pulse, the raid warning sound plays once, and `PET 18%` shows in big text above your character for a few seconds. Hunters also see **Mend Pet** under it when it's ready to cast.
- An optional red glow at the screen edges joins in at the danger level. It's off by default because it looks like your own low health warning.
- Each alert only clears once your pet's health is 5% above its line, so it doesn't flicker on and off.
- On clients that hide unit health from addons (WoW Forever 1.60 and later), the game itself fades the glows and a "PET IN DANGER" text in by your pet's health. That mode has no sound, because the addon never sees the number.
- Every part has its own checkbox on the **Misc** tab, with sliders for both levels.

| Command | What it does |
| --- | --- |
| `/qol pet` / `on` / `off` | Turn the whole warning on or off |
| `/qol pet test` | Preview the warning, then the danger alert |
| `/qol pet warn <%>` | Set the warning level |
| `/qol pet danger <%>` | Set the danger level |
| `/qol pet glow` / `sound` / `text` / `screen` `on` / `off` | Turn one part on or off |
| `/qol pet debug` | Print your pet's health and what the warning sees |

### Action bar gryphons (`/qol gryphons`)

Hides the two gryphon pictures on the left and right ends of the main action bar. Turn it on with the checkbox in the **Action bar** section of the Misc tab, or type `/qol gryphons` (also `on` / `off`). It takes effect straight away, works in combat, and doesn't touch your buttons or keybinds. Untick it to bring them back. `/qol gryphons debug` prints how many end caps QoL found, if they ever don't disappear.

### Zeppelins (`/qol zeppelins`)

Puts a pin on the world map and minimap for every zeppelin platform. Hover a pin to see where that zeppelin goes and who the zeppelin master is. Turn it on or off with the checkbox on the **Misc** tab, or with `/qol zeppelins`.

| Tower | Platform | Goes to |
| --- | --- | --- |
| Orgrimmar (Durotar 50.8, 13.5) | Frezza | Undercity, Tirisfal Glades |
| Orgrimmar (Durotar 50.7, 12.9) | Snurk Bucksquick | Grom'gol Base Camp, Stranglethorn Vale |
| Undercity (Tirisfal Glades 60.7, 58.9) | Zapetta | Orgrimmar, Durotar |
| Undercity (Tirisfal Glades 61.8, 59.2) | Hin Denburg | Grom'gol Base Camp, Stranglethorn Vale |
| Grom'gol (Stranglethorn Vale 31.4, 29.9) | Nez'raz | Orgrimmar, Durotar |
| Grom'gol (Stranglethorn Vale 31.5, 29.4) | Squibby Overspeck | Undercity, Tirisfal Glades |
| Skywatcher Plateau (Mulgore 34.3, 25.8) | skyboat | Valanaar, Zephras Isle (Forever only, not checked in game) |
| Dalaran (Alterac Mountains 12.5, 51.8) | skyboat | Valanaar, Zephras Isle (Forever only, not checked in game) |

Docks only one faction can use (Horde zeppelins and skyboat, Alliance boats and ferry) are hidden on characters of the other faction. Ratchet to Booty Bay and the Dalaran skyboat show for everyone.

**Boats** have gold pins (zeppelins are blue), with their own checkbox on the Misc tab:

| Dock | Goes to |
| --- | --- |
| Ratchet (The Barrens 63.4, 38.5) | Booty Bay |
| Booty Bay (Stranglethorn Vale 26.4, 73.6) | Ratchet |
| Menethil Harbor, north pier (Wetlands 5.0, 57.1) | Auberdine (in Forever it stops at Southshore first) |
| Menethil Harbor, south pier (Wetlands 5.3, 63.8) | Theramore |
| Theramore (Dustwallow Marsh 71.3, 56.3) | Menethil Harbor |
| Auberdine (Darkshore 33.2, 40.2, approximate) | Rut'theran Village |
| Auberdine (Darkshore 32.4, 43.8, approximate) | Menethil Harbor |
| Rut'theran Village (Teldrassil 55.0, 96.5, approximate) | Auberdine |
| Feathermoon Stronghold (Feralas 31.0, 39.9, approximate) | The Forgotten Coast |
| The Forgotten Coast (Feralas 43.3, 42.8, approximate) | Feathermoon Stronghold |

Forever's new docks (Stormwind Harbor to Auberdine, Southshore, Steamwheedle Port and Powderfuse Port) have no pins yet because their positions aren't known.

- On zone maps each platform has its own pin. On the continent map a tower has one pin that lists both platforms.
- Minimap pins show when a dock is within minimap range, and follow a rotating minimap.
- The Zephras Isle end of the skyboats has no pin yet, because its map position isn't known.
- If a pin is in the wrong spot, stand next to that zeppelin master and type `/qol zeppelins here`. QoL moves the pin there and prints the new spot.

| Command | What it does |
| --- | --- |
| `/qol zeppelins` / `on` / `off` | Turn the zeppelin pins on or off |
| `/qol zeppelins boats` / `boats on` / `boats off` | Turn the boat pins on or off |
| `/qol zeppelins where` | Print the map and spot you are standing on |
| `/qol zeppelins list` | Print every dock and where it goes |
| `/qol zeppelins here` | Standing on a platform, move that platform's pin to where you are |
| `/qol zeppelins reset` | Put every moved pin back |
| `/qol zeppelins debug` | Print the map IDs and positions QoL is using |
### Flight masters (`/qol flights`)

Puts a pin on the world map and minimap for every flight master, coloured by faction: **blue** for Alliance, **red** for Horde and **green** for neutral ones both factions can use (Ratchet and Marshal's Refuge). Hover a pin to see the flight master's name, what they are (gryphon master, wind rider master and so on), the town and the faction. Turn it on or off with the checkbox in the **Map** section of the Misc tab, or with `/qol flights`.

- All 64 flight masters show by default, both factions. Tick **Only my faction's flight masters** (or `/qol flights mine`) to hide the other side's; neutral ones still show.
- Spots come from QuestieDB's WoW Forever data, so they use Forever's own positions where Forever moved a flight master (Stormwind, Lakeshire and Light's Hope Chapel).
- New in Forever: Grakna (Horde) and Gretchen Mayberry (Alliance) in the Riverglades, and Fayran Elthas (Alliance) in Mount Hyjal. Their tooltips say they haven't been checked in game.
- Zephras Isle has no flight master in that data. It's reached by the skyboats on the zeppelin pins.
- The druid-only flight masters in Thunder Bluff and Darnassus are left out.
- City flight masters (Stormwind, Ironforge, Orgrimmar, Thunder Bluff, Undercity) show on the city map and on the continent map.

| Command | What it does |
| --- | --- |
| `/qol flights` / `on` / `off` | Turn the flight master pins on or off |
| `/qol flights mine` | Show only your faction's flight masters, or every faction's again |
| `/qol flights list` | Print every flight master and where they are |
| `/qol flights debug` | Print how many flight masters QoL could place, and which ones it couldn't |

### Zone Levels (`/qol zones`)

A **Zone Levels** button in the top-right corner of the world map opens a list of questing zones and their suggested levels, grouped by continent.

- Zone names are coloured by faction: red for Horde, blue for Alliance, yellow for contested.
- Click Horde, Alliance or Contested at the top of the list to hide or show those zones. Each character remembers its choice.
- Level ranges are green when you're in range, red when the zone is above you and grey once you've outlevelled it.
- Click a zone to show it on the map. Hover for details.
- Zones new in WoW Forever have a blue `*`. Shen'dralas and Mount Hyjal levels aren't confirmed yet.
- `/qol zones` opens the map with the list showing.

## Install

1. With WowUp: Get Addons, Install from URL, `https://github.com/patrickpoulin/qol`. Or by hand: copy the `QoL` folder into `World of Warcraft/_forever_/Interface/AddOns/`.
2. Restart the game, or type `/reload` if it is already running.
3. Type `/qol` in chat.

The TOC targets interface `16001`. If the game lists QoL as out of date after a patch, check the current number with `/dump select(4, GetBuildInfo())` and update `## Interface` in `QoL/QoL.toc`.

## Development

- Each feature is a module in `QoL/Modules/<Name>/` that calls `QoL:RegisterModule(key, module)` (see `QoL/Core.lua`). Add its files to `QoL/QoL.toc`.
- Saved data: `QoLDB.modules.<key>` (account-wide) and `QoLCharDB.<key>` (per character).
- Lint with `luacheck QoL`. CI runs this on every push.

## Releasing

Bump `## Version` in `QoL/QoL.toc` and push. The Release workflow builds `QoL-v<version>-forever.zip` and publishes it as a GitHub release, which WowUp installs from. It skips versions that already have a release.
