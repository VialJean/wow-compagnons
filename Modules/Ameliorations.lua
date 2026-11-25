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

--- Stats d'un objet porté { { type, valeur } }, ou nil si le client ne les donne pas.
local function statsObjet(lien)
	local lire = (C_Item and C_Item.GetItemStats) or GetItemStats
	if not lire then return nil end
	local ok, brut = pcall(lire, lien)
	if not ok then return nil end
	return ns.Ameliorations.statsDuJeu(brut)
end

--- Arbres de talents du personnage : { { index, nom, points } } (vide si le client n'expose pas les talents).
function Module:Specialisations()
	local liste = {}
	if not GetNumTalentTabs or not GetTalentTabInfo then return liste end
	local ok, nb = pcall(GetNumTalentTabs)
	if not ok or type(nb) ~= "number" then return liste end
	for i = 1, math.min(nb, 3) do
		local bon, nom, _, points = pcall(GetTalentTabInfo, i)
		if bon and type(nom) == "string" then liste[#liste + 1] = { index = i, nom = nom, points = tonumber(points) or 0 } end
	end
	return liste
end

--- Arbre où le personnage a dépensé le plus de points de talent, ou nil (aucun point, ou talents inaccessibles).
function Module:SpecialisationAuto()
	local meilleur
	for _, s in ipairs(self:Specialisations()) do
		if s.points > 0 and (not meilleur or s.points > meilleur.points) then meilleur = s end
	end
	return meilleur and meilleur.index or nil
end

--- Équipement porté par le personnage connecté : { [emplacement] = { itemID, ilvl, lien, stats } }. Lu à l'ouverture de l'onglet ;
-- pas d'inspection des autres joueurs.
function Module:LireEquipement()
	local equipement = {}
	for emplacement = 1, NB_EMPLACEMENTS do
		local lien = GetInventoryItemLink("player", emplacement)
		if lien then
			local itemID = tonumber(lien:match("item:(%d+)"))
			equipement[emplacement] = { itemID = itemID, ilvl = niveauObjet(lien) or 0, lien = lien, stats = statsObjet(lien) }
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

--- Les améliorations du personnage connecté. options : guilde, enLigne, spec (arbre 1 à 3 ; nil : celui où l'on a le plus de points).
function Module:Chercher(options)
	local catalogue = ns.catalogue
	if not catalogue then return {}, false end
	local _, classe = UnitClass("player")
	local resultat = ns.Ameliorations.chercher({
		donnees = ns.Recettes,
		equipement = self:LireEquipement(),
		niveau = UnitLevel("player") or 1,
		classe = classe,
		spec = options and options.spec or self:SpecialisationAuto(),
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
