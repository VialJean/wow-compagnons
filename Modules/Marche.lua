-- Relevé des prix des composants à l'hôtel des ventes. Rien n'est scanné automatiquement : on lit seulement ce que le
-- joueur affiche en cherchant lui-même (docs/livraison.md). Deux familles d'API sont gérées, avec des garde-fous :
--   - ancienne : AUCTION_ITEM_LIST_UPDATE, GetNumAuctionItems / GetAuctionItemInfo / GetAuctionItemLink ;
--   - moderne : COMMODITY_SEARCH_RESULTS_UPDATED, C_AuctionHouse.GetCommoditySearchResultInfo.
-- Chez un marchand : le prix des composants qu'il vend en quantité illimitée et contre de l'or seulement (un prix de vendeur
-- l'emporte sur l'hôtel des ventes : c'est le coût réel, voir Core/Prix.lua). Le prix affiché tient compte de la réputation ;
-- le prix de base, plus haut, l'emporte à la synchro.
-- Seul le prix d'un composant de la base (ou d'un objet qu'elle sait fabriquer, en local) est mémorisé : le plus bas prix à achat immédiat vu, par unité.
-- Message émis : COMPAGNONS_PRIX_MAJ
-- /cpg prix [<id ou lien> <montant>|clear]
local _, ns = ...
local L = ns.L
local Compagnons = ns.addon

local Marche = Compagnons:NewModule("Marche", "AceEvent-3.0")
ns.Marche = Marche

local function securise(_, fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then
		ns.log("info", "prix", "relevé impossible : %s", tostring(a))
		return nil
	end
	return a, b
end

function Marche:OnEnable()
	-- Un événement inconnu du client fait échouer RegisterEvent : on l'ignore (le relevé d'observation dit lesquels existent).
	for evenement, methode in pairs({
		AUCTION_ITEM_LIST_UPDATE = "SurListe",
		COMMODITY_SEARCH_RESULTS_UPDATED = "SurMarchandise",
		MERCHANT_SHOW = "SurMarchand",
		MERCHANT_UPDATE = "SurMarchand",
	}) do
		pcall(self.RegisterEvent, self, evenement, methode)
	end
end

local function idDepuisLien(lien)
	return type(lien) == "string" and tonumber(lien:match("item:(%d+)")) or nil
end

--- Un objet dont on retient le prix : un composant de la base, ou un objet que la base sait fabriquer.
function Marche:Suivi(itemID)
	if ns.Recettes.objets[itemID] then return true end
	return ns.catalogue ~= nil and #ns.catalogue:RecettesCreant(itemID) > 0
end

--- Prix d'achat relevé d'un objet : prix unitaire, horodatage, vendeur (ou nil).
function Marche:PrixAchat(itemID)
	local p, t, pnj = ns.Prix.unitaire(ns.db.global.prix, itemID)
	if p then return p, t, pnj end
	return ns.Prix.unitaire(ns.db.global.prixObjets or {}, itemID)
end

--- Enregistre un prix. Un composant de la base entre dans les prix de la guilde (synchronisés) ; un objet fabricable reste
-- local (`prixObjets`), pour comparer avec le coût de fabrication. Renvoie vrai s'il a changé.
function Marche:Noter(itemID, unitaire, pnj)
	if not ns.Recettes.objets[itemID] then
		if not self:Suivi(itemID) then return false end
		ns.db.global.prixObjets = ns.db.global.prixObjets or {}
		local change = ns.Prix.enregistrer(ns.db.global.prixObjets, itemID, unitaire, time(), pnj)
		if change then Compagnons:SendMessage("COMPAGNONS_PRIX_MAJ") end
		return change
	end
	local change = ns.Prix.enregistrer(ns.db.global.prix, itemID, unitaire, time(), pnj)
	if change then
		Compagnons:SendMessage("COMPAGNONS_PRIX_MAJ")
		if ns.Reseau and ns.Reseau.moteur then ns.Reseau.moteur:PublierPrix(itemID) end
	end
	return change
end

--- Ancienne API : la page de résultats affichée.
function Marche:SurListe()
	securise("liste", function()
		local nombre = GetNumAuctionItems("list")
		local parObjet = {}
		for i = 1, nombre or 0 do
			local itemID = idDepuisLien(GetAuctionItemLink("list", i))
			if itemID and self:Suivi(itemID) then
				local _, _, quantite, _, _, _, _, _, _, achat = GetAuctionItemInfo("list", i)
				local lots = parObjet[itemID]
				if not lots then
					lots = {}
					parObjet[itemID] = lots
				end
				lots[#lots + 1] = { quantite, achat }
			end
		end
		for itemID, lots in pairs(parObjet) do
			local minimum = ns.Prix.minimum(lots)
			if minimum then self:Noter(itemID, minimum) end
		end
	end)
end

--- API moderne : les marchandises sont triées par prix, le premier résultat est le moins cher.
function Marche:SurMarchandise(_, itemID)
	securise("marchandise", function()
		if not itemID or not self:Suivi(itemID) then return end
		local api = _G.C_AuctionHouse
		if not api or not api.GetNumCommoditySearchResults or (api.GetNumCommoditySearchResults(itemID) or 0) < 1 then return end
		local info = api.GetCommoditySearchResultInfo(itemID, 1)
		if info and info.unitPrice then self:Noter(itemID, info.unitPrice) end
	end)
end

--- Marchand : les composants vendus sans limite de stock, contre de l'or seulement.
function Marche:SurMarchand()
	securise("marchand", function()
		local nombre = _G.GetMerchantNumItems and _G.GetMerchantNumItems() or 0
		for i = 1, nombre do
			local prix, quantite, disponible, cout
			local api = _G.C_MerchantFrame
			if api and api.GetItemInfo then
				-- API récente : un tableau (numAvailable vaut -1 sans limite de stock)
				local info = api.GetItemInfo(i)
				if info then prix, quantite, disponible, cout = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost end
			elseif _G.GetMerchantItemInfo then
				local _
				_, _, prix, quantite, disponible, _, cout = _G.GetMerchantItemInfo(i)
			end
			local itemID = idDepuisLien(_G.GetMerchantItemLink and _G.GetMerchantItemLink(i))
			if itemID and self:Suivi(itemID) and disponible == -1 and not cout
				and type(prix) == "number" and prix > 0 and type(quantite) == "number" and quantite >= 1 then
				self:Noter(itemID, prix / quantite, true)
			end
		end
	end)
end

-- ---------------------------------------------------------------------------------------------
-- Lecture
-- ---------------------------------------------------------------------------------------------

--- Prix unitaire connu d'un composant, avec la date du relevé.
function Marche:Pour(itemID)
	return ns.Prix.unitaire(ns.db.global.prix, itemID)
end

-- Icônes de pièces du jeu, insérées dans le texte. Construites ici plutôt que par GetCoinTextureString : sur ce client la
-- fonction globale n'existe plus (le prix s'affichait en texte brut), et une séquence |T…|t ne dépend d'aucune API.
local ICONES = {
	or_ = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
	argent = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
	cuivre = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}

--- Montant en cuivre -> texte avec les icônes de pièces (or, argent, cuivre).
function Marche.Argent(cuivre)
	return ns.Prix.texte(cuivre, ICONES)
end

-- ---------------------------------------------------------------------------------------------
-- /cpg prix
-- ---------------------------------------------------------------------------------------------

function Marche:Commande(objet, montant)
	local prix = ns.db.global.prix
	objet = type(objet) == "string" and objet or ""

	if objet:lower() == "clear" then
		for id in pairs(prix) do prix[id] = nil end
		ns.db.global.prixObjets = {}
		Compagnons:Print(L.PRIX_EFFACE)
		Compagnons:SendMessage("COMPAGNONS_PRIX_MAJ")
		return
	end

	if objet ~= "" then
		local itemID = idDepuisLien(objet) or tonumber(objet)
		local cuivre = ns.Prix.lire(montant)
		if not itemID or not cuivre or not ns.Recettes.objets[itemID] then
			Compagnons:Print(L.PRIX_USAGE)
			return
		end
		-- Un prix saisi à la main compte comme un relevé d'aujourd'hui.
		if ns.Prix.enregistrer(prix, itemID, cuivre, time()) then Compagnons:SendMessage("COMPAGNONS_PRIX_MAJ") end
		local nom = ns.Recettes.objets[itemID][1]
		Compagnons:Print(string.format(L.PRIX_FIXE, nom ~= "" and nom or ("#" .. itemID), Marche.Argent(cuivre)))
		return
	end

	local n = 0
	for _ in pairs(prix) do n = n + 1 end
	Compagnons:Print(string.format(L.PRIX_ETAT, n))
end
