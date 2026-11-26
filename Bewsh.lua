-- Boosh (code name Bewsh): a level-up notification. Everyone says "ding"; this says you booshed.
-- Players only see "boosh"; identifiers, the banner key and the saved account.bewsh table keep the old name.

local _, EspiUtils = ...

local Print = EspiUtils.Printer("Boosh", "ffd100")

local DISPLAY_SECONDS = 6
local DEFAULTS = { enabled = true, guild = false, party = false }
local STORY = "Everyone says \"ding\" when they level, a habit from the EverQuest days. "
    .. "Back in vanilla WoW, Espi joked that it's really more of a \"boosh\" noise, and it stuck."

local settings = {} -- EspiUtils.InitializeBewsh replaces it with the saved table
local pendingChat = {}

local events = CreateFrame("Frame")

local function Dismiss()
    EspiUtils.Banner.Dismiss("bewsh")
end

-- preview: ignore the hide options (the Preview button and /espiutils boosh test).
local function Show(level, preview)
    EspiUtils.Banner.Push({
        key = "bewsh",
        title = "Boosh!",
        text = level and ("You booshed! Level %d."):format(level) or "You booshed!",
        icon = "Interface\\Icons\\Spell_Holy_SurgeOfLight",
        duration = DISPLAY_SECONDS,
        tooltip = { "Why boosh?", STORY },
        preview = preview,
    })
end

-- Chat ------------------------------------------------------------------------

local function ChatLocked()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

local sendChatMessage = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage

-- Returns true if the message went out.
local function Send(message, channel)
    if pcall(sendChatMessage, message, channel) then return true end
    Print("couldn't post to " .. channel:lower() .. ".")
    return false
end

local function GroupChannel()
    local home = LE_PARTY_CATEGORY_HOME or 1
    if IsInGroup(home) then
        return IsInRaid(home) and "RAID" or "PARTY"
    end
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end
end

-- Channels the player opted into and can post in right now.
local function Channels()
    local list = {}
    if settings.guild and IsInGuild() then
        list[#list + 1] = "GUILD"
    end
    local group = settings.party and GroupChannel()
    if group then
        list[#list + 1] = group
    end
    return list
end

local function ClearPendingChat()
    pendingChat = {}
    events:UnregisterEvent("PLAYER_REGEN_ENABLED")
end

local function PostChat(message)
    local channels = Channels()
    if #channels == 0 then return end
    if ChatLocked() then
        pendingChat[#pendingChat + 1] = { message = message, channels = channels }
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    for _, channel in ipairs(channels) do
        Send(message, channel)
    end
end

local function FlushChat()
    local queued = pendingChat
    ClearPendingChat()
    if #queued == 0 then return end
    if ChatLocked() then
        Print("chat was locked, so deferred Boosh messages weren't sent.")
        return
    end
    -- Only post to channels still open now (e.g. skip a party you left mid-combat).
    local eligible = {}
    for _, channel in ipairs(Channels()) do eligible[channel] = true end
    for _, entry in ipairs(queued) do
        for _, channel in ipairs(entry.channels) do
            if eligible[channel] then Send(entry.message, channel) end
        end
    end
end

-- Events ----------------------------------------------------------------------

events:SetScript("OnEvent", function(_, event, level)
    if event == "PLAYER_LEVEL_UP" then
        if not settings.enabled then return end
        Show(level)
        PostChat(("boosh (%d)"):format(level or UnitLevel("player") + 1))
    elseif event == "PLAYER_REGEN_ENABLED" then
        FlushChat()
    end
end)

-- account: EspiUtilsAccountDB; settings live in account.bewsh. Anything that is not a boolean falls back to its default.
function EspiUtils.InitializeBewsh(account)
    settings = EspiUtils.SubTable(account, "bewsh")
    EspiUtils.ApplyDefaults(settings, DEFAULTS, false, true)
    events:RegisterEvent("PLAYER_LEVEL_UP")
end

-- API shared by the slash command and the options screen.
EspiUtils.Bewsh = {
    Story = STORY,
    GetSettings = function() return settings end,
    Set = function(key, on)
        if DEFAULTS[key] == nil then return end
        settings[key] = on and true or false
        if key == "enabled" and not on then
            ClearPendingChat()
            Dismiss()
        end
    end,
    -- Shows the alert for a few seconds; false when in combat or dead.
    Preview = function()
        if not EspiUtils.CanPreviewReminder() then return false end
        Show(UnitLevel("player"), true)
        return true
    end,
    ResetDefaults = function()
        EspiUtils.ApplyDefaults(settings, DEFAULTS, true)
        ClearPendingChat()
        Dismiss()
    end,
}

local OnOff = EspiUtils.OnOff

-- Story targets: each returns the chat channel, or nil plus why it can't post there.
local STORY_TARGETS = {
    say = function() return "SAY" end,
    party = function() return GroupChannel(), "you're not in a group." end,
    guild = function() return IsInGuild() and "GUILD" or nil, "you're not in a guild." end,
}
local STORY_USAGE = "story [say | party | guild]"
local USAGE = "[on | off | status | guild | party | test | " .. STORY_USAGE .. "]"
EspiUtils.Bewsh.Usage = USAGE

-- Prints the story, or posts it to say (one message) or party/guild (one sentence per message).
local function TellStory(target)
    if target == "" then
        Print(STORY)
        return
    end
    local resolve = STORY_TARGETS[target]
    if not resolve then
        Print("use /espiutils boosh " .. STORY_USAGE .. ".")
        return
    end
    local channel, reason = resolve()
    if not channel then
        Print(reason)
        return
    end
    if ChatLocked() then
        Print("chat is locked right now, try again later.")
        return
    end
    -- Outside instances, SAY allows one message per keypress, so it gets the whole story at once.
    if channel == "SAY" then
        Send(STORY, channel)
        return
    end
    -- Every sentence in STORY must end in . ! or ?, or this pattern drops it.
    for sentence in STORY:gmatch("%S.-[%.!?]") do
        if not Send(sentence, channel) then return end
    end
end

EspiUtils.Bewsh.TellStory = TellStory

function EspiUtils.HandleBewshCommand(action, value)
    local api = EspiUtils.Bewsh
    if action == "on" or action == "off" then
        api.Set("enabled", action == "on")
        Print("level-up notification " .. OnOff(settings.enabled) .. ".")
    elseif action == "guild" or action == "party" then
        api.Set(action, not settings[action])
        Print(("posting \"boosh\" to %s %s."):format(action, OnOff(settings[action])))
    elseif action == "test" then
        if not api.Preview() then EspiUtils.PrintPreviewBlocked() end
    elseif action == "story" then
        TellStory(value:lower())
    elseif action == "" or action == "status" then
        Print(("level-up notification %s. Guild post %s, party post %s."):format(
            OnOff(settings.enabled), OnOff(settings.guild), OnOff(settings.party)))
    else
        Print("use /espiutils boosh " .. USAGE .. ".")
    end
end
