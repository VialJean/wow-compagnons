-- Assistance à l'envoi (phase 5 de docs/livraison.md) : à côté de la fenêtre d'échange ou de courrier, un bouton pose
-- dans la fenêtre, un emplacement par clic, ce que je dois remettre pour mes commandes (composants au crafteur, objet
-- fabriqué au client). Le joueur vérifie puis valide lui-même : l'addon n'accepte jamais l'échange et n'envoie jamais le courrier.
local _, ns = ...
local L = ns.L
local Compagnons = ns.addon

local Assistance = Compagnons:NewModule("AssistanceUI", "AceEvent-3.0")
ns.AssistanceUI = Assistance

local EMPLACEMENTS_ECHANGE = 6
local EMPLACEMENTS_COURRIER = 12

local function securise(etape, fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then
		ns.log("erreur", "ui", "%s : %s", etape, tostring(a))
		return nil
	end
	return a, b
end

local function nomObjet(id)
	local objet = ns.Recettes.objets[id]
	return objet and objet.nom or ("#" .. id)
end

-- ---------------------------------------------------------------------------------------------
-- Lecture du jeu
-- ---------------------------------------------------------------------------------------------

--- Contenu de mes sacs : liste de { bag, slot, itemID, count }.
local function lireSacs()
	local sacs = {}
	local C = _G.C_Container
	-- Sacs 0 à 4, plus le sac de composants (emplacement 5, vérifié sur Forever) : un emplacement absent renvoie 0 case.
	local nombreSacs = math.max(_G.NUM_BAG_SLOTS or 4, _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS or 0, 5)
	for bag = 0, nombreSacs do
		local n = (C and C.GetContainerNumSlots and C.GetContainerNumSlots(bag))
			or (_G.GetContainerNumSlots and _G.GetContainerNumSlots(bag)) or 0
		for slot = 1, n do
			local id, count
			if C and C.GetContainerItemInfo then
				local info = C.GetContainerItemInfo(bag, slot)
				if info and not info.isLocked then id, count = info.itemID, info.stackCount end
			elseif _G.GetContainerItemInfo then
				local _, nombre, verrou, _, _, _, lien = _G.GetContainerItemInfo(bag, slot)
				if lien and not verrou then id, count = tonumber(lien:match("item:(%d+)")), nombre end
			end
			if id and count then sacs[#sacs + 1] = { bag = bag, slot = slot, itemID = id, count = count } end
		end
	end
	return sacs
end

--- Première case libre des sacs ordinaires (hors sac de composants), ou nil.
local function caseLibre()
	local C = _G.C_Container
	for bag = 0, _G.NUM_BAG_SLOTS or 4 do
		local n = (C and C.GetContainerNumSlots and C.GetContainerNumSlots(bag))
			or (_G.GetContainerNumSlots and _G.GetContainerNumSlots(bag)) or 0
		for slot = 1, n do
			local pris
			if C and C.GetContainerItemInfo then pris = C.GetContainerItemInfo(bag, slot) ~= nil
			elseif _G.GetContainerItemInfo then pris = _G.GetContainerItemInfo(bag, slot) ~= nil end
			if not pris then return bag, slot end
		end
	end
end

--- Ce qui est déjà posé dans la fenêtre d'échange : { [itemID] = quantité } et premier emplacement libre.
local function lireEchange()
	local places, libre = {}, nil
	for i = 1, EMPLACEMENTS_ECHANGE do
		local lien = GetTradePlayerItemLink(i)
		local id = lien and tonumber(lien:match("item:(%d+)"))
		if id then
			local _, _, nombre = GetTradePlayerItemInfo(i)
			places[id] = (places[id] or 0) + (tonumber(nombre) or 1)
		elseif not libre then
			libre = i
		end
	end
	return places, libre
end

local function lireCourrier()
	local places, libre = {}, nil
	for i = 1, EMPLACEMENTS_COURRIER do
		local nom, itemID, _, nombre = GetSendMailItem(i)
		if nom and tonumber(itemID) then
			places[itemID] = (places[itemID] or 0) + (tonumber(nombre) or 1)
		elseif not libre then
			libre = i
		end
	end
	return places, libre
end

local function destinataireCourrier()
	local champ = _G.SendMailNameEditBox
	local texte = champ and champ.GetText and champ:GetText()
	if texte and texte ~= "" then return texte end
end

-- ---------------------------------------------------------------------------------------------
-- Cadre
-- ---------------------------------------------------------------------------------------------

function Assistance:OnEnable()
	self.contexte = nil
	self:RegisterEvent("TRADE_SHOW", "SurEchange")
	self:RegisterEvent("TRADE_CLOSED", "Fermer")
	self:RegisterEvent("TRADE_PLAYER_ITEM_CHANGED", "Actualiser")
	self:RegisterEvent("MAIL_SHOW", "SurCourrier")
	self:RegisterEvent("MAIL_CLOSED", "Fermer")
	self:RegisterEvent("MAIL_SEND_INFO_UPDATE", "Actualiser")
	self:RegisterEvent("MAIL_SEND_SUCCESS", "Actualiser")
	self:RegisterEvent("BAG_UPDATE_DELAYED", "Actualiser")
	self:RegisterMessage("COMPAGNONS_COMMANDES_MAJ", "Actualiser")
end

function Assistance:Actif()
	return ns.db.profile.livraison.aide
end

function Assistance:Creer()
	local f = CreateFrame("Frame", "CompagnonsAssistance", UIParent, "InsetFrameTemplate")
	self.cadre = f
	f:SetSize(240, 84)
	f:SetFrameStrata("HIGH")
	f:Hide()

	f.titre = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.titre:SetPoint("TOPLEFT", 10, -8)
	f.titre:SetPoint("RIGHT", -10, 0)
	f.titre:SetJustifyH("LEFT")

	f.etat = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.etat:SetPoint("TOPLEFT", f.titre, "BOTTOMLEFT", 0, -4)
	f.etat:SetPoint("RIGHT", -10, 0)
	f.etat:SetJustifyH("LEFT")

	f.bouton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.bouton:SetSize(220, 24)
	f.bouton:SetPoint("BOTTOM", 0, 8)
	f.bouton:SetScript("OnClick", function() Assistance:Placer() end)
	return true -- `securise` en fait un succès ; sans cela, la première ouverture après un rechargement n'affichait rien
end

function Assistance:Afficher(contexte, ancre)
	ns.log("info", "ui", "assistance : %s ouvert (option %s)", contexte, self:Actif() and "active" or "coupée")
	if not self:Actif() then return end
	if not self.cadre then
		if not securise("création de l'assistance", self.Creer, self) then return end
	end
	self.contexte = contexte
	self.ancre = ancre
	-- Filet de sécurité : MAIL_CLOSED / TRADE_CLOSED ne suffisent pas toujours (fenêtre masquée autrement).
	self.ancresSurveillees = self.ancresSurveillees or {}
	if not self.ancresSurveillees[ancre] and ancre.HookScript then
		self.ancresSurveillees[ancre] = true
		ancre:HookScript("OnHide", function() Assistance:Fermer() end)
	end
	self.cadre:ClearAllPoints()
	self.cadre:SetPoint("TOPLEFT", ancre, "TOPRIGHT", 4, 0)
	self.cadre:Show()
	self:Actualiser(true)
	-- La fenêtre du jeu peut n'être affichée qu'un instant après son événement : on recalcule juste après.
	C_Timer.After(0.3, function() self:Actualiser() end)
end

function Assistance:SurEchange()
	if _G.TradeFrame then self:Afficher("echange", _G.TradeFrame) end
end

function Assistance:SurCourrier()
	if _G.MailFrame then self:Afficher("courrier", _G.MailFrame) end
end

function Assistance:Fermer()
	self.contexte, self.plan = nil, nil
	if self.cadre then self.cadre:Hide() end
end

-- ---------------------------------------------------------------------------------------------
-- Calcul de l'étape suivante
-- ---------------------------------------------------------------------------------------------

--- Détermine le partenaire, ce qui reste à poser et le prochain emplacement. Met à jour le cadre.
function Assistance:Actualiser(tolerant)
	local f = self.cadre
	if not f or not self.contexte then return end -- aucune fenêtre d'échange ou de courrier ouverte : rien à faire
	if not f:IsShown() then
		ns.log("info", "ui", "assistance : actualisation ignorée (cadre caché, contexte %s)", tostring(self.contexte))
		return
	end
	if self.ancre and self.ancre.IsShown and not self.ancre:IsShown() then
		ns.log("info", "ui", "assistance : la fenêtre d'ancrage n'est pas (encore) affichée%s", tolerant == true and "" or ", fermeture")
		if tolerant == true then return end -- à l'ouverture : la fenêtre du jeu peut s'afficher un instant plus tard
		return self:Fermer()
	end
	securise("actualisation de l'assistance", function()
		local moi = ns.clePersonnage()
		local commandes = ns.db.global.commandes
		local partenaire, places, libre
		if self.contexte == "echange" then
			partenaire = UnitName and UnitName("NPC")
			places, libre = lireEchange()
		else
			partenaire = destinataireCourrier() or ns.Assistance.partenaires(commandes, ns.Recettes, moi)[1]
			places, libre = lireCourrier()
		end

		local requis, ids = {}, {}
		if partenaire then requis, ids = ns.Assistance.requis(commandes, ns.Recettes, moi, partenaire) end
		-- Journal : pourquoi l'assistance s'affiche ou non (« /cpg debug » puis « /cpg journal »).
		local commeCrafteur, commeClient, sansRecette = 0, 0, 0
		for _, o in pairs(commandes) do
			if o.assigne == moi then commeCrafteur = commeCrafteur + 1 end
			if o.client == moi then commeClient = commeClient + 1 end
			if (o.assigne == moi or o.client == moi) and not (ns.Recettes.recettes[o.spell] and ns.Recettes.recettes[o.spell].objet) then
				sansRecette = sansRecette + 1
			end
		end
		ns.log("info", "ui", "assistance : moi=%s, partenaire=%s, %d commande(s) concernée(s) ; en base : %d crafteur, %d client, %d sans objet connu",
			tostring(moi), tostring(partenaire), #ids, commeCrafteur, commeClient, sansRecette)
		if #ids == 0 then
			f:Hide()
			self.plan = nil
			return
		end
		f:Show()

		local reste = ns.Assistance.restant(requis, places)
		local maxEmpl = self.contexte == "echange" and EMPLACEMENTS_ECHANGE or EMPLACEMENTS_COURRIER
		local sacs = lireSacs()
		local plan, manque = ns.Assistance.placements(reste, sacs, libre and (maxEmpl - (libre - 1)) or 0)
		self.plan = { partenaire = partenaire, suivant = plan[1], libre = libre }

		f.titre:SetText(string.format(L.ASSIST_TITRE, partenaire, #ids))
		-- Où se trouve le manque : la banque de ce personnage, ou un autre de mes personnages.
		local enSacs = {}
		for _, s in ipairs(sacs) do enSacs[s.itemID] = (enSacs[s.itemID] or 0) + s.count end
		local ailleurs = ns.Stocks and ns.Assistance.ou(manque, function(id) return ns.Stocks:Detail(id) end, moi, enSacs) or {}
		local absents = {}
		for id in pairs(manque) do absents[#absents + 1] = id end
		table.sort(absents)
		local texteManque
		for _, id in ipairs(absents) do
			local texte = manque[id] .. " × " .. nomObjet(id)
			local o = ailleurs[id]
			if o then
				local ou = {}
				if o.banque > 0 then ou[#ou + 1] = string.format(L.ASSIST_OU_BANQUE, o.banque) end
				for _, a in ipairs(o.autres) do ou[#ou + 1] = string.format(L.ASSIST_OU_PERSO, a.n, a.cle) end
				texte = texte .. " (" .. table.concat(ou, ", ") .. ")"
			end
			texteManque = (texteManque and (texteManque .. ", ") or "") .. texte
		end
		if not next(reste) then
			f.etat:SetText(L.ASSIST_FINI)
		elseif texteManque then
			f.etat:SetText(string.format(L.ASSIST_MANQUE, texteManque))
		else
			f.etat:SetText(L.ASSIST_ENCORE)
		end

		local suivant = plan[1]
		if suivant then
			f.bouton:SetText(string.format(L.ASSIST_PLACER, suivant.n, nomObjet(suivant.itemID)))
			f.bouton:Enable()
		else
			f.bouton:SetText(L.ASSIST_RIEN)
			f.bouton:Disable()
		end
	end)
end

-- ---------------------------------------------------------------------------------------------
-- Pose d'un objet : un clic, un emplacement
-- ---------------------------------------------------------------------------------------------

function Assistance:Placer()
	local plan = self.plan
	if not plan or not plan.suivant or not plan.libre then return end
	if InCombatLockdown and InCombatLockdown() then return end
	local p = plan.suivant

	local ok, erreur = pcall(function()
		local C = _G.C_Container
		local prendre = C and C.PickupContainerItem or _G.PickupContainerItem
		local fractionner = C and C.SplitContainerItem or _G.SplitContainerItem
		-- Journal : ce qu'on demande et ce qui est vraiment dans le tas (pour comprendre une quantité inattendue).
		local C2 = _G.C_Container
		local info = C2 and C2.GetContainerItemInfo and C2.GetContainerItemInfo(p.bag, p.slot)
		ns.log("info", "ui", "assistance : pose de %d × #%d (sac %d, case %d, tas de %s, %s)", p.n, p.itemID, p.bag, p.slot,
			info and tostring(info.stackCount) or "?", p.partiel and "fractionné" or "tas entier")
		if p.partiel then
			-- Forever ignore le fractionnement quand on attache au courrier (tout le tas part) : on sépare d'abord le tas
			-- dans une case libre des sacs ; le clic suivant pose ce tas entier.
			local bagLibre, caseL = caseLibre()
			if not bagLibre then
				Compagnons:Print(L.ASSIST_PAS_DE_PLACE)
				return
			end
			fractionner(p.bag, p.slot, p.n)
			prendre(bagLibre, caseL)
			ns.log("info", "ui", "assistance : tas séparé vers le sac %d, case %d", bagLibre, caseL)
			return
		end
		prendre(p.bag, p.slot)
		local curseur = _G.GetCursorInfo and { _G.GetCursorInfo() }
		ns.log("info", "ui", "assistance : curseur après %s : %s", p.partiel and "fractionnement" or "prise",
			curseur and curseur[1] and (tostring(curseur[1]) .. " " .. tostring(curseur[2])) or "vide")
		if self.contexte == "echange" then
			_G.ClickTradeButton(plan.libre)
		else
			-- Destinataire (et objet du courrier s'il est vide) pré-remplis pour la première pièce jointe.
			local champ = _G.SendMailNameEditBox
			if champ and champ:GetText() == "" then champ:SetText(plan.partenaire) end
			local sujet = _G.SendMailSubjectEditBox
			if sujet and sujet:GetText() == "" then sujet:SetText("Compagnons") end
			_G.ClickSendMailItemButton(plan.libre)
		end
	end)
	if not ok then
		ns.log("erreur", "ui", "pose d'un objet : %s", tostring(erreur))
		if _G.ClearCursor then _G.ClearCursor() end
	end
	self:Actualiser()
	-- Ce qui est réellement posé une fois l'objet arrivé dans la fenêtre.
	C_Timer.After(0.5, function()
		local places = (self.contexte == "echange" and lireEchange or lireCourrier)()
		ns.log("info", "ui", "assistance : posé %s dans la fenêtre (demandé %d)", tostring(places[p.itemID] or 0), p.n)
	end)
end
