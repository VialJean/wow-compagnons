-- Chercheur d'améliorations côté jeu : lit l'équipement du joueur et prépare le contexte de Core/Ameliorations.lua.
-- Rien n'est acheté, commandé ni équipé tout seul : un clic ouvre le dialogue de commande habituel.
local _, ns = ...
local Compagnons = ns.addon

local Module = Compagnons:NewModule("AmeliorationsModule")
ns.AmeliorationsModule = Module

local NB_EMPLACEMENTS = 19

local function niveauObjet(lien)
	if C_Item and C_Item.GetDetailedItemLevelInfo then
		local n = C_Item.GetDetailedItemLevelInfo(lien)
		if n then return n end
	end
	if GetDetailedItemLevelInfo then
		local n = GetDetailedItemLevelInfo(lien)
		if n then return n end
	end
	local _, _, _, ilvl = GetItemInfo(lien)
	return ilvl
end

--- Équipement porté par le personnage connecté : { [emplacement] = { itemID, ilvl, lien } }. Lu à l'ouverture de l'onglet ;
-- pas d'inspection des autres joueurs.
function Module:LireEquipement()
	local equipement = {}
	for emplacement = 1, NB_EMPLACEMENTS do
		local lien = GetInventoryItemLink("player", emplacement)
		if lien then
			local itemID = tonumber(lien:match("item:(%d+)"))
			equipement[emplacement] = { itemID = itemID, ilvl = niveauObjet(lien) or 0, lien = lien }
		end
	end
	return equipement
end

--- Vrai si l'un de nos personnages a ce métier (skillLineID).
local function possede(metierID)
	for _, perso in pairs(ns.db.global.personnages) do
		for cle, metier in pairs(perso.metiers or {}) do
			if ns.Profil.idMetier(ns.Recettes, metier, cle) == metierID then return true end
		end
	end
	return false
end

--- Les améliorations du personnage connecté. options : guilde, enLigne.
function Module:Chercher(options)
	local catalogue = ns.catalogue
	if not catalogue then return {}, false end
	local _, classe = UnitClass("player")
	local resultat = ns.Ameliorations.chercher({
		donnees = ns.Recettes,
		equipement = self:LireEquipement(),
		niveau = UnitLevel("player") or 1,
		classe = classe,
		crafteurs = function(spellID) return #catalogue:Crafteurs(spellID) end,
		crafteursEnLigne = function(spellID)
			local n = 0
			for _, c in ipairs(catalogue:Crafteurs(spellID)) do
				if ns.estEnLigne(c.cle) then n = n + 1 end
			end
			return n
		end,
		possede = possede,
		options = options,
	})
	return resultat, ns.Ameliorations.donneesPresentes(ns.Recettes)
end
