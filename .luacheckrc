std = "lua51"
max_line_length = false
codes = true
-- WoW globals are read-only API unless listed under globals.
read_globals = {
    -- namespaces and enums
    "C_ActionBar", "C_AddOns", "C_ChatInfo", "C_Container", "C_EquipmentSet", "C_Item", "C_Secrets",
    "C_QuestLog", "C_Spell", "C_SpellBook", "C_Timer", "C_TooltipInfo", "C_UnitAuras", "Constants", "Enum", "Settings",
    "bit",
    -- functions
    "AddQuestWatch", "RemoveQuestWatch", "GetNumQuestWatches", "GetQuestIndexForWatch", "GetQuestLogTitle", "ClearCursor", "CopyTable", "CreateFrame", "CreateMacro", "DeleteMacro", "EditMacro",
    "GetBuildInfo", "GetContainerNumSlots", "GetCursorInfo", "GetCursorPosition", "GetItemFamily", "GetMacroBody",
    "GetMacroIndexByName", "GetMacroInfo", "GetNumMacros", "GetServerTime", "GetTime", "GetUIPanel",
    "HideUIPanel", "InCombatLockdown", "InterfaceOptionsFrame_OpenToCategory",
    "InterfaceOptions_AddCategory", "IsAddOnLoaded", "IsBagOpen", "IsPlayerInWorld",
    "IsResting", "IsShiftKeyDown", "OpenBag", "PlaySound", "ToggleGameMenu", "UnitClass",
    "UnitClassBase", "UnitIsDeadOrGhost", "UnitName", "IsPlayerSpell", "IsSpellKnown",
    "IsInRaid", "IsInGroup", "IsInGuild", "SendChatMessage", "GetNumGroupMembers", "UnitExists", "UnitIsConnected",
    "UnitIsVisible", "UnitInRange", "UnitIsUnit", "UnitPowerType", "date", "geterrorhandler",
    "UnitLevel", "UnitIsAFK", "UnitOnTaxi","IsMounted", "IsInInstance", "GetAddOnMetadata",
    "hooksecurefunc", "issecretvalue", "strtrim", "tContains", "wipe",
    "ContainerFrame_AllowedToOpenBags", "ContainerFrame_GetContainerNumSlots",
    -- frames, mixins and constants
    "BagItemAutoSortButton", "ContainerFrameCombinedBags", "ContainerFrameContainer",
    "ContainerFrameSettingsManager", "GameTooltip", "ItemLocation", "SettingsPanel",
    "UIParent", "UISpecialFrames", "BACKPACK_CONTAINER", "ITEM_CONJURED", "KEYRING_CONTAINER",
    "LE_PARTY_CATEGORY_HOME", "LE_PARTY_CATEGORY_INSTANCE",
    "NUM_BAG_FRAMES", "NUM_CONTAINER_FRAMES", "NUM_TOTAL_BAG_FRAMES", "SOUNDKIT",
}
globals = {
    "EspiUtilsDB", "EspiUtilsAccountDB", "EspiBagRulesDB", "MouseoverMacrosDB",
    "KeepBagsOpenDB", "SlashCmdList", "EspiUtils_OnCompartmentClick",
    "EspiUtils_OnCompartmentEnter", "EspiUtils_OnCompartmentLeave",
}
-- SLASH_* globals are assigned freely.
ignore = { "11./SLASH_.*", "212", "213" }
