local _, EspiUtils = ...
local Print = EspiUtils.Print

local DISPLAY_SECONDS = 8
local MAX_MINUTES = 180
local SNOOZE_MINUTES = 5
local STAGGER_SECONDS = 120
local definitions = {
    {
        command = "posture",
        label = "Posture", -- short name for chat messages
        title = "Posture check",
        detail = "Sit tall and relax your shoulders.",
        icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
        minutes = 40,
    },
    {
        command = "water",
        label = "Water",
        title = "Drink water",
        detail = "Take a sip of water.",
        icon = "Interface\\Icons\\INV_Drink_07",
        minutes = 25,
    },
    {
        command = "standup",
        label = "Stand up",
        title = "Stand up",
        detail = "Stand up and stretch your legs.",
        icon = "Interface\\Icons\\Ability_Rogue_Sprint",
        minutes = 60,
    },
}
local reminders = {}

local function ValidMinutes(m)
    return EspiUtils.IsWholeInRange(m, 1, MAX_MINUTES)
end

local Fire

-- Pushes due later until no other reminder is due within STAGGER_SECONDS,
-- so reminders with the same interval or clock don't all fire at once.
local function Staggered(reminder, due)
    local moved = true
    while moved do
        moved = false
        for _, other in pairs(reminders) do
            if other ~= reminder and other.dueAt and math.abs(due - other.dueAt) < STAGGER_SECONDS then
                due = other.dueAt + STAGGER_SECONDS
                moved = true
            end
        end
    end
    return due
end

local function Schedule(reminder, delay)
    local now = GetTime()
    reminder.dueAt = Staggered(reminder, now + (delay or reminder.settings.minutes * 60))
    reminder.intervalTimer = C_Timer.NewTimer(reminder.dueAt - now, function()
        reminder.intervalTimer = nil
        reminder.dueAt = nil
        if EspiUtils.Banner.CanShow(true) then
            Fire(reminder)
        else
            reminder.pending = true
        end
    end)
end

-- Shows the reminder and starts the next interval. lastShown is saved so that
-- short play sessions still get their reminders.
function Fire(reminder)
    reminder.settings.lastShown = GetServerTime()
    EspiUtils.Banner.Push(reminder.alert)
    Schedule(reminder)
end

-- Pushes the next reminder back by at least SNOOZE_MINUTES (staggering may add more).
local function CancelInterval(reminder)
    if reminder.intervalTimer then
        reminder.intervalTimer:Cancel()
        reminder.intervalTimer = nil
    end
end

local function Snooze(reminder)
    CancelInterval(reminder)
    reminder.pending = false
    Schedule(reminder, SNOOZE_MINUTES * 60)
end

-- resume keeps the saved clock (login); otherwise the interval starts over.
local function Restart(reminder, resume)
    CancelInterval(reminder)
    reminder.dueAt = nil
    reminder.pending = false
    if reminder.settings.enabled then
        local delay
        local last = reminder.settings.lastShown
        if resume and type(last) == "number" then
            delay = math.max(0, last + reminder.settings.minutes * 60 - GetServerTime())
        else
            reminder.settings.lastShown = GetServerTime()
        end
        Schedule(reminder, delay)
    else
        EspiUtils.Banner.Dismiss(reminder.alert.key)
    end
end

local function Defaults(definition)
    return { enabled = true, minutes = definition.minutes }
end

function EspiUtils.InitializeTimedReminders(settings)
    local store = EspiUtils.SubTable(settings, "timedReminders")
    for _, definition in ipairs(definitions) do
        local saved = EspiUtils.SubTable(store, definition.command)
        EspiUtils.ApplyDefaults(saved, Defaults(definition))
        if not ValidMinutes(saved.minutes) then
            saved.minutes = definition.minutes
        end
        local reminder = { settings = saved, definition = definition }
        -- Left-click dismisses the banner; right-click also delays the next reminder.
        reminder.alert = {
            key = definition.command,
            title = definition.title,
            text = definition.detail,
            icon = definition.icon,
            duration = DISPLAY_SECONDS,
            timed = true, -- waits while AFK, obeys "hide in instances"
            onRightClick = function()
                if saved.enabled then Snooze(reminder) end
            end,
        }
        reminders[definition.command] = reminder
        Restart(reminder, true)
    end
end

-- Reminders that came due while blocked fire once alerts may show again. One that
-- was on screen when it got blocked is paused by the banner and comes back on its own.
EspiUtils.Banner.OnVisibilityChanged(function(_, _, timedOk)
    if not timedOk then return end
    for _, reminder in pairs(reminders) do
        if reminder.pending then
            -- Schedule (not Fire) so reminders that piled up while blocked stagger.
            reminder.pending = false
            Schedule(reminder, 0)
        end
    end
end)

-- API shared by the slash command and the options screen.
EspiUtils.TimedReminderMaxMinutes = MAX_MINUTES

function EspiUtils.GetTimedReminders()
    return definitions
end

function EspiUtils.GetTimedReminder(command)
    local reminder = reminders[command]
    return reminder and reminder.settings
end

function EspiUtils.SetTimedReminderEnabled(command, enabled)
    local reminder = reminders[command]
    if not reminder then return end
    if not enabled or reminder.settings.enabled ~= enabled then
        reminder.settings.enabled = enabled
        Restart(reminder)
    end
end

-- Returns true when minutes was a valid whole number in range.
function EspiUtils.SetTimedReminderMinutes(command, minutes)
    local reminder = reminders[command]
    if not reminder or not ValidMinutes(minutes) then
        return false
    end
    if reminder.settings.minutes ~= minutes then
        reminder.settings.minutes = minutes
        Restart(reminder)
    end
    return true
end

function EspiUtils.ResetTimedReminders()
    for _, definition in ipairs(definitions) do
        local reminder = reminders[definition.command]
        if reminder then
            EspiUtils.ApplyDefaults(reminder.settings, Defaults(definition), true)
            Restart(reminder)
        end
    end
end

-- Returns true when the preview was shown.
function EspiUtils.TestTimedReminder(command)
    local reminder = reminders[command]
    if not reminder then return false end
    -- A preview shows even while AFK or in an instance.
    return EspiUtils.Banner.Preview(CopyTable(reminder.alert))
end

function EspiUtils.HandleTimedReminderCommand(command, action, value)
    local reminder = reminders[command]
    if not reminder then
        return false
    end

    local saved = reminder.settings
    if action == "on" or action == "off" then
        local enabled = action == "on"
        EspiUtils.SetTimedReminderEnabled(command, enabled)
        Print(("%s reminders %s."):format(reminder.definition.label, enabled and "enabled" or "disabled"))
    elseif action == "interval" then
        local minutes = tonumber(value)
        if EspiUtils.SetTimedReminderMinutes(command, minutes) then
            Print(("%s interval set to %d min."):format(reminder.definition.label, minutes))
        else
            Print(("Enter a whole number from 1 to %d minutes."):format(MAX_MINUTES))
        end
    elseif action == "test" then
        if not EspiUtils.TestTimedReminder(command) then EspiUtils.PrintPreviewBlocked() end
    elseif action == "" or action == "status" then
        Print(("%s reminders %s. Interval: %d min."):format(
            reminder.definition.label, saved.enabled and "enabled" or "disabled", saved.minutes
        ))
    else
        Print(("Use /espiutils %s [on | off | status | interval <minutes> | test]."):format(command))
    end
    return true
end
