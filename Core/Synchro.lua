-- Moteur de synchronisation des profils de guilde. Lua pur : le transport, l'horloge et les
-- temporisations sont fournis de l'extérieur, ce qui permet de le tester avec des dizaines de clients simulés.
--
-- Messages (voir docs/protocole.md) :
--   HELLO        GUILD    { v, h, n }              annonce : hash global et nombre de profils
--   PRET         WHISPER  { v, h }                 un pair dont le hash diffère se propose (minuscule)
--   HASHES       WHISPER  { v, liste = { [cle] = { maj, hash } } }   envoyé par l'annonceur au premier pair prêt
--   PROFILE_REQ  WHISPER  { cles = { cle, ... } }  profils demandés
--   PROFILE      WHISPER  { profil }               un profil transmis à un seul membre
--   PROFILE_UPD  GUILD    { profil }               un profil vient de changer (scan)
local _, ns = ...

local Synchro = {}
Synchro.__index = Synchro
ns.Synchro = Synchro

Synchro.PROTOCOLE = 1

local FENETRE_PARTENAIRE = 20 -- secondes pendant lesquelles on ne synchronise qu'avec un seul pair
local DELAI_REPONSE = 2       -- les pairs répondent après un délai aléatoire borné par cette valeur
local DELAI_REANNONCE = 5     -- regroupe plusieurs changements en une seule annonce
local MAX_CLES_DEMANDEES = 400

--- options :
--   donnees       ns.Recettes
--   profils       table cle -> profil (tous les profils connus, y compris les nôtres)
--   moi           fonction -> clé du personnage connecté
--   proprietaire  fonction(cle) -> vrai si le personnage est à nous (le réseau ne peut pas l'écraser)
--   envoyer       fonction(canal, cible, type, charge)   canal = "GUILD" | "WHISPER"
--   maintenant    fonction -> secondes
--   planifier     fonction(delai, fn)
--   alea          fonction -> nombre dans [0, 1[
--   normaliser    fonction(expéditeur brut) -> clé (par défaut : « Prénom-Nom » devient « Prénom Nom »)
--   surMaj        fonction(cle) appelée quand un profil est modifié depuis le réseau
--   journal       fonction(niveau, format, ...)
function Synchro.nouveau(o)
	local s = setmetatable({}, Synchro)
	s.donnees = o.donnees
	s.profils = o.profils
	s.moi = o.moi
	s.proprietaire = o.proprietaire or function() return false end
	s.envoyerBrut = o.envoyer
	s.maintenant = o.maintenant
	s.planifier = o.planifier
	s.alea = o.alea or math.random
	s.normaliser = o.normaliser or function(brut) return (brut:gsub("%-", " ")) end
	s.surMaj = o.surMaj or function() end
	s.journal = o.journal or function() end
	s.partenaire = nil
	s.partenaireJusqua = 0
	s.reponduA = {}      -- [expéditeur] = hash global au moment où l'on a répondu
	s.annoncePrevue = false
	s.stats = { envoyes = 0, recus = 0, parGenre = {} }
	return s
end

function Synchro:Envoyer(canal, cible, genre, charge)
	self.stats.envoyes = self.stats.envoyes + 1
	self.stats.parGenre[genre] = (self.stats.parGenre[genre] or 0) + 1
	self.envoyerBrut(canal, cible, genre, charge)
end

--- Hash global : somme de contrôle de la liste triée « clé:hash ».
function Synchro:HashGlobal()
	local cles = {}
	for cle in pairs(self.profils) do cles[#cles + 1] = cle end
	table.sort(cles)
	local morceaux = {}
	for i, cle in ipairs(cles) do morceaux[i] = cle .. ":" .. self.profils[cle].hash end
	return ns.Profil.adler(table.concat(morceaux, ";"))
end

function Synchro:Compter()
	local n = 0
	for _ in pairs(self.profils) do n = n + 1 end
	return n
end

-- ---------------------------------------------------------------------------------------------
-- Émission
-- ---------------------------------------------------------------------------------------------

--- Annonce notre état à la guilde (à la connexion, puis après chaque changement reçu).
function Synchro:Annoncer()
	self.annoncePrevue = false
	self.partenaire = nil -- nouvelle ronde : on peut de nouveau choisir un partenaire
	self.partenaireJusqua = 0
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

local GENRES = { HELLO = true, PRET = true, HASHES = true, PROFILE_REQ = true, PROFILE = true, PROFILE_UPD = true }

function Synchro:Recevoir(genre, charge, expediteur)
	if type(expediteur) ~= "string" or not GENRES[genre] or type(charge) ~= "table" then return end
	if self.normaliser(expediteur) == self.moi() then return end
	self.stats.recus = self.stats.recus + 1

	if charge.v ~= nil and charge.v ~= Synchro.PROTOCOLE then
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
	elseif genre == "PROFILE_UPD" then
		-- Diffusé à toute la guilde en même temps : inutile de le répéter.
		self:Integrer(charge.profil)
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
	local liste = {}
	for cle, p in pairs(self.profils) do liste[cle] = { p.maj, p.hash } end
	self:Envoyer("WHISPER", expediteur, "HASHES", { v = Synchro.PROTOCOLE, liste = liste })
end

--- On reçoit la liste de hashes d'un pair : on lui demande ce qui est plus récent chez lui
-- et on lui envoie ce qui est plus récent chez nous.
function Synchro:SurHashes(charge, expediteur)
	if type(charge.liste) ~= "table" then return end

	local demande = {}
	for cle, info in pairs(charge.liste) do
		if type(cle) == "string" and type(info) == "table" and not self.proprietaire(cle) then
			local local_ = self.profils[cle]
			local distant = { maj = info[1], hash = info[2] }
			if type(distant.maj) == "number" and type(distant.hash) == "number" then
				if not local_ or ns.Profil.plusRecent(distant, local_) then
					if #demande < MAX_CLES_DEMANDEES then demande[#demande + 1] = cle end
				end
			end
		end
	end
	if #demande > 0 then
		self:Envoyer("WHISPER", expediteur, "PROFILE_REQ", { v = Synchro.PROTOCOLE, cles = demande })
	end

	-- Ce que le pair n'a pas, ou a en version plus ancienne : on le lui envoie.
	for cle, p in pairs(self.profils) do
		local info = charge.liste[cle]
		local pousser = info == nil
		if not pousser and type(info) == "table" and type(info[1]) == "number" and type(info[2]) == "number" then
			pousser = ns.Profil.plusRecent(p, { maj = info[1], hash = info[2] })
		end
		if pousser then self:Envoyer("WHISPER", expediteur, "PROFILE", { v = Synchro.PROTOCOLE, profil = p }) end
	end
end

function Synchro:SurDemande(charge, expediteur)
	if type(charge.cles) ~= "table" then return end
	for i, cle in ipairs(charge.cles) do
		if i > MAX_CLES_DEMANDEES then break end
		local p = type(cle) == "string" and self.profils[cle]
		if p then self:Envoyer("WHISPER", expediteur, "PROFILE", { v = Synchro.PROTOCOLE, profil = p }) end
	end
end

return Synchro
