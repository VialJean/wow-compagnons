-- Rappels de commandes (docs/v5.md, §3.2-3.3). Lua pur, sans API du jeu.
--
-- Personne n'est connecté en permanence : c'est à la connexion de chacun que remontent les commandes qui n'avancent pas.
-- Un rappel signale, il ne décide rien : le joueur agit (ou non).
--
--   a_confirmer   client    ma commande est livrée, je n'ai pas encore confirmé la réception
--   sans_preneur  client    ma commande est ouverte et personne ne l'a prise
--   sans_progres  crafteur  j'ai pris une commande, rien n'a bougé depuis longtemps
--   en_attente    crafteur  j'ai livré, le client n'a pas confirmé (information)
local _, ns = ...

local Rappels = {}
ns.Rappels = Rappels

local JOUR = 24 * 3600

--- Délais par défaut, en jours.
Rappels.DEFAUTS = { aConfirmer = 1, sansPreneur = 3, sansProgres = 5, enAttente = 3, ancienne = 30 }

--- Ordre d'affichage des genres.
Rappels.GENRES = { "a_confirmer", "sans_preneur", "sans_progres", "en_attente" }

local function delai(delais, cle)
	local v = delais and delais[cle]
	if type(v) ~= "number" or v ~= v or v < 0 then v = Rappels.DEFAUTS[cle] end
	return v * JOUR
end

--- Rappels pour mes commandes. `miens` : ensemble des clés de mes personnages ; `delais` : { aConfirmer, sansPreneur, ... }
-- en jours (les valeurs absentes ou invalides retombent sur les défauts).
-- Renvoie une liste `{ genre, commande, jours }` triée : genres dans l'ordre de `GENRES`, puis la plus ancienne d'abord.
function Rappels.calculer(commandes, miens, maintenant, delais)
	local liste = {}
	local seuils = {
		a_confirmer = delai(delais, "aConfirmer"), sans_preneur = delai(delais, "sansPreneur"),
		sans_progres = delai(delais, "sansProgres"), en_attente = delai(delais, "enAttente"),
	}
	for _, o in pairs(commandes or {}) do
		local age = maintenant - (o.maj or maintenant)
		local genre
		if miens[o.client] and o.statut == "livree" then genre = "a_confirmer"
		elseif miens[o.client] and o.statut == "ouverte" then genre = "sans_preneur"
		elseif o.assigne and miens[o.assigne] and (o.statut == "prise" or o.statut == "mats") then genre = "sans_progres"
		elseif o.assigne and miens[o.assigne] and o.statut == "livree" then genre = "en_attente"
		end
		if genre and age >= seuils[genre] then
			liste[#liste + 1] = { genre = genre, commande = o, jours = math.floor(age / JOUR) }
		end
	end
	local rang = {}
	for i, g in ipairs(Rappels.GENRES) do rang[g] = i end
	table.sort(liste, function(a, b)
		if a.genre ~= b.genre then return rang[a.genre] < rang[b.genre] end
		if a.commande.maj ~= b.commande.maj then return a.commande.maj < b.commande.maj end
		return a.commande.id < b.commande.id
	end)
	return liste
end

--- Regroupe par genre : `{ [genre] = { n = nombre, jours = ancienneté de la plus ancienne } }`.
function Rappels.resumer(liste)
	local groupes = {}
	for _, r in ipairs(liste) do
		local g = groupes[r.genre]
		if not g then
			g = { n = 0, jours = 0 }
			groupes[r.genre] = g
		end
		g.n = g.n + 1
		if r.jours > g.jours then g.jours = r.jours end
	end
	return groupes
end

--- Mes commandes ouvertes depuis au moins `jours` jours (30 par défaut) sans preneur : à proposer à l'annulation.
-- Seul le client annule, d'où `miens` contre le client. Les plus anciennes d'abord.
function Rappels.anciennes(commandes, miens, maintenant, jours)
	local seuil = delai({ ancienne = jours }, "ancienne")
	local liste = {}
	for _, o in pairs(commandes or {}) do
		if o.statut == "ouverte" and miens[o.client] and maintenant - o.maj >= seuil then liste[#liste + 1] = o end
	end
	table.sort(liste, function(a, b)
		if a.maj ~= b.maj then return a.maj < b.maj end
		return a.id < b.id
	end)
	return liste
end

return Rappels
