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
	"UnitClass", "UnitName",
	"date", "time",
}

files["tests/"] = { std = "+busted" }
