local _, EspiUtils = ...

-- Options screen: a main page plus one subpage per feature, in the game's
-- Settings window (Esc > Options > AddOns). Built from plain frames so it
-- works on both the retail and WoW Forever clients.

local PAGE_WIDTH = 560
local DISCORD_URL = "https://discord.gg/6QXzmaSjW"
local GITHUB_ISSUES_URL = "https://github.com/joshespi/EspiUtils/issues"
local BTC_ADDRESS = "bc1q3742790fs0xe93nlcj3e4ta5m0fenykkt5euqq"
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
    -- The Settings window can show a page without firing OnShow the first time,
    -- so also use its own refresh hook.
    panel:SetScript("OnShow", RefreshPanel)
    panel.OnRefresh = RefreshPanel
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

-- A read-only box that selects its text on focus so it can be copied.
local function AddCopyBox(panel, value, width)
    local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    box:SetSize(width, 20)
    box:SetPoint("TOPLEFT", 22, panel.y)
    box:SetAutoFocus(false)
    local function reset() box:SetText(value) box:HighlightText() end
    box:SetScript("OnEditFocusGained", reset)
    box:SetScript("OnTextChanged", function(_, user) if user then reset() end end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetText(value)
    box:SetCursorPosition(0)
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
    label = "Move banner",
    tip = "Show the alert banner to drag and resize (scroll over it). Right-click it to lock. The position is shared by all characters.",
    onClick = function()
        -- The Settings window would cover the reminders, so close it to drag.
        if EspiUtils.ToggleTileMove() and SettingsPanel and SettingsPanel:IsShown() then
            HideUIPanel(SettingsPanel)
        end
    end,
}

local RESET_POSITION_BUTTON = {
    label = "Reset position",
    tip = "Default position and size for the alert banner. Shared by every alert.",
    onClick = EspiUtils.Banner.ResetPosition,
}

-- Button spec that runs a preview function; false means it couldn't show.
local function PreviewButton(preview, label, width, tip)
    return { label = label or "Preview", width = width, tip = tip, onClick = function()
        if not preview() then
            EspiUtils.Print("Preview available while alive and out of combat.")
        end
    end }
end

-- Pages ----------------------------------------------------------------------

local function BuildMain()
    local panel = NewPage("main", "Espi Utils")
    AddNote(panel, "Small quality-of-life tools. Pick a page on the left. Everything is also available from chat: /espiutils with no arguments lists the commands.")
    AddNote(panel, "Pages:\n- Food Reminder\n- Class Rebuff\n- Timed Reminders (posture, water)\n- Bag Rules (custom Clean Up)\n- Keep Bags Open\n- Quest Tracker\n- Mouseover Macros\n- Bewsh (level-up notification)")
    AddHeader(panel, "All reminders")
    local general = EspiUtils.General
    for _, c in ipairs({
        { "sound", "Play a sound when a reminder appears", "Off by default." },
        { "hideMounted", "Hide while mounted", "Reminders return when you dismount." },
        { "hidePvP", "Hide in battlegrounds and arenas", nil },
        { "timedHideInstances", "Hide posture and water reminders in instances", "Well Fed and rebuff reminders are not affected." },
    }) do
        local key = c[1]
        AddCheck(panel, c[2], c[3],
            function() return general.GetSettings()[key] end,
            function(on) general.Set(key, on) end)
    end
    AddButtons(panel, {
        { label = "Test sound", width = 110, onClick = general.PlaySound },
        PreviewButton(EspiUtils.Banner.Test, "Test banner", 110,
            "Queue three sample alerts to see them appear one after another."),
        MOVE_BUTTON,
        { label = "Reset all", width = 110,
          tip = "Default settings for these options and default positions and sizes for every reminder.",
          onClick = function()
              general.Reset()
              EspiUtils.Tiles.Reset()
              EspiUtils.RefreshOptions()
          end },
    })
    AddHeader(panel, "Feature requests and bug reports")
    AddNote(panel, "Join the Discord (click the box, Ctrl+C to copy, paste into your browser):")
    AddCopyBox(panel, DISCORD_URL, 300)
    AddNote(panel, "Or report bugs on GitHub:")
    AddCopyBox(panel, GITHUB_ISSUES_URL, 380)
    AddHeader(panel, "Support the addon")
    AddNote(panel, "Optional. Bitcoin (BTC) donation address:")
    AddCopyBox(panel, BTC_ADDRESS, 380)
    return panel
end

local function AddReminderActions(panel, api)
    AddButtons(panel, { PreviewButton(api.Preview), MOVE_BUTTON, RESET_POSITION_BUTTON })
    AddDefaults(panel, api.ResetDefaults)
end

-- Shared page body for the Food and Rebuff reminders.
local function AddBuffControls(panel, api, enableLabel)
    AddCheck(panel, enableLabel, nil,
        function() return api.GetSettings().enabled end,
        api.SetEnabled)
    AddCheck(panel, "Hide in rested areas", "Hide the reminder in cities and inns.",
        function() return api.GetSettings().hideResting end,
        api.SetHideResting)
    AddNumber(panel, "Expiry warning (seconds, 0 = missing only)",
        ("Whole number from 0 to %d."):format(api.MAX_LEAD),
        function() return api.GetSettings().lead end,
        api.SetLead)
    AddReminderActions(panel, api)
end

local function BuildFood()
    local panel = NewPage("food", "Food Reminder", true)
    AddNote(panel, "Shows a reminder when the Well Fed buff is missing or about to run out.")
    AddBuffControls(panel, EspiUtils.Food, "Enable food reminder")
end

local function BuildRebuff()
    local panel = NewPage("rebuff", "Class Rebuff", true)
    AddNote(panel, "Reminds you to recast your class buffs (Fortitude, Arcane Intellect, Mark of the Wild, Battle Shout, armors) when they are missing or about to run out. Paladins are warned when a blessing they cast is running low.")
    local rebuff = EspiUtils.Rebuff
    if not rebuff.HasBuffs() then
        AddNote(panel, "No buffs are tracked for this character's class.")
        return
    end
    AddBuffControls(panel, rebuff, "Enable rebuff reminder")
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
            PreviewButton(function() return EspiUtils.TestTimedReminder(command) end),
        })
    end
    AddHeader(panel, "Position")
    AddButtons(panel, { MOVE_BUTTON, RESET_POSITION_BUTTON })
    AddDefaults(panel, EspiUtils.ResetTimedReminders)
end

local function AddBagOrder(panel, bags)
    local rowHeight, headerHeight, groupGap, listWidth = 23, 24, 5, 330
    local sides = bags.Sides
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, panel.y)
    scroll:SetPoint("BOTTOMLEFT", 16, 16)
    scroll:SetWidth(listWidth)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(listWidth, 1)
    scroll:SetScrollChild(content)

    local marker = content:CreateTexture(nil, "OVERLAY")
    marker:SetSize(listWidth, 2)
    marker:SetColorTexture(1, 0.82, 0, 1)
    marker:Hide()

    local rows, groups = {}, {}
    local dragged

    -- cursor position in UI units, plus the list's top and bottom edges
    local function CursorPosition()
        local x, y = GetCursorPosition()
        local scale = scroll:GetEffectiveScale()
        local top, bottom = scroll:GetTop(), scroll:GetBottom()
        if not (top and bottom) then return end
        return x / scale, y / scale, top, bottom
    end

    local function CursorInList()
        local x, y, top, bottom = CursorPosition()
        if not x then return end
        local left, right = scroll:GetLeft(), scroll:GetRight()
        if x < left or x > right or y < bottom or y > top then return end
        return y, top
    end

    local function DropTarget()
        local y, top = CursorInList()
        if not y then return end
        local offset = top - y + scroll:GetVerticalScroll()
        local order = bags.GetSettings().order
        for position, side in ipairs(sides) do
            local group = groups[side]
            -- the gap between groups belongs to the group above; the last takes the rest
            if offset >= group.start and (offset <= group.finish + groupGap or position == #sides) then
                local index = 1
                for slot, section in ipairs(order[side]) do
                    local rowTop = group.start + headerHeight + (slot - 1) * rowHeight
                    if section ~= dragged.section then
                        if offset < rowTop + rowHeight / 2 then return side, index, rowTop end
                        index = index + 1
                    end
                end
                local line = #order[side] > 0 and group.finish or group.start + headerHeight
                return side, index, line
            end
        end
    end

    local function StopDrag()
        if dragged then dragged:SetAlpha(1) end
        dragged = nil
        marker:Hide()
        scroll:SetScript("OnUpdate", nil)
    end

    local function Refresh()
        StopDrag()
        local db, offset = bags.GetSettings(), 0
        for _, side in ipairs(sides) do
            local group, order = groups[side], db.order[side]
            group.start = offset
            group.header:ClearAllPoints()
            group.header:SetPoint("TOPLEFT", 2, -offset - 3)
            offset = offset + headerHeight
            group.empty:ClearAllPoints()
            group.empty:SetPoint("TOPLEFT", 24, -offset - 3)
            group.empty:SetShown(#order == 0)
            for _, section in ipairs(order) do
                local row = rows[section]
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -offset)
                if row.check then row.check:SetChecked(db[row.setting]) end
                offset = offset + rowHeight
            end
            if #order == 0 then offset = offset + rowHeight end
            group.finish = offset
            offset = offset + groupGap
        end
        content:SetHeight(offset)
    end

    local function UpdateDrag(_, elapsed)
        local _, y, top, bottom = CursorPosition()
        if y then -- scrolls while the cursor is at or past the list's top or bottom edge
            local offset = scroll:GetVerticalScroll()
            if y > top - 14 then
                scroll:SetVerticalScroll(math.max(0, offset - elapsed * 160))
            elseif y < bottom + 14 then
                scroll:SetVerticalScroll(math.min(scroll:GetVerticalScrollRange(), offset + elapsed * 160))
            end
        end
        local side, _, line = DropTarget()
        marker:SetShown(side ~= nil)
        if side then
            marker:ClearAllPoints()
            marker:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -line + 1)
        end
    end

    for _, side in ipairs(sides) do
        local header = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        header:SetText(side == "top" and "Top" or "Bottom")
        local empty = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
        empty:SetText("Drop a group here")
        groups[side] = { header = header, empty = empty }
    end

    for section, info in ipairs(bags.Sections) do
        local row = CreateFrame("Button", nil, content)
        row:SetSize(listWidth, rowHeight)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.section, row.setting = section, info.setting
        local grip = row:CreateFontString(nil, "ARTWORK", "GameFontDisable")
        grip:SetPoint("LEFT", 4, 0)
        grip:SetText("::")
        local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("LEFT", 24, 0)
        label:SetText(info.name)
        if info.setting then
            local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            check:SetSize(22, 22)
            check:SetPoint("RIGHT", -4, 0)
            check:SetScript("OnClick", function(self)
                bags.GetSettings()[row.setting] = self:GetChecked() and true or false
            end)
            Tooltip(check, info.tip or "Give " .. info.name .. " its own sorting group.")
            row.check = check
        end
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnDragStart", function(self)
            dragged = self
            self:SetAlpha(0.5)
            scroll:SetScript("OnUpdate", UpdateDrag)
            UpdateDrag(scroll, 0)
        end)
        row:SetScript("OnDragStop", function(self)
            if dragged ~= self then return end
            local side, index = DropTarget()
            if side then bags.MoveSection(self.section, side, index) end
            Refresh()
        end)
        rows[section] = row
    end

    panel:HookScript("OnHide", StopDrag)
    panel.refreshers[#panel.refreshers + 1] = Refresh
    Refresh()
end

local function BuildBags()
    local panel = NewPage("bags", "Bag Rules", true)
    if not EspiUtils.ready.bags then return ModuleOff(panel, "bags") end
    AddNote(panel, "Drag groups to set their order. Top starts at the first slot and Bottom ends at the last. Shift-click Clean Up for Blizzard's sort.")
    local bags = EspiUtils.Bags
    for _, c in ipairs({
        { "enabled", "Clean Up button uses this sort", "Off: the button runs Blizzard's sort." },
        { "depositReagents", "Deposit reagents when the bank is open", "Clean Up first sends crafting reagents to the bank, then sorts the rest." },
        { "questToJunk", "Sort quest items with junk", "With Junk enabled, quest items follow grey items in that group." },
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
    AddBagOrder(panel, bags)
end

local function BuildKeep()
    local panel = NewPage("keep", "Keep Bags Open", true)
    AddNote(panel, "Reopens bags when the game closes them. Bags you close yourself stay closed.")
    if not EspiUtils.ready.keep then return ModuleOff(panel, "keep") end
    local keep = EspiUtils.Keep
    AddCheck(panel, "Keep bags open", "Turning it on keeps whatever bags are open right now.",
        function() return keep.GetSettings().enabled end,
        keep.SetEnabled)
    AddCheck(panel, "Include reagent bag", "Off leaves the reagent bag alone: it is not reopened and not saved as kept.",
        function() return keep.GetSettings().reagent end,
        keep.SetReagent)
    AddDefaults(panel, function()
        keep.SetReagent(true)
        keep.SetEnabled(true)
    end)
end

local function BuildQuests()
    local panel = NewPage("quests", "Quest Tracker", true)
    AddNote(panel, "Sorts the quest tracker by quest level, lowest first. Off leaves the tracker in the game's order.")
    local qs = EspiUtils.QuestSort
    AddCheck(panel, "Sort tracked quests by level", nil,
        function() return qs.GetSettings().enabled end,
        qs.SetEnabled)
    AddNote(panel, "Untrack every tracked quest that is yellow, orange or red for your level, keeping only green and grey ones.")
    AddButtons(panel, {
        { label = "Untrack non-green quests", width = 180, onClick = qs.KeepEasy,
          tip = "Quests you haven't tracked are not added." },
    })
    AddDefaults(panel, function() qs.SetEnabled(false) end)
end

local function BuildBewsh()
    local panel = NewPage("bewsh", "Bewsh (Level Up)", true)
    local bewsh = EspiUtils.Bewsh
    AddNote(panel, "Shows \"You bewshed!\" when you level up. Hover over it for the story.")
    AddNote(panel, "|cffffd100Why bewsh?|r " .. bewsh.Story)
    for _, c in ipairs({
        { "enabled", "Enable Bewsh on level up", "Turns on the alert and any chat posts you select below." },
        { "guild", "Post \"bewsh\" to guild (needs Enable)", "Sends \"bewsh (<level>)\" to guild chat instead of you typing ding." },
        { "party", "Post \"bewsh\" to group chat (needs Enable)", "Sends \"bewsh (<level>)\" to your party or raid, or to instance chat if you only have a matchmaking group. If chat is locked, it is sent after combat." },
    }) do
        local key = c[1]
        AddCheck(panel, c[2], c[3],
            function() return bewsh.GetSettings()[key] end,
            function(on) bewsh.Set(key, on) end)
    end
    AddReminderActions(panel, bewsh)
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
    panel.y = panel.y - 30

    local refreshList
    local function act(cmd)
        return function()
            local text = strtrim(box:GetText())
            if text ~= "" then
                if mo.Add(cmd, text) then
                    box:SetText("")
                    box:ClearFocus()
                    refreshList()
                end
            end
        end
    end
    local picker
    local function openPicker()
        if picker then
            picker:SetShown(not picker:IsShown())
            if picker:IsShown() then picker.refresh() end
            return
        end
        picker = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
        picker:SetSize(380, 440)
        picker:SetPoint("CENTER")
        picker:SetFrameStrata("DIALOG")
        picker:SetMovable(true)
        picker:EnableMouse(true)
        picker:RegisterForDrag("LeftButton")
        picker:SetScript("OnDragStart", picker.StartMoving)
        picker:SetScript("OnDragStop", picker.StopMovingOrSizing)
        picker.TitleText:SetText("Pick spells")
        table.insert(UISpecialFrames, "EspiUtilsSpellPicker")
        _G.EspiUtilsSpellPicker = picker

        local search = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
        search:SetSize(330, 20)
        search:SetPoint("TOPLEFT", 18, -34)
        search:SetAutoFocus(false)
        search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        local scroll = CreateFrame("ScrollFrame", nil, picker, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -62)
        scroll:SetPoint("BOTTOMRIGHT", -32, 10)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(320, 1)
        scroll:SetScrollChild(content)

        local ROW = 26
        local prow = {}
        local function makePickRow(i)
            local row = CreateFrame("Frame", nil, content)
            row:SetSize(320, ROW)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(20, 20)
            row.icon:SetPoint("LEFT", 2, 0)
            row.hostile = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.hostile:SetSize(56, 22)
            row.hostile:SetPoint("RIGHT", -2, 0)
            row.hostile:SetText("Hostile")
            row.friendly = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.friendly:SetSize(56, 22)
            row.friendly:SetPoint("RIGHT", row.hostile, "LEFT", -2, 0)
            row.friendly:SetText("Friendly")
            row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.label:SetPoint("RIGHT", row.friendly, "LEFT", -4, 0)
            row.label:SetJustifyH("LEFT")
            local function pick(cmd)
                return function()
                    if mo.Add(cmd, row.spell) then
                        refreshList()
                        picker.refresh()
                    end
                end
            end
            row.friendly:SetScript("OnClick", pick("add"))
            row.hostile:SetScript("OnClick", pick("harm"))
            prow[i] = row
            return row
        end

        picker.refresh = function()
            local q = strtrim(search:GetText()):lower()
            local n = 0
            for _, e in ipairs(mo.GetSpellbook()) do
                if q == "" or e.name:lower():find(q, 1, true) then
                    n = n + 1
                    local row = prow[n] or makePickRow(n)
                    row.spell = e.name
                    row.icon:SetTexture(e.icon)
                    row.label:SetText(e.name)
                    local shade = mo.Has(e.name) and 0.5 or 1 -- dim spells already in the list
                    row.label:SetTextColor(shade, shade, shade)
                    row:Show()
                end
            end
            for i = n + 1, #prow do prow[i]:Hide() end
            content:SetHeight(math.max(1, n * ROW))
        end
        search:SetScript("OnTextChanged", function() picker.refresh() end)
        picker.refresh()
    end

    local addFriendly = act("add")
    box:SetScript("OnEnterPressed", addFriendly)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    AddNote(panel, "Type spell names (comma separated) or shift-click them in the spellbook, then press Enter (adds as friendly) or pick a button.")
    AddButtons(panel, {
        { label = "Add friendly", width = 110, tip = "Mouseover friendly, falls back to your target.",
          onClick = addFriendly },
        { label = "Add hostile", width = 110, tip = "Mouseover hostile, falls back to your target.",
          onClick = act("harm") },
        { label = "Pick spells", width = 90, tip = "Choose from your spellbook.", onClick = openPicker },
        { label = "Sync now", width = 90, onClick = mo.Sync },
    })

    AddHeader(panel, "Spells for this class")
    local listTop = panel.y
    local emptyText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    emptyText:SetPoint("TOPLEFT", 16, listTop)
    emptyText:SetText("No spells yet. Add one above.")

    local ROW_HEIGHT = 24
    local rows = {}
    local function makeRow(i)
        local row = CreateFrame("Frame", nil, panel)
        row:SetSize(PAGE_WIDTH, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 16, listTop - (i - 1) * ROW_HEIGHT)

        row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.remove:SetSize(24, 22)
        row.remove:SetPoint("LEFT", 0, 0)
        row.remove:SetText("X")
        row.remove:SetScript("OnClick", function()
            mo.Remove(row.entry.name)
            refreshList()
        end)
        Tooltip(row.remove, "Remove this spell and delete its macro.")

        row.kind = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.kind:SetSize(80, 22)
        row.kind:SetPoint("LEFT", row.remove, "RIGHT", 4, 0)
        row.kind:SetScript("OnClick", function()
            mo.SetKind(row.entry.name, row.entry.kind == "help" and "harm" or "help")
            refreshList()
        end)
        Tooltip(row.kind, "Click to switch between friendly and hostile.")

        row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.label:SetPoint("LEFT", row.kind, "RIGHT", 8, 0)
        rows[i] = row
        return row
    end

    refreshList = function()
        local spells = mo.GetList() or {}
        emptyText:SetShown(#spells == 0)
        for i, e in ipairs(spells) do
            local row = rows[i] or makeRow(i)
            row.entry = e
            row.label:SetText(e.name)
            row.kind:SetText(mo.LABEL[e.kind] or "?")
            row:Show()
        end
        for i = #spells + 1, #rows do
            rows[i]:Hide()
        end
    end
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
    BuildBewsh()
    Register(main)
    -- Fill every control now so a page never starts blank.
    EspiUtils.RefreshOptions()
end

-- Re-reads every page's controls after settings changed from outside the page.
function EspiUtils.RefreshOptions()
    for _, panel in pairs(pages) do RefreshPanel(panel) end
end

-- key: "main", "food", "rebuff", "timed", "bags", "keep", "quests", "mouseover" or "bewsh"
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
