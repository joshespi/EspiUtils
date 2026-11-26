# Espi Utils

Small quality-of-life tools for World of Warcraft (retail 12.x and WoW Forever). Open the settings with `/espiutils options` (Esc > Options > AddOns > Espi Utils), or use the commands below. `/espiutils` with no arguments lists them.

This addon replaces the standalone EspiBagRules, KeepBagsOpen and MouseoverMacros addons. A module stays off while its old addon is enabled. To bring your old settings over, log in once with both the old addons and Espi Utils enabled, then disable the old addons and `/reload`: the settings are copied on that load. (WoW only loads an addon's saved settings while that addon is enabled, so disabling the old ones first leaves nothing to copy.)

## Features

### Food reminder

Shows a reminder when Well Fed is missing or about to expire. It stays quiet when you carry no food.

`/espiutils food [on | off | status | lead <seconds> | test]`

### Class rebuff reminder

Shows a reminder when a buff your class maintains is missing or about to expire: Priest Fortitude and Inner Fire, Mage Arcane Intellect and armors, Druid Mark of the Wild and Thorns, Warrior Battle Shout. Group buffs are checked on you and on group members who are nearby. For Paladins it only warns when a blessing you cast is running low. Hidden in combat, while dead, and (by default) in rested areas.

`/espiutils rebuff [on | off | status | lead <seconds> | test]`

### Timed reminders

Posture, water and stand up reminders that show for a few seconds at an interval, once you are alive and out of combat. Click a shown reminder to dismiss it; right-click to dismiss it and delay the next one by 5 minutes. They wait while you are AFK, and all reminders wait during cinematics.

`/espiutils <posture|water|standup> [on | off | status | interval <minutes> | test]`

### Reminder options

On the main settings page: play a sound when a reminder appears, hide reminders while mounted, hide them in battlegrounds and arenas, and hide the posture, water and stand up reminders in instances. All are off by default. `/espiutils food test` and `/espiutils rebuff test` preview a reminder for a few seconds; `/espiutils version` prints the version.

### Moving and resizing reminders

All alerts (Boosh, posture, water, stand up, Well Fed, rebuff) appear in one banner and queue in order. `/espiutils move` shows the banner: drag it to move it, scroll over it to resize it, and right-click it (or run `/espiutils move` again) to lock. The position and size are saved account-wide, so every character uses the same layout. `/espiutils move reset` puts it back.

### Bag Rules

Bag Rules lets you drag item groups within and between **Top** and **Bottom**. Top starts in the first slot of your general bags and Bottom ends in the last slot. Both follow the list order, with empty slots between them. The order is shared across characters.

By default, Top contains Hearthstone (off by default), Camping, Tools, Equipment Sets, Use-Effect Gear, Heirlooms, Other, Tradeable Gear, and Quest Items. Bottom contains Conjured, Junk, and Bound Gear. Use a row's checkbox to turn its group on or off; with Quest Items off, quest items sort in Other. Preview shows counts in the saved order.

Partial stacks are merged, the reagent and profession bags sort within themselves, and bags set to "Ignore this bag" are left alone. Shift-click Clean Up for Blizzard's sort.

`/espiutils bags [sort | stop | preview | on | off | quest | hearth | camping | tools | sets | toys | heirloom | conjured | bound | junk | log | debug | probe]`

Each group can be switched off with its checkbox on the Bag Rules page or with its command (`camping`, `tools`, `sets`, `toys`, `heirloom`, `conjured`, `bound`, `junk`).

`/bagrules` and `/brules` still work. The log keeps the last 200 lines in the saved variables, written on `/reload` or logout.

### Keep Bags Open

Bags only close when you close them. When the game closes your bags (vendor, mail, Escape closing another window), they are reopened. Bags you close yourself stay closed, and in combat they come back when combat ends.

`/espiutils keep [on | off | status | blocked | blocked clear]` (no argument toggles). `/kbo` and `/keepbags` still work. `blocked` lists actions the game blocked; include it in bug reports. The reagent bag can be left out with "Include reagent bag" on the Keep Bags Open page.

### Quest Tracker

Sorts the quest tracker by quest level (off by default), with the lowest level at the top or, with "Highest level at the top", the highest. Tick it on the Quest Tracker page or use `/espiutils quests [on | off | status | order [low | high]]` (no argument toggles sorting; `order` with no argument flips the direction). It reorders your tracked quests, so turning it off leaves the current order in place.

The "Untrack non-green quests" button (`/espiutils quests keepeasy`) untracks every tracked quest that is yellow, orange or red for your level and keeps the green and grey ones. It never adds quests.

### Mouseover Macros

Keeps a character macro named `MO <spell>` for each spell in a per-class list:

```
#showtooltip Flash Heal
/cast [@mouseover,help,nodead][] Flash Heal
```

`/espiutils mouseover [add | harm | del | list | sync] <spells>`. `add` casts on a friendly mouseover, `harm` on a hostile one, both falling back to your target. Shift-click spells in the spellbook to insert them. The list is shared by all characters of the same class; macros are per character. Macro names are cut to 16 characters, so two spells that end up with the same name can't both be added. `/momacro` still works.

Typed spell names are matched against your spellbook and near-misses are corrected. On the settings page, "Pick spells" lists your spellbook with Friendly and Hostile buttons; or type spells and press Enter (friendly) or use the Add buttons; each listed spell has an X to remove it and a button to switch it between friendly and hostile.

### Boosh

Everyone says "ding" when they level, a habit from the EverQuest days. Back in vanilla WoW, Espi joked that it's really more of a "boosh" noise, and it stuck.

When you level up, a "Boosh!" alert tells you that you booshed (hover over it for the story; click to dismiss). Optionally post `boosh (<level>)` to guild chat, group chat, or both. Group posts go to your party or raid, or to instance chat if you only have a matchmaking group. Both chat options are off by default. If combat locks chat, posts wait until combat ends.

`/espiutils boosh [on | off | status | guild | party | test | story [say | party | guild]]` (`/espiutils bewsh` works too). `story` prints the story to you; add `say`, `party` or `guild` to post it there instead (`say` posts it as one message; party and guild get one sentence per message).

## Install

Copy the `EspiUtils` folder into `_retail_/Interface/AddOns/` (or the Forever equivalent).
