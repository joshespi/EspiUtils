local _, EspiUtils = ...

-- Class rebuff reminder: warns when a buff your class maintains is missing or
-- about to run out. Buffs are matched by localized name, so every rank counts.

local MAX_LEAD = 600
local DEFAULTS = { enabled = true, hideResting = true, lead = 120 }

-- Each entry is one buff; ids lists the spells that all count as it (the base
-- spell plus its group version).
-- target "self": only the player is checked.
-- target "group": the player and nearby group members; a missing buff is reported.
-- manaOnly: group members without a mana bar (warriors, rogues) are not checked.
-- mine: only auras you cast are watched, and only an expiring one is reported (a
--       Paladin blessing you gave). Nothing is reported once it has gone.
-- Spell IDs are rank 1 / the base spell; verify them on the client in use.
local CLASS_BUFFS = {
    PRIEST = {
        { target = "group", ids = { 1243, 21562 } },               -- Power Word: Fortitude, Prayer of Fortitude
        { target = "self", ids = { 588 } },                         -- Inner Fire
    },
    MAGE = {
        { target = "group", manaOnly = true, ids = { 1459, 23028 } }, -- Arcane Intellect, Arcane Brilliance
        { target = "self", ids = { 168, 7302, 6117 } },            -- Frost Armor, Ice Armor, Mage Armor
    },
    DRUID = {
        { target = "group", ids = { 1126, 21849 } },               -- Mark of the Wild, Gift of the Wild
        { target = "group", ids = { 467 } },                        -- Thorns
    },
    WARRIOR = {
        { target = "self", ids = { 6673 } },                        -- Battle Shout
    },
    PALADIN = {
        { target = "group", mine = true, ids = { 19740, 25782 } }, -- Blessing of Might, Greater
        { target = "group", mine = true, ids = { 19742, 25894 } }, -- Blessing of Wisdom, Greater
        { target = "group", mine = true, ids = { 20217, 25898 } }, -- Blessing of Kings, Greater
        { target = "group", mine = true, ids = { 1038, 25895 } },  -- Blessing of Salvation, Greater
        { target = "group", mine = true, ids = { 20911, 25899 } }, -- Blessing of Sanctuary, Greater
    },
}

local CLASS = UnitClassBase and UnitClassBase("player") or select(2, UnitClass("player"))
local issecretvalue = issecretvalue or function() return false end
local Print = EspiUtils.Print
local Tiles = EspiUtils.Tiles

local reminder, detail = EspiUtils.CreateReminder("Rebuff", "Interface\\Icons\\Spell_Holy_WordFortitude")
local events = CreateFrame("Frame")
local settings
local buffs -- this class's entries; nil when the class has none
local timer
local pending = false
local rosterDirty = false
local trackedIds = {} -- spell IDs of this class's buffs

-- Group ----------------------------------------------------------------------------

local PLAYER_ONLY = { "player" }
local RAID_UNITS, PARTY_UNITS = {}, {}
for i = 1, 40 do RAID_UNITS[i] = "raid" .. i end
for i = 1, 4 do PARTY_UNITS[i] = "party" .. i end

local groupUnits = PLAYER_ONLY -- the player plus group members, rebuilt on roster changes
local groupSet = { player = true }

local function RebuildGroup()
    local units = { "player" }
    if IsInRaid and IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = RAID_UNITS[i]
            if unit and UnitExists(unit) and not UnitIsUnit(unit, "player") then
                units[#units + 1] = unit
            end
        end
    elseif IsInGroup and IsInGroup() then
        for _, unit in ipairs(PARTY_UNITS) do
            if UnitExists(unit) then units[#units + 1] = unit end
        end
    end
    groupUnits = units
    groupSet = {}
    for _, unit in ipairs(units) do groupSet[unit] = true end
end

-- Group members we can expect to buff: connected, alive, near enough to be seen.
local function Reachable(unit)
    if unit == "player" then return true end
    if not (UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) and UnitIsVisible(unit)) then
        return false
    end
    if UnitInRange then
        local inRange, checked = UnitInRange(unit)
        if checked and not inRange then return false end
    end
    return true
end

local function ManaUnits(list)
    local units = {}
    for _, unit in ipairs(list) do
        if UnitPowerType(unit) == 0 then units[#units + 1] = unit end
    end
    return units
end

local function ReachableUnits()
    local units = {}
    for _, unit in ipairs(groupUnits) do
        if Reachable(unit) then units[#units + 1] = unit end
    end
    return units
end

-- Buffs ------------------------------------------------------------------------

local function Known(id)
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if IsSpellKnown and IsSpellKnown(id) then return true end
    return false
end

-- Localized names for every spell ID of an entry that the player knows. Cached
-- until the spellbook or spell data changes.
local function EntryNames(entry)
    if entry.names then return entry.names end
    local names = {}
    for _, id in ipairs(entry.ids) do
        if Known(id) then
            local name = C_Spell.GetSpellName(id)
            if name then names[#names + 1] = name end
        end
    end
    entry.names = names
    return names
end

local function ForgetNames()
    if not buffs then return end
    for _, entry in ipairs(buffs) do entry.names = nil end
end

-- The first matching aura on unit, or nil. A second return of true means the
-- client would not tell us (secret values).
local function FindAura(unit, names, filter)
    for _, name in ipairs(names) do
        local aura = C_UnitAuras.GetAuraDataBySpellName(unit, name, filter)
        if issecretvalue(aura) then return nil, true end
        if aura then return aura end
    end
end

-- Returns name, "missing" for a buff that has gone, or name, "expiring", remaining
-- for the one with the least time left within lead. The last return is how long
-- until the next buff will come within lead, so no polling is needed. Nothing is
-- returned for name and state when all is well or the client won't say.
local function GetRebuffState(lead)
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then return end

    local reachable
    local bestName, bestRemaining, nextCheck
    for _, entry in ipairs(buffs) do
        local names = EntryNames(entry)
        -- An entry whose spells the player doesn't know has no names: nothing to scan.
        if #names > 0 then
            local units = PLAYER_ONLY
            if entry.target == "group" then
                reachable = reachable or ReachableUnits()
                units = entry.manaOnly and ManaUnits(reachable) or reachable
            end
            local filter = entry.mine and "HELPFUL|PLAYER" or "HELPFUL"
            for _, unit in ipairs(units) do
                local aura, secret = FindAura(unit, names, filter)
                if secret then return end
                if aura then
                    local expiration = aura.expirationTime
                    if issecretvalue(expiration) then return end
                    local remaining = (expiration or 0) > 0 and expiration - GetTime() or 0
                    if remaining > lead then
                        local wait = remaining - lead
                        if not nextCheck or wait < nextCheck then nextCheck = wait end
                    elseif remaining > 0 and (not bestRemaining or remaining < bestRemaining) then
                        bestName, bestRemaining = names[1], remaining
                    end
                elseif not entry.mine then
                    return names[1], "missing"
                end
            end
        end
    end
    if bestName then return bestName, "expiring", bestRemaining, nextCheck end
    return nil, nil, nil, nextCheck
end

-- Display ------------------------------------------------------------------------

local function ShowReminder(message)
    detail:SetText(message)
    reminder:Show()
end

local function CancelTimer()
    if timer then
        timer:Cancel()
        timer = nil
    end
end

local function UpdateReminder()
    CancelTimer()
    -- A class with no tracked buffs never shows a tile, not even while moving tiles.
    if not buffs or not EspiUtils.CanShowReminder() then
        reminder:Hide()
        return
    end
    if Tiles.IsUnlocked() then
        ShowReminder(Tiles.MOVE_HINT)
        return
    end
    if not settings.enabled or (settings.hideResting and IsResting()) then
        reminder:Hide()
        return
    end

    local name, state, remaining, nextCheck = GetRebuffState(settings.lead)
    local delay = nextCheck
    if state == "missing" then
        ShowReminder(("%s missing"):format(name))
    elseif state == "expiring" then
        local seconds = math.ceil(remaining)
        ShowReminder(("%s expires in %d:%02d"):format(name, math.floor(seconds / 60), seconds % 60))
        delay = remaining - seconds + 1 -- tick once a second for the countdown
    else
        reminder:Hide()
    end
    -- Aura and roster events cover every other change.
    if delay then
        timer = C_Timer.NewTimer(math.max(0.05, delay), UpdateReminder)
    end
end

-- Only classes with buffs get a tile: move mode shows every registered tile.
if CLASS_BUFFS[CLASS] then
    EspiUtils.RegisterTile("rebuff", reminder, detail, { "CENTER", "CENTER", 0, 215 }, UpdateReminder)
end

-- API, shared by the slash command and the options screen ---------------------------

EspiUtils.Rebuff = {
    GetSettings = function() return settings end,
    HasBuffs = function() return buffs ~= nil end,
    SetEnabled = function(enabled)
        settings.enabled = enabled and true or false
        UpdateReminder()
    end,
    SetHideResting = function(hide)
        settings.hideResting = hide and true or false
        UpdateReminder()
    end,
    MAX_LEAD = MAX_LEAD,
    -- true when seconds is a whole number from 0 to MAX_LEAD
    SetLead = function(seconds)
        if not EspiUtils.IsWholeInRange(seconds, 0, MAX_LEAD) then
            return false
        end
        settings.lead = seconds
        UpdateReminder()
        return true
    end,
    ResetPosition = function()
        Tiles.Reset("rebuff")
    end,
    ResetDefaults = function()
        EspiUtils.ApplyDefaults(settings, DEFAULTS, true)
        Tiles.Lock()
        Tiles.Reset("rebuff")
        UpdateReminder()
    end,
}

function EspiUtils.HandleRebuffCommand(action, value)
    local rebuff = EspiUtils.Rebuff
    if not settings then return end
    if action == "on" or action == "off" then
        rebuff.SetEnabled(action == "on")
        Print(settings.enabled and "Rebuff reminders enabled." or "Rebuff reminders disabled.")
    elseif action == "lead" then
        local seconds = tonumber(value)
        if not rebuff.SetLead(seconds) then
            Print(("Enter a whole number from 0 to %d. Use 0 for missing-buff reminders only."):format(MAX_LEAD))
            return
        end
        Print(seconds == 0 and "Missing-buff reminders only." or ("Expiry warning set to %d seconds."):format(seconds))
    elseif action == "move" then
        EspiUtils.ToggleTileMove()
    elseif action == "reset" then
        rebuff.ResetPosition()
        Print("Reminder position reset.")
    elseif action == "" or action == "status" then
        Print(("Rebuff reminders %s. Expiry warning: %s.%s"):format(
            settings.enabled and "enabled" or "disabled",
            settings.lead > 0 and ("%d seconds"):format(settings.lead) or "off",
            buffs and "" or " No buffs are tracked for this class."
        ))
    else
        Print("Use /espiutils rebuff [on | off | status | lead <seconds> | move | reset].")
    end
end

-- Events -------------------------------------------------------------------------

local function OnSettled()
    pending = false
    -- Roster events come in bursts: rebuild the group once, here.
    if rosterDirty then
        rosterDirty = false
        RebuildGroup()
    end
    UpdateReminder()
end

-- Event bursts update once after they settle.
local function Schedule()
    if not pending then
        pending = true
        C_Timer.After(0.2, OnSettled)
    end
end

-- Remembers this class's spell IDs and asks the client to load their names.
local function TrackSpells()
    for _, entry in ipairs(buffs) do
        for _, id in ipairs(entry.ids) do
            trackedIds[id] = true
            if C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(id) end
        end
    end
end

local UPDATE_EVENTS = {
    "PLAYER_ENTERING_WORLD", "PLAYER_UPDATE_RESTING", "PLAYER_REGEN_ENABLED",
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
}

-- store: the character settings table (EspiUtilsDB).
function EspiUtils.InitializeRebuff(store)
    store.rebuff = type(store.rebuff) == "table" and store.rebuff or {}
    settings = store.rebuff
    EspiUtils.ApplyDefaults(settings, DEFAULTS)
    if not EspiUtils.IsWholeInRange(settings.lead, 0, MAX_LEAD) then
        settings.lead = DEFAULTS.lead
    end

    buffs = CLASS_BUFFS[CLASS]
    -- Without these APIs the state can never be read (Food.lua guards the same ones).
    if not (buffs and C_Spell and C_Spell.GetSpellName and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then
        buffs = nil
        return
    end

    RebuildGroup()
    TrackSpells()
    if not InCombatLockdown() then events:RegisterEvent("UNIT_AURA") end
    events:RegisterEvent("GROUP_ROSTER_UPDATE")
    events:RegisterEvent("SPELLS_CHANGED")
    events:RegisterEvent("SPELL_DATA_LOAD_RESULT")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    for _, event in ipairs(UPDATE_EVENTS) do events:RegisterEvent(event) end
    if IsPlayerInWorld() then UpdateReminder() end
end

events:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" then
        -- Only the player and group members matter; the rest of the world is noise.
        if settings.enabled and groupSet[unit] then Schedule() end
    elseif event == "GROUP_ROSTER_UPDATE" then
        rosterDirty = true
        Schedule()
    elseif event == "SPELLS_CHANGED" then
        ForgetNames()
        Schedule()
    elseif event == "SPELL_DATA_LOAD_RESULT" then
        -- Fires for every spell any addon loads; only ours matter (unit is the spell ID).
        if trackedIds[unit] then
            ForgetNames()
            Schedule()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Nothing shows in combat, so skip the aura events until it ends.
        events:UnregisterEvent("UNIT_AURA")
        -- InCombatLockdown() is still false during this event.
        CancelTimer()
        reminder:Hide()
    elseif event == "PLAYER_REGEN_ENABLED" then
        events:RegisterEvent("UNIT_AURA")
        UpdateReminder()
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        reminder:Hide()
        C_Timer.After(0, UpdateReminder)
    else
        UpdateReminder()
    end
end)
