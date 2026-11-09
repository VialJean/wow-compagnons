-- Panneau accolé à la fenêtre de métier du jeu : qui, dans la guilde, connaît la recette sélectionnée,
-- et accès rapide au navigateur. Les commandes en attente s'y ajouteront avec le sprint commandes.
local _, ns = ...
local L = ns.L
local Compagnons = ns.addon

local Panneau = Compagnons:NewModule("PanneauMetier", "AceEvent-3.0")
ns.PanneauMetier = Panneau

local TS = C_TradeSkillUI
local MAX_CRAFTEURS = 5
local MAX_CARTES = 3
local DELAI_OUVERTURE = 0.4
local PERIODE_SUIVI = 0.4
local LARGEUR = 300
local MARGE = 12
local HAUTEUR_CARTE = 62
-- La fenêtre de métier du jeu a une colonne d'onglets (les autres métiers) qui dépasse de son bord droit :
-- on décale le panneau pour ne pas la recouvrir.
local DECALAGE_ONGLETS = 70

local function securise(etape, fn, ...)
	local ok, resultat = pcall(fn, ...)
	if not ok then
		ns.log("erreur", "ui", "%s : %s", etape, tostring(resultat))
		return nil
	end
	return resultat
end

function Panneau:OnEnable()
	self:RegisterEvent("TRADE_SKILL_SHOW", "SurOuverture")
	self:RegisterEvent("TRADE_SKILL_CLOSE", "SurFermeture")
	self:RegisterMessage("COMPAGNONS_CATALOGUE_MAJ", "Actualiser")
	self:RegisterMessage("COMPAGNONS_COMMANDES_MAJ", "Actualiser")
end

--- Fenêtre de métier du jeu : interface moderne (ProfessionsFrame) ou ancienne (TradeSkillFrame).
local function fenetreDeMetier()
	local f = _G.ProfessionsFrame or _G.TradeSkillFrame
	if f and f.IsShown and f:IsShown() then return f end
	return nil
end

--- Identifiant (skillLineID) du métier affiché, ou nil.
local function metierAffiche()
	if TS and TS.GetBaseProfessionInfo then
		local info = TS.GetBaseProfessionInfo()
		if info and info.professionID then return info.professionID, info.professionName end
	end
	return nil
end

--- Recette (spellID) sélectionnée dans la fenêtre de métier, ou nil.
local function recetteSelectionnee()
	local pf = _G.ProfessionsFrame
	local formulaire = pf and pf.CraftingPage and pf.CraftingPage.SchematicForm
	if formulaire and formulaire.GetRecipeInfo then
		local info = formulaire:GetRecipeInfo()
		if info and info.recipeID then return info.recipeID end
	end
	if TS and TS.GetSelectedRecipeID then return TS.GetSelectedRecipeID() end
	return nil
end

function Panneau:SurOuverture()
	C_Timer.After(DELAI_OUVERTURE, function()
		securise("panneau de métier", self.Attacher, self)
	end)
end

function Panneau:SurFermeture()
	if self.cadre then self.cadre:Hide() end
end

function Panneau:Creer()
	-- Même gabarit natif que l'atelier : cadre à titre, avec un encart pour le contenu.
	local f = CreateFrame("Frame", "CompagnonsPanneauMetier", UIParent, "ButtonFrameTemplate")
	f:SetWidth(LARGEUR)
	f:SetHeight(300) -- recalculé selon le contenu (Disposer)
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()

	securise("gabarit", function()
		if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(f) end
		if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(f) end
	end)
	-- Le fond par défaut de l'encart est remplacé par le nôtre, plus simple à disposer.
	if f.Inset then f.Inset:Hide() end

	local c = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
	c:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -34)
	c:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
	f.contenu = c
	local largeurTexte = LARGEUR - 20 - 2 * MARGE

	f.recette = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.recette:SetWidth(largeurTexte)
	f.recette:SetJustifyH("LEFT")

	f.sousTitre = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.sousTitre:SetText(L.PEUVENT_CRAFTER)

	f.lignes = {}
	for i = 1, MAX_CRAFTEURS do
		local ligne = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		ligne:SetWidth(largeurTexte)
		ligne:SetJustifyH("LEFT")
		f.lignes[i] = ligne
	end
	f.aucun = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.aucun:SetText(L.PERSONNE_CONNAIT)

	-- Commandes du métier : celles que l'on peut remplir, et celles que l'on a prises.
	f.titreCommandes = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.titreCommandes:SetText(L.PANNEAU_COMMANDES)
	f.aucuneCommande = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.aucuneCommande:SetWidth(largeurTexte)
	f.aucuneCommande:SetJustifyH("LEFT")
	f.aucuneCommande:SetText(L.PANNEAU_AUCUNE_COMMANDE)

	f.cartes = {}
	for i = 1, MAX_CARTES do
		local carte = CreateFrame("Frame", nil, c, "BackdropTemplate")
		carte:SetHeight(HAUTEUR_CARTE)
		carte:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		carte:SetBackdropColor(0.13, 0.11, 0.08, 0.95)
		carte:SetBackdropBorderColor(0.54, 0.45, 0.25, 1)
		carte.titre = carte:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		carte.titre:SetPoint("TOPLEFT", 8, -7)
		carte.titre:SetPoint("RIGHT", carte, "RIGHT", -8, 0)
		carte.titre:SetJustifyH("LEFT")
		carte.meta = carte:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		carte.meta:SetPoint("TOPLEFT", carte.titre, "BOTTOMLEFT", 0, -2)
		carte.meta:SetPoint("RIGHT", carte, "RIGHT", -8, 0)
		carte.meta:SetJustifyH("LEFT")
		carte.bouton = CreateFrame("Button", nil, carte, "UIPanelButtonTemplate")
		carte.bouton:SetSize(120, 20)
		carte.bouton:SetPoint("BOTTOMRIGHT", -6, 5)
		carte.bouton:SetScript("OnClick", function(b)
			if not (b.action and carte.commande) then return end
			local _, erreur = ns.Atelier:Agir(carte.commande, b.action)
			if erreur then Compagnons:Print(erreur) end
		end)
		carte:Hide()
		f.cartes[i] = carte
	end

	f.bilan = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.bilan:SetWidth(largeurTexte)
	f.bilan:SetJustifyH("LEFT")

	f.ouvrir = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
	f.ouvrir:SetSize(largeurTexte, 24)
	f.ouvrir:SetText(L.OUVRIR_ATELIER)
	f.ouvrir:SetScript("OnClick", function()
		local fenetre = ns.Fenetre
		if fenetre then
			fenetre.metier = self.metier
			fenetre.texte = ""
			if fenetre.recherche then fenetre.recherche:SetText("") end
			fenetre:Afficher()
			fenetre:Rafraichir()
		end
	end)

	f:SetScript("OnShow", function() self:DemarrerSuivi() end)
	f:SetScript("OnHide", function() self:ArreterSuivi() end)
	self.cadre = f
end

--- Dispose le contenu de haut en bas et ajuste la hauteur du cadre : pas de vide, pas de chevauchement.
function Panneau:Disposer()
	local f = self.cadre
	local c = f.contenu
	local y = MARGE

	local function placer(element, decalage)
		element:ClearAllPoints()
		element:SetPoint("TOPLEFT", c, "TOPLEFT", MARGE, -y)
		y = y + (decalage or 0)
	end

	placer(f.recette, f.recette:GetStringHeight() + 12)

	if f.sousTitre:IsShown() then
		placer(f.sousTitre, 14)
		for i = 1, MAX_CRAFTEURS do
			if f.lignes[i]:IsShown() then placer(f.lignes[i], 17) end
		end
		if f.aucun:IsShown() then placer(f.aucun, 16) end
		y = y + 8
	end

	placer(f.titreCommandes, 16)
	local nbCartes = 0
	for i = 1, MAX_CARTES do
		local carte = f.cartes[i]
		if carte:IsShown() then
			nbCartes = nbCartes + 1
			carte:ClearAllPoints()
			carte:SetPoint("TOPLEFT", c, "TOPLEFT", MARGE, -y)
			carte:SetPoint("TOPRIGHT", c, "TOPRIGHT", -MARGE, -y)
			y = y + HAUTEUR_CARTE + 4
		end
	end
	if nbCartes == 0 then placer(f.aucuneCommande, f.aucuneCommande:GetStringHeight() + 4) end
	y = y + 10

	if f.bilan:GetText() and f.bilan:GetText() ~= "" then placer(f.bilan, f.bilan:GetStringHeight() + 10) end
	placer(f.ouvrir, 24 + MARGE)

	f:SetHeight(y + 34 + 10) -- barre de titre en haut, marge en bas
end

function Panneau:Attacher()
	local parent = fenetreDeMetier()
	if not parent then
		ns.log("info", "ui", "panneau de métier : fenêtre de métier introuvable ou fermée")
		return
	end
	if not self.cadre then self:Creer() end
	local f = self.cadre
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", parent, "TOPRIGHT", DECALAGE_ONGLETS, 0)
	if not self.parentSurveille then
		self.parentSurveille = true
		parent:HookScript("OnHide", function() f:Hide() end)
	end
	f:Show()
	self:Actualiser()
end

function Panneau:DemarrerSuivi()
	if self.suivi then return end
	self.suivi = C_Timer.NewTicker(PERIODE_SUIVI, function()
		local recette = securise("suivi de la recette", recetteSelectionnee)
		if recette ~= self.derniere then self:Actualiser() end
	end)
end

function Panneau:ArreterSuivi()
	if self.suivi then
		self.suivi:Cancel()
		self.suivi = nil
	end
end

--- Cartes de commandes du métier affiché (jusqu'à trois), avec l'action principale sur chaque carte.
function Panneau:ActualiserCommandes(idMetier)
	local f = self.cadre
	local liste = idMetier and ns.Atelier:PourMetier(idMetier) or {}
	local miens = ns.Atelier:Miens()
	for i = 1, MAX_CARTES do
		local carte, o = f.cartes[i], liste[i]
		if o then
			local recette = ns.Recettes.recettes[o.spell]
			carte.commande = o
			carte.titre:SetText(string.format("%d × %s", o.qte, recette and recette.nom or "?"))
			local libelle, couleur = ns.Atelier.LibelleStatut(o)
			local qui = miens[o.client] and L.PAR_CLIENT or o.client
			carte.meta:SetText(string.format("%s · |c%s%s|r", qui, couleur, libelle))

			-- Action principale disponible, sinon pas de bouton.
			local principale
			for _, a in ipairs(ns.Atelier:ActionsPossibles(o)) do
				if a.principale then principale = a break end
			end
			if principale then
				carte.bouton.action = principale.action
				carte.bouton:SetText(principale.libelle)
				carte.bouton:SetEnabled(principale.raison == nil)
				carte.bouton:Show()
			else
				carte.bouton.action = nil
				carte.bouton:Hide()
			end
			carte:Show()
		else
			carte.commande = nil
			carte:Hide()
		end
	end
	f.aucuneCommande:SetShown(#liste == 0)
	f.titreCommandes:SetText(string.format(L.PANNEAU_COMMANDES, #liste))
end

function Panneau:Actualiser()
	local f = self.cadre
	if not f or not f:IsShown() or not ns.catalogue then return end

	local idMetier, nomMetier = metierAffiche()
	self.metier = idMetier
	local metier = idMetier and ns.Recettes.metiers[idMetier]
	local titre = string.format(L.PANNEAU_TITRE, (metier and metier.nom) or nomMetier or "?")
	if f.SetTitle then f:SetTitle(titre) elseif f.TitleText then f.TitleText:SetText(titre) end

	local spellID = securise("recette sélectionnée", recetteSelectionnee)
	self.derniere = spellID
	local recette = spellID and ns.Recettes.recettes[spellID]

	if not recette then
		f.recette:SetText(spellID and L.RECETTE_INCONNUE_BASE or L.SELECTIONNE_RECETTE)
		f.sousTitre:Hide()
		f.aucun:Hide()
		for i = 1, MAX_CRAFTEURS do f.lignes[i]:Hide() end
	else
		f.recette:SetText(recette.nom)
		f.sousTitre:Show()
		local crafteurs = ns.catalogue:Crafteurs(spellID)
		for i = 1, MAX_CRAFTEURS do
			local c = crafteurs[i]
			local ligne = f.lignes[i]
			if c then
				local classe = c.classe and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.classe]
				local couleur = classe and ns.hex(classe.r, classe.g, classe.b) or "|cffcccccc"
				local etat = ns.estEnLigne(c.cle) and L.EN_LIGNE or L.HORS_LIGNE
				ligne:SetText(string.format("%s%s|r |cffa89c86· %s|r", couleur, c.nom, etat))
				ligne:Show()
			else
				ligne:Hide()
			end
		end
		if #crafteurs > MAX_CRAFTEURS then
			f.lignes[MAX_CRAFTEURS]:SetText(string.format(L.ET_AUTRES, #crafteurs - MAX_CRAFTEURS + 1))
		end
		f.aucun:SetShown(#crafteurs == 0)
	end

	self:ActualiserCommandes(idMetier)

	if idMetier then
		local total, connues = 0, 0
		for id, r in pairs(ns.Recettes.recettes) do
			if r.metier == idMetier then
				total = total + 1
				if #ns.catalogue:Crafteurs(id) > 0 then connues = connues + 1 end
			end
		end
		f.bilan:SetText(string.format(L.BILAN, connues, total))
	else
		f.bilan:SetText("")
	end

	self:Disposer()
end
