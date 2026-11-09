-- Dialogue « Nouvelle commande » : quantité, crafteur, qui fournit les composants, note.
-- Une commande part toujours d'une recette du navigateur.
local _, ns = ...
local L = ns.L
local Compagnons = ns.addon

local Dialogue = Compagnons:NewModule("Dialogue", "AceEvent-3.0")
ns.Dialogue = Dialogue

local ICONE_INCONNUE = 134400
local MAX_COMPOSANTS = 6
local QTE_MAX = 999

local function securise(etape, fn, ...)
	local ok, resultat = pcall(fn, ...)
	if not ok then
		ns.log("erreur", "ui", "%s : %s", etape, tostring(resultat))
		return nil
	end
	return resultat
end

local function couleurQualite(q)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

local function iconeObjet(id)
	if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
	if GetItemIcon then return GetItemIcon(id) end
end

--- Quantité possédée sur tous mes personnages (le personnage connecté est lu en direct).
local function stock(id)
	if ns.Stocks then return ns.Stocks:Total(id) end
	if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id, true) or 0 end
	if GetItemCount then return GetItemCount(id, true) or 0 end
	return 0
end

function Dialogue:Ouvrir(spellID)
	if not self.cadre then
		if not securise("création du dialogue", self.Creer, self) then return end
	end
	self.spellID = spellID
	self.qte = 1
	self.crafteur = nil
	self.mats = "partie"
	self.cadre.note:SetText("")
	self:Actualiser()
	self.cadre:Show()
end

function Dialogue:Fermer()
	if self.cadre then self.cadre:Hide() end
end

function Dialogue:Creer()
	local f = CreateFrame("Frame", "CompagnonsOrderDialog", UIParent, "ButtonFrameTemplate")
	self.cadre = f
	f:SetSize(480, 560)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	tinsert(UISpecialFrames, "CompagnonsOrderDialog")

	securise("titre", function()
		if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(f) end
		if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(f) end
		if f.SetTitle then f:SetTitle(L.DIALOGUE_TITRE) elseif f.TitleText then f.TitleText:SetText(L.DIALOGUE_TITRE) end
	end)

	-- Ancré à droite de la fenêtre principale quand elle est ouverte, sinon au centre.
	local principale = _G.CompagnonsFrame
	if principale and principale:IsShown() then
		f:SetPoint("TOPLEFT", principale, "TOPRIGHT", 8, 0)
	else
		f:SetPoint("CENTER")
	end

	-- Recette
	f.entete = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
	f.entete:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -34)
	f.entete:SetPoint("RIGHT", f, "RIGHT", -12, 0)
	f.entete:SetHeight(56)
	f.icone = f.entete:CreateTexture(nil, "ARTWORK")
	f.icone:SetSize(36, 36)
	f.icone:SetPoint("LEFT", 10, 0)
	f.nom = f.entete:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.nom:SetPoint("TOPLEFT", f.icone, "TOPRIGHT", 10, -2)
	f.nom:SetPoint("RIGHT", f.entete, "RIGHT", -10, 0)
	f.nom:SetJustifyH("LEFT")
	f.sous = f.entete:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.sous:SetPoint("TOPLEFT", f.nom, "BOTTOMLEFT", 0, -3)

	-- Quantité
	local etiquetteQte = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	etiquetteQte:SetPoint("TOPLEFT", f.entete, "BOTTOMLEFT", 4, -14)
	etiquetteQte:SetText(L.QUANTITE)

	f.moins = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.moins:SetSize(26, 24)
	f.moins:SetPoint("TOPLEFT", etiquetteQte, "BOTTOMLEFT", 0, -4)
	f.moins:SetText("-")
	f.moins:SetScript("OnClick", function() self:ChangerQuantite(self.qte - 1) end)

	f.champQte = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	f.champQte:SetSize(46, 24)
	f.champQte:SetPoint("LEFT", f.moins, "RIGHT", 8, 0)
	f.champQte:SetAutoFocus(false)
	f.champQte:SetNumeric(true)
	f.champQte:SetMaxLetters(3)
	f.champQte:SetJustifyH("CENTER")
	f.champQte:SetScript("OnTextChanged", function(champ, utilisateur)
		if utilisateur then
			local n = tonumber(champ:GetText())
			if n then self:ChangerQuantite(n, true) end
		end
	end)
	f.champQte:SetScript("OnEnterPressed", function(champ) champ:ClearFocus() end)

	f.plus = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.plus:SetSize(26, 24)
	f.plus:SetPoint("LEFT", f.champQte, "RIGHT", 8, 0)
	f.plus:SetText("+")
	f.plus:SetScript("OnClick", function() self:ChangerQuantite(self.qte + 1) end)

	-- Crafteur
	local etiquetteCrafteur = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	etiquetteCrafteur:SetPoint("TOPLEFT", f.entete, "BOTTOMLEFT", 200, -14)
	etiquetteCrafteur:SetText(L.CRAFTEUR)

	f.menuCrafteur = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
	f.menuCrafteur:SetSize(230, 24)
	f.menuCrafteur:SetPoint("TOPLEFT", etiquetteCrafteur, "BOTTOMLEFT", 0, -4)
	if f.menuCrafteur.SetupMenu then
		f.menuCrafteur:SetupMenu(function(_, racine)
			racine:CreateRadio(L.OUVERT_A_TOUS,
				function() return self.crafteur == nil end,
				function() self.crafteur = nil; self:Actualiser() end)
			if self.spellID then
				for _, c in ipairs(ns.catalogue:Crafteurs(self.spellID)) do
					local cle = c.cle
					local etat = ns.estEnLigne(cle) and (" · " .. L.EN_LIGNE) or ""
					racine:CreateRadio(c.nom .. etat,
						function() return self.crafteur == cle end,
						function() self.crafteur = cle; self:Actualiser() end)
				end
			end
		end)
	end

	-- Qui fournit les composants
	local etiquetteMats = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	etiquetteMats:SetPoint("TOPLEFT", f.moins, "BOTTOMLEFT", 0, -18)
	etiquetteMats:SetText(L.COMPOSANTS_QUI)

	f.radios = {}
	local choix = {
		{ "tout", L.MATS_JE_FOURNIS }, { "partie", L.MATS_EN_PARTIE }, { "crafteur", L.MATS_LE_CRAFTEUR },
	}
	for i, c in ipairs(choix) do
		local radio = CreateFrame("CheckButton", nil, f, "UIRadioButtonTemplate")
		radio:SetPoint("TOPLEFT", etiquetteMats, "BOTTOMLEFT", (i - 1) * 140, -4)
		radio.texte = radio:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		radio.texte:SetPoint("LEFT", radio, "RIGHT", 2, 0)
		radio.texte:SetText(c[2])
		radio:SetScript("OnClick", function()
			self.mats = c[1]
			self:Actualiser()
		end)
		f.radios[c[1]] = radio
	end

	-- Liste des composants
	f.liste = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
	f.liste:SetPoint("TOPLEFT", etiquetteMats, "BOTTOMLEFT", 0, -34)
	f.liste:SetPoint("RIGHT", f, "RIGHT", -12, 0)
	f.liste:SetHeight(MAX_COMPOSANTS * 24 + 12)
	f.lignes = {}
	for i = 1, MAX_COMPOSANTS do
		local ligne = CreateFrame("Frame", nil, f.liste)
		ligne:SetHeight(22)
		ligne:SetPoint("TOPLEFT", f.liste, "TOPLEFT", 8, -6 - (i - 1) * 24)
		ligne:SetPoint("RIGHT", f.liste, "RIGHT", -8, 0)
		ligne.icone = ligne:CreateTexture(nil, "ARTWORK")
		ligne.icone:SetSize(20, 20)
		ligne.icone:SetPoint("LEFT")
		ligne.nom = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		ligne.nom:SetPoint("LEFT", ligne.icone, "RIGHT", 6, 0)
		ligne.nom:SetJustifyH("LEFT")
		ligne.statut = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		ligne.statut:SetPoint("RIGHT")
		ligne.statut:SetJustifyH("RIGHT")
		ligne.nom:SetPoint("RIGHT", ligne.statut, "LEFT", -8, 0)
		ligne:EnableMouse(true)
		ligne:SetScript("OnEnter", function(l)
			securise("infobulle du composant", ns.infobulleObjet, l, l.itemID, l.nomObjet, l.qualiteObjet, "ANCHOR_LEFT")
		end)
		ligne:SetScript("OnLeave", function()
			if GameTooltip then GameTooltip:Hide() end
		end)
		ligne:Hide()
		f.lignes[i] = ligne
	end

	-- Note
	local etiquetteNote = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	etiquetteNote:SetPoint("TOPLEFT", f.liste, "BOTTOMLEFT", 4, -14)
	etiquetteNote:SetText(L.NOTE_CRAFTEUR)
	f.note = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	f.note:SetPoint("TOPLEFT", etiquetteNote, "BOTTOMLEFT", 4, -4)
	f.note:SetPoint("RIGHT", f, "RIGHT", -22, 0)
	f.note:SetHeight(24)
	f.note:SetAutoFocus(false)
	f.note:SetMaxLetters(120)
	f.note:SetScript("OnEnterPressed", function(champ) champ:ClearFocus() end)
	f.note:SetScript("OnEscapePressed", function(champ) champ:ClearFocus() end)
	f.exemple = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.exemple:SetPoint("TOPLEFT", f.note, "BOTTOMLEFT", -4, -2)
	f.exemple:SetText(L.NOTE_EXEMPLE)

	-- Pied
	f.visible = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.visible:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 18)

	f.publier = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.publier:SetSize(150, 26)
	f.publier:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)
	f.publier:SetText(L.PUBLIER)
	f.publier:SetScript("OnClick", function() self:Publier() end)

	f.annuler = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.annuler:SetSize(90, 26)
	f.annuler:SetPoint("RIGHT", f.publier, "LEFT", -6, 0)
	f.annuler:SetText(L.ANNULER)
	f.annuler:SetScript("OnClick", function() f:Hide() end)

	return true
end

function Dialogue:ChangerQuantite(n, depuisSaisie)
	self.qte = math.max(1, math.min(QTE_MAX, math.floor(n)))
	if not depuisSaisie then self.cadre.champQte:SetText(tostring(self.qte)) end
	self:ActualiserComposants()
end

function Dialogue:Actualiser()
	local f = self.cadre
	local recette = self.spellID and ns.Recettes.recettes[self.spellID]
	if not recette then return end

	local icone
	if recette.objet and recette.objet > 0 then icone = iconeObjet(recette.objet) end
	f.icone:SetTexture(icone or ICONE_INCONNUE)
	f.nom:SetText(recette.nom)
	f.nom:SetTextColor(couleurQualite(recette.qualite))
	local metier = ns.Recettes.metiers[recette.metier]
	local crafteurs = ns.catalogue:Crafteurs(self.spellID)
	f.sous:SetText(string.format("%s · %d · %s", metier and metier.nom or "?", recette.niveau,
		string.format(L.CRAFTEURS, #crafteurs)))

	f.champQte:SetText(tostring(self.qte))
	if f.menuCrafteur.GenerateMenu then f.menuCrafteur:GenerateMenu() end
	for cle, radio in pairs(f.radios) do radio:SetChecked(cle == self.mats) end
	self:ActualiserComposants()

	f.visible:SetText(#crafteurs > 0 and string.format(L.VISIBLE_PAR, #crafteurs) or L.VISIBLE_PERSONNE)
end

--- Composants nécessaires pour la quantité demandée, avec ce que l'on possède.
function Dialogue:ActualiserComposants()
	local f = self.cadre
	local composants = self.spellID and ns.catalogue:Composants(self.spellID) or {}
	for i = 1, MAX_COMPOSANTS do
		local ligne, comp = f.lignes[i], composants[i]
		if comp then
			local besoin = comp.qte * self.qte
			local possede = stock(comp.itemID)
			local nom = comp.nom ~= "" and comp.nom or ("#" .. comp.itemID)
			ligne.itemID, ligne.nomObjet, ligne.qualiteObjet = comp.itemID, nom, comp.qualite
			ligne.icone:SetTexture(iconeObjet(comp.itemID) or ICONE_INCONNUE)
			ligne.nom:SetText(string.format("%d × %s", besoin, nom))
			ligne.nom:SetTextColor(couleurQualite(comp.qualite))
			if self.mats == "crafteur" then
				ligne.statut:SetText("|cffa89c86" .. L.STOCK_CRAFTEUR .. "|r")
			elseif possede >= besoin then
				ligne.statut:SetText(string.format("|cff5fd068%d · %s|r", possede, L.STOCK_JE_FOURNIS))
			else
				ligne.statut:SetText(string.format("|cffe8a94f%d · %s|r", possede, string.format(L.STOCK_MANQUE, besoin - possede)))
			end
			ligne:Show()
		else
			ligne:Hide()
		end
	end
end

function Dialogue:Publier()
	local recette = self.spellID and ns.Recettes.recettes[self.spellID]
	if not recette then return end
	local commande, erreur = ns.Atelier:Creer({
		spell = self.spellID,
		qte = self.qte,
		crafteur = self.crafteur,
		mats = self.mats,
		note = self.cadre.note:GetText(),
	})
	if not commande then
		Compagnons:Print(erreur or L.ACTION_IMPOSSIBLE)
		return
	end
	Compagnons:Print(string.format(L.COMMANDE_PUBLIEE, commande.qte, recette.nom))
	self.cadre:Hide()
end
