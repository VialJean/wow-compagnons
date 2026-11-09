-- Prix des composants (hôtel des ventes) et estimation de coût. Lua pur, sans API du jeu.
-- Le module Modules/Marche.lua relève les prix à l'hôtel des ventes ; ici : stockage, validation, coûts.
--
--   prix[itemID] = { p = prix unitaire en cuivre, t = horodatage du relevé }
local _, ns = ...

local Prix = {}
ns.Prix = Prix

local MAX_PRIX = 2000000000   -- 200 000 pièces d'or : au-delà, valeur aberrante
Prix.ANCIEN = 3 * 24 * 3600   -- un prix de plus de trois jours est signalé comme ancien

--- `a` l'emporte-t-il sur `b` ? Entrées { p, t, v } (v : prix d'un vendeur PNJ).
-- Un prix de vendeur l'emporte sur un relevé de l'hôtel des ventes : c'est le coût réel, sans limite de stock. Entre deux
-- prix de vendeur, le plus haut (le prix de base : une réputation ne fait que baisser le prix). Entre deux relevés de l'hôtel
-- des ventes, le plus récent, et à date égale le moins cher. Ordre total : tous les clients tranchent pareil.
function Prix.bat(a, b)
	if not b then return true end
	local va, vb = a.v == true, b.v == true
	if va ~= vb then return va end
	if va then return a.p > b.p end
	if a.t ~= b.t then return a.t > b.t end
	return a.p < b.p
end

--- Enregistre un prix unitaire (en cuivre). `pnj` : prix d'un vendeur. Renvoie vrai si le prix a changé.
function Prix.enregistrer(prix, itemID, unitaire, maintenant, pnj)
	if type(itemID) ~= "number" or type(unitaire) ~= "number" or unitaire ~= unitaire then return false end
	unitaire = math.floor(unitaire + 0.5)
	if unitaire < 1 or unitaire > MAX_PRIX then return false end
	local nouveau = { p = unitaire, t = maintenant, v = pnj and true or nil }
	if not Prix.bat(nouveau, prix[itemID]) then return false end
	prix[itemID] = nouveau
	return true
end

Prix.MAX_LOT = 200            -- un message qui annonce plus de prix est ignoré en entier
Prix.TOLERANCE_FUTUR = 300    -- un horodatage plus loin dans le futur est refusé (horloges qui diffèrent un peu)

--- Valide un lot de prix reçu du réseau : { [itemID] = { p, t } }. Ne garde que les composants de la base, avec un prix
-- plausible et un horodatage qui n'est pas dans le futur. Un lot trop gros est refusé en entier.
function Prix.valider(brut, donnees, maintenant)
	local valides = {}
	if type(brut) ~= "table" then return valides end
	local n = 0
	for _ in pairs(brut) do
		n = n + 1
		if n > Prix.MAX_LOT then return {} end
	end
	for itemID, e in pairs(brut) do
		if type(itemID) == "number" and donnees.objets and donnees.objets[itemID] and type(e) == "table"
			and type(e.p) == "number" and type(e.t) == "number" and e.p == e.p and e.t == e.t
			and e.p >= 1 and e.p <= MAX_PRIX and e.t >= 0 and e.t <= maintenant + Prix.TOLERANCE_FUTUR then
			valides[itemID] = { p = math.floor(e.p + 0.5), t = e.t, v = e.v == true and true or nil }
		end
	end
	return valides
end

--- Fusionne des prix déjà validés : le plus récent gagne. Renvoie la liste des identifiants modifiés.
function Prix.fusionner(prix, valides)
	local changes = {}
	for itemID, e in pairs(valides) do
		if Prix.enregistrer(prix, itemID, e.p, e.t, e.v) then changes[#changes + 1] = itemID end
	end
	table.sort(changes)
	return changes
end

--- Somme de contrôle des prix (identifiant, prix, date), indépendante de l'ordre de parcours.
function Prix.hash(prix)
	local ids = {}
	for id in pairs(prix) do ids[#ids + 1] = id end
	table.sort(ids)
	local morceaux = {}
	for i, id in ipairs(ids) do morceaux[i] = id .. ":" .. prix[id].p .. ":" .. prix[id].t .. (prix[id].v and ":v" or "") end
	return ns.Profil.adler(table.concat(morceaux, ";"))
end

--- Résumé { [itemID] = { t, p, v } } (v : 1 pour un prix de vendeur) : ce qu'on annonce à un pair pour savoir qui a le
-- meilleur prix. Les deux premières cases suffisent à un client qui ne connaît pas les prix de vendeur.
function Prix.horodatages(prix)
	local t = {}
	for id, e in pairs(prix) do t[id] = { e.t, e.p, e.v and 1 or 0 } end
	return t
end

--- Convertit un résumé distant { t, p, v } en entrée comparable, ou nil s'il est invalide.
function Prix.depuisResume(r)
	if type(r) ~= "table" or type(r[1]) ~= "number" or type(r[2]) ~= "number" then return nil end
	return { t = r[1], p = r[2], v = r[3] == 1 or nil }
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
	if e then return e.p, e.t, e.v == true end
	return nil
end

function Prix.ancien(t, maintenant, pnj)
	return not pnj and t ~= nil and maintenant - t > Prix.ANCIEN
end

--- Coût d'une liste de besoins { { itemID, quantite }, ... }.
-- Renvoie { total, inconnus (nombre de composants sans prix), anciens (nombre de prix anciens), plusAncien (horodatage) }.
function Prix.cout(prix, besoins, maintenant)
	local r = { total = 0, inconnus = 0, anciens = 0, plusAncien = nil }
	for _, b in ipairs(besoins) do
		local p, t, pnj = Prix.unitaire(prix, b[1])
		if b[2] > 0 then
			if p then
				r.total = r.total + p * b[2]
				if Prix.ancien(t, maintenant, pnj) then r.anciens = r.anciens + 1 end
				if not pnj and (not r.plusAncien or t < r.plusAncien) then r.plusAncien = t end
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
