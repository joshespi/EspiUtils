-- Spell lists are account-wide per class; macros are per-character.

local _, EspiUtils = ...

local PREFIX = "MO "
local COND = {
    help = "[@mouseover,help,nodead][]",
    harm = "[@mouseover,harm,nodead][]",
}
local LABEL = { help = "friendly", harm = "hostile" }
local KIND = { add = "help", harm = "harm" }

local spells -- this class's list, set at login
local pending = false

local function say(msg)
    EspiUtils.Print("|cff33ccffMouseover:|r " .. msg)
end

-- Macro names cap at 16 bytes; back off so a multi-byte character isn't cut in half.
local function macroName(spell)
    local s, n = PREFIX .. spell, 16
    local b = s:byte(n + 1)
    while b and b >= 0x80 and b < 0xC0 do
        n = n - 1
        b = s:byte(n + 1)
    end
    return s:sub(1, n)
end

local function macroBody(spell, kind)
    return ("#showtooltip %s\n/cast %s %s"):format(spell, COND[kind], spell)
end

-- Returns the entry matching spell (case-insensitive), or, as a third value, the
-- name of another entry whose truncated macro name collides with spell's.
local function find(spell)
    local lower, name = spell:lower(), macroName(spell)
    local clash
    for i, e in ipairs(spells) do
        if e.name:lower() == lower then
            return i, e
        end
        if not clash and macroName(e.name) == name then
            clash = e.name
        end
    end
    return nil, nil, clash
end

-- Character macro index for name, 0 if none, nil if an account macro holds the name.
local function macroIndex(name)
    local idx = GetMacroIndexByName(name)
    local maxAccount = Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_ACCOUNT_MACROS or 120
    if idx > 0 and idx <= maxAccount then
        return nil
    end
    return idx
end

local function sync()
    if InCombatLockdown() then
        pending = true
        return false
    end
    pending = false

    local made, updated = 0, 0
    local _, numChar = GetNumMacros()
    local maxChar = Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_CHARACTER_MACROS or 18
    for _, e in ipairs(spells) do
        local name, body = macroName(e.name), macroBody(e.name, e.kind)
        local idx = macroIndex(name)
        if not idx then
            say("account macro already named " .. name .. ", skipped: " .. e.name)
        elseif idx == 0 then
            if numChar >= maxChar then
                say("character macro slots full, skipped: " .. e.name)
            else
                CreateMacro(name, "INV_Misc_QuestionMark", body, true)
                numChar = numChar + 1
                made = made + 1
            end
        elseif strtrim(GetMacroBody(idx) or "") ~= body then
            EditMacro(idx, name, nil, body)
            updated = updated + 1
        end
    end

    if made + updated > 0 then
        say(("macros synced: %d created, %d updated"):format(made, updated))
    end
    return true
end

local function requestSync()
    if not sync() then
        say("in combat, macros sync when it ends")
    end
end

local function parseSpell(arg)
    local id = arg:match("|Hspell:(%d+)")
    if id then
        return C_Spell.GetSpellName(tonumber(id))
    end
    arg = strtrim(arg)
    return arg ~= "" and arg or nil
end

local function add(cmd, list)
    local kind = KIND[cmd]
    local parsed, changed = false, false
    for piece in list:gmatch("[^,]+") do
        local spell = parseSpell(piece)
        if spell then
            parsed = true
            local _, existing, clash = find(spell)
            if clash then
                say(spell .. ": macro name same as " .. clash .. " after truncation, skipped")
            else
                if existing then
                    existing.kind = kind
                else
                    table.insert(spells, { name = spell, kind = kind })
                end
                if not C_Spell.GetSpellInfo(spell) then
                    say(spell .. ": not in your spellbook (other spec?), saved anyway")
                end
                changed = true
            end
        end
    end
    if not parsed then
        say("usage: /espiutils mouseover " .. cmd .. " Spell One, Spell Two")
    elseif changed then
        requestSync()
    end
end

local function remove(list)
    if InCombatLockdown() then
        say("can't delete macros in combat")
        return
    end
    for piece in list:gmatch("[^,]+") do
        local spell = parseSpell(piece)
        local i = spell and find(spell)
        if i then
            local e = table.remove(spells, i)
            local idx = macroIndex(macroName(e.name))
            if idx and idx > 0 then
                DeleteMacro(idx)
            end
            say("removed " .. e.name)
        else
            say("not in list: " .. (spell or piece))
        end
    end
    sync() -- restores any macro shared with a removed entry (lists saved before the clash check)
end

local function list()
    if #spells == 0 then
        say("empty. /espiutils mouseover add Spell One, Spell Two")
        return
    end
    for _, e in ipairs(spells) do
        say(("%s (%s)"):format(e.name, LABEL[e.kind]))
    end
end

local function help()
    say("/espiutils mouseover add Spell, Spell - friendly mouseover, falls back to target")
    say("/espiutils mouseover harm Spell, Spell - hostile mouseover, falls back to target")
    say("/espiutils mouseover del Spell, Spell - remove from list and delete macro")
    say("/espiutils mouseover list - show this class's list")
    say("/espiutils mouseover sync - force a sync")
    say("Shift-click spells from the spellbook to insert them.")
end

function EspiUtils.HandleMouseoverCommand(msg)
    if not spells then
        say("not ready yet, try again after login finishes")
        return
    end
    local cmd, rest = msg:match("^(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if KIND[cmd] then
        add(cmd, rest)
    elseif cmd == "del" or cmd == "remove" then
        remove(rest)
    elseif cmd == "list" then
        list()
    elseif cmd == "sync" then
        requestSync()
    else
        help()
    end
end

-- Used by the options screen. Each returns nothing; they report through chat.
EspiUtils.Mouseover = {
    Add = function(cmd, text) if spells then add(cmd, text) end end,
    Remove = function(text) if spells then remove(text) end end,
    Sync = function() if spells then requestSync() end end,
    GetList = function() return spells end,
    LABEL = LABEL,
}

local f = CreateFrame("Frame")
local db -- EspiUtilsAccountDB.mouseover, set by InitMouseover
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        db.spells = db.spells or {}
        local class = UnitClassBase and UnitClassBase("player") or select(2, UnitClass("player"))
        db.spells[class] = db.spells[class] or {}
        spells = db.spells[class]
        for _, e in ipairs(spells) do
            if not COND[e.kind] then
                e.kind = "help" -- hand-edited or corrupt SavedVariables
            end
        end
        sync()
    elseif pending then
        sync()
    end
end)

function EspiUtils.InitMouseover(settings)
    db = settings
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
end
