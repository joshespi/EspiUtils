-- Sorts the tracked quests by quest level (lowest at the top by default, or
-- highest at the top) by re-adding the quest watches in that order; the stock
-- tracker lists quests in watch order.

local _, EspiUtils = ...

local Print = EspiUtils.Printer("Quest sort", "33ccff")

local db                -- EspiUtilsDB.questSort
local scheduled = false
local sorting = false   -- our own re-adds fire the watch events; ignore them
local deferred = false  -- wanted a sort during combat
local passes = 0        -- consecutive sorts that changed the order
local MAX_PASSES = 3    -- past this, sorting is paused until toggled or the order changes

local CQ = C_QuestLog

-- Quest watches as { key, level, title }. key is the quest ID (or log index on
-- clients without quest IDs in the watch API); it is what Add/RemoveQuestWatch take.
local function ReadWatches()
    local list = {}
    if CQ and CQ.GetNumQuestWatches and CQ.GetQuestIDForQuestWatchIndex and CQ.GetLogIndexForQuestID and CQ.GetInfo then
        for i = 1, CQ.GetNumQuestWatches() do
            local id = CQ.GetQuestIDForQuestWatchIndex(i)
            local index = id and CQ.GetLogIndexForQuestID(id)
            local info = index and CQ.GetInfo(index)
            if info then
                list[#list + 1] = { key = id, isQuestID = true, level = info.level or 0, title = info.title or "" }
            end
        end
    elseif GetNumQuestWatches and GetQuestIndexForWatch and GetQuestLogTitle then
        for i = 1, GetNumQuestWatches() do
            local index = GetQuestIndexForWatch(i)
            local title, level = GetQuestLogTitle(index)
            if title then
                list[#list + 1] = { key = index, level = level or 0, title = title }
            end
        end
    end
    return list
end

local function Add(key)
    if CQ and CQ.AddQuestWatch then return CQ.AddQuestWatch(key) end
    return AddQuestWatch(key)
end

local function Remove(key)
    if CQ and CQ.RemoveQuestWatch then return CQ.RemoveQuestWatch(key) end
    return RemoveQuestWatch(key)
end

-- Green and grey quests are 3 or more levels below the player (yellow starts at -2).
local function IsEasy(q)
    local level = q.level
    if q.isQuestID and CQ.GetQuestDifficultyLevel then
        level = CQ.GetQuestDifficultyLevel(q.key) or level
    end
    return level > 0 and level - UnitLevel("player") <= -3
end

local function KeepEasy()
    if InCombatLockdown() then
        Print("can't change the tracker in combat.")
        return
    end
    local removed, kept = 0, 0
    sorting = true
    local ok, err = pcall(function()
        for _, q in ipairs(ReadWatches()) do
            if IsEasy(q) then
                kept = kept + 1
            else
                Remove(q.key)
                removed = removed + 1
            end
        end
    end)
    sorting = false
    if not ok then
        Print("couldn't update the tracker: " .. tostring(err))
        return
    end
    Print(("untracked %d quest(s), kept %d green or grey."):format(removed, kept))
end

-- Only the level flips with db.order; same-level quests stay in title order either way.
local function Less(a, b)
    if a.level ~= b.level then
        if db.order == "desc" then return a.level > b.level end
        return a.level < b.level
    end
    if a.title ~= b.title then return a.title < b.title end
    return tostring(a.key) < tostring(b.key)
end

local function SortNow()
    scheduled = false
    if not db.enabled or sorting then return end
    if InCombatLockdown() then
        deferred = true
        return
    end
    local list = ReadWatches()
    if #list < 2 then return end
    local sorted = { unpack(list) }
    table.sort(sorted, Less)
    local same = true
    for i, q in ipairs(list) do
        if q ~= sorted[i] then same = false break end
    end
    if same then
        passes = 0
        return
    end
    if passes > MAX_PASSES then return end
    -- Our own re-adds fire watch events after this returns; if the order never
    -- settles (the game refuses to keep it), stop instead of looping.
    passes = passes + 1
    if passes > MAX_PASSES then
        Print("the game keeps changing the tracker order back; sorting paused until you toggle it.")
        return
    end

    sorting = true
    local ok, err = pcall(function()
        for _, q in ipairs(list) do Remove(q.key) end
        for _, q in ipairs(sorted) do Add(q.key) end
    end)
    sorting = false
    if not ok then
        Print("couldn't reorder the tracker: " .. tostring(err))
    end
    -- Put back anything the re-add lost (e.g. a watch cap), in the original order.
    if #ReadWatches() < #list then
        sorting = true
        for _, q in ipairs(list) do Add(q.key) end
        sorting = false
        passes = MAX_PASSES + 1
        Print("the game wouldn't keep the sorted order; sorting paused until you toggle it.")
    end
end

local function Schedule()
    if scheduled or sorting or not db.enabled then return end
    scheduled = true
    C_Timer.After(0, SortNow)
end

local function SetEnabled(on)
    db.enabled = on and true or false
    passes = 0
    if db.enabled then Schedule() end
    Print(db.enabled and "on: tracked quests sort by level." or "off: the tracker keeps its current order.")
end

local ORDER_TEXT = { asc = "lowest level at the top", desc = "highest level at the top" }

-- order: "asc" (lowest level at the top) or "desc" (highest level at the top).
local function SetOrder(order)
    if not ORDER_TEXT[order] then return end
    db.order = order
    passes = 0
    if db.enabled then Schedule() end
    Print(ORDER_TEXT[order] .. "." .. (db.enabled and "" or " Sorting is off; turn it on to apply."))
end

local function Status()
    Print(("%s, %s.%s"):format(EspiUtils.OnOff(db.enabled), ORDER_TEXT[db.order],
        passes > MAX_PASSES and " Paused: the game wouldn't keep the order; toggle sorting to try again." or ""))
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if deferred then
            deferred = false
            Schedule()
        end
    else
        Schedule()
    end
end)

function EspiUtils.InitializeQuestSort(settings)
    settings.questSort = type(settings.questSort) == "table" and settings.questSort or {}
    db = settings.questSort
    EspiUtils.ApplyDefaults(db, { enabled = false, order = "asc" })
    if not ORDER_TEXT[db.order] then db.order = "asc" end
    for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_WATCH_LIST_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do
        pcall(events.RegisterEvent, events, event)
    end
    Schedule()
end

EspiUtils.QuestSort = {
    GetSettings = function() return db end,
    SetEnabled = SetEnabled,
    SetOrder = SetOrder,
    KeepEasy = KeepEasy,
}

local ORDER_WORDS = { low = "asc", high = "desc" }

function EspiUtils.HandleQuestSortCommand(action, value)
    action = (action or ""):lower()
    value = (value or ""):lower()
    if action == "" then
        SetEnabled(not db.enabled)
    elseif action == "on" then
        SetEnabled(true)
    elseif action == "off" then
        SetEnabled(false)
    elseif action == "status" then
        Status()
    elseif action == "order" and value == "" then
        SetOrder(db.order == "desc" and "asc" or "desc")
    elseif action == "order" and ORDER_WORDS[value] then
        SetOrder(ORDER_WORDS[value])
    elseif action == "keepeasy" then
        KeepEasy()
    elseif action == "config" or action == "options" then
        EspiUtils.OpenOptions("quests")
    else
        Print("/espiutils quests [on | off | status | keepeasy | order [low | high]] (no argument toggles sorting; low/high: which level goes at the top)")
    end
end
