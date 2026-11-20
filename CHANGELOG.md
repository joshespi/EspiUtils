# Changelog

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
