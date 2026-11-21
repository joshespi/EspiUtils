-- Sorts the tracked quests by quest level (low to high) by re-adding the quest
-- watches in that order; the stock tracker lists quests in watch order.

local _, EspiUtils = ...

local Print = EspiUtils.Printer("Quest sort", "33ccff")

local db                -- EspiUtilsDB.questSort
local scheduled = false
local sorting = false   -- our own re-adds fire the watch events; ignore them
local deferred = false  -- wanted a sort during combat
local passes = 0        -- consecutive sorts that changed the order
local MAX_PASSES = 3

local CQ = C_QuestLog

-- Quest watches as { id, level, title, key }. id is the quest ID (or log index on
-- clients without quest IDs in the watch API); key is what Add/RemoveQuestWatch take.
local function ReadWatches()
    local list = {}
    if CQ and CQ.GetNumQuestWatches and CQ.GetQuestIDForQuestWatchIndex and CQ.GetLogIndexForQuestID and CQ.GetInfo then
        for i = 1, CQ.GetNumQuestWatches() do
            local id = CQ.GetQuestIDForQuestWatchIndex(i)
            local index = id and CQ.GetLogIndexForQuestID(id)
            local info = index and CQ.GetInfo(index)
            if info then
                list[#list + 1] = { key = id, level = info.level or 0, title = info.title or "" }
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

local function Less(a, b)
    if a.level ~= b.level then return a.level < b.level end
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
    -- Our own re-adds fire watch events after this returns; if the order never
    -- settles (the game refuses to keep it), stop instead of looping.
    passes = passes + 1
    if passes > MAX_PASSES then return end

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
        passes = MAX_PASSES
        Print("the game wouldn't keep the sorted order; sorting paused until you toggle it.")
    end
end

local function Schedule()
    if scheduled or sorting or not db or not db.enabled then return end
    scheduled = true
    C_Timer.After(0, SortNow)
end

local function SetEnabled(on)
    db.enabled = on and true or false
    passes = 0
    if db.enabled then Schedule() end
    Print(db.enabled and "on: tracked quests sort by level." or "off: the tracker keeps its current order.")
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
    EspiUtils.ApplyDefaults(db, { enabled = false })
    for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_WATCH_LIST_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do
        pcall(events.RegisterEvent, events, event)
    end
    Schedule()
end

EspiUtils.QuestSort = {
    GetSettings = function() return db end,
    SetEnabled = SetEnabled,
}

function EspiUtils.HandleQuestSortCommand(action)
    action = (action or ""):lower()
    if action == "" then
        SetEnabled(not db.enabled)
    elseif action == "on" then
        SetEnabled(true)
    elseif action == "off" then
        SetEnabled(false)
    elseif action == "status" then
        Print(db.enabled and "on." or "off.")
    elseif action == "config" or action == "options" then
        EspiUtils.OpenOptions("quests")
    else
        Print("/espiutils quests [on | off | status] (no argument toggles)")
    end
end
