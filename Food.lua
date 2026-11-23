local _, EspiUtils = ...

local WELL_FED = 19705
EspiUtils.wellFedSpellID = WELL_FED

local issecretvalue = issecretvalue or function() return false end
local wellFedName -- localized; nil until the spell data has loaded

local FOOD_CLASS = Enum.ItemClass.Consumable
local FOOD_SUBCLASS = Enum.ItemConsumableSubclass.Fooddrink
local hasFood -- cached bag scan; nil until needed, cleared when the bags change

function EspiUtils.InvalidateFoodItems()
    hasFood = nil
end

-- True when the bags hold anything that could give a food buff.
local function HasFoodItem()
    if hasFood == nil then
        hasFood = false
        for bag = 0, Enum.BagIndex.ReagentBag do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local itemID = C_Container.GetContainerItemID(bag, slot)
                if itemID then
                    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
                    if classID == FOOD_CLASS and subClassID == FOOD_SUBCLASS then
                        hasFood = true
                        break
                    end
                end
            end
            if hasFood then break end
        end
    end
    return hasFood
end

-- Return no state when the client cannot tell us whether Well Fed is active.
function EspiUtils.GetFoodState()
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

    wellFedName = wellFedName or C_Spell.GetSpellName(WELL_FED)
    if not wellFedName then
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
