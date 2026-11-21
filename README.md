# Espi Utils

Small quality-of-life tools for World of Warcraft (retail 12.x and WoW Forever). Open the settings with `/espiutils options` (Esc > Options > AddOns > Espi Utils), or use the commands below. `/espiutils` with no arguments lists them.

This addon replaces the standalone EspiBagRules, KeepBagsOpen and MouseoverMacros addons. A module stays off while its old addon is enabled. To bring your old settings over, log in once with both the old addons and Espi Utils enabled, then disable the old addons and `/reload`: the settings are copied on that load. (WoW only loads an addon's saved settings while that addon is enabled, so disabling the old ones first leaves nothing to copy.)

## Features

### Food reminder

Shows a reminder when Well Fed is missing or about to expire.

`/espiutils food [on | off | status | lead <seconds> | move | reset]`

### Class rebuff reminder

Shows a reminder when a buff your class maintains is missing or about to expire: Priest Fortitude and Inner Fire, Mage Arcane Intellect and armors, Druid Mark of the Wild and Thorns, Warrior Battle Shout. Group buffs are checked on you and on group members who are nearby. For Paladins it only warns when a blessing you cast is running low. Hidden in combat, while dead, and (by default) in rested areas.

`/espiutils rebuff [on | off | status | lead <seconds> | move | reset]`

### Timed reminders

Posture and water reminders that show for a few seconds at an interval, once you are alive and out of combat.

`/espiutils <posture|water> [on | off | status | interval <minutes> | test]`

### Moving and resizing reminders

`/espiutils move` shows every reminder: drag one to move it, scroll over it to resize it, and right-click it (or run `/espiutils move` again) to lock. Positions and sizes are saved account-wide, so every character uses the same layout. `/espiutils move reset` puts them all back.

### Bag Rules

A custom Clean Up. Your general bags are sorted, in on-screen order, into:

1. **Camping**: WoW Forever campfire kits and camp features, the Cozy Sleeping Bag, the Pouch of Violet Dust.
2. **Tools**: profession and rogue tools, fishing poles, enchanting rods.
3. **Set gear**: one block per equipment set, ordered by assigned spec, pieces in paperdoll order.
4. **Toy gear**: gear kept for its Use effect (guild teleport cloaks).
5. **Heirloom**: heirloom gear not in a set.
6. **Other**: everything else by type, quality, item level and name.
7. **BoE**: gear you can still trade or send to an alt (unbound, Warbound, Warbound until equipped).
8. Conjured, then Junk, then Bound gear, pinned to the last slots. With "Sort quest items with junk" on, quest items go at the very end, after the grey items.

Partial stacks are merged, the reagent and profession bags sort within themselves, and bags set to "Ignore this bag" are left alone. Shift-click Clean Up for Blizzard's sort.

`/espiutils bags [sort | stop | preview | on | off | pin | quest | log | debug | probe]`

`/bagrules` and `/brules` still work. The log keeps the last 200 lines in the saved variables, written on `/reload` or logout.

### Keep Bags Open

Bags only close when you close them. When the game closes your bags (vendor, mail, Escape closing another window), they are reopened. Bags you close yourself stay closed, and in combat they come back when combat ends.

`/espiutils keep [on | off | status | blocked | blocked clear]` (no argument toggles). `/kbo` and `/keepbags` still work. `blocked` lists actions the game blocked; include it in bug reports.

### Mouseover Macros

Keeps a character macro named `MO <spell>` for each spell in a per-class list:

```
#showtooltip Flash Heal
/cast [@mouseover,help,nodead][] Flash Heal
```

`/espiutils mouseover [add | harm | del | list | sync] <spells>`. `add` casts on a friendly mouseover, `harm` on a hostile one, both falling back to your target. Shift-click spells in the spellbook to insert them. The list is shared by all characters of the same class; macros are per character. Macro names are cut to 16 characters, so two spells that end up with the same name can't both be added. `/momacro` still works.

## Install

Copy the `EspiUtils` folder into `_retail_/Interface/AddOns/` (or the Forever equivalent).
