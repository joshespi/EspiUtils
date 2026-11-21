local _, EspiUtils = ...

local WELL_FED = 19705
EspiUtils.wellFedSpellID = WELL_FED

-- Return no state when the client cannot tell us whether Well Fed is active.
function EspiUtils.GetFoodState()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
        return
    end
    local issecretvalue = issecretvalue or function() return false end
    if not (C_Spell and C_Spell.GetSpellName and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then
        return
    end

    local name = C_Spell.GetSpellName(WELL_FED)
    if not name then
        return
    end

    -- Match the localized name so the different Well Fed spell IDs all count.
    local aura = C_UnitAuras.GetAuraDataBySpellName("player", name, "HELPFUL")
    if issecretvalue(aura) then
        return
    end
    if not aura then
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
