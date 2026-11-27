# Cross-module helpers and remaining hot-path work

Found by a whole-codebase `/espi-review` pass (2026-11-26, the second one that day, after 1.11.0). Plans in `alerts-and-module-apis.md`, `banner-consolidation.md` and `shared-lifecycle-and-perf.md` are not repeated here. Each section stands on its own.

Already done in that pass, ready to build on:
- `Banner.Preview(alert)`: the one preview gate. It returns false when blocked.
- `Banner.InCombat()`.
- `Banner.OnVisibilityChanged(fn)` listeners now get `fn(event, normal, timed)`.
- `EspiUtils.ShowTooltip(owner, anchor, title, ...)` and `EspiUtils.SetTooltip(widget, content, anchor)` in `Reminder.lua`.

---

## 1. One bag iteration helper

**Why:** Three modules each decide which bags exist and how to read slot counts. Only KeepBagsOpen copes with clients that have no `C_Container`.

**Where:**
- `Food.lua`: `LAST_BAG` and the bag/slot loop in `FindFood`.
- `BagRules.lua`: `AllSlots`, and the Backpack..ReagentBag loops in `BuildRegions` and near the snapshot code.
- `KeepBagsOpen.lua`: `MAX_BAG`, `REAGENT_ID`, and the `GetNumSlots` shim with legacy fallbacks.

**Proposed approach:** In `Reminder.lua`, next to `BagTooltipMatches`, add `EspiUtils.BagRange()` (first and last bag ID, reagent bag included when present) and `EspiUtils.NumSlots(bag)`. The shim moves over from KeepBagsOpen. Optionally add `ForEachBagSlot(fn)`. While there, give `BagTooltipMatches` a second return value for "tooltip API missing", so Food's `GrantsWellFed` stops checking `C_TooltipInfo` itself.

**Risks / open questions:**
- BagRules deliberately treats the reagent bag as its own region. The helper must not hide that.
- Food scanning the reagent bag would change behaviour. Keep Food's range as it is unless that is wanted.

**Suggested scope:** In scope: Reminder.lua plus the three modules. Out of scope: the bank.

## 2. `EspiUtils.WhenFrame(getFrame, ownerAddon, fn)`

**Why:** QuestSort (the tracker Sort button) and BagRules (the sort-button hook) each find a Blizzard frame their own way. QuestSort retries on ADDON_LOADED and after combat, and gives up quietly. BagRules looks once at PLAYER_LOGIN and prints when the frame is missing. The next module would invent a third way.

**Where:**
- `QuestSort.lua`: `AttachTrackerButton` and the `attacher` frame.
- `BagRules.lua`: the PLAYER_LOGIN hook setup, around the `BagItemAutoSortButton` lookup.

**Proposed approach:** One helper that runs `fn(frame)` now if `getFrame()` returns a frame. Otherwise it waits for `ownerAddon` to load (`EventUtil.ContinueOnAddOnLoaded` where it exists, else ADDON_LOADED) and, if asked, for the end of combat. It reports once when the owner loaded and there is still no frame.

**Risks / open questions:**
- Which Blizzard addon owns the tracker differs by client (`Blizzard_ObjectiveTracker` on retail; part of FrameXML on classic). Accept a list, or nil for "already loaded".
- Whether creating an unprotected child of the tracker in combat is safe on every client. The combat wait was kept to be careful.

**Suggested scope:** In scope: the helper plus both callers. Out of scope: Options' hooks.

## 3. Validated defaults (`ApplyDefaults` validators or `api.Load`)

**Why:** Every numeric or enum setting needs a hand-written range check after `ApplyDefaults`:
- `Food.lua` `InitializeFood` (lead)
- `ClassBuffs.lua` `InitializeRebuff` (lead)
- `TimedReminders.lua` `InitializeTimedReminders` (minutes)
- `QuestSort.lua` `InitializeQuestSort` (order)

**Where:** `Reminder.lua` `EspiUtils.ApplyDefaults` and `NewBuffReminderAPI`, plus the four init functions above.

**Proposed approach:** Give `ApplyDefaults` an optional `valid = { key = fn(value) }` table that resets a key to its default when `fn` returns false. Food and Rebuff could go further: `NewBuffReminderAPI` already knows `defaults` and `maxLead`, so it could own an `api.Load(store)`.

**Risks / open questions:**
- Food's `hideRestingMigrated` migration has to stay ahead of the defaults.
- Do this before or together with `alerts-and-module-apis.md` #2 (the skeleton merge), not against it.

**Suggested scope:** In scope: the helper plus the four callers. Out of scope: saved-variable migrations.

## 4. KeepBagsOpen: reconcile on a signal instead of polling

**Why:** `Retry` polls every 0.5s, then every 2s with no end, while `ContainerFrame_AllowedToOpenBags()` is false. That covers for the missing "bags allowed again" signal, and the timer runs for as long as a center panel or the hidden UI stays up.

**Where:** `KeepBagsOpen.lua`: `Retry` and the timer setup next to it.

**Proposed approach:** Post-hook `HideUIPanel` and `CloseWindows` (and the UIParent OnShow, for the hidden UI) to call `Reconcile`. Keep the poll only as a capped fallback, for example 10 tries.

**Risks / open questions:**
- Hook coverage differs between clients. Check retail and WoW Forever.
- Some panels close without `HideUIPanel`. The capped fallback covers those.

**Suggested scope:** In scope: KeepBagsOpen.lua. Out of scope: BagRules.

## 5. Banner render does only what changed

**Why:** Every 1s countdown tick (Food and Rebuff expiry) builds a new alert table. ClassBuffs calls `C_Spell.GetSpellTexture` again. `Banner.Render` then sets the title, icon, mouse state and `Show` again, even when the same entry is showing.

**Where:**
- `Banner.lua`: `Render`.
- `ClassBuffs.lua`: `ShowReminder`.
- `Food.lua`: `ShowReminder`.

**Proposed approach:**
- In `Render`, when `entry == current` and the frame is shown, update only `detail` (plus title or icon if they changed).
- In ClassBuffs, cache the spell texture on the buff entry.
- Optionally add `Banner.Update(key, text)` for countdown ticks, which edits the queued alert in place.

**Risks / open questions:**
- `Push` replacing an entry resets its timer on purpose: a repeated alert starts over. `Update` must not do that.
- The sound plays when a different alert comes on screen. That must still work.

**Suggested scope:** In scope: Banner, Food and ClassBuffs. Out of scope: the hold policy (`alerts-and-module-apis.md` #1).

## 6. QuestSort: check what `sorting` actually protects against

**Why:** `sorting` is meant to stop our own watch events from triggering another sort. But a comment in `AutoSort` says those events fire after the function returns, which would make the real guard the "already in order" check plus `MAX_PASSES`. That is three overlapping mechanisms, and one of them may do nothing.

**Where:** `QuestSort.lua`: `sorting`, `Quietly`, `Schedule`, `AutoSort` and `SortOnce`.

**Proposed approach:** In game, log `QUEST_WATCH_LIST_CHANGED` timing relative to `Add`/`Remove`. Then either delete `sorting` (and `Quietly`), or fix the comment. While there, register the quest events only while auto sort is on (the tracker button doesn't need them).

**Risks / open questions:** The timing may differ between retail and classic clients. Test both.

**Suggested scope:** In scope: QuestSort.lua. Out of scope: the tracker button.
