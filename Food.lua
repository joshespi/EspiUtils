local _, EspiUtils = ...

-- Food reminder: warns when Well Fed is missing or about to run out, as long as
-- the bags hold food that gives it.

local WELL_FED = 19705 -- Well Fed; matched by name, so every food version counts
local MAX_LEAD = 300
local FOOD_DEFAULTS = { enabled = true, hideResting = true, lead = 60 }

local issecretvalue = issecretvalue or function() return false end
local wellFedName -- localized; nil until the spell data has loaded

-- Fallbacks are the raw IDs (Consumable = 0, Food & Drink = 5) for clients without these enums.
local FOOD_CLASS = Enum.ItemClass and Enum.ItemClass.Consumable or 0
local FOOD_SUBCLASS = Enum.ItemConsumableSubclass and Enum.ItemConsumableSubclass.Fooddrink or 5
-- Last bag to scan: the reagent bag where it exists, else the last general bag.
local LAST_BAG = Enum.BagIndex and Enum.BagIndex.ReagentBag or NUM_BAG_FRAMES or 4
local hasFood -- cached bag scan; nil until needed, cleared when the bags change
-- itemID -> whether its tooltip mentions Well Fed. Kept across bag changes, so a
-- bag full of plain water is read once per session instead of on every loot.
local grantsByItem = {}

local function InvalidateFoodItems()
    hasFood = nil
end

-- Plain food and water only give the "eating" buff. Only items whose tooltip
-- mentions Well Fed can satisfy the reminder.
local function WellFedName()
    wellFedName = wellFedName or C_Spell.GetSpellName(WELL_FED)
    return wellFedName
end

-- Returns true/false, or nil (and a fallback guess) when the data has not loaded.
local function GrantsWellFed(bag, slot)
    if not (C_TooltipInfo and C_TooltipInfo.GetBagItem and wellFedName) then
        return nil, true -- cannot tell; fall back to any food
    end
    local data = C_TooltipInfo.GetBagItem(bag, slot)
    if not data or not data.lines then
        return nil, false -- tooltip not loaded yet
    end
    local needle = wellFedName:lower()
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if text and not issecretvalue(text) and text:lower():find(needle, 1, true) then
            return true
        end
    end
    return false
end

-- True when the bags hold anything that could give the Well Fed buff.
local function HasFoodItem()
    if hasFood ~= nil then
        return hasFood
    end
    local found, uncertain = false, false
    WellFedName()
    for bag = 0, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID then
                local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
                if classID == FOOD_CLASS and subClassID == FOOD_SUBCLASS then
                    local grants, guess = grantsByItem[itemID], nil
                    if grants == nil then
                        grants, guess = GrantsWellFed(bag, slot)
                        if grants ~= nil then grantsByItem[itemID] = grants end
                    end
                    if grants == nil then
                        uncertain = true
                        grants = guess
                    end
                    if grants then
                        found = true
                        break
                    end
                end
            end
        end
        if found then break end
    end
    -- only cache a certain answer; unloaded tooltip data gets re-checked next time
    if not uncertain then hasFood = found end
    return found
end

-- Return no state when the client cannot tell us whether Well Fed is active.
local function GetFoodState()
    -- Can't eat on a flight path.
    if UnitOnTaxi and UnitOnTaxi("player") then
        return
    end
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
        return
    end
    if not (C_Spell and C_Spell.GetSpellName and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then
        return
    end

    if not WellFedName() then
        return
    end

    -- Match the localized name so the different Well Fed spell IDs all count.
    local aura = C_UnitAuras.GetAuraDataBySpellName("player", wellFedName, "HELPFUL")
    if issecretvalue(aura) then
        return
    end
    if not aura then
        -- Nothing to eat: no reminder.
        if not HasFoodItem() then
            return
        end
        return "missing"
    end

    local expiration = aura.expirationTime
    if issecretvalue(expiration) then
        return
    end
    if not expiration or expiration == 0 then
        return "active"
    end

    local remaining = expiration - GetTime()
    if remaining <= 0 then
        return "missing"
    end
    return "active", remaining
end

-- Reminder ---------------------------------------------------------------------

local settings -- EspiUtilsDB (the food settings sit at its top level)
local timer
local auraPending = false

-- preview: ignore the hide options (the Preview button and /espiutils food test).
local function ShowReminder(message, preview)
    EspiUtils.Banner.Push({
        key = "food", title = "Well Fed", text = message, icon = "Interface\\Icons\\INV_Misc_Fork&Knife",
        preview = preview,
    })
end

local function HideReminder()
    EspiUtils.Banner.Dismiss("food")
end

local function CancelTimer()
    if timer then
        timer:Cancel()
        timer = nil
    end
end

-- While the banner can't show it (combat, hide options), skip the aura and bag scans
-- and the countdown; the banner's visibility listener runs this again once it can.
local function UpdateReminder()
    CancelTimer()
    if not settings.enabled or (settings.hideResting and IsResting()) or not EspiUtils.Banner.CanShow() then
        HideReminder()
        return
    end

    local state, remaining = GetFoodState()
    if state == "missing" then
        ShowReminder("Food buff missing")
        return
    end
    if not remaining then
        HideReminder()
        return
    end
    -- remaining is always > 0 here, so a lead of 0 never shows the countdown.
    local delay
    if remaining <= settings.lead then
        local text
        text, delay = EspiUtils.FormatCountdown(remaining)
        ShowReminder("Expires in " .. text)
    else
        HideReminder()
        delay = remaining - settings.lead
    end
    timer = C_Timer.NewTimer(math.max(0.05, delay), UpdateReminder)
end

-- Food reminder API, shared by the slash command and the options screen.
local foodOptions = {
    key = "food", command = "food", label = "Food",
    defaults = FOOD_DEFAULTS, maxLead = MAX_LEAD,
    settings = function() return settings end,
    update = UpdateReminder,
    preview = function()
        CancelTimer()
        ShowReminder("Preview", true)
        timer = C_Timer.NewTimer(5, UpdateReminder)
    end,
}
EspiUtils.Food = EspiUtils.NewBuffReminderAPI(foodOptions)

function EspiUtils.HandleFoodCommand(action, value)
    EspiUtils.HandleBuffReminderCommand(foodOptions, action, value)
end

-- Events -----------------------------------------------------------------------

local events = CreateFrame("Frame")

local function OnAurasSettled()
    auraPending = false
    UpdateReminder()
end

events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        -- This event can run just before the new restriction is enforced.
        HideReminder()
        C_Timer.After(0, UpdateReminder)
    elseif event == "SPELL_DATA_LOAD_RESULT" then
        -- Only the Well Fed name is needed, and only once.
        if arg1 == WELL_FED then
            self:UnregisterEvent("SPELL_DATA_LOAD_RESULT")
            UpdateReminder()
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        InvalidateFoodItems()
        if IsPlayerInWorld() then UpdateReminder() end
    elseif event == "UNIT_AURA" then
        -- Aura events arrive in bursts; update once after they settle.
        if not auraPending then
            auraPending = true
            C_Timer.After(0.2, OnAurasSettled)
        end
    else
        UpdateReminder()
    end
end)

-- PLAYER_FLAGS_CHANGED (AFK) only affects timed alerts: no rescan for it.
EspiUtils.Banner.OnVisibilityChanged(function(event)
    if settings and event ~= "PLAYER_FLAGS_CHANGED" and (event == "PLAYER_ENTERING_WORLD" or IsPlayerInWorld()) then
        UpdateReminder()
    end
end)

-- store: EspiUtilsDB. SavedVariables can be hand-edited or corrupt: fall back to defaults.
function EspiUtils.InitializeFood(store)
    settings = store
    -- hideResting now defaults to on; carry existing characters over once.
    if not settings.hideRestingMigrated then
        settings.hideRestingMigrated = true
        settings.hideResting = true
    end
    EspiUtils.ApplyDefaults(settings, FOOD_DEFAULTS)
    if not EspiUtils.IsWholeInRange(settings.lead, 0, MAX_LEAD) then
        settings.lead = FOOD_DEFAULTS.lead
    end
    settings.x, settings.y = nil, nil -- the food tile position from before the shared banner

    events:RegisterUnitEvent("UNIT_AURA", "player")
    -- PLAYER_ENTERING_WORLD and the other visibility events arrive through the banner's listener.
    for _, event in ipairs({ "PLAYER_UPDATE_RESTING", "ADDON_RESTRICTION_STATE_CHANGED",
        "SPELL_DATA_LOAD_RESULT", "BAG_UPDATE_DELAYED" }) do
        events:RegisterEvent(event)
    end
    -- Flight paths: GetFoodState stays quiet on a taxi. Not on every client.
    pcall(events.RegisterEvent, events, "PLAYER_CONTROL_LOST")
    pcall(events.RegisterEvent, events, "PLAYER_CONTROL_GAINED")
    if C_Spell and C_Spell.RequestLoadSpellData then
        C_Spell.RequestLoadSpellData(WELL_FED)
    end
    if IsPlayerInWorld() then UpdateReminder() end
end
