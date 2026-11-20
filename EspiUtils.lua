local addonName, EspiUtils = ...
local DEFAULT_LEAD = 60
local Print = EspiUtils.Print

local events = CreateFrame("Frame")
local reminder, detail = EspiUtils.CreateReminder("Well Fed", "Interface\\Icons\\INV_Misc_Fork&Knife")
reminder:SetMovable(true)

local settings
local timer
local moving = false

local function AnchorReminder()
    reminder:ClearAllPoints()
    reminder:SetPoint("CENTER", UIParent, "CENTER", settings.x or 0, settings.y or 155)
end

local function ShowReminder(message)
    detail:SetText(message)
    reminder:Show()
end

local UpdateReminder

local function OnTimer()
    timer = nil
    UpdateReminder()
end

function UpdateReminder()
    if timer then
        timer:Cancel()
        timer = nil
    end
    if InCombatLockdown() or UnitIsDeadOrGhost("player") then
        reminder:Hide()
        return
    end
    if moving then
        ShowReminder("Drag here. Repeat command to lock.")
        return
    end
    if not settings.enabled then
        reminder:Hide()
        return
    end

    local state, remaining = EspiUtils.GetFoodState()
    if state == "missing" then
        ShowReminder("Food buff missing")
    elseif remaining then
        local delay = remaining
        if settings.lead > 0 then
            if remaining <= settings.lead then
                local seconds = math.ceil(remaining)
                ShowReminder(("Expires in %d:%02d"):format(math.floor(seconds / 60), seconds % 60))
                delay = remaining - seconds + 1
            else
                reminder:Hide()
                delay = remaining - settings.lead
            end
        else
            reminder:Hide()
        end
        timer = C_Timer.NewTimer(math.max(0.05, delay), OnTimer)
    else
        reminder:Hide()
    end
end

reminder:RegisterForDrag("LeftButton")
reminder:EnableMouse(false)
reminder:SetScript("OnDragStart", function(self)
    if moving then
        self:StartMoving()
    end
end)
reminder:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local x, y = self:GetCenter()
    local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local parentX, parentY = UIParent:GetCenter()
    settings.x, settings.y = x * scale - parentX, y * scale - parentY
    AnchorReminder()
end)
reminder:SetScript("OnHide", function(self)
    self:StopMovingOrSizing()
end)

-- Food reminder API, shared by the slash command and the options screen.
EspiUtils.Food = {
    GetSettings = function() return settings end,
    IsMoving = function() return moving end,
    SetEnabled = function(enabled)
        settings.enabled = enabled and true or false
        UpdateReminder()
    end,
    -- true when seconds is a whole number from 0 to 300
    SetLead = function(seconds)
        if not seconds or seconds < 0 or seconds > 300 or seconds % 1 ~= 0 then
            return false
        end
        settings.lead = seconds
        UpdateReminder()
        return true
    end,
    ToggleMove = function()
        moving = not moving
        reminder:EnableMouse(moving)
        UpdateReminder()
        return moving
    end,
    ResetPosition = function()
        settings.x, settings.y = nil, nil
        AnchorReminder()
        UpdateReminder()
    end,
}

-- Modules ---------------------------------------------------------------------

-- Standalone addons this one replaced. Running both would double-hook the same
-- buttons and bag frames, so a module stays off while its old addon is enabled.
local LEGACY = {
    bags = { addon = "EspiBagRules", title = "Bag Rules" },
    keep = { addon = "KeepBagsOpen", title = "Keep Bags Open" },
    mouseover = { addon = "MouseoverMacros", title = "Mouseover Macros" },
}
EspiUtils.legacy = LEGACY
EspiUtils.ready = {}

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

local function InitModule(key, init, ...)
    local legacy = LEGACY[key]
    if LegacyEnabled(legacy.addon) then
        Print(("%s is off: disable the old %s addon."):format(legacy.title, legacy.addon))
        return
    end
    init(...)
    EspiUtils.ready[key] = true
end

-- One-time copy of the old addons' saved variables (the TOC still loads them).
local function Migrate(account, character)
    if EspiBagRulesDB and not account.bags then
        account.bags = CopyTable(EspiBagRulesDB)
    end
    if MouseoverMacrosDB and not account.mouseover then
        account.mouseover = CopyTable(MouseoverMacrosDB)
    end
    if KeepBagsOpenDB and not character.keep then
        character.keep = CopyTable(KeepBagsOpenDB)
    end
end

-- Commands ----------------------------------------------------------------------

-- Handlers are looked up by name at call time because the modules load after this file.
local MODULE_HANDLERS = {
    bags = "HandleBagsCommand",
    keep = "HandleKeepBagsCommand",
    mouseover = "HandleMouseoverCommand",
}

local function RunModule(key, message)
    if not EspiUtils.ready[key] then
        local legacy = LEGACY[key]
        Print(("%s is off: disable the old %s addon and /reload."):format(legacy.title, legacy.addon))
        return
    end
    EspiUtils[MODULE_HANDLERS[key]](message)
end

local MODULE_ALIASES = {
    bags = "bags", bag = "bags",
    keep = "keep", keepbags = "keep",
    mouseover = "mouseover", mo = "mouseover",
}

local function PrintHelp()
    Print("/espiutils options - open the settings")
    Print("/espiutils food [on | off | status | lead <seconds> | move | reset]")
    Print("/espiutils <posture|water> [on | off | status | interval <minutes> | test]")
    Print("/espiutils bags [sort | stop | preview | on | off | pin | log | debug | probe]")
    Print("/espiutils keep [on | off | status | blocked]")
    Print("/espiutils mouseover [add | harm | del | list | sync] <spells>")
end

local function HandleFood(action, value)
    local food = EspiUtils.Food
    if action == "on" or action == "off" then
        food.SetEnabled(action == "on")
        Print(settings.enabled and "Food reminders enabled." or "Food reminders disabled.")
    elseif action == "lead" then
        local seconds = tonumber(value)
        if not food.SetLead(seconds) then
            Print("Enter a whole number from 0 to 300. Use 0 for missing-buff reminders only.")
            return
        end
        Print(seconds == 0 and "Missing-buff reminders only." or ("Expiry warning set to %d seconds."):format(seconds))
    elseif action == "move" then
        local nowMoving = food.ToggleMove()
        Print(nowMoving and "Drag the reminder. Use /espiutils food move to finish." or "Reminder locked.")
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
    m = strtrim(m or ""):lower()
    if m == "config" or m == "options" then
        EspiUtils.OpenOptions("keep")
        return
    end
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
        Migrate(account, settings)

        if settings.enabled == nil then
            settings.enabled = true
        end
        settings.lead = settings.lead or DEFAULT_LEAD
        AnchorReminder()
        EspiUtils.InitializeTimedReminders(settings)

        account.bags = account.bags or {}
        account.mouseover = account.mouseover or {}
        settings.keep = settings.keep or {}
        InitModule("bags", EspiUtils.InitBagRules, account.bags)
        InitModule("keep", EspiUtils.InitKeepBagsOpen, settings.keep)
        InitModule("mouseover", EspiUtils.InitMouseover, account.mouseover)
        EspiUtils.InitializeOptions()

        self:RegisterUnitEvent("UNIT_AURA", "player")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterEvent("PLAYER_DEAD")
        self:RegisterEvent("PLAYER_ALIVE")
        self:RegisterEvent("PLAYER_UNGHOST")
        self:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
        self:RegisterEvent("SPELL_DATA_LOAD_RESULT")
        C_Spell.RequestLoadSpellData(EspiUtils.wellFedSpellID)
        if IsPlayerInWorld() then
            UpdateReminder()
        end
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        -- This event can run just before the new restriction is enforced.
        reminder:Hide()
        C_Timer.After(0, UpdateReminder)
    elseif event == "SPELL_DATA_LOAD_RESULT" then
        if ... == EspiUtils.wellFedSpellID then
            UpdateReminder()
        end
    else
        if event == "PLAYER_REGEN_DISABLED" and moving then
            moving = false
            reminder:EnableMouse(false)
        end
        if event ~= "UNIT_AURA" then
            EspiUtils.RefreshTimedReminders(event)
        end
        UpdateReminder()
    end
end)
