-- Banner: the one place every alert appears. Alerts are queued by key and shown one at a time.
-- Timed alerts (duration set) go first-in first-out and leave on their own; persistent alerts
-- (no duration: Well Fed, rebuff) stay until dismissed and give way to timed ones.

local _, EspiUtils = ...

local MAX_WAIT = 60 -- seconds a timed alert may wait while blocked before it is dropped
local IDLE_ICON = "Interface\\Icons\\INV_Misc_Bell_01"

local queue = {}   -- every live alert, oldest first
local current      -- the alert on screen, nil when none

local frame, detail, icon, title = EspiUtils.CreateReminder("Alerts", IDLE_ICON)

local function StopTimer(entry)
    if entry.timer then
        entry.timer:Cancel()
        entry.timer = nil
        entry.left = math.max(0.1, (entry.left or entry.duration) - (GetTime() - entry.startedAt))
    end
end

local Render

local function Remove(entry)
    StopTimer(entry)
    for i, e in ipairs(queue) do
        if e == entry then
            table.remove(queue, i)
            break
        end
    end
    if current == entry then current = nil end
end

local function Expire(entry)
    entry.timer = nil
    Remove(entry)
    Render()
end

-- Timed alerts first (oldest first), then the one already showing, then the oldest persistent.
local function Pick()
    local now = GetTime()
    for i = #queue, 1, -1 do
        local e = queue[i]
        if e.duration and e ~= current and now - e.queuedAt > MAX_WAIT then Remove(e) end
    end
    if current and current.duration then return current end
    for _, e in ipairs(queue) do
        if e.duration then return e end
    end
    if current then return current end
    return queue[1]
end

function Render()
    if EspiUtils.Tiles.IsUnlocked() then
        title:SetText("Alerts")
        icon:SetTexture(IDLE_ICON)
        frame:EnableMouse(true)
        frame:Show()
        return
    end
    if not EspiUtils.CanShowReminder() then
        if current then StopTimer(current) end
        frame:Hide()
        return
    end
    local entry = Pick()
    if not entry then
        current = nil
        frame:Hide()
        return
    end
    local wasShown = frame:IsShown()
    local changed = entry ~= current
    current = entry
    title:SetText(entry.title)
    detail:SetText(entry.text or "")
    icon:SetTexture(entry.icon or IDLE_ICON)
    frame:EnableMouse(entry.duration ~= nil)
    frame:Show()
    -- Hidden -> shown plays the sound from the OnShow hook in Reminder.lua; this covers switching alerts.
    if changed and wasShown then EspiUtils.General.PlayAlertSound() end
    if entry.duration and not entry.timer then
        entry.startedAt = GetTime()
        entry.timer = C_Timer.NewTimer(entry.left or entry.duration, function() Expire(entry) end)
    end
end

local function Find(key)
    for _, e in ipairs(queue) do
        if e.key == key then return e end
    end
end

-- alert: { key, title, text, icon, duration, onRightClick, tooltip = { title, text } }
-- Pushing a key that is already queued or showing updates it in place.
local Banner = {}
EspiUtils.Banner = Banner

function Banner.Push(alert)
    local entry = Find(alert.key)
    -- Countdown ticks (Well Fed, rebuff) update the shown alert's text once a second: skip the full render.
    if entry and entry == current and not alert.duration and frame:IsShown() and not EspiUtils.Tiles.IsUnlocked() then
        for k, v in pairs(alert) do entry[k] = v end
        detail:SetText(entry.text or "")
        icon:SetTexture(entry.icon or IDLE_ICON)
        return
    end
    if entry then
        StopTimer(entry)
        entry.left = nil -- a repeated alert starts over
        entry.queuedAt = GetTime()
    else
        entry = { queuedAt = GetTime() }
        queue[#queue + 1] = entry
    end
    for k, v in pairs(alert) do entry[k] = v end
    Render()
end

function Banner.ResetPosition()
    EspiUtils.Tiles.Reset("banner")
end

function Banner.Dismiss(key)
    local entry = Find(key)
    if entry then
        Remove(entry)
        Render()
    end
end

-- Re-evaluate after something that may allow or block alerts changed (combat, mount, ...).
Banner.Refresh = Render

-- Left-click dismisses a timed alert; right-click also runs its onRightClick (e.g. snooze).
EspiUtils.RegisterTile("banner", frame, detail, { "TOP", "TOP", 0, -42 }, Render, function(button)
    local entry = current
    if not entry or not entry.duration then return end
    if button == "RightButton" and entry.onRightClick then entry.onRightClick() end
    Remove(entry)
    Render()
end)

frame:HookScript("OnEnter", function(self)
    if EspiUtils.Tiles.IsUnlocked() or not (current and current.tooltip) then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(current.tooltip[1])
    GameTooltip:AddLine(current.tooltip[2], 1, 1, 1, true)
    GameTooltip:Show()
end)
frame:HookScript("OnLeave", function() GameTooltip:Hide() end)

-- Queues three sample alerts so the order and look can be checked. False when blocked.
function Banner.Test()
    if not EspiUtils.CanPreviewReminder() then return false end
    for i = 1, 3 do
        Banner.Push({
            key = "test" .. i, title = "Test alert " .. i, text = ("Alert %d of 3, shown in order."):format(i),
            icon = IDLE_ICON, duration = 3,
        })
    end
    return true
end
