-- Commandes de craft : modèle, transitions autorisées et fusion des copies. Lua pur, sans API WoW.
--
--   commande = {
--     id = "Prénom Nom#1731180062#1",   -- unique : client, horodatage, compteur
--     client = "Prénom Nom",            -- qui commande
--     spell = 2329, qte = 5,            -- recette et quantité
--     crafteur = nil | "Prénom Nom",    -- crafteur désigné, ou nil : ouvert à tous
--     mats = "tout" | "partie" | "crafteur",   -- qui fournit les composants
--     note = "",                        -- 120 caractères au plus
--     statut = "ouverte" | "prise" | "mats" | "terminee" | "annulee",
--     assigne = nil | "Prénom Nom",     -- crafteur qui a pris la commande
--     rev = 0,                          -- numéro de révision : un par transition
--     cree = 1731180062, maj = 1731180062,   -- création, dernière transition
--     par = "Prénom Nom",               -- auteur de la dernière transition
--     histo = { { t, par, statut }, ... },   -- dernières transitions (10 au plus)
--   }
--
-- Cycle de vie : ouverte -> prise -> mats reçus -> terminée.
-- Le crafteur peut libérer (retour à « ouverte »), le client peut annuler. Seul le client annule,
-- seul le crafteur assigné fait avancer la commande.
local _, ns = ...

local Commandes = {}
ns.Commandes = Commandes

Commandes.DUREE_CONSERVATION = 7 * 24 * 3600 -- une commande terminée ou annulée disparaît après 7 jours

local MAX_NOTE = 120
local MAX_ID = 96
local MAX_QTE = 9999
local MAX_HISTO = 10

local STATUTS = { ouverte = true, prise = true, mats = true, terminee = true, annulee = true }
local MATS = { tout = true, partie = true, crafteur = true }

local compteur = 0

local function texte(v, max)
	if type(v) ~= "string" then return nil end
	return v:sub(1, max)
end

function Commandes.estFinale(o)
	return o.statut == "terminee" or o.statut == "annulee"
end

--- Une commande finale dont la dernière transition date de plus de 7 jours : à oublier partout.
function Commandes.perimee(o, maintenant)
	return Commandes.estFinale(o) and maintenant - o.maj > Commandes.DUREE_CONSERVATION
end

--- Nombre d'exemplaires fabriqués par le crafteur assigné (0 si rien n'est enregistré).
function Commandes.crafte(o)
	return o.progres and o.progres.craftes or 0
end

function Commandes.hash(o)
	local morceaux = {
		o.id, o.client, tostring(o.spell), tostring(o.qte), o.crafteur or "", o.mats, o.note or "",
		o.statut, o.assigne or "", tostring(o.rev), tostring(o.cree), tostring(o.maj), o.par or "",
		tostring(Commandes.crafte(o)),
	}
	return ns.Profil.adler(table.concat(morceaux, "\n"))
end

--- Crée une commande. options : client, spell, qte, crafteur, mats, note, maintenant.
function Commandes.nouvelle(o)
	compteur = compteur + 1
	local c = {
		id = string.format("%s#%d#%d", o.client, math.floor(o.maintenant), compteur),
		client = o.client,
		spell = o.spell,
		qte = math.max(1, math.min(MAX_QTE, math.floor(o.qte or 1))),
		crafteur = o.crafteur,
		mats = MATS[o.mats] and o.mats or "partie",
		note = texte(o.note or "", MAX_NOTE),
		statut = "ouverte",
		rev = 0,
		cree = o.maintenant,
		maj = o.maintenant,
		par = o.client,
		histo = { { o.maintenant, o.client, "ouverte" } },
	}
	c.hash = Commandes.hash(c)
	return c
end

--- Valide et normalise une commande reçue du réseau. Renvoie nil si elle est inutilisable.
function Commandes.valider(brut, donnees)
	if type(brut) ~= "table" then return nil end
	local id, client = texte(brut.id, MAX_ID), texte(brut.client, 64)
	if not id or id == "" or not client or client == "" then return nil end
	if type(brut.spell) ~= "number" or not donnees.recettes[brut.spell] then return nil end
	if not STATUTS[brut.statut] or not MATS[brut.mats] then return nil end
	for _, champ in ipairs({ "qte", "rev", "cree", "maj" }) do
		local v = brut[champ]
		if type(v) ~= "number" or v ~= v or v < 0 then return nil end
	end
	if brut.qte < 1 or brut.qte > MAX_QTE or brut.rev > 1000000 then return nil end

	local c = {
		id = id, client = client,
		spell = brut.spell, qte = math.floor(brut.qte),
		crafteur = texte(brut.crafteur, 64),
		mats = brut.mats,
		note = texte(brut.note or "", MAX_NOTE) or "",
		statut = brut.statut,
		assigne = texte(brut.assigne, 64),
		rev = math.floor(brut.rev), cree = brut.cree, maj = brut.maj,
		par = texte(brut.par, 64) or client,
		histo = {},
	}
	if type(brut.histo) == "table" then
		for i = 1, math.min(#brut.histo, MAX_HISTO) do
			local h = brut.histo[i]
			if type(h) == "table" and type(h[1]) == "number" and STATUTS[h[3]] then
				c.histo[#c.histo + 1] = { h[1], texte(h[2], 64) or "", h[3] }
			end
		end
	end

	-- Progression : un nombre d'exemplaires fabriqués, entre 0 et la quantité commandée. Sans crafteur, elle n'a pas de sens.
	if type(brut.progres) == "table" and type(brut.progres.craftes) == "number" and brut.progres.craftes == brut.progres.craftes
		and brut.progres.craftes > 0 and brut.assigne then
		c.progres = { craftes = math.min(math.floor(brut.progres.craftes), c.qte) }
	end

	-- Cohérence : une commande en cours a un crafteur, une commande ouverte n'en a pas.
	local enCours = c.statut == "prise" or c.statut == "mats" or c.statut == "terminee"
	if enCours and not c.assigne then return nil end
	if c.statut == "ouverte" and c.assigne then return nil end
	-- L'auteur de la dernière transition doit y avoir droit : le client annule, le crafteur assigné avance.
	if c.statut == "annulee" and c.par ~= c.client then return nil end
	if enCours and c.par ~= c.assigne then return nil end
	if c.crafteur and c.assigne and c.assigne ~= c.crafteur then return nil end
	c.hash = Commandes.hash(c)
	return c
end

--- Droits : qui peut faire quoi depuis quel état. Renvoie le nouveau statut, ou nil si interdit.
local function suivant(o, action, par, extra)
	local s = o.statut
	if action == "progres" then
		-- Le crafteur assigné fait avancer le nombre d'exemplaires fabriqués : sans changer d'état, et seulement vers le haut.
		local n = extra and extra.craftes
		if (s == "prise" or s == "mats") and par == o.assigne and type(n) == "number" and n == math.floor(n)
			and n >= Commandes.crafte(o) and n <= o.qte then
			return s
		end
		return nil
	elseif action == "prendre" then
		if s ~= "ouverte" then return nil end
		if o.crafteur and o.crafteur ~= par then return nil end
		return "prise"
	elseif action == "mats" then
		if s == "prise" and par == o.assigne then return "mats" end
	elseif action == "terminer" then
		if (s == "prise" or s == "mats") and par == o.assigne then return "terminee" end
	elseif action == "liberer" then
		if (s == "prise" or s == "mats") and par == o.assigne then return "ouverte" end
	elseif action == "annuler" then
		if not Commandes.estFinale(o) and par == o.client then return "annulee" end
	end
	return nil
end

--- Applique une action de `par` à la commande. Renvoie la nouvelle commande (la précédente n'est pas modifiée),
-- ou nil et une raison.
function Commandes.appliquer(o, action, par, maintenant, extra)
	local statut = suivant(o, action, par, extra)
	if not statut then return nil, "interdit" end
	local c = {}
	for k, v in pairs(o) do c[k] = v end
	c.statut = statut
	c.rev = o.rev + 1
	c.maj = math.max(maintenant, o.maj) -- jamais en arrière, même si les horloges diffèrent
	c.par = par
	if statut == "prise" then c.assigne = par end
	if statut == "ouverte" then
		c.assigne = nil
		c.progres = nil -- libérée : la progression ne suit pas la commande
	end
	if action == "progres" then
		-- Pas de ligne d'historique : il y en aurait une par fabrication.
		c.progres = { craftes = extra.craftes }
		c.hash = Commandes.hash(c)
		return c
	end
	c.histo = {}
	for i = math.max(1, #o.histo - MAX_HISTO + 2), #o.histo do c.histo[#c.histo + 1] = o.histo[i] end
	c.histo[#c.histo + 1] = { c.maj, par, statut }
	c.hash = Commandes.hash(c)
	return c
end

--- Vrai si `apres` est une suite légale de `avant` quand il n'y a qu'une révision d'écart.
function Commandes.transitionLegale(avant, apres)
	if apres.id ~= avant.id or apres.client ~= avant.client or apres.spell ~= avant.spell then return false end
	local par = apres.par

	-- Progression seule : même état, même crafteur, mêmes termes de la commande, nombre fabriqué en hausse.
	if apres.statut == avant.statut and (avant.statut == "prise" or avant.statut == "mats") then
		return par == avant.assigne and apres.assigne == avant.assigne
			and apres.qte == avant.qte and apres.mats == avant.mats and apres.crafteur == avant.crafteur
			and (apres.note or "") == (avant.note or "")
			and Commandes.crafte(apres) >= Commandes.crafte(avant) and Commandes.crafte(apres) <= apres.qte
	end
	local action
	if apres.statut == "prise" then action = "prendre"
	elseif apres.statut == "mats" then action = "mats"
	elseif apres.statut == "terminee" then action = "terminer"
	elseif apres.statut == "annulee" then action = "annuler"
	elseif apres.statut == "ouverte" then action = "liberer"
	end
	local attendu = action and suivant(avant, action, par)
	if attendu ~= apres.statut then return false end
	if apres.statut == "prise" and apres.assigne ~= par then return false end
	if (apres.statut == "mats" or apres.statut == "terminee" or apres.statut == "annulee")
		and apres.assigne ~= avant.assigne then
		return false
	end
	return true
end

--- Laquelle des deux copies doit être gardée : plus de révisions, puis action la plus ancienne,
-- puis ordre alphabétique de l'auteur, puis hash. Renvoie vrai si `a` l'emporte sur `b`.
function Commandes.meilleure(a, b)
	if a.rev ~= b.rev then return a.rev > b.rev end
	if a.maj ~= b.maj then return a.maj < b.maj end
	if (a.par or "") ~= (b.par or "") then return (a.par or "") < (b.par or "") end
	return a.hash > b.hash
end

-- ---------------------------------------------------------------------------------------------
-- Vues pour l'interface
-- ---------------------------------------------------------------------------------------------

--- Commandes triées : les plus récentes d'abord.
local function triees(liste)
	table.sort(liste, function(a, b)
		if a.maj ~= b.maj then return a.maj > b.maj end
		return a.id < b.id
	end)
	return liste
end

--- Commandes ouvertes de la guilde.
function Commandes.ouvertes(commandes)
	local liste = {}
	for _, o in pairs(commandes) do
		if o.statut == "ouverte" then liste[#liste + 1] = o end
	end
	return triees(liste)
end

--- Commandes que l'un de nos personnages peut remplir : ouvertes, recette connue d'un de nos personnages,
-- et pas passées par nous. `connait(spellID)` renvoie la clé de notre personnage qui connaît la recette.
function Commandes.pourMoi(commandes, miens, connait)
	local liste = {}
	for _, o in pairs(commandes) do
		if o.statut == "ouverte" and not miens[o.client] then
			local qui = connait(o.spell)
			if qui and (not o.crafteur or miens[o.crafteur]) then liste[#liste + 1] = o end
		end
	end
	return triees(liste)
end

--- Nos commandes : passées par nous, ou prises par l'un de nos personnages.
function Commandes.miennes(commandes, miens)
	local liste = {}
	for _, o in pairs(commandes) do
		if miens[o.client] or (o.assigne and miens[o.assigne]) then liste[#liste + 1] = o end
	end
	return triees(liste)
end

return Commandes
