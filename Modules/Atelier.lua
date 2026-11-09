-- Logique commune des commandes côté jeu : quels personnages sont à nous, qui peut remplir quoi,
-- et les actions de l'utilisateur. La fenêtre, le panneau, la minicarte et les alertes s'appuient dessus.
-- Message émis : COMPAGNONS_COMMANDES_MAJ (une commande a changé, localement ou depuis le réseau).
local _, ns = ...
local L = ns.L
local Compagnons = ns.addon

local Atelier = Compagnons:NewModule("Atelier", "AceEvent-3.0")
ns.Atelier = Atelier

function Atelier:OnEnable()
	self:RegisterMessage("COMPAGNONS_COMMANDE_RECUE", "SurCommandeRecue")
end

function Atelier:SurCommandeRecue()
	Compagnons:SendMessage("COMPAGNONS_COMMANDES_MAJ")
end

--- Table des commandes de la guilde (la même que celle du moteur de synchro).
function Atelier:Commandes()
	return ns.db.global.commandes
end

--- Ensemble des clés de nos personnages (tous ceux du compte).
function Atelier:Miens()
	local t = {}
	for cle in pairs(ns.db.global.personnages) do t[cle] = true end
	t[ns.clePersonnage()] = true
	return t
end

--- Clé de l'un de nos personnages qui connaît la recette (de préférence le personnage connecté), ou nil.
function Atelier:Connait(spellID)
	local moi = ns.clePersonnage()
	local trouve
	for _, c in ipairs(ns.catalogue:Crafteurs(spellID)) do
		if c.cle == moi then return moi end
		if not trouve and ns.db.global.personnages[c.cle] then trouve = c.cle end
	end
	return trouve
end

--- Les trois vues du tableau.
function Atelier:Vue(nom)
	local commandes, miens = self:Commandes(), self:Miens()
	if nom == "ouvertes" then
		return ns.Commandes.ouvertes(commandes)
	elseif nom == "pourmoi" then
		return ns.Commandes.pourMoi(commandes, miens, function(spell) return self:Connait(spell) end)
	end
	return ns.Commandes.miennes(commandes, miens)
end

--- Nombre de commandes que l'on peut remplir (pastille de la minicarte et de l'onglet).
function Atelier:CompterPourMoi()
	return #self:Vue("pourmoi")
end

--- Commandes d'un métier que l'on peut remplir, plus celles que l'on a prises : panneau de la fenêtre de métier.
function Atelier:PourMetier(idMetier)
	local miens = self:Miens()
	local liste = {}
	local vues = {}
	for _, o in ipairs(self:Vue("pourmoi")) do
		local r = ns.Recettes.recettes[o.spell]
		if r and r.metier == idMetier then
			liste[#liste + 1] = o
			vues[o.id] = true
		end
	end
	for _, o in ipairs(ns.Commandes.miennes(self:Commandes(), miens)) do
		local r = ns.Recettes.recettes[o.spell]
		if r and r.metier == idMetier and not vues[o.id] and o.assigne and miens[o.assigne]
			and not ns.Commandes.estFinale(o) then
			liste[#liste + 1] = o
		end
	end
	return liste
end

--- Actions que l'utilisateur peut faire sur une commande : liste de { action, libelle, principale, raison }.
-- `raison` non nil : l'action existe mais est impossible pour l'instant (infobulle).
function Atelier:ActionsPossibles(o)
	local miens = self:Miens()
	local actions = {}
	local function ajouter(action, libelle, principale, raison)
		actions[#actions + 1] = { action = action, libelle = libelle, principale = principale, raison = raison }
	end

	if o.statut == "ouverte" then
		if not miens[o.client] then
			local qui = self:Connait(o.spell)
			if qui and (not o.crafteur or miens[o.crafteur]) then
				local moi = ns.clePersonnage()
				ajouter("prendre", L.ACTION_PRENDRE, true, qui ~= moi and string.format(L.CONNECTE_TOI, qui) or nil)
			end
		end
	elseif (o.statut == "prise" or o.statut == "mats") and o.assigne and miens[o.assigne] then
		if o.statut == "prise" then ajouter("mats", L.ACTION_MATS, true) end
		ajouter("terminer", L.ACTION_TERMINER, o.statut == "mats")
		ajouter("liberer", L.ACTION_LIBERER, false)
	end
	if miens[o.client] and not ns.Commandes.estFinale(o) then
		ajouter("annuler", L.ACTION_ANNULER, false)
	end
	return actions
end

--- Libellé de statut, coloré par l'appelant.
function Atelier.LibelleStatut(o)
	if o.statut == "ouverte" then return L.STATUT_OUVERTE, "ffe0b252" end
	if o.statut == "prise" then return string.format(L.STATUT_PRISE, o.assigne or "?"), "ff7fb2ff" end
	if o.statut == "mats" then return L.STATUT_MATS, "ff7fb2ff" end
	if o.statut == "terminee" then return L.STATUT_TERMINEE, "ff5fd068" end
	return L.STATUT_ANNULEE, "ffa89c86"
end

function Atelier.LibelleMats(o)
	if o.mats == "tout" then return L.MATS_TOUT end
	if o.mats == "crafteur" then return L.MATS_CRAFTEUR end
	return L.MATS_PARTIE
end

--- « il y a 8 min »
function Atelier.Age(t)
	local s = math.max(0, time() - t)
	if s < 60 then return L.AGE_INSTANT end
	if s < 3600 then return string.format(L.AGE_MINUTES, math.floor(s / 60)) end
	if s < 86400 then return string.format(L.AGE_HEURES, math.floor(s / 3600)) end
	return string.format(L.AGE_JOURS, math.floor(s / 86400))
end

-- ---------------------------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------------------------

local function moteur()
	return ns.Reseau and ns.Reseau.moteur
end

--- Publie une commande de la part du personnage connecté. options : spell, qte, crafteur, mats, note.
function Atelier:Creer(options)
	local m = moteur()
	if not m then return nil, L.ACTION_IMPOSSIBLE end
	options.client = ns.clePersonnage()
	local c = m:CreerCommande(options)
	Compagnons:SendMessage("COMPAGNONS_COMMANDES_MAJ")
	return c
end

--- Fait avancer une commande. Renvoie la commande mise à jour, ou nil et un message.
function Atelier:Agir(o, action)
	local m = moteur()
	if not m then return nil, L.ACTION_IMPOSSIBLE end
	local miens = self:Miens()
	local par
	if action == "prendre" then
		par = ns.clePersonnage()
		if self:Connait(o.spell) ~= par then
			return nil, string.format(L.CONNECTE_TOI, self:Connait(o.spell) or "?")
		end
	elseif action == "annuler" then
		par = o.client
	else
		par = o.assigne
	end
	if not par or not miens[par] then return nil, L.ACTION_IMPOSSIBLE end

	local nouvelle, raison = m:AgirCommande(o.id, action, par)
	if not nouvelle then return nil, raison or L.ACTION_IMPOSSIBLE end
	Compagnons:SendMessage("COMPAGNONS_COMMANDES_MAJ")
	return nouvelle
end
