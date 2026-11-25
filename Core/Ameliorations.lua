-- Chercheur d'améliorations : compare l'équipement porté aux objets que la guilde peut fabriquer. Lua pur, sans API WoW :
-- l'équipement du joueur est donné en table, le jeu n'est lu que dans Modules/Ameliorations.lua.
--
-- Une recette porte, pour un objet équipable (Data/Recettes.lua, voir docs/protocole.md) :
--   equip = { emplacement = InventoryType, ilvl, requis = niveau requis, classe = ClassID, sous = SubclassID, stats = { { type, valeur } } }
--
-- Deux tests cumulés, puis un classement :
--   Pour qui : la majorité du budget de stats du candidat tombe dans les stats utiles de la classe.
--   Combien : la valeur du candidat dépasse celle de l'objet porté (emplacement vide : toujours).
--   Classement : par gain de valeur.
-- Valeur d'un objet = niveau d'objet × (0,4 + 0,6 × utilité), l'utilité (0 à 1) étant la part de son budget de stats qui tombe
-- dans les stats recherchées par la classe et la spécialisation du joueur, chaque stat pesant selon un poids (voir POIDS).
-- Les valeurs de stats des recettes sont des parts de budget brutes (StatPercentEditor) : seul leur rapport compte, ce qui permet
-- de les comparer aux vraies stats de l'objet porté. Quand celles de l'objet porté sont inconnues, la comparaison retombe sur le
-- seul niveau d'objet. Les effets d'équipement et les procs ne sont pas comptés : le joueur juge sur les infobulles.
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
UTILES.PRIEST[31], UTILES.PRIEST[42] = true, true -- le prêtre soigne ou inflige des dégâts (ombre)

-- Types de stats (ItemStatType) qui comptent pour juger un objet : attributs, évaluations, puissances. L'armure supplémentaire (50),
-- les résistances (51 à 56) et les types que l'on ne sait pas interpréter sont ignorés : ni utiles, ni nuisibles.
local CONNUS = ensemble(3, 4, 5, 6, 7, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 31, 32, 36, 37, 38, 39, 41, 42, 43, 44, 45, 48)

-- Poids des stats par rôle, de 0 (inutile) à 1 (idéal). Les clés sont des noms lisibles, convertis en types par `poids()`.
local NOMS = {
	agilite = 3, force = 4, intelligence = 5, esprit = 6, endurance = 7, defense = 12, esquive = 13, parade = 14, blocage = 15,
	toucherMelee = 16, toucherDistance = 17, toucherSort = 18, critMelee = 19, critDistance = 20, critSort = 21,
	toucher = 31, critique = 32, hate = 36, expertise = 37, pa = 38, pad = 39, soins = 41, degats = 42, mp5 = 43,
	penArmure = 44, puissance = 45, valeurBlocage = 48,
}
local function poids(t)
	local r = {}
	for nom, v in pairs(t) do r[assert(NOMS[nom], nom)] = v end
	return r
end
local ROLES = {
	melee = poids({ force = 1, agilite = 0.6, endurance = 0.3, pa = 0.5, toucherMelee = 1, toucher = 1, critMelee = 0.8,
		critique = 0.8, hate = 0.6, expertise = 0.8, penArmure = 0.6 }),
	tank = poids({ endurance = 1, defense = 1, esquive = 1, parade = 1, blocage = 0.7, valeurBlocage = 0.5, force = 0.5,
		agilite = 0.7, toucherMelee = 0.4, toucher = 0.4, critMelee = 0.3, critique = 0.3, expertise = 0.5, pa = 0.2 }),
	paladinSoin = poids({ intelligence = 1, soins = 1, puissance = 1, esprit = 0.3, mp5 = 0.8, critSort = 0.6, critique = 0.6,
		hate = 0.5, endurance = 0.3 }),
	paladinRet = poids({ force = 1, agilite = 0.4, intelligence = 0.2, endurance = 0.3, pa = 0.5, toucherMelee = 1, toucher = 1,
		critMelee = 0.8, critique = 0.8, hate = 0.5, expertise = 0.8, puissance = 0.3 }),
	chasseur = poids({ agilite = 1, pad = 0.6, pa = 0.4, critDistance = 0.8, critique = 0.8, toucherDistance = 0.8, toucher = 0.8,
		hate = 0.6, intelligence = 0.2, endurance = 0.3, force = 0.1, penArmure = 0.5 }),
	voleur = poids({ agilite = 1, force = 0.5, endurance = 0.3, pa = 0.5, toucherMelee = 1, toucher = 1, critMelee = 0.8,
		critique = 0.8, hate = 0.6, expertise = 0.9, penArmure = 0.5 }),
	soin = poids({ intelligence = 1, soins = 1, puissance = 1, esprit = 0.7, mp5 = 0.8, critSort = 0.5, critique = 0.5, hate = 0.5,
		endurance = 0.3 }),
	ombre = poids({ intelligence = 0.8, degats = 1, puissance = 1, esprit = 0.2, toucherSort = 0.9, toucher = 0.9, critSort = 0.8,
		critique = 0.8, hate = 0.7, endurance = 0.3, mp5 = 0.2 }),
	lanceur = poids({ intelligence = 1, degats = 1, puissance = 1, toucherSort = 0.9, toucher = 0.9, critSort = 0.8, critique = 0.8,
		hate = 0.7, endurance = 0.3, esprit = 0.1, mp5 = 0.3 }),
	chamanAmelio = poids({ force = 0.7, agilite = 0.9, pa = 0.5, intelligence = 0.3, endurance = 0.3, toucherMelee = 1, toucher = 1,
		critMelee = 0.8, critique = 0.8, hate = 0.6, expertise = 0.7, puissance = 0.2 }),
	druideSauvage = poids({ agilite = 1, force = 1, pa = 0.5, endurance = 0.5, toucherMelee = 1, toucher = 1, critMelee = 0.8,
		critique = 0.8, expertise = 0.8, hate = 0.5, penArmure = 0.5 }),
}
-- Rôle par classe et par arbre de talents, dans l'ordre d'affichage des arbres du client (1, 2, 3).
local SPECIALISATIONS = {
	WARRIOR = { "melee", "melee", "tank" },
	PALADIN = { "paladinSoin", "tank", "paladinRet" },
	HUNTER = { "chasseur", "chasseur", "chasseur" },
	ROGUE = { "voleur", "voleur", "voleur" },
	PRIEST = { "soin", "soin", "ombre" },
	SHAMAN = { "lanceur", "chamanAmelio", "soin" },
	MAGE = { "lanceur", "lanceur", "lanceur" },
	WARLOCK = { "lanceur", "lanceur", "lanceur" },
	DRUID = { "lanceur", "druideSauvage", "soin" },
}
Ameliorations.ROLES = ROLES
Ameliorations.SPECIALISATIONS = SPECIALISATIONS

--- Poids des stats pour une classe et un arbre de talents (1 à 3), ou nil si la spécialisation est inconnue : on s'en tient alors
-- à la liste des stats utiles de la classe, toutes à égalité.
function Ameliorations.poids(classeJoueur, spec)
	local roles = SPECIALISATIONS[classeJoueur]
	local role = roles and spec and roles[spec]
	if role then return ROLES[role] end
	local utiles = UTILES[classeJoueur]
	if not utiles then return nil end
	local r = {}
	for t in pairs(utiles) do r[t] = 1 end
	return r
end

--- Utilité d'une liste de stats { { type, valeur } } : part (0 à 1) du budget qui tombe dans les stats recherchées, selon les
-- poids. Nil quand il n'y a rien à juger (aucune stat reconnue) ou pas de poids.
function Ameliorations.utilite(pesees, stats)
	if not pesees or not stats then return nil end
	local total, bon = 0, 0
	for _, s in ipairs(stats) do
		if CONNUS[s[1]] then
			local v = math.abs(s[2])
			total = total + v
			bon = bon + v * (pesees[s[1]] or 0)
		end
	end
	if total == 0 then return nil end
	return bon / total
end

--- Valeur d'un objet : niveau d'objet pondéré par l'utilité (sans utilité connue, le niveau d'objet seul).
function Ameliorations.valeur(ilvl, utilite)
	return ilvl * (0.4 + 0.6 * (utilite or 1))
end

--- Convertit les stats d'un objet porté telles que le jeu les donne (C_Item.GetItemStats : { ITEM_MOD_STAMINA_SHORT = 12, ... })
-- en liste { { type, valeur } }, ou nil si aucune n'est reconnue.
local CLES_STATS = {
	ITEM_MOD_AGILITY_SHORT = 3, ITEM_MOD_STRENGTH_SHORT = 4, ITEM_MOD_INTELLECT_SHORT = 5, ITEM_MOD_SPIRIT_SHORT = 6,
	ITEM_MOD_STAMINA_SHORT = 7, ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = 12, ITEM_MOD_DODGE_RATING_SHORT = 13,
	ITEM_MOD_PARRY_RATING_SHORT = 14, ITEM_MOD_BLOCK_RATING_SHORT = 15, ITEM_MOD_HIT_MELEE_RATING_SHORT = 16,
	ITEM_MOD_HIT_RANGED_RATING_SHORT = 17, ITEM_MOD_HIT_SPELL_RATING_SHORT = 18, ITEM_MOD_CRIT_MELEE_RATING_SHORT = 19,
	ITEM_MOD_CRIT_RANGED_RATING_SHORT = 20, ITEM_MOD_CRIT_SPELL_RATING_SHORT = 21, ITEM_MOD_HIT_RATING_SHORT = 31,
	ITEM_MOD_CRIT_RATING_SHORT = 32, ITEM_MOD_HASTE_RATING_SHORT = 36, ITEM_MOD_EXPERTISE_RATING_SHORT = 37,
	ITEM_MOD_ATTACK_POWER_SHORT = 38, ITEM_MOD_RANGED_ATTACK_POWER_SHORT = 39, ITEM_MOD_HEALING_POWER_SHORT = 41,
	ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 42, ITEM_MOD_MANA_REGENERATION_SHORT = 43, ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = 44,
	ITEM_MOD_SPELL_POWER_SHORT = 45, ITEM_MOD_BLOCK_VALUE_SHORT = 48,
}
function Ameliorations.statsDuJeu(brut)
	if type(brut) ~= "table" then return nil end
	local liste = {}
	for cle, valeur in pairs(brut) do
		local t = CLES_STATS[cle]
		if t and type(valeur) == "number" and valeur ~= 0 then liste[#liste + 1] = { t, valeur } end
	end
	if #liste == 0 then return nil end
	table.sort(liste, function(a, b) return a[1] < b[1] end)
	return liste
end

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
		if CONNUS[s[1]] then
			local v = math.abs(s[2])
			total = total + v
			if utiles[s[1]] then bon = bon + v end
		end
	end
	if total == 0 then return true end
	return bon * 2 > total
end

--- L'objet porté dans une famille d'emplacements : le moins bon, vide en premier. Renvoie son niveau d'objet, l'objet, sa valeur
-- et, quand ses stats sont connues, son utilité (nil sinon : sa valeur est alors son seul niveau d'objet).
local function porte(equipement, emplacements, pesees)
	local pire = nil
	for _, e in ipairs(emplacements) do
		local p = equipement[e]
		local niveau = p and p.ilvl or 0
		local utilite = p and Ameliorations.utilite(pesees, p.stats) or nil
		local valeur = Ameliorations.valeur(niveau, utilite)
		if pire == nil or valeur < pire.valeur then pire = { niveau = niveau, objet = p, valeur = valeur, utilite = utilite } end
	end
	return pire
end

--- Vrai si la base de recettes embarquée contient l'équipement des objets (Data/Recettes.lua généré avec la 0.6 du générateur).
function Ameliorations.donneesPresentes(donnees)
	for _, r in pairs(donnees.recettes) do
		if r.equip then return true end
	end
	return false
end

--- Les améliorations possibles.
-- ctx : donnees (ns.Recettes), equipement { [emplacement] = { itemID, ilvl, stats = nil | { { type, valeur } } } }, niveau (du joueur),
--       classe ("WARRIOR"…), spec (arbre de talents 1 à 3, nil si inconnu),
--       crafteurs(spellID) -> nombre de crafteurs, possede(metierID) -> vrai si le joueur a le métier,
--       options : { guilde = true (défaut : seulement ce que la guilde sait fabriquer), enLigne = false, estEnLigne, crafteursListe }
-- Renvoie { { emplacement (le premier de la famille), candidats = { { spell, ilvl, porteIlvl, porteItem, gain (en niveaux d'objet),
-- utilite (nil si le candidat n'a pas de stats), valeur, gainValeur, verifie } } }, ... }, les emplacements dans l'ordre, les
-- candidats par gain de valeur décroissant. Les emplacements sans amélioration sont absents.
function Ameliorations.chercher(ctx)
	local options = ctx.options or {}
	local seulementGuilde = options.guilde ~= false
	local groupes, ordre = {}, {}
	local pesees = Ameliorations.poids(ctx.classe, ctx.spec)

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
					local actuel = porte(ctx.equipement, emplacements, pesees)
					local utilite = Ameliorations.utilite(pesees, e.stats)
					local valeur = Ameliorations.valeur(e.ilvl or 0, utilite)
					local gain = (e.ilvl or 0) - actuel.niveau
					-- Stats du porté connues : on compare les valeurs. Inconnues (ou emplacement vide) : le niveau d'objet décide.
					local mieux
					if actuel.utilite ~= nil and actuel.niveau > 0 then mieux = valeur > actuel.valeur else mieux = gain > 0 end
					if mieux then
						local cle = emplacements[1]
						local g = groupes[cle]
						if not g then
							g = { emplacement = cle, candidats = {} }
							groupes[cle] = g
							ordre[#ordre + 1] = cle
						end
						g.candidats[#g.candidats + 1] = {
							spell = spellID, ilvl = e.ilvl or 0, porteIlvl = actuel.niveau,
							porteItem = actuel.objet and actuel.objet.itemID or nil,
							gain = gain, utilite = utilite, valeur = valeur, gainValeur = valeur - actuel.valeur,
							verifie = verifie, crafteurs = nb,
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
			if a.gainValeur ~= b.gainValeur then return a.gainValeur > b.gainValeur end
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
