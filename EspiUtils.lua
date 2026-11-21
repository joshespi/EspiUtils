local addonName, EspiUtils = ...
local MAX_LEAD = 300
local FOOD_DEFAULTS = { enabled = true, hideResting = true, lead = 60 }
local Print = EspiUtils.Print

local events = CreateFrame("Frame")
local reminder, detail = EspiUtils.CreateReminder("Well Fed", "Interface\\Icons\\INV_Misc_Fork&Knife")
local Tiles = EspiUtils.Tiles

local settings
local timer
local auraPending = false

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
    if not EspiUtils.CanShowReminder() then
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

    local state, remaining = EspiUtils.GetFoodState()
    if state == "missing" then
        ShowReminder("Food buff missing")
        return
    end
    if not remaining then
        reminder:Hide()
        return
    end
    -- remaining is always > 0 here, so a lead of 0 never shows the countdown.
    local delay
    if remaining <= settings.lead then
        local seconds = math.ceil(remaining)
        ShowReminder(("Expires in %d:%02d"):format(math.floor(seconds / 60), seconds % 60))
        delay = remaining - seconds + 1
    else
        reminder:Hide()
        delay = remaining - settings.lead
    end
    timer = C_Timer.NewTimer(math.max(0.05, delay), UpdateReminder)
end

EspiUtils.RegisterTile("food", reminder, detail, { "CENTER", "CENTER", 0, 155 }, function()
    if settings then UpdateReminder() else reminder:Hide() end
end)

-- Food reminder API, shared by the slash command and the options screen.
EspiUtils.Food = {
    GetSettings = function() return settings end,
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
        Tiles.Reset("food")
    end,
    ResetDefaults = function()
        EspiUtils.ApplyDefaults(settings, FOOD_DEFAULTS, true)
        Tiles.Lock()
        EspiUtils.Food.ResetPosition()
        UpdateReminder()
    end,
}

-- Modules ---------------------------------------------------------------------

local function HasEntries(t)
    return next(t) ~= nil
end

local function HasSpells(t)
    for _, list in pairs(type(t.spells) == "table" and t.spells or {}) do
        if type(list) == "table" and #list > 0 then return true end
    end
    return false
end

-- Standalone addons this one replaced. Running both would double-hook the same
-- buttons and bag frames, so a module stays off while its old addon is enabled.
-- handler: the module's command handler (the TOC loads the modules before this file).
-- db: the old addon's saved variable; hasData: whether a module table holds real settings.
local LEGACY = {
    bags = { addon = "EspiBagRules", title = "Bag Rules", handler = EspiUtils.HandleBagsCommand,
        db = "EspiBagRulesDB", hasData = HasEntries },
    keep = { addon = "KeepBagsOpen", title = "Keep Bags Open", handler = EspiUtils.HandleKeepBagsCommand,
        db = "KeepBagsOpenDB", hasData = HasEntries },
    mouseover = { addon = "MouseoverMacros", title = "Mouseover Macros", handler = EspiUtils.HandleMouseoverCommand,
        db = "MouseoverMacrosDB", hasData = HasSpells },
}
EspiUtils.legacy = LEGACY
EspiUtils.ready = {}

local function PrintLegacyOff(key)
    local legacy = LEGACY[key]
    Print(("%s is off: disable the old %s addon and /reload."):format(legacy.title, legacy.addon))
end

local function LegacyEnabled(name)
    local ok, enabled = pcall(function()
        local C = C_AddOns
        if C and C.DoesAddOnExist and not C.DoesAddOnExist(name) then
            return false
        end
        if C and C.GetAddOnEnableState then
            return C.GetAddOnEnableState(name, UnitName("player")) > 0
        end
        return IsAddOnLoaded and IsAddOnLoaded(name) and true or false
    end)
    return ok and enabled
end

-- One-time copy of an old addon's saved variable into store[key]. WoW only loads
-- that variable while the old addon is loaded, or from this addon's own saved
-- file (the TOC lists it too) once both were loaded in an earlier session. So it
-- is retried on every load until there is something to copy or the module
-- already has its own settings.
local function Migrate(key, store)
    store.migrated = type(store.migrated) == "table" and store.migrated or {}
    local legacy = LEGACY[key]
    local current = store[key]
    if type(current) ~= "table" then
        current = nil
    end
    if not store.migrated[key] then
        local old = _G[legacy.db]
        if not (current and legacy.hasData(current)) and type(old) == "table" and next(old) ~= nil then
            current = CopyTable(old)
            Print(("%s: settings copied from %s."):format(legacy.title, legacy.addon))
        end
        if current and legacy.hasData(current) then
            store.migrated[key] = true
        end
    end
    store[key] = current or {}
    return store[key]
end

-- store[key] holds the module's settings. Nothing is created or copied while the
-- old addon is enabled: its saved data is only complete once it has run.
local function InitModule(key, init, store)
    if LegacyEnabled(LEGACY[key].addon) then
        PrintLegacyOff(key)
        return
    end
    local moduleDB = Migrate(key, store)
    -- A failing module must not stop the rest of the addon from loading.
    local ok = xpcall(init, geterrorhandler(), moduleDB)
    if not ok then
        Print(("%s failed to start. See the error above."):format(LEGACY[key].title))
        return
    end
    EspiUtils.ready[key] = true
end

-- Commands ----------------------------------------------------------------------

local function RunModule(key, message)
    if not EspiUtils.ready[key] then
        PrintLegacyOff(key)
        return
    end
    LEGACY[key].handler(message)
end

local MODULE_ALIASES = {
    bags = "bags", bag = "bags",
    keep = "keep", keepbags = "keep",
    mouseover = "mouseover", mo = "mouseover",
}

local function PrintHelp()
    Print("/espiutils (or /espi) options - open the settings")
    Print("/espiutils food [on | off | status | lead <seconds> | move | reset]")
    Print("/espiutils rebuff [on | off | status | lead <seconds> | move | reset]")
    Print("/espiutils <posture|water> [on | off | status | interval <minutes> | test]")
    Print("/espiutils move [reset] - move and resize the reminders (shared by all characters)")
    Print("/espiutils bags [sort | stop | preview | on | off | pin | log | debug | probe]")
    Print("/espiutils quests [on | off | status] - sort the quest tracker by level")
    Print("/espiutils keep [on | off | status | blocked | blocked clear]")
    Print("/espiutils mouseover [add | harm | del | list | sync] <spells>")
end

-- Prints the outcome; returns whether the tiles are now unlocked.
function EspiUtils.ToggleTileMove()
    local unlocked, refused = Tiles.Toggle()
    if refused then
        Print(refused)
    elseif unlocked then
        Print("Drag the reminders to move them, scroll over one to resize. Right-click one or use /espiutils move to lock.")
    else
        Print("Reminders locked.")
    end
    return unlocked
end

local function HandleMove(action)
    if action == "" then
        EspiUtils.ToggleTileMove()
    elseif action == "reset" then
        Tiles.Reset()
        Print("Reminder positions and sizes reset.")
    else
        Print("Use /espiutils move [reset].")
    end
end

local function HandleFood(action, value)
    local food = EspiUtils.Food
    if action == "on" or action == "off" then
        food.SetEnabled(action == "on")
        Print(settings.enabled and "Food reminders enabled." or "Food reminders disabled.")
    elseif action == "lead" then
        local seconds = tonumber(value)
        if not food.SetLead(seconds) then
            Print(("Enter a whole number from 0 to %d. Use 0 for missing-buff reminders only."):format(MAX_LEAD))
            return
        end
        Print(seconds == 0 and "Missing-buff reminders only." or ("Expiry warning set to %d seconds."):format(seconds))
    elseif action == "move" then
        EspiUtils.ToggleTileMove()
    elseif action == "reset" then
        food.ResetPosition()
        Print("Reminder position reset.")
    elseif action == "" or action == "status" then
        Print(("Food reminders %s. Expiry warning: %s."):format(
            settings.enabled and "enabled" or "disabled",
            settings.lead > 0 and ("%d seconds"):format(settings.lead) or "off"
        ))
    else
        Print("Use /espiutils to see the available commands.")
    end
end

SLASH_ESPIUTILS1 = "/espiutils"
SLASH_ESPIUTILS2 = "/espi"
SlashCmdList.ESPIUTILS = function(message)
    -- Only the command words are lowercased: spell links and names in `rest` keep their case.
    local command, rest = message:match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    local action, value = rest:match("^(%S*)%s*(.*)$")
    action = action:lower()

    if command == "food" then
        HandleFood(action, value)
    elseif command == "quests" or command == "quest" then
        EspiUtils.HandleQuestSortCommand(action)
    elseif command == "rebuff" then
        EspiUtils.HandleRebuffCommand(action, value)
    elseif command == "move" then
        HandleMove(action)
    elseif command == "options" or command == "config" or command == "settings" then
        EspiUtils.OpenOptions()
    elseif MODULE_ALIASES[command] then
        RunModule(MODULE_ALIASES[command], rest)
    elseif not EspiUtils.HandleTimedReminderCommand(command, action, value) then
        PrintHelp()
    end
end

-- Short commands from the standalone addons keep working.
SLASH_ESPIUTILS_BAGS1 = "/bagrules"
SLASH_ESPIUTILS_BAGS2 = "/brules"
SlashCmdList.ESPIUTILS_BAGS = function(m)
    RunModule("bags", m)
end
SLASH_ESPIUTILS_KEEP1 = "/keepbags"
SLASH_ESPIUTILS_KEEP2 = "/kbo"
SlashCmdList.ESPIUTILS_KEEP = function(m)
    RunModule("keep", m)
end
SLASH_ESPIUTILS_MO1 = "/momacro"
SLASH_ESPIUTILS_MO2 = "/mouseovermacros"
SlashCmdList.ESPIUTILS_MO = function(m)
    RunModule("mouseover", m)
end

-- Retail addon compartment menu (TOC: AddonCompartmentFunc*).
function EspiUtils_OnCompartmentClick()
    EspiUtils.OpenOptions()
end

function EspiUtils_OnCompartmentEnter(_, button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:AddLine("Espi Utils")
    GameTooltip:AddLine("Click to open the settings.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

function EspiUtils_OnCompartmentLeave()
    GameTooltip:Hide()
end

-- Events ------------------------------------------------------------------------

local function OnAurasSettled()
    auraPending = false
    UpdateReminder()
end

events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= addonName then
            return
        end
        self:UnregisterEvent("ADDON_LOADED")
        EspiUtilsDB = EspiUtilsDB or {}
        EspiUtilsAccountDB = EspiUtilsAccountDB or {}
        settings = EspiUtilsDB
        local account = EspiUtilsAccountDB

        -- hideResting now defaults to on; carry existing characters over once.
        if not settings.hideRestingMigrated then
            settings.hideRestingMigrated = true
            settings.hideResting = true
        end
        EspiUtils.ApplyDefaults(settings, FOOD_DEFAULTS)
        -- SavedVariables can be hand-edited or corrupt: fall back to defaults.
        if not EspiUtils.IsWholeInRange(settings.lead, 0, MAX_LEAD) then
            settings.lead = FOOD_DEFAULTS.lead
        end
        -- Tile positions used to be per character (Well Fed only): the first
        -- character to log in after the update carries its spot over.
        account.tiles = type(account.tiles) == "table" and account.tiles or {}
        if not account.tiles.food and type(settings.x) == "number" and type(settings.y) == "number" then
            account.tiles.food = { x = settings.x, y = settings.y }
        end
        settings.x, settings.y = nil, nil
        EspiUtils.InitTiles(account.tiles)
        EspiUtils.InitializeTimedReminders(settings)
        if not xpcall(EspiUtils.InitializeRebuff, geterrorhandler(), settings) then
            Print("Rebuff reminders failed to start. See the error above.")
        end

        InitModule("bags", EspiUtils.InitBagRules, account)
        InitModule("keep", EspiUtils.InitKeepBagsOpen, settings)
        xpcall(EspiUtils.InitializeQuestSort, geterrorhandler(), settings)
        InitModule("mouseover", EspiUtils.InitMouseover, account)
        xpcall(EspiUtils.InitializeOptions, geterrorhandler())

        self:RegisterUnitEvent("UNIT_AURA", "player")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("PLAYER_UPDATE_RESTING")
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterEvent("PLAYER_DEAD")
        self:RegisterEvent("PLAYER_ALIVE")
        self:RegisterEvent("PLAYER_UNGHOST")
        self:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
        self:RegisterEvent("SPELL_DATA_LOAD_RESULT")
        if C_Spell and C_Spell.RequestLoadSpellData then
            C_Spell.RequestLoadSpellData(EspiUtils.wellFedSpellID)
        end
        if IsPlayerInWorld() then
            UpdateReminder()
        end
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        -- This event can run just before the new restriction is enforced.
        reminder:Hide()
        C_Timer.After(0, UpdateReminder)
    elseif event == "SPELL_DATA_LOAD_RESULT" then
        -- Only the Well Fed name is needed, and only once.
        if ... == EspiUtils.wellFedSpellID then
            self:UnregisterEvent("SPELL_DATA_LOAD_RESULT")
            UpdateReminder()
        end
    elseif event == "UNIT_AURA" then
        -- Aura events arrive in bursts; update once after they settle.
        if not auraPending then
            auraPending = true
            C_Timer.After(0.2, OnAurasSettled)
        end
    else
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_DEAD" then
            Tiles.Lock()
        end
        EspiUtils.RefreshTimedReminders(event)
        if event == "PLAYER_REGEN_DISABLED" then
            -- InCombatLockdown() is still false during this event, so
            -- UpdateReminder would show the reminder as combat starts.
            CancelTimer()
            reminder:Hide()
        else
            UpdateReminder()
        end
    end
end)
