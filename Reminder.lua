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
    for key, default in pairs(GENERAL_DEFAULTS) do
        if type(store[key]) ~= "boolean" then store[key] = default end
    end
    general = store
end

-- Shared pieces of the Food and Rebuff reminders ------------------------------------
-- o.key: settings key; o.label: "Food"; o.defaults: saved defaults; o.maxLead;
-- o.settings(): the saved table (nil before load); o.update(): re-evaluate the alert;
-- o.preview(): show a 5 second preview.
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
        if not EspiUtils.CanPreviewReminder() then return false end
        return o.preview() ~= false
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
    elseif action == "move" then
        EspiUtils.Banner.ToggleMove()
    elseif action == "reset" then
        EspiUtils.Banner.ResetPosition()
    elseif action == "test" then
        if not api.Preview() then
            Print("Preview available while alive and out of combat" .. (o.previewNote or "") .. ".")
        end
    elseif action == "" or action == "status" then
        Print(("%s reminders %s. Expiry warning: %s.%s"):format(
            o.label,
            settings.enabled and "enabled" or "disabled",
            settings.lead > 0 and ("%d seconds"):format(settings.lead) or "off",
            o.statusExtra and o.statusExtra() or ""
        ))
    else
        Print(("Use /espiutils %s [on | off | status | lead <seconds> | test | move | reset]."):format(o.command))
    end
end

-- Previews ignore the hide options but still wait for a calm moment.
function EspiUtils.CanPreviewReminder()
    return not InCombatLockdown() and not UnitIsDeadOrGhost("player")
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
function EspiUtils.ApplyDefaults(db, defaults, overwrite)
    for k, v in pairs(defaults) do
        if overwrite or db[k] == nil then db[k] = v end
    end
end
