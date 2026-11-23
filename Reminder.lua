local _, EspiUtils = ...

function EspiUtils.CreateReminder(titleText, iconPath)
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
    frame:Hide()

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(34, 34)
    icon:SetPoint("LEFT", 10, 0)
    icon:SetTexture(iconPath)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
    title:SetText(titleText)

    local detail = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    detail:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, 0)

    -- Fade in when the tile appears. Hiding stays instant: many paths call Hide().
    local fade = frame:CreateAnimationGroup()
    local alpha = fade:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(1)
    alpha:SetDuration(0.25)
    fade:SetToFinalAlpha(true)
    frame:HookScript("OnShow", function() fade:Play() end)
    frame:HookScript("OnHide", function() fade:Stop() end)
    return frame, detail, icon
end

-- Tiles -------------------------------------------------------------------------
-- Every reminder is a tile. Position and scale are account-wide (EspiUtilsAccountDB.tiles):
-- { x, y } is the tile's center offset from the screen center in UIParent units.

local MIN_SCALE, MAX_SCALE, SCALE_STEP = 0.5, 2, 0.1
local MOVE_HINT = "Drag to move. Scroll to resize."
local tiles = {}   -- in registration order
local layout       -- set by InitTiles
local unlocked = false
local general = {} -- EspiUtils.InitGeneral replaces it with the saved settings
local cinematic = false -- a cinematic or movie is playing
local RAID_WARNING_SOUND_ID = 8959 -- SOUNDKIT.RAID_WARNING, for clients without SOUNDKIT

-- Set from the cinematic events; callers refresh the reminders afterwards.
function EspiUtils.SetCinematic(on)
    cinematic = on and true or false
end

function EspiUtils.IsCinematic()
    return cinematic
end

-- Updates the flag from a cinematic or movie event; ignores other events.
function EspiUtils.TrackCinematic(event)
    if event == "CINEMATIC_START" or event == "PLAY_MOVIE" then
        cinematic = true
    elseif event == "CINEMATIC_STOP" or event == "STOP_MOVIE" then
        cinematic = false
    end
end

local function ValidScale(s)
    return type(s) == "number" and s >= MIN_SCALE and s <= MAX_SCALE
end

local function Place(tile)
    if not layout then return end
    local saved = layout[tile.key]
    local frame = tile.frame
    local scale = saved and saved.scale or 1
    frame:SetScale(scale)
    frame:ClearAllPoints()
    -- SetPoint offsets are in the frame's own (scaled) units.
    if saved and saved.x then
        frame:SetPoint("CENTER", UIParent, "CENTER", saved.x / scale, saved.y / scale)
    else
        local d = tile.default
        frame:SetPoint(d[1], UIParent, d[2], d[3] / scale, d[4] / scale)
    end
end

local function SavePosition(tile)
    local frame = tile.frame
    local x, y = frame:GetCenter()
    if not x then return end
    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local cx, cy = UIParent:GetCenter()
    local saved = layout[tile.key] or {}
    saved.x, saved.y = x * ratio - cx, y * ratio - cy
    layout[tile.key] = saved
end

local function Resize(tile, delta)
    SavePosition(tile) -- keeps the center where it is
    local saved = layout[tile.key]
    if not saved then return end
    local scale = math.min(MAX_SCALE, math.max(MIN_SCALE, (saved.scale or 1) + delta * SCALE_STEP))
    saved.scale = math.floor(scale * 100 + 0.5) / 100
    Place(tile)
end

local function SetUnlocked(on)
    unlocked = on
    for _, tile in ipairs(tiles) do
        tile.frame:EnableMouse(on or tile.onClick ~= nil)
        tile.frame:EnableMouseWheel(on)
        if on then
            tile.detail:SetText(MOVE_HINT)
            tile.frame:Show()
        else
            tile.frame:StopMovingOrSizing()
            tile.refresh()
        end
    end
end

-- default: { point, relativePoint, x, y } on UIParent, used until the tile is moved.
-- refresh: restores the tile's normal text and visibility after moving ends.
-- onClick(button): optional; called when the shown tile is clicked outside move mode.
function EspiUtils.RegisterTile(key, frame, detail, default, refresh, onClick)
    local tile = { key = key, frame = frame, detail = detail, default = default, refresh = refresh, onClick = onClick }
    tiles[#tiles + 1] = tile
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:EnableMouse(onClick ~= nil)
    frame:SetScript("OnDragStart", function(self)
        if unlocked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if layout then
            SavePosition(tile)
            Place(tile)
        end
    end)
    frame:SetScript("OnMouseWheel", function(_, delta)
        if unlocked and layout then Resize(tile, delta) end
    end)
    frame:SetScript("OnMouseUp", function(_, button)
        if unlocked then
            if button == "RightButton" then
                SetUnlocked(false)
                EspiUtils.Print("Reminders locked.")
            end
        elseif onClick then
            onClick(button)
        end
    end)
    frame:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
    end)
    -- OnShow only fires when a hidden tile appears, not on every text update.
    frame:HookScript("OnShow", function()
        if general.sound and not unlocked then
            EspiUtils.General.PlaySound()
        end
    end)
    Place(tile)
end

-- store: EspiUtilsAccountDB.tiles. Hand-edited or corrupt entries fall back to defaults.
function EspiUtils.InitTiles(store)
    for key, saved in pairs(store) do
        if type(saved) ~= "table" then
            store[key] = nil
        else
            if type(saved.x) ~= "number" or type(saved.y) ~= "number" then
                saved.x, saved.y = nil, nil
            end
            if not ValidScale(saved.scale) then saved.scale = nil end
            if next(saved) == nil then store[key] = nil end
        end
    end
    layout = store
    for _, tile in ipairs(tiles) do Place(tile) end
end

-- Tile API, shared by the slash commands and the options screen.
EspiUtils.Tiles = {
    MOVE_HINT = MOVE_HINT,
    IsUnlocked = function() return unlocked end,
    -- Returns whether tiles are now unlocked, plus a message when it was refused.
    Toggle = function()
        if not unlocked and InCombatLockdown() then
            return false, "Can't move reminders in combat."
        end
        if not unlocked and UnitIsDeadOrGhost("player") then
            return false, "Can't move reminders while dead."
        end
        SetUnlocked(not unlocked)
        return unlocked
    end,
    Lock = function()
        if unlocked then SetUnlocked(false) end
    end,
    -- Back to the default position and size; every tile when key is nil.
    Reset = function(key)
        for _, tile in ipairs(tiles) do
            if not key or tile.key == key then
                if layout then layout[tile.key] = nil end
                Place(tile)
            end
        end
    end,
}

-- General settings (EspiUtilsAccountDB.general), shared by every reminder -----------

local GENERAL_DEFAULTS = {
    sound = false,              -- play a sound when a reminder appears
    hideMounted = false,        -- hide reminders while mounted
    hidePvP = false,            -- hide reminders in battlegrounds and arenas
    timedHideInstances = false, -- hide posture and water reminders inside instances
}

local function RefreshTiles()
    for _, tile in ipairs(tiles) do
        if not unlocked then tile.refresh() end
    end
end

EspiUtils.General = {
    GetSettings = function() return general end,
    Set = function(key, value)
        if GENERAL_DEFAULTS[key] == nil then return end
        general[key] = value and true or false
        RefreshTiles()
    end,
    Reset = function()
        EspiUtils.ApplyDefaults(general, GENERAL_DEFAULTS, true)
        RefreshTiles()
    end,
    PlaySound = function()
        PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or RAID_WARNING_SOUND_ID)
    end,
}

-- Events that change whether reminders may show. Not on every client, so register with pcall.
EspiUtils.VISIBILITY_EVENTS = { "PLAYER_MOUNT_DISPLAY_CHANGED", "CINEMATIC_START", "CINEMATIC_STOP", "PLAY_MOVIE", "STOP_MOVIE" }

-- store: EspiUtilsAccountDB.general. Anything that is not a boolean falls back to its default.
function EspiUtils.InitGeneral(store)
    for key, default in pairs(GENERAL_DEFAULTS) do
        if type(store[key]) ~= "boolean" then store[key] = default end
    end
    general = store
end

-- Reminders only show while alive and out of combat, and not where the player
-- asked to hide them. timed: the posture and water reminders, which can also be
-- hidden in instances.
function EspiUtils.CanShowReminder(timed)
    if not EspiUtils.CanPreviewReminder() or cinematic then return false end
    if timed and UnitIsAFK and UnitIsAFK("player") then return false end
    if general.hideMounted and IsMounted and IsMounted() then return false end
    if general.hidePvP or (timed and general.timedHideInstances) then
        local inInstance, kind = IsInInstance()
        if general.hidePvP and (kind == "pvp" or kind == "arena") then return false end
        if timed and general.timedHideInstances and inInstance then return false end
    end
    return true
end

-- Shared pieces of the Food and Rebuff reminders ------------------------------------
-- o.key: tile key; o.label: "Food"; o.defaults: saved defaults; o.maxLead;
-- o.settings(): the saved table (nil before load); o.update(): re-evaluate the tile;
-- o.preview(): show a 5 second preview.
-- Returns the settings API used by the slash command and the options screen.
function EspiUtils.NewBuffReminderAPI(o)
    local api = { MAX_LEAD = o.maxLead, GetSettings = o.settings }
    o.api = api
    function api.SetEnabled(enabled)
        o.settings().enabled = enabled and true or false
        o.update()
    end
    function api.SetHideResting(hide)
        o.settings().hideResting = hide and true or false
        o.update()
    end
    -- true when seconds is a whole number from 0 to MAX_LEAD
    function api.SetLead(seconds)
        if not EspiUtils.IsWholeInRange(seconds, 0, o.maxLead) then
            return false
        end
        o.settings().lead = seconds
        o.update()
        return true
    end
    -- Shows the reminder for a few seconds; false when in combat or dead.
    function api.Preview()
        if not EspiUtils.CanPreviewReminder() then return false end
        return o.preview() ~= false
    end
    function api.ResetPosition()
        EspiUtils.Tiles.Reset(o.key)
    end
    function api.ResetDefaults()
        EspiUtils.ApplyDefaults(o.settings(), o.defaults, true)
        EspiUtils.Tiles.Lock()
        EspiUtils.Tiles.Reset(o.key)
        o.update()
    end
    return api
end

-- Slash command shared by Food and Rebuff. o as above (o.api is set by
-- NewBuffReminderAPI), plus o.command and o.statusExtra() (optional text appended to the status line).
function EspiUtils.HandleBuffReminderCommand(o, action, value)
    local api = o.api
    local settings = api.GetSettings()
    local Print = EspiUtils.Print
    if not settings then return end
    if action == "on" or action == "off" then
        api.SetEnabled(action == "on")
        Print(("%s reminders %s."):format(o.label, settings.enabled and "enabled" or "disabled"))
    elseif action == "lead" then
        local seconds = tonumber(value)
        if not api.SetLead(seconds) then
            Print(("Enter a whole number from 0 to %d. Use 0 for missing-buff reminders only."):format(o.maxLead))
            return
        end
        Print(seconds == 0 and "Missing-buff reminders only." or ("Expiry warning set to %d seconds."):format(seconds))
    elseif action == "move" then
        EspiUtils.ToggleTileMove()
    elseif action == "reset" then
        api.ResetPosition()
        Print("Reminder position reset.")
    elseif action == "test" then
        if not api.Preview() then
            Print("Preview available while alive and out of combat" .. (o.previewNote or "") .. ".")
        end
    elseif action == "" or action == "status" then
        Print(("%s reminders %s. Expiry warning: %s.%s"):format(
            o.label,
            settings.enabled and "enabled" or "disabled",
            settings.lead > 0 and ("%d seconds"):format(settings.lead) or "off",
            o.statusExtra and o.statusExtra() or ""
        ))
    else
        Print(("Use /espiutils %s [on | off | status | lead <seconds> | test | move | reset]."):format(o.command))
    end
end

-- Previews ignore the hide options but still wait for a calm moment.
function EspiUtils.CanPreviewReminder()
    return not InCombatLockdown() and not UnitIsDeadOrGhost("player")
end

function EspiUtils.Print(message)
    print("|cffefbd68Espi Utils|r " .. message)
end

-- A Print that tags each line with a colored module label.
function EspiUtils.Printer(label, color)
    local tag = ("|cff%s%s:|r "):format(color, label)
    return function(message)
        EspiUtils.Print(tag .. message)
    end
end

function EspiUtils.IsWholeInRange(value, min, max)
    return type(value) == "number" and value >= min and value <= max and value % 1 == 0
end

-- Fills keys missing from db; with overwrite, resets every key to its default.
function EspiUtils.ApplyDefaults(db, defaults, overwrite)
    for k, v in pairs(defaults) do
        if overwrite or db[k] == nil then db[k] = v end
    end
end
