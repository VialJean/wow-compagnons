-- Prix des composants (hôtel des ventes) et estimation de coût. Lua pur, sans API du jeu.
-- Le module Modules/Prix.lua relève les prix à l'hôtel des ventes ; ici : stockage, validation, coûts.
--
--   prix[itemID] = { p = prix unitaire en cuivre, t = horodatage du relevé }
local _, ns = ...

local Prix = {}
ns.Prix = Prix

local MAX_PRIX = 2000000000   -- 200 000 pièces d'or : au-delà, valeur aberrante
Prix.ANCIEN = 3 * 24 * 3600   -- un prix de plus de trois jours est signalé comme ancien

--- Enregistre un prix unitaire (en cuivre) : le plus récent gagne. Renvoie vrai si le prix a changé.
function Prix.enregistrer(prix, itemID, unitaire, maintenant)
	if type(itemID) ~= "number" or type(unitaire) ~= "number" or unitaire ~= unitaire then return false end
	unitaire = math.floor(unitaire + 0.5)
	if unitaire < 1 or unitaire > MAX_PRIX then return false end
	local actuel = prix[itemID]
	if actuel and actuel.t > maintenant then return false end -- on ne remplace pas par un relevé plus ancien
	if actuel and actuel.p == unitaire and actuel.t == maintenant then return false end
	prix[itemID] = { p = unitaire, t = maintenant }
	return true
end

--- Le prix unitaire le plus bas d'une liste de lots { { quantite, achat }, ... } (achat immédiat, en cuivre pour
-- tout le lot), ou nil s'il n'y a aucun lot à achat immédiat.
function Prix.minimum(lots)
	local meilleur
	for _, lot in ipairs(lots) do
		local quantite, achat = lot[1], lot[2]
		if type(quantite) == "number" and quantite > 0 and type(achat) == "number" and achat > 0 then
			local unitaire = achat / quantite
			if not meilleur or unitaire < meilleur then meilleur = unitaire end
		end
	end
	return meilleur
end

--- Prix unitaire connu, ou nil. Deuxième valeur : horodatage du relevé.
function Prix.unitaire(prix, itemID)
	local e = prix[itemID]
	if e then return e.p, e.t end
	return nil
end

function Prix.ancien(t, maintenant)
	return t ~= nil and maintenant - t > Prix.ANCIEN
end

--- Coût d'une liste de besoins { { itemID, quantite }, ... }.
-- Renvoie { total, inconnus (nombre de composants sans prix), anciens (nombre de prix anciens), plusAncien (horodatage) }.
function Prix.cout(prix, besoins, maintenant)
	local r = { total = 0, inconnus = 0, anciens = 0, plusAncien = nil }
	for _, b in ipairs(besoins) do
		local p, t = Prix.unitaire(prix, b[1])
		if b[2] > 0 then
			if p then
				r.total = r.total + p * b[2]
				if Prix.ancien(t, maintenant) then r.anciens = r.anciens + 1 end
				if not r.plusAncien or t < r.plusAncien then r.plusAncien = t end
			else
				r.inconnus = r.inconnus + 1
			end
		end
	end
	return r
end

--- Coût des composants d'une recette pour `qte` exemplaires.
function Prix.coutRecette(donnees, prix, spellID, qte, maintenant)
	local recette = donnees.recettes[spellID]
	local besoins = {}
	for _, comp in ipairs(recette and recette.composants or {}) do
		besoins[#besoins + 1] = { comp[1], comp[2] * qte }
	end
	return Prix.cout(prix, besoins, maintenant)
end

--- Coût du manque d'une liste de courses (voir Stock.courses). Chaque ligne reçoit aussi `cout` (nil si prix inconnu).
function Prix.coutListe(prix, liste, maintenant)
	local besoins = {}
	for _, e in ipairs(liste) do
		local p = Prix.unitaire(prix, e.itemID)
		e.prixUnitaire = p
		e.cout = (p and e.manque > 0) and p * e.manque or (p and 0 or nil)
		besoins[#besoins + 1] = { e.itemID, e.manque }
	end
	return Prix.cout(prix, besoins, maintenant)
end

--- Décompose un montant en cuivre : or, argent, cuivre.
function Prix.pieces(cuivre)
	cuivre = math.max(0, math.floor(cuivre or 0))
	return math.floor(cuivre / 10000), math.floor(cuivre / 100) % 100, cuivre % 100
end

--- « 12 po 34 pa » : les petites unités disparaissent au-delà de 10 pièces d'or. Sert quand le jeu n'en fournit pas.
function Prix.texte(cuivre, unites)
	unites = unites or { or_ = "g", argent = "s", cuivre = "c" }
	local o, a, c = Prix.pieces(cuivre)
	if o >= 10 then return string.format("%d%s", o, unites.or_) end
	local morceaux = {}
	if o > 0 then morceaux[#morceaux + 1] = o .. unites.or_ end
	if a > 0 or (o > 0 and c > 0) then morceaux[#morceaux + 1] = a .. unites.argent end
	if c > 0 or #morceaux == 0 then morceaux[#morceaux + 1] = c .. unites.cuivre end
	return table.concat(morceaux, " ")
end

--- Convertit « 12 », « 12.5 », « 12g 5s 3c » ou « 125000 cuivre » : renvoie des cuivres, ou nil.
-- Un nombre seul est en pièces d'or.
function Prix.lire(texte)
	if type(texte) ~= "string" then return nil end
	texte = texte:lower():gsub(",", ".")
	local seul = tonumber(texte)
	if seul then return math.floor(seul * 10000 + 0.5) end
	local total, trouve = 0, false
	for nombre, unite in texte:gmatch("([%d%.]+)%s*([gsc])") do
		local n = tonumber(nombre)
		if not n then return nil end
		trouve = true
		total = total + n * ((unite == "g") and 10000 or (unite == "s") and 100 or 1)
	end
	if not trouve then return nil end
	return math.floor(total + 0.5)
end

return Prix
