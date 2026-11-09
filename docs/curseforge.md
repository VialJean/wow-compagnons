# CurseForge project page

Project ID: 1793920. Logo: `docs/logo-512.png`.

## Summary (256 characters max, this one is 245)

Guild crafting hub for WoW Forever: browse every profession recipe, see which guildmates can craft it, and search by recipe or reagent. Recipes sync automatically between guild members through the addon channel, with no website or server needed.

## Description

**Compagnons: Guild Workshop**

Find out who in your guild can craft what, without asking in chat.

**What it does**
- **Recipe browser** (`/cpg` or the minimap button): all ~2,500 Forever recipes, with skill levels, reagents and your current bag and bank stock.
- **Search by recipe or reagent:** accent-insensitive. Type "terrestrine" and see every recipe that uses it.
- **Who can craft it:** guildmates who know the recipe, shown in class colours with their online status. Filter by "craftable in the guild", "crafter online" or "nobody knows it".
- **Profession window panel:** a panel attached to the game's profession window shows who else can craft the selected recipe.
- **Automatic sync:** open a profession once and your known recipes are shared with guildmates who also run the addon. It uses the addon channel, so there is no website, account or server.

**Getting started**
1. Install the addon and log in.
2. Open each of your professions once so the addon can scan them.
3. Type `/cpg` to open the workshop.

**Notes**
- Every guild member who wants to share or see recipes needs the addon. Trial accounts cannot send addon messages.
- Your data stays in your own SavedVariables. Nothing leaves the game.
- Crafting orders are planned next, followed by an optional read-only Discord bridge.

**Commands**
- `/cpg`: open or close the workshop
- `/cpg minicarte`: hide or show the minimap button
- `/cpg sync`: sync status (`/cpg sync annonce` forces an announcement)

Open source (MIT): https://github.com/VialJean/wow-compagnons
