# QoL

Quality-of-life features for WoW Forever, under one slash command: `/qol`.

## Features

### To-Do (`/qol todo`)

An on-screen to-do list.

- Drag the title bar to move the window anywhere. It remembers where you put it.
- Collapse it to a small title bar with the triangle next to the title or by double-clicking the title.
- Resize it from the bottom-right corner.
- Use as many tabs as you like. Click `+` to add one, double-click a tab to rename it, and right-click a tab to rename or delete it.
- Click a task to edit it, tick it when it's done, or click `x` to delete it.
- `/qol todo clear` deletes every ticked task on the current tab.
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
