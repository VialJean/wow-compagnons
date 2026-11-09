-- Panneau accolé à la fenêtre de métier du jeu : qui, dans la guilde, connaît la recette sélectionnée,
-- et accès rapide au navigateur. Les commandes en attente s'y ajouteront avec le sprint commandes.
local _, ns = ...
local L = ns.L
local Compagnons = ns.addon

local Panneau = Compagnons:NewModule("PanneauMetier", "AceEvent-3.0")
ns.PanneauMetier = Panneau

local TS = C_TradeSkillUI
local MAX_CRAFTEURS = 6
local DELAI_OUVERTURE = 0.4
local PERIODE_SUIVI = 0.4

local function securise(etape, fn, ...)
	local ok, resultat = pcall(fn, ...)
	if not ok then
		ns.log("erreur", "ui", "%s : %s", etape, tostring(resultat))
		return nil
	end
	return resultat
end

function Panneau:OnEnable()
	self:RegisterEvent("TRADE_SKILL_SHOW", "SurOuverture")
	self:RegisterEvent("TRADE_SKILL_CLOSE", "SurFermeture")
	self:RegisterMessage("COMPAGNONS_CATALOGUE_MAJ", "Actualiser")
end

--- Fenêtre de métier du jeu : interface moderne (ProfessionsFrame) ou ancienne (TradeSkillFrame).
local function fenetreDeMetier()
	local f = _G.ProfessionsFrame or _G.TradeSkillFrame
	if f and f.IsShown and f:IsShown() then return f end
	return nil
end

--- Identifiant (skillLineID) du métier affiché, ou nil.
local function metierAffiche()
	if TS and TS.GetBaseProfessionInfo then
		local info = TS.GetBaseProfessionInfo()
		if info and info.professionID then return info.professionID, info.professionName end
	end
	return nil
end

--- Recette (spellID) sélectionnée dans la fenêtre de métier, ou nil.
local function recetteSelectionnee()
	local pf = _G.ProfessionsFrame
	local formulaire = pf and pf.CraftingPage and pf.CraftingPage.SchematicForm
	if formulaire and formulaire.GetRecipeInfo then
		local info = formulaire:GetRecipeInfo()
		if info and info.recipeID then return info.recipeID end
	end
	if TS and TS.GetSelectedRecipeID then return TS.GetSelectedRecipeID() end
	return nil
end

function Panneau:SurOuverture()
	C_Timer.After(DELAI_OUVERTURE, function()
		securise("panneau de métier", self.Attacher, self)
	end)
end

function Panneau:SurFermeture()
	if self.cadre then self.cadre:Hide() end
end

function Panneau:Creer()
	local f = CreateFrame("Frame", "CompagnonsPanneauMetier", UIParent, "BackdropTemplate")
	f:SetSize(260, 300)
	f:SetFrameStrata("HIGH")
	f:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	f:SetBackdropColor(0.08, 0.07, 0.05, 0.95)
	f:SetBackdropBorderColor(0.54, 0.45, 0.25, 1)
	f:Hide()

	f.titre = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.titre:SetPoint("TOPLEFT", 14, -14)
	f.titre:SetPoint("RIGHT", f, "RIGHT", -14, 0)
	f.titre:SetJustifyH("LEFT")

	f.recette = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.recette:SetPoint("TOPLEFT", f.titre, "BOTTOMLEFT", 0, -12)
	f.recette:SetPoint("RIGHT", f, "RIGHT", -14, 0)
	f.recette:SetJustifyH("LEFT")

	f.sousTitre = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.sousTitre:SetPoint("TOPLEFT", f.recette, "BOTTOMLEFT", 0, -10)
	f.sousTitre:SetText(L.PEUVENT_CRAFTER)

	f.lignes = {}
	for i = 1, MAX_CRAFTEURS do
		local ligne = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		ligne:SetPoint("TOPLEFT", f.sousTitre, "BOTTOMLEFT", 0, -4 - (i - 1) * 16)
		ligne:SetJustifyH("LEFT")
		f.lignes[i] = ligne
	end
	f.aucun = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.aucun:SetPoint("TOPLEFT", f.sousTitre, "BOTTOMLEFT", 0, -4)
	f.aucun:SetText(L.PERSONNE_CONNAIT)

	f.bilan = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.bilan:SetPoint("BOTTOMLEFT", 14, 52)
	f.bilan:SetPoint("RIGHT", f, "RIGHT", -14, 0)
	f.bilan:SetJustifyH("LEFT")

	f.commandes = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.commandes:SetPoint("BOTTOMLEFT", 14, 38)
	f.commandes:SetText(L.COMMANDES_BIENTOT)

	f.ouvrir = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.ouvrir:SetSize(232, 24)
	f.ouvrir:SetPoint("BOTTOM", 0, 10)
	f.ouvrir:SetText(L.OUVRIR_ATELIER)
	f.ouvrir:SetScript("OnClick", function()
		local fenetre = ns.Fenetre
		if fenetre then
			fenetre.metier = self.metier
			fenetre.texte = ""
			if fenetre.recherche then fenetre.recherche:SetText("") end
			fenetre:Afficher()
			fenetre:Rafraichir()
		end
	end)

	f:SetScript("OnShow", function() self:DemarrerSuivi() end)
	f:SetScript("OnHide", function() self:ArreterSuivi() end)
	self.cadre = f
end

function Panneau:Attacher()
	local parent = fenetreDeMetier()
	if not parent then
		ns.log("info", "ui", "panneau de métier : fenêtre de métier introuvable ou fermée")
		return
	end
	if not self.cadre then self:Creer() end
	local f = self.cadre
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", parent, "TOPRIGHT", 2, -12)
	if not self.parentSurveille then
		self.parentSurveille = true
		parent:HookScript("OnHide", function() f:Hide() end)
	end
	f:Show()
	self:Actualiser()
end

function Panneau:DemarrerSuivi()
	if self.suivi then return end
	self.suivi = C_Timer.NewTicker(PERIODE_SUIVI, function()
		local recette = securise("suivi de la recette", recetteSelectionnee)
		if recette ~= self.derniere then self:Actualiser() end
	end)
end

function Panneau:ArreterSuivi()
	if self.suivi then
		self.suivi:Cancel()
		self.suivi = nil
	end
end

function Panneau:Actualiser()
	local f = self.cadre
	if not f or not f:IsShown() or not ns.catalogue then return end

	local idMetier, nomMetier = metierAffiche()
	self.metier = idMetier
	local metier = idMetier and ns.Recettes.metiers[idMetier]
	f.titre:SetText(string.format(L.PANNEAU_TITRE, (metier and metier.nom) or nomMetier or "?"))

	local spellID = securise("recette sélectionnée", recetteSelectionnee)
	self.derniere = spellID
	local recette = spellID and ns.Recettes.recettes[spellID]

	if not recette then
		f.recette:SetText(spellID and L.RECETTE_INCONNUE_BASE or L.SELECTIONNE_RECETTE)
		f.sousTitre:Hide()
		f.aucun:Hide()
		for i = 1, MAX_CRAFTEURS do f.lignes[i]:Hide() end
	else
		f.recette:SetText(recette.nom)
		f.sousTitre:Show()
		local crafteurs = ns.catalogue:Crafteurs(spellID)
		for i = 1, MAX_CRAFTEURS do
			local c = crafteurs[i]
			local ligne = f.lignes[i]
			if c then
				local classe = c.classe and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.classe]
				local couleur = classe and ns.hex(classe.r, classe.g, classe.b) or "|cffcccccc"
				local etat = ns.estEnLigne(c.cle) and L.EN_LIGNE or L.HORS_LIGNE
				ligne:SetText(string.format("%s%s|r |cffa89c86· %s|r", couleur, c.nom, etat))
				ligne:Show()
			else
				ligne:Hide()
			end
		end
		if #crafteurs > MAX_CRAFTEURS then
			f.lignes[MAX_CRAFTEURS]:SetText(string.format(L.ET_AUTRES, #crafteurs - MAX_CRAFTEURS + 1))
		end
		f.aucun:SetShown(#crafteurs == 0)
	end

	if idMetier then
		local total, connues = 0, 0
		for id, r in pairs(ns.Recettes.recettes) do
			if r.metier == idMetier then
				total = total + 1
				if #ns.catalogue:Crafteurs(id) > 0 then connues = connues + 1 end
			end
		end
		f.bilan:SetText(string.format(L.BILAN, connues, total))
	else
		f.bilan:SetText("")
	end
end
