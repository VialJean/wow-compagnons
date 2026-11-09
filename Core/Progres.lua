-- Progression des commandes (phase 2 de docs/livraison.md) : répartition des fabrications entre mes commandes prises.
-- Lua pur, sans API du jeu.
local _, ns = ...

local Progres = {}
ns.Progres = Progres

--- Nombre d'exemplaires créés par un lancer de la recette (au moins 1 : un enchantement ne crée pas d'objet mais
-- compte pour un).
function Progres.parLancer(recette)
	return (recette.qte and recette.qte > 0) and recette.qte or 1
end

--- Répartit `quantite` exemplaires fabriqués entre mes commandes prises pour cette recette.
-- Les plus anciennes d'abord, dans la limite de ce qu'il reste à fabriquer (en comptant `attente`, ce qui n'est pas
-- encore enregistré). Renvoie { [idCommande] = n } et la quantité qui n'a pu être rattachée à aucune commande.
function Progres.repartir(commandes, moi, spellID, quantite, attente)
	local liste = {}
	for _, o in pairs(commandes) do
		if o.spell == spellID and o.assigne == moi and (o.statut == "prise" or o.statut == "mats") then
			liste[#liste + 1] = o
		end
	end
	table.sort(liste, function(a, b)
		if a.cree ~= b.cree then return a.cree < b.cree end
		return a.id < b.id
	end)

	local parts, restant = {}, quantite
	for _, o in ipairs(liste) do
		if restant <= 0 then break end
		local deja = ns.Commandes.crafte(o) + ((attente and attente[o.id]) or 0)
		local libre = o.qte - deja
		if libre > 0 then
			local n = math.min(restant, libre)
			parts[o.id] = n
			restant = restant - n
		end
	end
	return parts, restant
end

--- « 3/5 craftés » pour une commande en cours de fabrication, ou nil.
function Progres.libelle(o, modele)
	if o.statut ~= "prise" and o.statut ~= "mats" then return nil end
	local n = ns.Commandes.crafte(o)
	if n <= 0 then return nil end
	return string.format(modele, n, o.qte)
end

return Progres
