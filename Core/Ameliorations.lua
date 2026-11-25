-- Chercheur d'améliorations : compare l'équipement porté aux objets que la guilde peut fabriquer. Lua pur, sans API WoW :
-- l'équipement du joueur est donné en table, le jeu n'est lu que dans Modules/Ameliorations.lua.
--
-- Une recette porte, pour un objet équipable (Data/Recettes.lua, voir docs/protocole.md) :
--   equip = { emplacement = InventoryType, ilvl, requis = niveau requis, classe = ClassID, sous = SubclassID, stats = { { type, valeur } } }
--
-- Deux modes.
--   Spécialisation choisie (ctx.spec, une des spécialisations de la classe) : chaque objet reçoit un score = somme de ses vraies
--   stats × leur poids (Core/Poids.lua, d'après Pawn Forever) ; le candidat doit battre le score de l'objet porté (emplacement vide :
--   0) et le gain est la différence. Les stats viennent du jeu (ctx.statsObjet), pas de la base de recettes, dont les `stats` ne sont
--   que des parts de budget. Les armes et les boucliers restent comparés par niveau d'objet : la base n'a pas leurs dégâts.
--   Sinon (ou objet sans stats connues) : repli sur le niveau d'objet, que le candidat doit dépasser strictement, et la majorité
--   de son budget de stats doit tomber dans les stats utiles de la classe.
-- Les effets d'équipement et les procs ne sont pas comptés : le joueur juge sur les infobulles.
local _, ns = ...

local Ameliorations = {}
ns.Ameliorations = Ameliorations

-- Emplacements d'équipement (GetInventoryItemLink) auxquels un InventoryType se compare.
-- Plusieurs emplacements : le candidat se compare au moins bon des deux (anneaux, bijoux).
local EMPLACEMENTS = {
	[1] = { 1 }, [2] = { 2 }, [3] = { 3 }, [4] = { 4 }, [5] = { 5 }, [6] = { 6 }, [7] = { 7 }, [8] = { 8 }, [9] = { 9 },
	[10] = { 10 }, [11] = { 11, 12 }, [12] = { 13, 14 },
	[13] = { 16 }, [14] = { 17 }, [15] = { 18 }, [16] = { 15 }, [17] = { 16 }, [19] = { 19 }, [20] = { 5 },
	[21] = { 16 }, [22] = { 17 }, [23] = { 17 }, [25] = { 18 }, [26] = { 18 }, [28] = { 18 },
}
Ameliorations.EMPLACEMENTS = EMPLACEMENTS

-- Objets que toute classe porte : le type d'armure n'entre pas en jeu.
local LIBRES = { [2] = true, [4] = true, [11] = true, [12] = true, [16] = true, [19] = true }
local ARMURE, ARME = 4, 2
local BOUCLIER = 6
local MAIN_GAUCHE = { [22] = true }  -- arme tenue en main gauche : seulement pour qui manie deux armes
local BOUCLIER_TYPES = { [14] = true }

-- Ce que la classe PEUT porter (pas ce qu'elle porte de préférence).
local ARMURES = {
	WARRIOR = { [1] = true, [2] = true, [3] = true, [4] = true, [6] = true },
	PALADIN = { [1] = true, [2] = true, [3] = true, [4] = true, [6] = true },
	HUNTER = { [1] = true, [2] = true, [3] = true },
	ROGUE = { [1] = true, [2] = true },
	PRIEST = { [1] = true },
	SHAMAN = { [1] = true, [2] = true, [3] = true, [6] = true },
	MAGE = { [1] = true },
	WARLOCK = { [1] = true },
	DRUID = { [1] = true, [2] = true },
}
local function ensemble(...)
	local t = {}
	for _, v in ipairs({ ... }) do t[v] = true end
	return t
end
-- Sous-classes d'armes : 0 hache 1M, 1 hache 2M, 2 arc, 3 arme à feu, 4 masse 1M, 5 masse 2M, 6 arme d'hast, 7 épée 1M,
-- 8 épée 2M, 10 bâton, 13 arme de pugilat, 15 dague, 16 arme de jet, 18 arbalète, 19 baguette.
local ARMES = {
	WARRIOR = ensemble(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18),
	PALADIN = ensemble(0, 1, 4, 5, 6, 7, 8),
	HUNTER = ensemble(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 18),
	ROGUE = ensemble(0, 2, 3, 4, 7, 13, 15, 16, 18),
	PRIEST = ensemble(4, 10, 15, 19),
	SHAMAN = ensemble(0, 1, 4, 5, 10, 13, 15),
	MAGE = ensemble(7, 10, 15, 19),
	WARLOCK = ensemble(7, 10, 15, 19),
	DRUID = ensemble(4, 5, 6, 10, 13, 15),
}
local DEUX_ARMES = ensemble("WARRIOR", "ROGUE", "HUNTER")

-- Stats utiles par classe (types d'ItemStatType) : une seule liste par classe, volontairement inclusive (aucun rôle).
-- 3 agilité, 4 force, 5 intelligence, 6 esprit, 7 endurance, 12 défense, 13 esquive, 14 parade, 15 blocage, 16-18 toucher,
-- 19-21 critique, 31 toucher, 32 critique, 36 hâte, 37 expertise, 38 puissance d'attaque, 39 puissance d'attaque à distance,
-- 41 puissance de soins, 42 dégâts des sorts, 43 régénération de mana, 44 pénétration d'armure, 45 puissance des sorts, 48 blocage.
local MELEE_TANK = { 3, 4, 7, 12, 13, 14, 15, 16, 19, 31, 32, 36, 37, 38, 44, 48 }
local SOIN = { 5, 6, 7, 41, 43, 45, 18, 21, 32, 36 }
local LANCEUR = { 5, 7, 42, 45, 18, 21, 31, 32, 36, 43 }
local UTILES = {
	WARRIOR = ensemble(unpack(MELEE_TANK)),
	PALADIN = ensemble(3, 4, 5, 6, 7, 12, 13, 14, 15, 16, 19, 31, 32, 36, 37, 38, 41, 43, 45, 48),
	HUNTER = ensemble(3, 4, 5, 7, 16, 17, 19, 20, 31, 32, 36, 38, 39, 43, 44),
	ROGUE = ensemble(3, 4, 7, 13, 14, 16, 19, 31, 32, 36, 37, 38, 44),
	PRIEST = ensemble(unpack(SOIN)),
	SHAMAN = ensemble(3, 4, 5, 6, 7, 16, 19, 31, 32, 36, 38, 41, 42, 43, 45),
	MAGE = ensemble(unpack(LANCEUR)),
	WARLOCK = ensemble(unpack(LANCEUR)),
	DRUID = ensemble(3, 4, 5, 6, 7, 12, 13, 16, 19, 31, 32, 36, 38, 41, 42, 43, 45),
}

--- Spécialisations d'une classe : { { cle, en, fr, niveau, max } } (Core/Poids.lua), vide si la classe est inconnue.
function Ameliorations.specs(classe)
	return ns.Poids and ns.Poids[classe] or {}
end

--- Poids de la spécialisation `cle` pour un personnage de ce niveau (avant le 60 : poids de progression), ou nil.
local function poidsSpec(classe, cle, niveau)
	for _, sp in ipairs(Ameliorations.specs(classe)) do
		if sp.cle == cle then return niveau >= 60 and sp.max or sp.niveau end
	end
	return nil
end

--- Score d'une liste de stats { { type, valeur } } avec des poids { [type] = poids }.
function Ameliorations.score(stats, poids)
	local total = 0
	for _, st in ipairs(stats or {}) do total = total + (poids[st[1]] or 0) * st[2] end
	return total
end

-- Emplacements (premier de la famille) comparés par niveau d'objet : main droite, main gauche/bouclier, distance.
local PAR_NIVEAU = { [16] = true, [17] = true, [18] = true }

--- Vrai si la classe peut porter l'objet ; en second, vrai si le jugement est sûr. `equip.classe` vaut nil/0 quand le client ne
-- l'a pas donnée : on ne peut alors pas juger le type d'armure ou d'arme (renvoie vrai, faux : non vérifié).
function Ameliorations.portable(classeJoueur, equip)
	local emplacement = equip.emplacement
	if LIBRES[emplacement] then return true, true end
	if MAIN_GAUCHE[emplacement] and not DEUX_ARMES[classeJoueur] then return false, true end
	if BOUCLIER_TYPES[emplacement] then
		-- Un bouclier ne dépend que de la classe : toujours connu par l'emplacement.
		return ARMURES[classeJoueur] ~= nil and ARMURES[classeJoueur][BOUCLIER] == true, true
	end
	local classe, sous = equip.classe, equip.sous
	if not classe or classe == 0 then return true, false end
	if classe == ARMURE then
		local permis = ARMURES[classeJoueur]
		if not permis then return true, false end
		return permis[sous] == true, true
	elseif classe == ARME then
		local permis = ARMES[classeJoueur]
		if not permis then return true, false end
		return permis[sous] == true, true
	end
	return true, false
end

--- Vrai si la majorité du budget de stats du candidat tombe dans les stats utiles de la classe. Sans stats (objet qui n'a que de
-- l'armure ou un effet), rien ne s'y oppose.
function Ameliorations.pertinent(classeJoueur, stats)
	local utiles = UTILES[classeJoueur]
	if not utiles or not stats or #stats == 0 then return true end
	local total, bon = 0, 0
	for _, s in ipairs(stats) do
		local v = math.abs(s[2])
		total = total + v
		if utiles[s[1]] then bon = bon + v end
	end
	if total == 0 then return true end
	return bon * 2 > total
end

--- Niveau d'objet porté dans les emplacements d'une famille : le moins bon, 0 si l'un est vide. Renvoie aussi l'objet comparé.
local function porte(equipement, emplacements)
	local pire, objet = nil, nil
	for _, e in ipairs(emplacements) do
		local p = equipement[e]
		local niveau = p and p.ilvl or 0
		if pire == nil or niveau < pire then pire, objet = niveau, p end
	end
	return pire or 0, objet
end

--- Score de l'objet porté dans une famille d'emplacements : le moins bon, 0 si un emplacement est vide. nil si un objet porté n'a
-- pas de stats connues (on ne peut alors pas comparer par score). Renvoie aussi l'objet comparé.
local function scorePorte(equipement, emplacements, poids)
	local pire, objet = nil, nil
	for _, e in ipairs(emplacements) do
		local p = equipement[e]
		local v = 0
		if p then
			if not p.stats or #p.stats == 0 then return nil end
			v = Ameliorations.score(p.stats, poids)
		end
		if pire == nil or v < pire then pire, objet = v, p end
	end
	return pire, objet
end

--- Vrai si la base de recettes embarquée contient l'équipement des objets (Data/Recettes.lua généré avec la 0.6 du générateur).
function Ameliorations.donneesPresentes(donnees)
	for _, r in pairs(donnees.recettes) do
		if r.equip then return true end
	end
	return false
end

--- Les améliorations possibles.
-- ctx : donnees (ns.Recettes), equipement { [emplacement] = { itemID, ilvl } }, niveau (du joueur), classe ("WARRIOR"…),
--       spec (facultatif : clé d'une spécialisation de la classe), statsObjet(itemID) -> { { type, valeur } } ou nil (stats réelles
--       d'un objet, lues dans le jeu), crafteurs(spellID) -> nombre de crafteurs, possede(metierID) -> vrai si le joueur a le métier,
--       options : { guilde = true (défaut : seulement ce que la guilde sait fabriquer), enLigne = false, estEnLigne, crafteursListe }
-- equipement : { [emplacement] = { itemID, ilvl, stats = { { type, valeur } } } } (stats facultatives).
-- Renvoie { { emplacement (le premier de la famille), candidats = { { spell, ilvl, porteIlvl, porteItem, gain, unite, verifie } } }, ... },
-- les emplacements dans l'ordre, les candidats par gain décroissant (unite : "stats" avant "ilvl"). Les emplacements sans amélioration sont absents.
function Ameliorations.chercher(ctx)
	local options = ctx.options or {}
	local seulementGuilde = options.guilde ~= false
	local groupes, ordre = {}, {}
	local poids = ctx.spec and poidsSpec(ctx.classe, ctx.spec, ctx.niveau)

	for spellID, r in pairs(ctx.donnees.recettes) do
		local e = r.equip
		local emplacements = e and EMPLACEMENTS[e.emplacement]
		if emplacements and (e.requis or 0) <= ctx.niveau then
			local portable, verifie = Ameliorations.portable(ctx.classe, e)
			local liePourTous = r.lie == true
			-- Un objet lié quand ramassé ne se commande que chez un crafteur qui a le métier : on ne le propose que si c'est le nôtre.
			local accessible = liePourTous or (ctx.possede and ctx.possede(r.metier))
			local statsCandidat = portable and accessible and poids and not PAR_NIVEAU[emplacements[1]] and r.objet and r.objet > 0 and ctx.statsObjet
				and ctx.statsObjet(r.objet)
			local parScore = statsCandidat and #statsCandidat > 0
			if portable and accessible and (parScore or Ameliorations.pertinent(ctx.classe, e.stats)) then
				local nb = ctx.crafteurs and ctx.crafteurs(spellID) or 0
				local garde = not seulementGuilde or nb > 0
				if garde and options.enLigne and ctx.crafteursEnLigne then garde = ctx.crafteursEnLigne(spellID) > 0 end
				if garde then
					local niveauPorte, objetPorte = porte(ctx.equipement, emplacements)
					local gain, unite = (e.ilvl or 0) - niveauPorte, "ilvl"
					if parScore then
						local scorePorteur, objetScore = scorePorte(ctx.equipement, emplacements, poids)
						if scorePorteur then
							gain, unite, objetPorte = Ameliorations.score(statsCandidat, poids) - scorePorteur, "stats", objetScore
						end
					end
					if gain > 0 then
						local cle = emplacements[1]
						local g = groupes[cle]
						if not g then
							g = { emplacement = cle, candidats = {} }
							groupes[cle] = g
							ordre[#ordre + 1] = cle
						end
						g.candidats[#g.candidats + 1] = {
							spell = spellID, ilvl = e.ilvl or 0, porteIlvl = objetPorte and objetPorte.ilvl or 0, porteItem = objetPorte and objetPorte.itemID or nil,
							gain = gain, unite = unite, verifie = verifie, crafteurs = nb,
						}
					end
				end
			end
		end
	end

	table.sort(ordre)
	local resultat = {}
	for _, cle in ipairs(ordre) do
		local g = groupes[cle]
		table.sort(g.candidats, function(a, b)
			if a.unite ~= b.unite then return a.unite == "stats" end
			if a.gain ~= b.gain then return a.gain > b.gain end
			return a.spell < b.spell
		end)
		resultat[#resultat + 1] = g
	end
	return resultat
end

--- Emplacements de la famille d'un emplacement (pour afficher les doubles) : le même tableau que celui des comparaisons.
function Ameliorations.famille(emplacement)
	for _, liste in pairs(EMPLACEMENTS) do
		if liste[1] == emplacement then return liste end
	end
	return { emplacement }
end

return Ameliorations
