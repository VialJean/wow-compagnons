-- Onglet « Commandes » de la fenêtre principale : trois vues (Ouvertes, Pour moi, Mes commandes),
-- filtre par métier, actions directement sur chaque ligne. Complète le module Fenetre.
local _, ns = ...
local L = ns.L
local Compagnons = ns.addon

local Fenetre = ns.Fenetre

local HAUTEUR_LIGNE = 46
local MAX_BOUTONS = 3
local ICONE_INCONNUE = 134400

local VUES = {
	{ id = "ouvertes", libelle = L.VUE_OUVERTES, aide = L.AIDE_VUE_OUVERTES },
	{ id = "pourmoi", libelle = L.VUE_POUR_MOI, aide = L.AIDE_VUE_POUR_MOI },
	{ id = "mes", libelle = L.VUE_MES_COMMANDES, aide = L.AIDE_VUE_MES_COMMANDES },
}

local function couleurQualite(q)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

local function iconeRecette(recette, spellID)
	local icone
	if recette.objet and recette.objet > 0 then
		if C_Item and C_Item.GetItemIconByID then icone = C_Item.GetItemIconByID(recette.objet) end
		if not icone and GetItemIcon then icone = GetItemIcon(recette.objet) end
	end
	if not icone then
		if C_Spell and C_Spell.GetSpellTexture then icone = C_Spell.GetSpellTexture(spellID) end
		if not icone and GetSpellTexture then icone = GetSpellTexture(spellID) end
	end
	return icone or ICONE_INCONNUE
end

function Fenetre:CreerCommandes(f)
	local vue = CreateFrame("Frame", nil, f)
	vue:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -34)
	vue:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 30)
	vue:Hide()
	self.vueCommandes = vue
	self.vueCmd = nil
	self.metierCmd = nil

	-- Sous-onglets
	vue.boutonsVue = {}
	for i, v in ipairs(VUES) do
		local b = CreateFrame("Button", nil, vue, "UIPanelButtonTemplate")
		b:SetSize(130, 24)
		if i == 1 then
			b:SetPoint("TOPLEFT", vue, "TOPLEFT", 70, -2)
		else
			b:SetPoint("LEFT", vue.boutonsVue[i - 1], "RIGHT", 4, 0)
		end
		b:SetScript("OnClick", function()
			self.vueCmd = v.id
			self:RafraichirCommandes()
		end)
		vue.boutonsVue[i] = b
	end

	-- Filtre par métier
	local menu = CreateFrame("DropdownButton", nil, vue, "WowStyle1DropdownTemplate")
	menu:SetSize(200, 24)
	menu:SetPoint("TOPRIGHT", vue, "TOPRIGHT", -6, -2)
	if menu.SetupMenu then
		menu:SetupMenu(function(_, racine)
			racine:CreateRadio(L.TOUS_METIERS,
				function() return self.metierCmd == nil end,
				function() self.metierCmd = nil; self:RafraichirCommandes() end)
			for _, m in ipairs(ns.catalogue:Metiers()) do
				local id = m.id
				racine:CreateRadio(m.nom,
					function() return self.metierCmd == id end,
					function() self.metierCmd = id; self:RafraichirCommandes() end)
			end
		end)
	end
	vue.menuMetier = menu

	vue.aide = vue:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	vue.aide:SetPoint("TOPLEFT", vue, "TOPLEFT", 74, -34)

	-- Liste
	local cadre = CreateFrame("Frame", nil, vue, "InsetFrameTemplate")
	cadre:SetPoint("TOPLEFT", vue, "TOPLEFT", 0, -54)
	cadre:SetPoint("BOTTOMRIGHT", vue, "BOTTOMRIGHT", 0, 32)

	local boite = CreateFrame("Frame", nil, cadre, "WowScrollBoxList")
	local barre = CreateFrame("EventFrame", nil, cadre, "MinimalScrollBar")
	local elements = CreateScrollBoxListLinearView()
	elements:SetElementExtent(HAUTEUR_LIGNE)
	elements:SetElementInitializer("Button", function(ligne, commande) self:InitialiserLigneCommande(ligne, commande) end)
	ScrollUtil.InitScrollBoxListWithScrollBar(boite, barre, elements)
	boite:SetPoint("TOPLEFT", cadre, "TOPLEFT", 4, -4)
	boite:SetPoint("BOTTOMRIGHT", cadre, "BOTTOMRIGHT", -22, 4)
	barre:SetPoint("TOPLEFT", boite, "TOPRIGHT", 4, 0)
	barre:SetPoint("BOTTOMLEFT", boite, "BOTTOMRIGHT", 4, 0)
	vue.liste = boite

	vue.vide = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	vue.vide:SetPoint("CENTER")
	vue.vide:SetText(L.AUCUNE_COMMANDE)
	vue.vide:Hide()

	-- Pied
	vue.synchro = vue:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	vue.synchro:SetPoint("BOTTOMLEFT", vue, "BOTTOMLEFT", 4, 8)

	local nouvelle = CreateFrame("Button", nil, vue, "UIPanelButtonTemplate")
	nouvelle:SetSize(170, 24)
	nouvelle:SetPoint("BOTTOMRIGHT", vue, "BOTTOMRIGHT", -4, 4)
	nouvelle:SetText(L.NOUVELLE_COMMANDE)
	-- Une commande part toujours d'une recette : on renvoie vers le navigateur.
	nouvelle:SetScript("OnClick", function()
		self:ChoisirOnglet(1)
		if self.recherche then self.recherche:SetFocus() end
	end)

	local courses = CreateFrame("Button", nil, vue, "UIPanelButtonTemplate")
	courses:SetSize(150, 24)
	courses:SetPoint("RIGHT", nouvelle, "LEFT", -6, 0)
	courses:SetText(L.COURSES_BOUTON)
	courses:SetScript("OnClick", function() ns.Courses:Basculer() end)
end

--- Construit (une seule fois) les éléments d'une ligne, puis les remplit.
function Fenetre:InitialiserLigneCommande(ligne, commande)
	if not ligne.initialise then
		ligne.initialise = true
		ligne.icone = ligne:CreateTexture(nil, "ARTWORK")
		ligne.icone:SetSize(32, 32)
		ligne.icone:SetPoint("LEFT", 8, 0)

		ligne.fond = ligne:CreateTexture(nil, "BACKGROUND")
		ligne.fond:SetAllPoints()
		ligne.fond:SetColorTexture(1, 1, 1, 0.03)
		ligne.survol = ligne:CreateTexture(nil, "HIGHLIGHT")
		ligne.survol:SetAllPoints()
		ligne.survol:SetColorTexture(1, 1, 1, 0.07)

		ligne.titre = ligne:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		ligne.titre:SetPoint("TOPLEFT", ligne.icone, "TOPRIGHT", 8, -1)
		ligne.titre:SetPoint("RIGHT", ligne, "RIGHT", -400, 0)
		ligne.titre:SetJustifyH("LEFT")
		ligne.meta = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		ligne.meta:SetPoint("BOTTOMLEFT", ligne.icone, "BOTTOMRIGHT", 8, 0)
		ligne.meta:SetPoint("RIGHT", ligne, "RIGHT", -400, 0)
		ligne.meta:SetJustifyH("LEFT")

		ligne.mats = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		ligne.mats:SetPoint("RIGHT", ligne, "RIGHT", -310, 0)
		ligne.mats:SetWidth(100)
		ligne.mats:SetJustifyH("RIGHT")
		ligne.statut = ligne:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		ligne.statut:SetPoint("RIGHT", ligne, "RIGHT", -214, 0)
		ligne.statut:SetWidth(90)
		ligne.statut:SetJustifyH("CENTER")

		ligne.boutons = {}
		for i = 1, MAX_BOUTONS do
			local b = CreateFrame("Button", nil, ligne, "UIPanelButtonTemplate")
			b:SetSize(68, 22)
			b:SetPoint("RIGHT", ligne, "RIGHT", -6 - (i - 1) * 70, 0)
			b:SetScript("OnClick", function(bouton)
				if not bouton.action then return end
				local _, erreur = ns.Atelier:Agir(ligne.commande, bouton.action)
				if erreur then Compagnons:Print(erreur) end
			end)
			b:SetScript("OnEnter", function(bouton)
				if bouton.raison and GameTooltip then
					GameTooltip:SetOwner(bouton, "ANCHOR_TOP")
					GameTooltip:SetText(bouton.raison, 1, 0.82, 0, 1, true)
					GameTooltip:Show()
				end
			end)
			b:SetScript("OnLeave", function()
				if GameTooltip then GameTooltip:Hide() end
			end)
			b:Hide()
			ligne.boutons[i] = b
		end

		ligne:SetScript("OnEnter", function(l) Fenetre:InfobulleCommande(l) end)
		ligne:SetScript("OnLeave", function()
			if GameTooltip then GameTooltip:Hide() end
		end)
	end

	ligne.commande = commande
	local recette = ns.Recettes.recettes[commande.spell]
	ligne.icone:SetTexture(recette and iconeRecette(recette, commande.spell) or ICONE_INCONNUE)
	ligne.titre:SetText(string.format("%d × %s", commande.qte, recette and recette.nom or "?"))
	ligne.titre:SetTextColor(couleurQualite(recette and recette.qualite))

	local metier = recette and ns.Recettes.metiers[recette.metier]
	local miens = ns.Atelier:Miens()
	local qui = miens[commande.client] and L.PAR_CLIENT or commande.client
	local meta = string.format("%s %d · %s · %s", metier and metier.nom or "?", recette and recette.niveau or 0,
		qui, ns.Atelier.Age(commande.cree))
	local progres = ns.Progres.libelle(commande, L.PROGRES_CRAFTES)
	if progres then meta = meta .. " · |cff5fd068" .. progres .. "|r" end
	ligne.meta:SetText(meta)
	ligne.mats:SetText(ns.Atelier.LibelleMats(commande))
	local libelle, couleur = ns.Atelier.LibelleStatut(commande)
	ligne.statut:SetText("|c" .. couleur .. libelle .. "|r")

	-- Boutons : le premier est l'action principale, tout à droite.
	local actions = ns.Atelier:ActionsPossibles(commande)
	table.sort(actions, function(a, b) return a.principale and not b.principale end)
	for i = 1, MAX_BOUTONS do
		local b, a = ligne.boutons[i], actions[i]
		if a then
			b.action, b.raison = a.action, a.raison
			b:SetText(a.libelle)
			b:SetEnabled(a.raison == nil)
			b:Show()
		else
			b.action, b.raison = nil, nil
			b:Hide()
		end
	end
end

function Fenetre:InfobulleCommande(ligne)
	local o = ligne.commande
	if not o or not GameTooltip then return end
	local recette = ns.Recettes.recettes[o.spell]
	if recette then
		-- Infobulle Blizzard de l'objet (ou du sort), puis les crafteurs de la guilde.
		ns.infobulleRecette(ligne, o.spell)
	else
		GameTooltip:SetOwner(ligne, "ANCHOR_RIGHT")
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(string.format("%d × %s", o.qte, recette and recette.nom or "?"), 1, 1, 1)
	GameTooltip:AddLine(string.format(L.POUR_CLIENT, o.client), 0.9, 0.8, 0.5)
	if o.note and o.note ~= "" then GameTooltip:AddLine(string.format(L.CRAFTEUR_NOTE, o.note), 1, 1, 1, true) end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L.HISTORIQUE, 0.66, 0.61, 0.53)
	for _, h in ipairs(o.histo or {}) do
		local libelle = ns.Atelier.LibelleStatut({ statut = h[3], assigne = h[2] })
		GameTooltip:AddLine(string.format("%s · %s · %s", ns.Atelier.Age(h[1]), h[2], libelle), 0.8, 0.8, 0.8)
	end
	GameTooltip:Show()
end

function Fenetre:RafraichirCommandes()
	local vue = self.vueCommandes
	if not vue or not self.cadre or not self.cadre:IsShown() or self.onglet ~= 2 then return end
	if not ns.Atelier or not ns.catalogue then return end

	-- Première ouverture : « Pour moi » s'il y a quelque chose à faire, sinon « Ouvertes ».
	if not self.vueCmd then
		self.vueCmd = ns.Atelier:CompterPourMoi() > 0 and "pourmoi" or "ouvertes"
	end

	local filtre = self.metierCmd
	local function filtrer(liste)
		if not filtre then return liste end
		local sortie = {}
		for _, o in ipairs(liste) do
			local r = ns.Recettes.recettes[o.spell]
			if r and r.metier == filtre then sortie[#sortie + 1] = o end
		end
		return sortie
	end

	local courant
	for i, v in ipairs(VUES) do
		local liste = filtrer(ns.Atelier:Vue(v.id))
		local b = vue.boutonsVue[i]
		b:SetText(string.format("%s (%d)", v.libelle, #liste))
		if v.id == self.vueCmd then
			b:LockHighlight()
			courant = liste
			vue.aide:SetText(v.aide)
		else
			b:UnlockHighlight()
		end
	end

	vue.liste:SetDataProvider(CreateDataProvider(courant or {}))
	vue.vide:SetShown(#(courant or {}) == 0)
	if vue.menuMetier.GenerateMenu then vue.menuMetier:GenerateMenu() end

	local m = ns.Reseau and ns.Reseau.moteur
	vue.synchro:SetText(m and string.format(L.SYNC_ETAT_COURT, m:CompterCommandes(), m:Compter()) or "")
end
