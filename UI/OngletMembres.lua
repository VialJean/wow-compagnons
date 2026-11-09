-- Onglet « Membres » de la fenêtre principale : qui a l'addon dans la guilde, et quels métiers (niveau, recettes connues).
-- Source : mes personnages et les profils reçus par la synchro (Catalogue:Membres). Complète le module Fenetre.
local _, ns = ...
local L = ns.L

local Fenetre = ns.Fenetre

local HAUTEUR_LIGNE = 40

local function couleurClasse(classe)
	local c = classe and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classe]
	if c then return c.r, c.g, c.b end
	return 0.8, 0.8, 0.8
end

function Fenetre:CreerMembres(f)
	local vue = CreateFrame("Frame", nil, f)
	vue:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -34)
	vue:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 30)
	vue:Hide()
	self.vueMembres = vue
	self.metierMembres = nil
	self.membresEnLigne = false

	vue.titre = vue:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	vue.titre:SetPoint("TOPLEFT", vue, "TOPLEFT", 70, -8)

	local menu = CreateFrame("DropdownButton", nil, vue, "WowStyle1DropdownTemplate")
	menu:SetSize(220, 24)
	menu:SetPoint("TOPRIGHT", vue, "TOPRIGHT", -6, -2)
	if menu.SetupMenu then
		menu:SetupMenu(function(_, racine)
			racine:CreateCheckbox(L.MEMBRES_EN_LIGNE_SEUL,
				function() return self.membresEnLigne end,
				function() self.membresEnLigne = not self.membresEnLigne; self:RafraichirMembres() end)
			racine:CreateRadio(L.TOUS_METIERS,
				function() return self.metierMembres == nil end,
				function() self.metierMembres = nil; self:RafraichirMembres() end)
			for _, m in ipairs(ns.catalogue:Metiers()) do
				local id = m.id
				racine:CreateRadio(m.nom,
					function() return self.metierMembres == id end,
					function() self.metierMembres = id; self:RafraichirMembres() end)
			end
		end)
	end
	vue.menu = menu

	local cadre = CreateFrame("Frame", nil, vue, "InsetFrameTemplate")
	cadre:SetPoint("TOPLEFT", vue, "TOPLEFT", 0, -30)
	cadre:SetPoint("BOTTOMRIGHT", vue, "BOTTOMRIGHT", 0, 0)

	local boite = CreateFrame("Frame", nil, cadre, "WowScrollBoxList")
	local barre = CreateFrame("EventFrame", nil, cadre, "MinimalScrollBar")
	local elements = CreateScrollBoxListLinearView()
	elements:SetElementExtent(HAUTEUR_LIGNE)
	elements:SetElementInitializer("Button", function(ligne, membre) self:InitialiserLigneMembre(ligne, membre) end)
	ScrollUtil.InitScrollBoxListWithScrollBar(boite, barre, elements)
	boite:SetPoint("TOPLEFT", cadre, "TOPLEFT", 4, -4)
	boite:SetPoint("BOTTOMRIGHT", cadre, "BOTTOMRIGHT", -22, 4)
	barre:SetPoint("TOPLEFT", boite, "TOPRIGHT", 4, 0)
	barre:SetPoint("BOTTOMLEFT", boite, "BOTTOMRIGHT", 4, 0)
	vue.liste = boite

	vue.vide = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	vue.vide:SetPoint("CENTER")
	vue.vide:SetWidth(520)
	vue.vide:SetText(L.MEMBRES_AUCUN)
	vue.vide:Hide()
end

function Fenetre:InitialiserLigneMembre(ligne, membre)
	if not ligne.initialise then
		ligne.initialise = true
		ligne.fond = ligne:CreateTexture(nil, "BACKGROUND")
		ligne.fond:SetAllPoints()
		ligne.fond:SetColorTexture(1, 1, 1, 0.03)
		ligne.survol = ligne:CreateTexture(nil, "HIGHLIGHT")
		ligne.survol:SetAllPoints()
		ligne.survol:SetColorTexture(1, 1, 1, 0.08)

		ligne.nom = ligne:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		ligne.nom:SetPoint("TOPLEFT", 10, -6)
		ligne.nom:SetJustifyH("LEFT")
		ligne.etat = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		ligne.etat:SetPoint("TOPRIGHT", -10, -7)
		ligne.etat:SetJustifyH("RIGHT")
		ligne.metiers = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		ligne.metiers:SetPoint("BOTTOMLEFT", 10, 6)
		ligne.metiers:SetPoint("RIGHT", -10, 0)
		ligne.metiers:SetJustifyH("LEFT")
	end

	local r, g, b = couleurClasse(membre.classe)
	ligne.nom:SetTextColor(r, g, b)
	ligne.nom:SetText(membre.moi and (membre.nom .. " |cffa89c86(" .. L.MEMBRES_MOI .. ")|r") or membre.nom)
	local enLigne = ns.estEnLigne and ns.estEnLigne(membre.cle)
	ligne.etat:SetText(enLigne and ("|cff5cd65c" .. L.EN_LIGNE .. "|r") or ("|cffa89c86" .. L.HORS_LIGNE .. "|r"))

	local morceaux = {}
	for _, m in ipairs(membre.metiers) do
		local niveau = (m.max and m.max > 0) and string.format("%d/%d", m.niveau, m.max) or tostring(m.niveau)
		morceaux[#morceaux + 1] = string.format("%s %s |cffa89c86(%s)|r", m.nom, niveau,
			string.format(L.MEMBRES_RECETTES, m.recettes))
	end
	ligne.metiers:SetText(table.concat(morceaux, "   "))
end

function Fenetre:RafraichirMembres()
	local vue = self.vueMembres
	if not vue or not self.cadre or not self.cadre:IsShown() or self.onglet ~= 3 or not ns.catalogue then return end

	local liste = {}
	for _, membre in ipairs(ns.catalogue:Membres()) do
		local garde = true
		if self.membresEnLigne and not (ns.estEnLigne and ns.estEnLigne(membre.cle)) then garde = false end
		if garde and self.metierMembres then
			garde = false
			for _, m in ipairs(membre.metiers) do
				if m.id == self.metierMembres then garde = true end
			end
		end
		if garde then liste[#liste + 1] = membre end
	end

	-- Les membres connectés d'abord, dans l'ordre alphabétique.
	local ordre = {}
	for i, m in ipairs(liste) do ordre[m] = i end
	table.sort(liste, function(a, b)
		local ea = ns.estEnLigne and ns.estEnLigne(a.cle) or false
		local eb = ns.estEnLigne and ns.estEnLigne(b.cle) or false
		if ea ~= eb then return ea end
		return ordre[a] < ordre[b]
	end)

	vue.titre:SetText(string.format(L.MEMBRES_NOMBRE, #liste))
	vue.vide:SetShown(#liste == 0)
	vue.liste:SetDataProvider(CreateDataProvider(liste))
end
