local _, EspiUtils = ...

-- Options screen: a main page plus one subpage per feature, in the game's
-- Settings window (Esc > Options > AddOns). Built from plain frames so it
-- works on both the retail and WoW Forever clients.

local PAGE_WIDTH = 560
local pages = {}   -- key -> panel
local ordered = {}

-- Builders -------------------------------------------------------------------

local function RefreshPanel(panel)
    for _, refresh in ipairs(panel.refreshers) do refresh() end
end

local function NewPage(key, title, parent)
    local panel = CreateFrame("Frame")
    panel.name = title
    panel.refreshers = {}
    local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", 16, -16)
    heading:SetText(title)
    panel.y = -52
    panel:SetScript("OnShow", RefreshPanel)
    pages[key] = panel
    if parent then
        ordered[#ordered + 1] = panel
    end
    return panel
end

local function AddNote(panel, text)
    local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", 16, panel.y)
    fs:SetWidth(PAGE_WIDTH)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    panel.y = panel.y - math.max(fs:GetStringHeight(), 14) - 12
    return fs
end

local function AddHeader(panel, text)
    local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 16, panel.y)
    fs:SetText(text)
    panel.y = panel.y - 24
end

local function Tooltip(widget, text)
    if not text then return end
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, nil, nil, nil, nil, true)
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function AddCheck(panel, label, tip, get, set)
    local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", 12, panel.y)
    local text = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", check, "RIGHT", 4, 0)
    text:SetText(label)
    -- make the label part of the click target
    check:SetHitRectInsets(0, -(text:GetStringWidth() + 8), 0, 0)
    check:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    Tooltip(check, tip)
    panel.refreshers[#panel.refreshers + 1] = function() check:SetChecked(get()) end
    panel.y = panel.y - 28
    return check
end

-- A whole-number box. set returns false for a value out of range, which restores
-- the stored value.
local function AddNumber(panel, label, tip, get, set)
    local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 16, panel.y - 4)
    text:SetText(label)
    local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    box:SetSize(50, 20)
    box:SetPoint("TOPLEFT", 280, panel.y)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(4)
    local function refresh() box:SetText(tostring(get() or "")) end
    local function commit(self)
        local value = tonumber(self:GetText())
        if value then set(value) end
        refresh()
    end
    -- ClearFocus fires OnEditFocusLost, which commits.
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self) refresh() self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", commit)
    Tooltip(box, tip)
    panel.refreshers[#panel.refreshers + 1] = refresh
    panel.y = panel.y - 30
    return box
end

local function AddButtons(panel, specs)
    local x = 16
    for _, spec in ipairs(specs) do
        local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        button:SetSize(spec.width or 130, 22)
        button:SetPoint("TOPLEFT", x, panel.y)
        button:SetText(spec.label)
        button:SetScript("OnClick", spec.onClick)
        Tooltip(button, spec.tip)
        x = x + (spec.width or 130) + 8
    end
    panel.y = panel.y - 32
end

-- Adds a "Reset to defaults" button and wires the Settings window's own Defaults
-- button (panel.OnDefault) to the same reset.
local function AddDefaults(panel, reset)
    local function run()
        reset()
        RefreshPanel(panel)
    end
    panel.OnDefault = run
    AddButtons(panel, { { label = "Reset to defaults", width = 140, onClick = run } })
end

local function ModuleOff(panel, key)
    local legacy = EspiUtils.legacy[key]
    AddNote(panel, ("|cffff6060Off:|r the old %s addon is enabled. Disable it in the AddOns list and /reload to use this."):format(legacy.addon))
end

local MOVE_BUTTON = {
    label = "Move reminders",
    tip = "Show every reminder to drag and resize (scroll over one). Right-click one to lock. Positions are shared by all characters.",
    onClick = function()
        -- The Settings window would cover the reminders, so close it to drag.
        if EspiUtils.ToggleTileMove() and SettingsPanel and SettingsPanel:IsShown() then
            HideUIPanel(SettingsPanel)
        end
    end,
}

-- Pages ----------------------------------------------------------------------

local function BuildMain()
    local panel = NewPage("main", "Espi Utils")
    AddNote(panel, "Small quality-of-life tools. Pick a page on the left. Everything is also available from chat: /espiutils with no arguments lists the commands.")
    AddNote(panel, "Pages:\n- Food Reminder\n- Class Rebuff\n- Timed Reminders (posture, water)\n- Bag Rules (custom Clean Up)\n- Keep Bags Open\n- Quest Tracker\n- Mouseover Macros")
    return panel
end

local function BuildFood()
    local panel = NewPage("food", "Food Reminder", true)
    AddNote(panel, "Shows a reminder when the Well Fed buff is missing or about to run out.")
    local food = EspiUtils.Food
    AddCheck(panel, "Enable food reminder", nil,
        function() return food.GetSettings().enabled end,
        food.SetEnabled)
    AddCheck(panel, "Hide in rested areas", "Hide the reminder in cities and inns.",
        function() return food.GetSettings().hideResting end,
        food.SetHideResting)
    AddNumber(panel, "Expiry warning (seconds, 0 = missing only)",
        ("Whole number from 0 to %d."):format(food.MAX_LEAD),
        function() return food.GetSettings().lead end,
        food.SetLead)
    AddButtons(panel, {
        MOVE_BUTTON,
        { label = "Reset position", tip = "Default position and size for the Well Fed reminder.",
          onClick = food.ResetPosition },
    })
    AddDefaults(panel, food.ResetDefaults)
end

local function BuildRebuff()
    local panel = NewPage("rebuff", "Class Rebuff", true)
    AddNote(panel, "Reminds you to recast your class buffs (Fortitude, Arcane Intellect, Mark of the Wild, Battle Shout, armors) when they are missing or about to run out. Paladins are warned when a blessing they cast is running low.")
    local rebuff = EspiUtils.Rebuff
    if not rebuff.HasBuffs() then
        AddNote(panel, "No buffs are tracked for this character's class.")
        return
    end
    AddCheck(panel, "Enable rebuff reminder", nil,
        function() return rebuff.GetSettings().enabled end,
        rebuff.SetEnabled)
    AddCheck(panel, "Hide in rested areas", "Hide the reminder in cities and inns.",
        function() return rebuff.GetSettings().hideResting end,
        rebuff.SetHideResting)
    AddNumber(panel, "Expiry warning (seconds, 0 = missing only)",
        ("Whole number from 0 to %d."):format(rebuff.MAX_LEAD),
        function() return rebuff.GetSettings().lead end,
        rebuff.SetLead)
    AddButtons(panel, {
        MOVE_BUTTON,
        { label = "Reset position", tip = "Default position and size for the rebuff reminder.",
          onClick = rebuff.ResetPosition },
    })
    AddDefaults(panel, rebuff.ResetDefaults)
end

local function BuildTimed()
    local panel = NewPage("timed", "Timed Reminders", true)
    AddNote(panel, "Periodic reminders that appear for a few seconds. They wait until you are alive and out of combat.")
    for _, definition in ipairs(EspiUtils.GetTimedReminders()) do
        local command = definition.command
        AddHeader(panel, definition.title)
        AddCheck(panel, "Enabled", nil,
            function() local s = EspiUtils.GetTimedReminder(command) return s and s.enabled end,
            function(on) EspiUtils.SetTimedReminderEnabled(command, on) end)
        AddNumber(panel, "Interval (minutes)",
            ("Whole number from 1 to %d."):format(EspiUtils.TimedReminderMaxMinutes),
            function() local s = EspiUtils.GetTimedReminder(command) return s and s.minutes end,
            function(v) return EspiUtils.SetTimedReminderMinutes(command, v) end)
        AddButtons(panel, {
            { label = "Preview", onClick = function()
                if not EspiUtils.TestTimedReminder(command) then
                    EspiUtils.Print("Preview available while alive and out of combat.")
                end
            end },
        })
    end
    AddHeader(panel, "Position")
    AddButtons(panel, {
        MOVE_BUTTON,
        { label = "Reset positions", tip = "Default position and size for the posture and water reminders.",
          onClick = function()
              for _, definition in ipairs(EspiUtils.GetTimedReminders()) do
                  EspiUtils.Tiles.Reset(definition.command)
              end
          end },
    })
    AddDefaults(panel, EspiUtils.ResetTimedReminders)
end

local function BuildBags()
    local panel = NewPage("bags", "Bag Rules", true)
    AddNote(panel, "A custom Clean Up: camping items and tools first, equipment-set gear together, tradeable gear in the middle, conjured items, junk and bound gear at the bottom. Shift-click Clean Up for Blizzard's sort.")
    if not EspiUtils.ready.bags then return ModuleOff(panel, "bags") end
    local bags = EspiUtils.Bags
    for _, c in ipairs({
        { "enabled", "Clean Up button uses this sort", "Off: the button runs Blizzard's sort." },
        { "depositReagents", "Deposit reagents when the bank is open", "Clean Up first sends crafting reagents to the bank, then sorts the rest." },
        { "pinBound", "Pin conjured, junk and bound gear to the last slots", "Off: they are packed right after BoE gear." },
        { "questToJunk", "Sort quest items with junk", "Quest items go to the bottom with grey items (follows the pin setting above)." },
        { "debug", "Debug output", "Per-pass detail in chat and the log." },
    }) do
        local key = c[1]
        AddCheck(panel, c[2], c[3],
            function() return bags.GetSettings()[key] end,
            function(on) bags.GetSettings()[key] = on end)
    end
    AddButtons(panel, {
        { label = "Sort now", tip = "Open your bags first so their layout is used.", onClick = bags.Sort },
        { label = "Preview", tip = "Counts per section in chat; moves nothing.", onClick = bags.Preview },
    })
    AddDefaults(panel, bags.ResetDefaults)
end

local function BuildKeep()
    local panel = NewPage("keep", "Keep Bags Open", true)
    AddNote(panel, "Reopens bags when the game closes them. Bags you close yourself stay closed.")
    if not EspiUtils.ready.keep then return ModuleOff(panel, "keep") end
    local keep = EspiUtils.Keep
    AddCheck(panel, "Keep bags open", "Turning it on keeps whatever bags are open right now.",
        function() return keep.GetSettings().enabled end,
        keep.SetEnabled)
    AddDefaults(panel, function() keep.SetEnabled(true) end)
end

local function BuildQuests()
    local panel = NewPage("quests", "Quest Tracker", true)
    AddNote(panel, "Sorts the quest tracker by quest level, lowest first. Off leaves the tracker in the game's order.")
    local qs = EspiUtils.QuestSort
    AddCheck(panel, "Sort tracked quests by level", nil,
        function() return qs.GetSettings().enabled end,
        qs.SetEnabled)
    AddDefaults(panel, function() qs.SetEnabled(false) end)
end

local function BuildMouseover()
    local panel = NewPage("mouseover", "Mouseover Macros", true)
    AddNote(panel, "Keeps a mouseover cast macro (named \"MO <spell>\") for each spell in this class's list. The list is shared by your characters of the same class; macros are per character. Changes made in combat apply when it ends.")
    if not EspiUtils.ready.mouseover then return ModuleOff(panel, "mouseover") end
    local mo = EspiUtils.Mouseover

    local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    box:SetSize(360, 20)
    box:SetPoint("TOPLEFT", 22, panel.y)
    box:SetAutoFocus(false)
    box:SetMaxLetters(200)
    Tooltip(box, "Spell names separated by commas. Shift-click spells in the spellbook to insert them.")
    panel.y = panel.y - 30

    local listText
    local function refreshList()
        local spells = mo.GetList()
        if not spells or #spells == 0 then
            listText:SetText("List is empty.")
            return
        end
        local lines = {}
        for _, e in ipairs(spells) do
            lines[#lines + 1] = ("%s (%s)"):format(e.name, mo.LABEL[e.kind] or "?")
        end
        listText:SetText(table.concat(lines, "\n"))
    end

    local function act(fn)
        return function()
            local text = strtrim(box:GetText() or "")
            if text ~= "" then
                fn(text)
                box:SetText("")
                box:ClearFocus()
                refreshList()
            end
        end
    end
    AddButtons(panel, {
        { label = "Add friendly", width = 110, tip = "Mouseover friendly, falls back to your target.",
          onClick = act(function(t) mo.Add("add", t) end) },
        { label = "Add hostile", width = 110, tip = "Mouseover hostile, falls back to your target.",
          onClick = act(function(t) mo.Add("harm", t) end) },
        { label = "Remove", width = 90, onClick = act(function(t) mo.Remove(t) end) },
        { label = "Sync now", width = 90, onClick = mo.Sync },
    })

    AddHeader(panel, "Spells for this class")
    listText = AddNote(panel, "")
    listText:SetJustifyV("TOP")
    panel.refreshers[#panel.refreshers + 1] = refreshList
end

-- Registration ---------------------------------------------------------------

local function Register(main)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local ok, err = pcall(function()
            local category = Settings.RegisterCanvasLayoutCategory(main, main.name)
            main.category = category
            for _, panel in ipairs(ordered) do
                panel.category = Settings.RegisterCanvasLayoutSubcategory(category, panel, panel.name)
            end
            Settings.RegisterAddOnCategory(category)
        end)
        if ok then return end
        EspiUtils.Print("Couldn't register the settings panel: " .. tostring(err))
    end
    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(main)
        for _, panel in ipairs(ordered) do
            panel.parent = main.name
            InterfaceOptions_AddCategory(panel)
        end
    end
end

function EspiUtils.InitializeOptions()
    local main = BuildMain()
    BuildFood()
    BuildRebuff()
    BuildTimed()
    BuildBags()
    BuildKeep()
    BuildQuests()
    BuildMouseover()
    Register(main)
end

-- key: "main", "food", "rebuff", "timed", "bags", "keep", "quests" or "mouseover"
function EspiUtils.OpenOptions(key)
    local panel = pages[key or "main"] or pages.main
    if not panel then return end
    if InCombatLockdown() then
        EspiUtils.Print("Settings can't be opened in combat.")
        return
    end
    local target = panel.category or pages.main.category
    if target and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(target:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- Known quirk: the first call can land on the wrong page.
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    else
        EspiUtils.Print("No settings window on this client; use /espiutils for the commands.")
    end
end
