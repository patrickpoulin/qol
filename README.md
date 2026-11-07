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

Shows your threat on the enemy you have targeted, as a small number just above the target frame. Turn it on or off with the checkbox on the built-in **Misc** tab of the QoL window, or with `/qol threat`.

### Misc tab

A built-in tab in the QoL window with on/off switches and settings: the threat % checkbox, and a slider for how see-through the window's background is (the text and border stay solid).

- `Threat 100%` means you pull aggro (or already have it). The colour follows the game's threat colours: grey, yellow when you are close to pulling, orange, then red when the mob is on you.
- It reads the game's own threat API (`UnitDetailedThreatSituation`). If the client doesn't have it, QoL uses LibThreatClassic2 when another addon (such as Details! or ThreatClassic2) ships it. With neither, nothing is shown.
- It only shows on enemies you can attack, and only once the game reports threat for you on them.

| Command | What it does |
| --- | --- |
| `/qol threat` / `on` / `off` | Turn the threat number on or off |
| `/qol threat unlock` / `lock` | Drag the number somewhere else (it stays relative to the target frame) |
| `/qol threat reset` | Put the number back above the target frame |
| `/qol threat raw on` / `off` | Show % of the tank's threat (you pull at 110% in melee, 130% at range) instead of % to pull |
| `/qol threat debug` | Print which threat API the game has and what it returns for your target |

To check by hand: `/dump UnitDetailedThreatSituation` prints `function` if the client has it. Then attack a mob, keep it targeted and run `/dump UnitDetailedThreatSituation("player", "target")`. It returns whether you are tanking, the threat status (0 to 3), your % to pull, your raw %, and your threat value.

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
