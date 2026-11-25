-- Onglet « Améliorations » : ce que la guilde peut fabriquer pour faire mieux que l'équipement porté, emplacement par
-- emplacement. Le calcul est dans Core/Ameliorations.lua, la lecture de l'équipement dans Modules/Ameliorations.lua.
-- Un clic ouvre le dialogue de commande habituel, rien ne se commande tout seul. Complète le module Fenetre.
local _, ns = ...
local L = ns.L

local Fenetre = ns.Fenetre

local HAUTEUR_LIGNE = 40
local ICONE_INCONNUE = 134400

-- Noms d'emplacement fournis par le jeu (HEADSLOT…), par numéro d'emplacement d'équipement.
local NOMS_EMPLACEMENT = {
	[1] = "HEADSLOT", [2] = "NECKSLOT", [3] = "SHOULDERSLOT", [4] = "SHIRTSLOT", [5] = "CHESTSLOT", [6] = "WAISTSLOT",
	[7] = "LEGSSLOT", [8] = "FEETSLOT", [9] = "WRISTSLOT", [10] = "HANDSSLOT", [11] = "FINGER0SLOT", [13] = "TRINKET0SLOT",
	[15] = "BACKSLOT", [16] = "MAINHANDSLOT", [17] = "SECONDARYHANDSLOT", [18] = "RANGEDSLOT", [19] = "TABARDSLOT",
}

local function nomEmplacement(e)
	local global = NOMS_EMPLACEMENT[e]
	return (global and _G[global]) or ("#" .. e)
end

local function couleurQualite(q)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

function Fenetre:CreerAmeliorations(f)
	local vue = CreateFrame("Frame", nil, f)
	vue:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -34)
	vue:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 30)
	vue:Hide()
	self.vueAmeliorations = vue
	self.ameliorations = { guilde = true, enLigne = false, vides = false }

	vue.titre = vue:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	vue.titre:SetPoint("TOPLEFT", vue, "TOPLEFT", 6, -8)

	local menu = CreateFrame("DropdownButton", nil, vue, "WowStyle1FilterDropdownTemplate")
	menu:SetSize(220, 22)
	menu:SetPoint("TOPRIGHT", vue, "TOPRIGHT", -6, -3)
	menu:SetText(L.FILTRES)
	if menu.SetupMenu then
		menu:SetupMenu(function(_, racine)
			local function option(texte, cle)
				racine:CreateCheckbox(texte,
					function() return self.ameliorations[cle] end,
					function()
						self.ameliorations[cle] = not self.ameliorations[cle]
						self:RafraichirAmeliorations()
					end)
			end
			option(L.AMELIORATIONS_GUILDE, "guilde")
			option(L.AMELIORATIONS_EN_LIGNE, "enLigne")
			option(L.AMELIORATIONS_VIDES, "vides")
		end)
	end

	-- Spécialisation : sans elle on compare le niveau d'objet ; avec elle, un score de stats (Core/Ameliorations.lua).
	local spec = CreateFrame("DropdownButton", nil, vue, "WowStyle1DropdownTemplate")
	spec:SetSize(190, 22)
	spec:SetPoint("RIGHT", menu, "LEFT", -8, 0)
	if spec.SetDefaultText then spec:SetDefaultText(L.AMELIORATIONS_SPEC) end
	if spec.SetupMenu then
		spec:SetupMenu(function(_, racine)
			local function choix(texte, valeur)
				racine:CreateRadio(texte,
					function() return ns.AmeliorationsModule:Spec() == valeur end,
					function()
						ns.AmeliorationsModule:ChoisirSpec(valeur)
						self:RafraichirAmeliorations()
					end)
			end
			choix(L.SPEC_AUTO, nil)
			choix(L.SPEC_AUCUNE, "aucune")
			local _, classe = UnitClass("player")
			for _, sp in ipairs(ns.Ameliorations.specs(classe)) do choix(GetLocale() == "frFR" and sp.fr or sp.en, sp.cle) end
		end)
	end

	local cadre = CreateFrame("Frame", nil, vue, "InsetFrameTemplate")
	cadre:SetPoint("TOPLEFT", vue, "TOPLEFT", 0, -30)
	cadre:SetPoint("BOTTOMRIGHT", vue, "BOTTOMRIGHT", 0, 0)
	local boite = CreateFrame("Frame", nil, cadre, "WowScrollBoxList")
	local barre = CreateFrame("EventFrame", nil, cadre, "MinimalScrollBar")
	local elements = CreateScrollBoxListLinearView()
	elements:SetElementExtent(HAUTEUR_LIGNE)
	elements:SetElementInitializer("Button", function(ligne, e) self:InitialiserLigneAmelioration(ligne, e) end)
	ScrollUtil.InitScrollBoxListWithScrollBar(boite, barre, elements)
	boite:SetPoint("TOPLEFT", cadre, "TOPLEFT", 4, -4)
	boite:SetPoint("BOTTOMRIGHT", cadre, "BOTTOMRIGHT", -22, 4)
	barre:SetPoint("TOPLEFT", boite, "TOPRIGHT", 4, 0)
	barre:SetPoint("BOTTOMLEFT", boite, "BOTTOMRIGHT", 4, 0)
	vue.liste = boite

	vue.vide = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	vue.vide:SetPoint("CENTER")
	vue.vide:SetWidth(520)
	vue.vide:SetJustifyH("CENTER")
	vue.vide:Hide()
end

function Fenetre:InitialiserLigneAmelioration(ligne, e)
	if not ligne.initialise then
		ligne.initialise = true
		ligne.fond = ligne:CreateTexture(nil, "BACKGROUND")
		ligne.fond:SetAllPoints()
		ligne.survol = ligne:CreateTexture(nil, "HIGHLIGHT")
		ligne.survol:SetAllPoints()
		ligne.survol:SetColorTexture(1, 1, 1, 0.07)
		ligne.entete = ligne:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		ligne.entete:SetPoint("LEFT", 10, 0)
		ligne.icone = ligne:CreateTexture(nil, "ARTWORK")
		ligne.icone:SetSize(30, 30)
		ligne.icone:SetPoint("LEFT", 14, 0)
		ligne.titre = ligne:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		ligne.titre:SetPoint("TOPLEFT", ligne.icone, "TOPRIGHT", 8, 0)
		ligne.titre:SetPoint("RIGHT", ligne, "RIGHT", -230, 0)
		ligne.titre:SetJustifyH("LEFT")
		ligne.detail = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		ligne.detail:SetPoint("TOPLEFT", ligne.titre, "BOTTOMLEFT", 0, -2)
		ligne.detail:SetPoint("RIGHT", ligne, "RIGHT", -230, 0)
		ligne.detail:SetJustifyH("LEFT")
		ligne.qui = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		ligne.qui:SetPoint("RIGHT", ligne, "RIGHT", -118, 0)
		ligne.qui:SetWidth(104)
		ligne.qui:SetJustifyH("RIGHT")
		ligne.commander = CreateFrame("Button", nil, ligne, "UIPanelButtonTemplate")
		ligne.commander:SetSize(104, 24)
		ligne.commander:SetPoint("RIGHT", -8, 0)
		ligne.commander:SetText(L.COMMANDER)
		ligne.commander:SetScript("OnClick", function(b)
			local c = b:GetParent().candidat
			if c then ns.Dialogue:Ouvrir(c.spell, c.suggere and { crafteur = c.suggere } or nil) end
		end)
		ligne:SetScript("OnEnter", function(l)
			local c = l.candidat
			if not c or not ns.infobulleRecette then return end
			local ok, erreur = pcall(ns.infobulleRecette, l, c.spell)
			if not ok then
				ns.log("erreur", "ui", "infobulle de l'amélioration : %s", tostring(erreur))
				return
			end
			-- Ce que l'on porte aujourd'hui, et ce que le calcul ne voit pas.
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(string.format(L.AMELIORATIONS_PORTE, c.porteIlvl), 0.66, 0.61, 0.53)
			GameTooltip:AddLine(L.AMELIORATIONS_EFFETS, 0.66, 0.61, 0.53, true)
			if not c.verifie then GameTooltip:AddLine(L.AMELIORATIONS_NON_VERIFIE, 0.91, 0.66, 0.31, true) end
			GameTooltip:Show()
		end)
		ligne:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	end

	ligne.candidat = e.candidat
	local entete = e.entete ~= nil
	ligne.entete:SetShown(entete)
	ligne.icone:SetShown(not entete)
	ligne.titre:SetShown(not entete)
	ligne.detail:SetShown(not entete)
	ligne.qui:SetShown(not entete)
	ligne.commander:SetShown(not entete)
	ligne.fond:SetColorTexture(1, 1, 1, entete and 0.08 or 0.03)
	ligne:EnableMouse(not entete)
	if entete then
		ligne.entete:SetText(e.entete)
		return
	end

	local c = e.candidat
	local recette = ns.Recettes.recettes[c.spell]
	local objet = recette and recette.objet or 0
	local icone = objet > 0 and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(objet)
	ligne.icone:SetTexture(icone or ICONE_INCONNUE)
	ligne.titre:SetText(recette and recette.nom or "?")
	ligne.titre:SetTextColor(couleurQualite(recette and recette.qualite))
	local porte = c.porteItem and (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(c.porteItem)) or nil
	ligne.detail:SetText(string.format("|cff5fd068+%d|r %s · %s %d · %s", math.floor(c.gain + 0.5),
		c.unite == "stats" and L.AMELIORATIONS_UNITE_STATS or L.AMELIORATIONS_UNITE_ILVL, L.AMELIORATIONS_ILVL, c.ilvl,
		string.format(L.AMELIORATIONS_REMPLACE, porte or L.AMELIORATIONS_VIDE)))

	-- Le crafteur à suggérer : en ligne, peu chargé, bon niveau (même règle que le dialogue de commande).
	local suggere = ns.Suggestion.meilleur(ns.catalogue:Crafteurs(c.spell), ns.estEnLigne,
		ns.Suggestion.charges(ns.db.global.commandes), ns.Atelier:Miens())
	c.suggere = suggere and suggere.cle or nil
	ligne.qui:SetText(suggere and string.format("|cffa89c86%s|r", suggere.nom) or "")
end

function Fenetre:RafraichirAmeliorations()
	local vue = self.vueAmeliorations
	if not vue or not self.cadre or not self.cadre:IsShown() or self.onglet ~= 6 then return end
	local groupes, donneesPresentes = ns.AmeliorationsModule:Chercher(self.ameliorations)

	if not donneesPresentes then
		vue.titre:SetText("")
		vue.vide:SetText(L.AMELIORATIONS_SANS_DONNEES)
		vue.vide:Show()
		vue.liste:SetDataProvider(CreateDataProvider({}))
		return
	end

	local lignes, nb = {}, 0
	local parEmplacement = {}
	for _, g in ipairs(groupes) do parEmplacement[g.emplacement] = g end
	local emplacements = {}
	if self.ameliorations.vides then
		for e in pairs(NOMS_EMPLACEMENT) do emplacements[#emplacements + 1] = e end
	else
		for _, g in ipairs(groupes) do emplacements[#emplacements + 1] = g.emplacement end
	end
	table.sort(emplacements)
	for _, e in ipairs(emplacements) do
		local g = parEmplacement[e]
		lignes[#lignes + 1] = { entete = nomEmplacement(e) .. (g and "" or ("  |cffa89c86" .. L.AMELIORATIONS_RIEN .. "|r")) }
		for _, c in ipairs(g and g.candidats or {}) do
			lignes[#lignes + 1] = { candidat = c }
			nb = nb + 1
		end
	end
	vue.titre:SetText(string.format(L.AMELIORATIONS_NOMBRE, nb))
	vue.vide:SetText(L.AMELIORATIONS_AUCUNE)
	vue.vide:SetShown(#lignes == 0)
	vue.liste:SetDataProvider(CreateDataProvider(lignes))
end
