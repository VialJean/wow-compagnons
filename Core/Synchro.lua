-- Moteur de synchronisation de guilde : profils des personnages et commandes de craft.
-- Lua pur : le transport, l'horloge et les temporisations sont fournis de l'extérieur, ce qui permet de
-- le tester avec des dizaines de clients simulés.
--
-- Messages (voir docs/protocole.md) :
--   HELLO        GUILD    { v, h, n }              annonce : hash global et nombre de profils
--   PRET         WHISPER  { v, h }                 un pair dont le hash diffère se propose (minuscule)
--   HASHES       WHISPER  { v, liste = { p = { [cle] = { maj, hash } }, c = { [id] = { rev, maj, par, hash } } } }
--                                                  envoyé par l'annonceur au premier pair prêt
--   PROFILE_REQ  WHISPER  { v, cles = {...}, ids = {...} }   profils et commandes demandés
--   PROFILE      WHISPER  { v, profil }            un profil transmis pendant une synchro
--   ORDER        WHISPER  { v, commande }          une commande transmise pendant une synchro
--   PROFILE_UPD  GUILD    { v, profil }            un personnage vient d'être scanné
--   ORDER_NEW    GUILD    { v, commande }          une commande vient d'être créée
--   ORDER_UPD    GUILD    { v, commande }          une commande vient de changer d'état
local _, ns = ...

local Synchro = {}
Synchro.__index = Synchro
ns.Synchro = Synchro

Synchro.PROTOCOLE = 2

local FENETRE_PARTENAIRE = 20 -- secondes pendant lesquelles on ne synchronise qu'avec un seul pair
local DELAI_REPONSE = 2       -- les pairs répondent après un délai aléatoire borné par cette valeur
local DELAI_REANNONCE = 5     -- regroupe plusieurs changements en une seule annonce
local MAX_DEMANDES = 400
local MAX_COMMANDES = 600     -- au-delà, les nouvelles commandes reçues sont ignorées

--- options :
--   donnees       ns.Recettes
--   profils       table cle -> profil (tous les profils connus, y compris les nôtres)
--   commandes     table id -> commande
--   moi           fonction -> clé du personnage connecté
--   proprietaire  fonction(cle) -> vrai si le personnage est à nous (le réseau ne peut pas écraser son profil)
--   envoyer       fonction(canal, cible, genre, charge)   canal = "GUILD" | "WHISPER"
--   maintenant    fonction -> secondes
--   planifier     fonction(delai, fn)
--   alea          fonction -> nombre dans [0, 1[
--   normaliser    fonction(expéditeur brut) -> clé (par défaut : « Prénom-Nom » devient « Prénom Nom »)
--   surMaj        fonction(cle) appelée quand un profil est modifié depuis le réseau
--   surCommande   fonction(id, avant, apres) appelée quand une commande change depuis le réseau
--   journal       fonction(niveau, format, ...)
function Synchro.nouveau(o)
	local s = setmetatable({}, Synchro)
	s.donnees = o.donnees
	s.profils = o.profils
	s.commandes = o.commandes or {}
	s.moi = o.moi
	s.proprietaire = o.proprietaire or function() return false end
	s.envoyerBrut = o.envoyer
	s.maintenant = o.maintenant
	s.planifier = o.planifier
	s.alea = o.alea or math.random
	s.normaliser = o.normaliser or function(brut) return (brut:gsub("%-", " ")) end
	s.surMaj = o.surMaj or function() end
	s.surCommande = o.surCommande or function() end
	s.journal = o.journal or function() end
	s.partenaire = nil
	s.partenaireJusqua = 0
	s.reponduA = {}      -- [expéditeur] = état auquel on a déjà répondu
	s.annoncePrevue = false
	s.stats = { envoyes = 0, recus = 0, parGenre = {} }
	return s
end

function Synchro:Envoyer(canal, cible, genre, charge)
	self.stats.envoyes = self.stats.envoyes + 1
	self.stats.parGenre[genre] = (self.stats.parGenre[genre] or 0) + 1
	self.envoyerBrut(canal, cible, genre, charge)
end

--- Hash global : somme de contrôle des listes triées « clé:hash » des profils et des commandes.
function Synchro:HashGlobal()
	local function liste(table_)
		local cles = {}
		for cle in pairs(table_) do cles[#cles + 1] = cle end
		table.sort(cles)
		local morceaux = {}
		for i, cle in ipairs(cles) do morceaux[i] = cle .. ":" .. table_[cle].hash end
		return table.concat(morceaux, ";")
	end
	return ns.Profil.adler(liste(self.profils) .. "|" .. liste(self.commandes))
end

function Synchro:Compter()
	local n = 0
	for _ in pairs(self.profils) do n = n + 1 end
	return n
end

function Synchro:CompterCommandes()
	local n = 0
	for _ in pairs(self.commandes) do n = n + 1 end
	return n
end

--- Oublie les commandes terminées ou annulées depuis plus de 7 jours. Tous les clients appliquent la même règle.
function Synchro:Nettoyer()
	local maintenant = self.maintenant()
	for id, c in pairs(self.commandes) do
		if ns.Commandes.perimee(c, maintenant) then self.commandes[id] = nil end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Émission
-- ---------------------------------------------------------------------------------------------

--- Annonce notre état à la guilde (à la connexion, puis après chaque changement reçu).
function Synchro:Annoncer()
	self.annoncePrevue = false
	self.partenaire = nil -- nouvelle ronde : on peut de nouveau choisir un partenaire
	self.partenaireJusqua = 0
	self:Nettoyer()
	self:Envoyer("GUILD", nil, "HELLO", { v = Synchro.PROTOCOLE, h = self:HashGlobal(), n = self:Compter() })
end

function Synchro:ProgrammerAnnonce()
	if self.annoncePrevue then return end
	self.annoncePrevue = true
	self.planifier(DELAI_REANNONCE, function() self:Annoncer() end)
end

--- Enregistre un de nos propres profils (après un scan) et le diffuse.
function Synchro:Publier(profil)
	local p = ns.Profil.valider(profil, self.donnees)
	if not p then return false end
	local actuel = self.profils[p.cle]
	if actuel and actuel.hash == p.hash then return false end
	self.profils[p.cle] = p
	self:Envoyer("GUILD", nil, "PROFILE_UPD", { v = Synchro.PROTOCOLE, profil = p })
	return true
end

--- Crée une commande de notre part et la diffuse. options : voir Commandes.nouvelle.
function Synchro:CreerCommande(options)
	options.maintenant = options.maintenant or self.maintenant()
	local c = ns.Commandes.nouvelle(options)
	self.commandes[c.id] = c
	self:Envoyer("GUILD", nil, "ORDER_NEW", { v = Synchro.PROTOCOLE, commande = c })
	return c
end

--- Fait avancer une commande (prendre, mats, terminer, liberer, annuler) au nom du personnage `par`.
-- Renvoie la nouvelle commande, ou nil et la raison.
function Synchro:AgirCommande(id, action, par, extra)
	local actuelle = self.commandes[id]
	if not actuelle then return nil, "inconnue" end
	local nouvelle, erreur = ns.Commandes.appliquer(actuelle, action, par, self.maintenant(), extra)
	if not nouvelle then return nil, erreur end
	self.commandes[id] = nouvelle
	self:Envoyer("GUILD", nil, "ORDER_UPD", { v = Synchro.PROTOCOLE, commande = nouvelle })
	return nouvelle
end

-- ---------------------------------------------------------------------------------------------
-- Réception
-- ---------------------------------------------------------------------------------------------

--- Intègre un profil venu du réseau. Renvoie vrai s'il a modifié notre copie.
function Synchro:Integrer(brut)
	local p = ns.Profil.valider(brut, self.donnees)
	if not p then
		self.journal("warn", "profil reçu invalide, ignoré")
		return false
	end
	if self.proprietaire(p.cle) then return false end -- nos personnages ne se laissent pas écraser
	local actuel = self.profils[p.cle]
	if actuel and not ns.Profil.plusRecent(p, actuel) then return false end
	self.profils[p.cle] = p
	self.surMaj(p.cle)
	return true
end

--- Intègre une commande venue du réseau. Renvoie vrai si elle a modifié notre copie.
function Synchro:IntegrerCommande(brut)
	local c = ns.Commandes.valider(brut, self.donnees)
	if not c then
		self.journal("warn", "commande reçue invalide, ignorée")
		return false
	end
	if ns.Commandes.perimee(c, self.maintenant()) then return false end

	local actuelle = self.commandes[c.id]
	if actuelle then
		if not ns.Commandes.meilleure(c, actuelle) then return false end
		-- Une seule révision d'écart : la transition doit être permise à son auteur.
		if c.rev == actuelle.rev + 1 and not ns.Commandes.transitionLegale(actuelle, c) then
			self.journal("warn", "transition interdite refusée sur %s (%s -> %s par %s)",
				c.id, actuelle.statut, c.statut, tostring(c.par))
			return false
		end
	else
		if self:CompterCommandes() >= MAX_COMMANDES then return false end
		-- Une commande neuve doit être créée par son client.
		if c.rev == 0 and (c.statut ~= "ouverte" or c.par ~= c.client) then return false end
	end

	self.commandes[c.id] = c
	self.surCommande(c.id, actuelle, c)
	return true
end

local GENRES = {
	HELLO = true, PRET = true, HASHES = true, PROFILE_REQ = true,
	PROFILE = true, PROFILE_UPD = true, ORDER = true, ORDER_NEW = true, ORDER_UPD = true,
}

function Synchro:Recevoir(genre, charge, expediteur)
	if type(expediteur) ~= "string" or not GENRES[genre] or type(charge) ~= "table" then return end
	if self.normaliser(expediteur) == self.moi() then return end
	self.stats.recus = self.stats.recus + 1

	if charge.v ~= Synchro.PROTOCOLE then
		self.journal("warn", "protocole %s ignoré (attendu %d)", tostring(charge.v), Synchro.PROTOCOLE)
		return
	end

	if genre == "HELLO" then
		self:SurHello(charge, expediteur)
	elseif genre == "PRET" then
		self:SurPret(charge, expediteur)
	elseif genre == "HASHES" then
		self:SurHashes(charge, expediteur)
	elseif genre == "PROFILE_REQ" then
		self:SurDemande(charge, expediteur)
	elseif genre == "PROFILE" then
		-- Reçu pendant une synchro : d'autres pairs peuvent ne pas l'avoir, on se ré-annonce.
		if self:Integrer(charge.profil) then self:ProgrammerAnnonce() end
	elseif genre == "ORDER" then
		if self:IntegrerCommande(charge.commande) then self:ProgrammerAnnonce() end
	elseif genre == "PROFILE_UPD" then
		-- Diffusé à toute la guilde en même temps : inutile de le répéter.
		self:Integrer(charge.profil)
	else -- ORDER_NEW, ORDER_UPD
		self:IntegrerCommande(charge.commande)
	end
end

function Synchro:SurHello(charge, expediteur)
	local monHash = self:HashGlobal()
	if charge.h == monHash then return end
	-- On ne répond qu'une fois par couple d'états (le nôtre, le sien) : une annonce identique est ignorée.
	local etat = monHash .. ":" .. tostring(charge.h)
	if self.reponduA[expediteur] == etat then return end

	-- Délai aléatoire : évite que tous les pairs répondent en même temps.
	self.planifier(self.alea() * DELAI_REPONSE, function()
		local maintenant = self:HashGlobal()
		if maintenant == charge.h then return end -- on s'est synchronisés entre-temps
		local actuel = maintenant .. ":" .. tostring(charge.h)
		if self.reponduA[expediteur] == actuel then return end
		self.reponduA[expediteur] = actuel
		-- Réponse minuscule : l'annonceur n'en retiendra qu'une, la liste ne voyagera qu'avec celle-là.
		self:Envoyer("WHISPER", expediteur, "PRET", { v = Synchro.PROTOCOLE, h = maintenant })
	end)
end

--- Un pair dont l'état diffère se propose : on garde le premier, on lui envoie notre liste de hashes.
function Synchro:SurPret(_, expediteur)
	local maintenant = self.maintenant()
	if self.partenaire and self.partenaire ~= expediteur and maintenant < self.partenaireJusqua then
		return -- on synchronise déjà avec un autre pair
	end
	self.partenaire = expediteur
	self.partenaireJusqua = maintenant + FENETRE_PARTENAIRE
	local p, c = {}, {}
	for cle, profil in pairs(self.profils) do p[cle] = { profil.maj, profil.hash } end
	for id, o in pairs(self.commandes) do c[id] = { o.rev, o.maj, o.par, o.hash } end
	self:Envoyer("WHISPER", expediteur, "HASHES", { v = Synchro.PROTOCOLE, liste = { p = p, c = c } })
end

local function nombre(v) return type(v) == "number" end

--- On reçoit la liste de hashes d'un pair : on lui demande ce qui est meilleur chez lui
-- et on lui envoie ce qui est meilleur chez nous.
function Synchro:SurHashes(charge, expediteur)
	local liste = charge.liste
	if type(liste) ~= "table" then return end
	local distantsP = type(liste.p) == "table" and liste.p or {}
	local distantsC = type(liste.c) == "table" and liste.c or {}

	local demandeP, demandeC = {}, {}
	for cle, info in pairs(distantsP) do
		if type(cle) == "string" and type(info) == "table" and nombre(info[1]) and nombre(info[2])
			and not self.proprietaire(cle) then
			local local_ = self.profils[cle]
			if not local_ or ns.Profil.plusRecent({ maj = info[1], hash = info[2] }, local_) then
				if #demandeP < MAX_DEMANDES then demandeP[#demandeP + 1] = cle end
			end
		end
	end
	for id, info in pairs(distantsC) do
		if type(id) == "string" and type(info) == "table" and nombre(info[1]) and nombre(info[2]) and nombre(info[4]) then
			local local_ = self.commandes[id]
			local distant = { rev = info[1], maj = info[2], par = info[3], hash = info[4] }
			if not local_ or ns.Commandes.meilleure(distant, local_) then
				if #demandeC < MAX_DEMANDES then demandeC[#demandeC + 1] = id end
			end
		end
	end
	if #demandeP > 0 or #demandeC > 0 then
		self:Envoyer("WHISPER", expediteur, "PROFILE_REQ", { v = Synchro.PROTOCOLE, cles = demandeP, ids = demandeC })
	end

	-- Ce que le pair n'a pas, ou a en moins bonne version : on le lui envoie.
	for cle, p in pairs(self.profils) do
		local info = distantsP[cle]
		local pousser = info == nil
		if not pousser and type(info) == "table" and nombre(info[1]) and nombre(info[2]) then
			pousser = ns.Profil.plusRecent(p, { maj = info[1], hash = info[2] })
		end
		if pousser then self:Envoyer("WHISPER", expediteur, "PROFILE", { v = Synchro.PROTOCOLE, profil = p }) end
	end
	for id, c in pairs(self.commandes) do
		local info = distantsC[id]
		local pousser = info == nil
		if not pousser and type(info) == "table" and nombre(info[1]) and nombre(info[2]) and nombre(info[4]) then
			pousser = ns.Commandes.meilleure(c, { rev = info[1], maj = info[2], par = info[3], hash = info[4] })
		end
		if pousser then self:Envoyer("WHISPER", expediteur, "ORDER", { v = Synchro.PROTOCOLE, commande = c }) end
	end
end

function Synchro:SurDemande(charge, expediteur)
	if type(charge.cles) == "table" then
		for i, cle in ipairs(charge.cles) do
			if i > MAX_DEMANDES then break end
			local p = type(cle) == "string" and self.profils[cle]
			if p then self:Envoyer("WHISPER", expediteur, "PROFILE", { v = Synchro.PROTOCOLE, profil = p }) end
		end
	end
	if type(charge.ids) == "table" then
		for i, id in ipairs(charge.ids) do
			if i > MAX_DEMANDES then break end
			local c = type(id) == "string" and self.commandes[id]
			if c then self:Envoyer("WHISPER", expediteur, "ORDER", { v = Synchro.PROTOCOLE, commande = c }) end
		end
	end
end

return Synchro
