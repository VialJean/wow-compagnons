-- Onglet « Annonces » : les messages permanents de la guilde, en texte libre. Complète le module Fenetre.
-- Le modèle est dans Core/Annonces.lua.
local _, ns = ...
local L = ns.L

local Fenetre = ns.Fenetre

local HAUTEUR_LIGNE = 44
local MAX_TEXTE = 200

local function couleurClasse(classe)
	local c = classe and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classe]
	if c then return c.r, c.g, c.b end
	return 0.8, 0.8, 0.8
end

function Fenetre:CreerAnnonces(f)
	local vue = CreateFrame("Frame", nil, f)
	vue:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -34)
	vue:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 30)
	vue:Hide()
	self.vueAnnonces = vue

	-- Saisie du message : un clic sur Publier (ou Entrée) le diffuse à la guilde.
	local saisie = CreateFrame("EditBox", nil, vue, "SearchBoxTemplate")
	saisie:SetPoint("TOPLEFT", vue, "TOPLEFT", 6, -2)
	saisie:SetPoint("TOPRIGHT", vue, "TOPRIGHT", -150, -2)
	saisie:SetHeight(22)
	saisie:SetAutoFocus(false)
	saisie:SetMaxLetters(MAX_TEXTE)
	if saisie.Instructions then saisie.Instructions:SetText(L.ANNONCES_PUBLIER_AIDE) end
	saisie:SetScript("OnEnterPressed", function() self:PublierAnnonce() end)
	vue.saisie = saisie

	vue.publier = CreateFrame("Button", nil, vue, "UIPanelButtonTemplate")
	vue.publier:SetSize(130, 24)
	vue.publier:SetPoint("TOPRIGHT", vue, "TOPRIGHT", -6, -1)
	vue.publier:SetText(L.ANNONCES_PUBLIER)
	vue.publier:SetScript("OnClick", function() self:PublierAnnonce() end)

	local cadre = CreateFrame("Frame", nil, vue, "InsetFrameTemplate")
	cadre:SetPoint("TOPLEFT", vue, "TOPLEFT", 0, -30)
	cadre:SetPoint("BOTTOMRIGHT", vue, "BOTTOMRIGHT", 0, 0)
	local boite = CreateFrame("Frame", nil, cadre, "WowScrollBoxList")
	local barre = CreateFrame("EventFrame", nil, cadre, "MinimalScrollBar")
	local elements = CreateScrollBoxListLinearView()
	elements:SetElementExtent(HAUTEUR_LIGNE)
	elements:SetElementInitializer("Button", function(ligne, a) self:InitialiserLigneAnnonce(ligne, a) end)
	ScrollUtil.InitScrollBoxListWithScrollBar(boite, barre, elements)
	boite:SetPoint("TOPLEFT", cadre, "TOPLEFT", 4, -4)
	boite:SetPoint("BOTTOMRIGHT", cadre, "BOTTOMRIGHT", -22, 4)
	barre:SetPoint("TOPLEFT", boite, "TOPRIGHT", 4, 0)
	barre:SetPoint("BOTTOMLEFT", boite, "BOTTOMRIGHT", 4, 0)
	vue.liste = boite

	vue.vide = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	vue.vide:SetPoint("CENTER")
	vue.vide:SetWidth(520)
	vue.vide:SetText(L.ANNONCES_AUCUNE)
	vue.vide:Hide()

	ns.addon:RegisterMessage("COMPAGNONS_ANNONCES_MAJ", function()
		if self.cadre and self.cadre:IsShown() and self.onglet == 5 then self:RafraichirAnnonces(true) end
	end)
end

function Fenetre:InitialiserLigneAnnonce(ligne, a)
	if not ligne.initialise then
		ligne.initialise = true
		ligne.fond = ligne:CreateTexture(nil, "BACKGROUND")
		ligne.fond:SetAllPoints()
		ligne.fond:SetColorTexture(1, 1, 1, 0.03)
		ligne.auteur = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		ligne.auteur:SetPoint("TOPLEFT", ligne, "TOPLEFT", 8, -5)
		ligne.auteur:SetPoint("RIGHT", ligne, "RIGHT", -120, 0)
		ligne.auteur:SetJustifyH("LEFT")
		ligne.texte = ligne:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		ligne.texte:SetPoint("TOPLEFT", ligne.auteur, "BOTTOMLEFT", 0, -2)
		ligne.texte:SetPoint("RIGHT", ligne, "RIGHT", -120, 0)
		ligne.texte:SetJustifyH("LEFT")
		ligne.texte:SetJustifyV("TOP")
		ligne.texte:SetMaxLines(2)
		ligne.retirer = CreateFrame("Button", nil, ligne, "UIPanelButtonTemplate")
		ligne.retirer:SetSize(104, 24)
		ligne.retirer:SetPoint("RIGHT", -8, 0)
		ligne.retirer:SetText(L.ANNONCE_RETIRER)
		ligne.retirer:SetScript("OnClick", function(b)
			ns.AnnoncesModule:Retirer(b:GetParent().annonce)
			Fenetre:RafraichirAnnonces(true)
		end)
	end
	ligne.annonce = a
	local perso = ns.db.global.personnages[a.auteur]
	local r, g, b = couleurClasse(perso and perso.classe)
	local enLigne = ns.estEnLigne and ns.estEnLigne(a.auteur)
	ligne.auteur:SetText(string.format("|cff%02x%02x%02x%s|r |cffa89c86· %s|r", r * 255, g * 255, b * 255, a.auteur,
		enLigne and L.EN_LIGNE or L.HORS_LIGNE))
	ligne.texte:SetText(a.texte)
	ligne.retirer:SetShown(ns.AnnoncesModule:EstMienne(a))
end

--- Publie le message saisi.
function Fenetre:PublierAnnonce()
	local saisie = self.vueAnnonces.saisie
	local texte = saisie:GetText()
	if not texte:match("%S") then return end
	local a, erreur = ns.AnnoncesModule:Publier({ texte = texte })
	if not a then
		ns.addon:Print(erreur)
		return
	end
	saisie:SetText("")
	saisie:ClearFocus()
	self:RafraichirAnnonces(true)
end

function Fenetre:RafraichirAnnonces(garder)
	local vue = self.vueAnnonces
	if not vue or not self.cadre or not self.cadre:IsShown() or self.onglet ~= 5 then return end
	local liste = ns.Annonces.liste(ns.AnnoncesModule:Toutes(), { estEnLigne = ns.estEnLigne }, time())
	vue.vide:SetShown(#liste == 0)
	local fournisseur = CreateDataProvider(liste)
	if garder and ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition then
		vue.liste:SetDataProvider(fournisseur, ScrollBoxConstants.RetainScrollPosition)
	else
		vue.liste:SetDataProvider(fournisseur)
	end
end
