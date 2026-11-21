# Changelog

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
