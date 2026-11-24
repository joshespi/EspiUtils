# Banner consolidation refactors

Follow-ups from the 1.7.0 review. Version 1.7.0 replaced the per-reminder tiles with one queued alert banner (`Banner.lua`). The code still sits on the old multi-tile setup. Each section below can be done as its own change, in the order given.

## 1. Fold the Tiles system into Banner

**Why:** `Reminder.lua` still has a general multi-tile registry: the `tiles` list, `RegisterTile`, per-key `layout`, `Tiles.Reset(key)`, and loops in `SetUnlocked`, `RefreshTiles` and `InitTiles`. Its only caller is `RegisterTile("banner", ...)`. That is about 150 lines of indirection, and Banner reaches back through `EspiUtils.Tiles.*` using a magic `"banner"` key.

**Where:**
- `Reminder.lua`: the Tiles block (lines ~42-220), `CreateReminder` (lines 3-40, which has one caller and grew a 4th return just for Banner), and `RefreshTiles` in `EspiUtils.General`
- `Banner.lua`: the `RegisterTile` call, `Tiles.IsUnlocked`, `Tiles.Reset("banner")`
- `EspiUtils.lua`: `ToggleTileMove`, `local Tiles`, `/espiutils move [reset]`, and `Tiles.Lock()` (~line 386)
- `Options.lua`: `MOVE_BUTTON`, `RESET_POSITION_BUTTON`, and "Reset all" (`Tiles.Reset()`)

**Proposed approach:**
- Move frame creation, drag, scroll-resize, lock/unlock and position save/restore into `Banner.lua` with one saved layout table.
- Expose `Banner.ToggleMove`, `Banner.Lock`, `Banner.IsUnlocked` and `Banner.ResetPosition`, then delete `EspiUtils.Tiles` and `RegisterTile`.
- Banner renders its own move-mode state (title "Alerts", idle icon, move hint) instead of Tiles writing `MOVE_HINT` into its detail.
- Play the sound in one place: Render, whenever the shown entry changes. This lets you drop the OnShow hook and the `wasShown` bookkeeping.
- Rename leftovers to banner terms, such as the "Reminders locked." prints in `EspiUtils.lua` and `Reminder.lua`, and the "tile" comments in `Reminder.lua`.

**Risks / open questions:**
- Saved-variable shape: see section 3. Do both in one change, or do section 3 first.
- `General.Set` and `General.Reset` refresh through `RefreshTiles`. Replace that with a direct `Banner.Refresh()`.
- The fade animation in `CreateReminder` must move over unchanged.

**Suggested scope:** In scope: Reminder.lua, Banner.lua, EspiUtils.lua and Options.lua move/reset plumbing. Out of scope: the visibility rules (section 2).

## 2. Make Banner the single visibility gate

**Why:** Whether an alert may show is decided in three layers:
- Producers check `CanShowReminder` or `CanShow(true)` themselves. TimedReminders also keeps a `pending` flag and dismisses blocked alerts in `RefreshTimedReminders`.
- Banner `Render` checks `CanShowReminder()`, but without the timed variant.
- Banner `Pick` pauses timers and drops entries after `MAX_WAIT`.

For timed reminders the Banner pause/resume path never runs, because they are dismissed first. Banner also depends on Food's event frame to call `Banner.Refresh()`: if Food stops listening, the banner stops refreshing.

**Where:**
- `Banner.lua`: `Render`, `Pick`, `StopTimer`, `MAX_WAIT`
- `TimedReminders.lua`: `CanShow`, `pending`, `Fire`, `RefreshTimedReminders`
- `EspiUtils.lua`: Food `UpdateReminder` `CanShowReminder` branch, and `Banner.Refresh()` in the shared event branch (~line 393)
- `ClassBuffs.lua`: `UpdateReminder` `CanShowReminder` branch

**Proposed approach:**
- Alerts carry `timed = true`, or a `canShow` predicate. Banner checks `CanShowReminder(entry.timed)` per entry when picking.
- Banner registers its own visibility events: `VISIBILITY_EVENTS`, REGEN enabled/disabled, PLAYER_DEAD/ALIVE/UNGHOST, PLAYER_FLAGS_CHANGED and ADDON_RESTRICTION_STATE_CHANGED.
- Producers only push and dismiss on their own state (buff missing or expiring, interval elapsed).
- Decide one policy for blocked timed alerts: hold them until unblocked (replaces `pending`), or drop them after `MAX_WAIT`.
- Optional: coalesce renders, using a dirty flag plus `C_Timer.After(0, Render)`, so one event triggers one render instead of 3 to 5.

**Risks / open questions:**
- The current behavior on block/unblock has to be kept, or deliberately changed and noted in the CHANGELOG. In particular, a posture reminder that comes due while AFK should fire when you return.
- `PLAYER_REGEN_DISABLED` fires before `InCombatLockdown()` is true. The existing code works around this, and the workaround must move into Banner.
- Known gap today: on `PLAYER_REGEN_DISABLED`, `Banner.Refresh()` sees `CanShowReminder()` as true, so Bewsh and test alerts stay up as combat starts. Passing the event into Refresh is not enough, because the ClassBuffs/Food dismisses in the same event re-render. Banner needs its own combat/dead flag (set on REGEN_DISABLED/PLAYER_DEAD, cleared on REGEN_ENABLED/ALIVE/UNGHOST).
- ADDON_RESTRICTION_STATE_CHANGED can fire before the restriction is enforced. The existing `C_Timer.After(0, ...)` handles this and must be kept.

**Suggested scope:** In scope: visibility logic in Banner, TimedReminders, Food and ClassBuffs. Out of scope: Tiles and layout (section 1), and Bewsh chat posting.

## 3. Saved-variable migration for the banner position

**Why:** `InitTiles` now prunes any key that is not registered so that the old per-tile positions get dropped. That puts migration logic in the shared validator, and it would silently delete a tile that registers after `InitTiles` runs. `EspiUtils.lua` also still creates `account.tiles` and clears the character-level `settings.x`/`settings.y`.

**Where:**
- `Reminder.lua`: `InitTiles` (`registered` map, ~lines 174-180)
- `EspiUtils.lua`: ADDON_LOADED (~lines 320-324)

**Proposed approach:**
- Store the position under `EspiUtilsAccountDB.banner = { x, y, scale }`.
- In ADDON_LOADED run a one-time migration: `account.tiles = nil`, `settings.x, settings.y = nil, nil`.
- Validate only the banner table, and drop the `registered` pruning.

**Risks / open questions:**
- Do users keep their 1.7.0 banner position, which is stored at `account.tiles.banner`? If so, copy it over once before clearing `tiles`.

**Suggested scope:** In scope: saved-variable shape and its validation. Pairs naturally with section 1.
