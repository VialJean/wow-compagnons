-- Onglet « Annonces » : les offres (« je fabrique ça ») et les demandes (« je cherche ça ») permanentes de la guilde.
-- Complète le module Fenetre. Une offre mène au dialogue de commande prérempli ; une demande ouvre un chuchotement déjà écrit
-- que le joueur envoie lui-même (rien ne part tout seul). Le modèle est dans Core/Annonces.lua.
local _, ns = ...
local L = ns.L

local Fenetre = ns.Fenetre

local HAUTEUR_LIGNE = 44
local ICONE_INCONNUE = 134400
local ICONE_TEXTE = "Interface\\Icons\\INV_Misc_Note_01"

local function couleurQualite(q)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

local function couleurClasse(classe)
	local c = classe and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classe]
	if c then return c.r, c.g, c.b end
	return 0.8, 0.8, 0.8
end

--- Nom, icône et qualité de la cible d'une annonce (recette ou objet). Une annonce de texte seul n'a pas de cible : son message
-- sert de titre.
local function cible(a)
	if not a.spell and not a.item then
		return a.note, ICONE_TEXTE, 1
	end
	if a.spell then
		local r = ns.Recettes.recettes[a.spell]
		local icone = r and r.objet and r.objet > 0 and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(r.objet)
		return r and r.nom or "?", icone or ICONE_INCONNUE, r and r.qualite or 1
	end
	local o = ns.Recettes.objets and ns.Recettes.objets[a.item]
	local nom = o and o[1] or ""
	if nom == "" and C_Item and C_Item.GetItemNameByID then nom = C_Item.GetItemNameByID(a.item) or "" end
	if nom == "" then nom = "#" .. a.item end
	return nom, (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(a.item)) or ICONE_INCONNUE, o and o[2] or 1
end

function Fenetre:CreerAnnonces(f)
	local vue = CreateFrame("Frame", nil, f)
	vue:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -34)
	vue:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 30)
	vue:Hide()
	self.vueAnnonces = vue
	self.annoncesGenre, self.annoncesMetier = "offre", nil

	-- Offres / Demandes
	vue.boutonsGenre = {}
	for i, genre in ipairs({ "offre", "demande" }) do
		local b = CreateFrame("Button", nil, vue, "UIPanelButtonTemplate")
		b:SetSize(110, 24)
		b:SetPoint("TOPLEFT", vue, "TOPLEFT", (i - 1) * 114, -2)
		b:SetText(genre == "offre" and L.ANNONCES_OFFRES or L.ANNONCES_DEMANDES)
		b:SetScript("OnClick", function()
			self.annoncesGenre = genre
			self:RafraichirAnnonces()
		end)
		vue.boutonsGenre[genre] = b
	end

	-- Publier : la recette sélectionnée dans l'onglet Recettes (ou le composant filtré, pour une demande).
	vue.publier = CreateFrame("Button", nil, vue, "UIPanelButtonTemplate")
	vue.publier:SetSize(240, 24)
	vue.publier:SetPoint("LEFT", vue.boutonsGenre.demande, "RIGHT", 14, 0)
	vue.publier:SetScript("OnClick", function() self:PublierAnnonce() end)
	vue.publier:SetScript("OnEnter", function(b)
		if GameTooltip then
			GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
			GameTooltip:SetText(L.ANNONCES_PUBLIER_AIDE, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	vue.publier:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

	-- Texte libre : une annonce sans recette ni objet liés, un message seul.
	vue.texte = CreateFrame("Button", nil, vue, "UIPanelButtonTemplate")
	vue.texte:SetSize(120, 24)
	vue.texte:SetPoint("LEFT", vue.publier, "RIGHT", 6, 0)
	vue.texte:SetText(L.ANNONCES_TEXTE_BOUTON)
	vue.texte:SetScript("OnClick", function() self:PublierTexteLibre() end)
	vue.texte:SetScript("OnEnter", function(b)
		if GameTooltip then
			GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
			GameTooltip:SetText(L.ANNONCES_TEXTE_AIDE, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	vue.texte:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

	local menu = CreateFrame("DropdownButton", nil, vue, "WowStyle1DropdownTemplate")
	menu:SetSize(200, 24)
	menu:SetPoint("TOPRIGHT", vue, "TOPRIGHT", -6, -2)
	if menu.SetupMenu then
		menu:SetupMenu(function(_, racine)
			racine:CreateRadio(L.TOUS_METIERS,
				function() return self.annoncesMetier == nil end,
				function() self.annoncesMetier = nil; self:RafraichirAnnonces() end)
			for _, m in ipairs(ns.catalogue and ns.catalogue:Metiers() or {}) do
				local id = m.id
				racine:CreateRadio(m.nom,
					function() return self.annoncesMetier == id end,
					function() self.annoncesMetier = id; self:RafraichirAnnonces() end)
			end
		end)
	end

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
		ligne.survol = ligne:CreateTexture(nil, "HIGHLIGHT")
		ligne.survol:SetAllPoints()
		ligne.survol:SetColorTexture(1, 1, 1, 0.07)
		ligne.icone = ligne:CreateTexture(nil, "ARTWORK")
		ligne.icone:SetSize(32, 32)
		ligne.icone:SetPoint("LEFT", 8, 0)
		ligne.titre = ligne:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		ligne.titre:SetPoint("TOPLEFT", ligne.icone, "TOPRIGHT", 8, 0)
		ligne.titre:SetPoint("RIGHT", ligne, "RIGHT", -120, 0)
		ligne.titre:SetJustifyH("LEFT")
		ligne.auteur = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		ligne.auteur:SetPoint("TOPLEFT", ligne.titre, "BOTTOMLEFT", 0, -2)
		ligne.auteur:SetPoint("RIGHT", ligne, "RIGHT", -120, 0)
		ligne.auteur:SetJustifyH("LEFT")
		ligne.note = ligne:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		ligne.note:SetPoint("TOPLEFT", ligne.auteur, "BOTTOMLEFT", 0, -1)
		ligne.note:SetPoint("RIGHT", ligne, "RIGHT", -120, 0)
		ligne.note:SetJustifyH("LEFT")
		ligne.action = CreateFrame("Button", nil, ligne, "UIPanelButtonTemplate")
		ligne.action:SetSize(104, 24)
		ligne.action:SetPoint("RIGHT", -8, 0)
		ligne.action:SetScript("OnClick", function(b) Fenetre:AgirSurAnnonce(b:GetParent().annonce) end)
		ligne:SetScript("OnEnter", function(l)
			if l.annonce and l.annonce.spell and ns.infobulleRecette then
				local ok, erreur = pcall(ns.infobulleRecette, l, l.annonce.spell)
				if not ok then ns.log("erreur", "ui", "infobulle de l'annonce : %s", tostring(erreur)) end
			end
		end)
		ligne:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	end
	ligne.annonce = a
	local nom, icone, qualite = cible(a)
	ligne.icone:SetTexture(icone)
	ligne.titre:SetText(nom)
	ligne.titre:SetTextColor(couleurQualite(qualite))

	local perso = ns.db.global.personnages[a.auteur]
	local r, g, b = couleurClasse(perso and perso.classe)
	local enLigne = ns.estEnLigne and ns.estEnLigne(a.auteur)
	local mats = a.mats == "tout" and L.ANNONCE_MATS_TOUT or a.mats == "crafteur" and L.ANNONCE_MATS_CRAFTEUR or L.ANNONCE_MATS_PARTIE
	ligne.auteur:SetText(string.format("|cff%02x%02x%02x%s|r |cffa89c86· %s · %s|r", r * 255, g * 255, b * 255, a.auteur,
		enLigne and L.EN_LIGNE or L.HORS_LIGNE, mats))
	local seul = not a.spell and not a.item
	ligne.note:SetText((a.note ~= "" and not seul) and ('"' .. a.note .. '"') or "")

	if ns.AnnoncesModule:EstMienne(a) then
		ligne.action:SetText(L.ANNONCE_RETIRER)
	elseif seul then
		ligne.action:SetText(L.ANNONCE_CONTACTER)
	elseif a.genre == "offre" then
		ligne.action:SetText(L.COMMANDER)
	else
		ligne.action:SetText(L.ANNONCE_ME_PROPOSER)
	end
end

function Fenetre:AgirSurAnnonce(a)
	if not a then return end
	if ns.AnnoncesModule:EstMienne(a) then
		ns.AnnoncesModule:Retirer(a)
		self:RafraichirAnnonces(true)
	elseif not a.spell and not a.item then
		-- Texte seul : un chuchotement vide, le joueur écrit lui-même.
		local texte = string.format("/w %s ", a.auteur)
		if ChatFrame_OpenChat then ChatFrame_OpenChat(texte) else ns.addon:Print(texte) end
	elseif a.genre == "offre" then
		-- Dialogue de commande prérempli : crafteur = l'auteur, conditions de l'annonce.
		ns.Dialogue:Ouvrir(a.spell, { crafteur = a.auteur, mats = a.mats })
	else
		-- Chuchotement déjà écrit : le joueur appuie lui-même sur Entrée, rien ne part tout seul.
		local nom = cible(a)
		local texte = string.format("/w %s %s", a.auteur, string.format(L.ANNONCE_PROPOSITION, nom))
		if ChatFrame_OpenChat then ChatFrame_OpenChat(texte) else ns.addon:Print(texte) end
	end
end

--- Publie une annonce sur la recette sélectionnée dans l'onglet Recettes ; une demande peut viser le composant filtré.
function Fenetre:PublierAnnonce()
	local genre = self.annoncesGenre
	local options = { genre = genre, mats = "partie" }
	if genre == "demande" and self.composant then
		options.item = self.composant
	elseif self.selection then
		options.spell = self.selection
	else
		ns.addon:Print(L.ANNONCES_CHOISIR)
		return
	end
	local a, erreur = ns.AnnoncesModule:Publier(options)
	if not a then
		ns.addon:Print(erreur or L.ACTION_IMPOSSIBLE)
		return
	end
	self:RafraichirAnnonces(true)
end

--- Publie une annonce de texte seul (offre ou demande selon l'onglet) : une fenêtre demande le message.
function Fenetre:PublierTexteLibre()
	if not StaticPopupDialogs["COMPAGNONS_ANNONCE_TEXTE"] then
		StaticPopupDialogs["COMPAGNONS_ANNONCE_TEXTE"] = {
			text = "%s",
			button1 = ACCEPT,
			button2 = CANCEL,
			hasEditBox = true,
			maxLetters = 100,
			OnAccept = function(dialogue, genre)
				local champ = dialogue.EditBox or dialogue.editBox
				local note = champ and champ:GetText() or ""
				if not note:find("%S") then
					ns.addon:Print(L.ANNONCES_TEXTE_VIDE)
					return
				end
				local a, erreur = ns.AnnoncesModule:Publier({ genre = genre, mats = "partie", note = note })
				if not a then
					ns.addon:Print(erreur or L.ACTION_IMPOSSIBLE)
					return
				end
				if Fenetre.RafraichirAnnonces then Fenetre:RafraichirAnnonces(true) end
			end,
			EditBoxOnEnterPressed = function(champ)
				local dialogue = champ:GetParent()
				if dialogue.GetButton then
					local b = dialogue:GetButton(1)
					if b then b:Click() return end
				end
				if dialogue.button1 then dialogue.button1:Click() end
			end,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3,
		}
	end
	local genre = self.annoncesGenre
	StaticPopup_Show("COMPAGNONS_ANNONCE_TEXTE", genre == "offre" and L.ANNONCES_TEXTE_TITRE_OFFRE or L.ANNONCES_TEXTE_TITRE_DEMANDE,
		nil, genre)
end

function Fenetre:RafraichirAnnonces(garder)
	local vue = self.vueAnnonces
	if not vue or not self.cadre or not self.cadre:IsShown() or self.onglet ~= 5 then return end
	local genre = self.annoncesGenre
	for g, b in pairs(vue.boutonsGenre) do b:SetEnabled(g ~= genre) end
	vue.publier:SetText(genre == "offre" and L.ANNONCES_PUBLIER_OFFRE or L.ANNONCES_PUBLIER_DEMANDE)
	local liste = ns.Annonces.liste(ns.AnnoncesModule:Toutes(), {
		genre = genre, metier = self.annoncesMetier, estEnLigne = ns.estEnLigne, donnees = ns.Recettes,
	}, time())
	vue.vide:SetShown(#liste == 0)
	local fournisseur = CreateDataProvider(liste)
	if garder and ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition then
		vue.liste:SetDataProvider(fournisseur, ScrollBoxConstants.RetainScrollPosition)
	else
		vue.liste:SetDataProvider(fournisseur)
	end
end
