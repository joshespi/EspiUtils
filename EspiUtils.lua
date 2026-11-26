local addonName, EspiUtils = ...
local Print = EspiUtils.Print

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
-- key -> why a legacy-replacing module is off: "legacy" (the old addon is enabled) or "error"
EspiUtils.offReason = {}

-- A failing feature must not stop the rest of the addon from loading. Returns whether init ran.
local function Start(title, init, ...)
    if xpcall(init, geterrorhandler(), ...) then return true end
    Print(("%s failed to start. See the error above."):format(title))
    return false
end

-- Why a legacy-replacing module is off, for chat and its options page.
function EspiUtils.ModuleOffText(key)
    if EspiUtils.offReason[key] == "error" then
        return "it failed to start. /reload, and report the error if it comes back."
    end
    return ("disable the old %s addon in the AddOns list and /reload."):format(LEGACY[key].addon)
end

local function PrintModuleOff(key)
    Print(("%s is off: %s"):format(LEGACY[key].title, EspiUtils.ModuleOffText(key)))
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
    EspiUtils.SubTable(store, "migrated")
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
        EspiUtils.offReason[key] = "legacy"
        PrintModuleOff(key)
        return
    end
    if Start(LEGACY[key].title, init, Migrate(key, store)) then
        EspiUtils.ready[key] = true
    else
        EspiUtils.offReason[key] = "error"
    end
end

-- Commands ----------------------------------------------------------------------

local function RunModule(key, message)
    if not EspiUtils.ready[key] then
        PrintModuleOff(key)
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
    Print("/espiutils food [on | off | status | lead <seconds> | test]")
    Print("/espiutils rebuff [on | off | status | lead <seconds> | test]")
    Print("/espiutils <posture|water|standup> [on | off | status | interval <minutes> | test]")
    Print("/espiutils move [reset] - move and resize the alert banner (shared by all characters)")
    Print("/espiutils bags [sort | stop | preview | on | off | log | debug | probe | help] - help lists the group toggles")
    Print("/espiutils quests [on | off | status | keepeasy | order [low | high]] - sort the quest tracker by level")
    Print("/espiutils keep [on | off | status | blocked | blocked clear]")
    Print("/espiutils mouseover [add | harm | del | list | sync] <spells>")
    Print("/espiutils boosh (or bewsh) " .. EspiUtils.Bewsh.Usage .. " - level-up notification")
    Print("/espiutils version")
end

local function GetVersion()
    local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    return get and get(addonName, "Version") or "unknown"
end

local function HandleMove(action)
    if action == "" then
        EspiUtils.Banner.ToggleMove()
    elseif action == "reset" then
        EspiUtils.Banner.ResetPosition()
    else
        Print("Use /espiutils move [reset].")
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
        EspiUtils.HandleFoodCommand(action, value)
    elseif command == "quests" or command == "quest" then
        EspiUtils.HandleQuestSortCommand(action, value)
    elseif command == "rebuff" then
        EspiUtils.HandleRebuffCommand(action, value)
    elseif command == "move" then
        HandleMove(action)
    elseif command == "bewsh" or command == "boosh" then
        EspiUtils.HandleBewshCommand(action, value)
    elseif command == "options" or command == "config" or command == "settings" then
        EspiUtils.OpenOptions()
    elseif command == "version" then
        Print("Version " .. GetVersion())
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

-- Loading ---------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, _, name)
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")
    EspiUtilsDB = EspiUtilsDB or {}
    EspiUtilsAccountDB = EspiUtilsAccountDB or {}
    local settings, account = EspiUtilsDB, EspiUtilsAccountDB

    EspiUtils.InitGeneral(EspiUtils.SubTable(account, "general"))
    EspiUtils.Banner.Init(account)
    Start("The food reminder", EspiUtils.InitializeFood, settings)
    Start("Timed reminders", EspiUtils.InitializeTimedReminders, settings)
    Start("Rebuff reminders", EspiUtils.InitializeRebuff, settings)

    InitModule("bags", EspiUtils.InitBagRules, account)
    InitModule("keep", EspiUtils.InitKeepBagsOpen, settings)
    Start("Quest sort", EspiUtils.InitializeQuestSort, settings)
    InitModule("mouseover", EspiUtils.InitMouseover, account)
    Start("Boosh", EspiUtils.InitializeBewsh, account)
    Start("The settings window", EspiUtils.InitializeOptions)
end)
