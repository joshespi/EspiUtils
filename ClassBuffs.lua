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
        { target = "self", ids = { 467 } },                         -- Thorns (often cast on the tank instead)
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

local IsSecret = EspiUtils.IsSecret

local DEFAULT_ICON = "Interface\\Icons\\Spell_Holy_WordFortitude"
local events = CreateFrame("Frame")
local settings
local buffs -- this class's entries; nil when the class has none
local timer
local pending = false
local rosterDirty = false
local inCombat = false -- PLAYER_REGEN_DISABLED fires before InCombatLockdown() is true
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
            if name then
                names[#names + 1] = name
                entry.iconId = entry.iconId or id
            end
        end
    end
    entry.names = names
    return names
end

local function ForgetNames()
    if not buffs then return end
    for _, entry in ipairs(buffs) do entry.names, entry.iconId = nil, nil end
end

-- The first matching aura on unit, or nil. A second return of true means the
-- client would not tell us (secret values).
local function FindAura(unit, names, filter)
    for _, name in ipairs(names) do
        local aura = C_UnitAuras.GetAuraDataBySpellName(unit, name, filter)
        if IsSecret(aura) then return nil, true end
        if aura then return aura end
    end
end

-- Returns state, entry, unit, remaining, nextCheck. state is "missing" for a buff that has
-- gone or "expiring" for the one with the least time left (remaining) within lead; entry
-- is that buff and unit the one it is on or missing from. nextCheck is how long until the
-- next buff comes within lead, so no polling is needed. state is nil when all is well or
-- the client won't say.
local function GetRebuffState(lead)
    if EspiUtils.AurasSecret() then return end

    local reachable
    local bestRemaining, nextCheck, bestEntry, bestUnit
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
                    if IsSecret(expiration) then return end
                    local remaining = (expiration or 0) > 0 and expiration - GetTime() or 0
                    if remaining > lead then
                        local wait = remaining - lead
                        if not nextCheck or wait < nextCheck then nextCheck = wait end
                    elseif remaining > 0 and (not bestRemaining or remaining < bestRemaining) then
                        bestRemaining, bestEntry, bestUnit = remaining, entry, unit
                    end
                elseif not entry.mine then
                    return "missing", entry, unit
                end
            end
        end
    end
    if bestEntry then return "expiring", bestEntry, bestUnit, bestRemaining, nextCheck end
    return nil, nil, nil, nil, nextCheck
end

-- Display ------------------------------------------------------------------------

-- " on <name>" for a group member, "" for you or when the client hides the name.
local function OnWhom(unit)
    if not unit or UnitIsUnit(unit, "player") then return "" end
    local name = UnitName(unit)
    if not name or IsSecret(name) then return "" end
    return " on " .. name
end

-- entry: the buff being shown, whose spell icon replaces the default one.
-- preview: ignore the hide options (the Preview button and /espiutils rebuff test).
local function ShowReminder(message, entry, preview)
    local texture = entry and entry.iconId and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(entry.iconId)
    EspiUtils.Banner.Push({
        key = "rebuff", title = "Rebuff", text = message, icon = texture or DEFAULT_ICON, preview = preview,
    })
end

local function HideReminder()
    EspiUtils.Banner.Dismiss("rebuff")
end

local function CancelTimer()
    if timer then
        timer:Cancel()
        timer = nil
    end
end

-- UNIT_AURA only matters while the reminder is on and out of combat. Solo and in a party it
-- is registered for the player and party units only; a raid needs the global event, filtered
-- by groupSet. auraMode: "party", "raid" or nil (not registered).
local AURA_UNITS = { { "player", "party1" }, { "party2", "party3" }, { "party4" } }
local auraFrames = {}
local auraMode

local function TrackAuras()
    local mode = settings.enabled and not inCombat and (IsInRaid and IsInRaid() and "raid" or "party") or nil
    if mode == auraMode then return end
    auraMode = mode
    if mode == "raid" then events:RegisterEvent("UNIT_AURA") else events:UnregisterEvent("UNIT_AURA") end
    for i, frame in ipairs(auraFrames) do
        if mode == "party" then
            frame:RegisterUnitEvent("UNIT_AURA", unpack(AURA_UNITS[i]))
        else
            frame:UnregisterEvent("UNIT_AURA")
        end
    end
end

local function UpdateReminder()
    CancelTimer()
    if not buffs then
        HideReminder()
        return
    end
    TrackAuras() -- follows SetEnabled
    -- While the banner can't show it (combat, hide options), skip the group aura scan and
    -- the countdown; the banner's visibility listener runs this again once it can.
    if not settings.enabled or (settings.hideResting and IsResting()) or not EspiUtils.Banner.CanShow() then
        HideReminder()
        return
    end

    local state, entry, unit, remaining, nextCheck = GetRebuffState(settings.lead)
    local name = entry and entry.names[1]
    local delay = nextCheck
    if state == "missing" then
        ShowReminder(("%s missing%s"):format(name, OnWhom(unit)), entry)
    elseif state == "expiring" then
        local text
        text, delay = EspiUtils.FormatCountdown(remaining) -- ticks once a second
        ShowReminder(("%s%s expires in %s"):format(name, OnWhom(unit), text), entry)
    else
        HideReminder()
    end
    -- Aura and roster events cover every other change.
    if delay then
        timer = C_Timer.NewTimer(math.max(0.05, delay), UpdateReminder)
    end
end

-- API, shared by the slash command and the options screen ---------------------------

local rebuffOptions = {
    key = "rebuff", command = "rebuff", label = "Rebuff",
    defaults = DEFAULTS, maxLead = MAX_LEAD,
    settings = function() return settings end,
    update = UpdateReminder,
    previewNote = ", for classes with tracked buffs",
    statusExtra = function() return buffs and "" or " No buffs are tracked for this class." end,
    preview = function()
        if not buffs then return false end
        CancelTimer()
        ShowReminder("Preview", nil, true)
        timer = C_Timer.NewTimer(5, UpdateReminder)
    end,
}
EspiUtils.Rebuff = EspiUtils.NewBuffReminderAPI(rebuffOptions)
EspiUtils.Rebuff.HasBuffs = function() return buffs ~= nil end

function EspiUtils.HandleRebuffCommand(action, value)
    EspiUtils.HandleBuffReminderCommand(rebuffOptions, action, value)
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

-- SPELL_DATA_LOAD_RESULT fires for every spell any addon loads: listen only while one of
-- ours still has no name.
local function WatchSpellData()
    for id in pairs(trackedIds) do
        if not C_Spell.GetSpellName(id) then
            events:RegisterEvent("SPELL_DATA_LOAD_RESULT")
            return
        end
    end
    events:UnregisterEvent("SPELL_DATA_LOAD_RESULT")
end

-- Rescan only when the banner's answer changed (combat, death, mounting with "Hide while
-- mounted", ...) or on entering the world; aura, roster and resting events cover the rest.
local couldShow
EspiUtils.Banner.OnVisibilityChanged(function(event)
    if not buffs then return end
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    end
    TrackAuras() -- nothing shows in combat, so auras aren't tracked then
    local canShow = EspiUtils.Banner.CanShow()
    if event == "PLAYER_ENTERING_WORLD" or (canShow ~= couldShow and IsPlayerInWorld()) then
        couldShow = canShow
        UpdateReminder()
    end
end)

local function OnAura(_, _, unit)
    -- Only the player and group members matter; in a raid the rest of the world is noise.
    if groupSet[unit] then Schedule() end
end

-- store: the character settings table (EspiUtilsDB).
function EspiUtils.InitializeRebuff(store)
    settings = EspiUtils.SubTable(store, "rebuff")
    EspiUtils.ApplyDefaults(settings, DEFAULTS)
    if not EspiUtils.IsWholeInRange(settings.lead, 0, MAX_LEAD) then
        settings.lead = DEFAULTS.lead
    end

    buffs = CLASS_BUFFS[EspiUtils.PlayerClass]
    -- Without these APIs the state can never be read.
    if not (buffs and C_Spell and C_Spell.GetSpellName and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then
        buffs = nil
        return
    end

    for i = 1, #AURA_UNITS do
        auraFrames[i] = CreateFrame("Frame")
        auraFrames[i]:SetScript("OnEvent", OnAura)
    end
    inCombat = InCombatLockdown()
    RebuildGroup()
    TrackSpells()
    WatchSpellData()
    TrackAuras()
    events:RegisterEvent("GROUP_ROSTER_UPDATE")
    events:RegisterEvent("SPELLS_CHANGED")
    events:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    -- Entering the world, death, combat and the other visibility changes arrive through
    -- the banner's listener.
    events:RegisterEvent("PLAYER_UPDATE_RESTING")
    if IsPlayerInWorld() then UpdateReminder() end
end

events:SetScript("OnEvent", function(self, event, unit)
    if event == "UNIT_AURA" then
        OnAura(self, event, unit)
    elseif event == "GROUP_ROSTER_UPDATE" then
        rosterDirty = true
        Schedule()
    elseif event == "SPELLS_CHANGED" then
        ForgetNames()
        WatchSpellData()
        Schedule()
    elseif event == "SPELL_DATA_LOAD_RESULT" then
        -- unit is the spell ID here
        if trackedIds[unit] then
            ForgetNames()
            WatchSpellData()
            Schedule()
        end
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        HideReminder()
        C_Timer.After(0, UpdateReminder)
    elseif event == "PLAYER_UPDATE_RESTING" then
        UpdateReminder()
    end
end)
