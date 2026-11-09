-- Relevé des prix des composants à l'hôtel des ventes. Rien n'est scanné automatiquement : on lit seulement ce que le
-- joueur affiche en cherchant lui-même (docs/livraison.md). Deux familles d'API sont gérées, avec des garde-fous :
--   - ancienne : AUCTION_ITEM_LIST_UPDATE, GetNumAuctionItems / GetAuctionItemInfo / GetAuctionItemLink ;
--   - moderne : COMMODITY_SEARCH_RESULTS_UPDATED, C_AuctionHouse.GetCommoditySearchResultInfo.
-- Seul le prix d'un composant de la base est mémorisé : le plus bas prix à achat immédiat vu, par unité.
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
	}) do
		pcall(self.RegisterEvent, self, evenement, methode)
	end
end

local function idDepuisLien(lien)
	return type(lien) == "string" and tonumber(lien:match("item:(%d+)")) or nil
end

--- Enregistre un prix pour un composant de la base. Renvoie vrai s'il a changé.
function Marche:Noter(itemID, unitaire)
	if not ns.Recettes.objets[itemID] then return false end
	local change = ns.Prix.enregistrer(ns.db.global.prix, itemID, unitaire, time())
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
			if itemID and ns.Recettes.objets[itemID] then
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
		if not itemID or not ns.Recettes.objets[itemID] then return end
		local api = _G.C_AuctionHouse
		if not api or not api.GetNumCommoditySearchResults or (api.GetNumCommoditySearchResults(itemID) or 0) < 1 then return end
		local info = api.GetCommoditySearchResultInfo(itemID, 1)
		if info and info.unitPrice then self:Noter(itemID, info.unitPrice) end
	end)
end

-- ---------------------------------------------------------------------------------------------
-- Lecture
-- ---------------------------------------------------------------------------------------------

--- Prix unitaire connu d'un composant, avec la date du relevé.
function Marche:Pour(itemID)
	return ns.Prix.unitaire(ns.db.global.prix, itemID)
end

--- Montant en cuivre -> texte (avec les icônes de pièces du jeu quand elles existent).
function Marche.Argent(cuivre)
	if GetCoinTextureString then return GetCoinTextureString(cuivre) end
	return ns.Prix.texte(cuivre)
end

-- ---------------------------------------------------------------------------------------------
-- /cpg prix
-- ---------------------------------------------------------------------------------------------

function Marche:Commande(objet, montant)
	local prix = ns.db.global.prix
	objet = type(objet) == "string" and objet or ""

	if objet:lower() == "clear" then
		for id in pairs(prix) do prix[id] = nil end
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
