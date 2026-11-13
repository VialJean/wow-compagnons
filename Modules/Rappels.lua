-- Rappels à la connexion (docs/v5.md, §3.2-3.3) : les commandes qui n'avancent pas, et les vieilles commandes ouvertes.
-- Le calcul est dans Core/Rappels.lua. Une seule fois par jour et par personnage (CompagnonsPersoDB.rappelLe), pas à chaque
-- rechargement. Un rappel ne fait rien tout seul : il signale, et l'annulation des commandes anciennes demande un clic.
local _, ns = ...
local L = ns.L
local Compagnons = ns.addon

local Rappels = Compagnons:NewModule("Rappels", "AceEvent-3.0")
ns.RappelsModule = Rappels

local DELAI_CONNEXION = 30 -- après la synchro de guilde (8 s) et l'avertissement de version (20 s)

local function securise(etape, fn, ...)
	local ok, resultat = pcall(fn, ...)
	if not ok then
		ns.log("erreur", "rappels", "%s : %s", etape, tostring(resultat))
		return nil
	end
	return resultat
end

function Rappels:OnEnable()
	StaticPopupDialogs["COMPAGNONS_ANCIENNES"] = {
		text = "%s",
		button1 = L.RAPPEL_ANNULER,
		button2 = L.RAPPEL_GARDER,
		OnAccept = function(_, data) Rappels:Annuler(data) end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	C_Timer.After(DELAI_CONNEXION, function() securise("rappels", self.Lancer, self, false) end)
end

--- Réglages : `profile.rappels` (actif, expiration, délais en jours).
function Rappels:Reglages()
	return ns.db.profile.rappels
end

--- Texte d'un groupe de rappels (nombre et ancienneté de la plus ancienne), ou nil.
local function fragment(genre, groupe)
	if not groupe then return nil end
	local modele = ({
		a_confirmer = L.RAPPEL_A_CONFIRMER, sans_preneur = L.RAPPEL_SANS_PRENEUR,
		sans_progres = L.RAPPEL_SANS_PROGRES, en_attente = L.RAPPEL_EN_ATTENTE,
	})[genre]
	return modele and string.format(modele, groupe.n, groupe.jours)
end

--- Calcule et affiche les rappels. `force` : même si on les a déjà donnés aujourd'hui (/cpg rappels now).
function Rappels:Lancer(force)
	local reglages = self:Reglages()
	if not reglages.actif and not force then return end
	local aujourdhui = date("%Y%m%d")
	if not force and CompagnonsPersoDB and CompagnonsPersoDB.rappelLe == aujourdhui then return end

	local miens = ns.Atelier:Miens()
	local commandes = ns.db.global.commandes
	local liste = ns.Rappels.calculer(commandes, miens, time(), reglages)
	local anciennes = reglages.expiration and ns.Rappels.anciennes(commandes, miens, time(), reglages.ancienne) or {}

	if #liste == 0 and #anciennes == 0 then
		if force then Compagnons:Print(L.RAPPEL_RIEN) end
		return
	end
	if CompagnonsPersoDB then CompagnonsPersoDB.rappelLe = aujourdhui end

	if #liste > 0 then
		local groupes = ns.Rappels.resumer(liste)
		local morceaux = {}
		for _, genre in ipairs(ns.Rappels.GENRES) do
			local texte = fragment(genre, groupes[genre])
			if texte then morceaux[#morceaux + 1] = texte end
		end
		-- Dans le cadre d'alertes (qui attend la fin d'un combat) et dans le chat.
		if ns.Alertes then ns.Alertes:Poster(L.RAPPEL_TITRE, table.concat(morceaux, " · "), "mes") end
	end
	if #anciennes > 0 then
		local jours = reglages.ancienne or ns.Rappels.DEFAUTS.ancienne
		securise("proposition d'annulation", StaticPopup_Show, "COMPAGNONS_ANCIENNES",
			string.format(L.RAPPEL_ANCIENNES, #anciennes, jours), nil, anciennes)
	end
end

--- Annule les commandes anciennes proposées (le joueur a cliqué). Seul le client annule : ce sont les siennes.
function Rappels:Annuler(anciennes)
	local n = 0
	for _, o in ipairs(anciennes or {}) do
		local courante = ns.db.global.commandes[o.id]
		if courante and courante.statut == "ouverte" and ns.Atelier:Agir(courante, "annuler") then n = n + 1 end
	end
	Compagnons:Print(string.format(L.RAPPEL_ANNULEES, n))
end

-- ---------------------------------------------------------------------------------------------
-- /cpg rappels
-- ---------------------------------------------------------------------------------------------

function Rappels:Commande(arg)
	local action = type(arg) == "string" and arg:lower() or ""
	local reglages = self:Reglages()
	if action == "on" then
		reglages.actif = true
	elseif action == "off" then
		reglages.actif = false
	elseif action == "now" then
		self:Lancer(true)
		return
	end
	Compagnons:Print(string.format(L.RAPPEL_ETAT, reglages.actif and L.INFO_ACTIVE or L.INFO_DESACTIVE))
end
