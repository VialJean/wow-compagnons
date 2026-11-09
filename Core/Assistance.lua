-- Assistance à l'envoi (phase 5 de docs/livraison.md) : ce qu'il faut remettre à quelqu'un pour mes commandes, et où le
-- prendre dans mes sacs. Lua pur, sans API du jeu ; le module UI/Assistance.lua pose les objets, un clic à la fois.
-- L'addon ne valide jamais l'échange ni n'envoie le courrier : ces actions restent au joueur.
local _, ns = ...

local Assistance = {}
ns.Assistance = Assistance

local function memePersonne(cle, nom) return ns.Livraison.memePersonne(cle, nom) end

--- Commandes concernées par une remise entre moi et `partenaire` (nil : tous), de la plus ancienne à la plus récente.
-- Deux sens : je fournis les composants que je dois en tant que client, ou je livre l'objet que j'ai fabriqué.
local function concernees(commandes, donnees, moi, partenaire)
	local liste = {}
	for _, o in pairs(commandes) do
		local recette = donnees.recettes[o.spell]
		if recette then
			if o.client == moi and o.statut == "prise" and o.mats ~= "crafteur" and o.assigne
				and (not partenaire or memePersonne(o.assigne, partenaire)) then
				liste[#liste + 1] = { commande = o, sens = "fournir", autre = o.assigne }
			elseif o.assigne == moi and (o.statut == "prise" or o.statut == "mats") and recette.objet
				and (not partenaire or memePersonne(o.client, partenaire)) then
				liste[#liste + 1] = { commande = o, sens = "livrer", autre = o.client }
			end
		end
	end
	table.sort(liste, function(a, b)
		if a.commande.cree ~= b.commande.cree then return a.commande.cree < b.commande.cree end
		return a.commande.id < b.commande.id
	end)
	return liste
end

--- Les personnes à qui j'ai quelque chose à remettre, la plus ancienne commande d'abord (sans doublon).
function Assistance.partenaires(commandes, donnees, moi)
	local vus, liste = {}, {}
	for _, e in ipairs(concernees(commandes, donnees, moi, nil)) do
		if not vus[e.autre] then
			vus[e.autre] = true
			liste[#liste + 1] = e.autre
		end
	end
	return liste
end

--- Ce que je dois remettre à `partenaire` : { [itemID] = quantité } et les identifiants des commandes concernées.
function Assistance.requis(commandes, donnees, moi, partenaire)
	local requis, ids = {}, {}
	for _, e in ipairs(concernees(commandes, donnees, moi, partenaire)) do
		local o, recette = e.commande, donnees.recettes[e.commande.spell]
		if e.sens == "fournir" then
			for _, comp in ipairs(recette.composants or {}) do
				requis[comp[1]] = (requis[comp[1]] or 0) + comp[2] * o.qte
			end
		else
			requis[recette.objet] = (requis[recette.objet] or 0) + o.qte * (recette.qte or 1)
		end
		ids[#ids + 1] = o.id
	end
	return requis, ids
end

--- Ce qu'il reste à poser une fois déduit ce qui l'est déjà (`places` : { [itemID] = quantité }).
function Assistance.restant(requis, places)
	local reste = {}
	for id, n in pairs(requis) do
		local manque = n - (places[id] or 0)
		if manque > 0 then reste[id] = manque end
	end
	return reste
end

--- Emplacements à utiliser dans les sacs pour couvrir `restant`, au plus `maxEmplacements` (6 pour un échange, 12 pour
-- un courrier). `sacs` : liste de { bag, slot, itemID, count }. Les plus gros tas d'abord ; le dernier peut être fractionné
-- (`partiel`). Renvoie la liste ordonnée et ce qu'on ne trouve pas dans les sacs, ou ne peut pas poser faute de place.
function Assistance.placements(restant, sacs, maxEmplacements)
	local ids = {}
	for id in pairs(restant) do ids[#ids + 1] = id end
	table.sort(ids)

	local par = {}
	for _, s in ipairs(sacs) do
		par[s.itemID] = par[s.itemID] or {}
		table.insert(par[s.itemID], s)
	end

	local liste, manque = {}, {}
	for _, id in ipairs(ids) do
		local besoin = restant[id]
		local tas = par[id] or {}
		table.sort(tas, function(a, b)
			if a.count ~= b.count then return a.count > b.count end
			if a.bag ~= b.bag then return a.bag < b.bag end
			return a.slot < b.slot
		end)
		for _, s in ipairs(tas) do
			if besoin <= 0 or #liste >= maxEmplacements then break end
			local n = math.min(s.count, besoin)
			liste[#liste + 1] = { itemID = id, bag = s.bag, slot = s.slot, n = n, partiel = n < s.count }
			besoin = besoin - n
		end
		if besoin > 0 then manque[id] = besoin end
	end
	return liste, manque
end

return Assistance
