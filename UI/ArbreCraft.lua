-- Arbre de craft : ce qu'il faut fabriquer, étage par étage, jusqu'aux matières premières, avec le stock de tous mes
-- personnages et le coût estimé. Ouvert depuis la fiche d'une recette de l'atelier. Le calcul vit dans Core/ArbreCraft.lua.
local _, ns = ...
local L = ns.L
local Compagnons = ns.addon

local Arbre = Compagnons:NewModule("ArbreCraft", "AceEvent-3.0")
ns.ArbreCraftUI = Arbre

local HAUTEUR_LIGNE = 24
local DECALAGE = 16
local ICONE_INCONNUE = 134400
local QTE_MAX = 999

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

local function couleurQualite(q)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

local function stock(id)
	if ns.Stocks then return ns.Stocks:Total(id) end
	if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id, true) or 0 end
	return 0
end

local function nomObjet(itemID)
	local objet = ns.Recettes.objets and ns.Recettes.objets[itemID]
	local nom = objet and objet[1] or ""
	if nom == "" and C_Item and C_Item.GetItemNameByID then nom = C_Item.GetItemNameByID(itemID) or "" end
	if nom == "" then nom = "#" .. itemID end
	return nom, objet and objet[2] or 1
end

--- Ouvre l'arbre de la recette `spellID` (une fabrication au départ).
function Arbre:Ouvrir(spellID)
	if not self.cadre then
		if not securise("création de l'arbre de craft", self.Creer, self) then return end
	end
	self.spellID = spellID
	self.qte = 1
	self.cadre:Show()
	self:Rafraichir()
end

function Arbre:Creer()
	local f = CreateFrame("Frame", "CompagnonsCraftTree", UIParent, "ButtonFrameTemplate")
	self.cadre = f
	f:SetSize(540, 520)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	tinsert(UISpecialFrames, "CompagnonsCraftTree")
	local principale = _G.CompagnonsFrame
	if principale and principale:IsShown() then
		f:SetPoint("TOPLEFT", principale, "TOPRIGHT", 8, 0)
	else
		f:SetPoint("CENTER")
	end

	securise("gabarit", function()
		if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(f) end
		if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(f) end
		if f.SetTitle then f:SetTitle(L.ARBRE_TITRE) elseif f.TitleText then f.TitleText:SetText(L.ARBRE_TITRE) end
	end)

	f.nom = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.nom:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -36)
	f.nom:SetPoint("RIGHT", f, "RIGHT", -150, 0)
	f.nom:SetJustifyH("LEFT")

	-- Nombre de fabrications demandées
	f.plus = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.plus:SetSize(26, 24)
	f.plus:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -34)
	f.plus:SetText("+")
	f.plus:SetScript("OnClick", function() self:ChangerQuantite(self.qte + 1) end)
	f.qte = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.qte:SetPoint("RIGHT", f.plus, "LEFT", -8, 0)
	f.qte:SetWidth(40)
	f.qte:SetJustifyH("CENTER")
	f.moins = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.moins:SetSize(26, 24)
	f.moins:SetPoint("RIGHT", f.qte, "LEFT", -8, 0)
	f.moins:SetText("-")
	f.moins:SetScript("OnClick", function() self:ChangerQuantite(self.qte - 1) end)

	f.resume = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.resume:SetPoint("TOPLEFT", f.nom, "BOTTOMLEFT", 0, -4)

	local cadre = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
	cadre:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -82)
	cadre:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 62)

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

	f.bilan = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.bilan:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 40)
	f.cout = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.cout:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 18)

	self:RegisterMessage("COMPAGNONS_STOCK_MAJ", "SurStock")
	return true
end

function Arbre:SurStock()
	if self.cadre and self.cadre:IsShown() then self:Rafraichir() end
end

function Arbre:ChangerQuantite(n)
	self.qte = math.max(1, math.min(QTE_MAX, math.floor(n)))
	self:Rafraichir()
end

function Arbre:InitialiserLigne(ligne, e)
	if not ligne.initialise then
		ligne.initialise = true
		ligne.icone = ligne:CreateTexture(nil, "ARTWORK")
		ligne.icone:SetSize(20, 20)
		ligne.nom = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		ligne.nom:SetJustifyH("LEFT")
		ligne.droite = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		ligne.droite:SetPoint("RIGHT", -8, 0)
		ligne.droite:SetJustifyH("RIGHT")
		ligne.survol = ligne:CreateTexture(nil, "HIGHLIGHT")
		ligne.survol:SetAllPoints()
		ligne.survol:SetColorTexture(1, 1, 1, 0.07)
		ligne:SetScript("OnEnter", function(l)
			if l.itemID then
				securise("infobulle du composant", ns.infobulleObjet, l, l.itemID, l.nomObjet, l.qualiteObjet, "ANCHOR_LEFT")
			end
		end)
		ligne:SetScript("OnLeave", function()
			if GameTooltip then GameTooltip:Hide() end
		end)
	end
	ligne.itemID = e.itemID
	ligne.icone:ClearAllPoints()
	ligne.icone:SetPoint("LEFT", 6 + e.profondeur * DECALAGE, 0)
	ligne.nom:ClearAllPoints()
	ligne.nom:SetPoint("LEFT", ligne.icone, "RIGHT", 6, 0)
	ligne.nom:SetPoint("RIGHT", ligne.droite, "LEFT", -8, 0)

	if not e.itemID then
		-- La racine : la recette demandée.
		local recette = ns.Recettes.recettes[e.spell]
		local objet = recette and recette.objet or 0
		ligne.icone:SetTexture(objet > 0 and iconeObjet(objet) or ICONE_INCONNUE)
		ligne.nom:SetText(string.format(L.ARBRE_RACINE, e.fabrications, recette and recette.nom or "?"))
		ligne.nom:SetTextColor(1, 0.82, 0)
		ligne.droite:SetText("")
		ligne.nomObjet, ligne.qualiteObjet = nil, nil
		return
	end

	local nom, qualite = nomObjet(e.itemID)
	ligne.nomObjet, ligne.qualiteObjet = nom, qualite
	ligne.icone:SetTexture(iconeObjet(e.itemID) or ICONE_INCONNUE)
	ligne.nom:SetText(string.format("%d × %s", e.besoin, nom))
	ligne.nom:SetTextColor(couleurQualite(qualite))
	if e.spell then
		-- Un composant que l'on fabrique : la recette utilisée et le nombre de fabrications.
		local recette = ns.Recettes.recettes[e.spell]
		local texte = string.format(L.ARBRE_FABRIQUER, e.fabrications, recette and ns.Recettes.metiers[recette.metier]
			and ns.Recettes.metiers[recette.metier].nom or "?")
		if e.surplus and e.surplus > 0 then texte = texte .. " · " .. string.format(L.ARBRE_SURPLUS, e.surplus) end
		ligne.droite:SetText("|cffe8a94f" .. texte .. "|r")
	else
		local possede = stock(e.itemID)
		local couleur = possede >= e.besoin and "|cff5fd068" or (possede > 0 and "|cffe8a94f" or "|cffe8806a")
		ligne.droite:SetText(string.format("%s%d|r / %d", couleur, possede, e.besoin))
	end
end

function Arbre:Rafraichir()
	local f = self.cadre
	if not f or not f:IsShown() or not self.spellID then return end
	local arbre = ns.ArbreCraft.construire(ns.Recettes, function(itemID) return ns.catalogue:RecettesCreant(itemID) end,
		self.spellID, self.qte)
	if not arbre then return end
	local recette = ns.Recettes.recettes[self.spellID]
	f.nom:SetText(recette.nom)
	f.qte:SetText(tostring(self.qte))

	local lignes = ns.ArbreCraft.lignes(arbre)
	local fournisseur = CreateDataProvider(lignes)
	if ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition then
		f.liste:SetDataProvider(fournisseur, ScrollBoxConstants.RetainScrollPosition)
	else
		f.liste:SetDataProvider(fournisseur)
	end

	local etages = ns.ArbreCraft.etages(arbre)
	if etages == 0 then
		f.resume:SetText("|cffa89c86" .. L.ARBRE_AUCUN .. "|r")
	else
		f.resume:SetText(string.format(L.ARBRE_ETAGES, etages))
	end

	-- Matières premières : ce qui manque et ce que cela coûte.
	local manque, besoins = 0, {}
	for _, feuille in ipairs(arbre.feuilles) do
		besoins[#besoins + 1] = { feuille.itemID, feuille.qte }
		if stock(feuille.itemID) < feuille.qte then manque = manque + 1 end
	end
	f.bilan:SetText(manque == 0 and ("|cff5fd068" .. L.ARBRE_TOUT_EN_STOCK .. "|r")
		or string.format(L.ARBRE_MANQUE, manque, #arbre.feuilles))
	local cout = ns.Prix.cout(ns.db.global.prix, besoins, time())
	if cout.total == 0 and cout.inconnus > 0 then
		f.cout:SetText("|cffa89c86" .. L.PRIX_AUCUN .. "|r")
	else
		local texte = string.format(L.ARBRE_COUT, ns.Marche.Argent(cout.total))
		if cout.inconnus > 0 then texte = texte .. " |cffa89c86(" .. string.format(L.PRIX_SANS, cout.inconnus) .. ")|r" end
		f.cout:SetText(texte)
	end
end
