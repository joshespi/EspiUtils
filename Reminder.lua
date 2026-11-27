local _, EspiUtils = ...

-- Shared reminder state and helpers. The banner itself (frame, queue, position, and the
-- decision whether an alert may show) lives in Banner.lua.

local general = {} -- EspiUtils.InitGeneral replaces it with the saved settings
local RAID_WARNING_SOUND_ID = 8959 -- SOUNDKIT.RAID_WARNING, for clients without SOUNDKIT

-- General settings (EspiUtilsAccountDB.general), shared by every reminder -----------

local GENERAL_DEFAULTS = {
    sound = false,              -- play a sound when a reminder appears
    hideMounted = false,        -- hide reminders while mounted
    hidePvP = false,            -- hide reminders in battlegrounds and arenas
    timedHideInstances = false, -- hide the timed reminders (posture, water, stand up) inside instances
}

EspiUtils.General = {
    GetSettings = function() return general end,
    Set = function(key, value)
        if GENERAL_DEFAULTS[key] == nil then return end
        general[key] = value and true or false
        EspiUtils.Banner.Refresh()
    end,
    Reset = function()
        EspiUtils.ApplyDefaults(general, GENERAL_DEFAULTS, true)
        EspiUtils.Banner.Refresh()
    end,
    PlaySound = function()
        PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or RAID_WARNING_SOUND_ID)
    end,
}

-- store: EspiUtilsAccountDB.general. Anything that is not a boolean falls back to its default.
function EspiUtils.InitGeneral(store)
    EspiUtils.ApplyDefaults(store, GENERAL_DEFAULTS, false, true)
    general = store
end

-- Shared pieces of the Food and Rebuff reminders ------------------------------------
-- o.key: the banner key (not read yet); o.command: the slash command word; o.label: "Food";
-- o.defaults: saved defaults; o.maxLead; o.settings(): the saved table (nil before load);
-- o.update(): re-evaluate the alert; o.preview(): show a 5 second preview, false when blocked;
-- o.previewNote: optional text added to the "preview available" message.
-- Returns the settings API used by the slash command and the options screen.
function EspiUtils.NewBuffReminderAPI(o)
    local api = { MAX_LEAD = o.maxLead, GetSettings = o.settings }
    o.api = api
    function api.SetEnabled(enabled)
        o.settings().enabled = enabled and true or false
        o.update()
    end
    function api.SetHideResting(hide)
        o.settings().hideResting = hide and true or false
        o.update()
    end
    -- true when seconds is a whole number from 0 to MAX_LEAD
    function api.SetLead(seconds)
        if not EspiUtils.IsWholeInRange(seconds, 0, o.maxLead) then
            return false
        end
        o.settings().lead = seconds
        o.update()
        return true
    end
    -- Shows the reminder for a few seconds; false when in combat or dead.
    function api.Preview()
        return o.preview()
    end
    function api.ResetDefaults()
        EspiUtils.ApplyDefaults(o.settings(), o.defaults, true)
        o.update()
    end
    return api
end

-- Slash command shared by Food and Rebuff. o as above (o.api is set by
-- NewBuffReminderAPI), plus o.command and o.statusExtra() (optional text appended to the status line).
function EspiUtils.HandleBuffReminderCommand(o, action, value)
    local api = o.api
    local settings = api.GetSettings()
    local Print = EspiUtils.Print
    if not settings then return end
    if action == "on" or action == "off" then
        api.SetEnabled(action == "on")
        Print(("%s reminders %s."):format(o.label, settings.enabled and "enabled" or "disabled"))
    elseif action == "lead" then
        local seconds = tonumber(value)
        if not api.SetLead(seconds) then
            Print(("Enter a whole number from 0 to %d. Use 0 for missing-buff reminders only."):format(o.maxLead))
            return
        end
        Print(seconds == 0 and "Missing-buff reminders only." or ("Expiry warning set to %d seconds."):format(seconds))
    elseif action == "test" then
        if not api.Preview() then EspiUtils.PrintPreviewBlocked(o.previewNote) end
    elseif action == "" or action == "status" then
        Print(("%s reminders %s. Expiry warning: %s.%s"):format(
            o.label,
            settings.enabled and "enabled" or "disabled",
            settings.lead > 0 and ("%d seconds"):format(settings.lead) or "off",
            o.statusExtra and o.statusExtra() or ""
        ))
    else
        Print(("Use /espiutils %s [on | off | status | lead <seconds> | test]."):format(o.command))
    end
end

-- Previews ignore the hide options but still wait for a calm moment.
function EspiUtils.CanPreviewReminder()
    return not InCombatLockdown() and not UnitIsDeadOrGhost("player")
end

-- note: optional text before the full stop (", for classes with tracked buffs").
function EspiUtils.PrintPreviewBlocked(note)
    EspiUtils.Print("Preview available while alive and out of combat" .. (note or "") .. ".")
end

function EspiUtils.Print(message)
    print("|cffefbd68Espi Utils|r " .. message)
end

-- A Print that tags each line with a colored module label.
function EspiUtils.Printer(label, color)
    local tag = ("|cff%s%s:|r "):format(color, label)
    return function(message)
        EspiUtils.Print(tag .. message)
    end
end

local WHITE = { 1, 1, 1 }

-- Tooltip on owner: title, then any further lines, all wrapped. No title: none.
-- A line is a string (white) or { text, r, g, b }.
function EspiUtils.ShowTooltip(owner, anchor, title, ...)
    if not title then return end
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    GameTooltip:SetText(title, nil, nil, nil, nil, true)
    for i = 1, select("#", ...) do
        local line = select(i, ...)
        local text, color = line, WHITE
        if type(line) == "table" then text, color = line[1], { line[2], line[3], line[4] } end
        GameTooltip:AddLine(text, color[1], color[2], color[3], true)
    end
    GameTooltip:Show()
end

local function HideTooltip()
    GameTooltip:Hide()
end

-- Shows a tooltip while the mouse is over widget. content: a string, or a function run on
-- each hover that returns the title and further lines (nothing: no tooltip).
function EspiUtils.SetTooltip(widget, content, anchor)
    widget:SetScript("OnEnter", function(self)
        if type(content) == "function" then
            EspiUtils.ShowTooltip(self, anchor, content())
        else
            EspiUtils.ShowTooltip(self, anchor, content)
        end
    end)
    widget:SetScript("OnLeave", HideTooltip)
end

function EspiUtils.OnOff(on)
    return on and "on" or "off"
end

-- Countdown text for a remaining time ("4:05"), and the delay until the text next changes.
function EspiUtils.FormatCountdown(remaining)
    local seconds = math.ceil(remaining)
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60), remaining - seconds + 1
end

function EspiUtils.IsWholeInRange(value, min, max)
    return type(value) == "number" and value >= min and value <= max and value % 1 == 0
end

-- Fills keys missing from db; with overwrite, resets every key to its default.
-- typed: also resets values whose type differs from the default's (hand-edited saves).
function EspiUtils.ApplyDefaults(db, defaults, overwrite, typed)
    for k, v in pairs(defaults) do
        if overwrite or db[k] == nil or (typed and type(db[k]) ~= type(v)) then db[k] = v end
    end
end

-- store[key] as a table, replacing a missing or non-table value with an empty one.
function EspiUtils.SubTable(store, key)
    if type(store[key]) ~= "table" then store[key] = {} end
    return store[key]
end

-- Game state shared by several modules ------------------------------------------------

EspiUtils.PlayerClass = UnitClassBase and UnitClassBase("player") or select(2, UnitClass("player"))

-- Clients without secret values never hide them.
EspiUtils.IsSecret = issecretvalue or function() return false end

-- True while the client hides aura data from addons.
function EspiUtils.AurasSecret()
    return C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() or false
end

-- Whether any left-hand line of a bag item's tooltip passes test(text). Returns nil when the
-- tooltip API is missing or the item's data hasn't loaded yet (worth asking again later).
function EspiUtils.BagTooltipMatches(bag, slot, test)
    if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then return nil end
    local data = C_TooltipInfo.GetBagItem(bag, slot)
    if not (data and data.lines and #data.lines > 0) then return nil end
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if text and not EspiUtils.IsSecret(text) and test(text) then return true end
    end
    return false
end
