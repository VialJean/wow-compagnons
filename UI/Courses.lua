-- Liste de courses : les composants à réunir pour mes commandes en cours, avec le stock de tous mes personnages.
-- Ouverte par le bouton de l'onglet Commandes ou par /cpg courses (aussi /cpg shopping).
local _, ns = ...
local L = ns.L
local Compagnons = ns.addon

local Courses = Compagnons:NewModule("Courses", "AceEvent-3.0")
ns.Courses = Courses

local HAUTEUR_LIGNE = 28
local ICONE_INCONNUE = 134400

local function securise(etape, fn, ...)
	local ok, resultat = pcall(fn, ...)
	if not ok then
		ns.log("erreur", "ui", "%s : %s", etape, tostring(resultat))
		return nil
	end
	return resultat
end

local function iconeObjet(id)
	if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
	if GetItemIcon then return GetItemIcon(id) end
end

function Courses:OnEnable()
	self:RegisterMessage("COMPAGNONS_COMMANDES_MAJ", "Rafraichir")
	self:RegisterMessage("COMPAGNONS_STOCK_MAJ", "Rafraichir")
end

function Courses:Basculer()
	if not self.cadre then
		if not securise("création de la liste de courses", self.Creer, self) then return end
	end
	if self.cadre:IsShown() then self.cadre:Hide() else self.cadre:Show() end
end

function Courses:Creer()
	local f = CreateFrame("Frame", "CompagnonsCourses", UIParent, "ButtonFrameTemplate")
	self.cadre = f
	f:SetSize(520, 460)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	tinsert(UISpecialFrames, "CompagnonsCourses")

	securise("gabarit", function()
		if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(f) end
		if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(f) end
		if f.SetTitle then f:SetTitle(L.COURSES_TITRE) elseif f.TitleText then f.TitleText:SetText(L.COURSES_TITRE) end
	end)

	local cadre = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
	cadre:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -34)
	cadre:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 46)

	local boite = CreateFrame("Frame", nil, cadre, "WowScrollBoxList")
	local barre = CreateFrame("EventFrame", nil, cadre, "MinimalScrollBar")
	local vue = CreateScrollBoxListLinearView()
	vue:SetElementExtent(HAUTEUR_LIGNE)
	vue:SetElementInitializer("Button", function(ligne, element) self:InitialiserLigne(ligne, element) end)
	ScrollUtil.InitScrollBoxListWithScrollBar(boite, barre, vue)
	boite:SetPoint("TOPLEFT", cadre, "TOPLEFT", 4, -4)
	boite:SetPoint("BOTTOMRIGHT", cadre, "BOTTOMRIGHT", -22, 4)
	barre:SetPoint("TOPLEFT", boite, "TOPRIGHT", 4, 0)
	barre:SetPoint("BOTTOMLEFT", boite, "BOTTOMRIGHT", 4, 0)
	f.liste = boite

	f.vide = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	f.vide:SetPoint("CENTER")
	f.vide:SetText(L.COURSES_VIDE)
	f.vide:Hide()

	f.bilan = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.bilan:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 20)

	f.copier = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.copier:SetSize(180, 24)
	f.copier:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
	f.copier:SetText(L.COURSES_CHAT)
	f.copier:SetScript("OnClick", function() self:CopierDansLeChat() end)

	f:SetScript("OnShow", function() self:Rafraichir() end)
	return true
end

function Courses:InitialiserLigne(ligne, e)
	if not ligne.initialise then
		ligne.initialise = true
		ligne.icone = ligne:CreateTexture(nil, "ARTWORK")
		ligne.icone:SetSize(22, 22)
		ligne.icone:SetPoint("LEFT", 6, 0)
		ligne.nom = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		ligne.nom:SetPoint("LEFT", ligne.icone, "RIGHT", 8, 0)
		ligne.nom:SetJustifyH("LEFT")
		ligne.chiffres = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		ligne.chiffres:SetPoint("RIGHT", -8, 0)
		ligne.chiffres:SetJustifyH("RIGHT")
		ligne.nom:SetPoint("RIGHT", ligne.chiffres, "LEFT", -8, 0)
		ligne.survol = ligne:CreateTexture(nil, "HIGHLIGHT")
		ligne.survol:SetAllPoints()
		ligne.survol:SetColorTexture(1, 1, 1, 0.07)
		ligne:SetScript("OnEnter", function(l) Courses:Infobulle(l) end)
		ligne:SetScript("OnLeave", function()
			if GameTooltip then GameTooltip:Hide() end
		end)
	end
	ligne.element = e
	ligne.icone:SetTexture(iconeObjet(e.itemID) or ICONE_INCONNUE)
	ligne.nom:SetText(e.nom)
	local couleur = e.manque > 0 and "|cffe8806a" or "|cff5fd068"
	local texte = string.format(L.COURSES_LIGNE, e.stock, e.besoin)
	if e.manque > 0 then texte = texte .. "  ·  " .. couleur .. string.format(L.COURSES_MANQUE, e.manque) .. "|r" end
	ligne.chiffres:SetText(texte)
end

--- Où sont les composants : un personnage par ligne, avec la date de son dernier relevé.
function Courses:Infobulle(ligne)
	local e = ligne.element
	if not e or not GameTooltip then return end
	GameTooltip:SetOwner(ligne, "ANCHOR_RIGHT")
	GameTooltip:SetText(e.nom, 1, 1, 1)
	GameTooltip:AddLine(string.format(L.COURSES_COMMANDES_LIGNE, e.commandes), 0.66, 0.61, 0.53)
	GameTooltip:AddLine(" ")
	if #e.detail == 0 then
		GameTooltip:AddLine(L.COURSES_AUCUN_STOCK, 0.9, 0.5, 0.42)
	else
		local maintenant = time()
		for _, d in ipairs(e.detail) do
			local suffixe = ""
			if d.maj then
				suffixe = " |cffa89c86(" .. ns.Atelier.Age(d.maj) .. ")|r"
				if ns.Stock.ancien(d.maj, maintenant) then suffixe = suffixe .. " |cffe8a94f" .. L.COURSES_ANCIEN .. "|r" end
			end
			GameTooltip:AddLine(string.format("%s : %d%s", d.cle, d.n, suffixe), 1, 1, 1)
		end
	end
	GameTooltip:Show()
end

function Courses:Rafraichir()
	local f = self.cadre
	if not f or not f:IsShown() or not ns.Stocks then return end
	local liste = ns.Stocks:Courses()
	f.liste:SetDataProvider(CreateDataProvider(liste))
	f.vide:SetShown(#liste == 0)

	local manque = 0
	for _, e in ipairs(liste) do
		if e.manque > 0 then manque = manque + 1 end
	end
	f.bilan:SetText(#liste == 0 and "" or string.format(L.COURSES_BILAN, #liste, manque))
	f.copier:SetEnabled(manque > 0)
	self.liste = liste
end

--- Ouvre la ligne de chat avec le résumé du manque : le joueur n'a plus qu'à envoyer (appuyer sur Entrée).
function Courses:CopierDansLeChat()
	local texte = ns.Stock.resume(self.liste or {}, L.COURSES_RESUME)
	if texte == "" then return end
	if #texte > 250 then texte = texte:sub(1, 247) .. "…" end
	if ChatFrame_OpenChat then
		ChatFrame_OpenChat(texte)
	else
		Compagnons:Print(texte)
	end
end
