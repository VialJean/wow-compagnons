-- Avertissement de version : prévient le joueur, de façon impossible à rater, qu'un ou plusieurs membres de la guilde ne se
-- synchronisent plus avec lui (version de Compagnons trop ancienne), ou qu'une version plus récente que la sienne existe
-- (docs/v5.md, §2.7). Le calcul de « qui est en retard » est dans Core/Versions.lua, l'envoi des chuchotements dans
-- Modules/Reseau.lua ; ici, seulement l'affichage :
--   1. fenêtre au centre de l'écran (à la connexion et à chaque nouveau pair en retard, jamais en combat)
--   2. texte central style avertissement de raid, et son
--   3. bandeau rouge permanent au-dessus de la fenêtre de l'atelier
--   4. pastille « ! » sur le bouton de minicarte (voir Minicarte.lua) et ligne dans son infobulle
--   5. ligne rouge dans le chat
--   6. mention rouge dans l'onglet Membres (voir OngletMembres.lua)
local _, ns = ...
local L = ns.L
local Compagnons = ns.addon

local Avertissement = Compagnons:NewModule("Avertissement", "AceEvent-3.0")
ns.Avertissement = Avertissement

local DELAI_CONNEXION = 20   -- après la première annonce de synchro (8 s) et les réponses des pairs
local DELAI_REGROUPEMENT = 3 -- plusieurs pairs détectés d'affilée : une seule fenêtre
local MAX_NOMS = 5

local function securise(etape, fn, ...)
	local ok, resultat = pcall(fn, ...)
	if not ok then
		ns.log("erreur", "ui", "%s : %s", etape, tostring(resultat))
		return nil
	end
	return resultat
end

function Avertissement:OnEnable()
	self.signales = {} -- pairs déjà annoncés pendant cette session
	StaticPopupDialogs["COMPAGNONS_VERSION"] = {
		text = "%s",
		button1 = L.VERSION_PREVENIR,
		button2 = L.VERSION_PLUS_TARD,
		OnAccept = function() if ns.Reseau then ns.Reseau:PrevenirTous() end end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	StaticPopupDialogs["COMPAGNONS_VERSION_RECENTE"] = {
		text = "%s",
		button1 = OKAY,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	self:RegisterMessage("COMPAGNONS_VERSION_MAJ", "SurMaj")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "Reprendre")
	C_Timer.After(DELAI_CONNEXION, function() self:Afficher(true) end)
end

-- ---------------------------------------------------------------------------------------------
-- État
-- ---------------------------------------------------------------------------------------------

--- Pairs obsolètes (liste triée) et version plus récente que la nôtre vue chez un pair (ou nil).
function Avertissement:Etat()
	local etat = ns.db.global.versions
	local protocole = ns.Synchro.PROTOCOLE
	return ns.Versions.obsoletes(etat, time(), protocole), ns.Versions.plusRecente(etat, protocole)
end

local function noms(liste)
	local morceaux = {}
	for i = 1, math.min(#liste, MAX_NOMS) do morceaux[i] = liste[i].cle end
	local texte = table.concat(morceaux, ", ")
	if #liste > MAX_NOMS then texte = texte .. string.format(" (+%d)", #liste - MAX_NOMS) end
	return texte
end

--- Phrase du bandeau, ou nil s'il n'y a rien à signaler.
function Avertissement:TexteBandeau()
	local obsoletes, recente = self:Etat()
	if #obsoletes > 0 then return string.format(L.VERSION_BANDEAU, noms(obsoletes)) end
	if recente then return L.VERSION_BANDEAU_RECENTE end
end

--- Ligne de l'infobulle de la minicarte, ou nil.
function Avertissement:Resume()
	local obsoletes, recente = self:Etat()
	if #obsoletes > 0 then return string.format(L.VERSION_MINICARTE, #obsoletes) end
	if recente then return L.VERSION_MINICARTE_RECENTE end
end

-- ---------------------------------------------------------------------------------------------
-- Fenêtre, texte central, son, chat
-- ---------------------------------------------------------------------------------------------

local function texteCentral(texte)
	if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] then
		RaidNotice_AddMessage(RaidWarningFrame, texte, ChatTypeInfo["RAID_WARNING"])
	end
	if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
end

--- Affiche l'avertissement. `connexion` : première annonce de la session (on la fait même sans nouveau pair) ; sinon seulement
-- ce qu'on n'a pas encore annoncé. En combat, on attend la fin du combat.
function Avertissement:Afficher(connexion)
	local obsoletes, recente = self:Etat()
	local neuf = false
	for _, p in ipairs(obsoletes) do
		if not self.signales[p.cle] then neuf = true end
	end
	local recenteNeuve = recente ~= nil and self.recenteSignalee ~= recente
	if not (neuf or recenteNeuve or (connexion and (#obsoletes > 0 or recente))) then return end

	if InCombatLockdown() then
		self.enAttente = true
		self.attenteConnexion = self.attenteConnexion or connexion
		return
	end
	for _, p in ipairs(obsoletes) do self.signales[p.cle] = true end
	self.recenteSignalee = recente

	local silencieux = ns.db.profile.avertir.silencieux
	local messages = {}
	if #obsoletes > 0 then
		messages[#messages + 1] = { texte = string.format(L.VERSION_OBSOLETES, #obsoletes, noms(obsoletes)), popup = "COMPAGNONS_VERSION" }
	end
	if recente then
		messages[#messages + 1] = { texte = L.VERSION_PLUS_RECENTE, popup = "COMPAGNONS_VERSION_RECENTE" }
	end
	for _, m in ipairs(messages) do
		Compagnons:Print("|cffff4040" .. m.texte .. "|r")
		if not silencieux then securise("fenêtre d'avertissement", StaticPopup_Show, m.popup, m.texte) end
	end
	if not silencieux then securise("texte central", texteCentral, L.VERSION_TITRE_ALERTE) end
	self:ActualiserBandeau()
end

--- Un combat vient de finir : ce qui était en attente s'affiche.
function Avertissement:Reprendre()
	if not self.enAttente then return end
	local connexion = self.attenteConnexion
	self.enAttente, self.attenteConnexion = false, nil
	self:Afficher(connexion)
end

--- Un pair vient d'apparaître en retard, de se mettre à jour, ou on a vu une version plus récente.
function Avertissement:SurMaj(_, evenement)
	self:ActualiserBandeau()
	if ns.Fenetre and ns.Fenetre.RafraichirMembres then securise("onglet Membres", ns.Fenetre.RafraichirMembres, ns.Fenetre) end
	if evenement == "nouveau" or evenement == "plusrecente" then
		if self.prevu then return end
		self.prevu = true
		C_Timer.After(DELAI_REGROUPEMENT, function()
			self.prevu = false
			self:Afficher(false)
		end)
	end
end

-- ---------------------------------------------------------------------------------------------
-- Bandeau rouge au-dessus de la fenêtre de l'atelier
-- ---------------------------------------------------------------------------------------------

--- Appelé par la fenêtre quand elle est créée.
function Avertissement:AttacherBandeau(f)
	local b = CreateFrame("Frame", nil, f)
	b:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 2)
	b:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 2)
	b:SetHeight(30)
	b.fond = b:CreateTexture(nil, "BACKGROUND")
	b.fond:SetAllPoints()
	b.fond:SetColorTexture(0.62, 0.1, 0.1, 0.96)
	b.texte = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	b.texte:SetPoint("LEFT", 12, 0)
	b.texte:SetPoint("RIGHT", -140, 0)
	b.texte:SetJustifyH("LEFT")
	b.texte:SetTextColor(1, 1, 1)
	b.bouton = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
	b.bouton:SetSize(120, 22)
	b.bouton:SetPoint("RIGHT", -6, 0)
	b.bouton:SetText(L.VERSION_PREVENIR)
	b.bouton:SetScript("OnClick", function() if ns.Reseau then ns.Reseau:PrevenirTous() end end)
	b:Hide()
	self.bandeau = b
	f:HookScript("OnShow", function() self:ActualiserBandeau() end)
	self:ActualiserBandeau()
end

function Avertissement:ActualiserBandeau()
	local b = self.bandeau
	if not b then return end
	local texte = self:TexteBandeau()
	if not texte then
		b:Hide()
		return
	end
	local obsoletes = self:Etat()
	b.texte:SetText(texte)
	b.bouton:SetShown(#obsoletes > 0) -- on ne prévient personne d'une version plus récente que la nôtre
	b:Show()
end

-- ---------------------------------------------------------------------------------------------
-- /cpg avertir
-- ---------------------------------------------------------------------------------------------

function Avertissement:Commande(arg, arg2)
	local action = type(arg) == "string" and arg:lower() or ""
	local valeur = type(arg2) == "string" and arg2:lower() or ""
	local reglage = ns.db.profile.avertir
	if action == "send" or action == "envoyer" then
		if ns.Reseau then ns.Reseau:PrevenirTous() end
		return
	elseif (action == "silent" or action == "silence") and (valeur == "on" or valeur == "off") then
		reglage.silencieux = valeur == "on"
	end
	Compagnons:Print(string.format(L.VERSION_ETAT, reglage.silencieux and L.INFO_ACTIVE or L.INFO_DESACTIVE))
end
