-- Petites annonces côté jeu : publier, modifier, retirer, reconduire à la connexion, purger les auteurs partis. Le modèle est dans
-- Core/Annonces.lua, la synchro dans Core/Synchro.lua. Message émis : COMPAGNONS_ANNONCES_MAJ (une annonce a changé).
local _, ns = ...
local L = ns.L
local Compagnons = ns.addon

local Annonces = Compagnons:NewModule("AnnoncesModule", "AceEvent-3.0")
ns.AnnoncesModule = Annonces

local DELAI_CONNEXION = 45 -- après la synchro de guilde (8 s) : on reconduit ce qu'on a déjà reçu des autres appareils

local function securise(etape, fn, ...)
	local ok, resultat = pcall(fn, ...)
	if not ok then
		ns.log("erreur", "annonces", "%s : %s", etape, tostring(resultat))
		return nil
	end
	return resultat
end

local function moteur()
	return ns.Reseau and ns.Reseau.moteur
end

function Annonces:OnEnable()
	self:RegisterMessage("COMPAGNONS_ANNONCES_MAJ", "SurMaj")
	C_Timer.After(DELAI_CONNEXION, function() securise("reconduction", self.Reconduire, self) end)
end

function Annonces:SurMaj() end

--- Table des annonces de la guilde (la même que celle du moteur de synchro).
function Annonces:Toutes()
	return ns.db.global.annonces
end

--- Publie une annonce au nom du personnage connecté. options : texte. Renvoie l'annonce, ou nil et
-- un message pour le joueur.
function Annonces:Publier(options)
	local m = moteur()
	if not m then return nil, L.ACTION_IMPOSSIBLE end
	options.auteur = ns.clePersonnage()
	local a, raison = m:CreerAnnonce(options)
	if not a then return nil, raison == "limite" and string.format(L.ANNONCES_LIMITE, ns.Annonces.MAX_PAR_AUTEUR) or L.ACTION_IMPOSSIBLE end
	Compagnons:SendMessage("COMPAGNONS_ANNONCES_MAJ")
	return a
end

--- Retire une de nos annonces.
function Annonces:Retirer(a)
	local m = moteur()
	if not m or not self:EstMienne(a) then return nil end
	local n = m:AgirAnnonce(a.id, "retirer", a.auteur)
	if n then Compagnons:SendMessage("COMPAGNONS_ANNONCES_MAJ") end
	return n
end

--- Vrai si l'annonce est celle d'un de nos personnages.
function Annonces:EstMienne(a)
	return ns.db.global.personnages[a.auteur] ~= nil or a.auteur == ns.clePersonnage()
end

--- À la connexion : reconduit les annonces du personnage connecté (30 jours de plus), et purge les annonces des membres qui
-- ont quitté la guilde (seulement une fois la liste de guilde reçue).
function Annonces:Reconduire()
	local m = moteur()
	if not m then return end
	local moi = ns.clePersonnage()
	local ids = {}
	for id, a in pairs(self:Toutes()) do
		if a.auteur == moi and not a.retire then ids[#ids + 1] = id end
	end
	table.sort(ids)
	for _, id in ipairs(ids) do m:AgirAnnonce(id, "reconduire", moi) end
	local membres = ns.Reseau.membres
	if membres then
		ns.Annonces.purgerAbsents(self:Toutes(), function(cle) return membres[cle] or ns.db.global.personnages[cle] ~= nil end)
	end
	if #ids > 0 then Compagnons:SendMessage("COMPAGNONS_ANNONCES_MAJ") end
end
