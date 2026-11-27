-- Spell lists are account-wide per class; macros are per-character.

local _, EspiUtils = ...

local PREFIX = "MO "
local COND = {
    help = "[@mouseover,help,nodead][]",
    harm = "[@mouseover,harm,nodead][]",
}
local LABEL = { help = "friendly", harm = "hostile" }
local KIND = { add = "help", harm = "harm" }
local MACRO_CONSTS = Constants and Constants.MacroConsts or {}
local MAX_ACCOUNT_MACROS = MACRO_CONSTS.MAX_ACCOUNT_MACROS or 120
local MAX_CHARACTER_MACROS = MACRO_CONSTS.MAX_CHARACTER_MACROS or 18

local spells -- this class's list, set by InitMouseover
local pending = false

local say = EspiUtils.Printer("Mouseover", "33ccff")

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
    if idx > 0 and idx <= MAX_ACCOUNT_MACROS then
        return nil
    end
    return idx
end

-- A character macro this addon made: "MO " name and the exact body macroBody writes.
-- Hand-made macros that happen to start with "MO " are left alone.
local function isOurMacro(name, body)
    if not name or name:sub(1, #PREFIX) ~= PREFIX then return false end
    local tip, kind, cast = strtrim(body or ""):match("^#showtooltip (.-)\n/cast %[@mouseover,(%a+),nodead%]%[%] (.+)$")
    return tip ~= nil and COND[kind] ~= nil and tip == cast
end

-- Deletes this addon's character macros for spells no longer in the list, for example
-- spells removed on another character of the same class. Returns how many were deleted.
local function prune(numChar)
    local wanted = {}
    for _, e in ipairs(spells) do wanted[macroName(e.name)] = true end
    local removed = 0
    -- Highest index first: deleting a macro shifts the ones after it down.
    for idx = MAX_ACCOUNT_MACROS + numChar, MAX_ACCOUNT_MACROS + 1, -1 do
        local name, _, body = GetMacroInfo(idx)
        if not wanted[name] and isOurMacro(name, body) then
            DeleteMacro(idx)
            removed = removed + 1
        end
    end
    return removed
end

-- verbose: also report when nothing needed to change (the sync command and button).
local function sync(verbose)
    if InCombatLockdown() then
        pending = true
        return false
    end
    pending = false

    local made, updated = 0, 0
    local _, numChar = GetNumMacros()
    local removed = prune(numChar)
    numChar = numChar - removed
    for _, e in ipairs(spells) do
        local name, body = macroName(e.name), macroBody(e.name, e.kind)
        local idx = macroIndex(name)
        if not idx then
            say("account macro already named " .. name .. ", skipped: " .. e.name)
        elseif idx == 0 then
            if numChar >= MAX_CHARACTER_MACROS then
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

    if made + updated + removed > 0 then
        say(("macros synced: %d created, %d updated, %d removed"):format(made, updated, removed))
    elseif verbose then
        say("macros up to date")
    end
    return true
end

local function requestSync(verbose)
    if not sync(verbose) then
        say("in combat, macros sync when it ends")
    end
end

-- Spellbook scan (castable spells only), cached until the book changes.
local book -- sorted { {name=, icon=, id=}, ... }

local function scanBook()
    local out, seen = {}, {}
    local SB = C_SpellBook
    if not (SB and SB.GetNumSpellBookSkillLines and Enum.SpellBookSpellBank) then
        return out
    end
    local bank = Enum.SpellBookSpellBank.Player
    local spellType = Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    for line = 1, SB.GetNumSpellBookSkillLines() do
        local li = SB.GetSpellBookSkillLineInfo(line)
        if li and not li.offSpecID then
            for slot = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
                local info = SB.GetSpellBookItemInfo(slot, bank)
                if info and info.itemType == spellType and not info.isPassive
                    and not info.isOffSpec and info.name and not seen[info.name] then
                    seen[info.name] = true
                    out[#out + 1] = { name = info.name, lower = info.name:lower(), icon = info.iconID, id = info.spellID }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

local function getBook()
    book = book or scanBook()
    return book
end

-- Edit distance. The two rows are reused between calls (only indexes 0..#b are read).
local rowA, rowB = {}, {}
local function distance(a, b)
    local prev, cur = rowA, rowB
    for j = 0, #b do prev[j] = j end
    for i = 1, #a do
        cur[0] = i
        local ai = a:byte(i)
        for j = 1, #b do
            local cost = ai == b:byte(j) and 0 or 1
            cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        end
        prev, cur = cur, prev
    end
    return prev[#b]
end

-- Best spellbook match for typed text, or nil when none/ambiguous (second value lists ambiguous names).
local function resolveSpell(text)
    local lower = text:lower()
    local entries = getBook()
    local function unique(test)
        local hits = {}
        for _, e in ipairs(entries) do
            if test(e.lower) then hits[#hits + 1] = e.name end
        end
        if #hits == 1 then return hits[1] end
        if #hits > 1 then return nil, hits end
    end
    local hit = unique(function(n) return n == lower end)
    if hit then return hit end
    local amb
    hit, amb = unique(function(n) return n:sub(1, #lower) == lower end)
    if hit or amb then return hit, amb end
    hit, amb = unique(function(n) return n:find(lower, 1, true) ~= nil end)
    if hit or amb then return hit, amb end
    local best, bestD, tie
    local maxD = math.min(2, math.floor(#lower / 4)) -- short names get little or no fuzz
    -- At 0 only an exact match would do, and that was checked above.
    if maxD == 0 then return end
    for _, e in ipairs(entries) do
        -- The distance is at least the length difference.
        local d = math.abs(#e.lower - #lower) <= maxD and distance(lower, e.lower) or maxD + 1
        if d <= maxD then
            if not bestD or d < bestD then
                best, bestD, tie = e.name, d, false
            elseif d == bestD then
                tie = true
            end
        end
    end
    if best and not tie then return best end
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
            local fixed, ambiguous = resolveSpell(spell)
            if fixed and fixed ~= spell then
                say(("corrected '%s' -> '%s'"):format(spell, fixed))
                spell = fixed
            elseif ambiguous then
                say(spell .. ": matches " .. table.concat(ambiguous, ", ") .. " (using as typed)")
            end
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
    return changed
end

local function setKind(spell, kind)
    local _, e = find(spell)
    if e and COND[kind] then
        e.kind = kind
        requestSync()
    end
end

-- The sync's prune deletes the removed spells' macros (only ones this addon wrote), and
-- waits for combat to end.
local function remove(list)
    local changed = false
    for piece in list:gmatch("[^,]+") do
        local spell = parseSpell(piece) -- nil for a blank piece ("a,,b")
        local i = spell and find(spell)
        if i then
            local e = table.remove(spells, i)
            say("removed " .. e.name)
            changed = true
        elseif spell then
            say("not in list: " .. spell)
        end
    end
    if changed then requestSync() end
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
    local cmd, rest = msg:match("^(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if KIND[cmd] then
        add(cmd, rest)
    elseif cmd == "del" or cmd == "remove" then
        remove(rest)
    elseif cmd == "list" then
        list()
    elseif cmd == "sync" then
        requestSync(true)
    else
        help()
    end
end

-- Used by the options screen, and only valid once the module is ready
-- (EspiUtils.ready.mouseover): spells is nil while it is off. Add returns true if the
-- list changed; the other actions return nothing and report through chat.
EspiUtils.Mouseover = {
    Add = add,
    SetKind = setKind,
    Remove = remove,
    Sync = function() requestSync(true) end,
    GetList = function() return spells end,
    -- Whether spell is in the list (case-insensitive, like every list lookup).
    Has = function(spell) return find(spell) ~= nil end,
    GetSpellbook = getBook,
    LABEL = LABEL,
}

local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        sync() -- macros can't be read or written before login
    elseif event == "SPELLS_CHANGED" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        book = nil
    elseif pending then
        sync()
    end
end)

-- settings: EspiUtilsAccountDB.mouseover
function EspiUtils.InitMouseover(settings)
    spells = EspiUtils.SubTable(EspiUtils.SubTable(settings, "spells"), EspiUtils.PlayerClass)
    for _, e in ipairs(spells) do
        if not COND[e.kind] then
            e.kind = "help" -- hand-edited or corrupt SavedVariables
        end
    end
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("SPELLS_CHANGED")
    f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
end
