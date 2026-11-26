# Shared lifecycle helpers, command registry and hot-path work

Found by a whole-codebase `/simplify` pass (2026-11-26). These are too large, or touch too many files, for that pass. Each section stands on its own. Plans in `alerts-and-module-apis.md` and `banner-consolidation.md` are not repeated here.

Shared helpers added in that pass, ready to build on (all in `Reminder.lua`):
- `EspiUtils.SubTable(store, key)`
- `ApplyDefaults(db, defaults, overwrite, typed)`
- `EspiUtils.IsSecret` and `EspiUtils.AurasSecret()`
- `EspiUtils.PlayerClass`
- `EspiUtils.BagTooltipMatches`
- `EspiUtils.PrintPreviewBlocked`

`EspiUtils.lua` also gained a local `Start(title, init, ...)` and `EspiUtils.offReason`.

---

## 1. `EspiUtils.AfterCombat(key, fn)`

**Why:** Four modules each keep their own "wanted to act in combat, retry on PLAYER_REGEN_ENABLED" logic: their own flag, their own event registration and their own branch in the event handler. Each copy can grow the same lifecycle bug.

**Where:**
- `QuestSort.lua`: `deferred`, the `SortNow` combat branch, and the `PLAYER_REGEN_ENABLED` branch in its OnEvent.
- `MouseoverMacros.lua`: `pending`, the `sync()` combat branch, and the `elseif pending then sync()` branch in its OnEvent.
- `Bewsh.lua`: `pendingChat`, plus registering and unregistering `PLAYER_REGEN_ENABLED` in `PostChat` and `ClearPendingChat`. Its gate is `ChatLocked()`, not `InCombatLockdown()`.
- `KeepBagsOpen.lua`: `deferred` in `Reconcile`. It only partly fits, because `SaveState` reads the deferred list and `Reconcile` already runs on every REGEN_ENABLED.

**Proposed approach:** Add one frame in `Reminder.lua` that listens for `PLAYER_REGEN_ENABLED` while a queue is non-empty. `AfterCombat(key, fn)` runs `fn` now when out of combat, or else stores `queue[key] = fn`, so repeats collapse. On REGEN_ENABLED it runs and clears every entry, each under `xpcall`. Then move QuestSort and Mouseover onto it. Bewsh needs a `gate` option for the chat lockdown, or keeps its own queue and uses only the flush trigger.

**Risks / open questions:**
- Event order: Banner, Food and ClassBuffs also react to REGEN_ENABLED, and Banner's combat flag clears in its handler. Callbacks must not depend on the banner having cleared first.
- Is `InCombatLockdown()` already false when REGEN_ENABLED fires? It should be, but verify on WoW Forever.

**Suggested scope:** In: the helper, QuestSort, Mouseover. Optional: Bewsh. Out: KeepBagsOpen, which keeps its data-bearing `deferred`.

---

## 2. `EspiUtils.Debounce(fn, delay)`

**Why:** The same "flag plus `C_Timer.After`, then clear the flag and call" scheduler is hand-written five times.

**Where:**
- `Banner.lua` `RequestRender` (delay 0)
- `QuestSort.lua` `Schedule` (0, with extra guards)
- `KeepBagsOpen.lua` `Schedule` (0)
- `Food.lua` `auraPending` / `OnAurasSettled` (0.2)
- `ClassBuffs.lua` `Schedule` / `OnSettled` (0.2)

**Proposed approach:** `EspiUtils.Debounce(fn, delay)` returns a `request()` function, and calling it schedules `fn` once. Callers with extra guards (QuestSort's `sorting` / `db.enabled`) check them before calling `request()`. Coordinate with plan #2 in `alerts-and-module-apis.md`, which merges the Food and Rebuff skeletons; do this first or together with it.

**Risks / open questions:** `C_Timer.After` cannot be cancelled, so a debounced call that becomes moot still runs. That is the same as today.

**Suggested scope:** In: the helper and all five sites. Out: KeepBagsOpen `Retry`, whose backoff delay is different.

---

## 3. Rebuff group scan: rescan only changed units

**Why:** In a raid, every member's aura change (HoTs, procs) triggers a full rescan: `ReachableUnits()` over 40 units, then `GetAuraDataBySpellName` for each unit × name × entry. For a Paladin that is about 400 lookups a pass, up to 5 passes a second. The 1 s countdown tick reruns the same full scan.

**Where:** `ClassBuffs.lua`: `GetRebuffState`, `ReachableUnits`, `ManaUnits`, `UpdateReminder`, and the UNIT_AURA handler (`OnAura`).

**Proposed approach:**
1. Use UNIT_AURA's `updateInfo`. Ignore an event unless it is a full update, an added aura's name is one of the tracked names, or a removed `auraInstanceID` is one we saw on that unit.
2. Keep per-unit results (`best remaining per entry`) and mark only the units that changed as dirty. `UpdateReminder` rescans only the dirty units, then picks the best result from the cache.
3. Countdown ticks reuse the cached expiration times and do no API calls.
4. At minimum, reuse the scratch tables with `wipe()`.

**Risks / open questions:**
- `updateInfo` fields differ by client. WoW Forever may not send them, in which case fall back to treating every event as a full update.
- Reachability (range or visibility) changes without an aura event. Today's countdown tick and roster events hide that gap, and a cache must not make it worse.

**Suggested scope:** In: ClassBuffs only. Out: Food (player only, already cheap).

---

## 4. Build options pages on first open

**Why:** `InitializeOptions` builds all nine pages at ADDON_LOADED: a few hundred frames, font strings and closures, including the 12-row bag-order list and its drag handlers. It then refreshes every page, on every login and /reload, though most sessions never open Settings.

**Where:** `Options.lua`: `NewPage`, every `Build*` function, `InitializeOptions`, `RefreshOptions` and `OpenOptions`.

**Proposed approach:** Keep creating and registering each outer `page` frame up front, because Settings needs it. Give each page a `build` function that runs on its first `OnShow` / `OnRefresh` and sets `page.built`. `RefreshOptions` skips pages that aren't built yet.

**Risks / open questions:**
- The Settings window sometimes shows a page without firing OnShow, which is why `OnRefresh` exists. Verify that first-show building works on retail and on WoW Forever's `InterfaceOptions` path.
- `OnDefault` is wired in `AddDefaults` at build time. It has to be set on the outer page up front, or lazily, before the Defaults button can be used.

**Suggested scope:** In: Options.lua only. Out: any change to the page contents.

---

## 5. Bag sort: keep each slot's record between passes

**Why:** Each pass (every 50 ms, up to 60 passes) re-reads and re-classifies every slot from scratch: `GetContainerItemInfo`, item level, equipment-set info, quest info, a key string and a fresh record. It then re-sorts the whole list, although only the slots in `run.pending` changed.

**Where:** `BagRules.lua`: `Scan`, `Classify`, `Step`, `MergeRegion`, `OrderRegion`, `BuildDesired`.

**Proposed approach:** Keep `run.snaps` across passes. At the start of a pass, re-scan only the slots in the previous pass's `run.pending`, plus any slot whose `hyperlink` / `stackCount` changed, if that check is cheap. The desired layout depends only on the multiset of records, so compute it once and recompute it only after merges.

**Risks / open questions:**
- Item locks and other addons moving items mid-sort. A cheap full verification pass before `Done` keeps correctness.
- Merges change counts in place.

**Suggested scope:** In: the move engine. Out: classification rules and sort order.

---

## 6. Timed reminders as one API table

**Why:** Timed reminders expose seven loose globals: `EspiUtils.GetTimedReminders`, `GetTimedReminder`, `SetTimedReminderEnabled`, `SetTimedReminderMinutes`, `ResetTimedReminders`, `TestTimedReminder` and `TimedReminderMaxMinutes`. Every other module exposes one table (`EspiUtils.Food`, `.Keep`, `.QuestSort`, ...).

**Where:** `TimedReminders.lua` (bottom half), `Options.lua` `BuildTimed`, and `EspiUtils.lua`, which calls `HandleTimedReminderCommand`.

**Proposed approach:** Replace them with `EspiUtils.Timed = { List, Get, SetEnabled, SetMinutes, Reset, Test, MAX_MINUTES }` and update the two callers.

**Risks / open questions:** None beyond the rename. Do it with #7 if that lands, because the command handler moves too.

**Suggested scope:** In: TimedReminders.lua and its two callers.

---

## 7. Command registry and shared toggle/reminder handlers

**Why:**
- Slash dispatch in `EspiUtils.lua` is an if/elseif chain with inline aliases, plus a separate `MODULE_ALIASES` table, plus a fall-through into `HandleTimedReminderCommand`. `PrintHelp` is kept up to date by hand.
- Handler signatures differ: raw `rest` for the legacy modules, `(action, value)` for the others.
- QuestSort and KeepBagsOpen hand-roll the same on/off/status/toggle/options handler.
- TimedReminders' handler repeats `HandleBuffReminderCommand` word for word, apart from the value argument.

**Where:**
- `EspiUtils.lua` (`SlashCmdList.ESPIUTILS`, `PrintHelp`, `MODULE_ALIASES`)
- `QuestSort.lua` `HandleQuestSortCommand`
- `KeepBagsOpen.lua` `HandleKeepBagsCommand`
- `TimedReminders.lua` `HandleTimedReminderCommand`
- `Reminder.lua` `HandleBuffReminderCommand`
- BagRules `on`/`off`

**Proposed approach:**
1. Add a registry of `{ names = {...}, handler, usage }`. Dispatch becomes a lookup, `PrintHelp` is generated from `usage`, and Timed registers its three words.
2. Handle `/espiutils <module> options` once, generically.
3. Add `EspiUtils.HandleToggleCommand(action, { get, set, status, optionsKey, usage, extra = { ... } })` for QuestSort, Keep and BagRules on/off.
4. Generalise `HandleBuffReminderCommand` so it takes the value word (`lead` / `interval`), its setter and its messages, and use it for Timed.

**Risks / open questions:**
- Plan #3 in `alerts-and-module-apis.md` changes what `SetEnabled` prints. Do that first or together.
- Keep the standalone `/bagrules`, `/keepbags` and `/momacro` slash commands working.

**Suggested scope:** In: dispatch, help and the shared handlers. Out: changing any command's words or replies, beyond generated help text.

---

## 8. Saved-variable schema version and one-time migrations

**Why:** One-time migrations live inside module init functions and run on every load, each with its own marker:
- Food: `hideRestingMigrated`, and clearing `settings.x` / `settings.y`.
- Banner: clearing `account.tiles`.
- BagRules: `pinBound` and `questToJunk`.
- KeepBagsOpen: string compatibility in `Ago`.

Food also keeps its settings at the root of `EspiUtilsDB`, mixed in with other modules' tables.

**Where:** `Food.lua` `InitializeFood`, `Banner.lua` `Banner.Init`, `BagRules.lua` `InitBagRules`, `KeepBagsOpen.lua` `Ago`, and the `ADDON_LOADED` handler in `EspiUtils.lua`.

**Proposed approach:** Add `schema` numbers on `EspiUtilsDB` and `EspiUtilsAccountDB`, with an ordered list of migrations that `ADDON_LOADED` runs once, before any module init. Then module inits can assume the current shape. Moving Food's settings to `EspiUtilsDB.food` becomes one more migration.

**Risks / open questions:**
- Saved data from very old versions, and characters not logged in for a long time: migrations must stay idempotent and order-safe.
- The legacy-addon `Migrate` in `EspiUtils.lua` is a different mechanism and should stay as it is.

**Suggested scope:** In: the schema and moving the existing migrations. Optional: Food's sub-table move. Out: new settings.
