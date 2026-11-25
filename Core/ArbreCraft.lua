-- Arbre de craft : ce qu'il faut fabriquer, étage par étage, pour obtenir une recette (minerai -> barre -> objet).
-- Lua pur, sans API WoW.
--
-- Un composant qui est lui-même le résultat d'une recette devient une branche : on descend jusqu'aux matières
-- premières, que l'on ne fabrique pas. Les quantités sont calculées en fabrications entières (on ne fabrique pas
-- une demi-barre) ; ce qui dépasse est signalé comme surplus.
--
--   arbre = {
--     racine = { spell, fabrications, enfants = { noeud, ... } },
--     feuilles = { { itemID, qte }, ... },   -- matières premières totales, triées par itemID
--   }
--   noeud = { itemID, besoin, spell = nil | spellID, fabrications, surplus, enfants }
--     (sans `spell` : matière première, à acheter ou récolter)
local _, ns = ...

local ArbreCraft = {}
ns.ArbreCraft = ArbreCraft

ArbreCraft.PROFONDEUR_MAX = 8

--- La recette retenue pour fabriquer `itemID`, ou nil : première (par spellID) qui n'est pas déjà dans la branche
-- (évite les boucles, comme les conversions dans les deux sens) et qui a des composants. `choisir(liste, itemID)`
-- peut imposer un autre choix.
local function recetteDe(ctx, itemID, chemin)
	local candidates = {}
	for _, spellID in ipairs(ctx.creant(itemID) or {}) do
		local r = ctx.donnees.recettes[spellID]
		if r and not chemin[spellID] and r.composants and #r.composants > 0 then candidates[#candidates + 1] = spellID end
	end
	if #candidates == 0 then return nil end
	table.sort(candidates)
	if ctx.choisir then
		local choix = ctx.choisir(candidates, itemID)
		if choix then return choix end
	end
	return candidates[1]
end

local function noeudRecette(ctx, spellID, fabrications, chemin, profondeur)
	local recette = ctx.donnees.recettes[spellID]
	local noeud = { spell = spellID, fabrications = fabrications, enfants = {} }
	chemin[spellID] = true
	for _, comp in ipairs(recette.composants or {}) do
		local itemID, parFabrication = comp[1], comp[2]
		local besoin = parFabrication * fabrications
		local enfant = { itemID = itemID, besoin = besoin, enfants = {} }
		local sous = profondeur < ArbreCraft.PROFONDEUR_MAX and recetteDe(ctx, itemID, chemin)
		if sous then
			local produit = math.max(1, ctx.donnees.recettes[sous].qte or 1)
			local n = noeudRecette(ctx, sous, math.ceil(besoin / produit), chemin, profondeur + 1)
			enfant.spell = sous
			enfant.fabrications = n.fabrications
			enfant.surplus = n.fabrications * produit - besoin
			enfant.enfants = n.enfants
		else
			ctx.feuilles[itemID] = (ctx.feuilles[itemID] or 0) + besoin
		end
		noeud.enfants[#noeud.enfants + 1] = enfant
	end
	chemin[spellID] = nil
	return noeud
end

--- Construit l'arbre de `fabrications` exemplaires de la recette `spellID`.
-- `creant(itemID)` renvoie les spellIDs des recettes qui créent l'objet (Catalogue:RecettesCreant).
-- Renvoie nil si la recette est inconnue.
function ArbreCraft.construire(donnees, creant, spellID, fabrications, choisir)
	if not donnees.recettes[spellID] then return nil end
	fabrications = math.max(1, math.floor(fabrications or 1))
	local ctx = { donnees = donnees, creant = creant, choisir = choisir, feuilles = {} }
	local racine = noeudRecette(ctx, spellID, fabrications, {}, 1)
	local feuilles = {}
	for itemID, qte in pairs(ctx.feuilles) do feuilles[#feuilles + 1] = { itemID = itemID, qte = qte } end
	table.sort(feuilles, function(a, b) return a.itemID < b.itemID end)
	return { racine = racine, feuilles = feuilles }
end

--- Aplatit l'arbre en lignes pour l'affichage, dans l'ordre de lecture : { profondeur, itemID, besoin, spell,
-- fabrications, surplus }. La racine est la première ligne (itemID nil : c'est la recette demandée).
function ArbreCraft.lignes(arbre)
	local lignes = {}
	local function descendre(noeud, profondeur)
		lignes[#lignes + 1] = {
			profondeur = profondeur, itemID = noeud.itemID, besoin = noeud.besoin, spell = noeud.spell,
			fabrications = noeud.fabrications, surplus = noeud.surplus,
		}
		for _, e in ipairs(noeud.enfants or {}) do descendre(e, profondeur + 1) end
	end
	descendre(arbre.racine, 0)
	return lignes
end

--- Nombre d'étages de fabrication sous la racine (0 : tous les composants sont des matières premières).
function ArbreCraft.etages(arbre)
	local function hauteur(noeud)
		local h = 0
		for _, e in ipairs(noeud.enfants or {}) do
			if e.spell then h = math.max(h, 1 + hauteur(e)) end
		end
		return h
	end
	return hauteur(arbre.racine)
end

return ArbreCraft
