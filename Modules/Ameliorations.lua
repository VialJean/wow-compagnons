-- Chercheur d'améliorations côté jeu : lit l'équipement du joueur et prépare le contexte de Core/Ameliorations.lua.
-- Rien n'est acheté, commandé ni équipé tout seul : un clic ouvre le dialogue de commande habituel.
local _, ns = ...
local Compagnons = ns.addon

local Module = Compagnons:NewModule("AmeliorationsModule")
ns.AmeliorationsModule = Module

local NB_EMPLACEMENTS = 19

-- Clés de C_Item.GetItemStats → ItemStatType (les numéros de Core/Ameliorations.lua).
local TYPES_STATS = {
	ITEM_MOD_AGILITY_SHORT = 3, ITEM_MOD_STRENGTH_SHORT = 4, ITEM_MOD_INTELLECT_SHORT = 5, ITEM_MOD_SPIRIT_SHORT = 6,
	ITEM_MOD_STAMINA_SHORT = 7, ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = 12, ITEM_MOD_DODGE_RATING_SHORT = 13,
	ITEM_MOD_PARRY_RATING_SHORT = 14, ITEM_MOD_BLOCK_RATING_SHORT = 15, ITEM_MOD_HIT_MELEE_RATING_SHORT = 16,
	ITEM_MOD_HIT_RANGED_RATING_SHORT = 17, ITEM_MOD_HIT_SPELL_RATING_SHORT = 18, ITEM_MOD_CRIT_MELEE_RATING_SHORT = 19,
	ITEM_MOD_CRIT_RANGED_RATING_SHORT = 20, ITEM_MOD_CRIT_SPELL_RATING_SHORT = 21, ITEM_MOD_HIT_RATING_SHORT = 31,
	ITEM_MOD_CRIT_RATING_SHORT = 32, ITEM_MOD_HASTE_RATING_SHORT = 36, ITEM_MOD_EXPERTISE_RATING_SHORT = 37,
	ITEM_MOD_ATTACK_POWER_SHORT = 38, ITEM_MOD_RANGED_ATTACK_POWER_SHORT = 39, ITEM_MOD_SPELL_HEALING_DONE_SHORT = 41,
	ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 42, ITEM_MOD_MANA_REGENERATION_SHORT = 43,
	ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = 44, ITEM_MOD_SPELL_POWER_SHORT = 45, ITEM_MOD_BLOCK_VALUE_SHORT = 48,
}

--- Stats d'un objet porté { { type, valeur } }, suffixes aléatoires compris ; nil si le jeu ne les donne pas (objet pas en cache).
local function statsObjet(lien)
	if not (C_Item and C_Item.GetItemStats) then return nil end
	local brut = C_Item.GetItemStats(lien)
	if type(brut) ~= "table" then return nil end
	local stats = {}
	for cle, valeur in pairs(brut) do
		if TYPES_STATS[cle] and type(valeur) == "number" then stats[#stats + 1] = { TYPES_STATS[cle], valeur } end
	end
	return #stats > 0 and stats or nil
end

local function niveauObjet(lien)
	if C_Item and C_Item.GetDetailedItemLevelInfo then
		local n = C_Item.GetDetailedItemLevelInfo(lien)
		if n then return n end
	end
	if GetDetailedItemLevelInfo then
		local n = GetDetailedItemLevelInfo(lien)
		if n then return n end
	end
	-- GetItemInfo global absent sur Forever : C_Item.GetItemInfo, qui peut renvoyer une table ou des valeurs.
	local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if not fn then return nil end
	local a, _, _, ilvl = fn(lien)
	if type(a) == "table" then return a.itemLevel end
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

--- Numéro de l'arbre de talents où le personnage a dépensé le plus de points, ou nil (aucun point, ou talents inaccessibles).
local function arbreDominant()
	if not GetNumTalentTabs or not GetTalentTabInfo then return nil end
	local ok, nb = pcall(GetNumTalentTabs)
	if not ok or type(nb) ~= "number" then return nil end
	local meilleur, max = nil, 0
	for i = 1, math.min(nb, 3) do
		local bon, _, _, points = pcall(GetTalentTabInfo, i)
		points = bon and tonumber(points) or 0
		if points > max then meilleur, max = i, points end
	end
	return meilleur
end

--- Choix enregistré pour la classe du personnage connecté : nil (détecter par les talents), "aucune" (niveau d'objet seulement)
-- ou la clé d'une spécialisation.
function Module:Spec()
	local _, classe = UnitClass("player")
	return ns.db.profile.ameliorations.specs[classe]
end

function Module:ChoisirSpec(spec)
	local _, classe = UnitClass("player")
	ns.db.profile.ameliorations.specs[classe] = spec
end

--- Spécialisation utilisée pour le calcul : le choix, ou celle de l'arbre de talents dominant ; nil si aucune.
function Module:SpecEffective()
	local choix = self:Spec()
	if choix == "aucune" then return nil end
	if choix then return choix end
	local arbre = arbreDominant()
	local _, classe = UnitClass("player")
	for _, sp in ipairs(ns.Ameliorations.specs(classe)) do
		if sp.id == arbre then return sp.cle end
	end
	return nil
end

--- Stats réelles d'un objet de recette, lues dans le jeu ; nil tant que le jeu ne l'a pas en cache (on le lui demande : au
-- prochain affichage il sera là, et l'objet est d'ici là comparé par niveau d'objet).
local function statsRecette(itemID)
	local stats = statsObjet("item:" .. itemID)
	if not stats and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
	return stats
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
		spec = self:SpecEffective(),
		statsObjet = statsRecette,
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
