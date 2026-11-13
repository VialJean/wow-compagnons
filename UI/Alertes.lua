-- Alertes : nouvelle commande pour toi, commande terminée, prise ou libérée.
-- Jamais en combat (elles attendent la fin), regroupées si plusieurs arrivent en même temps.
local _, ns = ...
local L = ns.L
local Compagnons = ns.addon

local Alertes = Compagnons:NewModule("Alertes", "AceEvent-3.0")
ns.Alertes = Alertes

local DELAI_REGROUPEMENT = 1.5
local DUREE_AFFICHAGE = 8

local function securise(etape, fn, ...)
	local ok, resultat = pcall(fn, ...)
	if not ok then
		ns.log("erreur", "ui", "%s : %s", etape, tostring(resultat))
		return nil
	end
	return resultat
end

function Alertes:OnEnable()
	self.file = {}      -- alertes détectées, en attente de regroupement
	self.messages = {}  -- messages prêts à être affichés, l'un après l'autre
	self:RegisterMessage("COMPAGNONS_COMMANDE_RECUE", "SurCommande")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "Vider")
end

--- Une commande vient de changer depuis le réseau : mérite-t-elle une alerte ?
function Alertes:SurCommande(_, _, avant, apres)
	local miens = ns.Atelier:Miens()
	local genre
	if not avant then
		if apres.statut == "ouverte" and not miens[apres.client]
			and ns.Atelier:Connait(apres.spell) and (not apres.crafteur or miens[apres.crafteur]) then
			genre = "nouvelle"
		end
	elseif miens[apres.client] and avant.statut ~= apres.statut then
		if apres.statut == "livree" then genre = "livree"
		elseif apres.statut == "terminee" then genre = "terminee"
		elseif apres.statut == "prise" then genre = "prise"
		elseif apres.statut == "ouverte" then genre = "liberee"
		end
	elseif apres.assigne and miens[apres.assigne] and avant.statut == "livree" then
		-- Je suis le crafteur : le client confirme la réception, ou dit qu'il n'a rien reçu.
		if apres.statut == "terminee" then genre = "confirmee"
		elseif apres.statut == "prise" then genre = "contestee"
		end
	end
	if not genre then return end

	self.file[#self.file + 1] = { genre = genre, commande = apres }
	if not self.prevue then
		self.prevue = true
		C_Timer.After(DELAI_REGROUPEMENT, function()
			self.prevue = false
			self:Vider()
		end)
	end
end

local function nomRecette(o)
	local r = ns.Recettes.recettes[o.spell]
	return r and r.nom or "?"
end

--- Écrit l'alerte dans le chat tout de suite, même en combat : le cadre, lui, attend la fin du combat.
local function ecrireDansLeChat(message)
	Compagnons:Print(message.titre .. (message.detail ~= "" and (" : " .. message.detail) or ""))
end

--- Ajoute une alerte qui ne vient pas d'une commande reçue (les rappels de connexion) : dans le chat tout de suite, dans le
-- cadre dès qu'on n'est plus en combat.
function Alertes:Poster(titre, detail, voir)
	local message = { titre = titre, detail = detail or "", voir = voir, vue = voir }
	self.messages[#self.messages + 1] = message
	ecrireDansLeChat(message)
	if not InCombatLockdown() then self:Suivante() end
end

--- Transforme la file en messages (un par genre), puis les affiche si l'on n'est pas en combat.
function Alertes:Vider()
	if #self.file > 0 then
		local groupes = { nouvelle = {}, livree = {}, terminee = {}, prise = {}, liberee = {}, confirmee = {}, contestee = {} }
		for _, a in ipairs(self.file) do table.insert(groupes[a.genre], a.commande) end
		self.file = {}

		-- `avecClient` : l'alerte concerne le client (je suis le crafteur), sinon c'est le crafteur qui est nommé.
		local function ajouter(titre, liste, voir, avecClient)
			if #liste == 0 then return end
			local o = liste[1]
			local message = {
				titre = titre,
				detail = string.format(L.ALERTE_DETAIL, o.qte, nomRecette(o), avecClient and o.client or (o.assigne or o.client)),
				voir = voir,
				vue = voir,
			}
			self.messages[#self.messages + 1] = message
			ecrireDansLeChat(message)
		end
		if #groupes.nouvelle > 1 then
			local message = {
				titre = string.format(L.ALERTE_PLUSIEURS, #groupes.nouvelle), detail = "", voir = "pourmoi",
			}
			self.messages[#self.messages + 1] = message
			ecrireDansLeChat(message)
		else
			ajouter(L.ALERTE_NOUVELLE, groupes.nouvelle, "pourmoi")
		end
		ajouter(L.ALERTE_LIVREE, groupes.livree, "mes")
		ajouter(L.ALERTE_TERMINEE, groupes.terminee, "mes")
		ajouter(L.ALERTE_PRISE, groupes.prise, "mes")
		ajouter(L.ALERTE_LIBEREE, groupes.liberee, "mes")
		ajouter(L.ALERTE_CONFIRMEE, groupes.confirmee, "mes", true)
		ajouter(L.ALERTE_CONTESTEE, groupes.contestee, "mes", true)
	end
	if InCombatLockdown() then return end -- reprendra à PLAYER_REGEN_ENABLED
	self:Suivante()
end

function Alertes:Suivante()
	if self.visible or #self.messages == 0 then return end
	local message = table.remove(self.messages, 1)
	if not securise("alerte", self.Afficher, self, message) then self:Suivante() end
end

function Alertes:Creer()
	local f = CreateFrame("Frame", "CompagnonsAlerte", UIParent, "BackdropTemplate")
	f:SetSize(380, 62)
	f:SetPoint("TOP", UIParent, "TOP", 0, -140)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 14,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	f:SetBackdropColor(0.08, 0.07, 0.05, 0.95)
	f:SetBackdropBorderColor(0.54, 0.45, 0.25, 1)
	f.icone = f:CreateTexture(nil, "ARTWORK")
	f.icone:SetSize(34, 34)
	f.icone:SetPoint("LEFT", 12, 0)
	f.icone:SetTexture("Interface\\Icons\\Trade_BlackSmithing")
	f.titre = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.titre:SetPoint("TOPLEFT", f.icone, "TOPRIGHT", 10, 0)
	f.titre:SetPoint("RIGHT", f, "RIGHT", -80, 0)
	f.titre:SetJustifyH("LEFT")
	f.detail = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.detail:SetPoint("TOPLEFT", f.titre, "BOTTOMLEFT", 0, -3)
	f.detail:SetPoint("RIGHT", f, "RIGHT", -80, 0)
	f.detail:SetJustifyH("LEFT")
	f.voir = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.voir:SetSize(60, 24)
	f.voir:SetPoint("RIGHT", -10, 0)
	f.voir:SetText(L.ALERTE_VOIR)
	f.voir:SetScript("OnClick", function()
		f:Hide()
		local fenetre = ns.Fenetre
		fenetre.vueCmd = f.vue
		fenetre:Afficher()
		fenetre:ChoisirOnglet(2)
	end)
	f:Hide()
	self.cadre = f
	return true
end

function Alertes:Afficher(message)
	if not self.cadre then self:Creer() end
	local f = self.cadre
	self.visible = true
	f.vue = message.voir
	f.titre:SetText(message.titre)
	f.detail:SetText(message.detail)
	f:Show()

	local jeton = (self.jeton or 0) + 1
	self.jeton = jeton
	C_Timer.After(DUREE_AFFICHAGE, function()
		if self.jeton ~= jeton then return end
		f:Hide()
		self.visible = false
		self:Suivante()
	end)
	f:SetScript("OnHide", function() self.visible = false end)
	return true
end
