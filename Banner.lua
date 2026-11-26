-- Banner: the one place every alert appears, and the one place that decides whether an
-- alert may show. Alerts are queued by key and shown one at a time. Timed alerts
-- (duration set) go first-in first-out and leave on their own; persistent alerts (no
-- duration: Well Fed, rebuff) stay until dismissed and give way to timed ones.
-- Producers only push and dismiss on their own state (buff missing, interval elapsed);
-- combat, death, cinematics and the hide options are checked here, per alert.
-- Position and scale are account-wide (EspiUtilsAccountDB.banner): { x, y } is the
-- banner's center offset from the screen center in UIParent units.

local _, EspiUtils = ...

local MAX_WAIT = 60 -- seconds a timed alert may wait unstarted while blocked before it is dropped
local IDLE_ICON = "Interface\\Icons\\INV_Misc_Bell_01"
local MIN_SCALE, MAX_SCALE, SCALE_STEP = 0.5, 2, 0.1
local DEFAULT_POINT = { "TOP", "TOP", 0, -42 } -- on UIParent, until the banner is moved
local MOVE_HINT = "Drag to move. Scroll to resize."
-- Events that can change whether alerts may show. Some are not on every client: pcall.
local VISIBILITY_EVENTS = {
    "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "PLAYER_MOUNT_DISPLAY_CHANGED", "CINEMATIC_START", "CINEMATIC_STOP", "PLAY_MOVIE", "STOP_MOVIE",
}

local queue = {}      -- every live entry, oldest first: { key, alert, queuedAt, timer, left, startedAt }
local current         -- the entry on screen, nil when none
local layout          -- EspiUtilsAccountDB.banner, set by Banner.Init
local unlocked = false
-- PLAYER_REGEN_DISABLED fires before InCombatLockdown() is true, so combat start is tracked here.
local combat = false
local cinematic = false -- a cinematic or movie is playing
local listeners = {}  -- Banner.OnVisibilityChanged callbacks

local Banner = {}
EspiUtils.Banner = Banner

-- Frame -------------------------------------------------------------------------

local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
frame:SetSize(300, 54)
frame:SetFrameStrata("MEDIUM") -- below the world map and other full-screen panels (HIGH)
frame:SetClampedToScreen(true)
frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
frame:SetBackdropColor(0.07, 0.065, 0.05, 0.96)
frame:SetBackdropBorderColor(0.53, 0.38, 0.19)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:EnableMouse(false)
frame:Hide()

local icon = frame:CreateTexture(nil, "ARTWORK")
icon:SetSize(34, 34)
icon:SetPoint("LEFT", 10, 0)
icon:SetTexture(IDLE_ICON)
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)

local detail = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
detail:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, 0)

-- Fade in when the banner appears. Hiding stays instant.
local fade = frame:CreateAnimationGroup()
local alpha = fade:CreateAnimation("Alpha")
alpha:SetFromAlpha(0)
alpha:SetToAlpha(1)
alpha:SetDuration(0.25)
fade:SetToFinalAlpha(true)
frame:SetScript("OnShow", function() fade:Play() end)
frame:SetScript("OnHide", function(self)
    fade:Stop()
    self:StopMovingOrSizing()
end)

-- Visibility ----------------------------------------------------------------------

-- Whether persistent and timed alerts may show now: alive, out of combat, no cinematic,
-- and not where the player asked to hide them. Timed alerts (posture, water, stand up)
-- also wait while AFK and can be hidden in instances.
local function Visibility()
    if combat or cinematic or not EspiUtils.CanPreviewReminder() then return false, false end
    local general = EspiUtils.General.GetSettings()
    if general.hideMounted and IsMounted and IsMounted() then return false, false end
    local inInstance, kind = IsInInstance()
    if general.hidePvP and (kind == "pvp" or kind == "arena") then return false, false end
    local timed = not (general.timedHideInstances and inInstance) and not (UnitIsAFK and UnitIsAFK("player"))
    return true, timed
end

-- timed: ask for the posture, water and stand up reminders instead of persistent alerts.
function Banner.CanShow(timed)
    local normal, timedOk = Visibility()
    if timed then return timedOk end
    return normal
end

-- Whether alert may show, given this Pick's answers for each kind. Previews ignore the
-- hide options but still wait for a calm moment.
local function Allowed(alert, normal, timed, preview)
    if alert.preview then return preview end
    if alert.timed then return timed end
    return normal
end

-- Queue ---------------------------------------------------------------------------

local function CancelTimer(entry)
    if entry.timer then
        entry.timer:Cancel()
        entry.timer = nil
    end
end

-- Stops a timed entry's countdown, keeping the time it has left.
local function PauseTimer(entry)
    if entry.timer then
        CancelTimer(entry)
        entry.left = math.max(0.1, (entry.left or entry.alert.duration) - (GetTime() - entry.startedAt))
    end
end

local Render

local function Remove(entry)
    CancelTimer(entry)
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

local function Find(key)
    for _, e in ipairs(queue) do
        if e.key == key then return e end
    end
end

-- Timed alerts first (the one showing, then oldest first), then the persistent one
-- already showing, then the oldest persistent. Only alerts allowed right now count.
local function Pick()
    local now = GetTime()
    for i = #queue, 1, -1 do
        local e = queue[i]
        -- Started alerts were interrupted mid-display (combat): they resume instead.
        if e.alert.duration and not e.startedAt and e ~= current and now - e.queuedAt > MAX_WAIT then
            Remove(e)
        end
    end
    if #queue == 0 then return end
    -- Checked once per Pick, not once per entry.
    local normal, timed = Visibility()
    local preview = not combat and EspiUtils.CanPreviewReminder()
    if current and current.alert.duration and Allowed(current.alert, normal, timed, preview) then return current end
    for _, e in ipairs(queue) do
        if e.alert.duration and Allowed(e.alert, normal, timed, preview) then return e end
    end
    if current and Allowed(current.alert, normal, timed, preview) then return current end
    for _, e in ipairs(queue) do
        if Allowed(e.alert, normal, timed, preview) then return e end
    end
end

function Render()
    if unlocked then
        title:SetText("Alerts")
        detail:SetText(MOVE_HINT)
        icon:SetTexture(IDLE_ICON)
        frame:EnableMouse(true)
        frame:Show()
        return
    end
    local entry = Pick()
    if current and current ~= entry then PauseTimer(current) end
    if not entry then
        current = nil
        frame:Hide()
        return
    end
    local alert = entry.alert
    local appeared = entry ~= current or not frame:IsShown()
    current = entry
    title:SetText(alert.title)
    detail:SetText(alert.text or "")
    icon:SetTexture(alert.icon or IDLE_ICON)
    frame:EnableMouse(alert.duration ~= nil)
    frame:Show()
    -- The one place the alert sound plays: whenever a different alert comes on screen.
    if appeared and EspiUtils.General.GetSettings().sound then
        EspiUtils.General.PlaySound()
    end
    if alert.duration and not entry.timer then
        entry.startedAt = GetTime()
        entry.timer = C_Timer.NewTimer(entry.left or alert.duration, function() Expire(entry) end)
    end
end

-- Events arrive in bursts (several frames react to the same one): render once, next frame.
local renderQueued = false
local function DeferredRender()
    renderQueued = false
    Render()
end
local function RequestRender()
    if renderQueued then return end
    renderQueued = true
    C_Timer.After(0, DeferredRender)
end

-- alert: { key, title, text, icon, duration, timed, preview, onRightClick, tooltip = { title, text } }
-- timed: wait while AFK and obey "hide in instances"; preview: ignore the hide options.
-- Pushing a key that is already queued or showing replaces it. The banner redraws on the
-- next frame, so a burst of pushes (countdown ticks, Banner.Test) renders once.
function Banner.Push(alert)
    local entry = Find(alert.key)
    if entry then
        -- A repeated alert starts over.
        CancelTimer(entry)
        entry.left, entry.startedAt = nil, nil
        entry.queuedAt = GetTime()
    else
        entry = { key = alert.key, queuedAt = GetTime() }
        queue[#queue + 1] = entry
    end
    entry.alert = alert
    RequestRender()
end

function Banner.Dismiss(key)
    local entry = Find(key)
    if entry then
        Remove(entry)
        Render()
    end
end

-- fn(event) runs after every visibility event or Refresh, before the banner re-renders.
function Banner.OnVisibilityChanged(fn)
    listeners[#listeners + 1] = fn
end

local function Notify(event)
    for _, fn in ipairs(listeners) do fn(event) end
end

-- Re-evaluate after something that may allow or block alerts changed (a setting, ...).
function Banner.Refresh()
    Notify()
    RequestRender()
end

-- Queues three sample alerts so the order and look can be checked. False when blocked.
function Banner.Test()
    if not EspiUtils.CanPreviewReminder() then return false end
    for i = 1, 3 do
        Banner.Push({
            key = "test" .. i, title = "Test alert " .. i, text = ("Alert %d of 3, shown in order."):format(i),
            icon = IDLE_ICON, duration = 3, preview = true,
        })
    end
    return true
end

-- Position and move mode ------------------------------------------------------------

local function ValidScale(s)
    return type(s) == "number" and s >= MIN_SCALE and s <= MAX_SCALE
end

local function Place()
    if not layout then return end
    local scale = layout.scale or 1
    frame:SetScale(scale)
    frame:ClearAllPoints()
    -- SetPoint offsets are in the frame's own (scaled) units.
    if layout.x then
        frame:SetPoint("CENTER", UIParent, "CENTER", layout.x / scale, layout.y / scale)
    else
        local d = DEFAULT_POINT
        frame:SetPoint(d[1], UIParent, d[2], d[3] / scale, d[4] / scale)
    end
end

local function SavePosition()
    local x, y = frame:GetCenter()
    if not (x and layout) then return end
    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local cx, cy = UIParent:GetCenter()
    layout.x, layout.y = x * ratio - cx, y * ratio - cy
end

local function Resize(delta)
    SavePosition() -- keeps the center where it is
    local scale = math.min(MAX_SCALE, math.max(MIN_SCALE, (layout.scale or 1) + delta * SCALE_STEP))
    layout.scale = math.floor(scale * 100 + 0.5) / 100
    Place()
end

local function SetUnlocked(on)
    unlocked = on
    frame:EnableMouseWheel(on)
    if not on then frame:StopMovingOrSizing() end
    Render()
end

-- Toggles move mode and prints the outcome; returns whether the banner is now unlocked.
function Banner.ToggleMove()
    local Print = EspiUtils.Print
    if not unlocked and (combat or InCombatLockdown()) then
        Print("Can't move the banner in combat.")
        return false
    end
    if not unlocked and UnitIsDeadOrGhost("player") then
        Print("Can't move the banner while dead.")
        return false
    end
    SetUnlocked(not unlocked)
    if unlocked then
        Print("Drag the alert banner to move it, scroll over it to resize. Right-click it or use /espiutils move to lock.")
    else
        Print("Banner locked.")
    end
    return unlocked
end

local function Lock()
    if unlocked then SetUnlocked(false) end
end

-- Back to the default position and size; prints the outcome.
function Banner.ResetPosition()
    if layout then wipe(layout) end
    Place()
    EspiUtils.Print("Banner position and size reset.")
end

frame:SetScript("OnDragStart", function(self)
    if unlocked then self:StartMoving() end
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
    Place()
end)
frame:SetScript("OnMouseWheel", function(_, delta)
    if unlocked and layout then Resize(delta) end
end)
-- Left-click dismisses a timed alert; right-click also runs its onRightClick (e.g. snooze).
-- In move mode, right-click locks.
frame:SetScript("OnMouseUp", function(_, button)
    if unlocked then
        if button == "RightButton" then Banner.ToggleMove() end
        return
    end
    local entry = current
    if not entry or not entry.alert.duration then return end
    if button == "RightButton" and entry.alert.onRightClick then entry.alert.onRightClick() end
    Remove(entry)
    Render()
end)
frame:SetScript("OnEnter", function(self)
    local tip = not unlocked and current and current.alert.tooltip
    if not tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(tip[1])
    GameTooltip:AddLine(tip[2], 1, 1, 1, true)
    GameTooltip:Show()
end)
frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Setup ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        combat = true
        Lock()
    elseif event == "PLAYER_REGEN_ENABLED" then
        combat = false
    elseif event == "PLAYER_DEAD" then
        Lock()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "CINEMATIC_STOP" or event == "STOP_MOVIE" then
        cinematic = false
    elseif event == "CINEMATIC_START" or event == "PLAY_MOVIE" then
        cinematic = true
    end
    Notify(event)
    -- Hide at once as combat starts; everything else can wait a frame.
    if event == "PLAYER_REGEN_DISABLED" then Render() else RequestRender() end
end)

-- account: EspiUtilsAccountDB. Hand-edited or corrupt values fall back to defaults.
function Banner.Init(account)
    -- 1.7.0 to 1.9.x kept the position at account.tiles.banner; the older per-reminder
    -- tile positions in that table are dropped.
    if type(account.banner) ~= "table" then
        local tiles = account.tiles
        account.banner = type(tiles) == "table" and type(tiles.banner) == "table" and tiles.banner or {}
    end
    account.tiles = nil
    layout = account.banner
    if type(layout.x) ~= "number" or type(layout.y) ~= "number" then layout.x, layout.y = nil, nil end
    if not ValidScale(layout.scale) then layout.scale = nil end
    Place()

    for _, event in ipairs(VISIBILITY_EVENTS) do
        pcall(events.RegisterEvent, events, event)
    end
    -- Timed reminders wait while AFK.
    pcall(events.RegisterUnitEvent, events, "PLAYER_FLAGS_CHANGED", "player")
end
