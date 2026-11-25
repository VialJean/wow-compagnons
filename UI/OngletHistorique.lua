-- Onglet « Historique » : les commandes terminées ou annulées que cette copie a vues (voir Core/Historique.lua), les plus
-- récentes d'abord, avec un filtre par membre et par métier et une recherche par objet. Complète le module Fenetre.
local _, ns = ...
local L = ns.L

local Fenetre = ns.Fenetre

local HAUTEUR_LIGNE = 38
local ICONE_INCONNUE = 134400

local function couleurQualite(q)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

local function iconeRecette(recette)
	if recette and recette.objet and recette.objet > 0 then
		local icone = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(recette.objet)
		if icone then return icone end
	end
	return ICONE_INCONNUE
end

function Fenetre:CreerHistorique(f)
	local vue = CreateFrame("Frame", nil, f)
	vue:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -34)
	vue:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 30)
	vue:Hide()
	self.vueHistorique = vue
	self.histoMembre, self.histoMetier, self.histoTexte = nil, nil, ""

	local recherche = CreateFrame("EditBox", nil, vue, "SearchBoxTemplate")
	recherche:SetSize(240, 20)
	recherche:SetPoint("TOPLEFT", vue, "TOPLEFT", 68, -6)
	recherche:SetAutoFocus(false)
	if recherche.Instructions then recherche.Instructions:SetText(L.RECHERCHE) end
	recherche:HookScript("OnTextChanged", function(boite)
		self.histoTexte = boite:GetText() or ""
		self:RafraichirHistorique()
	end)

	local menu = CreateFrame("DropdownButton", nil, vue, "WowStyle1DropdownTemplate")
	menu:SetSize(220, 24)
	menu:SetPoint("TOPRIGHT", vue, "TOPRIGHT", -6, -2)
	if menu.SetupMenu then
		menu:SetupMenu(function(_, racine)
			racine:CreateRadio(L.HISTO_TOUS_MEMBRES,
				function() return self.histoMembre == nil end,
				function() self.histoMembre = nil; self:RafraichirHistorique() end)
			local vus, cles = {}, {}
			for _, e in ipairs(ns.db.global.historique) do
				for _, cle in ipairs({ e.client, e.crafteur or false }) do
					if cle and not vus[cle] then vus[cle] = true; cles[#cles + 1] = cle end
				end
			end
			table.sort(cles)
			for _, cle in ipairs(cles) do
				racine:CreateRadio(cle,
					function() return self.histoMembre == cle end,
					function() self.histoMembre = cle; self:RafraichirHistorique() end)
			end
			racine:CreateDivider()
			racine:CreateRadio(L.TOUS_METIERS,
				function() return self.histoMetier == nil end,
				function() self.histoMetier = nil; self:RafraichirHistorique() end)
			for _, m in ipairs(ns.catalogue and ns.catalogue:Metiers() or {}) do
				local id = m.id
				racine:CreateRadio(m.nom,
					function() return self.histoMetier == id end,
					function() self.histoMetier = id; self:RafraichirHistorique() end)
			end
		end)
	end
	vue.menu = menu

	vue.titre = vue:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	vue.titre:SetPoint("LEFT", recherche, "RIGHT", 14, 0)

	local cadre = CreateFrame("Frame", nil, vue, "InsetFrameTemplate")
	cadre:SetPoint("TOPLEFT", vue, "TOPLEFT", 0, -30)
	cadre:SetPoint("BOTTOMRIGHT", vue, "BOTTOMRIGHT", 0, 0)

	local boite = CreateFrame("Frame", nil, cadre, "WowScrollBoxList")
	local barre = CreateFrame("EventFrame", nil, cadre, "MinimalScrollBar")
	local elements = CreateScrollBoxListLinearView()
	elements:SetElementExtent(HAUTEUR_LIGNE)
	elements:SetElementInitializer("Button", function(ligne, entree) self:InitialiserLigneHistorique(ligne, entree) end)
	ScrollUtil.InitScrollBoxListWithScrollBar(boite, barre, elements)
	boite:SetPoint("TOPLEFT", cadre, "TOPLEFT", 4, -4)
	boite:SetPoint("BOTTOMRIGHT", cadre, "BOTTOMRIGHT", -22, 4)
	barre:SetPoint("TOPLEFT", boite, "TOPRIGHT", 4, 0)
	barre:SetPoint("BOTTOMLEFT", boite, "BOTTOMRIGHT", 4, 0)
	vue.liste = boite

	vue.vide = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	vue.vide:SetPoint("CENTER")
	vue.vide:SetWidth(520)
	vue.vide:SetText(L.HISTO_AUCUN)
	vue.vide:Hide()

	ns.addon:RegisterMessage("COMPAGNONS_HISTORIQUE_MAJ", function()
		if self.cadre and self.cadre:IsShown() and self.onglet == 4 then self:RafraichirHistorique() end
	end)
end

function Fenetre:InitialiserLigneHistorique(ligne, e)
	if not ligne.initialise then
		ligne.initialise = true
		ligne.fond = ligne:CreateTexture(nil, "BACKGROUND")
		ligne.fond:SetAllPoints()
		ligne.fond:SetColorTexture(1, 1, 1, 0.03)
		ligne.survol = ligne:CreateTexture(nil, "HIGHLIGHT")
		ligne.survol:SetAllPoints()
		ligne.survol:SetColorTexture(1, 1, 1, 0.07)
		ligne.icone = ligne:CreateTexture(nil, "ARTWORK")
		ligne.icone:SetSize(30, 30)
		ligne.icone:SetPoint("LEFT", 8, 0)
		ligne.titre = ligne:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		ligne.titre:SetPoint("TOPLEFT", ligne.icone, "TOPRIGHT", 8, -1)
		ligne.titre:SetPoint("RIGHT", ligne, "RIGHT", -150, 0)
		ligne.titre:SetJustifyH("LEFT")
		ligne.meta = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		ligne.meta:SetPoint("BOTTOMLEFT", ligne.icone, "BOTTOMRIGHT", 8, 0)
		ligne.meta:SetPoint("RIGHT", ligne, "RIGHT", -150, 0)
		ligne.meta:SetJustifyH("LEFT")
		ligne.issue = ligne:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		ligne.issue:SetPoint("TOPRIGHT", -10, -8)
		ligne.issue:SetJustifyH("RIGHT")
		ligne.date = ligne:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		ligne.date:SetPoint("BOTTOMRIGHT", -10, 7)
		ligne:SetScript("OnEnter", function(l)
			if l.spell and ns.infobulleRecette then
				local ok, erreur = pcall(ns.infobulleRecette, l, l.spell)
				if not ok then ns.log("erreur", "ui", "infobulle de l'historique : %s", tostring(erreur)) end
			end
		end)
		ligne:SetScript("OnLeave", function()
			if GameTooltip then GameTooltip:Hide() end
		end)
	end
	ligne.spell = e.spell
	local recette = ns.Recettes.recettes[e.spell]
	ligne.icone:SetTexture(iconeRecette(recette))
	ligne.titre:SetText(string.format("%d × %s", e.qte, recette and recette.nom or "?"))
	ligne.titre:SetTextColor(couleurQualite(recette and recette.qualite))
	local meta = string.format(L.HISTO_PAR, e.client)
	if e.crafteur then meta = meta .. " · " .. string.format(L.HISTO_CRAFTE_PAR, e.crafteur) end
	if e.pourboire then meta = meta .. " · " .. string.format(L.POURBOIRE_LIGNE, ns.Marche.Argent(e.pourboire)) end
	ligne.meta:SetText(meta)
	local libelles = {
		terminee = "|cff5fd068" .. L.HISTO_TERMINEE .. "|r",
		annulee = "|cffe8806a" .. L.HISTO_ANNULEE .. "|r",
		sansconfirmation = "|cffe8a94f" .. L.HISTO_SANS_CONFIRMATION .. "|r",
	}
	ligne.issue:SetText(libelles[e.issue] or "")
	ligne.date:SetText(date("%d/%m/%Y", e.fin))
end

function Fenetre:RafraichirHistorique()
	local vue = self.vueHistorique
	if not vue or not self.cadre or not self.cadre:IsShown() or self.onglet ~= 4 then return end
	local liste = ns.Historique.liste(ns.db.global.historique, {
		membre = self.histoMembre, metier = self.histoMetier, texte = self.histoTexte,
		donnees = ns.Recettes, normaliser = ns.Catalogue and ns.Catalogue.normaliser,
	})
	vue.titre:SetText(string.format(L.HISTO_NOMBRE, #liste))
	vue.vide:SetShown(#liste == 0)
	vue.liste:SetDataProvider(CreateDataProvider(liste))
end
