-- Branche le texte des infobulles (Core/Infobulles.lua) sur celles du jeu, et gère la commande rapide
-- Ctrl+Maj+clic sur un objet. Voir docs/infobulles.md.
local _, ns = ...
local L = ns.L
local Compagnons = ns.addon

local Module = Compagnons:NewModule("InfobullesObjet", "AceEvent-3.0")
ns.InfobullesObjet = Module

local DELAI_DOUBLON = 0.3 -- un même clic peut passer par deux fonctions du jeu

local function securise(etape, fn, ...)
	local ok, resultat = pcall(fn, ...)
	if not ok then
		ns.log("erreur", "ui", "%s : %s", etape, tostring(resultat))
		return nil
	end
	return resultat
end

--- Quantité possédée sur tous mes personnages (le personnage connecté est lu en direct).
local function stock(itemID)
	if ns.Stocks then return ns.Stocks:Total(itemID) end
	if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(itemID, true) or 0 end
	if GetItemCount then return GetItemCount(itemID, true) or 0 end
	return 0
end

local function couleurClasse(classe)
	local c = classe and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classe]
	if c then return c.r, c.g, c.b end
	return 0.8, 0.8, 0.8
end

--- Classe, sous-classe, qualité et niveau d'objet effectif d'un objet, ou nil si le jeu ne les a pas encore en cache.
-- `lien` (lien de l'infobulle) donne le niveau effectif, qui tient compte des améliorations.
local function informationsObjet(itemID, lien)
	local lire = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
	if not lire then return nil end
	-- 1 nom, 2 lien, 3 qualité, 4 niveau d'objet, 5 niveau requis, 6 type, 7 sous-type, 8 pile, 9 emplacement,
	-- 10 icône, 11 prix, 12 classe, 13 sous-classe
	local nom, lienObjet, qualite, niveau, _, _, _, _, _, _, _, classe, sous = lire(lien or itemID)
	if not nom or not classe then return nil end
	local effectif = C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(lien or lienObjet)
	if type(effectif) == "number" and effectif > 0 then niveau = effectif end
	return { classe = classe, sous = sous, qualite = qualite, niveau = niveau }
end

--- Données fournies au texte des infobulles. `lien` : lien de l'objet survolé, s'il est connu.
function Module:Contexte(lien)
	return {
		infoObjet = function(itemID) return informationsObjet(itemID, lien) end,
		catalogue = ns.catalogue,
		commandes = ns.db.global.commandes,
		miens = ns.Atelier:Miens(),
		connait = function(spellID) return ns.Atelier:Connait(spellID) end,
		stock = stock,
		enLigne = ns.estEnLigne,
		maj = IsShiftKeyDown(),
		options = ns.db.profile.infobulles,
		couleurClasse = couleurClasse,
		couleurQualite = function(qualite)
			local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[qualite or 1]
			if c then return c.r, c.g, c.b end
			return 1, 1, 1
		end,
	}
end

function Module:OnEnable()
	local donnees = _G.Enum and _G.Enum.TooltipDataType
	if _G.TooltipDataProcessor and _G.TooltipDataProcessor.AddTooltipPostCall and donnees and donnees.Item then
		_G.TooltipDataProcessor.AddTooltipPostCall(donnees.Item, function(infobulle, data)
			securise("infobulle d'objet", self.Ajouter, self, infobulle, data)
		end)
	else
		ns.log("warn", "ui", "TooltipDataProcessor indisponible : infobulles d'objet désactivées")
	end

	-- Une infobulle réutilisée d'un objet à l'autre : on oublie le marquage quand elle est vidée.
	for _, infobulle in ipairs({ GameTooltip, _G.ItemRefTooltip }) do
		if infobulle and infobulle.HookScript then
			infobulle:HookScript("OnTooltipCleared", function(t) t.cpgAjoute = nil end)
		end
	end

	self:RegisterEvent("MODIFIER_STATE_CHANGED", "SurModificateur")

	-- Commande rapide : après les actions du jeu.
	if _G.hooksecurefunc then
		if _G.HandleModifiedItemClick then
			hooksecurefunc("HandleModifiedItemClick", function(lien)
				securise("commande rapide", self.SurClic, self, lien)
			end)
		end
		if _G.SetItemRef then
			hooksecurefunc("SetItemRef", function(lien)
				securise("commande rapide (chat)", self.SurClic, self, lien)
			end)
		end
	end
end

--- Ajoute le bloc Compagnons à une infobulle d'objet du jeu.
function Module:Ajouter(infobulle, data)
	if infobulle ~= GameTooltip and infobulle ~= _G.ItemRefTooltip then return end -- pas les comparaisons
	local itemID = data and data.id
	if not itemID or not ns.catalogue or not ns.Atelier then return end
	if infobulle.cpgAjoute == itemID then return end -- jamais en double

	local lignes = ns.Infobulles.lignes(self:Contexte(data.hyperlink), itemID)
	if not lignes then return end
	infobulle.cpgAjoute = itemID
	infobulle:AddLine(" ")
	for _, l in ipairs(lignes) do infobulle:AddLine(l.texte, l.r, l.g, l.b) end
end

--- Maj enfoncé ou relâché : l'infobulle d'un composant change (liste de crafteurs ou détail des recettes).
function Module:SurModificateur()
	if GameTooltip and GameTooltip:IsShown() and GameTooltip.cpgAjoute and GameTooltip.RefreshData then
		securise("rafraîchissement de l'infobulle", GameTooltip.RefreshData, GameTooltip)
	end
end

-- ---------------------------------------------------------------------------------------------
-- Commande rapide
-- ---------------------------------------------------------------------------------------------

local function toucheActive(reglage)
	local maj, ctrl = IsShiftKeyDown(), IsControlKeyDown()
	if reglage == "ctrlmaj" then return maj and ctrl end
	if reglage == "maj" then return maj and not ctrl end
	return false
end

--- La recette à commander pour un objet : celle dont le plus de crafteurs sont en ligne, puis la moins élevée.
function Module:MeilleureRecette(itemID)
	local meilleure, score, niveau
	for _, spellID in ipairs(ns.catalogue:RecettesCreant(itemID)) do
		local enLigne = 0
		for _, c in ipairs(ns.catalogue:Crafteurs(spellID)) do
			if ns.estEnLigne(c.cle) then enLigne = enLigne + 1 end
		end
		local n = ns.Recettes.recettes[spellID].niveau
		if not meilleure or enLigne > score or (enLigne == score and n < niveau) then
			meilleure, score, niveau = spellID, enLigne, n
		end
	end
	return meilleure
end

function Module:SurClic(lien)
	if type(lien) ~= "string" or not ns.catalogue then return end
	if not toucheActive(ns.db.profile.infobulles.commander) then return end
	if InCombatLockdown() then return end
	local itemID = tonumber(lien:match("item:(%d+)"))
	if not itemID then return end

	local maintenant = GetTime()
	if self.dernierClic and self.dernierClic.id == itemID and maintenant - self.dernierClic.t < DELAI_DOUBLON then return end
	self.dernierClic = { id = itemID, t = maintenant }

	local recette = self:MeilleureRecette(itemID)
	if not recette then
		Compagnons:Print(L.INFO_AUCUNE_RECETTE)
		return
	end
	ns.Dialogue:Ouvrir(recette)
end

-- ---------------------------------------------------------------------------------------------
-- /cpg infobulles
-- ---------------------------------------------------------------------------------------------

local function etat(v) return v and L.INFO_ACTIVE or L.INFO_DESACTIVE end

--- /cpg infobulles [objet|composant|personne|commander <ctrlmaj|maj|aucune>]
function Module:Commande(option, valeur)
	local reglages = ns.db.profile.infobulles
	option = ns.Alias.option(option) -- anglais ou français
	if option == "objet" or option == "composant" or option == "personne" or option == "desenchantement" then
		reglages[option] = not reglages[option]
	elseif option == "enchanteur" then
		reglages.aucunEnchanteur = not reglages.aucunEnchanteur
	elseif option == "commander" then
		valeur = ns.Alias.valeur(valeur)
		if valeur == "ctrlmaj" or valeur == "maj" or valeur == "aucune" then reglages.commander = valeur end
	end
	Compagnons:Print(string.format(L.INFO_ETAT, etat(reglages.objet), etat(reglages.composant),
		etat(reglages.personne), etat(reglages.desenchantement), etat(reglages.aucunEnchanteur), reglages.commander))
end
