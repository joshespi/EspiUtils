# Changelog

## 1.11.0

- Bag Rules has a Quest Items group of its own. Drag it anywhere in the group order or untick it to sort quest items in Other (`/espiutils bags quest` toggles it). It replaces "Sort quest items with junk": if you had that on, Quest Items starts right after Junk.
- The banner's Move and Reset buttons now live only on the main options page, and `/espiutils food move | reset` and `/espiutils rebuff move | reset` are gone. Use `/espiutils move [reset]`.
- If timed reminders, quest sort or Boosh fail to start, chat now says so, like the other features already did. A Bag Rules, Keep Bags Open or Mouseover Macros page that failed to start says so instead of blaming an old addon.
- `/espiutils bags hearth` replies like the other group toggles ("Hearthstone group: on"), and the bags help lists every group word on one line.
- The main options page lists the pages by their real titles.
- Internal: in a party or solo, the rebuff reminder listens only to your and your party's auras, and it stops listening while it is off or you're in combat. The food reminder also stops listening then, and after a loot it rechecks only the food it found. Both skip rescans on banner events that don't change whether they can show.
- Internal: shared helpers for saved sub-tables, typed defaults, secret aura checks and bag tooltip scans. Keep Bags Open and Quest Tracker own their defaults.

## 1.10.0

- Bewsh is now Boosh everywhere you see it: the alert, chat posts (`boosh (<level>)`), the options page and the help. `/espiutils boosh` is the command; `/espiutils bewsh` still works, and your settings carry over.
- Quest Tracker can sort with the highest level at the top: tick "Highest level at the top" or use `/espiutils quests order [low | high]`. `status` shows the direction.
- Thorns is only checked on you, so druids no longer get "Thorns missing" for every group member without it.
- Mouseover macro sync removes `MO` macros for spells taken off the list on another character of the same class. Only macros in the exact format the addon writes are removed. `/espiutils mouseover sync` and the Sync button say "macros up to date" when nothing changed.
- Fixed a bank reagent deposit that could start sorting before a second deposit landed.
- Fixed "Untrack non-green quests" reading the wrong difficulty on clients that track quests by log index.
- The food reminder and Keep Bags Open no longer depend on retail-only bag and item enums.
- A rebuff alert for a group member names them: "Arcane Intellect missing on Bob".
- `/espiutils bags sort` and the "Sort now" button print the result ("sorted: …" or "already sorted"). Clean Up stays quiet.
- Typing an out-of-range number on an options page prints the allowed range instead of just snapping back.
- Quest sort says when it pauses because the game keeps undoing the order, and `status` shows it.
- Timed reminder messages use short names ("Water reminders enabled." instead of "Drink water reminders enabled.").
- Every options page scrolls, so long spell lists and smaller options windows no longer cut anything off.
- Boosh's "On level up: post…" checkboxes are greyed out while Boosh is off.
- Keep Bags Open page has "Show blocked actions" and "Clear list" buttons. Its Defaults no longer prints to chat, and "Include reagent bag" is hidden on clients without a reagent bag.
- The spell picker closes with the Settings window, says why when it has nothing to list, and spell rows use the same "Friendly"/"Hostile" wording as the picker.
- A posture, water or stand up reminder that was on screen when combat started comes back for the rest of its time when combat ends, instead of being dropped.
- The test buttons for the food, rebuff, timed and Boosh alerts show even while mounted, AFK or in an instance with those alerts hidden (still not in combat or while dead).
- A Boosh alert that fires during a cinematic waits for it to end (up to a minute) instead of being skipped.
- "Reset position" prints the same "Banner position and size reset." from every button and command.
- Internal: the food and rebuff reminders stop scanning auras and bags while the banner can't show them (combat, mounted with "Hide while mounted", and so on), and catch up as soon as it can.
- Internal: the banner now decides on its own whether any alert may show, the food reminder moved into its own file, and the banner position has its own saved table (your current position is kept). The food check remembers which items give Well Fed instead of re-reading tooltips after every loot.
- Texts that said "posture and water" now include stand up. The quests help line lists `keepeasy` and `order`, and the README lists `test` for food and rebuff.

## 1.9.0

- Posture, water and stand up reminders no longer come due at the same moment: if two would fire together, the later one is moved to at least 2 minutes after the other. This also spaces out reminders that are overdue at login or that piled up during combat.
- Bewsh options page has "Story to say / party / guild" buttons that post the "Why bewsh?" story on demand. The level-up chat checkboxes are relabelled "On level up: ...".

## 1.7.0

- One alert banner: Bewsh, posture, water, stand up, Well Fed and rebuff alerts now appear in a single movable spot and queue one after another instead of stacking. Timed alerts go in order; Well Fed and rebuff stay up and give way to them. Left-click dismisses a timed alert, right-click on a posture, water or stand up alert also snoozes it. The Options page has a "Test banner" button. The banner position is new (per-alert positions are dropped); "Reset position" on any page resets the shared banner, and a page's Defaults no longer moves it.

## 1.6.0

- New "Bewsh" level-up notification: a tile says you bewshed instead of ding, with the story on hover. Optional `bewsh (<level>)` post to guild and/or party (off by default). Settings on the new Bewsh page or `/espiutils bewsh [on | off | status | guild | party | test | story]`.

## 1.5.0

- Bag Rules sections can be dragged into any order on the Bag Rules page. This replaces the "pin" option and the `/espiutils bags pin` command.
- The food reminder only counts food whose tooltip mentions Well Fed, so plain food and water no longer silence it. It stays quiet when you carry no Well Fed food.

## 1.4.0

- Quest Tracker page has an "Untrack non-green quests" button (`/espiutils quests keepeasy`) that keeps only green and grey tracked quests.
- New hourly "Stand up" timed reminder (`/espiutils standup`), with the same options as posture and water.
- Bag Rules can switch off each sorting rule: camping, tools, set gear, use-effect gear, heirlooms, conjured, bound split and junk (`/espiutils bags camping | tools | sets | toys | heirloom | conjured | bound | junk`).
- Keep Bags Open has an "Include reagent bag" option.
- Mouseover Macros has a "Pick spells" spellbook picker and corrects near-miss spell names.
- The food reminder stays quiet when you carry nothing to eat.

## 1.3.0

- Bag Rules has a new option, "Always sort Hearthstone first" (off by default; `/espiutils bags hearth`).

## 1.2.1

- New "All reminders" options on the main page: play a sound when a reminder appears (off by default), hide while mounted, hide in battlegrounds and arenas, and hide the posture and water reminders in instances. All off by default.
- Preview button on the Food Reminder and Class Rebuff pages, and `/espiutils food test` and `/espiutils rebuff test`.
- Reminders fade in instead of popping up.
- Click a shown posture or water reminder to dismiss it; right-click dismisses it and delays the next one by 5 minutes.
- Reminders wait during cinematics and movies, and posture and water reminders wait while you are AFK.
- The rebuff reminder shows the icon of the buff it is about.
- Food and rebuff reminders share their settings and command code.
- "Reset all" on the main page restores those options and every reminder position.
- `/espiutils version`. The help list now includes `bags quest`.
- Reminders sit below the world map and other full-screen panels.
- The settings main page has Discord and Bitcoin donation boxes you can copy from.

## 1.2.0

- The Mouseover Macros page lists each spell as a row with an X to remove it and a button to switch friendly/hostile. Enter in the box adds a spell as friendly.
- New Quest Tracker option: sorts the quest tracker by quest level, lowest first. Off by default; tick it on the Quest Tracker page or use `/espiutils quests`.

## 1.1.0

- New class rebuff reminder: warns when a class buff is missing or about to run out. Tracks Fortitude, Arcane Intellect and your armor, Mark of the Wild and Thorns, Battle Shout and Inner Fire. Paladins are warned when a blessing they cast is running low. Settings are on the new Class Rebuff page or under `/espiutils rebuff`.

## 1.0.2

- Bag Rules has a new option, "Sort quest items with junk" (off by default; `/espiutils bags quest`). Quest items go to the bottom of the bags after the grey items.

## 1.0.1

- The Well Fed reminder is now hidden in rested areas (cities and inns) by default, including for existing characters. Untick "Hide in rested areas" on the Food Reminder page to show it there again.

## 1.0.0

- All reminder tiles (Well Fed, posture, water) can be moved and resized with `/espiutils move` or the Move reminders button: drag to move, scroll to resize, right-click to lock. Positions and sizes are saved account-wide, so every character shares them. The first character to log in carries its Well Fed position over.

- A module that fails to start no longer stops the rest of Espi Utils from loading.
- Missing game APIs (spell data, tooltip info, item locations, class lookup) are now guarded instead of raising errors.
- Moving the Well Fed reminder is refused in combat; failures to register the settings panel are reported in chat.
- Posture and water reminders keep their timing across reloads and logouts.
- The Well Fed reminder can be locked with a right-click, and the Move button closes the Settings window so the reminder is visible.
- Invalid saved Well Fed settings fall back to defaults; checkbox labels are clickable.
- Buff changes are batched, so the Well Fed reminder updates once per burst instead of on every aura event.
- Bag Rules looks up each item's type and reagent flag once instead of on every sort pass.
- Each settings page has a "Reset to defaults" button, and the Settings window's Defaults button now works for the Food, Timed Reminders, Bag Rules and Keep Bags Open pages. Mouseover Macros keeps your spell list.
- Keep Bags Open backs off its retries while a panel blocks bags, and reuses its bag list.
- `/espiutils help` lists the `/espi` alias and `keep blocked clear`.
- Settings from the old standalone addons now copy over: log in once with them enabled, then disable them and /reload. A mouseover spell list that 0.3.0 failed to copy is recovered the same way, as long as no spells were added since.
- The Well Fed reminder no longer appears for a moment as combat starts.
- Moving the Well Fed reminder is refused while dead.
- Turning Keep Bags Open on reopens the saved bags right away instead of on the next bag update.
- `/espiutils keep config` opens the Keep Bags Open page, like `/kbo config`.
- Bag Rules no longer prints "sorting by slot order" on every sort with separate bags (it is in the debug output), and refuses to sort on clients without the ItemLocation API instead of erroring.
- Removing mouseover spells ignores blank entries.
- The water reminder's default interval is now 30 minutes (saved intervals are unchanged).
- Clean Up at the bank waits for the reagent deposits to land before sorting.
- Releases are linted with luacheck before packaging.

## 0.3.0

- Merged EspiBagRules, KeepBagsOpen and MouseoverMacros into Espi Utils as modules. Their commands live under `/espiutils bags`, `/espiutils keep` and `/espiutils mouseover`; the old short commands still work.
- New options screen with a page per feature (`/espiutils options`, or the addon compartment menu).
- Saved settings from the three old addons are copied over on first load.
- A module stays off, with a chat notice, while its old standalone addon is enabled.

The history below is from the merged addons.

## EspiBagRules 1.5.0

- New Tools section at the very top of the bags: profession tools, fishing poles, enchanting rods, Thieves' Tools and other tools sort first, even when poor quality.

## EspiBagRules 1.3.1

- Supports the WoW Forever client (interface 16001) alongside retail.
- Reagent and profession bags: items move into a bag only if its type accepts them. Each item is tried once per sort, which fixes a sort that repeated until it gave up after 60 passes.
- Probe command lists which game APIs the client is missing.
- Loads without errors on clients that lack `Enum.ItemBind` or `ItemLocation`.
- Debug now logs each move.

## EspiBagRules 1.2.x

- Reagents sort into the reagent container when there is space.
- Stop command cancels a sort; a sort announces itself when it starts.
- A sort that falls back to slot order says so in chat.
- Heirloom items get their own section.

## EspiBagRules 1.1.0

- Guild teleport cloaks sort right after set gear, as toy gear.

## EspiBagRules 1.0.0

- First release: custom Clean Up keeping set gear together, BoE gear in the middle, and conjured, junk and bound gear pinned to the last slots.

## KeepBagsOpen 1.0.1

- Bags are no longer reopened during combat; they come back when combat ends (addon-opened bags are tainted).
- When the game blocks an action and blames the addon, it prints and saves the blocked function.

## KeepBagsOpen 1.0.0

- Initial release: bags reopen when the game closes them; bags you close yourself stay closed.
