-- Suivi automatique des fabrications (phase 2 de docs/livraison.md) : chaque fabrication réussie d'une recette que j'ai
-- prise fait avancer la progression de la commande (« 3/5 craftés »), et la guilde la voit.
-- Signal retenu, d'après le relevé en jeu : UNIT_SPELLCAST_SUCCEEDED du joueur, avec l'identifiant de la recette.
-- Les mises à jour sont regroupées : une fabrication en série n'envoie qu'un message quand elle s'arrête (ou toutes les 30 s).
local _, ns = ...
local Compagnons = ns.addon

local Fabrication = Compagnons:NewModule("Fabrication", "AceEvent-3.0")
ns.Fabrication = Fabrication

local DELAI_SILENCE = 5   -- secondes sans fabrication avant d'enregistrer
local ATTENTE_MAX = 30    -- au plus : une longue série est enregistrée par tranches
local MAX_VUS = 100       -- identifiants de lancers retenus pour ne pas compter deux fois le même

function Fabrication:OnEnable()
	self.attente = {}     -- [idCommande] = exemplaires fabriqués, pas encore enregistrés
	self.vus = {}
	self.nVus = 0
	self.jeton = 0
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "SurSort")
end

function Fabrication:Actif()
	return ns.db.profile.livraison.suivi
end

function Fabrication:SurSort(_, unite, castGUID, spellID)
	if unite ~= "player" or not self:Actif() then return end
	local recette = spellID and ns.Recettes.recettes[spellID]
	if not recette then return end

	-- Un même lancer peut être signalé deux fois : on le compte une seule.
	if castGUID then
		if self.vus[castGUID] then return end
		if self.nVus >= MAX_VUS then self.vus, self.nVus = {}, 0 end
		self.vus[castGUID] = true
		self.nVus = self.nVus + 1
	end

	local parts = ns.Progres.repartir(ns.db.global.commandes, ns.clePersonnage(), spellID,
		ns.Progres.parLancer(recette), self.attente)
	local rattache = false
	for id, n in pairs(parts) do
		self.attente[id] = (self.attente[id] or 0) + n
		rattache = true
	end
	if rattache then self:Programmer() end
end

--- Enregistre dans DELAI_SILENCE secondes si plus rien n'est fabriqué, ou tout de suite après ATTENTE_MAX.
function Fabrication:Programmer()
	local maintenant = GetTime()
	self.premier = self.premier or maintenant
	if maintenant - self.premier >= ATTENTE_MAX then
		self:Enregistrer()
		return
	end
	self.jeton = self.jeton + 1
	local jeton = self.jeton
	C_Timer.After(DELAI_SILENCE, function()
		if self.jeton == jeton then self:Enregistrer() end
	end)
end

--- Écrit la progression en attente dans les commandes et la diffuse.
function Fabrication:Enregistrer()
	local attente = self.attente
	self.attente, self.premier = {}, nil
	local moteur = ns.Reseau and ns.Reseau.moteur
	if not moteur then return end

	local change = false
	for id, n in pairs(attente) do
		local o = ns.db.global.commandes[id]
		if o and o.assigne then
			local total = math.min(ns.Commandes.crafte(o) + n, o.qte)
			if moteur:AgirCommande(id, "progres", o.assigne, { craftes = total }) then change = true end
		end
	end
	if change then Compagnons:SendMessage("COMPAGNONS_COMMANDES_MAJ") end
end
