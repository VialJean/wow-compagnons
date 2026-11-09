-- /cpg diag : vérifie sur le client Forever les points qui conditionnent l'architecture.
--   1. Version du client et numéro d'interface
--   2. Persistance des SavedVariables (compte et personnage)
--   3. Fonctions natives C_EncodingUtil
--   4. API des métiers, et si GetAllRecipeIDs renvoie les recettes non apprises
--   5. Templates d'interface prévus dans le plan de montage
--   6. Canal addon (préfixe, guilde, compte d'essai)
-- Le rapport est affiché dans le chat et enregistré dans CompagnonsDB.global.diag.rapport.
local _, ns = ...
local Compagnons = ns.addon

local Diagnostic = Compagnons:NewModule("Diagnostic")

local OK, KO, INFO = "|cff5fd068OK|r", "|cffe8806aKO|r", "|cffe8a94f??|r"

local TEMPLATES = {
	"ButtonFrameTemplate", "PortraitFrameTemplate", "InsetFrameTemplate",
	"PanelTabButtonTemplate", "TabSystemTemplate", "UIPanelButtonTemplate",
	"WowScrollBoxList", "MinimalScrollBar", "SearchBoxTemplate",
	"WowStyle1DropdownTemplate", "WowStyle1FilterDropdownTemplate",
	"UICheckButtonTemplate", "UIRadioButtonTemplate", "NumericInputSpinnerTemplate",
	"ScrollingEditBoxTemplate", "ItemButtonTemplate",
}

local rapport

local function ligne(etat, texte, ...)
	local msg = string.format(texte, ...)
	print("  " .. etat .. " " .. msg)
	rapport[#rapport + 1] = (etat == OK and "OK " or etat == KO and "KO " or "?? ") .. msg
end

local function section(titre)
	print("|cffe0b252" .. titre .. "|r")
	rapport[#rapport + 1] = "## " .. titre
end

function Diagnostic:Lancer()
	rapport = {}
	Compagnons:Print("Diagnostic du client")

	-- 1. Client
	section("Client")
	local version, build, dateBuild, toc = GetBuildInfo()
	ligne(INFO, "Version %s, build %s (%s), interface %s", version, build, dateBuild, tostring(toc))
	ligne(toc == 16001 and OK or KO, "Interface attendue par le .toc : 16001")

	-- 1 bis. Identité : comment le jeu nomme le personnage (sert à définir la clé d'un personnage)
	section("Identité")
	local function valeurs(...)
		local t = {}
		for i = 1, select("#", ...) do t[i] = string.format("%q", tostring((select(i, ...)))) end
		return table.concat(t, ", ")
	end
	local function relever(nom, fn, ...)
		local ok, a, b, c = pcall(fn, ...)
		ligne(INFO, "%s -> %s", nom, ok and valeurs(a, b, c) or ("erreur : " .. tostring(a)))
	end
	relever('UnitName("player")', UnitName, "player")
	relever('UnitFullName("player")', UnitFullName, "player")
	relever('GetUnitName("player", false)', GetUnitName, "player", false)
	relever('GetUnitName("player", true)', GetUnitName, "player", true)
	relever("GetRealmName()", GetRealmName)
	relever("GetNormalizedRealmName()", GetNormalizedRealmName)
	relever("ns.clePersonnage()", ns.clePersonnage)
	local guid = UnitGUID and UnitGUID("player")
	relever('GetPlayerInfoByGUID(UnitGUID("player"))', GetPlayerInfoByGUID, guid)
	if IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
		for i = 1, math.min(3, (GetNumGuildMembers())) do
			relever("GetGuildRosterInfo(" .. i .. ")", GetGuildRosterInfo, i)
		end
	end

	-- 2. SavedVariables
	section("SavedVariables")
	local diag = ns.db.global.diag
	ligne(INFO, "Compte : %d sessions depuis le %s", diag.sessions, date("%d/%m/%Y %H:%M", diag.premiere))
	ligne(INFO, "Personnage : %d sessions", CompagnonsPersoDB and CompagnonsPersoDB.sessions or 0)
	ligne(INFO, "Fais /reload, puis déconnecte-toi et reconnecte-toi : les deux compteurs doivent augmenter")

	-- 3. C_EncodingUtil
	section("C_EncodingUtil")
	local E = C_EncodingUtil
	if not E then
		ligne(KO, "C_EncodingUtil absent : on utilisera LibSerialize + LibDeflate")
	else
		for _, f in ipairs({ "SerializeCBOR", "DeserializeCBOR", "CompressString", "DecompressString", "EncodeBase64", "DecodeBase64" }) do
			ligne(E[f] and OK or KO, "%s", f)
		end
		if E.CompressString and E.DecompressString then
			local source = string.rep("Compagnons ", 50)
			local ok, rond = pcall(function() return E.DecompressString(E.CompressString(source)) end)
			ligne(ok and rond == source and OK or KO, "Aller-retour compression")
		end
		if E.SerializeCBOR and E.DeserializeCBOR then
			local ok, t = pcall(function() return E.DeserializeCBOR(E.SerializeCBOR({ a = 1, b = { 2, 3 } })) end)
			ligne(ok and type(t) == "table" and t.a == 1 and OK or KO, "Aller-retour CBOR")
		end
	end

	-- 4. Métiers
	section("Métiers")
	local TS = C_TradeSkillUI
	for _, f in ipairs({ "GetAllRecipeIDs", "GetRecipeInfo", "GetRecipeSchematic", "GetBaseProfessionInfo" }) do
		ligne(TS and TS[f] and OK or KO, "C_TradeSkillUI.%s", f)
	end
	local perso = ns.db.global.personnages[ns.clePersonnage()]
	local vu = false
	if perso then
		for _, m in pairs(perso.metiers) do
			vu = true
			if m.nbVues > m.nbApprises then
				ligne(OK, "%s : %d vues pour %d apprises → les recettes non apprises sont renvoyées", m.nom, m.nbVues, m.nbApprises)
			else
				ligne(INFO, "%s : %d vues = %d apprises → seulement les apprises (ou tout est appris)", m.nom, m.nbVues, m.nbApprises)
			end
		end
	end
	if not vu then
		ligne(INFO, "Aucun métier scanné : ouvre une fenêtre de métier puis relance /cpg diag")
	end

	-- 5. Templates
	section("Templates d'interface")
	local X = C_XMLUtil
	if not (X and X.GetTemplateInfo) then
		ligne(INFO, "C_XMLUtil.GetTemplateInfo absent : vérification manuelle dans wow-ui-source")
	else
		for _, nom in ipairs(TEMPLATES) do
			local ok, info = pcall(X.GetTemplateInfo, nom)
			ligne(ok and info and OK or KO, "%s%s", nom, ok and info and (" (" .. tostring(info.type) .. ")") or "")
		end
	end

	-- 5 bis. Infobulles : API qui décident du branchement (voir docs/infobulles.md, §4.4)
	section("Infobulles")
	local function api(nom, valeur, detail)
		ligne(valeur and OK or KO, "%s%s", nom, detail and (" : " .. detail) or "")
	end
	local enum = _G.Enum and _G.Enum.TooltipDataType
	api("TooltipDataProcessor", _G.TooltipDataProcessor ~= nil)
	api("TooltipDataProcessor.AddTooltipPostCall", _G.TooltipDataProcessor and _G.TooltipDataProcessor.AddTooltipPostCall ~= nil)
	api("Enum.TooltipDataType.Item", enum and enum.Item ~= nil, enum and enum.Item and tostring(enum.Item) or nil)
	api("GameTooltip", GameTooltip ~= nil)
	api("GameTooltip:SetItemByID", GameTooltip and GameTooltip.SetItemByID ~= nil)
	api("GameTooltip:GetItem", GameTooltip and GameTooltip.GetItem ~= nil)
	api("GameTooltip:HookScript", GameTooltip and GameTooltip.HookScript ~= nil)
	api("ItemRefTooltip", _G.ItemRefTooltip ~= nil)
	api("ShoppingTooltip1", _G.ShoppingTooltip1 ~= nil)
	api("C_Item.GetItemCount", C_Item and C_Item.GetItemCount ~= nil)
	api("C_Item.GetItemNameByID", C_Item and C_Item.GetItemNameByID ~= nil)
	api("IsShiftKeyDown / IsControlKeyDown", _G.IsShiftKeyDown ~= nil and _G.IsControlKeyDown ~= nil)
	api("HandleModifiedItemClick", _G.HandleModifiedItemClick ~= nil)
	api("ContainerFrameItemButton_OnModifiedClick", _G.ContainerFrameItemButton_OnModifiedClick ~= nil)
	api("hooksecurefunc", _G.hooksecurefunc ~= nil)
	-- Désenchantement (docs/desenchantement.md) : informations d'objet lisibles à l'exécution ?
	api("C_Item.GetItemInfo", C_Item and C_Item.GetItemInfo ~= nil)
	api("C_Item.GetDetailedItemLevelInfo", C_Item and C_Item.GetDetailedItemLevelInfo ~= nil)
	api("GetItemInfo (global)", _G.GetItemInfo ~= nil)
	do
		-- Épée usée (25) : arme, qualité 1 ; elle donne la forme des valeurs renvoyées.
		local fn = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
		if fn then
			-- Valeurs attendues : 1 nom, 2 lien, 3 qualité, 4 niveau d'objet, ... 12 classe, 13 sous-classe.
			local r = { pcall(fn, 25) } -- r[1] = réussite, puis les valeurs décalées d'un cran
			ligne(INFO, "GetItemInfo(25) -> %s, nom=%s, qualité=%s, niveauObjet=%s, classe=%s, sousClasse=%s",
				tostring(r[1]), tostring(r[2]), tostring(r[4]), tostring(r[5]), tostring(r[13]), tostring(r[14]))
			if type(r[2]) == "table" then
				local t = r[2]
				ligne(INFO, "GetItemInfo renvoie une table : classID=%s subclassID=%s quality=%s itemLevel=%s",
					tostring(t.classID), tostring(t.subclassID), tostring(t.quality), tostring(t.itemLevel))
			end
		end
	end
	-- Essai réel : une infobulle d'objet connue (Bandage en lin, 1251) se remplit-elle, et par quelle voie ?
	if GameTooltip then
		GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
		local ok = GameTooltip.SetItemByID and pcall(GameTooltip.SetItemByID, GameTooltip, 1251)
		ligne(INFO, "SetItemByID(1251) -> %s, %d lignes", tostring(ok), GameTooltip:NumLines())
		GameTooltip:Hide()
	end

	-- 6. Canal addon
	section("Canal addon")
	local CI = C_ChatInfo
	if CI and CI.RegisterAddonMessagePrefix then
		CI.RegisterAddonMessagePrefix(ns.PREFIXE)
		ligne(CI.IsAddonMessagePrefixRegistered(ns.PREFIXE) and OK or KO, "Préfixe %s enregistré", ns.PREFIXE)
	else
		ligne(KO, "C_ChatInfo.RegisterAddonMessagePrefix absent")
	end
	ligne(IsInGuild() and OK or INFO, IsInGuild() and "Dans une guilde" or "Pas de guilde : la synchro ne pourra pas être testée")
	local essai = (IsTrialAccount and IsTrialAccount()) or (IsVeteranTrialAccount and IsVeteranTrialAccount())
	ligne(essai and KO or OK, essai and "Compte d'essai : envoi de messages addon impossible" or "Compte complet")

	-- Bibliothèques
	section("Bibliothèques")
	for _, lib in ipairs({ "AceAddon-3.0", "AceDB-3.0", "AceComm-3.0", "LibSerialize", "LibDeflate", "LibDBIcon-1.0" }) do
		ligne(LibStub(lib, true) and OK or KO, "%s", lib)
	end

	diag.rapport = rapport
	diag.rapportLe = time()
	Compagnons:Print("Rapport enregistré dans CompagnonsDB (fichier WTF/Account/<compte>/SavedVariables/Compagnons.lua après /reload).")
end
