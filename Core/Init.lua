-- Point d'entrée : addon Ace3, base de données, commandes slash.
local NOM, ns = ...
local L = ns.L

local Compagnons = LibStub("AceAddon-3.0"):NewAddon(NOM, "AceConsole-3.0", "AceEvent-3.0")
ns.addon = Compagnons
_G.Compagnons = Compagnons -- accessible via /dump pendant le développement

local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = GetMeta(NOM, "Version") or "dev"
ns.PROTOCOLE = 1   -- version du protocole de synchro (docs/protocole.md)
ns.SCHEMA_DB = 1   -- version du format de CompagnonsDB
ns.PREFIXE = "COMPAGNONS"

local defauts = {
	global = {
		-- `schema` n'est volontairement pas ici : AceDB n'écrit pas les valeurs égales aux défauts,
		-- or le Relais exige ce champ dans le fichier (voir OnInitialize).
		personnages = {}, -- [clé perso] = { nom, royaume, classe, metiers = {}, maj }
		guilde = {},      -- copie synchronisée des membres (sprint synchro)
		commandes = {},   -- (sprint commandes)
		diag = { sessions = 0 },
	},
	profile = {
		debug = false,
		minimap = { hide = false },
	},
}

--- Nom complet du personnage. Dans Forever un personnage a un prénom et un nom de famille
-- (« Jean Vialjean ») ; le jeu renvoie le nom de famille à la place du royaume.
function ns.nomComplet()
	return (GetUnitName and GetUnitName("player", true)) or UnitName("player")
end

--- Clé unique d'un personnage : son nom complet, comme dans la liste de guilde.
-- Le royaume est le même pour tous les joueurs de Forever, il n'entre donc pas dans la clé.
function ns.clePersonnage()
	return ns.nomComplet()
end

--- Ancienne clé « Prénom-Royaume » (avant la prise en compte du nom de famille).
local function ancienneCle()
	local royaume = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName()
	return UnitName("player") .. "-" .. (royaume or "?")
end

--- Vrai si le personnage est connecté. Pour l'instant seul le personnage courant l'est ;
-- la synchro de guilde étendra cette fonction aux autres membres.
function ns.estEnLigne(cle)
	return cle == ns.clePersonnage()
end

function Compagnons:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("CompagnonsDB", defauts, true)
	ns.db = self.db
	self.db.global.schema = ns.SCHEMA_DB

	-- Migration : les personnages scannés avant le nom de famille étaient rangés sous « Prénom-Royaume ».
	local persos = self.db.global.personnages
	local cle, ancienne = ns.clePersonnage(), ancienneCle()
	if persos[ancienne] and not persos[cle] and ancienne ~= cle then
		persos[cle] = persos[ancienne]
		persos[ancienne] = nil
	end

	self:RegisterChatCommand("compagnons", "Commande")
	self:RegisterChatCommand("cpg", "Commande")
end

function Compagnons:OnEnable()
	-- Compteurs de sessions : servent au diagnostic de persistance des SavedVariables.
	local diag = self.db.global.diag
	diag.sessions = (diag.sessions or 0) + 1
	diag.premiere = diag.premiere or time()
	diag.derniere = time()

	CompagnonsPersoDB = CompagnonsPersoDB or {}
	CompagnonsPersoDB.sessions = (CompagnonsPersoDB.sessions or 0) + 1

	-- Base de recettes croisée avec les métiers connus ; mise à jour après chaque scan.
	ns.catalogue = ns.Catalogue.nouveau(ns.Recettes, self.db.global.personnages, self.db.global.guilde)
	self:RegisterMessage("COMPAGNONS_METIER_SCANNE", function()
		ns.catalogue:Actualiser()
		self:SendMessage("COMPAGNONS_CATALOGUE_MAJ")
	end)

	ns.log("info", "init", "Compagnons %s chargé (protocole %d, session %d)",
		ns.VERSION, ns.PROTOCOLE, diag.sessions)
end

function Compagnons:Commande(saisie)
	local action, arg = self:GetArgs(saisie, 2)
	action = action and action:lower() or ""

	if action == "" or action == "recettes" then
		self:GetModule("Fenetre"):Basculer()
	elseif action == "sync" then
		self:GetModule("Reseau"):Etat(arg)
	elseif action == "minicarte" then
		self:GetModule("Minicarte"):Basculer()
	elseif action == "debug" then
		local p = self.db.profile
		p.debug = not p.debug
		self:Print(p.debug and L.DEBUG_ON or L.DEBUG_OFF)
	elseif action == "journal" then
		ns.Journal.afficher(tonumber(arg) or 20)
	elseif action == "perso" then
		self:AfficherPerso()
	elseif action == "diag" then
		self:GetModule("Diagnostic"):Lancer()
	else
		self:Print(L.AIDE_TITRE)
		print("  " .. L.AIDE_OUVRIR)
		print("  " .. L.AIDE_MINICARTE)
		print("  " .. L.AIDE_SYNC)
		print("  " .. L.AIDE_DEBUG)
		print("  " .. L.AIDE_JOURNAL)
		print("  " .. L.AIDE_PERSO)
		print("  " .. L.AIDE_DIAG)
	end
end

function Compagnons:AfficherPerso()
	local perso = self.db.global.personnages[ns.clePersonnage()]
	if not perso or not next(perso.metiers) then
		self:Print(L.PERSO_AUCUN)
		return
	end
	self:Print(perso.nom .. " (" .. (perso.classe or "?") .. ")")
	for _, m in pairs(perso.metiers) do
		print(string.format("  %s %d/%d : %d apprises sur %d vues, scanné le %s",
			m.nom, m.niveau or 0, m.max or 0, m.nbApprises, m.nbVues,
			date("%d/%m %H:%M", m.scanneLe)))
	end
end
