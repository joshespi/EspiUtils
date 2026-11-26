# Alert and module API refactors

These follow-ups came out of the 1.10.0 review (the banner consolidation, see `banner-consolidation.md`). Each section can be done as its own change. They are listed roughly in order of value.

## 1. Per-alert hold policy in Banner

**Why:** Two layers still handle blocked timed alerts. TimedReminders keeps its own `pending` flag and resumes from `Banner.OnVisibilityChanged`. Banner drops every other blocked timed alert (Boosh, test alerts) after `MAX_WAIT`. The result is two policies for the same situation: a blocked TimedReminders alert is held forever, while any other blocked alert is dropped after 60s. Banner's API (`Banner.CanShow`, `OnVisibilityChanged`) was shaped around this one producer.

**Where:**
- `TimedReminders.lua`: the `pending` flag in `Schedule`, `Snooze` and `Restart`, and the `OnVisibilityChanged` listener near the bottom
- `Banner.lua`: `MAX_WAIT` and the pruning loop at the top of `Pick`

**Proposed approach:**
- Add an alert field, for example `hold = true`, which exempts the alert from `MAX_WAIT`.
- TimedReminders pushes as soon as an alert comes due, with `hold = true`, and drops `pending`.
- Banner spaces held alerts that come out of a block together, so they don't appear back to back. This takes over the 120s stagger that TimedReminders does today by rescheduling (`Schedule(reminder, 0)`).

**Risks / open questions:**
- The stagger: replace it with Banner spacing, or accept that held alerts show back to back. Choose deliberately and note it in the CHANGELOG.
- `lastShown` is saved when an alert fires. Decide whether it should mean "pushed" or "actually shown".
- Food and ClassBuffs now also use `Banner.CanShow` and `OnVisibilityChanged`, to skip scans while blocked, so those APIs stay even after TimedReminders stops needing them.

**Suggested scope:** In scope: Banner.lua and TimedReminders.lua. Out of scope: Food and Rebuff.

## 2. Merge the Food and Rebuff reminder skeleton into NewBuffReminderAPI

**Why:** `Food.lua` and `ClassBuffs.lua` repeat the same skeleton almost line for line:
- `ShowReminder` and `HideReminder` around `Banner.Push` and `Banner.Dismiss` with a fixed key
- `CancelTimer`, and the `timer` field
- the 5-second preview
- the `ADDON_RESTRICTION_STATE_CHANGED` hide-and-retry
- the 0.2s event debounce
- the `Banner.CanShow` gate and the visibility listener

That is about 40 duplicated lines, and every fix has to be made twice.

**Where:**
- `Reminder.lua`: `EspiUtils.NewBuffReminderAPI`
- `Food.lua`: `ShowReminder` through `foodOptions`, plus the `OnEvent` restriction and aura branches
- `ClassBuffs.lua`: `ShowReminder` through `rebuffOptions`, plus `OnSettled`, `Schedule` and the restriction branch

**Proposed approach:**
- Give `NewBuffReminderAPI` `o.key`, `o.title` and `o.icon`.
- Let it own the timer, `Show`/`Hide`, the preview, the debounce and the visibility listener.
- Each module provides only `o.evaluate()`, which returns the state, text, icon and next-check delay. The shared code does the rest.

**Risks / open questions:**
- Rebuff stops listening to `UNIT_AURA` during combat and Food doesn't. Decide whether that becomes shared behaviour.
- The rebuff icon is chosen per entry, so `evaluate` needs to be able to return an icon.

**Suggested scope:** In scope: Reminder.lua, Food.lua and ClassBuffs.lua. Out of scope: the state logic itself (`GetFoodState`, `GetRebuffState`).

## 3. Module APIs return a status; callers print

**Why:** KeepBagsOpen, BagRules and MouseoverMacros each added a boolean that controls printing: `SetEnabled(on, quiet)`, `Sort(verbose)` and `sync(verbose)`. The flags point in opposite directions. They exist because each API prints as a side effect of acting, so every caller with different output needs has to thread a flag through. The callers are the slash command, the options page and the Clean Up hook.

**Where:**
- `KeepBagsOpen.lua`: `SetEnabled`
- `BagRules.lua`: `Sort`
- `MouseoverMacros.lua`: `sync`
- their callers in `Options.lua`, `EspiUtils.lua` and the modules' slash handlers

**Proposed approach:** The APIs return a result (counts, or a status string or enum) and never print. Slash handlers print. The options page shows nothing, or a note.

**Risks / open questions:** Messages printed from deep inside a loop, for example per-item BagRules debug output. Keep those behind `db.debug` rather than returning them.

**Suggested scope:** In scope: these three modules and their callers. Out of scope: the other modules' prints.

## 4. `enabledIf` option on Options `AddCheck`

**Why:** The Boosh page wires "greyed out unless Enabled" by hand inside its check loop, with `if key == "enabled" then RefreshPanel(panel)` and a custom refresher. Every other page that wants the same behaviour would copy it.

**Where:** `Options.lua`: `AddCheck`, `SetCheckEnabled`, and the check loop in `BuildBewsh`.

**Proposed approach:** Add `AddCheck(panel, label, tip, get, set, { enabledIf = fn })`. The check registers a refresher that calls `SetCheckEnabled(check, enabledIf())`. A setter that other checks depend on calls `RefreshPanel`.

**Risks / open questions:** Low value while Boosh is the only user. Do it when a second page needs it.

**Suggested scope:** Options.lua only.
