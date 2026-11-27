-- Sorts the tracked quests by quest level (lowest at the top by default, or
-- highest at the top) by re-adding the quest watches in that order; the stock
-- tracker lists quests in watch order.

local _, EspiUtils = ...

local Print = EspiUtils.Printer("Quest sort", "33ccff")

local DEFAULTS = { enabled = false, order = "asc" }
local ORDER_TEXT = { asc = "lowest level at the top", desc = "highest level at the top" }
local db                -- EspiUtilsDB.questSort
local scheduled = false
local sorting = false   -- our own re-adds fire the watch events; ignore them
local deferred = false  -- wanted a sort during combat
local passes = 0        -- consecutive sorts that changed the order
local MAX_PASSES = 3    -- past this, sorting pauses until toggled or the order settles
local paused = false    -- the game wouldn't keep the order

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

-- Prints and returns true while the tracker can't be changed.
local function TrackerLocked()
    if not InCombatLockdown() then return false end
    Print("can't change the tracker in combat.")
    return true
end

-- Runs fn with our own watch events ignored; returns pcall's results.
local function Quietly(fn)
    sorting = true
    local ok, err = pcall(fn)
    sorting = false
    return ok, err
end

local function WatchCount()
    if CQ and CQ.GetNumQuestWatches then return CQ.GetNumQuestWatches() end
    return GetNumQuestWatches and GetNumQuestWatches() or 0
end

local function KeepEasy()
    if TrackerLocked() then return end
    local removed, kept = 0, 0
    local ok, err = Quietly(function()
        for _, q in ipairs(ReadWatches()) do
            if IsEasy(q) then
                kept = kept + 1
            else
                Remove(q.key)
                removed = removed + 1
            end
        end
    end)
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

local function ClearPause()
    passes, paused = 0, false
end

-- The watches and their sorted copy, or nil when they are already in order.
local function Unsorted()
    local list = ReadWatches()
    if #list < 2 then return end
    local sorted = { unpack(list) }
    table.sort(sorted, Less)
    for i, q in ipairs(list) do
        if q ~= sorted[i] then return list, sorted end
    end
end

-- Re-adds the watches in sorted order. If the game drops any (e.g. a watch cap), puts
-- the original order back and pauses automatic sorting. Returns whether the sort held.
local function Apply(list, sorted)
    local before = WatchCount()
    local ok, err = Quietly(function()
        for _, q in ipairs(list) do Remove(q.key) end
        for _, q in ipairs(sorted) do Add(q.key) end
    end)
    if not ok then
        Print("couldn't reorder the tracker: " .. tostring(err))
    end
    if WatchCount() < before then
        Quietly(function()
            for _, q in ipairs(list) do Add(q.key) end
        end)
        if db.enabled then
            paused = true
            Print("the game wouldn't keep the sorted order; sorting paused until you toggle it.")
        else
            Print("the game wouldn't keep the sorted order; the old order is back.")
        end
        return false
    end
    return ok
end

-- Automatic sort, after quest events while sorting is on.
local function AutoSort()
    scheduled = false
    if sorting or not db.enabled then return end
    if InCombatLockdown() then
        deferred = true
        return
    end
    local list, sorted = Unsorted()
    if not list then
        ClearPause()
        return
    end
    if paused then return end
    -- Our own re-adds fire watch events after this returns; if the order never
    -- settles (the game refuses to keep it), stop instead of looping.
    passes = passes + 1
    if passes > MAX_PASSES then
        paused = true
        Print("the game keeps changing the tracker order back; sorting paused until you toggle it.")
        return
    end
    Apply(list, sorted)
end

-- One sort in the chosen direction, even with sorting off. Also clears a pause.
local function SortOnce()
    if sorting or TrackerLocked() then return end
    ClearPause()
    local list, sorted = Unsorted()
    if not list then
        Print("already in order.")
    elseif Apply(list, sorted) then
        Print("sorted, " .. ORDER_TEXT[db.order] .. ".")
    end
end

local function Schedule()
    if scheduled or sorting or not db.enabled then return end
    scheduled = true
    C_Timer.After(0, AutoSort)
end

-- Clears the pause so the next sort tries again.
local function Resume()
    ClearPause()
    Schedule()
end

local function SetEnabled(on)
    db.enabled = on and true or false
    Resume()
    Print(db.enabled and "on: tracked quests sort by level." or "off: the tracker keeps its current order.")
end

-- order: "asc" (lowest level at the top) or "desc" (highest level at the top).
local function SetOrder(order)
    if not ORDER_TEXT[order] then return end
    db.order = order
    Resume()
    Print(ORDER_TEXT[order] .. "." .. (db.enabled and "" or " Sorting is off; turn it on to apply."))
end

local function Status()
    Print(("%s, %s.%s"):format(EspiUtils.OnOff(db.enabled), ORDER_TEXT[db.order],
        paused and " Paused: the game wouldn't keep the order; toggle sorting to try again." or ""))
end

-- A Sort button on the tracker header: left-click sorts once, right-click runs KeepEasy.
-- Returns true once the button exists. The tracker may load after us, and frames are
-- not touched in combat.
local trackerButton
local function AttachTrackerButton()
    if trackerButton then return true end
    if InCombatLockdown() then return false end
    local tracker = _G.ObjectiveTrackerFrame or _G.WatchFrame or _G.QuestWatchFrame
    if not tracker then return false end
    local parent = tracker.Header or _G.WatchFrameHeader or tracker
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(44, 20)
    button:SetFrameLevel(parent:GetFrameLevel() + 5)
    button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -32, -2)
    button:SetText("Sort")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then KeepEasy() else SortOnce() end
    end)
    EspiUtils.SetTooltip(button, function()
        return "Quest tracker",
            "Left-click to sort by level (" .. ORDER_TEXT[db.order] .. ").",
            "Right-click to untrack all but green and grey quests."
    end, "ANCHOR_LEFT")
    trackerButton = button
    return true
end

local attacher = CreateFrame("Frame")
attacher:SetScript("OnEvent", function(self)
    if AttachTrackerButton() then self:UnregisterAllEvents() end
end)

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
    db = EspiUtils.SubTable(settings, "questSort")
    EspiUtils.ApplyDefaults(db, DEFAULTS)
    if not ORDER_TEXT[db.order] then db.order = DEFAULTS.order end
    if not AttachTrackerButton() then
        attacher:RegisterEvent("ADDON_LOADED")
        attacher:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
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
    SortOnce = SortOnce,
    ResetDefaults = function()
        EspiUtils.ApplyDefaults(db, DEFAULTS, true)
        Resume()
    end,
}

local ORDER_WORDS = { low = "asc", high = "desc" }

-- action is already lowercased by the /espiutils dispatcher.
function EspiUtils.HandleQuestSortCommand(action, value)
    value = value:lower()
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
    elseif action == "sort" then
        SortOnce()
    elseif action == "keepeasy" then
        KeepEasy()
    elseif action == "config" or action == "options" then
        EspiUtils.OpenOptions("quests")
    else
        Print("/espiutils quests [on | off | status | sort | keepeasy | order [low | high]] (no argument toggles sorting; sort: once, even when off; low/high: which level goes at the top)")
    end
end
