-- Fenêtre principale « Atelier de guilde » : onglet Recettes (navigateur) et onglet Commandes (à venir).
-- Templates natifs uniquement (voir le plan de montage). ItemButtonTemplate est absent de Forever :
-- les icônes d'objets sont de simples textures.
local _, ns = ...
local L = ns.L
local Compagnons = ns.addon

local Fenetre = Compagnons:NewModule("Fenetre", "AceEvent-3.0")
ns.Fenetre = Fenetre

local LARGEUR, HAUTEUR = 940, 600
local LARGEUR_METIERS, LARGEUR_DETAIL = 190, 290
local ICONE_INCONNUE = 134400 -- INV_Misc_QuestionMark
local MAX_LIGNES = 8

--- Exécute fn ; en cas d'erreur, la journalise au lieu de casser le chargement de l'addon.
local function securise(etape, fn, ...)
	local ok, resultat = pcall(fn, ...)
	if not ok then
		ns.log("erreur", "ui", "%s : %s", etape, tostring(resultat))
		return nil
	end
	return resultat
end

local function octet(x)
	return math.floor((x or 1) * 255 + 0.5)
end

local function hex(r, g, b)
	return string.format("|cff%02x%02x%02x", octet(r), octet(g), octet(b))
end
ns.hex = hex

local function couleurQualite(qualite)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[qualite or 1]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

local function couleurClasse(classe)
	local c = classe and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classe]
	if c then return c.r, c.g, c.b end
	return 0.8, 0.8, 0.8
end

--- Infobulle d'un objet. Essaie SetItemByID, puis un lien d'objet, puis, si le client n'a pas encore
-- l'objet en cache, un simple titre avec le nom de la base de recettes : l'infobulle n'est jamais vide.
function ns.infobulleObjet(proprietaire, itemID, nom, qualite, ancre)
	if not GameTooltip or not itemID then return end
	GameTooltip:SetOwner(proprietaire, ancre or "ANCHOR_RIGHT")
	local ok = false
	if GameTooltip.SetItemByID then ok = pcall(GameTooltip.SetItemByID, GameTooltip, itemID) end
	if not ok or GameTooltip:NumLines() == 0 then
		ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. itemID)
	end
	if not ok or GameTooltip:NumLines() == 0 then
		GameTooltip:ClearLines()
		local r, g, b = couleurQualite(qualite)
		GameTooltip:SetText((nom and nom ~= "") and nom or ("#" .. itemID), r, g, b)
	end
	GameTooltip:Show()
end

--- Infobulle d'une recette : l'objet créé (ou le sort, pour un enchantement) puis les crafteurs de la guilde.
function ns.infobulleRecette(proprietaire, spellID)
	local recette = spellID and ns.Recettes.recettes[spellID]
	if not recette or not GameTooltip then return end
	if recette.objet and recette.objet > 0 then
		ns.infobulleObjet(proprietaire, recette.objet, recette.nom, recette.qualite, "ANCHOR_RIGHT")
	else
		GameTooltip:SetOwner(proprietaire, "ANCHOR_RIGHT")
		local ok = GameTooltip.SetSpellByID and pcall(GameTooltip.SetSpellByID, GameTooltip, spellID)
		if not ok or GameTooltip:NumLines() == 0 then
			GameTooltip:ClearLines()
			GameTooltip:SetText(recette.nom, 1, 0.82, 0)
		end
	end

	local crafteurs = ns.catalogue and ns.catalogue:Crafteurs(spellID) or {}
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Compagnons", 0.88, 0.7, 0.32)
	if #crafteurs == 0 then
		GameTooltip:AddLine(L.PERSONNE_CONNAIT, 0.9, 0.5, 0.42)
	else
		for i = 1, math.min(#crafteurs, 6) do
			local c = crafteurs[i]
			local r, g, b = couleurClasse(c.classe)
			GameTooltip:AddLine(string.format("%s · %s", c.nom, ns.estEnLigne(c.cle) and L.EN_LIGNE or L.HORS_LIGNE), r, g, b)
		end
		if #crafteurs > 6 then GameTooltip:AddLine(string.format(L.ET_AUTRES, #crafteurs - 6), 0.7, 0.7, 0.7) end
	end
	GameTooltip:Show()
end

local function iconeObjet(itemID)
	if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemID) end
	if GetItemIcon then return GetItemIcon(itemID) end
end

local function iconeSort(spellID)
	if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(spellID) end
	if GetSpellTexture then return GetSpellTexture(spellID) end
end

local function iconeRecette(spellID, recette)
	local icone
	if recette and recette.objet and recette.objet > 0 then icone = iconeObjet(recette.objet) end
	return icone or iconeSort(spellID) or ICONE_INCONNUE
end

--- Quantité possédée sur tous mes personnages (le personnage connecté est lu en direct).
local function nombreEnStock(itemID)
	if ns.Stocks then return ns.Stocks:Total(itemID) end
	if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(itemID, true) or 0 end
	if GetItemCount then return GetItemCount(itemID, true) or 0 end
	return 0
end

-- Une liste défilante native (WowScrollBoxList + MinimalScrollBar), éléments de type Button.
local function creerListe(parent, hauteurLigne, initialiser)
	local boite = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
	local barre = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
	local vue = CreateScrollBoxListLinearView()
	vue:SetElementExtent(hauteurLigne)
	vue:SetElementInitializer("Button", initialiser)
	ScrollUtil.InitScrollBoxListWithScrollBar(boite, barre, vue)
	return boite, barre
end

local function remplir(boite, elements, conserver)
	local fournisseur = CreateDataProvider(elements)
	if conserver and ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition then
		boite:SetDataProvider(fournisseur, ScrollBoxConstants.RetainScrollPosition)
	else
		boite:SetDataProvider(fournisseur)
	end
end

local function rafraichirLignes(boite)
	if boite.ForEachFrame then
		boite:ForEachFrame(function(ligne)
			if ligne.Actualiser then ligne:Actualiser() end
		end)
	end
end

local function creerCadre(parent)
	return CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
end

function Fenetre:OnEnable()
	self.filtres = { craftable = false, enLigne = false, inconnue = false }
	self.texte = ""
	self.metier = nil
	self.onglet = 1
	self:RegisterMessage("COMPAGNONS_CATALOGUE_MAJ", "SurMiseAJour")
	self:RegisterMessage("COMPAGNONS_COMMANDES_MAJ", "SurCommandes")
end

function Fenetre:SurMiseAJour()
	if self.cadre and self.cadre:IsShown() then
		self:Rafraichir()
		self:RafraichirMembres()
	end
end

function Fenetre:Basculer()
	if not self.cadre then
		if not securise("création de la fenêtre", self.Creer, self) then return end
	end
	if self.cadre:IsShown() then self.cadre:Hide() else self.cadre:Show() end
end

function Fenetre:Afficher()
	if not self.cadre then
		if not securise("création de la fenêtre", self.Creer, self) then return end
	end
	self.cadre:Show()
end

-- ---------------------------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------------------------

function Fenetre:Creer()
	local f = CreateFrame("Frame", "CompagnonsFrame", UIParent, "ButtonFrameTemplate")
	self.cadre = f
	f:SetSize(LARGEUR, HAUTEUR)
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	tinsert(UISpecialFrames, "CompagnonsFrame")

	securise("titre", function()
		if f.SetTitle then f:SetTitle(L.TITRE) elseif f.TitleText then f.TitleText:SetText(L.TITRE) end
	end)
	securise("portrait", function()
		if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(f) end
		if f.SetPortraitToAsset then f:SetPortraitToAsset("Interface\\Icons\\Trade_BlackSmithing") end
	end)

	securise("recherche", self.CreerRecherche, self, f)
	securise("liste des métiers", self.CreerMetiers, self, f)
	securise("détail", self.CreerDetail, self, f)
	securise("liste des recettes", self.CreerRecettes, self, f)
	securise("tableau des commandes", self.CreerCommandes, self, f)
	securise("liste des membres", self.CreerMembres, self, f)
	securise("onglets", self.CreerOnglets, self, f)
	securise("bandeau de version", function()
		if ns.Avertissement then ns.Avertissement:AttacherBandeau(f) end
	end)

	f.pied = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.pied:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 8)

	f:SetScript("OnShow", function() self:Rafraichir() end)
	return true
end

function Fenetre:CreerRecherche(f)
	local recherche = CreateFrame("EditBox", nil, f, "SearchBoxTemplate")
	recherche:SetSize(420, 20)
	recherche:SetPoint("TOPLEFT", f, "TOPLEFT", 78, -34)
	recherche:SetAutoFocus(false)
	if recherche.Instructions then recherche.Instructions:SetText(L.RECHERCHE) end
	recherche:HookScript("OnTextChanged", function(boite)
		self.texte = boite:GetText() or ""
		if f:IsShown() then self:Rafraichir() end
	end)
	self.recherche = recherche

	local filtre = CreateFrame("DropdownButton", nil, f, "WowStyle1FilterDropdownTemplate")
	filtre:SetSize(200, 22)
	filtre:SetPoint("LEFT", recherche, "RIGHT", 10, 0)
	filtre:SetText(L.FILTRES)
	if filtre.SetupMenu then
		filtre:SetupMenu(function(_, racine)
			local function option(texte, cle)
				racine:CreateCheckbox(texte,
					function() return self.filtres[cle] end,
					function()
						self.filtres[cle] = not self.filtres[cle]
						self:Rafraichir()
					end)
			end
			option(L.FILTRE_CRAFTABLE, "craftable")
			option(L.FILTRE_EN_LIGNE, "enLigne")
			option(L.FILTRE_INCONNUE, "inconnue")
		end)
	end
	self.filtre = filtre

	f.nbResultats = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.nbResultats:SetPoint("LEFT", filtre, "RIGHT", 12, 0)
end

function Fenetre:CreerMetiers(f)
	local cadre = creerCadre(f)
	cadre:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -64)
	cadre:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 30)
	cadre:SetWidth(LARGEUR_METIERS)

	local titre = cadre:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	titre:SetPoint("TOPLEFT", cadre, "TOPLEFT", 10, -8)
	titre:SetText(L.METIERS)

	local boite, barre = creerListe(cadre, 22, function(ligne, entree)
		if not ligne.initialise then
			ligne.initialise = true
			ligne.nom = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			ligne.nom:SetPoint("LEFT", 8, 0)
			ligne.nombre = ligne:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			ligne.nombre:SetPoint("RIGHT", -6, 0)
			ligne.survol = ligne:CreateTexture(nil, "HIGHLIGHT")
			ligne.survol:SetAllPoints()
			ligne.survol:SetColorTexture(1, 1, 1, 0.08)
			ligne.selection = ligne:CreateTexture(nil, "BACKGROUND")
			ligne.selection:SetAllPoints()
			ligne.selection:SetColorTexture(0.88, 0.7, 0.32, 0.22)
			ligne:SetScript("OnClick", function(bouton)
				self.metier = bouton.entree.id
				self:Rafraichir()
			end)
			function ligne:Actualiser()
				self.selection:SetShown(self.entree and self.entree.id == Fenetre.metier)
			end
		end
		ligne.entree = entree
		ligne.nom:SetText(entree.nom)
		ligne.nombre:SetText(tostring(entree.total))
		ligne:Actualiser()
	end)
	boite:SetPoint("TOPLEFT", cadre, "TOPLEFT", 4, -26)
	boite:SetPoint("BOTTOMRIGHT", cadre, "BOTTOMRIGHT", -22, 4)
	barre:SetPoint("TOPLEFT", boite, "TOPRIGHT", 4, 0)
	barre:SetPoint("BOTTOMLEFT", boite, "BOTTOMRIGHT", 4, 0)
	self.listeMetiers = boite
	self.cadreMetiers = cadre
end

function Fenetre:CreerRecettes(f)
	local cadre = creerCadre(f)
	cadre:SetPoint("TOPLEFT", self.cadreMetiers, "TOPRIGHT", 6, 0)
	cadre:SetPoint("BOTTOMRIGHT", self.cadreDetail, "BOTTOMLEFT", -6, 0)

	local boite, barre = creerListe(cadre, 38, function(ligne, spellID)
		if not ligne.initialise then
			ligne.initialise = true
			ligne.icone = ligne:CreateTexture(nil, "ARTWORK")
			ligne.icone:SetSize(30, 30)
			ligne.icone:SetPoint("LEFT", 6, 0)
			ligne.nom = ligne:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			ligne.nom:SetPoint("TOPLEFT", ligne.icone, "TOPRIGHT", 8, -2)
			ligne.nom:SetPoint("RIGHT", ligne, "RIGHT", -110, 0)
			ligne.nom:SetJustifyH("LEFT")
			ligne.detail = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			ligne.detail:SetPoint("BOTTOMLEFT", ligne.icone, "BOTTOMRIGHT", 8, 2)
			ligne.detail:SetJustifyH("LEFT")
			ligne.qui = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			ligne.qui:SetPoint("RIGHT", -8, 0)
			ligne.qui:SetJustifyH("RIGHT")
			ligne.survol = ligne:CreateTexture(nil, "HIGHLIGHT")
			ligne.survol:SetAllPoints()
			ligne.survol:SetColorTexture(1, 1, 1, 0.08)
			ligne.selection = ligne:CreateTexture(nil, "BACKGROUND")
			ligne.selection:SetAllPoints()
			ligne.selection:SetColorTexture(0.88, 0.7, 0.32, 0.22)
			ligne:SetScript("OnClick", function(bouton) Fenetre:Selectionner(bouton.spellID) end)
			ligne:SetScript("OnEnter", function(bouton)
				securise("infobulle de la recette", ns.infobulleRecette, bouton, bouton.spellID)
			end)
			ligne:SetScript("OnLeave", function()
				if GameTooltip then GameTooltip:Hide() end
			end)
			function ligne:Actualiser()
				self.selection:SetShown(self.spellID == Fenetre.selection)
			end
		end
		local recette = ns.Recettes.recettes[spellID]
		ligne.spellID = spellID
		ligne.icone:SetTexture(iconeRecette(spellID, recette))
		ligne.nom:SetText(recette.nom)
		ligne.nom:SetTextColor(couleurQualite(recette.qualite))
		local metier = ns.Recettes.metiers[recette.metier]
		ligne.detail:SetText(string.format("%s · %d", metier and metier.nom or "?", recette.niveau))

		local crafteurs = ns.catalogue:Crafteurs(spellID)
		local enLigne = 0
		for _, c in ipairs(crafteurs) do
			if ns.estEnLigne(c.cle) then enLigne = enLigne + 1 end
		end
		if #crafteurs == 0 then
			ligne.qui:SetText("|cffe8806a" .. L.PERSONNE .. "|r")
		elseif enLigne > 0 then
			ligne.qui:SetText(string.format("|cff5fd068%s|r", string.format(L.CRAFTEURS_EN_LIGNE, #crafteurs, enLigne)))
		else
			ligne.qui:SetText(string.format("|cffa89c86%s|r", string.format(L.CRAFTEURS, #crafteurs)))
		end
		ligne:Actualiser()
	end)
	boite:SetPoint("TOPLEFT", cadre, "TOPLEFT", 4, -4)
	boite:SetPoint("BOTTOMRIGHT", cadre, "BOTTOMRIGHT", -22, 4)
	barre:SetPoint("TOPLEFT", boite, "TOPRIGHT", 4, 0)
	barre:SetPoint("BOTTOMLEFT", boite, "BOTTOMRIGHT", 4, 0)

	cadre.vide = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	cadre.vide:SetPoint("CENTER")
	cadre.vide:SetText(L.AUCUN_RESULTAT)
	cadre.vide:Hide()

	self.listeRecettes = boite
	self.cadreRecettes = cadre
end

function Fenetre:CreerDetail(f)
	local cadre = creerCadre(f)
	cadre:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -64)
	cadre:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 30)
	cadre:SetWidth(LARGEUR_DETAIL)
	self.cadreDetail = cadre

	local d = {}
	self.detail = d

	d.icone = cadre:CreateTexture(nil, "ARTWORK")
	d.icone:SetSize(40, 40)
	d.icone:SetPoint("TOPLEFT", 12, -12)
	d.nom = cadre:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	d.nom:SetPoint("TOPLEFT", d.icone, "TOPRIGHT", 10, -2)
	d.nom:SetPoint("RIGHT", cadre, "RIGHT", -10, 0)
	d.nom:SetJustifyH("LEFT")
	d.sous = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	d.sous:SetPoint("TOPLEFT", d.nom, "BOTTOMLEFT", 0, -4)
	d.sous:SetJustifyH("LEFT")

	d.titreComposants = cadre:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	d.titreComposants:SetPoint("TOPLEFT", d.icone, "BOTTOMLEFT", 0, -16)
	d.titreComposants:SetText(L.COMPOSANTS)

	d.composants = {}
	for i = 1, MAX_LIGNES do
		local ligne = CreateFrame("Button", nil, cadre)
		ligne:SetHeight(22)
		ligne:SetPoint("TOPLEFT", d.titreComposants, "BOTTOMLEFT", 0, -4 - (i - 1) * 23)
		ligne:SetPoint("RIGHT", cadre, "RIGHT", -12, 0)
		ligne.icone = ligne:CreateTexture(nil, "ARTWORK")
		ligne.icone:SetSize(20, 20)
		ligne.icone:SetPoint("LEFT")
		ligne.nom = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		ligne.nom:SetPoint("LEFT", ligne.icone, "RIGHT", 6, 0)
		ligne.nom:SetPoint("RIGHT", ligne, "RIGHT", -60, 0)
		ligne.nom:SetJustifyH("LEFT")
		ligne.stock = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		ligne.stock:SetPoint("RIGHT")
		ligne:EnableMouse(true)
		ligne:SetScript("OnEnter", function(bouton)
			securise("infobulle du composant", ns.infobulleObjet, bouton, bouton.itemID, bouton.nomObjet,
				bouton.qualiteObjet, "ANCHOR_LEFT")
		end)
		ligne:SetScript("OnLeave", function()
			if GameTooltip then GameTooltip:Hide() end
		end)
		ligne:Hide()
		d.composants[i] = ligne
	end

	d.titreCrafteurs = cadre:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	d.titreCrafteurs:SetPoint("TOPLEFT", d.titreComposants, "BOTTOMLEFT", 0, -4 - MAX_LIGNES * 23 - 10)
	d.titreCrafteurs:SetText(L.PEUVENT_CRAFTER)

	d.crafteurs = {}
	for i = 1, MAX_LIGNES do
		local ligne = CreateFrame("Frame", nil, cadre)
		ligne:SetHeight(18)
		ligne:SetPoint("TOPLEFT", d.titreCrafteurs, "BOTTOMLEFT", 0, -4 - (i - 1) * 18)
		ligne:SetPoint("RIGHT", cadre, "RIGHT", -12, 0)
		ligne.point = ligne:CreateTexture(nil, "ARTWORK")
		ligne.point:SetSize(8, 8)
		ligne.point:SetPoint("LEFT", 2, 0)
		ligne.texte = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		ligne.texte:SetPoint("LEFT", ligne.point, "RIGHT", 6, 0)
		ligne.texte:SetPoint("RIGHT")
		ligne.texte:SetJustifyH("LEFT")
		ligne:Hide()
		d.crafteurs[i] = ligne
	end
	d.aucunCrafteur = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	d.aucunCrafteur:SetPoint("TOPLEFT", d.titreCrafteurs, "BOTTOMLEFT", 0, -4)
	d.aucunCrafteur:SetText(L.PERSONNE_CONNAIT)

	d.commander = CreateFrame("Button", nil, cadre, "UIPanelButtonTemplate")
	d.commander:SetSize(LARGEUR_DETAIL - 28, 26)
	d.commander:SetPoint("BOTTOM", cadre, "BOTTOM", 0, 12)
	d.commander:SetText(L.COMMANDER)
	d.commander:SetScript("OnClick", function()
		if self.selection then ns.Dialogue:Ouvrir(self.selection) end
	end)
	self.boutonCommander = d.commander
end

function Fenetre:CreerOnglets(f)
	self.onglets = {}
	local noms = { L.ONGLET_RECETTES, L.ONGLET_COMMANDES, L.ONGLET_MEMBRES }
	for i, nom in ipairs(noms) do
		local onglet = CreateFrame("Button", "CompagnonsFrameTab" .. i, f, "PanelTabButtonTemplate")
		onglet:SetID(i)
		onglet:SetText(nom)
		if i == 1 then
			onglet:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2)
		else
			onglet:SetPoint("LEFT", self.onglets[i - 1], "RIGHT", -4, 0)
		end
		if PanelTemplates_TabResize then securise("onglet", PanelTemplates_TabResize, onglet, 0) end
		onglet:SetScript("OnClick", function(bouton) self:ChoisirOnglet(bouton:GetID()) end)
		self.onglets[i] = onglet
	end

	self:ChoisirOnglet(1)
end

function Fenetre:ChoisirOnglet(numero)
	self.onglet = numero
	for i, onglet in ipairs(self.onglets) do
		if i == numero then
			if PanelTemplates_SelectTab then PanelTemplates_SelectTab(onglet) end
		else
			if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(onglet) end
		end
	end
	local recettes = numero == 1
	for _, region in ipairs({ self.cadreMetiers, self.cadreRecettes, self.cadreDetail, self.recherche, self.filtre }) do
		region:SetShown(recettes)
	end
	self.cadre.nbResultats:SetShown(recettes)
	if self.vueCommandes then self.vueCommandes:SetShown(numero == 2) end
	if self.vueMembres then self.vueMembres:SetShown(numero == 3) end
	if numero == 1 then
		self:Rafraichir()
	elseif numero == 2 then
		self:RafraichirCommandes()
	else
		self:RafraichirMembres()
	end
end

--- Libellé de l'onglet Commandes, avec le nombre de commandes que l'on peut remplir.
function Fenetre:ActualiserLibelleOnglets()
	local onglet = self.onglets and self.onglets[2]
	if not onglet or not ns.Atelier or not ns.catalogue then return end
	local n = ns.Atelier:CompterPourMoi()
	onglet:SetText(n > 0 and string.format("%s (%d)", L.ONGLET_COMMANDES, n) or L.ONGLET_COMMANDES)
	if PanelTemplates_TabResize then securise("onglet", PanelTemplates_TabResize, onglet, 0) end
end

function Fenetre:SurCommandes()
	if not self.cadre then return end
	self:ActualiserLibelleOnglets()
	if self.cadre:IsShown() and self.onglet == 2 then self:RafraichirCommandes() end
end

-- ---------------------------------------------------------------------------------------------
-- Contenu
-- ---------------------------------------------------------------------------------------------

function Fenetre:Options(sansMetier)
	return {
		texte = self.texte,
		metier = (not sansMetier) and self.metier or nil,
		craftable = self.filtres.craftable,
		enLigne = self.filtres.enLigne,
		inconnue = self.filtres.inconnue,
		estEnLigne = ns.estEnLigne,
	}
end

function Fenetre:Rafraichir()
	if not self.cadre or not self.cadre:IsShown() or self.onglet ~= 1 then return end
	local catalogue = ns.catalogue
	if not catalogue then return end

	-- Compteurs par métier, calculés avec tous les filtres sauf le métier.
	local compte, total = {}, 0
	local donnees = ns.Recettes
	for _, spellID in ipairs(catalogue:Chercher(self:Options(true))) do
		local m = donnees.recettes[spellID].metier
		compte[m] = (compte[m] or 0) + 1
		total = total + 1
	end
	local metiers = { { id = nil, nom = L.TOUS_METIERS, total = total } }
	for _, m in ipairs(catalogue:Metiers()) do
		if compte[m.id] then metiers[#metiers + 1] = { id = m.id, nom = m.nom, total = compte[m.id] } end
	end
	if self.metier and not compte[self.metier] then self.metier = nil end
	remplir(self.listeMetiers, metiers, true)
	rafraichirLignes(self.listeMetiers)

	local liste = catalogue:Chercher(self:Options())
	remplir(self.listeRecettes, liste, false)
	self.cadreRecettes.vide:SetShown(#liste == 0)
	self.cadre.nbResultats:SetText(string.format(L.RESULTATS, #liste))

	local present = false
	for _, spellID in ipairs(liste) do
		if spellID == self.selection then
			present = true
			break
		end
	end
	if not present then self.selection = liste[1] end
	rafraichirLignes(self.listeRecettes)
	self:ActualiserDetail()

	local nbPersos = 0
	for _ in pairs(ns.db.global.personnages) do nbPersos = nbPersos + 1 end
	self.cadre.pied:SetText(string.format(L.PIED, donnees.build or "?", nbPersos))
	self:ActualiserLibelleOnglets()
end

function Fenetre:Selectionner(spellID)
	self.selection = spellID
	rafraichirLignes(self.listeRecettes)
	self:ActualiserDetail()
end

function Fenetre:ActualiserDetail()
	local d = self.detail
	local spellID = self.selection
	local recette = spellID and ns.Recettes.recettes[spellID]
	if not recette then
		d.nom:SetText("")
		d.sous:SetText("")
		d.icone:SetTexture(nil)
		for i = 1, MAX_LIGNES do
			d.composants[i]:Hide()
			d.crafteurs[i]:Hide()
		end
		d.aucunCrafteur:Hide()
		return
	end

	d.icone:SetTexture(iconeRecette(spellID, recette))
	d.nom:SetText(recette.nom)
	d.nom:SetTextColor(couleurQualite(recette.qualite))
	local metier = ns.Recettes.metiers[recette.metier]
	d.sous:SetText(string.format(L.METIER_NIVEAU, metier and metier.nom or "?", recette.niveau))

	local composants = ns.catalogue:Composants(spellID)
	for i = 1, MAX_LIGNES do
		local ligne, comp = d.composants[i], composants[i]
		if comp then
			local nom = comp.nom
			if nom == "" and C_Item and C_Item.GetItemNameByID then nom = C_Item.GetItemNameByID(comp.itemID) or "" end
			if nom == "" then nom = "#" .. comp.itemID end
			ligne.itemID = comp.itemID
			ligne.nomObjet = nom
			ligne.qualiteObjet = comp.qualite
			ligne.icone:SetTexture(iconeObjet(comp.itemID) or ICONE_INCONNUE)
			ligne.nom:SetText(nom)
			ligne.nom:SetTextColor(couleurQualite(comp.qualite))
			local possede = nombreEnStock(comp.itemID)
			local couleur = possede >= comp.qte and "|cff5fd068" or (possede > 0 and "|cffe8a94f" or "|cffe8806a")
			ligne.stock:SetText(string.format("%s%d|r / %d", couleur, possede, comp.qte))
			ligne:Show()
		else
			ligne:Hide()
		end
	end

	local crafteurs = ns.catalogue:Crafteurs(spellID)
	for i = 1, MAX_LIGNES do
		local ligne, c = d.crafteurs[i], crafteurs[i]
		if c then
			local enLigne = ns.estEnLigne(c.cle)
			local r, g, b = couleurClasse(c.classe)
			if enLigne then ligne.point:SetColorTexture(0.37, 0.82, 0.41, 1) else ligne.point:SetColorTexture(0.5, 0.5, 0.5, 1) end
			ligne.texte:SetText(string.format("%s%s|r |cffa89c86· %s|r", hex(r, g, b), c.nom,
				enLigne and L.EN_LIGNE or L.HORS_LIGNE))
			ligne:Show()
		else
			ligne:Hide()
		end
	end
	d.aucunCrafteur:SetShown(#crafteurs == 0)
	d.titreCrafteurs:SetText(L.PEUVENT_CRAFTER)
end
