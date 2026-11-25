-- Chercheur d'améliorations : compare l'équipement porté aux objets que la guilde peut fabriquer. Lua pur, sans API WoW :
-- l'équipement du joueur est donné en table, le jeu n'est lu que dans Modules/Ameliorations.lua.
--
-- Une recette porte, pour un objet équipable (Data/Recettes.lua, voir docs/protocole.md) :
--   equip = { emplacement = InventoryType, ilvl, requis = niveau requis, classe = ClassID, sous = SubclassID, stats = { { type, valeur } } }
--
-- Heuristique de niveau 1 : deux tests cumulés.
--   Combien : le niveau d'objet du candidat dépasse strictement celui de l'objet porté (emplacement vide : toujours).
--   Pour qui : la majorité du budget de stats du candidat tombe dans les stats utiles de la classe.
-- Pas de pondération : le joueur juge sur les infobulles. Les effets d'équipement et les procs ne sont pas comptés.
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

--- Vrai si la base de recettes embarquée contient l'équipement des objets (Data/Recettes.lua généré avec la 0.6 du générateur).
function Ameliorations.donneesPresentes(donnees)
	for _, r in pairs(donnees.recettes) do
		if r.equip then return true end
	end
	return false
end

--- Les améliorations possibles.
-- ctx : donnees (ns.Recettes), equipement { [emplacement] = { itemID, ilvl } }, niveau (du joueur), classe ("WARRIOR"…),
--       crafteurs(spellID) -> nombre de crafteurs, possede(metierID) -> vrai si le joueur a le métier,
--       options : { guilde = true (défaut : seulement ce que la guilde sait fabriquer), enLigne = false, estEnLigne, crafteursListe }
-- Renvoie { { emplacement (le premier de la famille), candidats = { { spell, ilvl, porteIlvl, porteItem, gain, verifie } } }, ... },
-- les emplacements dans l'ordre, les candidats par gain décroissant. Les emplacements sans amélioration sont absents.
function Ameliorations.chercher(ctx)
	local options = ctx.options or {}
	local seulementGuilde = options.guilde ~= false
	local groupes, ordre = {}, {}

	for spellID, r in pairs(ctx.donnees.recettes) do
		local e = r.equip
		local emplacements = e and EMPLACEMENTS[e.emplacement]
		if emplacements and (e.requis or 0) <= ctx.niveau then
			local portable, verifie = Ameliorations.portable(ctx.classe, e)
			local liePourTous = r.lie == true
			-- Un objet lié quand ramassé ne se commande que chez un crafteur qui a le métier : on ne le propose que si c'est le nôtre.
			local accessible = liePourTous or (ctx.possede and ctx.possede(r.metier))
			if portable and accessible and Ameliorations.pertinent(ctx.classe, e.stats) then
				local nb = ctx.crafteurs and ctx.crafteurs(spellID) or 0
				local garde = not seulementGuilde or nb > 0
				if garde and options.enLigne and ctx.crafteursEnLigne then garde = ctx.crafteursEnLigne(spellID) > 0 end
				if garde then
					local niveauPorte, objetPorte = porte(ctx.equipement, emplacements)
					local gain = (e.ilvl or 0) - niveauPorte
					if gain > 0 then
						local cle = emplacements[1]
						local g = groupes[cle]
						if not g then
							g = { emplacement = cle, candidats = {} }
							groupes[cle] = g
							ordre[#ordre + 1] = cle
						end
						g.candidats[#g.candidats + 1] = {
							spell = spellID, ilvl = e.ilvl or 0, porteIlvl = niveauPorte, porteItem = objetPorte and objetPorte.itemID or nil,
							gain = gain, verifie = verifie, crafteurs = nb,
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
