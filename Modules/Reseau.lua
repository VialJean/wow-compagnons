-- Branche le moteur de synchro (Core/Synchro.lua) sur le jeu :
--   transport  AceComm (découpage et limitation de débit) sur le préfixe COMPAGNONS
--   codage     LibSerialize -> LibDeflate -> EncodeForWoWAddonChannel
--   présence   liste de guilde native (GetGuildRosterInfo), pas le protocole
local _, ns = ...
local L = ns.L
local Compagnons = ns.addon

local Reseau = Compagnons:NewModule("Reseau", "AceEvent-3.0")
ns.Reseau = Reseau
LibStub("AceComm-3.0"):Embed(Reseau)

local DELAI_CONNEXION = 8      -- laisse le temps à la guilde et aux autres addons de se charger
local PERIODE_ROSTER = 60
local DELAI_MAJ_CATALOGUE = 2

local Serialize, Deflate

local function securise(etape, fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then
		ns.log("erreur", "sync", "%s : %s", etape, tostring(a))
		return nil
	end
	return a, b
end

-- ---------------------------------------------------------------------------------------------
-- Codage
-- ---------------------------------------------------------------------------------------------

local function encoder(genre, charge)
	local brut = Serialize:Serialize({ genre, charge })
	return Deflate:EncodeForWoWAddonChannel(Deflate:CompressDeflate(brut))
end

local function decoder(texte)
	local compresse = Deflate:DecodeForWoWAddonChannel(texte)
	if not compresse then return nil end
	local brut = Deflate:DecompressDeflate(compresse)
	if not brut then return nil end
	local ok, valeur = Serialize:Deserialize(brut)
	if not ok or type(valeur) ~= "table" then return nil end
	return valeur[1], valeur[2]
end

-- ---------------------------------------------------------------------------------------------
-- Cycle de vie
-- ---------------------------------------------------------------------------------------------

function Reseau:OnEnable()
	Serialize = LibStub("LibSerialize")
	Deflate = LibStub("LibDeflate")

	self.enLigne = {}
	self.versionAddon = {} -- [clé] = version de l'addon annoncée par un pair à jour (informatif)
	self.moteur = ns.Synchro.nouveau({
		donnees = ns.Recettes,
		profils = ns.db.global.guilde,
		commandes = ns.db.global.commandes,
		prix = ns.db.global.prix,
		vus = ns.db.global.vus,
		surPrix = function() Compagnons:SendMessage("COMPAGNONS_PRIX_MAJ") end,
		version = ns.VERSION,
		surVersion = function(cle, v, brut, a) self:SurVersion(cle, v, brut, a) end,
		moi = ns.clePersonnage,
		proprietaire = function(cle) return ns.db.global.personnages[cle] ~= nil end,
		envoyer = function(canal, cible, genre, charge) self:Envoyer(canal, cible, genre, charge) end,
		maintenant = time,
		planifier = C_Timer.After,
		alea = math.random,
		surMaj = function() self:ProgrammerMajCatalogue() end,
		surCommande = function(id, avant, apres)
			Compagnons:SendMessage("COMPAGNONS_COMMANDE_RECUE", id, avant, apres)
		end,
		journal = function(niveau, fmt, ...) ns.log(niveau, "sync", fmt, ...) end,
	})

	self:RegisterComm(ns.PREFIXE, "SurMessage")
	self:RegisterMessage("COMPAGNONS_METIER_SCANNE", "SurScan")
	self:RegisterEvent("GUILD_ROSTER_UPDATE", "SurRoster")

	-- Nos personnages entrent dans la copie locale, sans rien diffuser tant que rien n'a changé.
	self:PublierPersonnages(false)

	-- La présence en ligne vient de la liste de guilde ; le personnage courant l'est toujours.
	ns.estEnLigne = function(cle)
		return cle == ns.clePersonnage() or self.enLigne[cle] == true
	end
	self:DemanderRoster()
	C_Timer.NewTicker(PERIODE_ROSTER, function() self:DemanderRoster() end)

	if IsInGuild() then
		C_Timer.After(DELAI_CONNEXION, function()
			ns.log("sync", "sync", "annonce à la connexion (%d profils, hash %d)",
				self.moteur:Compter(), self.moteur:HashGlobal())
			self.moteur:Annoncer()
		end)
	end
end

-- ---------------------------------------------------------------------------------------------
-- Transport
-- ---------------------------------------------------------------------------------------------

function Reseau:Envoyer(canal, cible, genre, charge)
	if canal == "GUILD" and not IsInGuild() then return end
	local texte = securise("codage", encoder, genre, charge)
	if not texte then return end
	ns.log("sync", "sync", "-> %s %s %s (%d octets)", canal, cible or "", genre, #texte)
	self:SendCommMessage(ns.PREFIXE, texte, canal, cible, genre == "PROFILE_UPD" and "NORMAL" or "BULK")
end

function Reseau:SurMessage(_, texte, canal, expediteur)
	local genre, charge = securise("décodage", decoder, texte)
	if not genre then
		ns.log("warn", "sync", "message illisible de %s (%d octets)", tostring(expediteur), #texte)
		return
	end
	ns.log("sync", "sync", "<- %s %s %s (%d octets)", canal, tostring(expediteur), tostring(genre), #texte)
	securise("traitement", self.moteur.Recevoir, self.moteur, genre, charge, expediteur)
end

-- ---------------------------------------------------------------------------------------------
-- Pairs en retard de version (docs/v5.md, §2.7)
-- ---------------------------------------------------------------------------------------------

--- La synchro nous donne la version de protocole de chaque expéditeur, même quand son message est ignoré.
function Reseau:SurVersion(cle, v, brut, a)
	local etat = ns.db.global.versions
	local evenement = ns.Versions.noter(etat, cle, v, time(), ns.Synchro.PROTOCOLE, brut)
	if (evenement == "ajour" or evenement == "misajour") and type(a) == "string" then
		self.versionAddon[cle] = a:sub(1, 16)
	end
	if evenement == "nouveau" or evenement == "plusrecente" or evenement == "misajour" then
		ns.log("warn", "sync", "version de protocole %s : %s (%s)", tostring(v), cle, evenement)
		Compagnons:SendMessage("COMPAGNONS_VERSION_MAJ", evenement, cle)
	end
end

local function envoyerChuchotement(texte, cible)
	local envoyer = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	return pcall(envoyer, texte, "WHISPER", nil, cible)
end

--- Écrit, sur demande du joueur (jamais automatiquement), par un chuchotement ordinaire (lisible sans l'addon), aux pairs de la liste. Renvoie le nombre de messages envoyés.
-- Un envoi par seconde : le serveur limite les messages envoyés d'affilée.
function Reseau:Prevenir(liste)
	local etat, n = ns.db.global.versions, 0
	for i, pair in ipairs(liste) do
		ns.Versions.marquer(etat, pair.cle, time()) -- marqué tout de suite : un seul message par personne, même en cas de ré-entrée
		C_Timer.After((i - 1) * 1, function()
			local ok, erreur = envoyerChuchotement(L.VERSION_CHUCHOTEMENT, pair.brut)
			ns.log(ok and "info" or "erreur", "sync", "chuchotement de mise à jour à %s : %s", pair.brut, ok and "envoyé" or tostring(erreur))
		end)
		n = n + 1
	end
	return n
end

--- Bouton « Les prévenir » : tous ceux qu'on n'a pas prévenus depuis un jour. Un clic du joueur.
function Reseau:PrevenirTous()
	if InCombatLockdown() then
		Compagnons:Print(L.VERSION_COMBAT)
		return
	end
	local liste = ns.Versions.aPrevenir(ns.db.global.versions, time(), ns.Synchro.PROTOCOLE, false)
	if #liste == 0 then
		Compagnons:Print(L.VERSION_DEJA_PREVENUS)
		return
	end
	Compagnons:Print(string.format(L.VERSION_PREVENUS, self:Prevenir(liste)))
	Compagnons:SendMessage("COMPAGNONS_VERSION_MAJ", "prevenus")
end

-- ---------------------------------------------------------------------------------------------
-- Nos personnages
-- ---------------------------------------------------------------------------------------------

--- Convertit nos personnages scannés en profils. `diffuser` : annoncer les changements à la guilde.
function Reseau:PublierPersonnages(diffuser)
	for cle, perso in pairs(ns.db.global.personnages) do
		self:PublierPersonnage(cle, perso, diffuser)
	end
end

function Reseau:PublierPersonnage(cle, perso, diffuser)
	local profil = ns.Profil.dePersonnage(cle, perso, ns.Recettes)
	local actuel = self.moteur.profils[cle]
	if actuel and actuel.hash == profil.hash then return end
	if diffuser then
		self.moteur:Publier(profil)
	else
		self.moteur.profils[cle] = profil
	end
end

function Reseau:SurScan(_, cle)
	local perso = cle and ns.db.global.personnages[cle]
	if perso then self:PublierPersonnage(cle, perso, true) end
end

-- ---------------------------------------------------------------------------------------------
-- Présence et mise à jour de l'affichage
-- ---------------------------------------------------------------------------------------------

function Reseau:DemanderRoster()
	if not IsInGuild() then return end
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	elseif GuildRoster then
		GuildRoster()
	end
end

function Reseau:SurRoster()
	local nouveaux = {}
	for i = 1, (GetNumGuildMembers() or 0) do
		local nom, _, _, _, _, _, _, _, connecte = GetGuildRosterInfo(i)
		if nom and connecte then nouveaux[nom] = true end
	end
	local change = false
	for nom in pairs(nouveaux) do
		if not self.enLigne[nom] then change = true end
	end
	for nom in pairs(self.enLigne) do
		if not nouveaux[nom] then change = true end
	end
	self.enLigne = nouveaux
	if change then self:ProgrammerMajCatalogue() end
end

--- Regroupe les mises à jour : une seule actualisation de l'affichage même si beaucoup de profils arrivent.
function Reseau:ProgrammerMajCatalogue()
	if self.majPrevue then return end
	self.majPrevue = true
	C_Timer.After(DELAI_MAJ_CATALOGUE, function()
		self.majPrevue = false
		if ns.catalogue then ns.catalogue:Actualiser() end
		Compagnons:SendMessage("COMPAGNONS_CATALOGUE_MAJ")
	end)
end

-- ---------------------------------------------------------------------------------------------
-- /cpg sync
-- ---------------------------------------------------------------------------------------------

function Reseau:Etat(action)
	local m = self.moteur
	if action == "annonce" then
		m:Annoncer()
		Compagnons:Print(L.SYNC_ANNONCE)
		return
	end
	local enLigne = 0
	for _ in pairs(self.enLigne) do enLigne = enLigne + 1 end
	Compagnons:Print(string.format(L.SYNC_ETAT, m:Compter(), m:CompterCommandes(), m:HashGlobal(),
		m.stats.envoyes, m.stats.recus, enLigne))
end
