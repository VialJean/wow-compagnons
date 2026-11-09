std = "lua51"
max_line_length = false
self = false

exclude_files = {
	"Libs/",
	".release/",
	".luarocks/",
	".lua/",
}

-- Variables globales écrites par l'addon
globals = {
	"Compagnons",
	"CompagnonsDB",
	"CompagnonsPersoDB",
}

-- API WoW utilisées (à compléter au fil des modules)
read_globals = {
	"LibStub",
	"C_AddOns", "GetAddOnMetadata",
	"C_ChatInfo", "C_EncodingUtil", "C_TradeSkillUI", "C_Timer", "C_XMLUtil",
	"GetBuildInfo", "GetNormalizedRealmName", "GetRealmName", "GetTradeSkillLine",
	"IsInGuild", "IsTrialAccount", "IsVeteranTrialAccount",
	"UnitClass", "UnitName", "UnitFullName", "GetUnitName", "UnitGUID", "GetPlayerInfoByGUID",
	"GetGuildRosterInfo", "GetNumGuildMembers", "C_GuildInfo", "GuildRoster",
	"date", "time", "tinsert",
	-- Interface
	"CreateFrame", "UIParent", "UISpecialFrames", "GameTooltip",
	"CreateDataProvider", "CreateScrollBoxListLinearView", "ScrollUtil", "ScrollBoxConstants",
	"ButtonFrameTemplate_HideButtonBar", "PanelTemplates_TabResize",
	"PanelTemplates_SelectTab", "PanelTemplates_DeselectTab",
	"ITEM_QUALITY_COLORS", "RAID_CLASS_COLORS",
	"C_Item", "C_Spell", "GetItemIcon", "GetSpellTexture", "GetItemCount",
	"ProfessionsFrame", "TradeSkillFrame",
	"GetTime", "SetItemRef", "Enum", "TooltipDataProcessor", "ItemRefTooltip", "ShoppingTooltip1", "IsShiftKeyDown", "IsControlKeyDown",
	"HandleModifiedItemClick", "ContainerFrameItemButton_OnModifiedClick", "hooksecurefunc",
	"ButtonFrameTemplate_HidePortrait", "InCombatLockdown",
}

files["tests/"] = { std = "+busted" }
