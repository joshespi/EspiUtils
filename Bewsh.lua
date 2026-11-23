-- Bewsh: a level-up notification. Everyone says "ding"; this says you bewshed.

local _, EspiUtils = ...

local Print = EspiUtils.Printer("Bewsh", "ffd100")

local DISPLAY_SECONDS = 6
local DEFAULTS = { enabled = true, guild = false, party = false }
local STORY = "Everyone says \"ding\" when they level, a habit from the EverQuest days. "
    .. "Back in vanilla WoW, Espi joked that it's really more of a \"boosh\" noise, and it stuck. "
    .. "Bewsh is that word, spelled the way it sounds."

local settings = {} -- EspiUtils.InitializeBewsh replaces it with the saved table
local hideTimer
local pendingChat = {}

local frame, detail = EspiUtils.CreateReminder("Bewsh!", "Interface\\Icons\\Spell_Holy_SurgeOfLight")
local events = CreateFrame("Frame")

local function Dismiss()
    if hideTimer then
        hideTimer:Cancel()
        hideTimer = nil
    end
    if not EspiUtils.Tiles.IsUnlocked() then
        frame:Hide()
    end
end

local function Show(level)
    if hideTimer then hideTimer:Cancel() end
    detail:SetText(level and ("You bewshed! Level %d."):format(level) or "You bewshed!")
    frame:Show()
    hideTimer = C_Timer.NewTimer(DISPLAY_SECONDS, function()
        hideTimer = nil
        Dismiss()
    end)
end

EspiUtils.RegisterTile("bewsh", frame, detail, { "CENTER", "CENTER", 0, 95 }, Dismiss, Dismiss)

frame:HookScript("OnEnter", function(self)
    if EspiUtils.Tiles.IsUnlocked() then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Why bewsh?")
    GameTooltip:AddLine(STORY, 1, 1, 1, true)
    GameTooltip:Show()
end)
frame:HookScript("OnLeave", function() GameTooltip:Hide() end)

-- Chat ------------------------------------------------------------------------

local function ChatLocked()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

local sendChatMessage = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage

local function Send(message, channel)
    if not pcall(sendChatMessage, message, channel) then
        Print("couldn't post to " .. channel:lower() .. ".")
    end
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
        Print("chat was locked, so deferred Bewsh messages weren't sent.")
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
        if not EspiUtils.IsCinematic() then
            Show(level)
        end
        PostChat(("bewsh (%d)"):format(level or UnitLevel("player") + 1))
    elseif event == "PLAYER_REGEN_ENABLED" then
        FlushChat()
    end
end)

-- account: EspiUtilsAccountDB; settings live in account.bewsh. Anything that is not a boolean falls back to its default.
function EspiUtils.InitializeBewsh(account)
    local store = type(account.bewsh) == "table" and account.bewsh or {}
    account.bewsh = store
    for key, default in pairs(DEFAULTS) do
        if type(store[key]) ~= "boolean" then store[key] = default end
    end
    settings = store
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
    -- Shows the tile for a few seconds; false when in combat or dead.
    Preview = function()
        if not EspiUtils.CanPreviewReminder() then return false end
        Show(UnitLevel("player"))
        return true
    end,
    ResetPosition = function()
        EspiUtils.Tiles.Reset("bewsh")
    end,
    ResetDefaults = function()
        EspiUtils.ApplyDefaults(settings, DEFAULTS, true)
        ClearPendingChat()
        EspiUtils.Tiles.Reset("bewsh")
        Dismiss()
    end,
}

local function OnOff(on)
    return on and "on" or "off"
end

function EspiUtils.HandleBewshCommand(action)
    local api = EspiUtils.Bewsh
    if action == "on" or action == "off" then
        api.Set("enabled", action == "on")
        Print("level-up notification " .. OnOff(settings.enabled) .. ".")
    elseif action == "guild" or action == "party" then
        api.Set(action, not settings[action])
        Print(("posting \"bewsh\" to %s %s."):format(action, OnOff(settings[action])))
    elseif action == "test" then
        if not api.Preview() then
            Print("preview available while alive and out of combat.")
        end
    elseif action == "story" then
        Print(STORY)
    elseif action == "" or action == "status" then
        Print(("level-up notification %s. Guild post %s, party post %s."):format(
            OnOff(settings.enabled), OnOff(settings.guild), OnOff(settings.party)))
    else
        Print("use /espiutils bewsh [on | off | status | guild | party | test | story].")
    end
end
