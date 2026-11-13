-- Rapprochement entre un échange (ou un courrier) et mes commandes. Lua pur, sans API du jeu.
-- `rapprocher` : côté crafteur, qui fait avancer la commande jusqu'à la livraison (voir Commandes).
-- `reception` : côté client, qui confirme la réception de l'objet fabriqué.
--   matériaux reçus du client      -> proposition « mats »     (commande prise)
--   objet fabriqué donné au client -> proposition « livrer » (commande prise ou matériaux reçus)
--   objet fabriqué reçu du crafteur -> proposition « confirmer » (commande livrée)
-- Le rapprochement ne décide rien : il propose, le joueur confirme (ou l'option d'automatisme applique).
local _, ns = ...

local Livraison = {}
ns.Livraison = Livraison

--- Premier mot d'un nom, en minuscules, sans le royaume. La fenêtre d'échange n'affiche que le prénom ; l'expéditeur
-- d'un courrier peut porter un royaume (« Prénom-Royaume »).
function Livraison.prenom(nom)
	if type(nom) ~= "string" then return nil end
	local p = nom:match("^[^%s%-]+")
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

--- Ajoute `n` unités de `id` au compteur `t`.
local function ajoute(t, id, n)
	if n > 0 then t[id] = (t[id] or 0) + n end
end

local function vide(t) return next(t) == nil end

--- Propositions pour un échange avec `partenaire`. `recu` et `donne` : { [itemID] = quantité }.
-- `cumul` (facultatif) : ce qui a déjà été remis pour chaque commande lors d'échanges ou de courriers précédents,
-- { [idCommande] = { recu = { [itemID] = n }, donne = { [itemID] = n } } }. Une livraison faite en plusieurs fois
-- s'additionne : la commande avance quand le total suffit.
-- Renvoie 1) une liste triée par ancienneté { { id, action = "mats" | "livrer" }, ... }
-- et 2) le nouveau cumul (les commandes qui avancent en sont retirées, celles qui reçoivent une partie y sont ajoutées).
function Livraison.rapprocher(commandes, donnees, moi, partenaire, recu, donne, cumul)
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

	-- Le cumul des commandes que cet échange ne concerne pas est conservé tel quel.
	local nouveau = {}
	for id, c in pairs(cumul or {}) do nouveau[id] = { recu = copie(c.recu), donne = copie(c.donne) } end

	local propositions = {}
	for _, o in ipairs(candidates) do
		local recette = donnees.recettes[o.spell]
		local fiche = nouveau[o.id] or { recu = {}, donne = {} }
		local action

		-- Objet fabriqué remis au client : la commande est terminée quand le total remis suffit.
		if (o.statut == "prise" or o.statut == "mats") and recette.objet then
			local besoin = o.qte * (recette.qte or 1)
			local deja = fiche.donne[recette.objet] or 0
			local dispo = restantDonne[recette.objet] or 0
			if deja + dispo >= besoin then
				restantDonne[recette.objet] = dispo - math.max(0, besoin - deja)
				action = "livrer"
			else
				ajoute(fiche.donne, recette.objet, dispo) -- remise partielle : on la garde pour la suite
				restantDonne[recette.objet] = 0
			end
		end

		-- Matériaux remis par le client : « tout » doit être couvert (en cumulant), « partie » se contente d'un composant.
		if not action and o.statut == "prise" and o.mats ~= "crafteur" then
			local couvre, un = true, false
			for _, comp in ipairs(recette.composants or {}) do
				local deja = fiche.recu[comp[1]] or 0
				local dispo = restantRecu[comp[1]] or 0
				if deja + dispo > 0 then un = true end
				if deja + dispo < comp[2] * o.qte then couvre = false end
			end
			if (o.mats == "tout" and couvre and un) or (o.mats == "partie" and un) then
				if o.mats == "tout" then
					for _, comp in ipairs(recette.composants) do
						local deja = fiche.recu[comp[1]] or 0
						restantRecu[comp[1]] = (restantRecu[comp[1]] or 0) - math.max(0, comp[2] * o.qte - deja)
					end
				end
				fiche.recu = {}
				action = "mats"
			elseif o.mats == "tout" then
				-- Remise partielle : chaque composant attendu est retenu, dans la limite de ce qu'il manque.
				for _, comp in ipairs(recette.composants or {}) do
					local manque = comp[2] * o.qte - (fiche.recu[comp[1]] or 0)
					local pris = math.min(restantRecu[comp[1]] or 0, math.max(0, manque))
					ajoute(fiche.recu, comp[1], pris)
					restantRecu[comp[1]] = (restantRecu[comp[1]] or 0) - pris
				end
			end
		end

		if action == "livrer" then
			nouveau[o.id] = nil
		elseif vide(fiche.recu) and vide(fiche.donne) then
			nouveau[o.id] = nil
		else
			nouveau[o.id] = fiche
		end
		if action then propositions[#propositions + 1] = { id = o.id, action = action } end
	end
	return propositions, nouveau
end

--- Réception côté client : l'objet fabriqué que mon crafteur m'a remis (échange ou courrier), additionné d'une remise à l'autre.
-- Propose « confirmer » quand la commande est **livrée** et que le total reçu suffit. Le crafteur déclare souvent la
-- livraison après l'échange : ce qui est reçu avant est donc retenu dans le cumul, et la proposition part dès que la commande
-- devient livrée (appel avec `recu` vide et `partenaire` nil). Même forme de cumul que `rapprocher`.
-- Renvoie 1) { { id, action = "confirmer" }, ... } 2) le nouveau cumul.
function Livraison.reception(commandes, donnees, moi, partenaire, recu, cumul)
	local restant = copie(recu)
	local candidates = {}
	for _, o in pairs(commandes) do
		local recette = donnees.recettes[o.spell]
		if o.client == moi and o.assigne and recette and recette.objet
			and (o.statut == "prise" or o.statut == "mats" or o.statut == "livree")
			and (partenaire == nil or Livraison.memePersonne(o.assigne, partenaire)) then
			candidates[#candidates + 1] = o
		end
	end
	table.sort(candidates, function(a, b)
		if a.cree ~= b.cree then return a.cree < b.cree end
		return a.id < b.id
	end)

	local nouveau = {}
	for id, c in pairs(cumul or {}) do nouveau[id] = { recu = copie(c.recu), donne = copie(c.donne) } end

	local propositions = {}
	for _, o in ipairs(candidates) do
		local recette = donnees.recettes[o.spell]
		local fiche = nouveau[o.id] or { recu = {}, donne = {} }
		local besoin = o.qte * (recette.qte or 1)
		local deja = fiche.recu[recette.objet] or 0
		local dispo = restant[recette.objet] or 0
		local pris = math.min(dispo, math.max(0, besoin - deja)) -- jamais plus que ce qui manque
		ajoute(fiche.recu, recette.objet, pris)
		restant[recette.objet] = dispo - pris

		if o.statut == "livree" and deja + pris >= besoin then
			propositions[#propositions + 1] = { id = o.id, action = "confirmer" }
			nouveau[o.id] = nil
		elseif vide(fiche.recu) and vide(fiche.donne) then
			nouveau[o.id] = nil
		else
			nouveau[o.id] = fiche
		end
	end
	return propositions, nouveau
end

--- Retire du cumul les commandes qui n'existent plus ou que je n'ai plus à suivre : annulée, terminée, libérée, ou reprise
-- par un autre (côté crafteur) ; terminée, annulée ou contestée (côté client : un cumul ne survit pas à une contestation).
function Livraison.purger(cumul, commandes, moi)
	for id in pairs(cumul) do
		local o = commandes[id]
		local crafteur = o and o.assigne == moi and (o.statut == "prise" or o.statut == "mats")
		local client = o and o.client == moi and o.assigne and (o.statut == "prise" or o.statut == "mats" or o.statut == "livree")
		if not (crafteur or client) then cumul[id] = nil end
	end
end

local function signature(courrier)
	local ids = {}
	for id in pairs(courrier.objets) do ids[#ids + 1] = id end
	table.sort(ids)
	local morceaux = { courrier.expediteur, courrier.sujet or "" }
	for _, id in ipairs(ids) do morceaux[#morceaux + 1] = id .. "x" .. courrier.objets[id] end
	return table.concat(morceaux, "\n")
end

--- Courriers dont les pièces jointes ont été retirées entre deux relevés de la boîte.
-- Un courrier est { expediteur, sujet, objets = { [itemID] = quantité } } ; seuls ceux qui ont des pièces jointes comptent.
-- Compare par contenu (et non par position, qui change quand un courrier disparaît) en tenant compte des doublons.
function Livraison.courriersRetires(avant, apres)
	local restant = {}
	for _, c in ipairs(apres) do
		if next(c.objets) then
			local s = signature(c)
			restant[s] = (restant[s] or 0) + 1
		end
	end
	local retires = {}
	for _, c in ipairs(avant) do
		if next(c.objets) then
			local s = signature(c)
			if (restant[s] or 0) > 0 then
				restant[s] = restant[s] - 1
			else
				retires[#retires + 1] = c
			end
		end
	end
	return retires
end

return Livraison
