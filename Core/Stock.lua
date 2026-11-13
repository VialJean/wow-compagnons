-- Stock des composants sur tous les personnages du compte, et liste de courses (phase 1 de docs/livraison.md).
-- Lua pur, sans API du jeu : le module Modules/Stocks.lua fournit les comptages.
--
--   stocks[cle] = { maj = 1731180062, [itemID] = quantité }   -- composants de la base seulement, quantités non nulles
local _, ns = ...

local Stock = {}
ns.Stock = Stock

Stock.ANCIEN = 7 * 24 * 3600 -- au-delà, le stock d'un personnage est signalé comme ancien

--- Relevé du personnage connecté : `compter(itemID)` renvoie la quantité en sacs et en banque.
function Stock.releve(donnees, compter, maintenant)
	local releve = { maj = maintenant }
	for itemID in pairs(donnees.objets or {}) do
		local n = compter(itemID) or 0
		if n > 0 then releve[itemID] = n end
	end
	return releve
end

--- Quantité mémorisée pour un personnage (0 si inconnu).
function Stock.quantite(stocks, cle, itemID)
	local s = stocks[cle]
	return s and s[itemID] or 0
end

--- Où se trouve un composant : { { cle, n, maj }, ... }, le plus fourni d'abord.
-- Le personnage connecté (`courant`) est lu en direct (`vivant`), les autres dans le dernier relevé.
function Stock.detail(stocks, itemID, miens, courant, vivant)
	local liste = {}
	for cle in pairs(miens) do
		local direct = cle == courant
		local n = direct and (vivant(itemID) or 0) or Stock.quantite(stocks, cle, itemID)
		if n > 0 then
			liste[#liste + 1] = { cle = cle, n = n, maj = (not direct) and stocks[cle] and stocks[cle].maj or nil }
		end
	end
	table.sort(liste, function(a, b)
		if a.n ~= b.n then return a.n > b.n end
		return a.cle < b.cle
	end)
	return liste
end

--- Quantité totale sur tous mes personnages.
function Stock.total(stocks, itemID, miens, courant, vivant)
	local total = 0
	for _, e in ipairs(Stock.detail(stocks, itemID, miens, courant, vivant)) do total = total + e.n end
	return total
end

--- Vrai si le dernier relevé d'un personnage date de plus de 7 jours.
function Stock.ancien(maj, maintenant)
	return maj ~= nil and maintenant - maj > Stock.ANCIEN
end

local function estFinale(o)
	return o.statut == "livree" or o.statut == "terminee" or o.statut == "annulee"
end

--- Liste de courses : les composants à réunir pour mes commandes en cours.
--   - commandes dont je suis le client, quand les composants ne sont pas fournis par le crafteur ;
--   - commandes que j'ai prises, quand c'est au crafteur de fournir les composants.
-- Un même composant demandé par plusieurs commandes est regroupé ; le stock n'est compté qu'une fois.
-- ctx : { commandes, miens, donnees, stocks, courant, vivant }
-- Renvoie { { itemID, nom, besoin, stock, manque, commandes, detail }, ... }, le plus manquant d'abord.
function Stock.courses(ctx)
	local parObjet = {}
	local function besoin(o)
		local r = ctx.donnees.recettes[o.spell]
		if not r then return end
		for _, comp in ipairs(r.composants or {}) do
			local e = parObjet[comp[1]]
			if not e then
				e = { itemID = comp[1], besoin = 0, commandes = 0 }
				parObjet[comp[1]] = e
			end
			e.besoin = e.besoin + comp[2] * o.qte
			e.commandes = e.commandes + 1
		end
	end

	for _, o in pairs(ctx.commandes or {}) do
		if not estFinale(o) then
			if ctx.miens[o.client] and o.mats ~= "crafteur" then
				besoin(o)
			elseif o.assigne and ctx.miens[o.assigne] and o.mats == "crafteur"
				and (o.statut == "prise" or o.statut == "mats") then
				besoin(o)
			end
		end
	end

	local liste = {}
	for itemID, e in pairs(parObjet) do
		local detail = Stock.detail(ctx.stocks, itemID, ctx.miens, ctx.courant, ctx.vivant)
		local total = 0
		for _, d in ipairs(detail) do total = total + d.n end
		local objet = ctx.donnees.objets and ctx.donnees.objets[itemID]
		liste[#liste + 1] = {
			itemID = itemID,
			nom = objet and objet[1] ~= "" and objet[1] or ("#" .. itemID),
			besoin = e.besoin,
			stock = total,
			manque = math.max(0, e.besoin - total),
			commandes = e.commandes,
			detail = detail,
		}
	end
	table.sort(liste, function(a, b)
		if a.manque ~= b.manque then return a.manque > b.manque end
		if a.nom ~= b.nom then return a.nom < b.nom end
		return a.itemID < b.itemID
	end)
	return liste
end

--- Texte de la liste pour le chat : « Manque : 13 Lotus pourpre, 5 Fiole vide ». Vide s'il ne manque rien.
function Stock.resume(liste, intitule, separateur)
	local morceaux = {}
	for _, e in ipairs(liste) do
		if e.manque > 0 then morceaux[#morceaux + 1] = e.manque .. " " .. e.nom end
	end
	if #morceaux == 0 then return "" end
	return intitule .. " " .. table.concat(morceaux, separateur or ", ")
end

return Stock
