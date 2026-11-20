local _, EspiUtils = ...
local Print = EspiUtils.Print

local DISPLAY_SECONDS = 8
local MAX_MINUTES = 180
local definitions = {
    {
        command = "posture",
        title = "Posture check",
        detail = "Sit tall and relax your shoulders.",
        icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
        minutes = 30,
        y = -42,
    },
    {
        command = "water",
        title = "Drink water",
        detail = "Take a sip of water.",
        icon = "Interface\\Icons\\INV_Drink_07",
        minutes = 60,
        y = -102,
    },
}
local reminders = {}

local function CanShow()
    return not InCombatLockdown() and not UnitIsDeadOrGhost("player")
end

local function Dismiss(reminder)
    if reminder.hideTimer then
        reminder.hideTimer:Cancel()
        reminder.hideTimer = nil
    end
    reminder.frame:Hide()
end

local function Show(reminder)
    Dismiss(reminder)
    reminder.frame:Show()
    reminder.hideTimer = C_Timer.NewTimer(DISPLAY_SECONDS, function()
        reminder.hideTimer = nil
        reminder.frame:Hide()
    end)
end

local function Schedule(reminder)
    reminder.intervalTimer = C_Timer.NewTimer(reminder.settings.minutes * 60, function()
        reminder.intervalTimer = nil
        if CanShow() then
            Show(reminder)
            Schedule(reminder)
        else
            reminder.pending = true
        end
    end)
end

local function Restart(reminder)
    if reminder.intervalTimer then
        reminder.intervalTimer:Cancel()
        reminder.intervalTimer = nil
    end
    reminder.pending = false
    if reminder.settings.enabled then
        Schedule(reminder)
    else
        Dismiss(reminder)
    end
end

function EspiUtils.InitializeTimedReminders(settings)
    settings.timedReminders = settings.timedReminders or {}
    for _, definition in ipairs(definitions) do
        local saved = settings.timedReminders[definition.command]
        if not saved then
            saved = { enabled = true, minutes = definition.minutes }
            settings.timedReminders[definition.command] = saved
        end
        local m = saved.minutes
        if type(m) ~= "number" or m < 1 or m > MAX_MINUTES or m % 1 ~= 0 then
            saved.minutes = definition.minutes
        end
        local frame, detail = EspiUtils.CreateReminder(definition.title, definition.icon)
        frame:SetPoint("TOP", UIParent, "TOP", 0, definition.y)
        detail:SetText(definition.detail)

        local reminder = { frame = frame, settings = saved, title = definition.title }
        reminders[definition.command] = reminder
        Restart(reminder)
    end
end

function EspiUtils.RefreshTimedReminders(event)
    local interrupted = event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_DEAD"
    local blocked = interrupted or not CanShow()
    for _, reminder in pairs(reminders) do
        if blocked then
            Dismiss(reminder)
        elseif reminder.pending then
            reminder.pending = false
            Show(reminder)
            Schedule(reminder)
        end
    end
end

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
    if not reminder or not minutes or minutes < 1 or minutes > MAX_MINUTES or minutes % 1 ~= 0 then
        return false
    end
    if reminder.settings.minutes ~= minutes then
        reminder.settings.minutes = minutes
        Restart(reminder)
    end
    return true
end

-- Returns true when the preview was shown.
function EspiUtils.TestTimedReminder(command)
    local reminder = reminders[command]
    if not reminder or not CanShow() then return false end
    Show(reminder)
    return true
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
        Print(("%s reminders %s."):format(reminder.title, enabled and "enabled" or "disabled"))
    elseif action == "interval" then
        local minutes = tonumber(value)
        if EspiUtils.SetTimedReminderMinutes(command, minutes) then
            Print(("%s interval set to %d min."):format(reminder.title, minutes))
        else
            Print(("Enter a whole number from 1 to %d minutes."):format(MAX_MINUTES))
        end
    elseif action == "test" then
        if not EspiUtils.TestTimedReminder(command) then
            Print("Preview available while alive and out of combat.")
        end
    elseif action == "" or action == "status" then
        Print(("%s reminders %s. Interval: %d min."):format(
            reminder.title, saved.enabled and "enabled" or "disabled", saved.minutes
        ))
    else
        Print(("Use /espiutils %s [on | off | status | interval <minutes> | test]."):format(command))
    end
    return true
end
