std = "lua51"
max_line_length = false
codes = true
-- WoW globals are read-only API unless listed under globals.
read_globals = {
    -- namespaces and enums
    "C_ActionBar", "C_AddOns", "C_Container", "C_EquipmentSet", "C_Item", "C_Secrets",
    "C_Spell", "C_Timer", "C_TooltipInfo", "C_UnitAuras", "Constants", "Enum", "Settings",
    "bit",
    -- functions
    "ClearCursor", "CopyTable", "CreateFrame", "CreateMacro", "DeleteMacro", "EditMacro",
    "GetBuildInfo", "GetContainerNumSlots", "GetCursorInfo", "GetItemFamily", "GetMacroBody",
    "GetMacroIndexByName", "GetNumMacros", "GetServerTime", "GetTime", "GetUIPanel",
    "HideUIPanel", "InCombatLockdown", "InterfaceOptionsFrame_OpenToCategory",
    "InterfaceOptions_AddCategory", "IsAddOnLoaded", "IsBagOpen", "IsPlayerInWorld",
    "IsResting", "IsShiftKeyDown", "OpenBag", "PlaySound", "ToggleGameMenu", "UnitClass",
    "UnitClassBase", "UnitIsDeadOrGhost", "UnitName", "IsPlayerSpell", "IsSpellKnown",
    "IsInRaid", "IsInGroup", "GetNumGroupMembers", "UnitExists", "UnitIsConnected",
    "UnitIsVisible", "UnitInRange", "UnitIsUnit", "UnitPowerType", "date", "geterrorhandler",
    "hooksecurefunc", "issecretvalue", "strtrim", "tContains", "wipe",
    "ContainerFrame_AllowedToOpenBags", "ContainerFrame_GetContainerNumSlots",
    -- frames, mixins and constants
    "BagItemAutoSortButton", "ContainerFrameCombinedBags", "ContainerFrameContainer",
    "ContainerFrameSettingsManager", "GameTooltip", "ItemLocation", "SettingsPanel",
    "UIParent", "UISpecialFrames", "BACKPACK_CONTAINER", "ITEM_CONJURED", "KEYRING_CONTAINER",
    "NUM_BAG_FRAMES", "NUM_CONTAINER_FRAMES", "NUM_TOTAL_BAG_FRAMES", "SOUNDKIT",
}
globals = {
    "EspiUtilsDB", "EspiUtilsAccountDB", "EspiBagRulesDB", "MouseoverMacrosDB",
    "KeepBagsOpenDB", "SlashCmdList", "EspiUtils_OnCompartmentClick",
    "EspiUtils_OnCompartmentEnter", "EspiUtils_OnCompartmentLeave",
}
-- SLASH_* globals are assigned freely.
ignore = { "11./SLASH_.*", "212", "213" }
