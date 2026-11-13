-- Pairs dont la version du protocole diffère de la nôtre (docs/v5.md, §2.7). Lua pur, sans API du jeu.
--
-- Un message d'une autre version est ignoré par la synchro, mais sa version se lit toujours (l'enveloppe ne change jamais, voir
-- docs/protocole.md) : on retient qui est resté en arrière, pour le dire au joueur et prévenir la personne concernée.
--
--   etat = {
--     pairs = { [cle] = { v = 2, vu = <heure>, brut = "Prénom-Nom", averti = <heure du dernier chuchotement> | nil } },
--     plusRecente = nil | 4,      -- plus grande version de protocole vue chez un pair, si elle dépasse la nôtre
--   }
-- `etat` est enregistré (CompagnonsDB.global.versions) : « averti » doit survivre à une déconnexion, sinon chaque connexion
-- relancerait un chuchotement.
local _, ns = ...

local Versions = {}
ns.Versions = Versions

Versions.JOUR = 24 * 3600
Versions.OUBLI = 14 * 24 * 3600 -- un pair obsolète qu'on n'a pas vu depuis 14 jours n'est plus signalé
local MAX_PAIRS = 200            -- au-delà, de nouveaux pairs obsolètes sont ignorés (message forgé en masse)

function Versions.nouveau()
	return { pairs = {} }
end

--- Note la version annoncée par un pair. Renvoie ce qu'il y a de neuf :
--   "nouveau"      un pair vient d'apparaître en version trop ancienne
--   "obsolete"     un pair déjà signalé est toujours en retard
--   "misajour"     un pair signalé est revenu à notre version
--   "ajour"        même version que nous (rien à faire)
--   "plusrecente"  un pair a une version plus récente que la nôtre, qu'on n'avait pas encore vue
--   "plusrecent"   idem, déjà vue
--   nil            version illisible, ou trop de pairs
function Versions.noter(etat, cle, v, maintenant, protocole, brut)
	if type(cle) ~= "string" or cle == "" or type(v) ~= "number" or v ~= v or v < 1 or v ~= math.floor(v) then return nil end
	if v == protocole then
		if etat.pairs[cle] then
			etat.pairs[cle] = nil
			return "misajour"
		end
		return "ajour"
	end
	if v > protocole then
		if etat.plusRecente and etat.plusRecente >= v then return "plusrecent" end
		etat.plusRecente = v
		return "plusrecente"
	end

	local e = etat.pairs[cle]
	local nouveau = e == nil
	if nouveau then
		local n = 0
		for _ in pairs(etat.pairs) do n = n + 1 end
		if n >= MAX_PAIRS then return nil end
		e = {}
		etat.pairs[cle] = e
	end
	e.v = v
	e.vu = maintenant
	e.brut = type(brut) == "string" and brut:sub(1, 64) or cle
	return nouveau and "nouveau" or "obsolete"
end

--- Oublie ce qui n'a plus lieu d'être : les pairs qu'on n'a pas vus depuis longtemps, et la « version plus récente » que notre
-- propre version a rattrapée (l'addon a été mis à jour).
function Versions.purger(etat, maintenant, protocole)
	for cle, e in pairs(etat.pairs) do
		if maintenant - e.vu > Versions.OUBLI or e.v >= protocole then etat.pairs[cle] = nil end
	end
	if etat.plusRecente and etat.plusRecente <= protocole then etat.plusRecente = nil end
end

--- Les pairs obsolètes, par ordre alphabétique : { { cle, v, vu, brut, averti }, ... }.
function Versions.obsoletes(etat, maintenant, protocole)
	Versions.purger(etat, maintenant, protocole)
	local liste = {}
	for cle, e in pairs(etat.pairs) do
		liste[#liste + 1] = { cle = cle, v = e.v, vu = e.vu, brut = e.brut, averti = e.averti }
	end
	table.sort(liste, function(a, b) return a.cle < b.cle end)
	return liste
end

--- Version plus récente que la nôtre vue chez un pair, ou nil.
function Versions.plusRecente(etat, protocole)
	local v = etat.plusRecente
	if v and v > protocole then return v end
	return nil
end

--- Pairs à qui écrire. `premiereFois` : seulement ceux qu'on n'a jamais prévenus (envoi automatique) ; sinon ceux qu'on n'a pas
-- prévenus depuis un jour (le bouton « Les prévenir »). Au plus un chuchotement par personne et par jour.
function Versions.aPrevenir(etat, maintenant, protocole, premiereFois)
	local liste = {}
	for _, p in ipairs(Versions.obsoletes(etat, maintenant, protocole)) do
		local ok
		if premiereFois then
			ok = p.averti == nil
		else
			ok = p.averti == nil or maintenant - p.averti >= Versions.JOUR
		end
		if ok then liste[#liste + 1] = p end
	end
	return liste
end

--- Retient qu'on vient de prévenir ce pair.
function Versions.marquer(etat, cle, maintenant)
	local e = etat.pairs[cle]
	if e then e.averti = maintenant end
end

return Versions
