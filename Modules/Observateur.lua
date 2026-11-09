-- Observateur (phase 0 de docs/livraison.md) : enregistre les événements réels d'échange, de courrier, de fabrication
-- et de sacs, avec des instantanés de leur contenu, dans CompagnonsDB.global.observation. Désactivé par défaut.
-- Il ne fait rien d'autre que lire : aucune action n'est effectuée dans le jeu.
-- /cpg observer [on|off|clear|show [n]]
local _, ns = ...
local L = ns.L
local Compagnons = ns.addon

local Observateur = Compagnons:NewModule("Observateur", "AceEvent-3.0")
ns.Observateur = Observateur

local CAPACITE = 400

-- Événements d'intérêt. Un nom inconnu du client est signalé (RegisterEvent échoue) : le relevé dit lesquels existent.
local EVENEMENTS = {
	-- échange
	"TRADE_REQUEST", "TRADE_REQUEST_CANCEL", "TRADE_SHOW", "TRADE_CLOSED", "TRADE_UPDATE", "TRADE_ACCEPT_UPDATE",
	"TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED", "TRADE_MONEY_CHANGED",
	-- courrier
	"MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "MAIL_SEND_INFO_UPDATE", "MAIL_SEND_SUCCESS", "MAIL_FAILED",
	"MAIL_SUCCESS",
	-- fabrication
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
	"TRADE_SKILL_CRAFT_BEGIN", "TRADE_SKILL_ITEM_CRAFTED_RESULT", "TRADE_SKILL_CRAFTING_BEGIN",
	-- hôtel des ventes (pour une estimation de coût : quelles API et quels événements existent ?)
	"AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_ITEM_LIST_UPDATE", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
	"COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
	-- sacs, banque, messages
	"BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "ITEM_PUSH",
	"CHAT_MSG_SYSTEM", "CHAT_MSG_LOOT", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE",
}

local function securise(_, fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then return nil, tostring(a) end
	return a, b
end

function Observateur:Tampon()
	return ns.db.global.observation
end

function Observateur:Noter(texte)
	ns.Observation.ajouter(self:Tampon(), CAPACITE, time(), texte)
end

function Observateur:OnEnable()
	if ns.db.profile.observer then self:Demarrer() end
end

function Observateur:Demarrer()
	ns.db.profile.observer = true
	self:Noter("# observation démarrée, build " .. tostring(select(2, GetBuildInfo())))
	local absents = {}
	for _, evenement in ipairs(EVENEMENTS) do
		local ok = pcall(self.RegisterEvent, self, evenement, "SurEvenement")
		if not ok then absents[#absents + 1] = evenement end
	end
	if #absents > 0 then self:Noter("# événements inconnus du client : " .. table.concat(absents, ", ")) end
	self.actif = true
end

function Observateur:Arreter()
	ns.db.profile.observer = false
	self:UnregisterAllEvents()
	self:Noter("# observation arrêtée")
	self.actif = false
end

-- ---------------------------------------------------------------------------------------------
-- Instantanés de contenu
-- ---------------------------------------------------------------------------------------------

local function instantaneEchange()
	local lignes = {}
	local partenaire = UnitName and UnitName("NPC")
	lignes[#lignes + 1] = "partenaire=" .. tostring(partenaire)
	for _, cote in ipairs({ { "moi", GetTradePlayerItemInfo }, { "lui", GetTradeTargetItemInfo } }) do
		for i = 1, 7 do
			local ok, nom, _, nombre = pcall(cote[2], i)
			if ok and nom then lignes[#lignes + 1] = string.format("%s[%d]=%s x%s", cote[1], i, tostring(nom), tostring(nombre)) end
			if not ok then
				lignes[#lignes + 1] = cote[1] .. " erreur : " .. tostring(nom)
				break
			end
		end
	end
	local argentMoi = GetPlayerTradeMoney and GetPlayerTradeMoney() or 0
	local argentLui = GetTargetTradeMoney and GetTargetTradeMoney() or 0
	lignes[#lignes + 1] = string.format("argent moi=%s lui=%s", tostring(argentMoi), tostring(argentLui))
	return "échange : " .. table.concat(lignes, " | ")
end

local function instantaneCourrier()
	local lignes = {}
	local total = GetInboxNumItems and GetInboxNumItems() or 0
	lignes[#lignes + 1] = "courrier reçu : " .. tostring(total)
	for i = 1, math.min(total, 5) do
		local ok, _, _, expediteur, objet, argent, _, _, avecObjet = pcall(GetInboxHeaderInfo, i)
		if ok then
			local pieces = {}
			if avecObjet then
				for j = 1, 12 do
					local ok2, nom, itemID, _, nombre = pcall(GetInboxItem, i, j)
					if ok2 and nom then pieces[#pieces + 1] = string.format("%s(%s) x%s", tostring(nom), tostring(itemID), tostring(nombre)) end
				end
			end
			lignes[#lignes + 1] = string.format("[%d] de %s « %s » argent=%s objets=%s", i, tostring(expediteur),
				tostring(objet), tostring(argent), table.concat(pieces, ", "))
		end
	end
	return table.concat(lignes, " | ")
end

local function instantaneEnvoi()
	local lignes = {}
	local champ = _G.SendMailNameEditBox
	lignes[#lignes + 1] = "destinataire=" .. tostring(champ and champ.GetText and champ:GetText())
	for i = 1, 12 do
		local ok, nom, itemID, _, nombre = pcall(GetSendMailItem, i)
		if ok and nom then lignes[#lignes + 1] = string.format("pj[%d]=%s(%s) x%s", i, tostring(nom), tostring(itemID), tostring(nombre)) end
	end
	lignes[#lignes + 1] = "argent=" .. tostring(GetSendMailMoney and GetSendMailMoney())
	return "envoi : " .. table.concat(lignes, " | ")
end

--- Quelles API de l'hôtel des ventes le client expose, et ce qu'elles renvoient pour la liste affichée.
local function instantaneVentes()
	local lignes = {}
	local api = _G.C_AuctionHouse
	for _, nom in ipairs({ "SendBrowseQuery", "SendSearchQuery", "GetNumCommoditySearchResults",
		"GetCommoditySearchResultInfo", "GetBrowseResults", "GetItemSearchResultInfo" }) do
		lignes[#lignes + 1] = "C_AuctionHouse." .. nom .. "=" .. tostring(api ~= nil and api[nom] ~= nil)
	end
	for _, nom in ipairs({ "QueryAuctionItems", "GetNumAuctionItems", "GetAuctionItemInfo", "GetAuctionItemLink",
		"CanSendAuctionQuery" }) do
		lignes[#lignes + 1] = nom .. "=" .. tostring(_G[nom] ~= nil)
	end
	if _G.GetNumAuctionItems then
		local ok, nombre, total = pcall(_G.GetNumAuctionItems, "list")
		lignes[#lignes + 1] = "GetNumAuctionItems(list)=" .. tostring(ok and nombre) .. "/" .. tostring(ok and total)
		if ok and nombre and nombre > 0 and _G.GetAuctionItemInfo then
			local ok2, nom, _, quantite, _, _, _, _, mise, _, achat = pcall(_G.GetAuctionItemInfo, "list", 1)
			lignes[#lignes + 1] = string.format("premier lot : %s x%s mise=%s achat=%s", tostring(nom), tostring(quantite),
				tostring(mise), tostring(ok2 and achat))
		end
	end
	return "hôtel des ventes : " .. table.concat(lignes, " | ")
end

-- ---------------------------------------------------------------------------------------------
-- Événements
-- ---------------------------------------------------------------------------------------------

function Observateur:SurEvenement(evenement, ...)
	-- Les lancers de sorts sont nombreux : on ne garde que ceux des recettes de la base, pour le personnage.
	if evenement:find("^UNIT_SPELLCAST_") then
		local unite, _, spellID = ...
		if unite ~= "player" then return end
		local recette = spellID and ns.Recettes.recettes[spellID]
		if not recette then return end
		self:Noter(ns.Observation.ligne(evenement, ...) .. " [recette " .. tostring(recette.nom) .. "]")
		return
	end

	self:Noter(ns.Observation.ligne(evenement, ...))

	local instantane
	if evenement == "TRADE_ACCEPT_UPDATE" or evenement == "TRADE_SHOW" or evenement == "TRADE_CLOSED" then
		instantane = instantaneEchange
	elseif evenement == "MAIL_INBOX_UPDATE" then
		instantane = instantaneCourrier
	elseif evenement == "MAIL_SEND_INFO_UPDATE" or evenement == "MAIL_SEND_SUCCESS" then
		instantane = instantaneEnvoi
	elseif evenement == "AUCTION_HOUSE_SHOW" or evenement == "AUCTION_ITEM_LIST_UPDATE" then
		instantane = instantaneVentes
	end
	if instantane then
		local texte, erreur = securise("instantané", instantane)
		self:Noter(texte and ("  " .. texte) or ("  instantané impossible : " .. tostring(erreur)))
	end
end

-- ---------------------------------------------------------------------------------------------
-- /cpg observer
-- ---------------------------------------------------------------------------------------------

function Observateur:Commande(action, valeur)
	action = type(action) == "string" and action:lower() or ""
	if action == "on" then
		if not self.actif then self:Demarrer() end
		Compagnons:Print(L.OBSERVER_ON)
		return
	elseif action == "off" then
		if self.actif then self:Arreter() end
		Compagnons:Print(L.OBSERVER_OFF)
		return
	elseif action == "clear" then
		for i = #self:Tampon(), 1, -1 do self:Tampon()[i] = nil end
		Compagnons:Print(L.OBSERVER_VIDE)
		return
	elseif action == "show" then
		local lignes = ns.Observation.dernieres(self:Tampon(), tonumber(valeur) or 15, function(t) return date("%H:%M:%S", t) end)
		for _, l in ipairs(lignes) do print("  " .. l) end
		return
	end
	-- sans argument : bascule
	if self.actif then self:Commande("off") else self:Commande("on") end
	Compagnons:Print(string.format(L.OBSERVER_ETAT, self.actif and L.INFO_ACTIVE or L.INFO_DESACTIVE, #self:Tampon()))
end
