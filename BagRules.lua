local _, EspiUtils = ...

local STEP_INTERVAL = 0.05 -- seconds between move-engine steps
local LOCK_TIMEOUT = 3     -- seconds to wait for item locks to clear
local MAX_PASSES = 60
local ROW_TOL = 2          -- px; button tops are floats
local LOG_MAX = 200        -- lines kept in EspiUtilsAccountDB.bags.log
local LOG_SLACK = 50       -- the log may grow this far past LOG_MAX before it is trimmed
local LOG_SHOW = 15        -- lines "/espiutils bags log" prints

local defaults = {
    enabled = true,  -- Clean Up button uses the Espi Utils sort
    depositReagents = false, -- Clean Up at an open bank deposits crafting reagents first
    hearthFirst = false, -- group the standard Hearthstone separately (key kept for saved settings)
    camping = true,  -- camping items get their own section at the front
    tools = true,    -- profession and rogue tools get their own section
    setGear = true,  -- equipment-set gear is grouped together
    toyGear = true,  -- use-effect gear sorts like a toy
    heirloom = true, -- heirlooms get their own section
    conjured = true, -- conjured items get their own section
    splitBound = true, -- bound gear separate from tradeable (BoE) gear
    junk = true,     -- grey items get their own section
    questItems = true, -- quest items get their own section
    debug = false,   -- per-pass detail in chat and the log
}

local db

local Print = EspiUtils.Printer("Bags", "66ccff")

-- run history in EspiUtilsAccountDB.bags.log; WoW writes it to disk on /reload or logout
local function Log(msg)
    local log = db.log
    log[#log + 1] = date("%m-%d %H:%M:%S ") .. msg
    -- Trim in batches: one shift per LOG_SLACK lines instead of one per line.
    local n = #log
    if n > LOG_MAX + LOG_SLACK then
        local drop = n - LOG_MAX
        for i = 1, LOG_MAX do log[i] = log[i + drop] end
        for i = n, LOG_MAX + 1, -1 do log[i] = nil end
    end
end

local function Say(msg)
    Log(msg)
    Print(msg)
end

-- Formats only when debug is on, so per-move calls cost nothing otherwise.
local function Debug(fmt, ...)
    if db.debug then Say(fmt:format(...)) end
end

local frame = CreateFrame("Frame")

-- Classification ------------------------------------------------------------

-- Section indices determine layout order. Pinned sections go in the last slots.
-- New sections take the next index: saved orders store these numbers.
local HEARTH, CAMPING, TOOLS, SETGEAR, TOYGEAR, HEIRLOOM, OTHER, BOE, CONJURED, JUNK, BOUND, QUEST =
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12

-- setting: the on/off key in db; command: the /espiutils bags word that toggles it;
-- desc: what it does, for that command's reply.
local SECTIONS = {
    [HEARTH] = { name = "Hearthstone", setting = "hearthFirst", command = "hearth", desc = "Hearthstone group",
        tip = "The standard Hearthstone gets its own group." },
    [CAMPING] = { name = "Camping", setting = "camping", command = "camping", desc = "camping items in their own section" },
    [TOOLS] = { name = "Tools", setting = "tools", command = "tools", desc = "tools in their own section" },
    [SETGEAR] = { name = "Equipment Sets", setting = "setGear", command = "sets", desc = "equipment-set gear grouped together" },
    [TOYGEAR] = { name = "Use-Effect Gear", setting = "toyGear", command = "toys", desc = "use-effect gear sorted like a toy",
        tip = "Group gear kept for its Use effect, like guild teleport cloaks." },
    [HEIRLOOM] = { name = "Heirlooms", setting = "heirloom", command = "heirloom", desc = "heirlooms in their own section" },
    [OTHER] = { name = "Other" },
    [BOE] = { name = "Tradeable Gear" },
    [CONJURED] = { name = "Conjured", setting = "conjured", command = "conjured", desc = "conjured items in their own group" },
    [JUNK] = { name = "Junk", setting = "junk", command = "junk", desc = "grey items in their own group" },
    [BOUND] = { name = "Bound Gear", setting = "splitBound", command = "bound", desc = "bound gear separate from tradeable gear",
        tip = "Off groups bound and tradeable gear together." },
    [QUEST] = { name = "Quest Items", setting = "questItems", command = "quest", desc = "quest items in their own group",
        tip = "Off sorts quest items in Other." },
}

local SIDES = { "top", "bottom" }

local function DefaultOrder(pin)
    local order = { top = {}, bottom = {} }
    for section in ipairs(SECTIONS) do
        local side = pin and section >= CONJURED and section <= BOUND and "bottom" or "top"
        table.insert(order[side], section)
    end
    return order
end

-- Returns true when every entry is a known, unique section. Also appends
-- sections missing from the saved order (added in a later version) to the top,
-- and returns them as a set.
local function NormalizeOrder(order)
    if type(order) ~= "table" then return false end
    local seen = {}
    for _, side in ipairs(SIDES) do
        local list = order[side]
        if type(list) ~= "table" then return false end
        local count = 0
        for _ in pairs(list) do count = count + 1 end
        if count ~= #list then return false end -- holes or stray keys
        for _, section in ipairs(list) do
            if type(section) ~= "number" or not SECTIONS[section] or seen[section] then return false end
            seen[section] = true
        end
    end
    local added = {}
    for section in ipairs(SECTIONS) do
        if not seen[section] then
            table.insert(order.top, section)
            added[section] = true
        end
    end
    return true, added
end

local function FindSection(section)
    for _, side in ipairs(SIDES) do
        for index, id in ipairs(db.order[side]) do
            if id == section then return side, index end
        end
    end
end

local function MoveSection(section, side, index)
    local from, at = FindSection(section)
    if not from then return end
    table.remove(db.order[from], at)
    table.insert(db.order[side], index, section)
end

local function SortLayout()
    local layout = { rank = {}, bottom = {} }
    local rank = 0
    for _, side in ipairs(SIDES) do
        for _, section in ipairs(db.order[side]) do
            rank = rank + 1
            layout.rank[section] = rank
            layout.bottom[section] = side == "bottom"
        end
    end
    return layout
end

local HEARTHSTONE_ID = 6948

-- WoW Forever campfire kits and camp features:
-- https://www.wowhead.com/forever/guide/camping-overview-unlock-rewards
local CAMPING_IDS = {
    [279981] = true, [279961] = true, [279974] = true, -- Basic, Journeyman, Expert Campfire Kits
    [279957] = true, [279982] = true, -- Cookie's Feast, Iron Oven
    [279956] = true, [279970] = true, [279990] = true, -- Mana Well, Fermenter, Alchemy Laboratory
    [279944] = true, [279988] = true, [279955] = true, -- Sharpening Wheel, Anvil, Master Forge
    [279976] = true, [279985] = true, [279987] = true, -- Enchanted Lute, Arcane Salvager, Arcane Forge
    [279950] = true, [279949] = true, [279989] = true, -- Reagent Bot, Repair Bot, Anarchist's Workbench
    [279962] = true, [279964] = true, [279947] = true, -- Incense Candle, Greenhouse, Seed Hybridizer
    [279978] = true, [279941] = true, [279945] = true, -- Camp Tent, Tanning Rack, Sewing Machine
    [279960] = true, [279948] = true, [279952] = true, -- Lodestone, Rock Garden, Molten Foundry
    [279979] = true, [279969] = true, [279938] = true, -- Camp Chair, Field Guide, Trapper's Workbench
    [279972] = true, [279973] = true, -- Faction Banners (Horde and Alliance)
    [279943] = true, [279959] = true, -- Spinning Wheel, Loom
    [279968] = true, [279940] = true, [279951] = true, -- First Aid Kit, Toxin Study, Plague Doctor's Laboratory
    [279967] = true, [279965] = true, [279966] = true, -- Fish Bowl, Fishing Rack, Fishing Hut
    -- not in the guide above:
    [211527] = true, -- Cozy Sleeping Bag
    [289439] = true, -- Pouch of Violet Dust
}

-- profession and rogue tools, kept near the front for easy access. Newer tools are
-- ItemClass.Profession and fishing poles are a weapon subclass; these are the classic ones
-- (some are typed as weapons or misc, so they're matched by ID).
local TOOL_IDS = {
    [2901] = true,  -- Mining Pick
    [5956] = true,  -- Blacksmith Hammer
    [7005] = true,  -- Skinning Knife
    [6219] = true,  -- Arclight Spanner
    [5060] = true,  -- Thieves' Tools
    [6218] = true, [6339] = true, [11130] = true, [11145] = true, [16207] = true, -- Runed Copper..Arcanite Rod
    [20815] = true, -- Jeweler's Kit
    [20824] = true, -- Simple Grinder
}

-- gear kept for its Use effect, not to wear: sorts like a toy
local TOYGEAR_IDS = {
    [63352] = true, [63353] = true, -- Shroud of Cooperation (Alliance, Horde)
    [63206] = true, [63207] = true, -- Wrap of Unity (Alliance, Horde)
    [65360] = true, [65274] = true, -- Cloak of Coordination (Alliance, Horde)
}

local SLOT_ORDER = {
    INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_CLOAK = 4,
    INVTYPE_CHEST = 5, INVTYPE_ROBE = 5, INVTYPE_BODY = 6, INVTYPE_TABARD = 7,
    INVTYPE_WRIST = 8, INVTYPE_HAND = 9, INVTYPE_WAIST = 10, INVTYPE_LEGS = 11,
    INVTYPE_FEET = 12, INVTYPE_FINGER = 13, INVTYPE_TRINKET = 14,
    INVTYPE_WEAPON = 15, INVTYPE_2HWEAPON = 15, INVTYPE_WEAPONMAINHAND = 15,
    INVTYPE_RANGED = 15, INVTYPE_RANGEDRIGHT = 15,
    INVTYPE_WEAPONOFFHAND = 16, INVTYPE_SHIELD = 16, INVTYPE_HOLDABLE = 16,
}

-- Warbound by the item's bind type. Not ToBnetAccountUntilEquipped: once worn that's soulbound,
-- so it's checked on the bag slot instead.
local WARBOUND = {}
if Enum and Enum.ItemBind then
    if Enum.ItemBind.ToWoWAccount then WARBOUND[Enum.ItemBind.ToWoWAccount] = true end
    if Enum.ItemBind.ToBnetAccount then WARBOUND[Enum.ItemBind.ToBnetAccount] = true end
end

-- gear you can still trade or send to an alt sorts as BoE: unbound, Warbound, or Warbound
-- until equipped (loc is the item's bag slot)
local function IsTradeable(info, static, loc)
    return not info.isBound or WARBOUND[static.bindType]
        or (C_Item.IsBoundToAccountUntilEquip and C_Item.IsBoundToAccountUntilEquip(loc))
end

-- no API for this: the tooltip's "Conjured Item" line is the only signal
local conjured = {} -- itemID -> bool
local function IsConjuredLine(text) return text == ITEM_CONJURED end
local function IsConjured(bag, slot, itemID)
    if conjured[itemID] == nil then
        -- nil: not loaded; retry next pass
        conjured[itemID] = EspiUtils.BagTooltipMatches(bag, slot, IsConjuredLine)
    end
    return conjured[itemID] == true
end

local FISHING_POLE = Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole or 20
local function IsTool(itemID, classID, subClassID)
    return TOOL_IDS[itemID] == true
        or (Enum.ItemClass.Profession ~= nil and classID == Enum.ItemClass.Profession)
        or (classID == Enum.ItemClass.Weapon and subClassID == FISHING_POLE)
end

local function IsQuestItem(bag, slot, classID)
    if classID == Enum.ItemClass.Questitem then return true end
    if C_Container.GetContainerItemQuestInfo then
        local q = C_Container.GetContainerItemQuestInfo(bag, slot)
        return q ~= nil and q.isQuestItem == true
    end
    return false
end

local function IsGear(classID, equipLoc)
    return (classID == Enum.ItemClass.Weapon or classID == Enum.ItemClass.Armor)
        and equipLoc ~= nil and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
end

-- sets in block order (an item's set rank is its index): assigned spec first, then unassigned by name
local function BuildSets()
    local sets = {}
    for _, id in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
        local name = C_EquipmentSet.GetEquipmentSetInfo(id)
        if name then
            sets[#sets + 1] = {
                name = name, lname = name:lower(), needle = ", " .. name .. ", ",
                spec = C_EquipmentSet.GetEquipmentSetAssignedSpec(id),
            }
        end
    end
    table.sort(sets, function(a, b)
        local sa, sb = a.spec or 1000, b.spec or 1000
        if sa ~= sb then return sa < sb end
        if a.lname ~= b.lname then return a.lname < b.lname end
        return a.name < b.name
    end)
    return sets
end

-- lowest rank of any known set named in setList (plain find: names may hold commas);
-- #sets + 1 for a set we don't know by name
local function SetRank(setList, sets)
    local hay = ", " .. setList .. ", "
    for rank, s in ipairs(sets) do
        if hay:find(s.needle, 1, true) then return rank end
    end
    return #sets + 1
end

local loc = ItemLocation and ItemLocation:CreateEmpty() -- reused: Classify never keeps it

local GetItemFamily = C_Item.GetItemFamily or GetItemFamily

-- Static per-item data, looked up once per itemID instead of on every pass.
-- itemID -> { equipLoc, classID, subClassID, reagent, bindType, maxStack, family }
local staticInfo = {}
local function StaticInfo(itemID)
    local s = staticInfo[itemID]
    if not s then
        local _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
        s = { equipLoc = equipLoc, classID = classID, subClassID = subClassID }
        staticInfo[itemID] = s
    end
    -- the fields below are only cached once the item data has loaded
    if s.reagent == nil then
        local name, _, _, _, _, _, _, _, _, _, _, _, _, bindType, _, _, isReagent = C_Item.GetItemInfo(itemID)
        if name then
            s.reagent = isReagent == true
            s.bindType = bindType
        end
    end
    s.maxStack = s.maxStack or C_Item.GetItemMaxStackSizeByID(itemID)
    s.family = s.family or GetItemFamily(itemID)
    return s
end

-- reagent and profession bags use Camping, Tools, Other, Junk and Quest Items
local function Classify(bag, slot, info, sets, general, rules)
    local itemID = info.itemID
    local count = info.stackCount or 1
    local link = info.hyperlink or tostring(itemID)
    local quality = info.quality or 0
    local static = StaticInfo(itemID)
    local equipLoc, classID, subClassID = static.equipLoc, static.classID, static.subClassID
    loc:SetBagAndSlot(bag, slot)
    local gear = IsGear(classID, equipLoc)

    local rec = {
        itemID = itemID, link = link, count = count, key = link .. ":" .. count,
        quality = quality, locked = info.isLocked,
        name = (info.itemName or ""):lower(),
        classID = classID or 0, subClassID = subClassID or 0,
        ilvl = C_Item.GetCurrentItemLevel(loc) or 0,
        slotOrder = gear and SLOT_ORDER[equipLoc] or 99,
        setRank = 0,
        reagent = static.reagent == true, -- isCraftingReagent
        maxStack = static.maxStack, family = static.family or 0,
    }

    if rules.hearthFirst and itemID == HEARTHSTONE_ID then
        rec.section = HEARTH
    elseif rules.camping and CAMPING_IDS[itemID] then
        rec.section = CAMPING
    elseif rules.tools and IsTool(itemID, classID, subClassID) then
        rec.section = TOOLS
    elseif rules.junk and quality == Enum.ItemQuality.Poor then
        rec.section = JUNK
    elseif rules.questItems and IsQuestItem(bag, slot, classID) then
        rec.section = QUEST
    elseif not general then
        rec.section = OTHER
    elseif rules.toyGear and TOYGEAR_IDS[itemID] then
        rec.section = TOYGEAR
    elseif rules.conjured and IsConjured(bag, slot, itemID) then
        rec.section = CONJURED
    elseif not gear then
        rec.section = OTHER
    else
        local inSet, setList
        if rules.setGear then inSet, setList = C_Container.GetContainerItemEquipmentSetInfo(bag, slot) end
        if inSet then
            rec.section = SETGEAR
            rec.setRank = SetRank(setList or "", sets)
        elseif rules.heirloom and quality == Enum.ItemQuality.Heirloom then
            rec.section = HEIRLOOM
        elseif not rules.splitBound or IsTradeable(info, static, loc) then
            rec.section = BOE
        else
            rec.section = BOUND
        end
    end
    return rec
end

local function Compare(a, b, rank)
    if a.section ~= b.section then
        if rank then return rank[a.section] < rank[b.section] end
        return a.section < b.section
    end
    if a.setRank ~= b.setRank then return a.setRank < b.setRank end
    if a.slotOrder ~= b.slotOrder then return a.slotOrder < b.slotOrder end
    if a.classID ~= b.classID then return a.classID < b.classID end
    if a.subClassID ~= b.subClassID then return a.subClassID < b.subClassID end
    if a.quality ~= b.quality then return a.quality > b.quality end
    if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
    if a.name ~= b.name then return a.name < b.name end
    if a.itemID ~= b.itemID then return a.itemID < b.itemID end
    if a.count ~= b.count then return a.count > b.count end
    return a.link < b.link -- equal link and count means equal key: interchangeable
end

-- one record per occupied position; empty positions stay nil (the table has holes)
local function Scan(region, sets, rules)
    local recs = {}
    for i = 1, region.n do
        local s = region.slots[i]
        local info = C_Container.GetContainerItemInfo(s.bag, s.slot)
        if info and info.itemID then
            recs[i] = Classify(s.bag, s.slot, info, sets, region.general, rules)
        end
    end
    return recs
end

-- Regions -------------------------------------------------------------------

local function Ignored(bag)
    if bag == Enum.BagIndex.Backpack then return C_Container.GetBackpackAutosortDisabled() end
    return C_Container.GetBagSlotFlag(bag, Enum.BagSlotFlags.DisableAutoSort)
end

local function UsingCombinedBags()
    return ContainerFrameSettingsManager and ContainerFrameSettingsManager:IsUsingCombinedBags()
end

-- combined bags on but hidden: their on-screen order can't be read
local function CombinedBagsClosed()
    return UsingCombinedBags() and not ContainerFrameCombinedBags:IsShown()
end

-- Reading order of the combined backpack, from the real buttons, and a description of
-- where it came from. Slots the buttons don't cover keep their fallback order at the end.
-- When the screen can't be read: the slot order, nil, and why.
local function DisplayOrder(slots)
    if not UsingCombinedBags() then
        return slots, nil, "combined bags off"
    end
    if CombinedBagsClosed() then -- only if WithBagsShown couldn't open them
        return slots, nil, "bags closed"
    end
    local cf = ContainerFrameCombinedBags

    local byId = {}
    for _, s in ipairs(slots) do byId[s.bag * 1000 + s.slot] = s end

    local btns, seen = {}, {}
    for _, btn in cf:EnumerateValidItems() do
        local bag, slot = btn:GetBagID(), btn:GetID()
        local top, left = btn:GetTop(), btn:GetLeft()
        local s = bag and slot and byId[bag * 1000 + slot]
        if s and top and left and not seen[s] then
            seen[s] = true
            btns[#btns + 1] = { s = s, top = top, left = left }
        end
    end
    table.sort(btns, function(a, b) return a.top > b.top end)

    local out, i = {}, 1
    while i <= #btns do
        local row, rowTop = {}, btns[i].top
        while i <= #btns and rowTop - btns[i].top <= ROW_TOL do
            row[#row + 1] = btns[i]
            i = i + 1
        end
        table.sort(row, function(a, b) return a.left < b.left end)
        for _, e in ipairs(row) do out[#out + 1] = e.s end
    end
    for _, s in ipairs(slots) do
        if not seen[s] then out[#out + 1] = s end
    end
    local missing = #slots - #btns
    return out, missing > 0 and ("screen, %d slots appended"):format(missing) or "screen"
end

local function AllSlots(bag)
    local slots = {}
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
        slots[slot] = { bag = bag, slot = slot }
    end
    return slots
end

local function NewRegion(slots, general, label)
    return { slots = slots, n = #slots, general = general, label = label }
end

-- the general bags share one region (first, in display order); reagent and profession bags sort alone
local function BuildRegions()
    local regions, general = {}, {}
    for bag = Enum.BagIndex.Backpack, Enum.BagIndex.ReagentBag do
        local slots = AllSlots(bag)
        if #slots > 0 and not Ignored(bag) then
            local _, family = C_Container.GetContainerNumFreeSlots(bag)
            if bag ~= Enum.BagIndex.ReagentBag and (family or 0) == 0 then
                for _, s in ipairs(slots) do general[#general + 1] = s end
            else
                local region = NewRegion(slots, false, ("bag %d: %d slots"):format(bag, #slots))
                region.reagent = bag == Enum.BagIndex.ReagentBag
                region.family = family or 0 -- item types the bag accepts (0: no restriction)
                regions[#regions + 1] = region
            end
        end
    end
    if #general > 0 then
        local slots, order, fallback = DisplayOrder(general)
        local region = NewRegion(slots, true, ("general %d slots (%s)"):format(#slots, order or "fallback: " .. fallback))
        region.fallback = fallback
        table.insert(regions, 1, region)
    end
    return regions
end

-- Desired layout ------------------------------------------------------------

-- des[i] is the record that belongs at position i; nil means empty
local function BuildDesired(region, recs, layout)
    local list = {}
    for i = 1, region.n do
        if recs[i] then list[#list + 1] = recs[i] end
    end
    local rank = region.general and layout.rank
    table.sort(list, function(a, b) return Compare(a, b, rank) end)

    local head, tail = {}, {}
    for _, r in ipairs(list) do
        local t = region.general and layout.bottom[r.section] and tail or head
        t[#t + 1] = r
    end
    local des, base = {}, region.n - #tail
    for k, r in ipairs(head) do des[k] = r end
    for k, r in ipairs(tail) do des[base + k] = r end
    return des
end

-- Move engine ---------------------------------------------------------------

local run -- state of the sort in progress; nil when idle

local function Stop(reason)
    if not run then return end
    run.ticker:Cancel()
    if reason then
        Say(("sort stopped: %s (pass %d, %d moves)"):format(reason, run.passes, run.moves))
    end
    run = nil
end

local function Done(stuck)
    local message = "already sorted"
    if run.moves + run.merges > 0 then
        message = ("sorted: %d moves, %d merges, %d passes, %.1fs"):format(
            run.moves, run.merges, run.passes, GetTime() - run.start)
    end
    local locked = stuck > 0 and ("%d locked items not moved"):format(stuck)
    local result = locked and (message .. "; " .. locked) or message
    if db.debug or run.verbose then
        Say(result)
    else
        Log(result)
        if locked then Print(locked) end
    end
    Stop()
end

-- Swap two slots, move into an empty one, or merge (amount splits off just what
-- fits). Anything still in hand after the drop is put back in slot a.
local function Move(a, b, amount)
    if GetCursorInfo() then -- the user grabbed something
        ClearCursor()
        return nil, "something is on your cursor"
    end
    if amount then
        C_Container.SplitContainerItem(a.bag, a.slot, amount)
    else
        C_Container.PickupContainerItem(a.bag, a.slot)
    end
    if not GetCursorInfo() then return nil, "couldn't pick up an item" end
    C_Container.PickupContainerItem(b.bag, b.slot)
    if GetCursorInfo() then
        C_Container.PickupContainerItem(a.bag, a.slot)
        if GetCursorInfo() then
            ClearCursor()
            return nil, "an item got stuck on your cursor"
        end
    end
    run.pending[#run.pending + 1] = a
    run.pending[#run.pending + 1] = b
    return true
end

-- only wait on slots we moved: an item locked by trade or mail mustn't stall the sort
local function PendingLocked()
    for _, s in ipairs(run.pending) do
        local info = C_Container.GetContainerItemInfo(s.bag, s.slot)
        if info and info.isLocked then return true end
    end
    return false
end

-- earliest stack to merge into and a later one to pick up, skipping pairs already tried
local function PickPair(region, g)
    for a = 1, #g - 1 do
        for b = #g, a + 1, -1 do
            local dst, src = region.slots[g[a]], region.slots[g[b]]
            -- bag * 1000 + slot fits well inside 100000, so each pair gets its own number.
            local id = (src.bag * 1000 + src.slot) * 100000 + dst.bag * 1000 + dst.slot
            if not run.tried[id] then
                run.tried[id] = true
                return g[b], g[a]
            end
        end
    end
end

-- one merge per item per pass; returns the merges issued.
-- Grouped by link, not itemID: the same item with different links may not stack.
local function MergeRegion(region, recs)
    local groups, order = {}, {}
    for i = 1, region.n do
        local r = recs[i]
        if r and not r.locked then
            local max = r.maxStack
            if max and r.count < max then
                local g = groups[r.link]
                if not g then
                    g = { max = max }
                    groups[r.link] = g
                    order[#order + 1] = g
                end
                g[#g + 1] = i
            end
        end
    end

    local moves = 0
    for _, g in ipairs(order) do
        local si, di = PickPair(region, g)
        if si then
            local room = g.max - recs[di].count
            local amount = recs[si].count > room and room or nil
            local ok, err = Move(region.slots[si], region.slots[di], amount)
            if not ok then return moves, err end
            moves = moves + 1
        end
    end
    return moves
end

-- Per key, the unlocked slots holding it that aren't already where they belong, in slot order.
local function Sources(region, recs, des)
    local byKey = {}
    for j = 1, region.n do
        local src, target = recs[j], des[j]
        if src and src.key ~= nil and not src.locked and not (target and target.key == src.key) then
            local list = byKey[src.key]
            if not list then
                list = { next = 1 }
                byKey[src.key] = list
            end
            list[#list + 1] = j
        end
    end
    return byKey
end

-- the first unused slot from Sources holding key
local function TakeSource(sources, used, key)
    local list = sources[key]
    if not list then return end
    while list.next <= #list do
        local j = list[list.next]
        list.next = list.next + 1
        if not used[j] then return j end
    end
end

-- swaps each wrong position into place, touching a slot at most once.
-- Returns the moves issued, an error, and the locked items that are out of place.
local function OrderRegion(region, recs)
    local des = BuildDesired(region, recs, run.layout)
    local sources = Sources(region, recs, des)
    local used, moves, stuck = {}, 0, 0
    for i = 1, region.n do
        local want, have = des[i], recs[i]
        if have and have.locked and not (want and want.key == have.key) then
            stuck = stuck + 1
        end
        if want and not used[i] and not (have and have.key == want.key) then
            local j = not (have and have.locked) and TakeSource(sources, used, want.key)
            if j then
                local ok, err = Move(region.slots[j], region.slots[i])
                if not ok then return moves, err end
                moves = moves + 1
                used[i], used[j] = true, true
                Debug("  move %d->%d: %s [sec %d, set %d, ilvl %d] (had %s)",
                    j, i, want.link, want.section, want.setRank, want.ilvl, have and have.link or "empty")
            end
        end
    end
    return moves, nil, stuck
end

-- does the item belong in this special bag? Profession bags (family ~= 0) take their own item
-- types; a family-less reagent bag takes crafting reagents
local function FitsBag(region, r)
    -- keep camping items at the front of the general bags. One already in a special bag stays put:
    -- this pass only fills special bags, it never empties them
    if r.section == CAMPING then return false end
    if region.family ~= 0 then
        return bit.band(r.family, region.family) ~= 0
    end
    return region.reagent and r.reagent
end

-- items in the general bags move into free slots of a reagent or profession bag they fit (like
-- Blizzard's sort); the merge and order passes then work inside that bag. Each source slot is
-- tried once per sort, so an item the bag refuses can't loop. Returns the moves issued.
local function FillSpecialBags(snaps)
    -- BuildRegions puts the general region first when there is one
    local general, gsnap = run.regions[1], snaps[1]
    if not general.general then return 0 end

    local moves = 0
    for ri = 2, #run.regions do
        local special, rsnap, free = run.regions[ri], snaps[ri], 1
        for i = 1, general.n do
            local r = gsnap[i]
            if r and not r.locked and FitsBag(special, r) then
                local s = general.slots[i]
                local id = s.bag .. ":" .. s.slot .. ":" .. r.itemID
                if not run.fillTried[id] then
                    while free <= special.n and rsnap[free] do free = free + 1 end
                    if free > special.n then break end
                    run.fillTried[id] = true
                    local ok, err = Move(s, special.slots[free])
                    if not ok then return moves, err end
                    moves = moves + 1
                    free = free + 1
                end
            end
        end
    end
    return moves
end

local function Step()
    if PendingLocked() then
        local now = GetTime()
        run.lockSince = run.lockSince or now
        if now - run.lockSince > LOCK_TIMEOUT then
            return Stop("timed out waiting for items to unlock")
        end
        return
    end
    run.lockSince = nil
    run.pending = {}

    if run.passes >= MAX_PASSES then
        return Stop("gave up after " .. MAX_PASSES .. " passes")
    end
    run.passes = run.passes + 1

    local snaps, merged = {}, 0
    for i, region in ipairs(run.regions) do
        snaps[i] = Scan(region, run.sets, run.rules)
        local n, err = MergeRegion(region, snaps[i])
        if err then return Stop(err) end
        merged = merged + n
    end
    if merged > 0 then -- let the merges land, then re-snapshot
        run.merges = run.merges + merged
        Debug("pass %d: %d merges", run.passes, merged)
        return
    end

    local filled, ferr = FillSpecialBags(snaps)
    if ferr then return Stop(ferr) end
    if filled > 0 then -- let the moves land, then re-snapshot
        run.moves = run.moves + filled
        Debug("pass %d: %d items to reagent/profession bags", run.passes, filled)
        return
    end

    local moved, stuck = 0, 0
    for i, region in ipairs(run.regions) do
        local n, err, s = OrderRegion(region, snaps[i])
        if err then return Stop(err) end
        moved, stuck = moved + n, stuck + s
    end
    -- no moves issued: anything still out of place is a locked item
    if moved == 0 then return Done(stuck) end
    run.moves = run.moves + moved
    Debug("pass %d: %d moves", run.passes, moved)
end

local function Tick()
    local ok, err = pcall(Step)
    if not ok then
        ClearCursor() -- the error may have hit between the two pickups
        Stop("Lua error: " .. tostring(err))
        geterrorhandler()(err)
    end
end

-- Classify needs an ItemLocation; without it every pass would error.
local function Supported()
    if loc then return true end
    Say("this client has no ItemLocation API; see /espiutils bags probe")
    return false
end

-- verbose: print the result even with debug off (the sort command and the Sort now button;
-- the Clean Up click stays quiet).
local function Sort(verbose)
    if run then
        Say("already sorting")
        return
    end
    if not Supported() then return end
    if InCombatLockdown() then
        Say("can't sort in combat")
        return
    end
    if GetCursorInfo() then
        Say("drop the item on your cursor first")
        return
    end
    -- the fallback order would fight the next sort made with the bags open
    -- (WithBagsShown opens them for the button and command, so this is only a guard)
    if CombinedBagsClosed() then
        Say("open your bags first")
        return
    end
    local regions = BuildRegions()
    if #regions == 0 then
        Say("no bags to sort")
        return
    end

    local labels = {}
    for _, region in ipairs(regions) do labels[#labels + 1] = region.label end
    Log("sort: " .. table.concat(labels, ", "))
    -- Sort refuses closed combined bags, so the only fallback left is separate
    -- bags, where slot order is the normal layout: no need to say so every time.
    if regions[1].fallback then
        Debug("sorting by slot order (" .. regions[1].fallback .. ")")
    end
    if db.debug then
        Print("sorting... /espiutils bags stop to cancel")
    end

    local rules = {}
    for _, section in ipairs(SECTIONS) do
        if section.setting then rules[section.setting] = db[section.setting] end
    end
    run = {
        verbose = verbose,
        regions = regions, sets = BuildSets(), layout = SortLayout(), rules = rules,
        passes = 0, moves = 0, merges = 0,
        tried = {}, fillTried = {}, pending = {}, start = GetTime(),
    }
    run.ticker = C_Timer.NewTicker(STEP_INTERVAL, Tick)
end

-- Preview -------------------------------------------------------------------

local function Preview()
    if not Supported() then return end
    local region = BuildRegions()[1] -- the general region always comes first
    if not (region and region.general) then
        Print("no general bags to sort")
        return
    end

    local sets = BuildSets()
    local recs = Scan(region, sets, db)
    local counts, perSet, total = {}, {}, 0
    for i = 1, region.n do
        local r = recs[i]
        if r then
            total = total + 1
            counts[r.section] = (counts[r.section] or 0) + 1
            if r.section == SETGEAR then perSet[r.setRank] = (perSet[r.setRank] or 0) + 1 end
        end
    end

    Print(("%d items in %d general slots"):format(total, region.n))
    for _, side in ipairs(SIDES) do
        Print(side == "top" and "Top" or "Bottom")
        for _, sec in ipairs(db.order[side]) do
            Print(("%s: %d"):format(SECTIONS[sec].name, counts[sec] or 0))
            if sec == SETGEAR then
                for rank, s in ipairs(sets) do
                    local spec = s.spec and (" (spec " .. s.spec .. ")") or ""
                    Print(("  %s%s: %d"):format(s.name, spec, perSet[rank] or 0))
                end
                if perSet[#sets + 1] then
                    Print(("  (unmatched set): %d"):format(perSet[#sets + 1]))
                end
            end
        end
    end
end

-- The order is read from the combined bag buttons, so they must be on screen: opens closed
-- combined bags and runs fn next frame, once the buttons are laid out. For the Sort now and
-- Preview buttons and commands, which are used with the bags closed. A second call while one
-- waits is dropped.
local waitingForBags = false
local function WithBagsShown(fn)
    if waitingForBags then return end
    if not CombinedBagsClosed() then
        fn()
        return
    end
    waitingForBags = true
    OpenAllBags()
    C_Timer.After(0, function()
        waitingForBags = false
        fn()
    end)
end

local function SortNow() WithBagsShown(function() Sort(true) end) end
local function PreviewNow() WithBagsShown(Preview) end

-- Probe ---------------------------------------------------------------------

-- reports which APIs this client has, so unsupported ones can be worked around
local function Probe()
    local C, I = C_Container or {}, C_Item or {}
    local checks = {
        { "C_Container", C_Container }, { "C_Container.GetContainerItemInfo", C.GetContainerItemInfo },
        { "C_Container.PickupContainerItem", C.PickupContainerItem },
        { "C_Container.SplitContainerItem", C.SplitContainerItem },
        { "C_Container.GetContainerNumSlots", C.GetContainerNumSlots },
        { "C_Container.GetContainerNumFreeSlots", C.GetContainerNumFreeSlots },
        { "C_Container.GetBagSlotFlag", C.GetBagSlotFlag },
        { "C_Container.GetBackpackAutosortDisabled", C.GetBackpackAutosortDisabled },
        { "C_Container.GetContainerItemEquipmentSetInfo", C.GetContainerItemEquipmentSetInfo },
        { "C_Container.GetContainerItemQuestInfo", C.GetContainerItemQuestInfo },
        { "C_Item.GetItemInfo", I.GetItemInfo }, { "C_Item.GetItemInfoInstant", I.GetItemInfoInstant },
        { "C_Item.GetCurrentItemLevel", I.GetCurrentItemLevel },
        { "C_Item.GetItemMaxStackSizeByID", I.GetItemMaxStackSizeByID },
        { "C_Item.IsBoundToAccountUntilEquip", I.IsBoundToAccountUntilEquip },
        { "ItemLocation", ItemLocation },
        { "C_TooltipInfo.GetBagItem", C_TooltipInfo and C_TooltipInfo.GetBagItem },
        { "C_EquipmentSet", C_EquipmentSet }, { "C_Timer.NewTicker", C_Timer and C_Timer.NewTicker },
        { "C_AddOns.GetAddOnMetadata", C_AddOns and C_AddOns.GetAddOnMetadata },
        { "Enum.BagIndex", Enum and Enum.BagIndex },
        { "Enum.BagIndex.ReagentBag", Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag },
        { "Enum.BagSlotFlags", Enum and Enum.BagSlotFlags },
        { "Enum.ItemBind", Enum and Enum.ItemBind }, { "Enum.ItemClass", Enum and Enum.ItemClass },
        { "Enum.ItemQuality", Enum and Enum.ItemQuality },
        { "ContainerFrameCombinedBags", ContainerFrameCombinedBags },
        { "ContainerFrameSettingsManager", ContainerFrameSettingsManager },
        { "BagItemAutoSortButton", BagItemAutoSortButton },
        { "SOUNDKIT", SOUNDKIT }, { "ITEM_CONJURED", ITEM_CONJURED },
    }
    local missing = 0
    for _, c in ipairs(checks) do
        if not c[2] then
            missing = missing + 1
            Say("MISSING " .. c[1])
        end
    end
    local build = select(4, GetBuildInfo())
    Say(("probe on interface %s: %d of %d missing"):format(tostring(build), missing, #checks))
end

-- Bank deposit --------------------------------------------------------------

local bankOpen = false

-- sends every unlocked crafting reagent in the bags to the bank; returns how many were sent
local function DepositReagents()
    local sent = 0
    for bag = Enum.BagIndex.Backpack, Enum.BagIndex.ReagentBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and not info.isLocked and StaticInfo(info.itemID).reagent then
                C_Container.UseContainerItem(bag, slot, nil, Enum.BankType and Enum.BankType.Character)
                sent = sent + 1
            end
        end
    end
    return sent
end

-- Sorts once the deposits have landed (BAG_UPDATE_DELAYED), or after 2s if no event comes.
-- depositWait is the fallback timer; it is cancelled so a stale one can't end a later deposit early.
local depositWait
local function FinishDeposit()
    if not depositWait then return end
    depositWait:Cancel()
    depositWait = nil
    frame:UnregisterEvent("BAG_UPDATE_DELAYED")
    Sort()
end

local function SortAfterDeposit()
    if depositWait then return end
    frame:RegisterEvent("BAG_UPDATE_DELAYED")
    depositWait = C_Timer.NewTimer(2, FinishDeposit)
end

-- Button hook ---------------------------------------------------------------

local function HookButton()
    local btn = BagItemAutoSortButton
    if not btn then
        Print("Clean Up button not found, use /espiutils bags sort")
        return
    end
    local blizzardClick = btn:GetScript("OnClick")
    btn:SetScript("OnClick", function(self, ...)
        if IsShiftKeyDown() or not db.enabled then
            if blizzardClick then return blizzardClick(self, ...) end
            return
        end
        PlaySound(SOUNDKIT.UI_BAG_SORTING_01)
        if db.depositReagents and bankOpen and not run and not InCombatLockdown() and not GetCursorInfo()
            and DepositReagents() > 0 then
            SortAfterDeposit()
        else
            Sort()
        end
    end)
    btn:HookScript("OnEnter", function()
        if not db.enabled then return end -- a plain click already is Blizzard's sort
        GameTooltip:AddLine("Espi Utils: Shift-click for Blizzard sort", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
end


-- Events --------------------------------------------------------------------

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        HookButton()
    elseif event == "BAG_UPDATE_DELAYED" then
        FinishDeposit()
    elseif event == "PLAYER_REGEN_DISABLED" then
        Stop("combat started")
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if Enum.PlayerInteractionType and arg1 == Enum.PlayerInteractionType.Banker then
            bankOpen = event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"
        end
    end
end)

function EspiUtils.InitBagRules(settings)
    db = settings
    EspiUtils.ApplyDefaults(db, defaults)
    local valid, added = NormalizeOrder(db.order)
    if not valid then db.order = DefaultOrder(db.pinBound ~= false) end
    db.pinBound = nil
    -- questToJunk (before Quest Items had a group) sorted quest items right after the grey ones
    if db.questToJunk ~= nil then
        if (not valid or added[QUEST]) and db.questToJunk and db.junk then
            local side, index = FindSection(JUNK)
            MoveSection(QUEST, side, index + 1)
        end
        db.questToJunk = nil
    end
    EspiUtils.SubTable(db, "log")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
end

-- used by the options screen
EspiUtils.Bags = {
    GetSettings = function() return db end,
    Sections = SECTIONS,
    Sides = SIDES,
    MoveSection = MoveSection,
    Sort = SortNow,
    Preview = PreviewNow,
    ResetDefaults = function()
        EspiUtils.ApplyDefaults(db, defaults, true)
        db.order = DefaultOrder(true)
    end,
}

-- Commands ------------------------------------------------------------------

-- command word -> the section it toggles, from SECTIONS, in section order for the help line
local TOGGLES, toggleWords = {}, {}
for _, section in ipairs(SECTIONS) do
    if section.command then
        TOGGLES[section.command] = section
        toggleWords[#toggleWords + 1] = section.command
    end
end

local HELP = {
    "/espiutils bags sort - sort your bags now",
    "/espiutils bags stop - cancel a sort in progress",
    "/espiutils bags preview - list what each section would hold, moves nothing",
    "/espiutils bags probe - list which game APIs this client is missing",
    "/espiutils bags on - Clean Up button uses the Espi Utils sort",
    "/espiutils bags off - Clean Up button uses Blizzard's sort",
    "/espiutils bags " .. table.concat(toggleWords, " | ") .. " - toggle that group",
    ("/espiutils bags log - show the last %d log lines"):format(LOG_SHOW),
    "/espiutils bags debug - toggle per-pass detail in chat and the log",
    "Shift-click Clean Up for Blizzard's sort",
}

function EspiUtils.HandleBagsCommand(msg)
    local cmd = strtrim(msg or ""):lower():match("^(%S*)")
    if cmd == "sort" then
        SortNow()
    elseif cmd == "stop" then
        if run then Stop("cancelled") else Print("not sorting") end
    elseif cmd == "preview" then
        PreviewNow()
    elseif cmd == "probe" then
        Probe()
    elseif cmd == "on" or cmd == "off" then
        db.enabled = cmd == "on"
        Print("Clean Up button override " .. cmd)
    elseif TOGGLES[cmd] then
        local section = TOGGLES[cmd]
        db[section.setting] = not db[section.setting]
        Print(section.desc .. ": " .. EspiUtils.OnOff(db[section.setting]))
    elseif cmd == "debug" then
        db.debug = not db.debug
        Print("debug " .. EspiUtils.OnOff(db.debug))
    elseif cmd == "log" then
        local log = db.log
        if #log == 0 then Print("log is empty") end
        for i = math.max(1, #log - LOG_SHOW + 1), #log do Print(log[i]) end
    else
        if cmd ~= "" and cmd ~= "help" then Print(("unknown command '%s'"):format(cmd)) end
        Print(("override %s, debug %s"):format(EspiUtils.OnOff(db.enabled), EspiUtils.OnOff(db.debug)))
        for _, line in ipairs(HELP) do Print(line) end
    end
end
