-- Noms du jeu dans la langue du client. Data/Recettes.lua ne contient aucun nom ; chaque Data/Noms.<langue>.lua apporte
-- ceux d'une langue (ns.NomsDonnees.<langue>). On les applique au chargement, avec repli nom par nom sur la langue de
-- référence quand une traduction manque. Lua pur, sans API du jeu.
local _, ns = ...

local Noms = {}
ns.Noms = Noms

--- Applique les noms de `langue` à la base de recettes `donnees` : metiers[id].nom, recettes[id].nom, objets[id][1].
-- tables : { enUS = { metiers, recettes, objets }, frFR = { ... } }. Renvoie vrai si au moins une langue était disponible.
-- Un nom introuvable devient l'identifiant (« #2329 ») plutôt que de laisser un champ vide.
function Noms.appliquer(donnees, tables, langue, repli)
	tables = tables or {}
	local principal, secours = tables[langue], tables[repli or "enUS"]

	local function nom(section, id)
		return (principal and principal[section] and principal[section][id])
			or (secours and secours[section] and secours[section][id])
	end

	for id, m in pairs(donnees.metiers or {}) do m.nom = nom("metiers", id) or ("#" .. id) end
	for spellID, r in pairs(donnees.recettes or {}) do r.nom = nom("recettes", spellID) or ("#" .. spellID) end
	for itemID, o in pairs(donnees.objets or {}) do o[1] = nom("objets", itemID) or "" end
	return principal ~= nil or secours ~= nil
end

return Noms
