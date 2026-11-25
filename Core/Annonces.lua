-- Petites annonces : des messages permanents de la guilde (« cherche un enchanteur pour… », « je fabrique des sacs »),
-- visibles de tous, qui durent jusqu'à leur retrait ou 30 jours sans reconduction. Lua pur, sans API WoW.
--
--   annonce = {
--     id = "Prénom Nom#1731180062#1",     -- unique : auteur, horodatage, compteur
--     auteur = "Prénom Nom",
--     texte = "Cherche enchanteur",       -- obligatoire, 200 caractères au plus
--     rev = 0, maj = 1731180062,          -- révision (une par modification) et dernière reconduction
--     retire = nil | true,                -- annonce retirée : la pierre tombale se propage avant d'être oubliée
--   }
--
-- Seul l'auteur écrit : la révision la plus haute gagne. Cinq annonces actives au plus par auteur.
local _, ns = ...

local Annonces = {}
ns.Annonces = Annonces

Annonces.DUREE = 30 * 24 * 3600        -- une annonce expire 30 jours après sa dernière reconduction
Annonces.DUREE_RETIREE = 7 * 24 * 3600 -- une annonce retirée est oubliée après 7 jours
Annonces.MAX_PAR_AUTEUR = 5

local MAX_TEXTE = 200
local MAX_ID = 96

local compteur = 0

local function texte(v, max)
	if type(v) ~= "string" then return nil end
	return v:sub(1, max)
end

function Annonces.hash(a)
	local morceaux = { a.id, a.auteur, a.texte, tostring(a.rev), tostring(a.maj), a.retire and "1" or "0" }
	return ns.Profil.adler(table.concat(morceaux, "\n"))
end

--- Crée une annonce. options : auteur, texte, maintenant. Renvoie nil et une raison si le texte est vide.
function Annonces.nouvelle(o)
	local t = texte(o.texte, MAX_TEXTE)
	if not t or t:match("^%s*$") then return nil, "texte" end
	compteur = compteur + 1
	local a = {
		id = string.format("%s#%d#%d", o.auteur, math.floor(o.maintenant), compteur),
		auteur = o.auteur, texte = t, rev = 0, maj = o.maintenant,
	}
	a.hash = Annonces.hash(a)
	return a
end

--- Valide et normalise une annonce reçue du réseau. Renvoie nil si elle est inutilisable.
function Annonces.valider(brut)
	if type(brut) ~= "table" then return nil end
	local id, auteur, t = texte(brut.id, MAX_ID), texte(brut.auteur, 64), texte(brut.texte, MAX_TEXTE)
	if not id or id == "" or not auteur or auteur == "" or not t or t:match("^%s*$") then return nil end
	for _, champ in ipairs({ "rev", "maj" }) do
		local v = brut[champ]
		if type(v) ~= "number" or v ~= v or v < 0 then return nil end
	end
	if brut.rev > 1000000 then return nil end
	-- L'identifiant commence par l'auteur : une annonce ne peut pas être écrite au nom d'un autre.
	if id:sub(1, #auteur + 1) ~= auteur .. "#" then return nil end
	local a = { id = id, auteur = auteur, texte = t, rev = math.floor(brut.rev), maj = brut.maj, retire = brut.retire == true or nil }
	a.hash = Annonces.hash(a)
	return a
end

--- Vrai si `a` l'emporte sur `b` : plus de révisions, puis reconduction la plus récente, puis hash.
function Annonces.meilleure(a, b)
	if a.rev ~= b.rev then return a.rev > b.rev end
	if a.maj ~= b.maj then return a.maj > b.maj end
	return a.hash > b.hash
end

--- À oublier : expirée (30 jours sans reconduction) ou retirée depuis plus de 7 jours.
function Annonces.perimee(a, maintenant)
	if a.retire then return maintenant - a.maj > Annonces.DUREE_RETIREE end
	return maintenant - a.maj > Annonces.DUREE
end

--- Copie de l'annonce après une action de son auteur. action : "reconduire", "modifier" (extra : texte) ou "retirer".
-- Renvoie nil et une raison si `par` n'est pas l'auteur.
function Annonces.appliquer(a, action, par, maintenant, extra)
	if par ~= a.auteur then return nil, "interdit" end
	if a.retire then return nil, "retiree" end
	local n = {}
	for k, v in pairs(a) do n[k] = v end
	n.rev = a.rev + 1
	n.maj = math.max(maintenant, a.maj)
	if action == "modifier" then
		local t = extra and texte(extra.texte, MAX_TEXTE)
		if not t or t:match("^%s*$") then return nil, "texte" end
		n.texte = t
	elseif action == "retirer" then
		n.retire = true
	elseif action ~= "reconduire" then
		return nil, "inconnue"
	end
	n.hash = Annonces.hash(n)
	return n
end

--- Nombre d'annonces actives (non retirées, non expirées) d'un auteur.
function Annonces.nombreActives(annonces, auteur, maintenant)
	local n = 0
	for _, a in pairs(annonces) do
		if a.auteur == auteur and not a.retire and not Annonces.perimee(a, maintenant) then n = n + 1 end
	end
	return n
end

--- Annonces visibles, triées : auteurs en ligne d'abord, puis les plus récentes. options : estEnLigne.
function Annonces.liste(annonces, options, maintenant)
	local liste = {}
	for _, a in pairs(annonces) do
		if not a.retire and not Annonces.perimee(a, maintenant) then liste[#liste + 1] = a end
	end
	local enLigne = options.estEnLigne or function() return false end
	table.sort(liste, function(a, b)
		local ea, eb = enLigne(a.auteur), enLigne(b.auteur)
		if ea ~= eb then return ea end
		if a.maj ~= b.maj then return a.maj > b.maj end
		return a.id < b.id
	end)
	return liste
end

--- Retire les annonces des auteurs qui ne sont plus membres de la guilde. `estMembre(cle)` renvoie vrai ou faux.
-- Renvoie le nombre d'annonces retirées de la table.
function Annonces.purgerAbsents(annonces, estMembre)
	local n = 0
	for id, a in pairs(annonces) do
		if not estMembre(a.auteur) then
			annonces[id] = nil
			n = n + 1
		end
	end
	return n
end

return Annonces
