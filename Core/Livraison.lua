-- Rapprochement entre un échange (ou un courrier) et mes commandes. Lua pur, sans API du jeu.
-- Côté crafteur uniquement : seul le crafteur assigné fait avancer une commande (voir Commandes).
--   matériaux reçus du client      -> proposition « mats »     (commande prise)
--   objet fabriqué donné au client -> proposition « terminer » (commande prise ou matériaux reçus)
-- Le rapprochement ne décide rien : il propose, le joueur confirme (ou l'option d'automatisme applique).
local _, ns = ...

local Livraison = {}
ns.Livraison = Livraison

--- Premier mot d'un nom, en minuscules. Le jeu n'affiche que le prénom dans la fenêtre d'échange.
function Livraison.prenom(nom)
	if type(nom) ~= "string" then return nil end
	local p = nom:match("^%S+")
	return p and p:lower() or nil
end

--- `partenaire` désigne-t-il le personnage `cle` ? Nom complet identique, sinon même prénom.
function Livraison.memePersonne(cle, partenaire)
	if not cle or not partenaire then return false end
	if cle == partenaire then return true end
	return Livraison.prenom(cle) == Livraison.prenom(partenaire)
end

local function copie(t)
	local c = {}
	for k, v in pairs(t or {}) do c[k] = v end
	return c
end

--- Propositions pour un échange avec `partenaire`. `recu` et `donne` : { [itemID] = quantité }.
-- Renvoie une liste triée par ancienneté { { id, action = "mats" | "terminer" }, ... }.
function Livraison.rapprocher(commandes, donnees, moi, partenaire, recu, donne)
	local restantRecu, restantDonne = copie(recu), copie(donne)
	local candidates = {}
	for _, o in pairs(commandes) do
		if o.assigne == moi and Livraison.memePersonne(o.client, partenaire) and donnees.recettes[o.spell] then
			candidates[#candidates + 1] = o
		end
	end
	table.sort(candidates, function(a, b)
		if a.cree ~= b.cree then return a.cree < b.cree end
		return a.id < b.id
	end)

	local propositions = {}
	for _, o in ipairs(candidates) do
		local recette = donnees.recettes[o.spell]
		local action

		-- Objet fabriqué remis au client : la commande est terminée.
		if (o.statut == "prise" or o.statut == "mats") and recette.objet then
			local besoin = o.qte * (recette.qte or 1)
			if (restantDonne[recette.objet] or 0) >= besoin then
				restantDonne[recette.objet] = restantDonne[recette.objet] - besoin
				action = "terminer"
			end
		end

		-- Matériaux remis par le client : « tout » doit être couvert, « partie » se contente d'un composant.
		if not action and o.statut == "prise" and o.mats ~= "crafteur" then
			local couvre, un = true, false
			for _, comp in ipairs(recette.composants or {}) do
				local dispo = restantRecu[comp[1]] or 0
				if dispo > 0 then un = true end
				if dispo < comp[2] * o.qte then couvre = false end
			end
			if (o.mats == "tout" and couvre and un) or (o.mats == "partie" and un) then
				if o.mats == "tout" then
					for _, comp in ipairs(recette.composants) do
						restantRecu[comp[1]] = restantRecu[comp[1]] - comp[2] * o.qte
					end
				end
				action = "mats"
			end
		end

		if action then propositions[#propositions + 1] = { id = o.id, action = action } end
	end
	return propositions
end

return Livraison
