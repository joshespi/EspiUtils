local _, EspiUtils = ...

function EspiUtils.CreateReminder(titleText, iconPath)
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(300, 54)
    frame:SetFrameStrata("HIGH")
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
    return frame, detail
end

-- Tiles -------------------------------------------------------------------------
-- Every reminder is a tile. Position and scale are account-wide (EspiUtilsAccountDB.tiles):
-- { x, y } is the tile's center offset from the screen center in UIParent units.

local MIN_SCALE, MAX_SCALE, SCALE_STEP = 0.5, 2, 0.1
local MOVE_HINT = "Drag to move. Scroll to resize."
local tiles = {}   -- in registration order
local layout       -- set by InitTiles
local unlocked = false

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
        tile.frame:EnableMouse(on)
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
function EspiUtils.RegisterTile(key, frame, detail, default, refresh)
    local tile = { key = key, frame = frame, detail = detail, default = default, refresh = refresh }
    tiles[#tiles + 1] = tile
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:EnableMouse(false)
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
        if unlocked and button == "RightButton" then
            SetUnlocked(false)
            EspiUtils.Print("Reminders locked.")
        end
    end)
    frame:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
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

-- Reminders only show while alive and out of combat.
function EspiUtils.CanShowReminder()
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
